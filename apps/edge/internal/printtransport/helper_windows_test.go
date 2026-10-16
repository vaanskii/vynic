//go:build windows

package printtransport

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"testing"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

const fixtureMode = "VYNIC_PRINT_TEST_CHILD"
const fixtureID = "VYNIC_PRINT_TEST_ID"

// Test children use this Go test executable, not the Winspool helper. They only
// hold/read OS handles. No positive payload ever reaches a real spooler API.
func TestMain(m *testing.M) {
	switch os.Getenv(fixtureMode) {
	case "eof":
		_, err := io.Copy(io.Discard, os.Stdin)
		if err != nil {
			os.Exit(3)
		}
		os.Exit(0)
	case "hold":
		frame, err := readFrame(os.Stdin)
		if err != nil || frame[6] != tagInventory {
			os.Exit(4)
		}
		reader := wireReader{bytes.NewReader(frame[8:])}
		name, err := reader.text(128, false, true)
		if err != nil || reader.Len() != 0 {
			os.Exit(5)
		}
		pointer, err := windows.UTF16PtrFromString(name)
		if err != nil {
			os.Exit(6)
		}
		raw, _, _ := kernel32.NewProc("OpenSemaphoreW").Call(windows.SYNCHRONIZE|0x0002, 0, uintptr(unsafe.Pointer(pointer)))
		if raw == 0 {
			os.Exit(7)
		}
		handle := windows.Handle(raw)
		state, err := windows.WaitForSingleObject(handle, 0)
		if err != nil || state != uint32(windows.WAIT_TIMEOUT) {
			if err == nil && state == windows.WAIT_OBJECT_0 {
				// As in the real helper, undo any unexpected acquisition before
				// refusing to proceed; the child never owns the parent's count.
				_, _, _ = releaseSemaphore.Call(uintptr(handle), 1, 0)
			}
			_ = windows.CloseHandle(handle)
			os.Exit(8)
		}
		if writeFrame(os.Stdout, header(tagReady)) != nil {
			_ = windows.CloseHandle(handle)
			os.Exit(9)
		}
		_, _ = io.Copy(io.Discard, os.Stdin)
		_ = windows.CloseHandle(handle)
		os.Exit(0)
	case "parent":
		guard, err := AcquirePrinterGuard(os.Getenv(fixtureID))
		if err != nil {
			os.Exit(10)
		}
		defer guard.Close()
		config, err := selfHelperConfig()
		if err != nil {
			os.Exit(11)
		}
		_ = os.Setenv(fixtureMode, "hold")
		process, err := launchHelper(config)
		if err != nil {
			os.Exit(12)
		}
		request := appendText(header(tagInventory), guard.(*physicalGuard).name)
		if writeFrame(process.Input(), request) != nil {
			os.Exit(13)
		}
		ready, err := readFrame(process.Output())
		if err != nil || !bytes.Equal(ready, header(tagReady)) {
			os.Exit(14)
		}
		pid, err := windows.GetProcessId(process.(*windowsHelperProcess).process)
		if err != nil {
			os.Exit(15)
		}
		if writeFrame(os.Stdout, binary.LittleEndian.AppendUint32(header(tagReady), pid)) != nil {
			os.Exit(16)
		}
		_, _ = io.Copy(io.Discard, os.Stdin)
		_ = process.Terminate()
		_ = process.Input().Close()
		_ = process.Output().Close()
		_ = process.Wait()
		_ = process.Close()
		os.Exit(0)
	default:
		os.Exit(m.Run())
	}
}

