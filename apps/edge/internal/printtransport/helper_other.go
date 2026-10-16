//go:build !windows

package printtransport

import "errors"

func nativeSupported() bool { return false }
func launchHelper(HelperConfig) (helperProcess, error) {
	return nil, errors.New("Windows spooler helper requires Windows")
}
