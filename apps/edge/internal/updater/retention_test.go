package updater

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func mustRetention(t *testing.T, e error) {
	t.Helper()
	if e != nil {
		t.Fatal(e)
	}
}
func assertOnlyCurrent(t *testing.T, f *fixture, version string) {
	t.Helper()
	v, e := ReleaseVersion(CurrentDir(f.cfg.Root))
	mustRetention(t, e)
	if v != version {
		t.Fatalf("current=%s want=%s", v, version)
	}
	for _, p := range []string{RollbackDir(f.cfg.Root), StagingDir(f.cfg.Root), filepath.Join(f.cfg.Root, "releases"), filepath.Join(f.cfg.Root, "staged.zip"), filepath.Join(f.cfg.Root, "staged.zip.part")} {
		if _, e = os.Stat(p); !os.IsNotExist(e) {
			t.Fatalf("historical/temp binaries retained at %s: %v", p, e)
		}
	}
	if f.s.Snapshot().CleanupPending {
		t.Fatal("cleanup still pending")
	}
}
func protectedSentinels(t *testing.T, f *fixture) func() {
	t.Helper()
	paths := []string{"restaurant-data/orders.hive", "restaurant-data/tables.hive", "restaurant-data/outbox.hive", "state/edge.db", "config/credentials.json", "journals/intent.json", "logs/support.log"}
	for _, p := range paths {
		file := filepath.Join(f.cfg.Root, p)
		mustRetention(t, os.MkdirAll(filepath.Dir(file), 0700))
		mustRetention(t, os.WriteFile(file, []byte("persisted "+p), 0600))
	}
	return func() {
		t.Helper()
		for _, p := range paths {
			b, e := os.ReadFile(filepath.Join(f.cfg.Root, p))
			mustRetention(t, e)
			if string(b) != "persisted "+p {
				t.Fatalf("modified protected state %s", p)
			}
		}
	}
}
func TestRepeatedUpdatesRetainOnlyCurrentAndPreserveDurableData(t *testing.T) {
	f := newFixture(t)
	verify := protectedSentinels(t, f)
	for n, v := range []string{"1.9.0", "1.10.0", "1.11.0"} {
		// Stop the simulated active child before changing fixture server metadata.
		if n > 0 {
			mustRetention(t, f.p.Stop(CurrentExecutable(f.cfg.Root)))
		}
		f.m.Version = v
		f.m.Release = uint64(19 + n)
		f.sign()
		mustRetention(t, f.s.Check(context.Background()))
		if !exists(CandidateDir(f.cfg.Root)) || !exists(f.s.artifact()) {
			t.Fatal("download/extraction not staged")
		}
		id := []string{requestID, "95a67a17-9e32-4fb8-8eee-c570ad897041", "95a67a17-9e32-4fb8-8eee-c570ad897042"}[n]
		mustRetention(t, f.s.Install(id, v, filepath.Join(f.cfg.Root, "restaurant-data"), 111, true))
		waitState(t, f.s, "SUCCESS")
		assertOnlyCurrent(t, f, v)
		verify()
	}
}
func TestProbationRetainsRollbackUntilRepeatedHealthPasses(t *testing.T) {
	f := newFixture(t)
	f.s.stabilization = 600 * time.Millisecond
	mustRetention(t, f.s.Check(context.Background()))
	mustRetention(t, f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true))
	deadline := time.Now().Add(2 * time.Second)
	for f.p.starts() == 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	time.Sleep(100 * time.Millisecond)
	if !exists(RollbackDir(f.cfg.Root)) || f.s.Snapshot().StartupVerified {
		t.Fatal("rollback deleted/input released before stabilization")
	}
	waitState(t, f.s, "SUCCESS")
	assertOnlyCurrent(t, f, "1.9.0")
}
func TestCrashAfterInitialHealthRollsBackAndCleansCandidate(t *testing.T) {
	f := newFixture(t)
	verify := protectedSentinels(t, f)
	f.p.crashVersion = "1.9.0"
	mustRetention(t, f.s.Check(context.Background()))
	mustRetention(t, f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true))
	waitState(t, f.s, "ROLLED_BACK")
	assertOnlyCurrent(t, f, "1.8.0")
	verify()
	if f.s.Snapshot().High != 19 {
		t.Fatal("rollback lowered replay high-water")
	}
}
func TestLaterSurvivesOrdinaryLaunchAndRepairStabilization(t *testing.T) {
	for _, repair := range []bool{false, true} {
		t.Run(map[bool]string{false: "launch", true: "repair"}[repair], func(t *testing.T) {
			f := newFixture(t)
			mustRetention(t, f.s.Check(context.Background()))
			if repair {
				mustRetention(t, f.s.PrepareRepair(false))
				mustRetention(t, moveBinary(CurrentDir(f.cfg.Root), RollbackDir(f.cfg.Root)))
				mustRetention(t, os.MkdirAll(CurrentDir(f.cfg.Root), 0700))
				mustRetention(t, MarkRelease(CurrentDir(f.cfg.Root), "1.8.0"))
				mustRetention(t, f.s.RegisterRepair(true))
				mustRetention(t, f.s.Recover())
				if f.p.starts() != 0 || !exists(RollbackDir(f.cfg.Root)) {
					t.Fatal("repair auto launched/cleaned without Open")
				}
			}
			mustRetention(t, f.s.launch())
			if f.s.Snapshot().Status != "READY_TO_INSTALL" || !exists(f.s.artifact()) || !exists(CandidateDir(f.cfg.Root)) {
				t.Fatal("Later candidate lost")
			}
			if exists(RollbackDir(f.cfg.Root)) {
				t.Fatal("healthy repair left rollback")
			}
		})
	}
}
func TestCleanupFailureRetriesAfterRestartWithoutRollback(t *testing.T) {
	f := newFixture(t)
	mustRetention(t, f.s.Check(context.Background()))
	// A junction/symlink in rollback must fail cleanup safely, even after success.
	target := filepath.Join(f.cfg.Root, "restaurant-data")
	mustRetention(t, os.MkdirAll(target, 0700))
	mustRetention(t, os.WriteFile(filepath.Join(target, "keep"), []byte("data"), 0600))
	mustRetention(t, os.Symlink(target, filepath.Join(CurrentDir(f.cfg.Root), "unexpected-link")))
	// Model durable stable success and partially completed deletion without execution.
	mustRetention(t, moveBinary(CurrentDir(f.cfg.Root), RollbackDir(f.cfg.Root)))
	mustRetention(t, moveBinary(CandidateDir(f.cfg.Root), CurrentDir(f.cfg.Root)))
	f.s.mu.Lock()
	f.s.state.Current = "1.9.0"
	f.s.state.High = 19
	f.s.mu.Unlock()
	mustRetention(t, f.s.finishStable("SUCCESS", "", true))
	if !f.s.Snapshot().CleanupPending || f.s.Snapshot().Status != "SUCCESS" {
		t.Fatal("cleanup error lost success/intent")
	}
	mustRetention(t, os.Remove(filepath.Join(RollbackDir(f.cfg.Root), "unexpected-link")))
	mustRetention(t, f.s.Close())
	s, e := Open(f.cfg, f.p)
	mustRetention(t, e)
	f.s = s
	fastHealth(s)
	mustRetention(t, s.Recover())
	assertOnlyCurrent(t, f, "1.9.0")
	if f.p.starts() != 0 {
		t.Fatal("cleanup restart unexpectedly launched/rolled back")
	}
	if b, e := os.ReadFile(filepath.Join(target, "keep")); e != nil || string(b) != "data" {
		t.Fatal("followed binary link into data")
	}
}
func makeLegacy(t *testing.T, f *fixture) {
	t.Helper()
	old := filepath.Join(f.cfg.Root, "releases", "1.8.0")
	mustRetention(t, os.MkdirAll(filepath.Dir(old), 0700))
	mustRetention(t, moveBinary(CurrentDir(f.cfg.Root), old))
	history := filepath.Join(f.cfg.Root, "releases", "1.7.0")
	mustRetention(t, os.MkdirAll(history, 0700))
	mustRetention(t, os.WriteFile(filepath.Join(history, Executable), []byte("historical"), 0600))
	if exists(f.s.artifact()) {
		mustRetention(t, moveBinary(f.s.artifact(), filepath.Join(f.cfg.Root, "staged.zip")))
	}
	f.s.mu.Lock()
	f.s.state.Layout = 0
	mustRetention(t, f.s.saveLocked())
	f.s.mu.Unlock()
}
func TestLegacyMigrationPreservesLaterThenPrunesAfterHealthyStartup(t *testing.T) {
	f := newFixture(t)
	mustRetention(t, f.s.Check(context.Background()))
	makeLegacy(t, f)
	mustRetention(t, f.s.Recover())
	if f.s.Snapshot().Layout != binaryLayout || !exists(f.s.artifact()) || !exists(filepath.Join(f.cfg.Root, "releases", "1.7.0")) {
		t.Fatal("migration discarded candidate/history prematurely")
	}
	mustRetention(t, f.s.launch())
	if exists(filepath.Join(f.cfg.Root, "releases")) || !exists(f.s.artifact()) {
		t.Fatal("migration cleanup violated retention/Later")
	}
}
func TestLegacyExplicitUpdateUsesCurrentSlot(t *testing.T) {
	f := newFixture(t)
	mustRetention(t, f.s.Check(context.Background()))
	makeLegacy(t, f)
	mustRetention(t, f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true))
	waitState(t, f.s, "SUCCESS")
	assertOnlyCurrent(t, f, "1.9.0")
}
func TestManagedDeletionRefusesDataAndUnknownPaths(t *testing.T) {
	f := newFixture(t)
	for _, p := range []string{f.cfg.Root, filepath.Join(f.cfg.Root, "updater.sqlite"), filepath.Join(f.cfg.Root, "config"), filepath.Join(f.cfg.Root, "staging", "..", "config")} {
		if e := f.s.removeBinary(p); e == nil {
			t.Fatalf("deleted nonbinary path %s", p)
		}
	}
	mustRetention(t, f.s.Check(context.Background()))
	if e := f.s.Install(requestID, "1.9.0", filepath.Join(CurrentDir(f.cfg.Root), "Hive"), 111, true); e == nil {
		t.Fatal("accepted data inside replaceable binaries")
	}
}

