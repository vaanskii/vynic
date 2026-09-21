//go:build windows

package setup

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/gofrs/flock"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
	"vynic.local/edge/internal/updater"
)

type NativeHost struct{}

func NativeLayout() (Layout, error) {
	if windows.GetCurrentProcessToken().IsElevated() {
		return Layout{}, errors.New("Run VynicSetup normally as the POS user, not as administrator. This installation is per-user")
	}
	root, e := windows.KnownFolderPath(windows.FOLDERID_LocalAppData, 0)
	if e != nil {
		return Layout{}, e
	}
	root, e = installRoot(root)
	return Layout{root}, e
}
func (NativeHost) Secure(l Layout) error {
	u, e := windows.GetCurrentProcessToken().GetTokenUser()
	if e != nil {
		return e
	}
	sd, e := windows.SecurityDescriptorFromString("D:P(A;OICI;FA;;;" + u.User.Sid.String() + ")(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)")
	if e != nil {
		return e
	}
	acl, _, e := sd.DACL()
	if e != nil {
		return e
	}
	return filepath.WalkDir(l.Root, func(p string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if e = checkReparse(p); e != nil {
			return e
		}
		return windows.SetNamedSecurityInfo(p, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION, nil, nil, acl, nil)
	})
}
func noPOS() error {
	h, e := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if e != nil {
		return e
	}
	defer windows.CloseHandle(h)
	p := windows.ProcessEntry32{Size: uint32(unsafe.Sizeof(windows.ProcessEntry32{}))}
	for e = windows.Process32First(h, &p); e == nil; e = windows.Process32Next(h, &p) {
		if strings.EqualFold(windows.UTF16ToString(p.ExeFile[:]), updater.Executable) {
			return errors.New("Close Vynic POS normally before setup/repair/uninstall; open restaurant data will be retained")
		}
	}
	if !errors.Is(e, windows.ERROR_NO_MORE_FILES) {
		return e
	}
	return nil
}
func status(ctx context.Context, c updater.Config) (updater.State, error) {
	var st updater.State
	r, e := http.NewRequestWithContext(ctx, "GET", "http://"+c.Listen+"/v1/status", nil)
	if e != nil {
		return st, e
	}
	r.Header.Set("Authorization", "Bearer "+c.Token)
	client := &http.Client{Timeout: 2 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("IPC redirect refused") }}
	res, e := client.Do(r)
	if e != nil {
		return st, e
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return st, fmt.Errorf("local updater HTTP %d", res.StatusCode)
	}
	e = json.NewDecoder(io.LimitReader(res.Body, 16<<10)).Decode(&st)
	return st, e
}
func (NativeHost) Quiesce(ctx context.Context, l Layout, r Receipt, uninstall bool) error {
	if e := noPOS(); e != nil {
		return e
	}
	// Removal needs stopped processes, not a successfully recovered binary journal.
	// The caller subsequently acquires the updater lock before deleting any files.
	if st, e := status(ctx, r.Config); !uninstall && e == nil && (st.Status == "INSTALLING" || st.Status == "RESTARTING") {
		return errors.New("POS install/recovery in progress; wait for its result")
	}
	if e := writeAtomic(l.StopFile(), []byte("stop\n")); e != nil {
		return e
	}
	deadline := time.Now().Add(30 * time.Second)
	for {
		f := flock.New(filepath.Join(l.Root, "state", "host.lock"))
		ok, e := f.TryLock()
		if e != nil {
			return e
		}
		if ok {
			e = f.Unlock()
			if e != nil {
				return e
			}
			break
		}
		if time.Now().After(deadline) {
			return errors.New("Edge did not stop cleanly; inspect logs and retry; no process was force-killed")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(200 * time.Millisecond):
		}
	}
	return noPOS()
}

const runKey = `Software\Microsoft\Windows\CurrentVersion\Run`
const uninstallKey = `Software\Microsoft\Windows\CurrentVersion\Uninstall\VynicPOS`
const runName = "Vynic POS Edge"

