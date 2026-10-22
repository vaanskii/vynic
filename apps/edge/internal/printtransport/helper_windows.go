//go:build windows

package printtransport

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// PROC_THREAD_ATTRIBUTE_JOB_LIST is the documented Windows 10 creation
// attribute: ProcThreadAttributeValue(13, false, true, false). It assigns the
// job during CreateProcess, avoiding an orphan suspended process if the parent
// dies between process creation and a later AssignProcessToJobObject call.
const procThreadAttributeJobList = 0x0002000d

func nativeSupported() bool { return true }

func pinnedExecutable(config HelperConfig) (*os.File, string, error) {
	if err := config.validate(); err != nil {
		return nil, "", err
	}
	path, err := windows.UTF16PtrFromString(config.Path)
	if err != nil {
		return nil, "", err
	}
	handle, err := windows.CreateFile(path, windows.GENERIC_READ, windows.FILE_SHARE_READ, nil, windows.OPEN_EXISTING, windows.FILE_FLAG_OPEN_REPARSE_POINT, 0)
	if err != nil {
		return nil, "", err
	}
	file := os.NewFile(uintptr(handle), config.Path)
	fail := func(err error) (*os.File, string, error) { return nil, "", errors.Join(err, file.Close()) }
	var info windows.ByHandleFileInformation
	if err = windows.GetFileInformationByHandle(handle, &info); err != nil {
		return fail(err)
	}
	if info.FileAttributes&(windows.FILE_ATTRIBUTE_REPARSE_POINT|windows.FILE_ATTRIBUTE_DIRECTORY) != 0 {
		return fail(errors.New("helper must be a regular non-reparse executable"))
	}
	stat, err := file.Stat()
	if err != nil {
		return fail(err)
	}
	if stat.Size() < 1 || stat.Size() > 64*1024*1024 {
		return fail(errors.New("helper binary exceeds size bounds"))
	}
	hash := sha256.New()
	if _, err = io.Copy(hash, file); err != nil {
		return fail(err)
	}
	if fmt.Sprintf("%x", hash.Sum(nil)) != config.SHA256 {
		return fail(errors.New("helper binary hash does not match its pin"))
	}
	buffer := make([]uint16, 32768)
	count, err := windows.GetFinalPathNameByHandle(handle, &buffer[0], uint32(len(buffer)), 0)
	if err != nil || count == 0 || count >= uint32(len(buffer)) {
		if err == nil {
			err = errors.New("helper canonical path exceeds bounds")
		}
		return fail(err)
	}
	canonical := windows.UTF16ToString(buffer[:count])
	return file, canonical, nil
}

type windowsHelperProcess struct {
	mu             sync.Mutex
	process        windows.Handle
	job            windows.Handle
	input          *os.File
	output         *os.File
	pin            *os.File
	stderr         *os.File
	diagnosticMu   sync.Mutex
	diagnostic     []byte
	diagnosticDone chan struct{}
}

type jobListSetter func(*windows.ProcThreadAttributeListContainer, []windows.Handle) error

func launchHelper(config HelperConfig) (helperProcess, error) {
	return launchHelperWithJobList(config, func(attributes *windows.ProcThreadAttributeListContainer, jobs []windows.Handle) error {
		return attributes.Update(procThreadAttributeJobList, unsafe.Pointer(&jobs[0]), unsafe.Sizeof(jobs[0]))
	})
}