// Kill a real helper after each filesystem/SQLite boundary, then reopen the DB
// and use the normal recovery path. No deferred cleanup can mask these crashes.
func TestBinarySwapCrashMatrix(t *testing.T) {
	for _, point := range []string{"prepared", "old_moved", "candidate_moved", "starting", "restoring", "restored", "stable", "cleanup_partial"} {
		t.Run(point, func(t *testing.T) {
			f := newFixture(t)
			verify := protectedSentinels(t, f)
			mustRetention(t, f.s.Check(context.Background()))
			mustRetention(t, f.s.Close())
			config := filepath.Join(f.cfg.Root, "crash-config.json")
			b, e := json.Marshal(f.cfg)
			mustRetention(t, e)
			mustRetention(t, os.WriteFile(config, b, 0600))
			c := exec.Command(os.Args[0], "-test.run=^TestRetentionCrashChild$")
			c.Env = append(os.Environ(), "VYNIC_RETENTION_CONFIG="+config, "VYNIC_RETENTION_POINT="+point)
			out, e := c.CombinedOutput()
			var code *exec.ExitError
			if !errors.As(e, &code) || code.ExitCode() != 91 {
				t.Fatalf("crash fixture %v %s", e, out)
			}
			s, e := Open(f.cfg, f.p)
			mustRetention(t, e)
			f.s = s
			fastHealth(s)
			api := httptest.NewServer(s.Handler())
			defer api.Close()
			f.p.url = api.URL
			mustRetention(t, s.Recover())
			want := "1.8.0"
			if point == "stable" || point == "cleanup_partial" {
				want = "1.9.0"
				if f.p.starts() != 0 {
					t.Fatal("stable commit rolled back")
				}
			}
			assertOnlyCurrent(t, f, want)
			verify()
		})
	}
}
func TestRetentionCrashChild(t *testing.T) {
	config := os.Getenv("VYNIC_RETENTION_CONFIG")
	if config == "" {
		t.Skip("crash helper")
	}
	var cfg Config
	b, e := os.ReadFile(config)
	mustRetention(t, e)
	mustRetention(t, json.Unmarshal(b, &cfg))
	s, e := OpenExisting(cfg, NativeProcess{})
	mustRetention(t, e)
	point := os.Getenv("VYNIC_RETENTION_POINT")
	crash := func(p string) {
		if point == p {
			os.Exit(91)
		}
	}
	s.state.Previous = "1.8.0"
	s.state.Version = "1.9.0"
	s.state.Attempt = requestID
	s.state.Swap = "prepared"
	s.state.Status = "INSTALLING"
	mustRetention(t, s.saveLocked())
	crash("prepared")
	s.state.Swap = "activating"
	mustRetention(t, s.saveLocked())
	mustRetention(t, moveBinary(CurrentDir(cfg.Root), RollbackDir(cfg.Root)))
	crash("old_moved")
	mustRetention(t, moveBinary(CandidateDir(cfg.Root), CurrentDir(cfg.Root)))
	crash("candidate_moved")
	s.state.Current = "1.9.0"
	s.state.High = 19
	s.state.Swap = "starting"
	s.state.Status = "RESTARTING"
	mustRetention(t, s.saveLocked())
	crash("starting")
	if strings.HasPrefix(point, "restor") {
		s.state.Swap = "restoring"
		mustRetention(t, s.saveLocked())
		mustRetention(t, s.removeBinary(CurrentDir(cfg.Root)))
		crash("restoring")
		mustRetention(t, moveBinary(RollbackDir(cfg.Root), CurrentDir(cfg.Root)))
		crash("restored")
	}
	s.state.Status = "SUCCESS"
	s.state.StartupVerified = true
	s.state.CleanupPending = true
	s.state.DiscardStaging = true
	s.state.Swap = "cleanup"
	mustRetention(t, s.saveLocked())
	crash("stable")
	mustRetention(t, s.removeBinary(RollbackDir(cfg.Root)))
	crash("cleanup_partial")
	t.Fatal("unknown checkpoint")
}