func quote(s string) string { return syscall.EscapeArg(s) }
func (NativeHost) Integrate(l Layout) error {
	if e := checkRegistration(l); e != nil {
		return e
	}

	k, _, e := registry.CreateKey(registry.CURRENT_USER, runKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if e != nil {
		return e
	}
	defer k.Close()
	want := quote(l.Setup()) + " --host"
	if old, _, e := k.GetStringValue(runName); e == nil && old != want {
		return errors.New("unrelated startup registration exists")
	} else if e != nil && !errors.Is(e, registry.ErrNotExist) {
		return e
	}
	if e = shortcuts(l, false); e != nil {
		return e
	}
	if e = k.SetStringValue(runName, want); e != nil {
		return e
	}
	u, _, e := registry.CreateKey(registry.CURRENT_USER, uninstallKey, registry.SET_VALUE)
	if e != nil {
		return e
	}
	defer u.Close()
	for name, value := range map[string]string{"DisplayName": "Vynic POS", "Publisher": "Vynic", "InstallLocation": l.Root, "UninstallString": quote(l.Setup()) + " --uninstall", "ModifyPath": quote(l.Setup()) + " --repair", "DisplayIcon": l.Setup()} {
		if e = u.SetStringValue(name, value); e != nil {
			return e
		}
	}
	return u.SetDWordValue("NoModify", 0)
}
func (NativeHost) RemoveIntegration(l Layout) error {
	if e := checkRegistration(l); e != nil {
		return e
	}

	if e := shortcuts(l, true); e != nil {
		return e
	}
	k, e := registry.OpenKey(registry.CURRENT_USER, runKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if e == nil {
		defer k.Close()
		old, _, e := k.GetStringValue(runName)
		if e == nil {
			if old != quote(l.Setup())+" --host" {
				return errors.New("startup owner mismatch")
			}
			if e = k.DeleteValue(runName); e != nil {
				return e
			}
		} else if !errors.Is(e, registry.ErrNotExist) {
			return e
		}
	} else if !errors.Is(e, registry.ErrNotExist) {
		return e
	}
	e = registry.DeleteKey(registry.CURRENT_USER, uninstallKey)
	if errors.Is(e, registry.ErrNotExist) {
		return nil
	}
	return e
}
func checkRegistration(l Layout) error {
	k, e := registry.OpenKey(registry.CURRENT_USER, uninstallKey, registry.QUERY_VALUE)
	if errors.Is(e, registry.ErrNotExist) {
		return nil
	}
	if e != nil {
		return e
	}
	defer k.Close()
	location, _, e := k.GetStringValue("InstallLocation")
	if e != nil {
		return e
	}
	if !strings.EqualFold(location, l.Root) {
		return errors.New("unrelated Vynic uninstall registration exists")
	}
	return nil
}
func legacyCheck(l Layout) error {
	if _, e := os.Stat(l.Receipt()); e == nil {
		return nil
	}
	if k, e := registry.OpenKey(registry.CURRENT_USER, uninstallKey, registry.QUERY_VALUE); e == nil {
		k.Close()
		return errors.New("Vynic registration exists without its installation receipt; contact support before reinstalling")
	} else if !errors.Is(e, registry.ErrNotExist) {
		return e
	}
	drive := os.Getenv("SystemDrive")
	if drive == "" {
		drive = "C:"
	}
	pd, e := windows.KnownFolderPath(windows.FOLDERID_ProgramData, 0)
	if e != nil {
		return e
	}
	for _, p := range []string{filepath.Join(drive+`\`, "Vynic", "App"), filepath.Join(pd, "Vynic", "Deployment")} {
		if _, e = os.Stat(p); e == nil {
			return fmt.Errorf("legacy POS deployment detected at %s; disable its deployment/startup integration through support before a managed migration; restaurant data is untouched", p)
		} else if !os.IsNotExist(e) {
			return e
		}
	}
	return noPOS()
}
func LegacyCheck(l Layout) error { return legacyCheck(l) }

// Supervise runs in the interactive user's session. One file lock covers its
// children; a graceful stop marker stops Edge without killing POS or Manager.
func Supervise(l Layout) error {
	if e := rejectLinks(l.Root); e != nil {
		return e
	}
	if _, e := os.Stat(l.Maintenance()); e == nil {
		return errors.New("installation maintenance in progress")
	}
	lock := flock.New(filepath.Join(l.Root, "state", "host.lock"))
	ok, e := lock.TryLock()
	if e != nil {
		return e
	}
	if !ok {
		return nil
	}
	defer lock.Unlock()
	// Stop requests are cleared only by EnsureHost, never by a stale logon process.
	if _, e = os.Stat(l.StopFile()); e == nil {
		return nil
	}
	if e = os.MkdirAll(filepath.Join(l.Root, "logs"), 0700); e != nil {
		return e
	}
	f, e := os.OpenFile(filepath.Join(l.Root, "logs", "edge.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer f.Close()
	for attempt := 0; attempt < 5; attempt++ {
		if _, e = os.Stat(l.Maintenance()); e == nil {
			return nil
		}
		if _, e = os.Stat(l.StopFile()); e == nil {
			return nil
		}
		r, e := Load(l)
		if e != nil {
			return e
		}
		if r.Status != "installed" {
			return errors.New("installation not active")
		}
		var cfg updater.Config
		if e = readJSON(l.Config(), &cfg); e != nil {
			return e
		}
		a, _ := json.Marshal(cfg)
		b, _ := json.Marshal(r.Config)
		if string(a) != string(b) {
			return errors.New("updater config differs from installation receipt; repair required")
		}
		c := exec.Command(l.Edge(r.EdgeVersion), "host", "--data", l.EdgeData(), "--pos-updater-config", l.Config(), "--shutdown-file", l.StopFile())
		c.Dir = filepath.Dir(l.Edge(r.EdgeVersion))
		c.Stdout = f
		c.Stderr = f
		c.SysProcAttr = &syscall.SysProcAttr{CreationFlags: windows.CREATE_NO_WINDOW}
		e = c.Run()
		if _, se := os.Stat(l.StopFile()); se == nil {
			return nil
		}
		fmt.Fprintf(f, "%s host exited: %v\n", time.Now().UTC().Format(time.RFC3339), e)
		time.Sleep(time.Duration(attempt+1) * time.Second)
	}
	return errors.New("Edge repeatedly failed; inspect logs/edge.log and use Repair")
}
func EnsureHost(ctx context.Context, l Layout, launch bool) error {
	return ensureHost(ctx, l, launch, nil)
}
func ensureHost(ctx context.Context, l Layout, launch bool, report func(UpdateProgress)) error {
	if e := rejectLinks(l.Root); e != nil {
		return e
	}
	if _, e := os.Stat(l.Maintenance()); e == nil {
		return errors.New("setup/repair in progress")
	}
	r, e := Load(l)
	if e != nil {
		return e
	}
	if r.Status != "installed" {
		return errors.New("Vynic is removed/incomplete; run Repair")
	}
	// Serialize explicit launches against maintenance; the long-lived supervisor
	// uses a separate lock and refuses a maintenance marker.
	lock := flock.New(filepath.Join(l.Root, "setup.lock"))
	ok, e := lock.TryLock()
	if e != nil {
		return e
	}
	if !ok {
		return errors.New("setup is running")
	}
	defer lock.Unlock()
	// Admission is serialized, but health observation must not own the setup
	// lock for minutes after the daemon accepts launch.
	waitHealth := func(previous string) error {
		if e := lock.Unlock(); e != nil {
			return e
		}
		return waitPOSHealth(ctx, l, r.Config, previous, report)
	}
	if e = os.Remove(l.StopFile()); e != nil && !os.IsNotExist(e) {
		return e
	}
	if _, e = status(ctx, r.Config); e != nil {
		c := exec.Command(l.Setup(), "--host")
		c.SysProcAttr = &syscall.SysProcAttr{CreationFlags: windows.CREATE_NO_WINDOW}
		if e = c.Start(); e != nil {
			return e
		}
		go func() { _ = c.Wait() }()
		deadline := time.Now().Add(20 * time.Second)
		for {
			if _, e = status(ctx, r.Config); e == nil {
				break
			}
			if time.Now().After(deadline) {
				return errors.New("Edge startup failed; see logs/edge.log and Repair")
			}
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(250 * time.Millisecond):
			}
		}
	}
	if launch {
		st, e := status(ctx, r.Config)
		if e != nil {
			return e
		}
		running, e := managedPOSRunning(posExecutable(l, st))
		if e != nil {
			return e
		}
		if running {
			if st.Status == "FAILED" && !st.StartupVerified {
				return fmt.Errorf("POS startup failed: %s; inspect logs and close POS before Repair", st.Reason)
			}
			if report != nil && !st.StartupVerified {
				return waitHealth(st.Reason)
			}
			return nil
		}
		if e = noPOS(); e != nil {
			return e
		}
		deadline := time.Now().Add(30 * time.Second)
		for {
			e = updater.LaunchCurrent(r.Config)
			if e == nil {
				return waitHealth(st.Reason)
			}
			if !strings.Contains(e.Error(), "updater busy") || time.Now().After(deadline) {
				return e
			}
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(250 * time.Millisecond):
			}
		}
	}
	return nil
}

func managedPOSRunning(path string) (bool, error) {
	h, e := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if e != nil {
		return false, e
	}
	defer windows.CloseHandle(h)
	p := windows.ProcessEntry32{Size: uint32(unsafe.Sizeof(windows.ProcessEntry32{}))}
	for e = windows.Process32First(h, &p); e == nil; e = windows.Process32Next(h, &p) {
		if strings.EqualFold(windows.UTF16ToString(p.ExeFile[:]), updater.Executable) {
			if (updater.NativeProcess{}).Validate(int(p.ProcessID), path) == nil {
				return true, nil
			}
		}
	}
	if !errors.Is(e, windows.ERROR_NO_MORE_FILES) {
		return false, e
	}
	return false, nil
}

// A launch ACK only schedules startup. Surface a failed process/health check to
// the installer/shortcut caller instead of reporting installation launch success.
func waitPOSHealth(ctx context.Context, l Layout, c updater.Config, previousReason string, report func(UpdateProgress)) error {
	started := time.Now()
	lastSecond := -1
	deadline := time.Now().Add(250 * time.Second)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(250 * time.Millisecond):
		}
		if _, e := os.Stat(l.Maintenance()); e == nil {
			return errors.New("POS launch cancelled by installation maintenance")
		}
		st, e := status(ctx, c)
		elapsed := int(time.Since(started).Seconds())
		if report != nil && elapsed != lastSecond {
			message := "Checking local data and POS startup health. Edge requires a 30-second stability check."
			if e != nil {
				message = "Waiting for the local update service to respond…"
			}
			if st.Swap == "restoring" {
				message = "Restoring the previous POS release and checking its startup health…"
			}
			report(UpdateProgress{Message: fmt.Sprintf("%s\nElapsed: %ds", message, elapsed)})
			lastSecond = elapsed
		}
		if e == nil {
			running, re := managedPOSRunning(posExecutable(l, st))
			if re != nil {
				return re
			}
			if !running && time.Since(started) > 5*time.Second {
				return fmt.Errorf("POS exited before startup health completed; %s", st.Reason)
			}
			if st.StartupVerified && running {
				return nil
			}
			if st.Status == "FAILED" && st.Reason != "" && st.Reason != previousReason {
				return fmt.Errorf("POS startup failed: %s; inspect logs/edge.log and use Repair", st.Reason)
			}
		}
		if time.Now().After(deadline) {
			return errors.New("POS did not confirm startup health; inspect the POS window and logs, then close POS normally before Repair")
		}
	}
}

func posExecutable(l Layout, st updater.State) string {
	if st.Layout == 0 {
		return filepath.Join(l.POS(), "releases", st.Current, updater.Executable)
	}
	return updater.CurrentExecutable(l.POS())
}
