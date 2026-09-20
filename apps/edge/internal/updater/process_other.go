//go:build !windows

package updater

import "errors"

type NativeProcess struct{}

func (NativeProcess) Validate(int, string) error {
	return errors.New("POS installation requires Windows")
}
func (NativeProcess) Stop(string) error { return errors.New("POS installation requires Windows") }
func (NativeProcess) Start(string, []string) (int, error) {
	return 0, errors.New("POS installation requires Windows")
}
