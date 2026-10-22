package printerdaemon

import (
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
)

func TestDaemonActualMTLSHealthAndMutatingRPCRemainHeld(t *testing.T) {
	f := fixture(t, "")
	d, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopDaemon(t, d)
	client, _ := connectFixture(t, f, d.Address())
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	h, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: healthAuth(f)})
	if err != nil {
		t.Fatal(err)
	}
	if !h.SoftwareReady || h.State != pb.PrinterAgentLifecycle_PRINTER_AGENT_RUNNING || h.PhysicalState != pb.PrinterAgentPhysicalState_PRINTER_AGENT_PHYSICAL_HELD || h.AdmissionState != pb.PrinterAgentAdmissionState_PRINTER_AGENT_ADMISSION_HELD_PROVISIONING {
		t.Fatalf("incorrect held health: %v", h)
	}
	r := testRegistry(f)
	j := frozenJob(t, f, r, false)
	if _, err = client.SubmitLocal(ctx, &pb.PrinterAgentSubmitLocalRequest{Auth: healthAuth(f), RequestId: j.RequestID, JobId: j.JobID, EnvelopeSha256: j.Digest(), FrozenEnvelope: j.Raw()}); status.Code(err) != codes.FailedPrecondition {
		t.Fatalf("unexpected submit result: %v", err)
	}
	if _, err = client.GetLocalResult(ctx, &pb.PrinterAgentGetLocalResultRequest{Auth: healthAuth(f), RequestId: j.RequestID, JobId: j.JobID, EnvelopeSha256: j.Digest()}); status.Code(err) != codes.FailedPrecondition {
		t.Fatalf("unexpected result lookup: %v", err)
	}
	// A separate store cannot mutate or inspect through a second writer while
	// this instance owns the actual dedicated DB.
	if other, err := store.Open(f.config.StateDirectory, false); err == nil {
		other.Close()
		t.Fatal("second store writer admitted")
	}
	other, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = other.Start(ctx); err == nil {
		stopDaemon(t, other)
		t.Fatal("second host admitted")
	}
	stopDaemon(t, other)
	if other.Address() != "" {
		t.Fatal("second host bound a listener")
	}
}

func TestDaemonStopDeadlineRetainsOriginalAdmissionDBAndOwner(t *testing.T) {
	f := fixture(t, "")
	d, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	entered, release, done := make(chan struct{}), make(chan struct{}), make(chan error, 1)
	go func() {
		done <- d.Host().WithAdmission(context.Background(), f.config.Pins, 2, func(context.Context) error { close(entered); <-release; return nil })
	}()
	<-entered
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	if err = d.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("stop: %v", err)
	}
	cancel()
	if other, err := store.Open(f.config.StateDirectory, false); err == nil {
		other.Close()
		t.Fatal("Stop deadline released actual DB")
	}
	if err = d.Host().WithAdmission(context.Background(), f.config.Pins, 2, func(context.Context) error { t.Fatal("new transaction admitted"); return nil }); err == nil {
		t.Fatal("new admission accepted")
	}
	other, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = other.Start(context.Background()); err == nil {
		t.Fatal("Stop deadline released host guard")
	}
	stopDaemon(t, other)
	close(release)
	if err = <-done; err != nil {
		t.Fatal(err)
	}
	stopDaemon(t, d)
	restarted, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = restarted.Start(context.Background()); err != nil {
		t.Fatal("settled drain did not release owner:", err)
	}
	stopDaemon(t, restarted)
}

