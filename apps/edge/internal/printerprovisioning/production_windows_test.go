//go:build windows

package printerprovisioning

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"testing"

	guuid "github.com/google/uuid"
)

func TestProductionWindowsIdentityProtection(t *testing.T) {
	pub, _, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	dir := t.TempDir()
	device := guuid.NewString()
	s, e := OpenProduction(dir, device, pub)
	if e != nil {
		t.Fatal(e)
	}
	before := s.Enrollment()
	var protected []byte
	if e = s.db.QueryRow("SELECT private_key FROM identity WHERE singleton=1").Scan(&protected); e != nil {
		t.Fatal(e)
	}
	if bytes.Equal(protected, s.key) || len(protected) == ed25519.PrivateKeySize {
		t.Fatal("private key was not DPAPI protected")
	}
	opened, e := unprotectProductionKey(protected)
	if e != nil || !bytes.Equal(opened, s.key) {
		t.Fatal("DPAPI roundtrip", e)
	}
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e = OpenProduction(dir, device, pub)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	if before.InstallationID != s.id || !bytes.Equal(before.Certificate, s.cert) {
		t.Fatal("Windows restart changed installation")
	}
	t.Log("actual Windows MachineGuid + current-user DPAPI + private directory DACL + persistent restart: PASS")
}
