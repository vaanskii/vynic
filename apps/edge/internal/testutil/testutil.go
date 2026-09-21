// Package testutil creates synthetic signing keys only for isolated tests.
package testutil

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"github.com/google/uuid"
	"testing"
	"time"
	"vynic.local/edge/internal/store"
)

func Bound(t *testing.T, dir string) (*store.Store, store.Identity) {
	t.Helper()
	s, err := store.Open(dir, true)
	if err != nil {
		t.Fatal(err)
	}
	id, err := s.Init()
	if err != nil {
		t.Fatal(err)
	}
	id.VenueID = uuid.NewString()
	grant, key := Grant(t, id, time.Now().Unix(), time.Now().Unix()+600)
	if err = s.Bind(grant, key); err != nil {
		t.Fatal(err)
	}
	return s, id
}
func Grant(t *testing.T, id store.Identity, issued, expires int64) (string, []byte) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(store.Grant{Version: 1, Purpose: "vynic-edge-foundation", Mode: "FOUNDATION_ONLY", InstallationID: id.InstallationID, PublicKey: id.PublicKey, VenueID: id.VenueID, IssuedAt: issued, ExpiresAt: expires})
	if err != nil {
		t.Fatal(err)
	}
	p := base64.RawURLEncoding.EncodeToString(b)
	raw := p + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(priv, []byte(p)))
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	return raw, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})
}
