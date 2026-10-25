package setup

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
	"vynic.local/edge/internal/updater"
)

func healthyFixture(t *testing.T) *fixture {
	f := newFixture(t)
	f.p.LicenseProtocol = 1
	f.p.URL = f.s.URL + "/baseline-pos.zip"
	f.set("/baseline-pos.zip", f.responses["/pos.zip"])
	f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", f.p)
	f.publish()
	f.install()
	r, e := Load(f.i.Layout)
	must(t, e)
	db, e := sql.Open("sqlite", filepath.Join(f.i.Layout.POS(), "updater.sqlite"))
	must(t, e)
	var raw []byte
	must(t, db.QueryRow("SELECT value FROM updater_state WHERE id=1").Scan(&raw))
	var st updater.State
	must(t, json.Unmarshal(raw, &st))
	st.Swap = ""
	st.RepairPending = false
	st.StartupVerified = true
	st.Previous = ""
	raw, e = json.Marshal(st)
	must(t, e)
	_, e = db.Exec("UPDATE updater_state SET value=? WHERE id=1", raw)
	must(t, e)
	must(t, db.Close())
	_ = r
	pos := bundle(t, map[string]string{updater.Executable: "new POS", "flutter_windows.dll": "dll", "data/icudtl.dat": "icu", "data/flutter_assets/AssetManifest.bin": "assets"})
	edge := bundle(t, map[string]string{EdgeExecutable: "new Edge"})
	sum := sha256.Sum256(pos)
	f.p.URL = f.s.URL + "/pos.zip"
	f.p.Version = "1.9.0"
	f.p.Release = 2
	f.p.Size = int64(len(pos))
	f.p.SHA256 = hex.EncodeToString(sum[:])
	f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", f.p)
	sum = sha256.Sum256(edge)
	f.b.Edge.Version = "1.0.1"
	f.b.Edge.Release = 2
	f.b.Edge.Size = int64(len(edge))
	f.b.Edge.SHA256 = hex.EncodeToString(sum[:])
	f.b.Release = 2
	f.set("/pos.zip", pos)
	f.set("/edge.zip", edge)
	f.publish()
	must(t, os.WriteFile(f.i.SetupSource, []byte("new setup"), 0600))
	return f
}
func upgradeState(t *testing.T, f *fixture) updater.State {
	t.Helper()
	r, e := Load(f.i.Layout)
	must(t, e)
	u, e := updater.OpenExisting(r.Config, updater.NativeProcess{})
	must(t, e)
	st := u.Snapshot()
	must(t, u.Close())
	return st
}
func TestCoordinatedUpgradeAndHealthCommit(t *testing.T) {
	f := healthyFixture(t)
	l := f.i.Layout
	r, e := Load(l)
	must(t, e)
	sentinel := filepath.Join(l.EdgeData(), "business-sentinel")
	must(t, os.WriteFile(sentinel, []byte("retained"), 0600))
	must(t, f.i.Upgrade(context.Background()))
	next, e := Load(l)
	must(t, e)
	if next.EdgeVersion != "1.0.1" || next.Config.Token != r.Config.Token || next.BootstrapHigh != 2 {
		t.Fatal("pair or identity mismatch")
	}
	st := upgradeState(t, f)
	if st.Current != "1.9.0" || st.Previous != "1.8.0" || st.High != 2 || !st.RepairPending {
		t.Fatalf("bad probation %+v", st)
	}
	if e = f.i.CompleteUpgrade(st); e == nil {
		t.Fatal("accepted unhealthy candidate")
	}
	st.StartupVerified = true
	must(t, f.i.CompleteUpgrade(st))
	if _, e = os.Stat(l.upgradeJournal()); !os.IsNotExist(e) {
		t.Fatal("journal retained after complete")
	}
	b, e := os.ReadFile(sentinel)
	must(t, e)
	if string(b) != "retained" {
		t.Fatal("data touched")
	}
}
func TestCoordinatedRecoveryPreservesHighWaterDataAndOldPair(t *testing.T) {
	for _, phase := range []string{"prepared", "probation"} {
		t.Run(phase, func(t *testing.T) {
			f := healthyFixture(t)
			l := f.i.Layout
			old, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
			must(t, e)
			r, e := Load(l)
			must(t, e)
			must(t, f.i.Upgrade(context.Background()))
			j, e := f.i.readUpgrade()
			must(t, e)
			j.Phase = phase
			must(t, writeJSON(l.upgradeJournal(), j))
			must(t, f.i.RecoverUpgrade(context.Background()))
			restored, e := Load(l)
			must(t, e)
			if restored.EdgeVersion != r.EdgeVersion || restored.Config.Token != r.Config.Token || restored.BootstrapHigh != 2 {
				t.Fatal("old pair or monotonic bootstrap lost")
			}
			coordinator, e := os.ReadFile(l.Setup())
			must(t, e)
			if string(coordinator) != "new setup" {
				t.Fatal("coordinator downgraded")
			}
			st := upgradeState(t, f)
			if st.Current != "1.8.0" || st.High != 2 || st.Swap != "" {
				t.Fatalf("counter/state lost %+v", st)
			}
			got, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
			must(t, e)
			if string(got) != string(old) {
				t.Fatal("old POS not restored")
			}
			if e = f.i.Upgrade(context.Background()); e == nil {
				t.Fatal("replayed failed release")
			}
		})
	}
}
func TestCoordinatedRejectsUnqualifiedUpgrade(t *testing.T) {
	for _, reason := range []string{"same-edge", "same-pos", "changed-feed", "busy", "signature"} {
		t.Run(reason, func(t *testing.T) {
			f := healthyFixture(t)
			switch reason {
			case "same-edge":
				f.b.Edge.Version = "1.0.0"
			case "same-pos":
				f.p.Version = "1.8.0"
				f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", f.p)
			case "changed-feed":
				f.b.POSFeed += "changed"
			case "busy":
				f.h.quiesceErr = errors.New("POS is open")
			case "signature":
				f.b.Edge.SHA256 = "00"
			}
			f.publish()
			if e := f.i.Upgrade(context.Background()); e == nil {
				t.Fatal("unsafe upgrade admitted")
			}
			r, e := Load(f.i.Layout)
			must(t, e)
			if r.EdgeVersion != "1.0.0" {
				t.Fatal("baseline changed")
			}
		})
	}
}
func TestCoordinatedRecoveryRefusesOpenPOSAndTamperedJournal(t *testing.T) {
	f := healthyFixture(t)
	must(t, f.i.Upgrade(context.Background()))
	f.h.quiesceErr = errors.New("POS open")
	if e := f.i.RecoverUpgrade(context.Background()); e == nil {
		t.Fatal("recovery ignored running POS")
	}
	f.h.quiesceErr = nil
	j, e := f.i.readUpgrade()
	must(t, e)
	j.Previous.Config.Root = t.TempDir()
	must(t, writeJSON(f.i.Layout.upgradeJournal(), j))
	if e = f.i.RecoverUpgrade(context.Background()); e == nil {
		t.Fatal("tampered recovery accepted")
	}
}
func TestCoordinatedCommittedCleanupRetriesWithoutRollback(t *testing.T) {
	f := healthyFixture(t)
	must(t, f.i.Upgrade(context.Background()))
	j, e := f.i.readUpgrade()
	must(t, e)
	j.Phase = "committed"
	must(t, writeJSON(f.i.Layout.upgradeJournal(), j))
	must(t, os.RemoveAll(f.i.Layout.upgradeDir()))
	must(t, f.i.RecoverUpgrade(context.Background()))
	r, e := Load(f.i.Layout)
	must(t, e)
	if r.EdgeVersion != "1.0.1" {
		t.Fatal("committed pair rolled back")
	}
}

