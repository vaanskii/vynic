//go:build !windows

package printtransport

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofrs/flock"
)

func acquireOSGuard(name string) (func() error, error) {
	lock := flock.New(filepath.Join(os.TempDir(), "vynic-print-"+strings.TrimPrefix(name, nativeGuardPrefix)+".lock"))
	ok, err := lock.TryLock()
	if err != nil || !ok {
		closeErr := lock.Close()
		if err == nil {
			err = errors.New("physical printer is held by another process")
		}
		return nil, errors.Join(err, closeErr)
	}
	return lock.Close, nil
}
