//go:build windows

package updater

import (
	"errors"
	"fmt"
	"golang.org/x/sys/windows"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"unsafe"
)

type NativeProcess struct{}

func posHandle(pid int, path string, access uint32) (windows.Handle, error) {
	if pid < 1 || uint64(pid) > uint64(^uint32(0)) {
		return 0, errors.New("invalid POS process ID")
	}
	if filepath.Base(path) != Executable {
		return 0, errors.New("refusing non-POS executable")
	}
	h, e := windows.OpenProcess(access|windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE, false, uint32(pid))
	if e != nil {
		return 0, e
	}
	fail := func(e error) (windows.Handle, error) { windows.CloseHandle(h); return 0, e }
	buf := make([]uint16, 32768)
	size := uint32(len(buf))
	if e = windows.QueryFullProcessImageName(h, 0, &buf[0], &size); e != nil {
		return fail(e)
	}
	if !strings.EqualFold(filepath.Clean(windows.UTF16ToString(buf[:size])), filepath.Clean(path)) {
		return fail(errOtherProcess)
	}
	result, e := windows.WaitForSingleObject(h, 0)
	if e != nil {
		return fail(e)
	}
	if result != uint32(windows.WAIT_TIMEOUT) {
		return fail(errProcessExited)
	}
	return h, nil
}

var errOtherProcess = errors.New("POS path mismatch")
var errProcessExited = errors.New("POS already exited")

func (NativeProcess) Validate(pid int, path string) error {
	h, e := posHandle(pid, path, 0)
	if e == nil {
		e = windows.CloseHandle(h)
	}
	return e
}
func matchingProcesses(path string, access uint32) (result []windows.Handle, err error) {
	snap, e := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if e != nil {
		return nil, e
	}
	defer windows.CloseHandle(snap)
	defer func() {
		if err != nil {
			for _, h := range result {
				windows.CloseHandle(h)
			}
			result = nil
		}
	}()
	entry := windows.ProcessEntry32{Size: uint32(unsafe.Sizeof(windows.ProcessEntry32{}))}
	for e = windows.Process32First(snap, &entry); e == nil; e = windows.Process32Next(snap, &entry) {
		if !strings.EqualFold(windows.UTF16ToString(entry.ExeFile[:]), Executable) {
			continue
		}
		h, he := posHandle(int(entry.ProcessID), path, access)
		if errors.Is(he, errOtherProcess) || errors.Is(he, windows.ERROR_INVALID_PARAMETER) || errors.Is(he, errProcessExited) {
			continue
		}
		if he != nil {
			return result, he
		}
		result = append(result, h)
	}
	if !errors.Is(e, windows.ERROR_NO_MORE_FILES) {
		return result, e
	}
	return result, nil
}
func (NativeProcess) Stop(path string) error {
	handles, e := matchingProcesses(path, windows.PROCESS_TERMINATE)
	if e != nil {
		return e
	}
	defer func() {
		for _, h := range handles {
			windows.CloseHandle(h)
		}
	}()
	// Full-path validation and termination share the same kernel handle. PID
	// reuse cannot redirect termination to Manager, Edge, or another process.
	for _, h := range handles {
		if e = windows.TerminateProcess(h, 0); e != nil {
			return e
		}
		result, e := windows.WaitForSingleObject(h, 15000)
		if e != nil {
			return e
		}
		if result != windows.WAIT_OBJECT_0 {
			return fmt.Errorf("POS stop wait returned %d", result)
		}
	}
	return nil
}
func (NativeProcess) Start(path string, env []string) (int, error) {
	if filepath.Base(path) != Executable {
		return 0, errors.New("refusing non-POS executable")
	}
	handles, e := matchingProcesses(path, 0)
	if e != nil {
		return 0, e
	}
	for _, h := range handles {
		windows.CloseHandle(h)
	}
	if len(handles) > 0 {
		return 0, errors.New("POS already running")
	}
	c := exec.Command(path)
	c.Dir = filepath.Dir(path)
	c.Env = append(os.Environ(), env...)
	if e = c.Start(); e != nil {
		return 0, e
	}
	pid := c.Process.Pid
	go func() { _ = c.Wait() }()
	return pid, nil
}

func (NativeProcess) Running(path string) (bool, error) {
	handles, e := matchingProcesses(path, 0)
	if e != nil {
		return false, e
	}
	for _, h := range handles {
		windows.CloseHandle(h)
	}
	return len(handles) > 0, nil
}
