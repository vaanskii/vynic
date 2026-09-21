//go:build windows

package main

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
	"vynic.local/edge/internal/setup"
)

// All windows and controls belong to the Setup process and one locked OS thread.
// No interpreter, temporary script, child UI process, or downloaded UI code.
var user32 = windows.NewLazySystemDLL("user32.dll")
var uiCallback = syscall.NewCallback(windowProc)
var uiLock sync.Mutex
var currentUI *nativeUI

type button struct {
	Text string
	ID   int
}
type windowClass struct {
	Size, Style                        uint32
	Proc                               uintptr
	ClassExtra, WindowExtra            int32
	Instance, Icon, Cursor, Background uintptr
	Menu, Name                         *uint16
	SmallIcon                          uintptr
}
type windowMessage struct {
	Window         uintptr
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	X, Y           int32
	Private        uint32
}
type nativeUI struct {
	hwnd, label  uintptr
	bar, busyBar uintptr
	progress     setup.UpdateProgress
	input        uintptr
	inputValue   *string
	buttons      []button
	selected     int
	working      bool
	mu           sync.Mutex
	message      string
	done         bool
	result       error
}

func utf(s string) *uint16 { return windows.StringToUTF16Ptr(s) }
func winCall(name string, args ...uintptr) (uintptr, error) {
	r, _, e := user32.NewProc(name).Call(args...)
	if r == 0 {
		return 0, fmt.Errorf("%s failed: %w", name, e)
	}
	return r, nil
}
func windowProc(hwnd uintptr, msg uint32, w, l uintptr) uintptr {
	u := currentUI
	if u != nil {
		switch msg {
		case 0x0111: // WM_COMMAND: only controls belonging to this window may select.
			if !u.working && w&0xffff == 900 && w>>16 == 0 {
				if selected, err := browseDestination(hwnd); err != nil {
					showError(err)
				} else if selected != "" {
					user32.NewProc("SetWindowTextW").Call(u.input, uintptr(unsafe.Pointer(utf(selected))))
				}
				return 0
			}
			if !u.working && w>>16 == 0 {
				index := int(w&0xffff) - 100
				if index >= 0 && index < len(u.buttons) {
					if u.inputValue != nil {
						value := make([]uint16, 32768)
						user32.NewProc("GetWindowTextW").Call(u.input, uintptr(unsafe.Pointer(&value[0])), uintptr(len(value)))
						*u.inputValue = windows.UTF16ToString(value)
					}
					u.selected = u.buttons[index].ID
					user32.NewProc("DestroyWindow").Call(hwnd)
					return 0
				}
			}
		case 0x0010: // WM_CLOSE: never abandon an in-flight install/repair.
			if !u.working {
				user32.NewProc("DestroyWindow").Call(hwnd)
			}
			return 0
		case 0x0113: // WM_TIMER: worker reports are consumed on the UI thread.
			u.mu.Lock()
			message, done, progress := u.message, u.done, u.progress
			u.mu.Unlock()
			user32.NewProc("SetWindowTextW").Call(u.label, uintptr(unsafe.Pointer(utf(message))))
			if u.bar != 0 {
				if progress.Total > 0 {
					user32.NewProc("ShowWindow").Call(u.busyBar, 0)
					user32.NewProc("ShowWindow").Call(u.bar, 5)
					user32.NewProc("SendMessageW").Call(u.bar, 0x402, uintptr(progress.Percent()), 0)
				} else {
					user32.NewProc("ShowWindow").Call(u.bar, 0)
					user32.NewProc("ShowWindow").Call(u.busyBar, 5)
				}
			}
			if done {
				user32.NewProc("DestroyWindow").Call(hwnd)
			}
			return 0
		case 0x0002: // WM_DESTROY
			user32.NewProc("PostQuitMessage").Call(0)
			return 0
		}
	}
	r, _, _ := user32.NewProc("DefWindowProcW").Call(hwnd, uintptr(msg), w, l)
	return r
}
func nativeDialog(message string, buttons []button, work func(func(string)) error) (int, error) {
	return nativePage("Vynic POS Setup", message, nil, buttons, work)
}

func nativePage(title, message string, input *string, buttons []button, work func(func(string)) error) (int, error) {
	var progressWork func(func(setup.UpdateProgress)) error
	if work != nil {
		progressWork = func(report func(setup.UpdateProgress)) error {
			return work(func(message string) { report(setup.UpdateProgress{Message: message}) })
		}
	}
	return nativeProgressPage(title, message, input, buttons, progressWork)
}

