//go:build windows

// Explicit, local-development-only Edge maintenance. Never shipped or scheduled.
package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
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

type backup struct {
	Receipt      setup.Receipt `json:"receipt"`
	DataPath     string        `json:"dataPath"`
	DataHash     string        `json:"dataHash"`
	IdentityHash string        `json:"identityHash"`
	POSHash      string        `json:"posHash"`
}

func fileHash(path string) (string, error) {
	f, e := os.Open(path)
	if e != nil {
		return "", e
	}
	defer f.Close()
	h := sha256.New()
	if _, e = io.Copy(h, f); e != nil {
		return "", e
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
func treeHash(root string) (string, error) {
	var paths []string
	e := filepath.WalkDir(root, func(path string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if d.Type()&os.ModeSymlink != 0 {
			return errors.New("linked data path refused")
		}
		if !d.IsDir() {
			paths = append(paths, path)
		}
		return nil
	})
	if e != nil {
		return "", e
	}
	sort.Strings(paths)
	h := sha256.New()
	for _, p := range paths {
		v, e := fileHash(p)
		if e != nil {
			return "", e
		}
		rel, e := filepath.Rel(root, p)
		if e != nil {
			return "", e
		}
		fmt.Fprintf(h, "%s\x00%s\n", rel, v)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
func identityHash(l setup.Layout) (string, error) {
	db, e := sql.Open("sqlite", "file:"+filepath.ToSlash(filepath.Join(l.EdgeData(), "edge.db"))+"?mode=ro")
	if e != nil {
		return "", e
	}
	defer db.Close()
	var id, pub, venue string
	e = db.QueryRow("SELECT id,public_key,COALESCE(venue_id,'') FROM installation WHERE singleton=1").Scan(&id, &pub, &venue)
	if e != nil {
		return "", e
	}
	h := sha256.Sum256([]byte(id + "\x00" + pub + "\x00" + venue))
	return hex.EncodeToString(h[:]), nil
}
func state(c updater.Config) (updater.State, error) {
	var st updater.State
	req, e := http.NewRequest("GET", "http://"+c.Listen+"/v1/status", nil)
	if e != nil {
		return st, e
	}
	req.Header.Set("Authorization", "Bearer "+c.Token)
	r, e := (&http.Client{Timeout: 5 * time.Second}).Do(req)
	if e != nil {
		return st, e
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return st, fmt.Errorf("updater status HTTP %d", r.StatusCode)
	}
	e = json.NewDecoder(io.LimitReader(r.Body, 65536)).Decode(&st)
	return st, e
}
func journal(l setup.Layout) string {
	return filepath.Join(l.Root, "state", "controlled-edge-upgrade.json")
}
func loadBackup(l setup.Layout) (backup, error) {
	var b backup
	r, e := os.ReadFile(journal(l))
	if e == nil {
		e = json.Unmarshal(r, &b)
	}
	return b, e
}
func verifyData(l setup.Layout, b backup) error {
	got, e := treeHash(b.DataPath)
	if e != nil {
		return e
	}
	if got != b.DataHash {
		return errors.New("restaurant data changed during Edge-only maintenance")
	}
	got, e = identityHash(l)
	if e != nil {
		return e
	}
	if got != b.IdentityHash {
		return errors.New("Edge identity changed")
	}
	got, e = fileHash(updater.CurrentExecutable(l.POS()))
	if e != nil {
		return e
	}
	if got != b.POSHash {
		return errors.New("POS executable changed")
	}
	return nil
}
func restore(ctx context.Context, l setup.Layout, b backup, lock *flock.Flock) error {
	if b.Receipt.EdgeVersion != "1.0.0" || b.Receipt.Distribution.Channel != "local-development" {
		return errors.New("invalid maintenance backup")
	}
	if e := atomic(l.Maintenance(), "controlled Edge rollback"); e != nil {
		return e
	}
	if e := (setup.NativeHost{}).Quiesce(ctx, l, b.Receipt, false); e != nil {
		return e
	}
	if e := atomic(l.Config(), b.Receipt.Config); e != nil {
		return e
	}
	if e := atomic(l.Receipt(), b.Receipt); e != nil {
		return e
	}
	if e := os.Remove(l.Maintenance()); e != nil {
		return e
	}
	if e := lock.Unlock(); e != nil {
		return e
	}
	if e := setup.EnsureHost(ctx, l, false); e != nil {
		return e
	}
	return verifyData(l, b)
}
func run(mode string) error {
	if mode != "apply" && mode != "finalize" && mode != "rollback" {
		return errors.New("explicit apply, finalize or rollback required")
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
		return errors.New("another Setup operation is running")
	}
	defer lock.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	old, e := setup.Load(l)
	if e != nil {
		return e
	}
	if old.Distribution.Channel != "local-development" || old.Config.Channel != "local-development" || old.Status != "installed" {
		return errors.New("installed development lab required")
	}
	if mode == "rollback" {
		b, e := loadBackup(l)
		if e != nil {
			return e
		}
		return restore(ctx, l, b, lock)
	}
	if mode == "finalize" {
		b, e := loadBackup(l)
		if e != nil {
			return e
		}
		st, e := state(old.Config)
		if e != nil {
			return e
		}
		if old.EdgeVersion != "1.0.1" || !st.StartupVerified || st.Current != "1.0.7" || st.Swap != "" || st.DataPath != b.DataPath {
			return errors.New("new host and POS startup proof required before cleanup")
		}
		identity, e := identityHash(l)
		if e != nil {
			return e
		}
		if identity != b.IdentityHash {
			return errors.New("identity mismatch")
		}
		// Only the exact previous Edge binary directory and this tool's stage.
		if e = os.RemoveAll(filepath.Dir(l.Edge("1.0.0"))); e != nil {
			return e
		}
		if e = os.RemoveAll(filepath.Join(l.Root, "edge", "controlled-upgrade-stage")); e != nil {
			return e
		}
		if e = os.Remove(journal(l)); e != nil {
			return e
		}
		fmt.Println("Verified Edge 1.0.1; previous Edge binary and maintenance temporary files removed.")
		return nil
	}
	if old.EdgeVersion != "1.0.0" || old.BootstrapRelease != 2 {
		return errors.New("only the approved 1.0.0 baseline may be upgraded")
	}
	if _, e = os.Stat(journal(l)); !os.IsNotExist(e) {
		return errors.New("maintenance journal exists; inspect and rollback rather than overwrite")
	}
	if _, e = os.Stat(l.Maintenance()); !os.IsNotExist(e) {
		return errors.New("another maintenance operation is active")
	}
	st, e := state(old.Config)
	if e != nil {
		return e
	}
	if st.Status == "INSTALLING" || st.Status == "RESTARTING" || st.Swap != "" || st.CleanupPending || st.RepairPending || st.Current != "1.0.7" || !st.StartupVerified || st.DataPath == "" {
		return errors.New("stable POS 1.0.7 with no pending recovery is required")
	}
	base := old.Distribution.BootstrapURL
	if base != "https://172.20.10.2:8443/networks/172.20.10.2/bootstrap.json" && base != "https://10.10.10.3:8443/networks/10.10.10.3/bootstrap.json" {
		return errors.New("registered LAN distribution required")
	}
	client := setup.SecureClient(&http.Client{Timeout: 30 * time.Second})
	raw, e := fetch(client, base)
	if e != nil {
		return e
	}
	signed, pos, e := setup.Verify(raw, old.Distribution, time.Now())
	if e != nil {
		return e
	}
	if signed.Release != 3 || signed.Edge.Version != "1.0.1" || pos.Version != st.Current || pos.Release != st.High || signed.POSFeed != old.Config.Feed || signed.RepairBase != old.RepairBase || signed.POSReleaseBase != old.POSReleaseBase {
		return errors.New("signed upgrade baseline mismatch")
	}
	if !strings.HasPrefix(signed.Edge.URL, strings.Split(base, "/networks/")[0]+"/artifacts/") {
		return errors.New("unexpected artifact origin")
	}
	stage := filepath.Join(l.Root, "edge", "controlled-upgrade-stage")
	if e = os.Mkdir(stage, 0700); e != nil {
		return e
	}
	archive := filepath.Join(stage, "edge.zip")
	r, e := client.Get(signed.Edge.URL)
	if e != nil {
		return e
	}
	if r.StatusCode != 200 {
		r.Body.Close()
		return errors.New("artifact request failed")
	}
	f, e := os.OpenFile(archive, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		r.Body.Close()
		return e
	}
	_, e = io.Copy(f, io.LimitReader(r.Body, signed.Edge.Size+1))
	e = errors.Join(e, f.Sync(), f.Close(), r.Body.Close())
	if e != nil {
		return e
	}
	if e = updater.VerifyArtifact(archive, signed.Edge); e != nil {
		return e
	}
	release := filepath.Join(stage, "release")
	if e = updater.ExtractBundle(archive, release, setup.EdgeExecutable); e != nil {
		return e
	}
	if e = atomic(l.Maintenance(), "controlled Edge upgrade"); e != nil {
		return e
	}
	if e = host.Quiesce(ctx, l, old, false); e != nil {
		return errors.Join(e, os.Remove(l.Maintenance()))
	}
	b := backup{Receipt: old, DataPath: st.DataPath}
	if b.DataHash, e = treeHash(b.DataPath); e != nil {
		return e
	}
	if b.IdentityHash, e = identityHash(l); e != nil {
		return e
	}
	if b.POSHash, e = fileHash(updater.CurrentExecutable(l.POS())); e != nil {
		return e
	}
	if e = atomic(journal(l), b); e != nil {
		return e
	}
	dest := filepath.Dir(l.Edge("1.0.1"))
	if _, e = os.Stat(dest); !os.IsNotExist(e) {
		return errors.New("candidate directory already exists")
	}
	if e = os.Rename(release, dest); e != nil {
		return e
	}
	next := old
	next.EdgeVersion = signed.Edge.Version
	next.EdgeHash = signed.Edge.SHA256
	next.BootstrapRelease = signed.Release
	next.Bootstrap = raw
	next.Config.InitialVersion = pos.Version
	next.Config.InitialRelease = pos.Release
	if e = atomic(l.Config(), next.Config); e != nil {
		return e
	}
	if e = atomic(l.Receipt(), next); e != nil {
		return e
	}
	if e = os.Remove(l.Maintenance()); e != nil {
		return e
	}
	if e = lock.Unlock(); e != nil {
		return e
	}
	if e = setup.EnsureHost(ctx, l, false); e != nil {
		if ok, le := lock.TryLock(); le != nil || !ok {
			return errors.Join(e, le, errors.New("reacquire maintenance lock for rollback"))
		}
		return errors.Join(e, restore(ctx, l, b, lock))
	}
	if e = verifyData(l, b); e != nil {
		return e
	}
	fmt.Println("Edge 1.0.1 running; restaurant data, Edge identity and POS binary verified unchanged. Previous binary retained until launch verification.")
	return nil
}
func main() {
	mode := flag.String("mode", "", "explicit local maintenance action")
	flag.Parse()
	if e := run(*mode); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