func TestLiveProcessWithoutContinuedHiveReadinessCannotStabilize(t *testing.T) {
	f := newFixture(t)
	f.p.quietVersion = "1.9.0"
	mustRetention(t, f.s.Check(context.Background()))
	mustRetention(t, f.s.Install(requestID, "1.9.0", filepath.Join(f.cfg.Root, "restaurant-data"), 111, true))
	waitState(t, f.s, "ROLLED_BACK")
	assertOnlyCurrent(t, f, "1.8.0")
	if !strings.Contains(f.s.Snapshot().Reason, "heartbeat timeout") {
		t.Fatal("missing heartbeat was not diagnosed")
	}
}

func TestRepairAfterRemovalDoesNotAdvertiseDeletedStaging(t *testing.T) {
	f := newFixture(t)
	mustRetention(t, f.s.Check(context.Background()))
	mustRetention(t, os.RemoveAll(CurrentDir(f.cfg.Root)))
	mustRetention(t, os.RemoveAll(StagingDir(f.cfg.Root)))
	mustRetention(t, f.s.PrepareRepair(true))
	st := f.s.Snapshot()
	if st.Status != "UP_TO_DATE" || st.Version != "" || len(st.Envelope) != 0 || st.High != 18 {
		t.Fatal("removed staging advertised/reset history", st)
	}
}