func nativeProgressPage(title, message string, input *string, buttons []button, work func(func(setup.UpdateProgress)) error) (int, error) {
	uiLock.Lock()
	defer uiLock.Unlock()
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	instance, _, e := windows.NewLazySystemDLL("kernel32.dll").NewProc("GetModuleHandleW").Call(0)
	if instance == 0 {
		return 0, e
	}
	name := utf("Vynic.Setup.NativeWindow")
	cursor, _, _ := user32.NewProc("LoadCursorW").Call(0, 32512)
	icon, _, _ := user32.NewProc("LoadImageW").Call(uintptr(instance), 1, 1, 32, 32, 0x8000) // RT_GROUP_ICON 1, LR_SHARED
	smallIcon, _, _ := user32.NewProc("LoadImageW").Call(uintptr(instance), 1, 1, 16, 16, 0x8000)
	wc := windowClass{Proc: uiCallback, Instance: uintptr(instance), Icon: icon, SmallIcon: smallIcon, Cursor: cursor, Background: 6, Name: name}
	wc.Size = uint32(unsafe.Sizeof(wc))
	atom, _, err := user32.NewProc("RegisterClassExW").Call(uintptr(unsafe.Pointer(&wc)))
	if atom == 0 {
		return 0, fmt.Errorf("register Setup window: %w", err)
	}
	defer user32.NewProc("UnregisterClassW").Call(uintptr(unsafe.Pointer(name)), uintptr(instance))
	u := &nativeUI{buttons: buttons, working: work != nil, message: message, inputValue: input}
	currentUI = u
	defer func() { currentUI = nil }()
	// Fixed dialog with taskbar presence; no hidden startup flag.
	screenW, _, _ := user32.NewProc("GetSystemMetrics").Call(0)
	screenH, _, _ := user32.NewProc("GetSystemMetrics").Call(1)
	x, y := uintptr(0), uintptr(0)
	if screenW > 660 {
		x = (screenW - 660) / 2
	}
	if screenH > 410 {
		y = (screenH - 410) / 2
	}
	hwnd, e := winCall("CreateWindowExW", 0x40000, uintptr(unsafe.Pointer(name)), uintptr(unsafe.Pointer(utf("Vynic Setup"))), 0x00c80000, x, y, 660, 410, 0, 0, uintptr(instance), 0)
	if e != nil {
		return 0, e
	}
	u.hwnd = hwnd
	defer user32.NewProc("DestroyWindow").Call(hwnd)
	font := uiFont(-16, 400)
	headingFont := uiFont(-25, 600)
	defer windows.NewLazySystemDLL("gdi32.dll").NewProc("DeleteObject").Call(font)
	defer windows.NewLazySystemDLL("gdi32.dll").NewProc("DeleteObject").Call(headingFont)
	control := func(class, text string, style, x, y, width, height, id uintptr) (uintptr, error) {
		h, e := winCall("CreateWindowExW", 0, uintptr(unsafe.Pointer(utf(class))), uintptr(unsafe.Pointer(utf(text))), style|0x50000000, x, y, width, height, hwnd, id, uintptr(instance), 0)
		if e == nil {
			user32.NewProc("SendMessageW").Call(h, 0x30, font, 1)
		}
		return h, e
	}
	heading, he := control("STATIC", title, 0, 28, 24, 596, 42, 0)
	if he != nil {
		return 0, he
	}
	user32.NewProc("SendMessageW").Call(heading, 0x30, headingFont, 1)
	u.label, e = control("STATIC", message, 0, 28, 82, 596, 142, 0)
	if e != nil {
		return 0, e
	}
	if input != nil {
		u.input, e = control("EDIT", *input, 0x00810080, 28, 220, 482, 30, 901)
		if e != nil {
			return 0, e
		}
		if _, e = control("BUTTON", "Browse…", 0x10000, 520, 220, 104, 30, 900); e != nil {
			return 0, e
		}
	}
	if _, e = control("STATIC", "Vynic POS  •  Setup "+setupVersion, 0, 28, 282, 590, 25, 0); e != nil {
		return 0, e
	}
	for i, b := range buttons {
		style := uintptr(0x10000)
		if b.ID == 1 || b.ID == 5 {
			style |= 1
		}
		if _, e = control("BUTTON", b.Text, style, uintptr(636-len(buttons)*150+i*150), 324, 140, 34, uintptr(100+i)); e != nil {
			return 0, e
		}
	}
	if work != nil {
		init := [2]uint32{8, 0x20}
		ok, _, ce := windows.NewLazySystemDLL("comctl32.dll").NewProc("InitCommonControlsEx").Call(uintptr(unsafe.Pointer(&init[0])))
		if ok == 0 {
			return 0, fmt.Errorf("initialize progress control: %w", ce)
		}
		bar, be := control("msctls_progress32", "", 8, 28, 236, 596, 18, 902)
		if be != nil {
			return 0, be
		}
		u.busyBar = bar
		u.bar, e = control("msctls_progress32", "", 0, 28, 236, 596, 18, 903)
		if e != nil {
			return 0, e
		}
		user32.NewProc("SendMessageW").Call(u.bar, 0x406, 0, 100) // PBM_SETRANGE32
		user32.NewProc("ShowWindow").Call(u.bar, 0)
		user32.NewProc("SendMessageW").Call(bar, 0x40a, 1, 40)
	}
	if work != nil {
		if _, e = winCall("SetTimer", hwnd, 1, 200, 0); e != nil {
			return 0, e
		}
		defer user32.NewProc("KillTimer").Call(hwnd, 1)
	}
	user32.NewProc("ShowWindow").Call(hwnd, 5)
	user32.NewProc("UpdateWindow").Call(hwnd)
	user32.NewProc("SetForegroundWindow").Call(hwnd)
	var finished chan struct{}
	if work != nil {
		finished = make(chan struct{})
		go func() {
			defer close(finished)
			result := work(func(p setup.UpdateProgress) { u.mu.Lock(); u.message = p.Message; u.progress = p; u.mu.Unlock() })
			u.mu.Lock()
			u.result = result
			u.done = true
			u.mu.Unlock()
		}()
	}
	var loopErr error
	for {
		var m windowMessage
		r, _, e := user32.NewProc("GetMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) == -1 {
			loopErr = fmt.Errorf("Setup message loop: %w", e)
			break
		}
		if r == 0 {
			break
		}
		handled, _, _ := user32.NewProc("IsDialogMessageW").Call(hwnd, uintptr(unsafe.Pointer(&m)))
		if handled == 0 {
			user32.NewProc("TranslateMessage").Call(uintptr(unsafe.Pointer(&m)))
			user32.NewProc("DispatchMessageW").Call(uintptr(unsafe.Pointer(&m)))
		}
	}
	if finished != nil {
		<-finished
	} // Process must not exit while durable work is active.
	return u.selected, errors.Join(loopErr, u.result)
}