func TestDaemonBindFailureClosesActualStorageBeforeRestart(t *testing.T) {
	f := fixture(t, "")
	occupied, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer occupied.Close()
	f.config.ListenAddress = occupied.Addr().String()
	f.save(t)
	d, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err == nil {
		t.Fatal("occupied listener accepted")
	}
	stopDaemon(t, d)
	if d.Address() != "" {
		t.Fatal("failed startup retained listener")
	}
	storage, err := store.Open(f.config.StateDirectory, false)
	if err != nil {
		t.Fatal("startup leaked writer:", err)
	}
	if err = storage.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestDaemonTrustedArtifactChangeLatchesDrainAndVisibleError(t *testing.T) {
	for _, artifact := range []string{"helper", "profile", "state-marker"} {
		t.Run(artifact, func(t *testing.T) {
			f := fixture(t, "")
			d, err := New(f.config, f.config.Agent.Path)
			if err != nil {
				t.Fatal(err)
			}
			if err = d.Start(context.Background()); err != nil {
				t.Fatal(err)
			}
			path := f.config.Helper.Path
			if artifact == "profile" {
				path = f.config.CapabilityProfile.Path
			}
			if artifact == "state-marker" {
				path = filepath.Join(f.config.StateDirectory, StateMarkerFilename)
			}
			original, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			writeBytes(t, path, []byte("replaced pinned input"))
			h, err := d.Health(context.Background())
			if err == nil || h.Ready {
				t.Fatal("changed current file still reported ready")
			}
			waitCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err = d.Wait(waitCtx); err == nil {
				t.Fatal("trusted failure hidden from foreground wait")
			}
			stopDaemon(t, d)
			writeBytes(t, path, original)
			// A later apparently good file cannot clear the prior composition.
			if _, err = d.Health(context.Background()); err == nil {
				t.Fatal("latched trusted failure auto-cleared")
			}
			storage, err := store.Open(f.config.StateDirectory, false)
			if err != nil {
				t.Fatal("drained failed host retained DB:", err)
			}
			storage.Close()
		})
	}
}

func TestDaemonUnexpectedListenerExitDrainsAndPreservesFailure(t *testing.T) {
	f := fixture(t, "")
	d, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	client, _ := connectFixture(t, f, d.Address())
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: healthAuth(f)}); err != nil {
		t.Fatal(err)
	}
	d.mu.Lock()
	listener := d.listener
	d.mu.Unlock()
	if err = listener.Close(); err != nil {
		t.Fatal(err)
	}
	if err = d.Wait(ctx); err == nil {
		t.Fatal("unexpected Serve failure hidden")
	}
	stopDaemon(t, d)
	storage, err := store.Open(f.config.StateDirectory, false)
	if err != nil {
		t.Fatal(err)
	}
	storage.Close()
}

func TestDaemonCallerCancellationDoesNotStopHealthyHost(t *testing.T) {
	f := fixture(t, "")
	d, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopDaemon(t, d)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err = d.Health(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled request: %v", err)
	}
	h, err := d.Health(context.Background())
	if err != nil || !h.Ready || h.State != printhost.Running {
		t.Fatalf("caller canceled whole host: %+v %v", h, err)
	}
}

type fixtureOwner struct{ close func() error }

