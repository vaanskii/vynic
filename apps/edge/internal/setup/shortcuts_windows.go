//go:build windows

package setup

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Native IShellLinkW/IPersistFile integration. Existing foreign shortcuts are
// refused; neither shortcut loading nor saving resolves or executes the target.
type shellCOM struct{ table *[21]uintptr }

func comCall(object *shellCOM, slot int, args ...uintptr) error {
	all := append([]uintptr{uintptr(unsafe.Pointer(object))}, args...)
	result, _, _ := syscall.SyscallN(object.table[slot], all...)
	if int32(result) < 0 {
		return fmt.Errorf("Shell Link method %d HRESULT 0x%08x", slot, uint32(result))
	}
	return nil
}
func shortcuts(l Layout, remove bool) error {
	var dirs []string
	for _, folder := range []*windows.KNOWNFOLDERID{windows.FOLDERID_Programs, windows.FOLDERID_Desktop} {
		dir, e := windows.KnownFolderPath(folder, 0)
		if e != nil {
			return e
		}
		dirs = append(dirs, dir)
	}
	return shortcutFolders(l, remove, dirs)
}

func shortcutFolders(l Layout, remove bool, dirs []string) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	ole := windows.NewLazySystemDLL("ole32.dll")
	hr, _, _ := ole.NewProc("CoInitializeEx").Call(0, 2)
	if int32(hr) < 0 {
		return fmt.Errorf("initialize Shell Link COM: 0x%08x", uint32(hr))
	}
	defer ole.NewProc("CoUninitialize").Call()
	clsid := windows.GUID{Data1: 0x21401, Data4: [8]byte{0xc0, 0, 0, 0, 0, 0, 0, 0x46}}
	iid := windows.GUID{Data1: 0x214f9, Data4: clsid.Data4}
	persistID := windows.GUID{Data1: 0x10b, Data4: clsid.Data4}
	for _, dir := range dirs {
		path := filepath.Join(dir, "Vynic POS.lnk")
		info, e := os.Lstat(path)
		exists := e == nil
		if e != nil && !os.IsNotExist(e) {
			return e
		}
		if exists {
			if !info.Mode().IsRegular() {
				return fmt.Errorf("non-regular shortcut refused: %s", path)
			}
			if e = checkReparse(path); e != nil {
				return e
			}
		}
		if remove && !exists {
			continue
		}
		var link *shellCOM
		hr, _, _ := ole.NewProc("CoCreateInstance").Call(uintptr(unsafe.Pointer(&clsid)), 0, 1, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&link)))
		if int32(hr) < 0 {
			return fmt.Errorf("create Shell Link: 0x%08x", uint32(hr))
		}
		e = func() error {
			defer comCall(link, 2)
			var file *shellCOM
			if e := comCall(link, 0, uintptr(unsafe.Pointer(&persistID)), uintptr(unsafe.Pointer(&file))); e != nil {
				return e
			}
			defer comCall(file, 2)
			p, e := windows.UTF16PtrFromString(path)
			if e != nil {
				return e
			}
			if exists {
				if e = comCall(file, 5, uintptr(unsafe.Pointer(p)), 0); e != nil {
					return e
				}
				target := make([]uint16, 32768)
				if e = comCall(link, 3, uintptr(unsafe.Pointer(&target[0])), uintptr(len(target)), 0, 4); e != nil {
					return e
				}
				if !strings.EqualFold(filepath.Clean(windows.UTF16ToString(target)), filepath.Clean(l.Setup())) {
					return fmt.Errorf("unrelated Vynic POS shortcut exists: %s", path)
				}
			}
			if remove {
				return os.Remove(path)
			}
			for _, setting := range []struct {
				slot  int
				value string
			}{{20, l.Setup()}, {11, "--launch"}, {9, filepath.Dir(l.Setup())}, {7, "Vynic POS"}} {
				value, e := windows.UTF16PtrFromString(setting.value)
				if e != nil {
					return e
				}
				if e = comCall(link, setting.slot, uintptr(unsafe.Pointer(value))); e != nil {
					return e
				}
				runtime.KeepAlive(value)
			}
			icon, e := windows.UTF16PtrFromString(l.Setup())
			if e != nil {
				return e
			}
			if e = comCall(link, 17, uintptr(unsafe.Pointer(icon)), 0); e != nil {
				return e
			}
			runtime.KeepAlive(icon)
			if e = comCall(link, 15, 1); e != nil {
				return e
			} // SW_SHOWNORMAL
			e = comCall(file, 6, uintptr(unsafe.Pointer(p)), 1)
			runtime.KeepAlive(p)
			return e
		}()
		if e != nil {
			return e
		}
	}
	return nil
}
