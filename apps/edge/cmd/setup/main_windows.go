//go:build windows

package main

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"vynic.local/edge/internal/setup"
)

//go:embed dialog.ps1
var dialogScript string

type button struct {
	Text string `json:"text"`
	ID   int    `json:"id"`
}

func dialogCommand(message, progress string, buttons ...button) (*exec.Cmd, error) {
	sys, e := windows.GetSystemDirectory()
	if e != nil {
		return nil, e
	}
	raw, e := json.Marshal(map[string]any{"message": message, "progress": progress, "buttons": buttons})
	if e != nil {
		return nil, e
	}
	c := exec.Command(filepath.Join(sys, "WindowsPowerShell", "v1.0", "powershell.exe"), "-NoProfile", "-NonInteractive", "-STA", "-Command", dialogScript)
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	c.Env = append(os.Environ(), "VYNIC_SETUP_UI="+string(raw))
	return c, nil
}
func dialog(message, progress string, buttons ...button) (int, error) {
	c, e := dialogCommand(message, progress, buttons...)
	if e != nil {
		return 0, e
	}
	out, e := c.CombinedOutput()
	if e != nil {
		return 0, fmt.Errorf("Windows setup UI failed: %w: %s", e, out)
	}
	return strconv.Atoi(strings.TrimSpace(string(out)))
}
func showError(e error) {
	if _, de := dialog(e.Error(), "", button{"Close", 1}); de != nil {
		// Last-resort native message box when PowerShell/WinForms is unavailable.
		text, _ := windows.UTF16PtrFromString(e.Error() + "\n" + de.Error())
		title, _ := windows.UTF16PtrFromString("Vynic Setup")
		windows.NewLazySystemDLL("user32.dll").NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
	}
}
func withProgress(l setup.Layout, work func(func(string)) error) error {
	if e := setup.PrepareRoot(l, setup.NativeHost{}); e != nil {
		return e
	}
	if e := os.MkdirAll(filepath.Join(l.Root, "logs"), 0700); e != nil {
		return e
	}
	if e := (setup.NativeHost{}).Secure(l); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Join(l.Root, "logs"), "setup-progress-*.json")
	if e != nil {
		return e
	}
	path := f.Name()
	f.Close()
	defer os.Remove(path)
	log, e := os.OpenFile(filepath.Join(l.Root, "logs", "setup.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer log.Close()
	write := func(message string, done bool) {
		fmt.Fprintf(log, "%s %s\n", time.Now().UTC().Format(time.RFC3339), message)
		b, _ := json.Marshal(map[string]any{"message": message, "done": done})
		if e := os.WriteFile(path, b, 0600); e != nil {
			fmt.Fprintln(log, "progress display:", e)
		}
	}
	write("Preparing Vynic installation…", false)
	c, e := dialogCommand("Preparing Vynic installation…", path)
	if e != nil {
		return e
	}
	var output bytes.Buffer
	c.Stdout = &output
	c.Stderr = &output
	if e = c.Start(); e != nil {
		return e
	}
	uiDone := make(chan error, 1)
	go func() { uiDone <- c.Wait() }()
	result := work(func(s string) { write(s, false) })
	if result != nil {
		write(result.Error(), true)
	} else {
		write("Completed", true)
	}
	select {
	case e = <-uiDone:
	case <-time.After(3 * time.Second):
		// The child is our own progress UI only; a full disk must not trap the UI.
		e = errors.Join(errors.New("progress window did not close; operation result is in setup.log"), c.Process.Kill(), <-uiDone)
	}
	if e != nil {
		return errors.Join(result, fmt.Errorf("setup progress UI: %w: %s", e, output.String()))
	}
	return result
}

func openVynic(ctx context.Context, l setup.Layout) error {
	return withProgress(l, func(report func(string)) error {
		report("Starting Vynic POS…")
		return setup.EnsureHost(ctx, l, true)
	})
}
func nativeMain() {
	if e := runWindows(); e != nil {
		showError(e)
		os.Exit(1)
	}
}
func runWindows() error {
	config := flag.String("distribution", "", "explicit administrator-supplied public distribution config")
	launch := flag.Bool("launch", false, "open current POS through Edge")
	host := flag.Bool("host", false, "interactive-user background Edge supervisor")
	repair := flag.Bool("repair", false, "repair existing installation")
	uninstall := flag.Bool("uninstall", false, "remove applications; preserve restaurant data")
	flag.Parse()
	actions := 0
	for _, set := range []bool{*launch, *host, *repair, *uninstall} {
		if set {
			actions++
		}
	}
	if actions > 1 || flag.NArg() != 0 {
		return errors.New("choose only one of --launch, --host, --repair or --uninstall")
	}
	l, e := setup.NativeLayout()
	if e != nil {
		return e
	}
	if *host {
		return setup.Supervise(l)
	}
	ctx := context.Background()
	if *launch {
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
	if exists && *config != "" {
		return errors.New("existing installation trust cannot be changed by --distribution; Repair uses the provisioned public keys")
	}
	action := 1
	if *repair {
		action = 2
	} else if *uninstall {
		action = 3
	} else if exists {
		if r.Status == "installed" {
			action, e = dialog("Vynic is already installed. Repair preserves restaurant data and updater history.\n\nUninstall removes applications and startup integration; restaurant data is retained.", "", button{"Open Vynic", 4}, button{"Repair", 2}, button{"Uninstall", 3}, button{"Cancel", 0})
		} else {
			action, e = dialog("Vynic installation is incomplete or its application files were removed.\n\nRepair restores the applications using retained identity and data. Uninstall keeps restaurant data.", "", button{"Repair", 2}, button{"Uninstall", 3}, button{"Cancel", 0})
		}
	} else {
		action, e = dialog("Install Vynic POS for this Windows account.\n\nSetup downloads and verifies Vynic Edge and the current POS baseline. The POS will ask for your Enrollment Code after launch.", "", button{"Install", 1}, button{"Cancel", 0})
	}
	if e != nil {
		return e
	}
	if action == 0 {
		return nil
	}
	if action == 4 {
		return openVynic(ctx, l)
	}
	d := r.Distribution
	if !exists {
		d, e = distribution(*config)
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
	choice, e := dialog("Vynic is installed. Open the POS to continue with your Enrollment Code.", "", button{"Open Vynic", 4}, button{"Close", 0})
	if e != nil {
		return e
	}
	if choice == 4 {
		return openVynic(ctx, l)
	}
	return nil
}
