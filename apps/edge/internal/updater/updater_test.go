package updater

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fixture struct {
	s            *Service
	p            *simProcess
	cfg          Config
	m            Manifest
	key          ed25519.PrivateKey
	artifact     []byte
	server       *httptest.Server
	raw          []byte
	downloadFail bool
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	f := &fixture{}
	pub, private, e := ed25519.GenerateKey(rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	f.key = private
	var b bytes.Buffer
	z := zip.NewWriter(&b)
	w, _ := z.Create(Executable)
	_, _ = w.Write([]byte("signed synthetic Windows bundle; never execute on macOS"))
	_ = z.Close()
	f.artifact = b.Bytes()
	h := sha256.Sum256(f.artifact)
	f.server = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/feed" {
			_, _ = w.Write(f.raw)
		} else if f.downloadFail {
			w.Header().Set("Content-Length", "100000")
			_, _ = w.Write([]byte("partial"))
		} else {
			_, _ = w.Write(f.artifact)
		}
	}))
	t.Cleanup(f.server.Close)
	f.m = Manifest{Product: Product, Version: "1.9.0", Release: 19, OS: "windows", Arch: "amd64", Channel: "stable", URL: f.server.URL + "/bundle", SHA256: hex.EncodeToString(h[:]), Size: int64(len(f.artifact)), Expires: time.Now().Add(time.Hour), UpdaterProtocol: 1, HiveSchema: 9, EdgeSchema: 2, DataPolicy: "hive9-no-migration"}
	f.sign()
	f.cfg = Config{Root: t.TempDir(), Feed: f.server.URL + "/feed", Channel: "stable", InitialVersion: "1.8.0", InitialRelease: 18, Token: strings.Repeat("a", 64), Listen: "127.0.0.1:7444", Keys: map[string]TrustedKey{"test-only": {Public: base64.StdEncoding.EncodeToString(pub), Expires: time.Now().Add(24 * time.Hour)}}}
	f.p = &simProcess{children: map[string]*exec.Cmd{}, failVersion: "", token: f.cfg.Token}
	f.s, e = Open(f.cfg, f.p)
	if e != nil {
		t.Fatal(e)
	}
	f.s.client = f.server.Client()
	f.s.healthTimeout = 2 * time.Second
	api := httptest.NewServer(f.s.Handler())
	f.p.url = api.URL
	t.Cleanup(api.Close)
	t.Cleanup(func() { _ = f.s.Close(); f.p.close() })
	return f
}
func (f *fixture) sign() {
	payload, _ := json.Marshal(f.m)
	f.raw, _ = json.Marshal(Envelope{KeyID: "test-only", Payload: base64.StdEncoding.EncodeToString(payload), Signature: base64.StdEncoding.EncodeToString(ed25519.Sign(f.key, append([]byte(signatureDomain), payload...)))})
}
func waitState(t *testing.T, s *Service, want string) {
	t.Helper()
	end := time.Now().Add(8 * time.Second)
	for time.Now().Before(end) {
		st := s.Snapshot()
		if st.Status == want {
			return
		}
		if st.Status == "FAILED" && want != "FAILED" {
			t.Fatalf("failed: %+v", st)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("want %s got %+v", want, s.Snapshot())
}

const requestID = "95a67a17-9e32-4fb8-8eee-c570ad897040"

func TestStageRestartInstallAndIdempotency(t *testing.T) {
	f := newFixture(t)
	if e := f.s.Check(context.Background()); e != nil {
		t.Fatal(e)
	}
	waitState(t, f.s, "READY_TO_INSTALL")
	if f.p.starts() != 0 {
		t.Fatal("download executed artifact")
	}
	// Later has no server side install action; an Edge restart keeps the zip.
	if e := f.s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e := Open(f.cfg, f.p)
	if e != nil {
		t.Fatal(e)
	}
	f.s = s
	f.s.client = f.server.Client()
	f.s.healthTimeout = 2 * time.Second
	api := httptest.NewServer(f.s.Handler())
	defer api.Close()
	f.p.url = api.URL
	if s.Snapshot().Status != "READY_TO_INSTALL" {
		t.Fatal(s.Snapshot())
	}
	if e = s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, false); e != nil {
		t.Fatal(e)
	}
	waitState(t, s, "BLOCKED")
	if f.p.starts() != 0 {
		t.Fatal("blocked started")
	}
	if e = s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 5; i++ {
		if e = s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e != nil {
			t.Fatal(e)
		}
	}
	waitState(t, s, "SUCCESS")
	if f.p.starts() != 1 {
		t.Fatal("repeated install launched multiple POS processes")
	}
	if e = s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e != nil {
		t.Fatal(e)
	}
	if f.p.starts() != 1 {
		t.Fatal("completed request replay")
	}
}
func TestFailedCandidateRollsBackWithoutDataRollback(t *testing.T) {
	f := newFixture(t)
	data := filepath.Join(t.TempDir(), "restaurant.hive")
	original := []byte("durable open Order + occupied Table + pending cloud outbox")
	if e := os.WriteFile(data, original, 0600); e != nil {
		t.Fatal(e)
	}
	f.p.failVersion = "1.9.0"
	if e := f.s.Check(context.Background()); e != nil {
		t.Fatal(e)
	}
	if e := f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e != nil {
		t.Fatal(e)
	}
	waitState(t, f.s, "ROLLED_BACK")
	st := f.s.Snapshot()
	if st.Current != "1.8.0" || st.High != 19 || f.p.starts() != 2 {
		t.Fatal(st)
	}
	got, _ := os.ReadFile(data)
	if !bytes.Equal(got, original) {
		t.Fatal("rollback touched restaurant data")
	}
}
func TestRejectBadReleaseAndCorruptDownloads(t *testing.T) {
	for _, name := range []string{"signature", "product", "os", "arch", "schema", "dataPolicy", "older", "expired", "unknownKey", "hash", "network"} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			switch name {
			case "product":
				f.m.Product = "vynic-manager"
			case "os":
				f.m.OS = "darwin"
			case "arch":
				f.m.Arch = "arm64"
			case "schema":
				f.m.HiveSchema = 10
			case "dataPolicy":
				f.m.DataPolicy = "migrate"
			case "older":
				f.m.Version = "1.7.0"
			case "expired":
				f.m.Expires = time.Now().Add(-time.Second)
			case "hash":
				f.m.SHA256 = strings.Repeat("0", 64)
			case "network":
				f.downloadFail = true
			}
			f.sign()
			if name == "signature" {
				f.raw[len(f.raw)-5] ^= 1
			}
			if name == "unknownKey" {
				f.cfg.Keys = map[string]TrustedKey{}
				f.s.cfg.Keys = f.cfg.Keys
			}
			if e := f.s.Check(context.Background()); e == nil {
				t.Fatal("accepted invalid release")
			}
			waitState(t, f.s, "FAILED")
			if f.p.starts() != 0 {
				t.Fatal("executed rejected release")
			}
		})
	}
}
func TestReverifyStagedArtifactAndExpiry(t *testing.T) {
	for _, name := range []string{"tamper", "keyRevoked"} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			if e := f.s.Check(context.Background()); e != nil {
				t.Fatal(e)
			}
			if name == "tamper" {
				_ = os.WriteFile(f.s.artifact(), []byte("evil"), 0600)
			} else {
				delete(f.s.cfg.Keys, "test-only")
			}
			if e := f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e == nil {
				t.Fatal("accepted staged corruption")
			}
			if f.p.starts() != 0 {
				t.Fatal("executed")
			}
		})
	}
}
func TestCrashDuringActivationRecoversPrevious(t *testing.T) {
	f := newFixture(t)
	f.s.mu.Lock()
	f.s.state.Status = "RESTARTING"
	f.s.state.Attempt = requestID
	f.s.state.Previous = "1.8.0"
	f.s.state.Current = "1.9.0"
	f.s.state.Version = "1.9.0"
	f.s.state.High = 19
	_ = f.s.saveLocked()
	f.s.mu.Unlock()
	if e := f.s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e := Open(f.cfg, f.p)
	if e != nil {
		t.Fatal(e)
	}
	f.s = s
	s.healthTimeout = 2 * time.Second
	api := httptest.NewServer(s.Handler())
	defer api.Close()
	f.p.url = api.URL
	if e = s.Recover(); e != nil {
		t.Fatal(e)
	}
	waitState(t, s, "ROLLED_BACK")
	if s.Snapshot().Current != "1.8.0" {
		t.Fatal(s.Snapshot())
	}
}
func TestIPCAuthorizationAndWrongProcess(t *testing.T) {
	f := newFixture(t)
	r := httptest.NewRequest("POST", "/v1/install", strings.NewReader(`{}`))
	w := httptest.NewRecorder()
	f.s.Handler().ServeHTTP(w, r)
	if w.Code != 401 {
		t.Fatal(w.Code)
	}
	if e := f.s.Check(context.Background()); e != nil {
		t.Fatal(e)
	}
	if e := f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 999, true); e == nil {
		t.Fatal("accepted wrong process")
	}
}
func TestArchivePaths(t *testing.T) {
	for _, name := range []string{"../escape", "C:/evil.exe", "a\\evil", "CON", "file:ads", "a. /x"} {
		t.Run(name, func(t *testing.T) {
			var b bytes.Buffer
			z := zip.NewWriter(&b)
			w, _ := z.Create(name)
			_, _ = w.Write([]byte("x"))
			_ = z.Close()
			p := filepath.Join(t.TempDir(), "x.zip")
			_ = os.WriteFile(p, b.Bytes(), 0600)
			if e := extract(p, t.TempDir()); e == nil {
				t.Fatal("accepted unsafe path")
			}
		})
	}
}