func TestCoordinatedRestoredCleanupRetriesWithoutCounterLoss(t *testing.T) {
	f := healthyFixture(t)
	must(t, f.i.Upgrade(context.Background()))
	j, e := f.i.readUpgrade()
	must(t, e)
	must(t, f.i.RecoverUpgrade(context.Background()))
	j.Phase = "restored"
	j.Previous.BootstrapHigh = j.Candidate.BootstrapRelease
	must(t, writeJSON(f.i.Layout.upgradeJournal(), j))
	must(t, f.i.RecoverUpgrade(context.Background()))
	if upgradeState(t, f).High != 2 {
		t.Fatal("release counter lost")
	}
}

func TestCoordinatedRecoveryRefusesUnlicensedOrUnprovenBaseline(t *testing.T) {
	for _, reason := range []string{"legacy", "unknown-protocol", "different-pos", "bad-signature", "changed-trust"} {
		t.Run(reason, func(t *testing.T) {
			f := healthyFixture(t)
			l := f.i.Layout
			sentinel := filepath.Join(l.EdgeData(), "business-sentinel")
			must(t, os.WriteFile(sentinel, []byte("business data"), 0600))
			must(t, f.i.Upgrade(context.Background()))
			before, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
			must(t, e)
			j, e := f.i.readUpgrade()
			must(t, e)
			b, p, e := Verify(j.Previous.Bootstrap, j.Previous.Distribution, time.Now())
			must(t, e)
			switch reason {
			case "legacy":
				p.LicenseProtocol = 0
			case "unknown-protocol":
				p.LicenseProtocol = 2
			case "different-pos":
				p.Version = "1.7.0"
			}
			b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", p)
			if reason == "bad-signature" {
				b.POS = []byte(`{"keyId":"test","payload":"e30=","signature":"AA=="}`)
			}
			j.PreviousPOSProof = b.POS
			if reason == "changed-trust" {
				j.Candidate.Distribution.Channel = "beta"
			}
			must(t, f.i.writeUpgrade(j))
			if e = f.i.RecoverUpgrade(context.Background()); e == nil {
				t.Fatal("unsafe rollback admitted")
			}
			after, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
			must(t, e)
			if string(after) != string(before) {
				t.Fatal("candidate replaced by unsafe fallback")
			}
			if upgradeState(t, f).High != 2 {
				t.Fatal("high-water changed")
			}
			data, e := os.ReadFile(sentinel)
			must(t, e)
			if string(data) != "business data" {
				t.Fatal("business data changed")
			}
			if _, e = os.Stat(l.upgradeJournal()); e != nil {
				t.Fatal("recovery evidence removed", e)
			}
			if _, e = os.Stat(filepath.Join(l.upgradeDir(), "previous-pos")); e != nil {
				t.Fatal("previous binaries removed", e)
			}
		})
	}
}

