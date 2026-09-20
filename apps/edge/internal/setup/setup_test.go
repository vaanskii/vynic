package setup

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/updater"
)

type fakeHost struct {
	integrateErr, quiesceErr error
	integrated, removed      int
}

func (h *fakeHost) Secure(Layout) error                            { return nil }
func (h *fakeHost) Quiesce(context.Context, Layout, Receipt) error { return h.quiesceErr }
func (h *fakeHost) Integrate(Layout) error                         { h.integrated++; return h.integrateErr }
func (h *fakeHost) RemoveIntegration(Layout) error                 { h.removed++; return nil }

type fixture struct {
	t         *testing.T
	i         *Installer
	h         *fakeHost
	s         *httptest.Server
	k         ed25519.PrivateKey
	b         Bootstrap
	p         updater.Manifest
	mu        sync.Mutex
	responses map[string][]byte
	broken    map[string]bool
}

func bundle(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	z := zip.NewWriter(&buf)
	for name, s := range files {
		f, e := z.Create(name)
		must(t, e)
		_, e = f.Write([]byte(s))
		must(t, e)
	}
	must(t, z.Close())
	return buf.Bytes()
}
func must(t *testing.T, e error) {
	t.Helper()
	if e != nil {
		t.Fatal(e)
	}
}
func signed(t *testing.T, k ed25519.PrivateKey, domain string, v any) []byte {
	t.Helper()
	b, e := json.Marshal(v)
	must(t, e)
	out, e := json.Marshal(updater.Envelope{KeyID: "test", Payload: base64.StdEncoding.EncodeToString(b), Signature: base64.StdEncoding.EncodeToString(ed25519.Sign(k, append([]byte(domain), b...)))})
	must(t, e)
	return out
}
func (f *fixture) set(path string, b []byte) { f.mu.Lock(); defer f.mu.Unlock(); f.responses[path] = b }
func (f *fixture) publish() {
	raw := signed(f.t, f.k, SignatureDomain, f.b)
	f.set("/bootstrap.json", raw)
	f.set("/repair/1.json", raw)
}
func newFixture(t *testing.T) *fixture {
	t.Helper()
	pub, k, e := ed25519.GenerateKey(rand.Reader)
	must(t, e)
	f := &fixture{t: t, k: k, responses: map[string][]byte{}, broken: map[string]bool{}}
	f.s = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		b, ok := f.responses[r.URL.Path]
		broken := f.broken[r.URL.Path]
		f.mu.Unlock()
		if !ok {
			http.NotFound(w, r)
			return
		}
		if broken {
			w.Header().Set("Content-Length", "100000")
			w.WriteHeader(200)
			_, _ = w.Write([]byte("partial"))
			return
		}
		_, _ = w.Write(b)
	}))
	t.Cleanup(f.s.Close)
	edge := bundle(t, map[string]string{EdgeExecutable: "synthetic Windows Edge, never executed"})
	pos := bundle(t, map[string]string{updater.Executable: "synthetic Windows POS, never executed", "flutter_windows.dll": "dll", "data/icudtl.dat": "icu", "data/flutter_assets/AssetManifest.bin": "assets"})
	metadata := func(product, v, u string, raw []byte) updater.Manifest {
		sum := sha256.Sum256(raw)
		return updater.Manifest{Product: product, Version: v, Release: 1, OS: "windows", Arch: "amd64", Channel: "stable", URL: f.s.URL + u, SHA256: hex.EncodeToString(sum[:]), Size: int64(len(raw)), Expires: time.Now().Add(time.Hour), UpdaterProtocol: 1, HiveSchema: 9, EdgeSchema: 2, DataPolicy: "hive9-no-migration"}
	}
	f.p = metadata("vynic-pos", "1.8.0", "/pos.zip", pos)
	em := metadata("vynic-edge", "1.0.0", "/edge.zip", edge)
	em.DataPolicy = "edge2-no-migration"
	f.b = Bootstrap{POSBinaryLayout: 2, Product: "vynic-bootstrap", Protocol: 1, Release: 1, OS: "windows", Arch: "amd64", Channel: "stable", Expires: time.Now().Add(time.Hour), Edge: em, POS: signed(t, k, "VYNIC-POS-RELEASE-v1\n", f.p), POSFeed: f.s.URL + "/pos.json", RepairBase: f.s.URL + "/repair", POSReleaseBase: f.s.URL + "/pos-releases"}
	d := Distribution{BootstrapURL: f.s.URL + "/bootstrap.json", Channel: "stable", Keys: map[string]updater.TrustedKey{"test": {Public: base64.StdEncoding.EncodeToString(pub), Expires: time.Now().Add(2 * time.Hour)}}}
	f.h = &fakeHost{}
	parent, e := filepath.EvalSymlinks(t.TempDir())
	must(t, e)
	root := filepath.Join(parent, "Vynic")
	src := filepath.Join(t.TempDir(), "VynicSetup.exe")
	must(t, os.WriteFile(src, []byte("trusted invoking setup"), 0600))
	f.i = &Installer{Layout: Layout{root}, Distribution: d, Client: f.s.Client(), Host: f.h, SetupSource: src}
	f.set("/edge.zip", edge)
	f.set("/pos.zip", pos)
	f.set("/pos.json", f.b.POS)
	f.publish()
	return f
}
func (f *fixture) install() { f.t.Helper(); must(f.t, f.i.Install(context.Background(), false)) }
func TestFirstInstallProvisioningAndRetry(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	r, e := Load(l)
	must(t, e)
	if r.Status != "installed" || len(r.Config.Token) != 64 || r.Config.Root != l.POS() || f.h.integrated != 1 {
		t.Fatal("incomplete provisioning")
	}
	s, e := store.Open(l.EdgeData(), false)
	must(t, e)
	id, e := s.Identity()
	must(t, e)
	must(t, s.Close())
	if id.VenueID != "" {
		t.Fatal("installer must not assign Venue authority")
	}
	cert, e := os.ReadFile(filepath.Join(l.EdgeData(), "edge-cert.pem"))
	must(t, e)
	if !bytes.Equal(cert, id.Certificate) {
		t.Fatal("certificate export differs from persistent identity")
	}
	before := r.Config.Token
	f2 := newFixture(t)
	f2.install()
	r2, e := Load(f2.i.Layout)
	must(t, e)
	if before == r2.Config.Token {
		t.Fatal("shared credentials")
	}
	if e = f.i.Install(context.Background(), false); e == nil {
		t.Fatal("duplicate fresh install accepted")
	}
	must(t, f.i.Install(context.Background(), true))
	r, e = Load(l)
	must(t, e)
	if before != r.Config.Token {
		t.Fatal("repair rotated credential")
	}
	s, e = store.Open(l.EdgeData(), false)
	must(t, e)
	after, e := s.Identity()
	must(t, e)
	must(t, s.Close())
	if after.InstallationID != id.InstallationID || after.PublicKey != id.PublicKey {
		t.Fatal("repair replaced Edge identity")
	}
}
func TestSignaturePolicyMatrix(t *testing.T) {
	cases := map[string]func(*fixture){
		"signature":            func(f *fixture) { f.k = make(ed25519.PrivateKey, 64) },
		"edge product":         func(f *fixture) { f.b.Edge.Product = "vynic-manager" },
		"bootstrap purpose":    func(f *fixture) { f.b.Product = "other" },
		"old binary layout":    func(f *fixture) { f.b.POSBinaryLayout = 0 },
		"future binary layout": func(f *fixture) { f.b.POSBinaryLayout = 3 },
		"schema":               func(f *fixture) { f.b.Edge.EdgeSchema = 3 },
		"arch":                 func(f *fixture) { f.b.Arch = "arm64" },
		"channel":              func(f *fixture) { f.b.Channel = "beta" },
		"expired":              func(f *fixture) { f.b.Expires = time.Now().Add(-time.Hour) },
		"http":                 func(f *fixture) { f.b.Edge.URL = "http://example.invalid/a.zip" },
		"pos signature":        func(f *fixture) { f.b.POS = json.RawMessage(`{"keyId":"test","payload":"e30=","signature":"AA=="}`) },
		"pos product": func(f *fixture) {
			p := f.p
			p.Product = "vynic-manager"
			f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", p)
		},
	}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			change(f)
			f.publish()
			if e := f.i.Install(context.Background(), false); e == nil {
				t.Fatal("unsafe bootstrap accepted")
			}
			if _, e := os.Stat(f.i.Layout.Config()); !os.IsNotExist(e) {
				t.Fatal("config provisioned before verification")
			}
		})
	}
}
func TestCorruptAndInterruptedDownloadRetry(t *testing.T) {
	for _, network := range []bool{false, true} {
		t.Run(map[bool]string{false: "hash", true: "network"}[network], func(t *testing.T) {
			f := newFixture(t)
			f.mu.Lock()
			original := f.responses["/pos.zip"]
			if network {
				f.broken["/pos.zip"] = true
			} else {
				f.responses["/pos.zip"] = []byte("corrupt")
			}
			f.mu.Unlock()
			if e := f.i.Install(context.Background(), false); e == nil {
				t.Fatal("download accepted")
			}
			if _, e := os.Stat(f.i.Layout.Edge("1.0.0")); !os.IsNotExist(e) {
				t.Fatal("partial artifact activated")
			}
			r, e := Load(f.i.Layout)
			must(t, e)
			token := r.Config.Token
			f.mu.Lock()
			f.responses["/pos.zip"] = original
			f.broken["/pos.zip"] = false
			f.mu.Unlock()
			f.install()
			r, e = Load(f.i.Layout)
			must(t, e)
			if token != r.Config.Token {
				t.Fatal("retry lost credentials")
			}
		})
	}
}
func TestFailedRepairPreservesWorkingReleaseAndData(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	path := l.Edge("1.0.0")
	before, e := os.ReadFile(path)
	must(t, e)
	preserved := map[string][]byte{}
	for _, p := range []string{path, updater.CurrentExecutable(l.POS()), l.Setup()} {
		preserved[p], e = os.ReadFile(p)
		must(t, e)
	}
	sentinel := filepath.Join(l.EdgeData(), "restaurant-sentinel")
	must(t, os.WriteFile(sentinel, []byte("never roll this back"), 0600))
	f.h.integrateErr = errors.New("simulated shortcut registration failure")
	if e = f.i.Install(context.Background(), true); e == nil {
		t.Fatal("failure hidden")
	}
	after, e := os.ReadFile(path)
	must(t, e)
	if !bytes.Equal(before, after) {
		t.Fatal("working Edge damaged")
	}
	b, e := os.ReadFile(sentinel)
	must(t, e)
	if string(b) != "never roll this back" {
		t.Fatal("data damaged")
	}
	for p, before := range preserved {
		after, e := os.ReadFile(p)
		must(t, e)
		if !bytes.Equal(before, after) {
			t.Fatalf("working binary damaged: %s", p)
		}
	}
	f.h.integrateErr = nil
	must(t, f.i.Install(context.Background(), true))
}
func TestInterruptedSwapRecovery(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	dest := filepath.Dir(l.Edge("1.0.0"))
	old, e := os.ReadFile(l.Edge("1.0.0"))
	must(t, e)
	child := exec.Command(os.Args[0], "-test.run=^TestSetupCrashWorker$")
	child.Env = append(os.Environ(), "VYNIC_SETUP_CRASH_ROOT="+l.Root)
	e = child.Run()
	var exit *exec.ExitError
	if !errors.As(e, &exit) || exit.ExitCode() != 91 {
		t.Fatalf("crash child: %v", e)
	}
	_ = dest
	// A new installer instance repairs the interrupted journal before any further swap.
	next := *f.i
	must(t, next.Install(context.Background(), true))
	after, e := os.ReadFile(l.Edge("1.0.0"))
	must(t, e)
	if !bytes.Equal(old, after) {
		t.Fatal("crash recovery lost prior binary")
	}
	if _, e = os.Stat(filepath.Join(l.Root, "state", "swap.json")); !os.IsNotExist(e) {
		t.Fatal("journal retained")
	}
}
func TestUninstallRetainsDataAndRepairReusesState(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	r, e := Load(l)
	must(t, e)
	data := filepath.Join(t.TempDir(), "Hive", "open-orders.hive")
	must(t, os.MkdirAll(filepath.Dir(data), 0700))
	must(t, os.WriteFile(data, []byte("open orders persist"), 0600))
	must(t, f.i.Uninstall(context.Background()))
	if f.h.removed != 1 {
		t.Fatal("integration remained")
	}
	for _, p := range []string{l.Edge("1.0.0"), updater.CurrentExecutable(l.POS())} {
		if _, e = os.Stat(p); !os.IsNotExist(e) {
			t.Fatal("binary not removed")
		}
	}
	for _, p := range []string{data, filepath.Join(l.EdgeData(), "edge.db"), filepath.Join(l.POS(), "updater.sqlite"), l.Config(), l.Receipt()} {
		if _, e = os.Stat(p); e != nil {
			t.Fatal("retained state missing", p, e)
		}
	}
	must(t, f.i.Uninstall(context.Background())) // removal is idempotent
	must(t, f.i.Install(context.Background(), true))
	after, e := Load(l)
	must(t, e)
	if after.Config.Token != r.Config.Token {
		t.Fatal("reinstall reset credentials")
	}
}
func TestRepairNeverChangesEdgeVersion(t *testing.T) {
	f := newFixture(t)
	f.install()
	f.b.Edge.Version = "2.0.0"
	f.publish()
	if e := f.i.Install(context.Background(), true); e == nil {
		t.Fatal("Edge self-update admitted")
	}
	if _, e := os.Stat(f.i.Layout.Edge("1.0.0")); e != nil {
		t.Fatal("previous Edge removed")
	}
}
func TestRepairActivePOSPreservesUpdaterHighWater(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	// Model updater-owned durable selection after a later POS update/rollback.
	db, e := sql.Open("sqlite", filepath.Join(l.POS(), "updater.sqlite"))
	must(t, e)
	var raw []byte
	must(t, db.QueryRow("SELECT value FROM updater_state WHERE id=1").Scan(&raw))
	var st updater.State
	must(t, json.Unmarshal(raw, &st))
	st.Current = "1.9.0"
	must(t, updater.MarkRelease(updater.CurrentDir(l.POS()), "1.9.0"))
	st.High = 4
	raw, e = json.Marshal(st)
	must(t, e)
	_, e = db.Exec("UPDATE updater_state SET value=? WHERE id=1", string(raw))
	must(t, e)
	must(t, db.Close())
	p := f.p
	p.Version = "1.9.0"
	p.Release = 2
	f.set("/pos-releases/1.9.0.json", signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", p))
	must(t, f.i.Install(context.Background(), true))
	r, e := Load(l)
	must(t, e)
	u, e := updater.Open(r.Config, updater.NativeProcess{})
	must(t, e)
	got := u.Snapshot()
	must(t, u.Close())
	if got.Current != "1.9.0" || got.High != 4 {
		t.Fatal("repair reset version/history")
	}
	if _, e = os.Stat(updater.CurrentExecutable(l.POS())); e != nil {
		t.Fatal(e)
	}
}
func TestRepairFailsClosedForMissingCorruptStateAndBusyHost(t *testing.T) {
	for _, mode := range []string{"missing", "corrupt", "busy", "receipt", "identity", "decision"} {
		t.Run(mode, func(t *testing.T) {
			f := newFixture(t)
			f.install()
			l := f.i.Layout
			switch mode {
			case "missing":
				must(t, os.Remove(filepath.Join(l.POS(), "updater.sqlite")))
			case "corrupt":
				must(t, os.WriteFile(filepath.Join(l.EdgeData(), "edge.db"), []byte("corrupt"), 0600))
			case "busy":
				f.h.quiesceErr = errors.New("POS is open")
			case "receipt":
				must(t, os.Remove(l.Receipt()))
			case "identity":
				db, e := sql.Open("sqlite", filepath.Join(l.EdgeData(), "edge.db"))
				must(t, e)
				_, e = db.Exec("DELETE FROM installation")
				must(t, e)
				must(t, db.Close())
			case "decision":
				db, e := sql.Open("sqlite", filepath.Join(l.POS(), "updater.sqlite"))
				must(t, e)
				_, e = db.Exec("DELETE FROM updater_state")
				must(t, e)
				must(t, db.Close())
			}
			if e := f.i.Install(context.Background(), true); e == nil {
				t.Fatal("unsafe repair accepted")
			}
			if _, e := os.Stat(l.Edge("1.0.0")); e != nil {
				t.Fatal("working binary removed")
			}
		})
	}
}
func TestUnsafeBundleAndSymlink(t *testing.T) {
	for _, name := range []string{"../escape", "C:/escape", "data/CON", "data/file:ads"} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			raw := bundle(t, map[string]string{EdgeExecutable: "edge", name: "attack"})
			sum := sha256.Sum256(raw)
			f.b.Edge.SHA256 = hex.EncodeToString(sum[:])
			f.b.Edge.Size = int64(len(raw))
			f.set("/edge.zip", raw)
			f.publish()
			if e := f.i.Install(context.Background(), false); e == nil {
				t.Fatal("unsafe zip accepted")
			}
		})
	}
	t.Run("symlink", func(t *testing.T) {
		f := newFixture(t)
		must(t, os.Symlink(t.TempDir(), f.i.Layout.Root))
		if e := f.i.Install(context.Background(), false); e == nil {
			t.Fatal("symlink root accepted")
		}
	})
}
func TestNoInsecureRedirectAndBoundedMetadata(t *testing.T) {
	f := newFixture(t)
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Error("HTTP downgrade followed") }))
	defer target.Close()
	redirect := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, 302) }))
	defer redirect.Close()
	_, e := fetch(context.Background(), SecureClient(redirect.Client()), redirect.URL, 64<<10)
	if e == nil {
		t.Fatal("redirect accepted")
	}
	f.set("/huge", []byte(strings.Repeat("x", 100)))
	if _, e = fetch(context.Background(), SecureClient(f.s.Client()), f.s.URL+"/huge", 10); e == nil {
		t.Fatal("oversize metadata accepted")
	}
}

