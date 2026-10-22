// printer-peer runs only the authenticated logical queue, in the foreground.
// It never installs a service, launches Flutter or activates a physical writer.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"time"
	"vynic.local/edge/internal/printerprovisioning"
	"vynic.local/edge/internal/printpeer"
)

func run() error {
	identity := flag.String("identity-dir", "", "existing protected production identity directory")
	state := flag.String("queue-dir", "", "dedicated logical queue directory")
	device := flag.String("device-id", "", "bound Device UUID")
	keyPath := flag.String("issuer-public-key", "", "independently deployed Ed25519 public PEM")
	grant := flag.String("grant-file", "", "optional new signed production inventory file")
	bootstrap := flag.Bool("initialize", false, "explicit first configuration bootstrap; never use to repair lost state")
	flag.Parse()
	if *identity == "" || *state == "" || *device == "" || *keyPath == "" {
		return fmt.Errorf("identity-dir, queue-dir, device-id and issuer-public-key required")
	}
	raw, e := os.ReadFile(*keyPath)
	if e != nil {
		return e
	}
	block, rest := pem.Decode(raw)
	if block == nil || block.Type != "PUBLIC KEY" || len(rest) != 0 {
		return fmt.Errorf("invalid public PEM")
	}
	pub, e := x509.ParsePKIXPublicKey(block.Bytes)
	if e != nil {
		return e
	}
	key, ok := pub.(ed25519.PublicKey)
	if !ok {
		return fmt.Errorf("Ed25519 pin required")
	}
	store, e := printerprovisioning.OpenProduction(*identity, *device, key)
	if e != nil {
		return e
	}
	defer store.Close()
	if *grant != "" {
		raw, e = os.ReadFile(*grant)
		if e != nil {
			return e
		}
		if e = store.Apply(raw); e != nil {
			return e
		}
	}
	runtime, e := printpeer.Open(*state, store)
	if e != nil {
		return e
	}
	defer runtime.Close()
	if *bootstrap {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		if e = runtime.Initialize(ctx); e != nil {
			return e
		}
	}
	if e = json.NewEncoder(os.Stdout).Encode(runtime.Status()); e != nil {
		return e
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	<-ctx.Done()
	return nil
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