// Real child processes simulate startup/health/crash on macOS. Downloaded
// synthetic .exe bytes are deliberately not executed on the wrong OS.
type simProcess struct {
	mu                      sync.Mutex
	children                map[string]*exec.Cmd
	count                   int
	url, token, failVersion string
	badDataVersion          string
}

func (p *simProcess) Validate(pid int, path string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if pid == 111 {
		return nil
	}
	if c := p.children[path]; c != nil && c.Process.Pid == pid {
		return nil
	}
	return errors.New("wrong process")
}
func (p *simProcess) Stop(path string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if c := p.children[path]; c != nil {
		_ = c.Process.Kill()
		_ = c.Wait()
		delete(p.children, path)
	}
	return nil
}
func (p *simProcess) Start(path string, env []string) (int, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.count++
	c := exec.Command(os.Args[0], "-test.run=^TestUpdaterChild$")
	c.Env = append(os.Environ(), env...)
	c.Env = append(c.Env, "VYNIC_TEST_CHILD=1", "VYNIC_TEST_URL="+p.url, "VYNIC_TEST_TOKEN="+p.token, "VYNIC_TEST_DATA="+filepath.Join(filepath.Dir(filepath.Dir(filepath.Dir(path))), "restaurant-data"))
	if strings.Contains(path, p.failVersion) && p.failVersion != "" {
		c.Env = append(c.Env, "VYNIC_TEST_FAIL=1")
	}
	if p.badDataVersion != "" && strings.Contains(path, p.badDataVersion) {
		c.Env = append(c.Env, "VYNIC_TEST_BAD_DATA=1")
	}
	if e := c.Start(); e != nil {
		return 0, e
	}
	p.children[path] = c
	return c.Process.Pid, nil
}
func (p *simProcess) starts() int { p.mu.Lock(); defer p.mu.Unlock(); return p.count }
func (p *simProcess) close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, c := range p.children {
		_ = c.Process.Kill()
		_ = c.Wait()
	}
}
func TestUpdaterChild(t *testing.T) {
	if os.Getenv("VYNIC_TEST_CHILD") != "1" {
		t.Skip("subprocess only")
	}
	if os.Getenv("VYNIC_TEST_FAIL") == "1" {
		os.Exit(23)
	}
	time.Sleep(50 * time.Millisecond)
	dataPath := os.Getenv("VYNIC_TEST_DATA")
	if os.Getenv("VYNIC_TEST_BAD_DATA") == "1" {
		dataPath = filepath.Join(dataPath, "unexpected-empty-db")
	}
	b, _ := json.Marshal(map[string]any{"nonce": os.Getenv("VYNIC_POS_UPDATE_NONCE"), "version": os.Getenv("VYNIC_POS_UPDATE_VERSION"), "pid": os.Getpid(), "dataPath": dataPath, "hiveSchema": 9})
	r, _ := http.NewRequest("POST", os.Getenv("VYNIC_TEST_URL")+"/v1/health", bytes.NewReader(b))
	r.Header.Set("Authorization", "Bearer "+os.Getenv("VYNIC_TEST_TOKEN"))
	resp, e := http.DefaultClient.Do(r)
	if e != nil {
		os.Exit(24)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		os.Exit(25)
	}
	time.Sleep(30 * time.Second)
	os.Exit(0)
}

