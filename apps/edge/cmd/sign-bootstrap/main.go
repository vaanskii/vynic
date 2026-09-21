// Offline bootstrap publisher. Shares the POS Ed25519 envelope/key model.
package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"
	"vynic.local/edge/internal/setup"
	"vynic.local/edge/internal/updater"
)

func run(args []string, output io.Writer) error {
	flags := flag.NewFlagSet("sign-bootstrap", flag.ContinueOnError)
	metadata := flags.String("manifest", "", "bootstrap metadata with an existing signed POS envelope")
	artifact := flags.String("edge-artifact", "", "Windows Edge ZIP")
	private := flags.String("private-key", "", "external Ed25519 PKCS8 PEM")
	keyID := flags.String("key-id", "", "pinned public key ID")
	distribution := flags.String("distribution", "", "public trust configuration (also trusts the embedded POS envelope)")
	if e := flags.Parse(args); e != nil {
		return e
	}
	raw, e := os.ReadFile(*metadata)
	if e != nil {
		return e
	}
	var b setup.Bootstrap
	if e = json.Unmarshal(raw, &b); e != nil {
		return e
	}
	f, e := os.Open(*artifact)
	if e != nil {
		return e
	}
	h := sha256.New()
	b.Edge.Size, e = io.Copy(h, io.LimitReader(f, updater.MaxArtifact+1))
	e = errors.Join(e, f.Close())
	if e != nil {
		return e
	}
	b.Edge.SHA256 = hex.EncodeToString(h.Sum(nil))
	raw, e = os.ReadFile(*private)
	if e != nil {
		return e
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return errors.New("PKCS8 PEM required")
	}
	k, e := x509.ParsePKCS8PrivateKey(block.Bytes)
	if e != nil {
		return e
	}
	key, ok := k.(ed25519.PrivateKey)
	if !ok {
		return errors.New("Ed25519 required")
	}
	payload, e := json.Marshal(b)
	if e != nil {
		return e
	}
	envelope := updater.Envelope{KeyID: *keyID, Payload: base64.StdEncoding.EncodeToString(payload), Signature: base64.StdEncoding.EncodeToString(ed25519.Sign(key, append([]byte(setup.SignatureDomain), payload...)))}
	out, e := json.Marshal(envelope)
	if e != nil {
		return e
	}
	raw, e = os.ReadFile(*distribution)
	if e != nil {
		return e
	}
	var d setup.Distribution
	if e = json.Unmarshal(raw, &d); e != nil {
		return e
	}
	if _, _, e = setup.Verify(out, d, time.Now()); e != nil {
		return e
	}
	_, e = fmt.Fprintln(output, string(out))
	return e
}
func main() {
	if e := run(os.Args[1:], os.Stdout); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