func TestSetupCrashWorker(t *testing.T) {
	root := os.Getenv("VYNIC_SETUP_CRASH_ROOT")
	if root == "" {
		t.Skip("subprocess helper")
	}
	l := Layout{root}
	staging := filepath.Join(root, "staging", "crash")
	must(t, os.MkdirAll(staging, 0700))
	must(t, os.WriteFile(filepath.Join(staging, EdgeExecutable), []byte("interrupted repair"), 0600))
	i := Installer{Layout: l}
	must(t, i.beginSwaps([]swap{{Target: filepath.Dir(l.Edge("1.0.0")), New: staging}}))
	os.Exit(91)
}

func TestRepairRestoresConfigurationWithoutRotatingCredentials(t *testing.T) {
	f := newFixture(t)
	f.install()
	r, e := Load(f.i.Layout)
	must(t, e)
	must(t, os.Remove(f.i.Layout.Config()))
	must(t, f.i.Install(context.Background(), true))
	var cfg updater.Config
	must(t, readJSON(f.i.Layout.Config(), &cfg))
	if cfg.Token != r.Config.Token || cfg.Root != r.Config.Root {
		t.Fatal("config recovery changed credential/root")
	}
}
func TestIncompleteFlutterBundleRefused(t *testing.T) {
	f := newFixture(t)
	raw := bundle(t, map[string]string{updater.Executable: "not full Flutter bundle"})
	sum := sha256.Sum256(raw)
	f.p.SHA256 = hex.EncodeToString(sum[:])
	f.p.Size = int64(len(raw))
	f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", f.p)
	f.set("/pos.zip", raw)
	f.publish()
	if e := f.i.Install(context.Background(), false); e == nil {
		t.Fatal("incomplete bundle accepted")
	}
	if _, e := os.Stat(f.i.Layout.Edge("1.0.0")); !os.IsNotExist(e) {
		t.Fatal("partial installation activated")
	}
}
func TestUninstallBlocksUnresolvedUpdaterDecision(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	db, e := sql.Open("sqlite", filepath.Join(l.POS(), "updater.sqlite"))
	must(t, e)
	st := updater.State{Status: "INSTALLING", Current: "1.8.0", Version: "1.9.0", Previous: "1.8.0", Attempt: "consented-request", High: 1}
	raw, e := json.Marshal(st)
	must(t, e)
	_, e = db.Exec("UPDATE updater_state SET value=? WHERE id=1", string(raw))
	must(t, e)
	must(t, db.Close())
	if e = f.i.Uninstall(context.Background()); e == nil {
		t.Fatal("unresolved update removed")
	}
	if f.h.removed != 0 {
		t.Fatal("removed integration before resolving update")
	}
}
func TestSingleSetupOwner(t *testing.T) {
	f := newFixture(t)
	unlock, e := f.i.lock()
	must(t, e)
	defer unlock()
	if e = f.i.Install(context.Background(), false); e == nil {
		t.Fatal("concurrent installation accepted")
	}
}

