//go:build windows

package setup

import (
	"testing"

	"golang.org/x/sys/windows"
)

// Core qualification must not accidentally hide per-user permission failures by
// running as Administrator. These fixtures use temporary paths and fake host
// integration; the shortcut roundtrip also stays in a temporary directory.
func TestCoreQualificationRunsUnelevated(t *testing.T) {
	if windows.GetCurrentProcessToken().IsElevated() {
		t.Fatal("run core qualification as a normal Windows user, not Administrator")
	}
}
