// Offline/CI release tool. This binary is not part of the POS/Edge distribution.
package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"os"
	"time"
	"vynic.local/edge/internal/updater"
)

func run() error {
	manifest := flag.String("manifest", "", "unsigned metadata JSON")
	artifact := flag.String("artifact", "", "complete Windows POS bundle zip")
	private := flag.String("private-key", "", "external PKCS8 Ed25519 PEM (never commit)")
	keyID := flag.String("key-id", "", "trusted release key ID")
	flag.Parse()
	if *keyID == "" {
		return fmt.Errorf("key ID required")
	}
	raw, e := os.ReadFile(*manifest)
	if e != nil {
		return e
	}
	var m updater.Manifest
	if e = json.Unmarshal(raw, &m); e != nil {
		return e
	}
	f, e := os.Open(*artifact)
	if e != nil {
		return e
	}
	h := sha256.New()
	m.Size, e = io.Copy(h, io.LimitReader(f, updater.MaxArtifact+1))
	e2 := f.Close()
	if e != nil {
		return e
	}
	if e2 != nil {
		return e2
	}
	m.SHA256 = hex.EncodeToString(h.Sum(nil))
	keyBytes, e := os.ReadFile(*private)
	if e != nil {
		return e
	}
	block, _ := pem.Decode(keyBytes)
	if block == nil {
		return fmt.Errorf("PKCS8 PEM required")
	}
	key, e := x509.ParsePKCS8PrivateKey(block.Bytes)
	if e != nil {
		return e
	}
	signer, ok := key.(ed25519.PrivateKey)
	if !ok {
		return fmt.Errorf("Ed25519 key required")
	}
	payload, e := json.Marshal(m)
	if e != nil {
		return e
	}
	envelope := updater.Envelope{KeyID: *keyID, Payload: base64.StdEncoding.EncodeToString(payload), Signature: base64.StdEncoding.EncodeToString(ed25519.Sign(signer, append([]byte("VYNIC-POS-RELEASE-v1\n"), payload...)))}
	out, e := json.Marshal(envelope)
	if e != nil {
		return e
	}
	_, e = updater.Verify(out, map[string]updater.TrustedKey{*keyID: {Public: base64.StdEncoding.EncodeToString(signer.Public().(ed25519.PublicKey)), Expires: time.Now().Add(time.Hour)}}, m.Channel, "0.0.0", 0, time.Now())
	if e != nil {
		return e
	}
	_, e = fmt.Fprintln(os.Stdout, string(out))
	return e
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
