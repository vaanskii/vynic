package printerdaemon

import (
	"fmt"
	"os"
	"path/filepath"
)

func noReparse(path string) error {
	if !absolutePath(path) {
		return fmt.Errorf("%w: noncanonical absolute path", ErrConfig)
	}
	if err := platformLocalPath(path); err != nil {
		return err
	}
	for current := path; ; current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("%w: symbolic path refused", ErrConfig)
		}
		if err = platformReparse(current); err != nil {
			return err
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
	}
}

// Windows fixed local drives are the only supported service/state volume. UNC,
// device namespaces and mapped network drives cannot claim SQLite/lock safety.
func validateWindowsVolume(path string, driveType uint32) error {
	if len(path) < 3 || path[1] != ':' || !(path[0] >= 'A' && path[0] <= 'Z' || path[0] >= 'a' && path[0] <= 'z') || !(path[2] == '\\' || path[2] == '/') || driveType != 3 {
		return fmt.Errorf("%w: ordinary fixed local Windows drive required", ErrConfig)
	}
	return nil
}