func TestInterruptedDownloadRetryAndSingleOwner(t *testing.T) {
	f := newFixture(t)
	if s, e := Open(f.cfg, f.p); e == nil {
		s.Close()
		t.Fatal("two updater owners")
	}
	f.downloadFail = true
	if e := f.s.Check(context.Background()); e == nil {
		t.Fatal("download unexpectedly succeeded")
	}
	f.downloadFail = false
	if e := f.s.Check(context.Background()); e != nil {
		t.Fatal(e)
	}
	if f.s.Snapshot().Downloaded != f.m.Size {
		t.Fatal("progress mismatch")
	}
	if e := f.s.Install(requestID, "1.8.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e == nil {
		t.Fatal("wrong staged version accepted")
	}
	if e := f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e != nil {
		t.Fatal(e)
	}
	waitState(t, f.s, "SUCCESS")
	if e := f.s.Install(requestID, "2.0.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e == nil {
		t.Fatal("idempotency ID allowed changed version")
	}
}
func TestCorruptedUpdaterStateRefused(t *testing.T) {
	for _, kind := range []string{"json", "schema", "path"} {
		t.Run(kind, func(t *testing.T) {
			f := newFixture(t)
			switch kind {
			case "json":
				_, _ = f.s.db.Exec(`UPDATE updater_state SET value='{'`)
			case "schema":
				_, _ = f.s.db.Exec(`PRAGMA ignore_check_constraints=ON; UPDATE updater_state SET version=8;`)
			case "path":
				_, _ = f.s.db.Exec(`UPDATE updater_state SET value='{"status":"SUCCESS","current":"../escape"}'`)
			}
			_ = f.s.Close()
			s, e := Open(f.cfg, f.p)
			if e == nil {
				s.Close()
				t.Fatal("corrupt updater state accepted")
			}
		})
	}
}

func TestWrongDataDirectoryCannotPassStartupHealth(t *testing.T) {
	f := newFixture(t)
	f.p.badDataVersion = "1.9.0"
	if e := f.s.Check(context.Background()); e != nil {
		t.Fatal(e)
	}
	if e := f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true); e != nil {
		t.Fatal(e)
	}
	waitState(t, f.s, "ROLLED_BACK")
	if f.s.Snapshot().Current != "1.8.0" || !f.s.Snapshot().StartupVerified {
		t.Fatal(f.s.Snapshot())
	}
}
