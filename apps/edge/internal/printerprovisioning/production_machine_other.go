//go:build !windows

package printerprovisioning

import (
	"bytes"
	"errors"
	"os"
)

func productionMachineID() (string, error) {
	return "", errors.New("production printer installation identity requires Windows; tests use isolated machine identities")
}

func secureProductionDirectory(path string) error { return os.Chmod(path, 0700) }

// Non-Windows callers cannot OpenProduction; these helpers exist for isolated tests.
func protectProductionKey(raw []byte) ([]byte, error)   { return bytes.Clone(raw), nil }
func unprotectProductionKey(raw []byte) ([]byte, error) { return bytes.Clone(raw), nil }