// The narrow attribute seam lets nonphysical tests exercise an unsupported
// JOB_LIST failure. The production path has no uncontained-process fallback.
func launchHelperWithJobList(config HelperConfig, setJobList jobListSetter) (_ helperProcess, _ error) {
	pin, path, err := pinnedExecutable(config)
	if err != nil {
		return nil, err
	}
	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		_ = pin.Close()
		return nil, err
	}
	var inputRead, inputWrite, outputRead, outputWrite, errorRead, errorWrite windows.Handle
	var process windows.ProcessInformation
	success := false
	defer func() {
		if inputRead != 0 {
			_ = windows.CloseHandle(inputRead)
		}
		if outputWrite != 0 {
			_ = windows.CloseHandle(outputWrite)
		}
		if errorWrite != 0 {
			_ = windows.CloseHandle(errorWrite)
		}
		if process.Thread != 0 {
			_ = windows.CloseHandle(process.Thread)
		}
		if !success {
			if process.Process != 0 {
				_ = windows.TerminateJobObject(job, 1)
				_ = windows.CloseHandle(job)
				job = 0
				_ = (&windowsHelperProcess{process: process.Process}).Wait()
				_ = windows.CloseHandle(process.Process)
			}
			if job != 0 {
				_ = windows.CloseHandle(job)
			}
			if inputWrite != 0 {
				_ = windows.CloseHandle(inputWrite)
			}
			if outputRead != 0 {
				_ = windows.CloseHandle(outputRead)
			}
			if errorRead != 0 {
				_ = windows.CloseHandle(errorRead)
			}
			_ = pin.Close()
		}
	}()
	if err = windows.SetHandleInformation(job, windows.HANDLE_FLAG_INHERIT, 0); err != nil {
		return nil, err
	}
	limits := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	limits.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	if _, err = windows.SetInformationJobObject(job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&limits)), uint32(unsafe.Sizeof(limits))); err != nil {
		return nil, err
	}
	security := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), InheritHandle: 1}
	if err = windows.CreatePipe(&inputRead, &inputWrite, &security, 0); err != nil {
		return nil, err
	}
	if err = windows.CreatePipe(&outputRead, &outputWrite, &security, 0); err != nil {
		return nil, err
	}
	if err = windows.CreatePipe(&errorRead, &errorWrite, &security, 0); err != nil {
		return nil, err
	}
	if err = windows.SetHandleInformation(inputWrite, windows.HANDLE_FLAG_INHERIT, 0); err != nil {
		return nil, err
	}
	if err = windows.SetHandleInformation(outputRead, windows.HANDLE_FLAG_INHERIT, 0); err != nil {
		return nil, err
	}
	if err = windows.SetHandleInformation(errorRead, windows.HANDLE_FLAG_INHERIT, 0); err != nil {
		return nil, err
	}
	attributes, err := windows.NewProcThreadAttributeList(2)
	if err != nil {
		return nil, err
	}
	defer attributes.Delete()
	inherited := []windows.Handle{inputRead, outputWrite, errorWrite}
	if err = attributes.Update(windows.PROC_THREAD_ATTRIBUTE_HANDLE_LIST, unsafe.Pointer(&inherited[0]), uintptr(len(inherited))*unsafe.Sizeof(inherited[0])); err != nil {
		return nil, err
	}
	jobs := []windows.Handle{job}
	if err = setJobList(attributes, jobs); err != nil {
		return nil, err
	}
	startup := windows.StartupInfoEx{}
	startup.Cb = uint32(unsafe.Sizeof(startup))
	startup.Flags = windows.STARTF_USESTDHANDLES
	startup.StdInput = inputRead
	startup.StdOutput = outputWrite
	startup.StdErr = errorWrite
	startup.ProcThreadAttributeList = attributes.List()
	application, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	command, err := windows.UTF16FromString(syscall.EscapeArg(path))
	if err != nil {
		return nil, err
	}
	directory, err := windows.UTF16PtrFromString(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	flags := uint32(windows.EXTENDED_STARTUPINFO_PRESENT | windows.CREATE_SUSPENDED | windows.CREATE_NO_WINDOW)
	if err = windows.CreateProcess(application, &command[0], nil, nil, true, flags, nil, directory, &startup.StartupInfo, &process); err != nil {
		return nil, fmt.Errorf("create helper in kill-on-close job: %w", err)
	}
	// The job handle and parent stdin writer are excluded from inheritance.
	if previous, err := windows.ResumeThread(process.Thread); err != nil || previous != 1 {
		if err == nil {
			err = fmt.Errorf("unexpected helper suspend count %d", previous)
		}
		return nil, err
	}
	success = true
	helper := &windowsHelperProcess{process: process.Process, job: job, input: os.NewFile(uintptr(inputWrite), "helper-stdin"), output: os.NewFile(uintptr(outputRead), "helper-stdout"), stderr: os.NewFile(uintptr(errorRead), "helper-stderr"), pin: pin, diagnosticDone: make(chan struct{})}
	go helper.drainDiagnostics()
	return helper, nil
}

func (p *windowsHelperProcess) Input() io.WriteCloser { return p.input }
func (p *windowsHelperProcess) Output() io.ReadCloser { return p.output }

func (p *windowsHelperProcess) drainDiagnostics() {
	defer close(p.diagnosticDone)
	buffer := make([]byte, 4096)
	for {
		count, err := p.stderr.Read(buffer)
		if count > 0 {
			p.diagnosticMu.Lock()
			room := 64*1024 - len(p.diagnostic)
			if room > count {
				room = count
			}
			if room > 0 {
				p.diagnostic = append(p.diagnostic, buffer[:room]...)
			}
			p.diagnosticMu.Unlock()
		}
		if err != nil {
			return
		}
	}
}

// Wait never reports completion until the kernel confirms exact-child exit.
func (p *windowsHelperProcess) Wait() error {
	var firstErr error
	for {
		state, err := windows.WaitForSingleObject(p.process, 250)
		if err == nil && state == windows.WAIT_OBJECT_0 {
			var code uint32
			if err = windows.GetExitCodeProcess(p.process, &code); err != nil {
				return errors.Join(firstErr, err)
			}
			if code != 0 {
				return errors.Join(firstErr, fmt.Errorf("helper exited with code %d", code))
			}
			return firstErr
		}
		if err != nil || state != uint32(windows.WAIT_TIMEOUT) {
			if firstErr == nil {
				if err == nil {
					err = fmt.Errorf("unexpected helper wait state %d", state)
				}
				firstErr = err
			}
			_ = p.Terminate()
			time.Sleep(25 * time.Millisecond)
		}
	}
}

func (p *windowsHelperProcess) Terminate() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.job == 0 {
		return nil
	}
	err := windows.TerminateJobObject(p.job, 1)
	if err != nil {
		closeErr := windows.CloseHandle(p.job)
		if closeErr == nil {
			p.job = 0
		}
		return errors.Join(err, closeErr)
	}
	return nil
}

func closePipe(file *os.File) error {
	err := file.Close()
	if errors.Is(err, os.ErrClosed) {
		return nil
	}
	return err
}
func (p *windowsHelperProcess) Close() error {
	p.mu.Lock()
	errs := []error{}
	if p.job != 0 {
		errs = append(errs, windows.CloseHandle(p.job))
		p.job = 0
	}
	p.mu.Unlock()
	// Close the non-inherited job before draining: its descendants must not
	// retain a stderr writer after the exact helper has exited.
	<-p.diagnosticDone
	errs = append(errs, closePipe(p.input), closePipe(p.output), p.stderr.Close(), p.pin.Close(), windows.CloseHandle(p.process))
	p.diagnosticMu.Lock()
	diagnostic := strings.TrimSpace(string(p.diagnostic))
	p.diagnosticMu.Unlock()
	if diagnostic != "" {
		errs = append(errs, fmt.Errorf("helper stderr: %s", diagnostic))
	}
	return errors.Join(errs...)
}