func (o fixtureOwner) Close() error { return o.close() }
func TestDaemonUnresolvedStartupCleanupRetainsDBAndHostOwner(t *testing.T) {
	f := fixture(t, "")
	storage, err := store.Open(f.config.StateDirectory, false)
	if err != nil {
		t.Fatal(err)
	}
	foreign := queueIdentity(f)
	foreign.DeviceID = uuid.NewString()
	q, err := printqueue.NewProofStore(context.Background(), storage.DB, foreign)
	if err != nil {
		t.Fatal(err)
	}
	r := testRegistry(f)
	r.DeviceID = foreign.DeviceID
	if err = q.Register(context.Background(), r); err != nil {
		t.Fatal(err)
	}
	storage.Close()
	var mutex sync.Mutex
	owned := false
	released := 0
	acquire := func(string) (printhost.Owner, error) {
		mutex.Lock()
		defer mutex.Unlock()
		if owned {
			return nil, errors.New("fixture owner retained")
		}
		owned = true
		return fixtureOwner{close: func() error { mutex.Lock(); defer mutex.Unlock(); owned = false; released++; return nil }}, nil
	}
	closeFailure := errors.New("synthetic unresolved storage close")
	var retained *store.Store
	d, err := newWithHooks(f.config, f.config.Agent.Path, daemonHooks{acquire: acquire, closeStorage: func(s *store.Store) error { retained = s; return closeFailure }})
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err == nil || !errors.Is(err, printqueue.ErrScope) {
		t.Fatalf("original startup failure absent: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err = d.Stop(ctx); !errors.Is(err, closeFailure) {
		t.Fatalf("close failure hidden: %v", err)
	}
	mutex.Lock()
	kept := owned && released == 0
	mutex.Unlock()
	if !kept || retained == nil {
		t.Fatal("cleanup failure released resources")
	}
	if s, err := store.Open(f.config.StateDirectory, false); err == nil {
		s.Close()
		t.Fatal("cleanup failure released SQLite exclusion")
	}
	second, err := newWithHooks(f.config, f.config.Agent.Path, daemonHooks{acquire: acquire})
	if err != nil {
		t.Fatal(err)
	}
	if err = second.Start(ctx); err == nil || !strings.Contains(err.Error(), "retained") {
		t.Fatal("new host bypassed retained owner", err)
	}
	stopDaemon(t, second)
	// Explicit test-only cleanup; the production host remains irreversibly held.
	if err = retained.Close(); err != nil {
		t.Fatal(err)
	}
	d.Host() // no recovery/takeover API exists
}
func seedRetainedQueue(t *testing.T, f softwareFixture) (printqueue.FrozenJob, printqueue.FrozenJob) {
	t.Helper()
	storage, err := store.Open(f.config.StateDirectory, false)
	if err != nil {
		t.Fatal(err)
	}
	q, err := printqueue.NewProofStore(context.Background(), storage.DB, queueIdentity(f))
	if err != nil {
		t.Fatal(err)
	}
	r1, r2 := testRegistry(f), testRegistry(f)
	r2.Destination.Port = 9101
	for _, r := range []printqueue.Registry{r1, r2} {
		if err = q.Register(context.Background(), r); err != nil {
			t.Fatal(err)
		}
	}
	j1, j2 := frozenJob(t, f, r1, false), frozenJob(t, f, r2, true)
	for _, j := range []printqueue.FrozenJob{j1, j2} {
		a := printqueue.Authority{VenueID: j.VenueID, InstallationID: j.InstallationID, OriginInstallationID: j.OriginInstallationID, TerminalID: j.TerminalID, Epoch: 1}
		if _, err = q.Accept(context.Background(), a, j); err != nil {
			t.Fatal(err)
		}
	}
	injected := errors.New("synthetic persisted crash window")
	sender := &syntheticSender{}
	worker, err := printqueue.NewProofScheduler(context.Background(), q, sender, printqueue.ProofOptions{WorkerID: uuid.NewString(), GuardFactory: func(string) (printtransport.PrinterGuard, error) { return syntheticGuard{}, nil }, AfterPersist: func(b printqueue.Boundary, j printqueue.FrozenJob) error {
		if j.JobID == j1.JobID && b == printqueue.StartedFlushed || j.JobID == j2.JobID && b == printqueue.BeepReservedFlushed {
			return injected
		}
		return nil
	}})
	if err != nil {
		t.Fatal(err)
	}
	for _, j := range []printqueue.FrozenJob{j1, j2} {
		if err = worker.RunNext(j.PhysicalPrinterID); !errors.Is(err, injected) {
			t.Fatal(err)
		}
	}
	if sender.sends != 1 {
		t.Fatal("unexpected synthetic primary/beep count", sender.sends)
	}
	if err = worker.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err = storage.Close(); err != nil {
		t.Fatal(err)
	}
	return j1, j2
}
func assertRetainedQueue(t *testing.T, f softwareFixture, j1, j2 printqueue.FrozenJob) {
	t.Helper()
	storage, err := store.Open(f.config.StateDirectory, false)
	if err != nil {
		t.Fatal(err)
	}
	defer storage.Close()
	q, err := printqueue.NewProofStore(context.Background(), storage.DB, queueIdentity(f))
	if err != nil {
		t.Fatal(err)
	}
	o1, err := q.Outcome(context.Background(), j1.JobID)
	if err != nil {
		t.Fatal(err)
	}
	o2, err := q.Outcome(context.Background(), j2.JobID)
	if err != nil {
		t.Fatal(err)
	}
	if o1.Primary != printqueue.Uncertain || o1.Phase != "hold" || o2.Primary != printqueue.Submitted || o2.Beep != printqueue.BeepUncertain || o2.Phase != "complete" {
		t.Fatalf("recovery/replay disposition: %+v %+v", o1, o2)
	}
	for _, j := range []printqueue.FrozenJob{j1, j2} {
		var raw []byte
		var attempts int
		if err = storage.DB.QueryRow("SELECT envelope FROM pq_job WHERE job_id=?", j.JobID).Scan(&raw); err != nil {
			t.Fatal(err)
		}
		if string(raw) != string(j.Raw()) {
			t.Fatal("queued frozen destination/profile changed")
		}
		if err = storage.DB.QueryRow("SELECT count(*) FROM pq_attempt WHERE job_id=?", j.JobID).Scan(&attempts); err != nil || attempts != 1 {
			t.Fatal("original primary replayed", attempts, err)
		}
	}
	var beeps int
	if err = storage.DB.QueryRow("SELECT count(*) FROM pq_beep WHERE job_id=?", j2.JobID).Scan(&beeps); err != nil || beeps != 1 {
		t.Fatal("spent beep replayed", beeps, err)
	}
}
func TestDaemonActualSQLiteRecoveryNeverReplaysStartedOrSpentBeep(t *testing.T) {
	f := fixture(t, "")
	j1, j2 := seedRetainedQueue(t, f)
	for i := 0; i < 2; i++ {
		d, err := New(f.config, f.config.Agent.Path)
		if err != nil {
			t.Fatal(err)
		}
		if err = d.Start(context.Background()); err != nil {
			t.Fatal(err)
		}
		h, err := d.Health(context.Background())
		if err != nil || !h.Ready || len(h.PrinterHolds) != 1 || h.BlockedReason == "" {
			t.Fatalf("retained per-printer hold not visible: %+v %v", h, err)
		}
		stopDaemon(t, d)
		assertRetainedQueue(t, f, j1, j2)
	}
}

func TestSharedHeldReportsInfrastructureWithoutSharedPhysicalAuthority(t *testing.T) {
	f := fixture(t, "")
	f.config.Profile = SharedHeld
	f.config.Pins.Scope = printhost.VenueShared
	f.config.Pins.OwnershipPolicy = printhost.ClusterLogicalOnly
	f.config.Pins.ClusterID = uuid.NewString()
	f.config.Pins.MembershipSHA256 = bytesHash([]byte("explicit synthetic stable member descriptor"))
	f.config.Pins.GatewayHostID = ""
	f.save(t)
	d, err := New(f.config, f.config.Agent.Path)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopDaemon(t, d)
	client, _ := connectFixture(t, f, d.Address())
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	h, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: healthAuth(f)})
	if err != nil {
		t.Fatal(err)
	}
	if !h.SoftwareReady || h.PhysicalState != pb.PrinterAgentPhysicalState_PRINTER_AGENT_PHYSICAL_HELD || h.AdmissionState != pb.PrinterAgentAdmissionState_PRINTER_AGENT_ADMISSION_HELD_PROVISIONING {
		t.Fatal("shared physical/provisioning readiness misreported")
	}
	found := false
	for _, reason := range h.HoldReasons {
		if reason == pb.PrinterAgentHoldReason_PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED {
			found = true
		}
	}
	if !found {
		t.Fatal("shared downstream physical fence gap hidden")
	}
}