func TestVerifiedOrdinaryLaunchNeedsFreshHealthButNotStabilization(t *testing.T) {
	f := newFixture(t)
	f.s.state.StartupVerified = true
	f.s.state.DataPath = filepath.Join(f.cfg.Root, "restaurant-data")
	mustRetention(t, f.s.saveLocked())
	f.s.stabilization = time.Hour
	done := make(chan error, 1)
	go func() { done <- f.s.launch() }()
	select {
	case e := <-done:
		mustRetention(t, e)
	case <-time.After(2 * time.Second):
		t.Fatal("verified ordinary launch repeated stabilization")
	}
	if !f.s.Snapshot().StartupVerified || f.p.starts() != 1 {
		t.Fatal("fresh health was not verified")
	}
}

func TestVerifiedOrdinaryLaunchStillRejectsWrongDataHealth(t *testing.T) {
	f := newFixture(t)
	f.s.state.StartupVerified = true
	f.s.state.DataPath = filepath.Join(f.cfg.Root, "restaurant-data")
	mustRetention(t, f.s.saveLocked())
	f.p.badDataVersion = f.cfg.InitialVersion
	f.s.healthTimeout = 300 * time.Millisecond
	if e := f.s.launch(); e == nil {
		t.Fatal("wrong data path admitted on quick launch")
	}
	if f.s.Snapshot().StartupVerified {
		t.Fatal("failed launch reported ready")
	}
}

func TestRepairOfVerifiedReleaseStillRequiresStabilization(t *testing.T) {
	f := newFixture(t)
	f.s.state.StartupVerified = true
	f.s.state.DataPath = filepath.Join(f.cfg.Root, "restaurant-data")
	mustRetention(t, f.s.saveLocked())
	mustRetention(t, f.s.PrepareRepair(false))
	mustRetention(t, f.s.RegisterRepair(false))
	start := time.Now()
	mustRetention(t, f.s.launch())
	if time.Since(start) < f.s.stabilization {
		t.Fatal("repair bypassed stabilization")
	}
}
