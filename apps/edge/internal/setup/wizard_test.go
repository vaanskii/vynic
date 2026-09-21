package setup

import (
	"path/filepath"
	"testing"
	"vynic.local/edge/internal/updater"
)

func TestPerUserDestinationBoundaries(t *testing.T) {
	base := t.TempDir()
	if e := validateDestination(base, filepath.Join(base, "Programs", "Vynic")); e != nil {
		t.Fatal(e)
	}
	for _, root := range []string{base, filepath.Dir(base), "relative", filepath.Join(base, "CON"), filepath.Join(base, "LPT²"), filepath.Join(base, "bad."), filepath.Join(base, "bad:stream")} {
		if e := validateDestination(base, root); e == nil {
			t.Fatalf("accepted unsafe destination %q", root)
		}
	}
}
func TestUpdateOfferDoesNotTreatRecoveryFailureAsSuccess(t *testing.T) {
	for _, status := range []string{"FAILED", "ROLLED_BACK"} {
		_, _, done, e := updateOfferStatus(updater.State{Status: status, Reason: "recovery blocked"}, 1)
		if !done || e == nil {
			t.Fatal(status)
		}
	}
	for _, status := range []string{"DOWNLOADING", "CHECKING", "SUCCESS", "UP_TO_DATE"} {
		_, _, done, e := updateOfferStatus(updater.State{Status: status}, 0)
		if done || e != nil {
			t.Fatal(status)
		}
	}
	message, _, done, e := updateOfferStatus(updater.State{Status: "READY_TO_INSTALL", Version: "1.0.1"}, 1)
	if !done || e != nil || message.Message == "" {
		t.Fatal(message, done, e)
	}
}
