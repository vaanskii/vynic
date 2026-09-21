//go:build windows

package setup

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofrs/flock"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const locationKey = `Software\Vynic\Setup`

func installRoot(base string) (string, error) {
	k, e := registry.OpenKey(registry.CURRENT_USER, locationKey, registry.QUERY_VALUE)
	if errors.Is(e, registry.ErrNotExist) {
		return filepath.Join(base, "Vynic"), nil
	}
	if e != nil {
		return "", e
	}
	defer k.Close()
	root, _, e := k.GetStringValue("InstallRoot")
	if e != nil {
		return "", e
	}
	if e = validateDestination(base, root); e != nil {
		return "", e
	}
	return root, nil
}

// Per-user destination selection is only for a fresh install. Existing data and
// receipts never move implicitly, including after a data-preserving uninstall.
func SelectInstallRoot(current Layout, root string) (Layout, error) {
	base, e := windows.KnownFolderPath(windows.FOLDERID_LocalAppData, 0)
	if e != nil {
		return current, e
	}
	lock := flock.New(filepath.Join(base, "Vynic", "destination.lock"))
	locked, e := lock.TryLock()
	if e != nil {
		return current, e
	}
	if !locked {
		return current, errors.New("another destination selection is in progress")
	}
	defer lock.Unlock()
	latest, e := NativeLayout()
	if e != nil {
		return current, e
	}
	if !strings.EqualFold(latest.Root, current.Root) {
		return current, errors.New("installation location changed; restart Setup")
	}
	root = filepath.Clean(strings.TrimSpace(root))
	if e = validateDestination(base, root); e != nil {
		return current, e
	}
	if strings.EqualFold(root, current.Root) {
		return current, nil
	}
	if _, e = Load(current); e == nil {
		return current, errors.New("existing installations cannot change location; repair preserves their data")
	}
	if !os.IsNotExist(e) {
		return current, e
	}
	if e = rejectLinks(root); e != nil {
		return current, e
	}
	entries, e := os.ReadDir(root)
	if e != nil && !os.IsNotExist(e) {
		return current, e
	}
	if len(entries) > 0 {
		return current, errors.New("choose an empty, dedicated Vynic folder")
	}
	next := Layout{Root: root}
	if e = PrepareRoot(next, NativeHost{}); e != nil {
		return current, e
	}
	if e = os.MkdirAll(filepath.Join(root, "logs"), 0700); e != nil {
		return current, e
	}
	if e = (NativeHost{}).Secure(next); e != nil {
		return current, e
	}
	k, _, e := registry.CreateKey(registry.CURRENT_USER, locationKey, registry.SET_VALUE)
	if e != nil {
		return current, e
	}
	defer k.Close()
	if e = k.SetStringValue("InstallRoot", root); e != nil {
		return current, e
	}
	return next, nil
}
