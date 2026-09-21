//go:build windows

package setup

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNativeShortcutRoundtripAndForeignOwnership(t *testing.T) {
	dir := t.TempDir()
	l := Layout{Root: filepath.Join(dir, "Vynic")}
	if e := shortcutFolders(l, false, []string{dir}); e != nil {
		t.Fatal(e)
	}
	if e := shortcutFolders(l, false, []string{dir}); e != nil {
		t.Fatal(e)
	}
	other := Layout{Root: filepath.Join(dir, "Other")}
	if e := shortcutFolders(other, true, []string{dir}); e == nil {
		t.Fatal("foreign shortcut removed")
	}
	if e := shortcutFolders(l, true, []string{dir}); e != nil {
		t.Fatal(e)
	}
	if _, e := os.Stat(filepath.Join(dir, "Vynic POS.lnk")); !os.IsNotExist(e) {
		t.Fatal(e)
	}
}