func uiFont(height int32, weight uintptr) uintptr {
	font, _, _ := windows.NewLazySystemDLL("gdi32.dll").NewProc("CreateFontW").Call(uintptr(height), 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, 5, 0, uintptr(unsafe.Pointer(utf("Segoe UI"))))
	return font
}

type browseInfo struct {
	Owner, Root        uintptr
	DisplayName, Title *uint16
	Flags              uint32
	Callback, Param    uintptr
	Image              int32
}

func browseDestination(owner uintptr) (string, error) {
	ole := windows.NewLazySystemDLL("ole32.dll")
	hr, _, _ := ole.NewProc("CoInitializeEx").Call(0, 2)
	if int32(hr) < 0 {
		return "", fmt.Errorf("folder picker initialization failed: 0x%x", hr)
	}
	defer ole.NewProc("CoUninitialize").Call()
	display := make([]uint16, 260)
	info := browseInfo{Owner: owner, DisplayName: &display[0], Title: utf("Choose a folder for Vynic POS"), Flags: 0x41}
	shell := windows.NewLazySystemDLL("shell32.dll")
	item, _, _ := shell.NewProc("SHBrowseForFolderW").Call(uintptr(unsafe.Pointer(&info)))
	if item == 0 {
		return "", nil
	}
	defer ole.NewProc("CoTaskMemFree").Call(item)
	path := make([]uint16, 260)
	result, _, _ := shell.NewProc("SHGetPathFromIDListW").Call(item, uintptr(unsafe.Pointer(&path[0])))
	if result == 0 {
		return "", errors.New("choose a local filesystem folder")
	}
	return windows.UTF16ToString(path), nil
}