func TestInterruptedRepairRestoresOldBinaryEvenOffline(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	old, e := os.ReadFile(l.Edge("1.0.0"))
	must(t, e)
	next := filepath.Join(l.Root, "staging", "offline-crash")
	must(t, os.MkdirAll(next, 0700))
	must(t, os.WriteFile(filepath.Join(next, EdgeExecutable), []byte("uncommitted"), 0600))
	must(t, f.i.beginSwaps([]swap{{Target: filepath.Dir(l.Edge("1.0.0")), New: next}}))
	f.s.Close()
	if e = f.i.Install(context.Background(), true); e == nil {
		t.Fatal("offline repair reported success")
	}
	restored, e := os.ReadFile(l.Edge("1.0.0"))
	must(t, e)
	if !bytes.Equal(old, restored) {
		t.Fatal("previous working release not restored before failed download")
	}
	if _, e = os.Stat(l.Maintenance()); !os.IsNotExist(e) {
		t.Fatal("failed repair stranded maintenance marker")
	}
}

func TestRepairUsesOneTemporaryRollbackAndCleansDownloads(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	// Represent the existing proven release. Repeated repair before Open must
	// retain this original fallback, not keep nesting unproven repair binaries.
	sentinel := filepath.Join(updater.CurrentDir(l.POS()), "previous-runtime.dll")
	must(t, os.WriteFile(sentinel, []byte("proven runtime"), 0600))
	for n := 0; n < 3; n++ {
		must(t, f.i.Install(context.Background(), true))
		old, e := os.ReadFile(filepath.Join(updater.RollbackDir(l.POS()), "previous-runtime.dll"))
		must(t, e)
		if string(old) != "proven runtime" {
			t.Fatal("repair discarded original fallback")
		}
		for _, p := range []string{filepath.Join(l.POS(), "releases"), updater.CurrentDir(l.POS()) + ".setup-old", filepath.Join(l.Root, "staging"), filepath.Join(updater.StagingDir(l.POS()), "setup.zip"), filepath.Join(updater.StagingDir(l.POS()), "setup-release")} {
			if _, e = os.Stat(p); !os.IsNotExist(e) {
				t.Fatalf("repair retained historical/temp path %s: %v", p, e)
			}
		}
		r, e := Load(l)
		must(t, e)
		u, e := updater.OpenExisting(r.Config, updater.NativeProcess{})
		must(t, e)
		st := u.Snapshot()
		must(t, u.Close())
		if st.Swap != "repair_ready" || st.StartupVerified || st.Previous != st.Current {
			t.Fatal("repair not awaiting explicit healthy Open", st)
		}
	}
	must(t, f.i.Uninstall(context.Background()))
	for _, p := range []string{updater.CurrentDir(l.POS()), updater.RollbackDir(l.POS()), updater.StagingDir(l.POS())} {
		if _, e := os.Stat(p); !os.IsNotExist(e) {
			t.Fatalf("binary slot survived uninstall: %s", p)
		}
	}
}
func TestInterruptedPOSRepairRestoresCurrentBeforeOfflineFailure(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	before, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
	must(t, e)
	next := filepath.Join(updater.StagingDir(l.POS()), "setup-release")
	must(t, os.MkdirAll(next, 0700))
	must(t, os.WriteFile(filepath.Join(next, updater.Executable), []byte("uncommitted"), 0600))
	must(t, updater.MarkRelease(next, "1.8.0"))
	must(t, f.i.beginSwaps([]swap{{Target: updater.CurrentDir(l.POS()), New: next, Backup: updater.RollbackDir(l.POS())}}))
	r, e := Load(l)
	must(t, e)
	u, e := updater.OpenExisting(r.Config, updater.NativeProcess{})
	must(t, e)
	must(t, u.RegisterRepair(true))
	must(t, u.Close())
	f.s.Close()
	if e = f.i.Install(context.Background(), true); e == nil {
		t.Fatal("offline repair reported success")
	}
	after, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
	must(t, e)
	if !bytes.Equal(before, after) || existsSetup(updater.RollbackDir(l.POS())) {
		t.Fatal("POS swap journal recovery failed")
	}
}
func existsSetup(path string) bool { _, e := os.Stat(path); return e == nil }

