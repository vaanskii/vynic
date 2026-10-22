//go:build windows

package printerdaemon

import (
	"context"
	"errors"
	"os/exec"
	"path/filepath"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc/mgr"
)

// WindowsInstallerBackend is used only by a later explicit reviewed Apply. This
// package never calls it in PlanOnly and never automatically elevates.
type WindowsInstallerBackend struct{}

func (WindowsInstallerBackend) IsAdmin(context.Context) (bool, error) {
	administrators, err := windows.CreateWellKnownSid(windows.WinBuiltinAdministratorsSid)
	if err != nil {
		return false, err
	}
	member, err := windows.Token(0).IsMember(administrators)
	return member && windows.GetCurrentProcessToken().IsElevated(), err
}
func (WindowsInstallerBackend) AccountSID(_ context.Context, account string) (string, error) {
	sid, _, _, err := windows.LookupSID("", account)
	if err != nil {
		return "", err
	}
	return sid.String(), nil
}

func (WindowsInstallerBackend) Inspect(_ context.Context, name string) (*InstalledService, error) {
	handle, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return nil, err
	}
	defer windows.CloseServiceHandle(handle)
	pointer, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	serviceHandle, err := windows.OpenService(handle, pointer, windows.SERVICE_QUERY_CONFIG)
	if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	service := &mgr.Service{Name: name, Handle: serviceHandle}
	defer service.Close()
	config, err := service.Config()
	if err != nil {
		return nil, err
	}
	arguments, err := windows.DecomposeCommandLine(config.BinaryPathName)
	if err != nil || len(arguments) == 0 {
		return nil, errors.Join(ErrConfig, err)
	}
	sid, _, _, err := windows.LookupSID("", config.ServiceStartName)
	if err != nil {
		return nil, err
	}
	return &InstalledService{ExecutablePath: arguments[0], Arguments: arguments[1:], AccountName: config.ServiceStartName, SID: sid.String(), ServiceType: config.ServiceType, StartType: config.StartType}, nil
}

func (WindowsInstallerBackend) SystemSCPath() (string, error) {
	directory, err := windows.GetSystemDirectory()
	if err != nil {
		return "", err
	}
	path := filepath.Join(directory, "sc.exe")
	if err = noReparse(path); err != nil {
		return "", err
	}
	return path, nil
}

func (backend WindowsInstallerBackend) RunSC(ctx context.Context, path string, args []string) error {
	if err := validateCreateArguments(args); err != nil {
		return err
	}
	exact, err := backend.SystemSCPath()
	if err != nil || path != exact {
		return errors.Join(ErrConfig, err)
	}
	// This exact executable/argv has no shell, PowerShell, PATH search or eval.
	// Only create-stopped is permitted; no start/delete/change/account grants.
	command := exec.CommandContext(ctx, exact, args...)
	if output, err := command.CombinedOutput(); err != nil {
		return errors.New("reviewed sc.exe create failed: " + err.Error() + ": " + string(output))
	}
	return nil
}
