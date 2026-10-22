//go:build windows

package printtransport

import (
	"errors"
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"
)

var kernel32 = windows.NewLazySystemDLL("kernel32.dll")
var createSemaphoreW = kernel32.NewProc("CreateSemaphoreW")
var releaseSemaphore = kernel32.NewProc("ReleaseSemaphore")

func acquireOSGuard(name string) (func() error, error) {
	nativeName, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	raw, _, callErr := createSemaphoreW.Call(0, 1, 1, uintptr(unsafe.Pointer(nativeName)))
	if raw == 0 {
		return nil, fmt.Errorf("create physical printer semaphore: %w", callErr)
	}
	handle := windows.Handle(raw)
	status, waitErr := windows.WaitForSingleObject(handle, 0)
	if waitErr != nil || status != windows.WAIT_OBJECT_0 {
		closeErr := windows.CloseHandle(handle)
		if waitErr == nil {
			waitErr = errors.New("physical printer is held by an original process/helper")
		}
		return nil, errors.Join(waitErr, closeErr)
	}
	return func() error {
		ok, _, releaseErr := releaseSemaphore.Call(raw, 1, 0)
		if ok != 0 {
			releaseErr = nil
		}
		return errors.Join(releaseErr, windows.CloseHandle(handle))
	}, nil
}
