//go:build !windows

package updater

import (
	"errors"
	"os"
	"path/filepath"
)

func moveBinary(from, to string) error {
	if e := os.Rename(from, to); e != nil {
		return e
	}
	d, e := os.Open(filepath.Dir(from))
	if e != nil {
		return e
	}
	if e = errors.Join(d.Sync(), d.Close()); e != nil {
		return e
	}
	d, e = os.Open(filepath.Dir(to))
	if e != nil {
		return e
	}
	return errors.Join(d.Sync(), d.Close())
}
func checkBinaryReparse(string) error { return nil }