func selfHelperConfig() (HelperConfig, error) {
	path, err := os.Executable()
	if err != nil {
		return HelperConfig{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return HelperConfig{}, err
	}
	sum := sha256.Sum256(data)
	return HelperConfig{Path: path, SHA256: fmt.Sprintf("%x", sum), ProtocolVersion: 1}, nil
}

func TestWindowsJobContainsChildAndStdinHasNoInheritedWriter(t *testing.T) {
	t.Setenv(fixtureMode, "eof")
	config, err := selfHelperConfig()
	if err != nil {
		t.Fatal(err)
	}
	process, err := launchHelper(config)
	if err != nil {
		t.Fatal(err)
	}
	defer process.Close()
	_ = process.Input().Close()
	done := make(chan error, 1)
	go func() { done <- process.Wait() }()
	select {
	case err = <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		_ = process.Terminate()
		<-done
		t.Fatal("stdin writer leaked into child; EOF did not arrive")
	}
	if _, err = AcquirePrinterGuard("bad physical identity"); err == nil {
		t.Fatal("invalid guard name admitted")
	}
}

func TestWindowsUnsupportedJobListFailsBeforeProcessCreation(t *testing.T) {
	config, err := selfHelperConfig()
	if err != nil {
		t.Fatal(err)
	}
	calls := 0
	process, err := launchHelperWithJobList(config, func(attributes *windows.ProcThreadAttributeListContainer, jobs []windows.Handle) error {
		calls++
		if attributes == nil || len(jobs) != 1 || jobs[0] == 0 {
			t.Fatal("job assignment missing before process creation")
		}
		return windows.ERROR_NOT_SUPPORTED
	})
	if process != nil || !errors.Is(err, windows.ERROR_NOT_SUPPORTED) || calls != 1 {
		t.Fatalf("unsupported JOB_LIST did not fail closed: process=%v err=%v calls=%d", process, err, calls)
	}
	t.Log("unsupported JOB_LIST rejected before CreateProcess; no child or request bytes")
}

func TestWindowsParentDeathTerminatesChildAndFreshGuardAcquires(t *testing.T) {
	path, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	id := "orphan-test-" + strconv.Itoa(os.Getpid()) + "-" + strconv.FormatInt(time.Now().UnixNano(), 10)
	command := exec.Command(path)
	command.Env = append(os.Environ(), fixtureMode+"=parent", fixtureID+"="+id)
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err = command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = input.Close(); _ = command.Process.Kill() }()
	readyChannel := make(chan struct {
		frame []byte
		err   error
	}, 1)
	go func() {
		frame, err := readFrame(output)
		readyChannel <- struct {
			frame []byte
			err   error
		}{frame, err}
	}()
	var ready []byte
	select {
	case result := <-readyChannel:
		if result.err != nil {
			_ = command.Process.Kill()
			_ = command.Wait()
			t.Fatal(result.err)
		}
		ready = result.frame
	case <-time.After(5 * time.Second):
		_ = command.Process.Kill()
		_ = command.Wait()
		t.Fatal("fixture parent readiness timed out")
	}
	if len(ready) != 12 || ready[6] != tagReady {
		_ = command.Process.Kill()
		_ = command.Wait()
		t.Fatal("invalid fixture child PID envelope")
	}
	child, err := windows.OpenProcess(windows.SYNCHRONIZE|windows.PROCESS_TERMINATE, false, binary.LittleEndian.Uint32(ready[8:]))
	if err != nil {
		_ = command.Process.Kill()
		_ = command.Wait()
		t.Fatal(err)
	}
	defer windows.CloseHandle(child)
	// Failed nonblocking acquisitions must immediately close their handles, or
	// the replacement would itself preserve the old zero-count semaphore.
	for n := 0; n < 3; n++ {
		guard, err := AcquirePrinterGuard(id)
		if err == nil {
			_ = guard.Close()
			t.Fatal("parent/child printer guard was bypassed")
		}
	}
	if err = command.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = command.Wait()
	state, err := windows.WaitForSingleObject(child, 5000)
	if err != nil || state != windows.WAIT_OBJECT_0 {
		_ = windows.TerminateProcess(child, 1)
		_, _ = windows.WaitForSingleObject(child, 5000)
		t.Fatalf("kill-on-parent-close did not terminate child: %d %v", state, err)
	}
	guard, err := AcquirePrinterGuard(id)
	if err != nil {
		t.Fatalf("old semaphore was preserved after exact child termination: %v", err)
	}
	if err = guard.Close(); err != nil {
		t.Fatal(err)
	}
}

func actualHelperConfig(t *testing.T) HelperConfig {
	t.Helper()
	path, hash := os.Getenv("VYNIC_PRINT_HELPER_TEST_PATH"), os.Getenv("VYNIC_PRINT_HELPER_TEST_SHA256")
	if path == "" || hash == "" {
		t.Skip("real read-only helper requires task-scoped executable/hash pins")
	}
	return HelperConfig{Path: path, SHA256: hash, ProtocolVersion: 1}
}

func TestWindowsActualHelperReadOnlyAndInvalidRequests(t *testing.T) {
	config := actualHelperConfig(t)
	badPin := config
	replacement := "0"
	if badPin.SHA256[0] == '0' {
		replacement = "1"
	}
	badPin.SHA256 = replacement + badPin.SHA256[1:]
	if process, err := launchHelper(badPin); err == nil {
		_ = process.Terminate()
		_ = process.Wait()
		_ = process.Close()
		t.Fatal("incorrect binary pin launched a child")
	}
	r, err := New(Config{WorkerHostID: "test-host", Helper: &config})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	queues, err := r.ListQueues(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("real read-only helper enumerated %d queues; no documents submitted", len(queues))
	for name, frame := range map[string][]byte{"missing": header(tagSubmit), "empty": submissionFrame(windowsDestination(), nil, guardName("nonphysical-test")), "extra inventory field": append(header(tagInventory), 0)} {
		t.Run(name, func(t *testing.T) {
			process, err := launchHelper(config)
			if err != nil {
				t.Fatal(err)
			}
			outcome := exchangeProcess(ctx, process, frame, 0, true)
			if outcome.err != nil || outcome.result.State != NotSent || outcome.result.WriteAttempted || outcome.result.Stage != "validate" {
				t.Fatalf("%+v", outcome)
			}
		})
	}
	for name, partial := range map[string][]byte{"zero": nil, "partial prefix": {8, 0}, "partial body": {8, 0, 0, 0, 'V', 'T'}} {
		t.Run(name, func(t *testing.T) {
			process, err := launchHelper(config)
			if err != nil {
				t.Fatal(err)
			}
			if len(partial) != 0 {
				if _, err = process.Input().Write(partial); err != nil {
					t.Fatal(err)
				}
			}
			_ = process.Input().Close()
			frame, err := readFrame(process.Output())
			if err != nil {
				_ = process.Terminate()
				_ = process.Wait()
				_ = process.Close()
				t.Fatal(err)
			}
			result, err := decodeResult(frame, 0)
			waitErr := process.Wait()
			closeErr := process.Close()
			if err != nil || waitErr != nil || closeErr != nil || result.State != NotSent || result.WriteAttempted || result.Stage != "validate" {
				t.Fatalf("%+v %v %v %v", result, err, waitErr, closeErr)
			}
		})
	}
}
