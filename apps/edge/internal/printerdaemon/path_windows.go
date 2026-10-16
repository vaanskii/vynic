//go:build windows

package printerdaemon

import (
	"fmt"

	"golang.org/x/sys/windows"
)

func platformReparse(path string) error {
	pointer, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	attributes, err := windows.GetFileAttributes(pointer)
	if err != nil {
		return err
	}
	if attributes&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		return fmt.Errorf("%w: Windows reparse path refused", ErrConfig)
	}
	return nil
}

func platformLocalPath(path string) error {
	if err := validateWindowsVolume(path, windows.DRIVE_FIXED); err != nil {
		return err
	}
	root, err := windows.UTF16PtrFromString(path[:3])
	if err != nil {
		return err
	}
	return validateWindowsVolume(path, windows.GetDriveType(root))
}
