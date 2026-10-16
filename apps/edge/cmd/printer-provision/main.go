// printer-provision manages only production printer identity and cached grants.
// It never starts a service, queue, LAN listener, controller or printer transport.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"vynic.local/edge/internal/printerprovisioning"
)

func run(args []string, in io.Reader, out io.Writer) error {
	flags := flag.NewFlagSet("printer-provision", flag.ContinueOnError)
	action := flags.String("action", "status", "init, pull, or status")
	directory := flags.String("state-dir", "", "dedicated service identity directory; exclude from POS backups")
	device := flags.String("device-id", "", "existing enrolled POS Device UUID")
	issuer := flags.String("issuer-public-key", "", "independently deployed printer Ed25519 public key PEM")
	cloud := flags.String("cloud", "", "trusted HTTPS Cloud origin (pull only)")
	if e := flags.Parse(args); e != nil {
		return e
	}
	if flags.NArg() != 0 || *directory == "" || *device == "" || *issuer == "" || (*action != "init" && *action != "pull" && *action != "status") {
		return errors.New("action, state-dir, device-id and trusted issuer-public-key are required")
	}
	raw, e := os.ReadFile(*issuer)
	if e != nil {
		return e
	}
	block, rest := pem.Decode(raw)
	if block == nil || block.Type != "PUBLIC KEY" || len(strings.TrimSpace(string(rest))) != 0 {
		return errors.New("one trusted printer public key PEM required")
	}
	key, e := x509.ParsePKIXPublicKey(block.Bytes)
	if e != nil {
		return e
	}
	public, ok := key.(ed25519.PublicKey)
	if !ok {
		return errors.New("printer issuer key must be Ed25519")
	}
	store, e := printerprovisioning.OpenProduction(*directory, *device, public)
	if e != nil {
		return e
	}
	defer store.Close()
	switch *action {
	case "init":
		return json.NewEncoder(out).Encode(store.Enrollment())
	case "pull":
		// Read from an authenticated caller's pipe, never from argv, environment,
		// business backup or a copied Foundation profile. Do not persist this secret.
		credential, e := io.ReadAll(io.LimitReader(in, 513))
		if e != nil {
			return e
		}
		if len(credential) > 512 {
			return errors.New("Device credential too long")
		}
		if e = store.Pull(context.Background(), *cloud, strings.TrimSpace(string(credential))); e != nil {
			return e
		}
	}
	body, e := store.Inventory()
	if e != nil {
		return e
	}
	return json.NewEncoder(out).Encode(body)
}
func main() {
	if e := run(os.Args[1:], os.Stdin, os.Stdout); e != nil {
		fmt.Fprintln(os.Stderr, "printer provisioning refused:", e)
		os.Exit(1)
	}
}
