//go:build !windows

package printerdaemon

import (
	"context"
	"errors"
)

type WindowsInstallerBackend struct{}

func (WindowsInstallerBackend) IsAdmin(context.Context) (bool, error) {
	return false, errors.New("explicit Windows Apply requires Windows")
}
func (WindowsInstallerBackend) AccountSID(context.Context, string) (string, error) {
	return "", errors.New("Windows account lookup unavailable")
}
func (WindowsInstallerBackend) Inspect(context.Context, string) (*InstalledService, error) {
	return nil, errors.New("Windows SCM unavailable")
}
func (WindowsInstallerBackend) SystemSCPath() (string, error) {
	return "", errors.New("Windows System32 unavailable")
}
func (WindowsInstallerBackend) RunSC(context.Context, string, []string) error {
	return errors.New("Windows SCM Apply unavailable")
}
