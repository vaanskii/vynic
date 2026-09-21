//go:build windows

package main

import (
	"errors"
	"testing"
	"time"
	"unsafe"
)

func TestWin32ABISizes(t *testing.T) {
	if unsafe.Sizeof(windowClass{}) != 80 || unsafe.Sizeof(windowMessage{}) != 48 {
		t.Fatal("Windows amd64 ABI mismatch")
	}
}

func TestNativeProgressLifecycle(t *testing.T) {
	sentinel := errors.New("simulated operation result")
	_, err := nativeDialog("Native Setup UI test", nil, func(report func(string)) error {
		visible, _, _ := user32.NewProc("IsWindowVisible").Call(currentUI.hwnd)
		if visible == 0 {
			return errors.New("native window was not visible")
		}
		report("Native progress test; no install or child process")
		time.Sleep(300 * time.Millisecond)
		return sentinel
	})
	if !errors.Is(err, sentinel) {
		t.Fatal(err)
	}
}
