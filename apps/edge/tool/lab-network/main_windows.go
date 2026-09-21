//go:build windows

// Development-only endpoint selection. This tool is not shipped with Setup.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"time"

	"github.com/gofrs/flock"
	"golang.org/x/sys/windows"
	"vynic.local/edge/internal/setup"
	"vynic.local/edge/internal/updater"
)

func atomic(path string, value any) error {
	b, e := json.MarshalIndent(value, "", "  ")
	if e != nil {
		return e
	}
	tmp := path + ".lan-tmp"
	f, e := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if e != nil {
		return e
	}
	if _, e = f.Write(b); e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	a, e := windows.UTF16PtrFromString(tmp)
	if e != nil {
		return e
	}
	z, e := windows.UTF16PtrFromString(path)
	if e != nil {
		return e
	}
	return windows.MoveFileEx(a, z, windows.MOVEFILE_REPLACE_EXISTING|windows.MOVEFILE_WRITE_THROUGH)
}
func fetch(client *http.Client, url string) ([]byte, error) {
	r, e := client.Get(url)
	if e != nil {
		return nil, e
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return nil, fmt.Errorf("metadata HTTP %d", r.StatusCode)
	}
	b, e := io.ReadAll(io.LimitReader(r.Body, 65537))
	if len(b) > 65536 {
		return nil, errors.New("metadata too large")
	}
	return b, e
}
func run(ip string) error {
	if ip != "172.20.10.2" && ip != "10.10.10.3" {
		return errors.New("only the two registered development LANs are allowed")
	}
	l, e := setup.NativeLayout()
	if e != nil {
		return e
	}
	host := setup.NativeHost{}
	if e = setup.PrepareRoot(l, host); e != nil {
		return e
	}
	lock := flock.New(filepath.Join(l.Root, "setup.lock"))
	ok, e := lock.TryLock()
	if e != nil {
		return e
	}
	if !ok {
		return errors.New("another setup operation is running")
	}
	defer lock.Unlock()
	journal := filepath.Join(l.Root, "state", "lab-network-backup.json")
	// An interrupted two-file edit leaves maintenance admission closed. Rerun
	// restores the old pair first, then retries against signed metadata.
	if raw, err := os.ReadFile(journal); err == nil {
		var old setup.Receipt
		if e = json.Unmarshal(raw, &old); e != nil {
			return e
		}
		if old.Distribution.Channel != "local-development" {
			return errors.New("non-lab recovery refused")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
		defer cancel()
		if e = host.Quiesce(ctx, l, old, false); e != nil {
			return e
		}
		if e = atomic(l.Config(), old.Config); e != nil {
			return e
		}
		if e = atomic(l.Receipt(), old); e != nil {
			return e
		}
		if e = os.Remove(journal); e != nil {
			return e
		}
		if e = os.Remove(l.Maintenance()); e != nil && !os.IsNotExist(e) {
			return e
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	if _, e = os.Stat(l.Maintenance()); e == nil {
		return errors.New("installation maintenance already active")
	} else if !os.IsNotExist(e) {
		return e
	}
	old, e := setup.Load(l)
	if e != nil {
		return e
	}
	if old.Status != "installed" || old.Distribution.Channel != "local-development" || old.Config.Channel != "local-development" {
		return errors.New("installed local-development lab required")
	}
	var cfg updater.Config
	raw, e := os.ReadFile(l.Config())
	if e != nil {
		return e
	}
	if e = json.Unmarshal(raw, &cfg); e != nil {
		return e
	}
	if !reflect.DeepEqual(cfg, old.Config) {
		return errors.New("config differs from receipt; no changes made")
	}
	prefix := "https://" + ip + ":8443/networks/" + ip
	next := old
	next.Distribution.BootstrapURL = prefix + "/bootstrap.json"
	client := setup.SecureClient(&http.Client{Timeout: 15 * time.Second})
	raw, e = fetch(client, fmt.Sprintf("%s/repair/%d.json", prefix, old.BootstrapRelease))
	if e != nil {
		return e
	}
	b, p, e := setup.Verify(raw, next.Distribution, time.Now())
	if e != nil {
		return e
	}
	if b.Release != old.BootstrapRelease || b.Edge.Version != old.EdgeVersion || b.Edge.SHA256 != old.EdgeHash || p.Version != old.Config.InitialVersion || p.Release != old.Config.InitialRelease || b.POSFeed != prefix+"/pos/manifest.json" || b.RepairBase != prefix+"/repair" || b.POSReleaseBase != prefix+"/pos/releases" {
		return errors.New("signed mirror does not match installed baseline")
	}
	next.Bootstrap = raw
	next.Config.Feed = b.POSFeed
	next.RepairBase = b.RepairBase
	next.POSReleaseBase = b.POSReleaseBase
	// Validate the current feed with existing trust roots before stopping anything.
	feed, e := fetch(client, next.Config.Feed)
	if e != nil {
		return e
	}
	if _, e = updater.Verify(feed, next.Config.Keys, next.Config.Channel, "0.0.0", 0, time.Now()); e != nil {
		return e
	}
	if e = atomic(l.Maintenance(), "development network selection"); e != nil {
		return e
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	if e = host.Quiesce(ctx, l, old, false); e != nil {
		return errors.Join(e, os.Remove(l.Maintenance()))
	}
	if e = atomic(journal, old); e != nil {
		return e
	}
	if e = atomic(l.Config(), next.Config); e != nil {
		return e
	}
	if e = atomic(l.Receipt(), next); e != nil {
		return e
	}
	verified, e := setup.Load(l)
	if e != nil {
		return e
	}
	if !reflect.DeepEqual(verified.Config, next.Config) || verified.Distribution.BootstrapURL != next.Distribution.BootstrapURL || verified.RepairBase != next.RepairBase || verified.POSReleaseBase != next.POSReleaseBase {
		return errors.New("receipt verification failed; rerun to restore backup")
	}
	if e = os.Remove(journal); e != nil {
		return e
	}
	if e = os.Remove(l.Maintenance()); e != nil {
		return e
	}
	if e = lock.Unlock(); e != nil {
		return e
	}
	if e = setup.EnsureHost(ctx, l, false); e != nil {
		return e
	}
	fmt.Println("Development release connection selected:", next.Config.Feed)
	fmt.Println("Same Edge binary restarted; POS, data, credentials and install consent unchanged.")
	return nil
}
func main() {
	ip := flag.String("ip", "", "registered development LAN IP")
	flag.Parse()
	if e := run(*ip); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