func TestCoordinatedMigrationRestrictionPrecedesBinaryMutation(t *testing.T) {
	for _, reason := range []string{"legacy-baseline", "unlicensed-candidate"} {
		t.Run(reason, func(t *testing.T) {
			f := healthyFixture(t)
			l := f.i.Layout
			before, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
			must(t, e)
			if reason == "legacy-baseline" {
				r, e := Load(l)
				must(t, e)
				b, p, e := Verify(r.Bootstrap, r.Distribution, time.Now())
				must(t, e)
				p.LicenseProtocol = 0
				b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", p)
				r.Bootstrap = signed(t, f.k, SignatureDomain, b)
				must(t, writeJSON(l.Receipt(), r))
			} else {
				f.p.LicenseProtocol = 0
				f.b.POS = signed(t, f.k, "VYNIC-POS-RELEASE-v1\n", f.p)
				f.publish()
			}
			if e = f.i.Upgrade(context.Background()); e == nil {
				t.Fatal("unqualified migration admitted")
			}
			after, e := os.ReadFile(updater.CurrentExecutable(l.POS()))
			must(t, e)
			if string(after) != string(before) {
				t.Fatal("old installation mutated")
			}
			if _, e = os.Stat(l.upgradeJournal()); !os.IsNotExist(e) {
				t.Fatal("unsafe migration left a rollback journal")
			}
			if upgradeState(t, f).High != 1 {
				t.Fatal("counter changed before migration qualification")
			}
		})
	}
}
