//go:build windows

package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"vynic.local/edge/internal/setup"
)

func dialog(message, progress string, buttons ...button) (int, error) {
	return nativeDialog(message, buttons, nil)
}
func showError(e error) {
	// Error reporting is native and independent of the wizard window.
	text, _ := windows.UTF16PtrFromString(e.Error())
	title, _ := windows.UTF16PtrFromString("Vynic Setup")
	windows.NewLazySystemDLL("user32.dll").NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10|0x10000)
}

func startupLog() (*os.File, error) {
	l, e := setup.NativeLayout()
	if e != nil {
		return nil, e
	}
	if e = setup.PrepareRoot(l, setup.NativeHost{}); e != nil {
		return nil, e
	}
	if e = os.MkdirAll(filepath.Join(l.Root, "logs"), 0700); e != nil {
		return nil, e
	}
	if e = (setup.NativeHost{}).Secure(l); e != nil {
		return nil, e
	}
	return os.OpenFile(filepath.Join(l.Root, "logs", "setup.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
}
func withProgress(l setup.Layout, work func(func(string)) error) error {
	log, e := os.OpenFile(filepath.Join(l.Root, "logs", "setup.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer log.Close()
	_, e = nativeDialog("Preparing Vynic installation…", nil, func(report func(string)) error {
		result := work(func(s string) { fmt.Fprintf(log, "%s %s\n", time.Now().UTC().Format(time.RFC3339), s); report(s) })
		if result != nil {
			fmt.Fprintf(log, "operation failed: %v\n", result)
		}
		return result
	})
	return e
}

func offerUpdate(ctx context.Context, l setup.Layout) error {
	log, e := os.OpenFile(filepath.Join(l.Root, "logs", "setup.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer log.Close()
	var result setup.UpdateOfferResult
	_, e = nativeProgressPage("Vynic POS Update", "Connecting to the local update service…", nil, nil, func(report func(setup.UpdateProgress)) error {
		var err error
		result, err = setup.OfferPOSUpdate(ctx, l, func(p setup.UpdateProgress) {
			fmt.Fprintf(log, "%s %s\n", time.Now().UTC().Format(time.RFC3339), p.Message)
			report(p)
		})
		return err
	})
	if e != nil {
		return e
	}
	buttons := []button{{"Close", 0}}
	if result.Ready {
		buttons = []button{{"Open POS", 4}, {"Later", 0}}
	}
	action, e := nativePage("Vynic POS Update", result.Message, nil, buttons, nil)
	if e != nil {
		return e
	}
	if action == 4 {
		return openVynic(ctx, l)
	}
	return nil
}

func openVynic(ctx context.Context, l setup.Layout) error {
	// A shortcut launch opens only the POS window. Keep waiting for authenticated
	// startup health without showing the installer; nativeMain logs and displays
	// any failure. Installation/repair operations still have their progress UI.
	return setup.EnsureHost(ctx, l, true)
}
func nativeMain() {
	o, e := parseStartup(os.Args[1:])
	log, logErr := startupLog()
	if log != nil {
		defer log.Close()
		fmt.Fprintf(log, "%s startup mode=%s setup=%s\n", time.Now().UTC().Format(time.RFC3339), o.mode, setupVersion)
	}
	if e == nil {
		e = logErr
	}
	if e == nil {
		e = runWindows(o)
	}
	if e != nil {
		if log != nil {
			fmt.Fprintf(log, "%s startup failed: %v\n", time.Now().UTC().Format(time.RFC3339), e)
			log.Sync()
			e = fmt.Errorf("%w\n\nDiagnostics: %s", e, log.Name())
		}
		if o.mode != "host" {
			showError(e)
		}
		os.Exit(1)
	}
}
func runWindows(o startupOptions) error {
	if o.mode != "host" && o.mode != "launch" {
		user, e := windows.GetCurrentProcessToken().GetTokenUser()
		if e != nil {
			return e
		}
		handle, e := windows.CreateMutex(nil, false, utf("Local\\Vynic.Setup.Wizard."+user.User.Sid.String()))
		if handle != 0 {
			defer windows.CloseHandle(handle)
		}
		if errors.Is(e, windows.ERROR_ALREADY_EXISTS) {
			return errors.New("Vynic Setup is already open for this Windows account")
		}
		if e != nil {
			return e
		}
	}

	l, e := setup.NativeLayout()
	if e != nil {
		return e
	}
	if o.mode == "host" {
		return setup.Supervise(l)
	}
	ctx := context.Background()
	if o.mode == "launch" {
		return openVynic(ctx, l)
	}
	if e = setup.LegacyCheck(l); e != nil {
		return e
	}
	r, readErr := setup.Load(l)
	exists := readErr == nil
	if readErr != nil && !os.IsNotExist(readErr) {
		return readErr
	}
	if exists && o.distribution != "" {
		return errors.New("existing installation trust cannot be changed by --distribution; Repair uses the provisioned public keys")
	}
	action := 1
	if o.mode == "repair" {
		action = 2
	} else if o.mode == "uninstall" {
		action = 3
	} else if exists {
		if r.Status == "installed" {
			action, e = maintenanceWizard(l)
		} else if r.Status == "removed" {
			action, e = dialog("Install Vynic POS? Your saved restaurant data and identity will be preserved.", "", button{"Install", 2}, button{"Uninstall", 3}, button{"Cancel", 0})
		} else {
			action, e = dialog("Vynic installation is incomplete. Repair restores applications and keeps restaurant data.", "", button{"Repair", 2}, button{"Uninstall", 3}, button{"Cancel", 0})
		}
	} else {
		var confirmed bool
		l, confirmed, e = installWizard(l)
		if !confirmed && e == nil {
			return nil
		}
	}
	if e != nil {
		return e
	}
	if action == 0 {
		return nil
	}
	if action == 5 {
		return offerUpdate(ctx, l)
	}
	if action == 4 {
		return openVynic(ctx, l)
	}
	d := r.Distribution
	if !exists {
		d, e = distribution(o.distribution)
		if e != nil {
			return e
		}
	}
	source, e := os.Executable()
	if e != nil {
		return e
	}
	i := setup.Installer{Layout: l, Distribution: d, Host: setup.NativeHost{}, SetupSource: source}
	if action == 3 {
		yes, e := dialog("Remove Vynic POS and Edge application releases?\n\nRestaurant data, local identities, update history and support diagnostics will be kept. The small setup utility is retained for Repair. Data deletion is a separate support operation.", "", button{"Uninstall", 3}, button{"Cancel", 0})
		if e != nil {
			return e
		}
		if yes != 3 {
			return nil
		}
		e = withProgress(l, func(report func(string)) error { i.Report = report; return i.Uninstall(ctx) })
		if e != nil {
			return e
		}
		_, e = dialog("Vynic applications were removed. Restaurant data was retained.", "", button{"Close", 1})
		return e
	}
	e = withProgress(l, func(report func(string)) error { i.Report = report; return i.Install(ctx, action == 2) })
	if e != nil {
		if exists && r.Status == "installed" {
			e = errors.Join(e, setup.EnsureHost(ctx, l, false))
		}
		return fmt.Errorf("%w\n\nDiagnostics: %s", e, filepath.Join(l.Root, "logs", "setup.log"))
	}
	if e = setup.EnsureHost(ctx, l, false); e != nil {
		return e
	}
	choice, e := nativePage("Installation complete", "Vynic POS is ready.\n\nUse the one-time device code from your restaurant account to connect this terminal.", nil, []button{{"Launch Vynic POS", 4}, {"Finish", 0}}, nil)
	if e != nil {
		return e
	}
	if choice == 4 {
		return openVynic(ctx, l)
	}
	return nil
}
