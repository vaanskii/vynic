package setup

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"vynic.local/edge/internal/updater"
)

// Models process/health transport only; the real updater downloads, verifies,
// installs, records consent and completes its production 30-second probation.
// No downloaded executable or real printer is run.
type syntheticHealthProcess struct {
	handler     http.Handler
	token, data string
	stop        chan struct{}
}

func (p *syntheticHealthProcess) Running(string) (bool, error) { return false, nil }
func (p *syntheticHealthProcess) Validate(pid int, _ string) error {
	if pid != 123 {
		return errors.New("unexpected synthetic pid")
	}
	return nil
}
func (p *syntheticHealthProcess) Stop(string) error { return nil }
func (p *syntheticHealthProcess) Start(_ string, env []string) (int, error) {
	values := map[string]string{}
	for _, entry := range env {
		parts := strings.SplitN(entry, "=", 2)
		if len(parts) == 2 {
			values[parts[0]] = parts[1]
		}
	}
	raw, _ := json.Marshal(map[string]any{"nonce": values["VYNIC_POS_UPDATE_NONCE"], "version": values["VYNIC_POS_UPDATE_VERSION"], "pid": 123, "dataPath": p.data, "hiveSchema": 9})
	go func() {
		tick := time.NewTicker(100 * time.Millisecond)
		defer tick.Stop()
		for {
			select {
			case <-p.stop:
				return
			case <-tick.C:
				req := httptest.NewRequest("POST", "https://fixture.invalid/v1/health", bytes.NewReader(raw))
				req.Header.Set("Authorization", "Bearer "+p.token)
				p.handler.ServeHTTP(httptest.NewRecorder(), req)
			}
		}
	}()
	return 123, nil
}

func TestPOSOnlyThenPairedUpgradeUsesActualSignedRecoveryArtifact(t *testing.T) {
	f := healthyFixture(t)
	l := f.i.Layout
	r, e := Load(l)
	must(t, e)
	archive := bundle(t, map[string]string{updater.Executable: "licensed POS-only candidate", "flutter_windows.dll": "dll", "data/icudtl.dat": "icu", "data/flutter_assets/AssetManifest.bin": "assets"})
	_, prior, e := Verify(r.Bootstrap, r.Distribution, time.Now())
	must(t, e)
	prior.Version = "1.8.1"
	prior.Release = 2
	prior.URL = f.s.URL + "/pos-only.zip"
	prior.Size = int64(len(archive))
	digest := sha256.Sum256(archive)
	prior.SHA256 = hex.EncodeToString(digest[:])
	proof := signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", prior)
	f.set("/pos-only.zip", archive)
	f.set("/pos.json", proof)
	f.set("/pos-releases/1.8.1.json", proof)
	oldTransport := http.DefaultTransport
	http.DefaultTransport = f.s.Client().Transport
	defer func() { http.DefaultTransport = oldTransport }()
	data, e := filepath.EvalSymlinks(t.TempDir())
	must(t, e)
	p := &syntheticHealthProcess{token: r.Config.Token, data: data, stop: make(chan struct{})}
	u, e := updater.OpenExisting(r.Config, p)
	must(t, e)
	p.handler = u.Handler()
	must(t, u.Check(context.Background()))
	must(t, u.Install("0d6cc2e6-13e8-4d8c-8407-847965d83562", prior.Version, data, 123, true))
	deadline := time.Now().Add(45 * time.Second)
	for u.Snapshot().Status != "SUCCESS" && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
	}
	st := u.Snapshot()
	close(p.stop)
	must(t, u.Close())
	if st.Status != "SUCCESS" || st.Current != prior.Version || !st.StartupVerified {
		t.Fatalf("POS-only update failed: %+v", st)
	}
	// Bootstrap deliberately remains 1.8.0; current POS is now 1.8.1.
	f.p.Release = 3
	f.b.Release = 3
	f.b.Edge.Release = 3
	f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", f.p)
	f.publish()
	for _, reason := range []string{"unsigned", "pre-license", "wrong-version", "wrong-hash"} {
		t.Run(reason, func(t *testing.T) {
			bad := prior
			switch reason {
			case "pre-license":
				bad.LicenseProtocol = 0
			case "wrong-version":
				bad.Version = "1.8.0"
			case "wrong-hash":
				bad.SHA256 = strings.Repeat("0", 64)
			}
			raw := signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", bad)
			if reason == "unsigned" {
				raw = []byte(`{"keyId":"test","payload":"e30=","signature":"AA=="}`)
			}
			f.set("/pos-releases/1.8.1.json", raw)
			if e := f.i.Upgrade(context.Background()); e == nil {
				t.Fatal("unproven current release admitted")
			}
			if upgradeState(t, f).Current != prior.Version {
				t.Fatal("rejected proof changed installed POS")
			}
		})
	}
	f.set("/pos-releases/1.8.1.json", proof)
	must(t, f.i.Upgrade(context.Background()))
	j, e := f.i.readUpgrade()
	must(t, e)
	stored, e := updater.Verify(j.PreviousPOSProof, r.Distribution.Keys, r.Distribution.Channel, "0.0.0", 0, time.Now())
	must(t, e)
	if j.PreviousPOS != prior.Version || stored.Version != prior.Version || stored.SHA256 != prior.SHA256 || stored.LicenseProtocol != 1 {
		t.Fatal("journal did not retain actual current signed proof")
	}
	backup := filepath.Join(l.upgradeDir(), "previous-pos.zip")
	must(t, os.WriteFile(backup, []byte("tampered recovery ZIP"), 0600))
	if e = f.i.RecoverUpgrade(context.Background()); e == nil {
		t.Fatal("tampered recovery archive admitted")
	}
	if upgradeState(t, f).Current != f.p.Version {
		t.Fatal("tampered archive replaced candidate")
	}
	must(t, os.WriteFile(backup, archive, 0600))
	must(t, f.i.RecoverUpgrade(context.Background()))
	st = upgradeState(t, f)
	if st.Current != prior.Version || st.High != 3 {
		t.Fatalf("actual current rollback/counter lost: %+v", st)
	}
	got, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
	must(t, e)
	if string(got) != "licensed POS-only candidate" {
		t.Fatal("recovered bootstrap baseline instead of actual current POS")
	}
}