func TestOldEdgeCapabilityRefusedBeforeLegacyLayoutMigration(t *testing.T) {
	f := newFixture(t)
	f.install()
	l := f.i.Layout
	old := filepath.Join(l.POS(), "releases", "1.8.0")
	must(t, os.MkdirAll(filepath.Dir(old), 0700))
	must(t, os.Rename(updater.CurrentDir(l.POS()), old))
	db, e := sql.Open("sqlite", filepath.Join(l.POS(), "updater.sqlite"))
	must(t, e)
	var raw []byte
	must(t, db.QueryRow("SELECT value FROM updater_state WHERE id=1").Scan(&raw))
	var st updater.State
	must(t, json.Unmarshal(raw, &st))
	st.Layout = 0
	st.Swap = ""
	st.RepairPending = false
	raw, e = json.Marshal(st)
	must(t, e)
	_, e = db.Exec("UPDATE updater_state SET value=? WHERE id=1", string(raw))
	must(t, e)
	must(t, db.Close())
	f.b.POSBinaryLayout = 0
	f.publish()
	if e = f.i.Install(context.Background(), true); e == nil {
		t.Fatal("old Edge accepted current-slot layout")
	}
	if !existsSetup(filepath.Join(old, updater.Executable)) || existsSetup(updater.CurrentDir(l.POS())) {
		t.Fatal("incompatible repair moved binaries")
	}
}
