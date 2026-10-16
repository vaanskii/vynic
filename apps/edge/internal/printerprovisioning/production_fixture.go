//go:build printerfixture

package printerprovisioning

import (
	"crypto/ed25519"
	"runtime"
	"time"
)

// OpenProcessFixture is excluded from distributable binaries. It uses the real
// identity/store/verification implementation with a disposable test machine on
// non-Windows; Windows still uses native MachineGuid, DPAPI and directory ACLs.
func OpenProcessFixture(dir, device string, key ed25519.PublicKey, now func() time.Time) (*ProductionStore, error) {
	machine := "disposable-process-fixture"
	if runtime.GOOS == "windows" {
		var e error
		machine, e = productionMachineID()
		if e != nil {
			return nil, e
		}
	}
	return openProduction(dir, device, key, machine, now)
}
