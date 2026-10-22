package printhost

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
)

type nonphysicalSender struct {
	call func(context.Context, printtransport.Destination, []byte) printtransport.Result
}

func (*nonphysicalSender) Physical() bool { return false }
func (s *nonphysicalSender) Send(ctx context.Context, d printtransport.Destination, p []byte) printtransport.Result {
	return s.call(ctx, d, p)
}

type observedGuard struct {
	closed func()
}

func (g *observedGuard) Context(ctx context.Context) context.Context { return ctx }
func (g *observedGuard) Close() error {
	if g.closed != nil {
		g.closed()
	}
	return nil
}

func syntheticSubmitted(p []byte) printtransport.Result {
	return printtransport.Result{State: printtransport.Submitted, Stage: "synthetic", WriteAttempted: true, BytesWritten: uint32(len(p))}
}

type queueFixture struct {
	storage *store.Store
	queue   *printqueue.Store
	pins    Pins
	dir     string
}

func openQueueFixture(t *testing.T, dir string, create bool) queueFixture {
	t.Helper()
	storage, err := store.Open(dir, create)
	if err != nil {
		t.Fatal(err)
	}
	pins := gatewayPins()
	queue, err := printqueue.NewProofStore(context.Background(), storage.DB, printqueue.GatewayIdentity{VenueID: pins.VenueID, InstallationID: pins.InstallationID, DeviceID: pins.DeviceID, WorkerHostID: pins.HostID, Epoch: pins.AuthorityEpoch})
	if err != nil {
		storage.Close()
		t.Fatal(err)
	}
	return queueFixture{storage: storage, queue: queue, pins: pins, dir: dir}
}

func registerPrinter(t *testing.T, f queueFixture, n int) printqueue.Registry {
	t.Helper()
	r := printqueue.Registry{PhysicalPrinterID: id(n), VenueID: f.pins.VenueID, InstallationID: f.pins.InstallationID, AuthorityEpoch: f.pins.AuthorityEpoch, DeviceID: f.pins.DeviceID, WorkerHostID: f.pins.HostID, BindingRevision: 1, ConfigRevision: 1, RegistryRevision: 1, Aliases: []string{id(n + 1000)}, Destination: printtransport.Destination{PhysicalPrinterID: id(n), WorkerHostID: f.pins.HostID, Transport: printtransport.TCP, Host: "127.0.0.1", Port: uint16(9000 + n)}}
	if err := f.queue.Register(context.Background(), r); err != nil {
		t.Fatal(err)
	}
	return r
}

func frozenJob(t *testing.T, r printqueue.Registry, n int, beep bool) printqueue.FrozenJob {
	t.Helper()
	primary := []byte(fmt.Sprintf("synthetic frozen job %d\n", n))
	hash := sha256.Sum256(primary)
	d := r.Destination
	d.DocumentName = fmt.Sprintf("synthetic job %d", n)
	profile := json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"none","encoding":"georgianViaRaster","beep":{"capability":"epsonEscA97Pattern","enabled":false}}`)
	if beep {
		profile = bytes.ReplaceAll(profile, []byte("false"), []byte("true"))
	}
	j := printqueue.FrozenJob{Version: 1, JobID: id(n), EffectID: id(n + 10000), RequestID: id(n + 20000), TerminalID: id(500), VenueID: r.VenueID, InstallationID: r.InstallationID, OriginInstallationID: id(501), AuthorityEpoch: r.AuthorityEpoch, DeviceID: r.DeviceID, PhysicalPrinterID: r.PhysicalPrinterID, AliasID: r.Aliases[0], RouteRevision: 1, ConfigRevision: r.ConfigRevision, BindingRevision: r.BindingRevision, RegistryRevision: r.RegistryRevision, AttemptID: id(n + 30000), BeepAttemptID: id(n + 40000), Destination: d, CapabilityProfile: profile, PrimaryBytes: primary, PrimarySHA256: hex.EncodeToString(hash[:])}
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	j, err = printqueue.DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	return j
}

func jobAuthority(j printqueue.FrozenJob) printqueue.Authority {
	return printqueue.Authority{VenueID: j.VenueID, InstallationID: j.InstallationID, OriginInstallationID: j.OriginInstallationID, TerminalID: j.TerminalID, Epoch: j.AuthorityEpoch}
}

func acceptJob(t *testing.T, queue *printqueue.Store, j printqueue.FrozenJob) {
	t.Helper()
	if _, err := queue.Accept(context.Background(), jobAuthority(j), j); err != nil {
		t.Fatal(err)
	}
}

func proofHost(t *testing.T, f queueFixture, scheduler *printqueue.Scheduler, ids []string, owner *memoryOwner, closed *atomic.Bool) *Host {
	t.Helper()
	probe, err := QueueProbe(f.queue, f.pins, ids)
	if err != nil {
		t.Fatal(err)
	}
	components, err := ComposeProofGateway(f.queue, scheduler, ids, probe, func() error { closed.Store(true); return f.storage.Close() })
	if err != nil {
		t.Fatal(err)
	}
	host, err := NewHost(Config{Pins: f.pins, Acquire: func(string) (Owner, error) { return owner, nil }}, func(context.Context, Pins) (Components, error) { return components, nil })
	if err != nil {
		t.Fatal(err)
	}
	return host
}

func awaitSignal(t *testing.T, signal <-chan struct{}) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(2 * time.Second):
		t.Fatal("synthetic worker did not reach expected boundary")
	}
}

// This is an actual same-SQLite transaction, not a mocked business callback.
// Authentication/replication are deliberately outside this LOCAL proof fixture.
func commitBusinessAndPrint(ctx context.Context, db *sql.DB, j printqueue.FrozenJob) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, "INSERT INTO op_entity(kind,id,revision,tombstone,document) VALUES('ORDER',?,1,0,?)", id(700), []byte(`{"synthetic":"committed"}`)); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO op_event(sequence,authority_epoch,request_id,terminal_id,event) VALUES(1,1,?,?,?)", j.RequestID, j.TerminalID, []byte(`{"synthetic":"event"}`)); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO op_effect(id,kind,request_id,event_sequence,ordinal,payload) VALUES(?,'PRINT',?,1,0,?)", j.EffectID, j.RequestID, j.Raw()); err != nil {
		return err
	}
	if _, err = printqueue.AdmitTx(ctx, tx, jobAuthority(j), j); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO op_request(request_id,terminal_id,authority_epoch,digest,outcome,event_sequence,result) VALUES(?,?,1,?,'COMMITTED',1,?)", j.RequestID, j.TerminalID, bytes.Repeat([]byte{1}, 32), []byte(`{"synthetic":"result"}`)); err != nil {
		return err
	}
	return tx.Commit()
}

func TestActualQueueP1StallAllowsP2BusinessAndPrintAndDrainsBeep(t *testing.T) {
	f := openQueueFixture(t, t.TempDir(), true)
	p1, p2 := registerPrinter(t, f, 21), registerPrinter(t, f, 22)
	j1, j2, j3 := frozenJob(t, p1, 10, true), frozenJob(t, p1, 11, false), frozenJob(t, p2, 12, false)
	acceptJob(t, f.queue, j1)
	if _, err := f.storage.DB.Exec("INSERT INTO terminal(id,display_name,verifier,created_at) VALUES(?,'synthetic','synthetic',0)", j3.TerminalID); err != nil {
		t.Fatal(err)
	}
	primaryStarted, beepStarted, primaryRelease, beepRelease := make(chan struct{}), make(chan struct{}), make(chan struct{}), make(chan struct{})
	var releasePrimary, releaseBeep sync.Once
	defer releasePrimary.Do(func() { close(primaryRelease) })
	defer releaseBeep.Do(func() { close(beepRelease) })
	var p1Calls atomic.Int32
	var p1GuardClosed, resourcesClosed atomic.Bool
	sender := &nonphysicalSender{call: func(ctx context.Context, d printtransport.Destination, p []byte) printtransport.Result {
		if ctx.Err() != nil {
			return printtransport.Result{State: printtransport.Uncertain, Stage: "abandoned original", WriteAttempted: true}
		}
		if d.PhysicalPrinterID == p1.PhysicalPrinterID {
			switch p1Calls.Add(1) {
			case 1:
				close(primaryStarted)
				<-primaryRelease
			case 2:
				close(beepStarted)
				<-beepRelease
			default:
				return printtransport.Result{State: printtransport.Uncertain, Stage: "unexpected replay", WriteAttempted: true}
			}
		}
		return syntheticSubmitted(p)
	}}
	options := printqueue.ProofOptions{WorkerID: id(900), GuardFactory: func(printer string) (printtransport.PrinterGuard, error) {
		return &observedGuard{closed: func() {
			if printer == p1.PhysicalPrinterID {
				p1GuardClosed.Store(true)
			}
		}}, nil
	}}
	scheduler, err := printqueue.NewProofScheduler(context.Background(), f.queue, sender, options)
	if err != nil {
		t.Fatal(err)
	}
	owner := &memoryOwner{}
	host := proofHost(t, f, scheduler, []string{p1.PhysicalPrinterID, p2.PhysicalPrinterID}, owner, &resourcesClosed)
	if err := host.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	awaitSignal(t, primaryStarted)
	if err := host.WithAdmission(context.Background(), f.pins, ReaderVersion, func(ctx context.Context) error { return commitBusinessAndPrint(ctx, f.storage.DB, j3) }); err != nil {
		t.Fatal("P1 stall disabled P2 business commit", err)
	}
	if err := host.WithAdmission(context.Background(), f.pins, ReaderVersion, func(ctx context.Context) error { _, err := f.queue.Accept(ctx, jobAuthority(j2), j2); return err }); err != nil {
		t.Fatal("P1 stall disabled persisted FIFO admission", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	outcome, err := scheduler.Wait(ctx, j3.JobID)
	if err != nil || outcome.Primary != printqueue.Submitted {
		t.Fatal("independent P2 did not progress", outcome, err)
	}
	var entities int
	if err := f.storage.DB.QueryRow("SELECT count(*) FROM op_entity WHERE id=?", id(700)).Scan(&entities); err != nil || entities != 1 {
		t.Fatal("business/print transaction did not commit", entities, err)
	}
	health, err := host.Health(context.Background())
	if err != nil || !health.Ready || len(health.PrinterHolds) != 1 || health.PrinterHolds[0].PhysicalPrinterID != p1.PhysicalPrinterID {
		t.Fatal("per-printer hold lost or became global admission failure", health, err)
	}
	if err := CheckUpgrade(f.pins, health, ReaderVersion); !errors.Is(err, ErrHeld) {
		t.Fatal("upgrade ignored actual original lifetime", err)
	}
	deadline, done := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer done()
	if err := host.Stop(deadline); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("Stop did not retain original primary", err)
	}
	if resourcesClosed.Load() || owner.closed.Load() || p1GuardClosed.Load() {
		t.Fatal("primary deadline released ownership")
	}
	if other, err := store.Open(f.dir, false); err == nil {
		other.Close()
		t.Fatal("Stop timeout freed database owner")
	}
	releasePrimary.Do(func() { close(primaryRelease) })
	awaitSignal(t, beepStarted)
	deadline2, done2 := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer done2()
	if err := host.Stop(deadline2); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("Stop did not retain optional beep", err)
	}
	if resourcesClosed.Load() || owner.closed.Load() || p1GuardClosed.Load() {
		t.Fatal("beep deadline released ownership")
	}
	releaseBeep.Do(func() { close(beepRelease) })
	stopHost(t, host)
	if !resourcesClosed.Load() || !owner.closed.Load() || !p1GuardClosed.Load() || p1Calls.Load() != 2 {
		t.Fatal("actual primary/beep drain did not close once")
	}
	reopened := openQueueFixture(t, f.dir, false)
	defer reopened.storage.Close()
	first, err := reopened.queue.Outcome(context.Background(), j1.JobID)
	if err != nil || first.Primary != printqueue.Submitted || first.Beep != printqueue.BeepSubmitted {
		t.Fatal("frozen primary/beep evidence lost", first, err)
	}
	queued, err := reopened.queue.Outcome(context.Background(), j2.JobID)
	if err != nil || queued.Primary != printqueue.Queued {
		t.Fatal("shutdown claimed or rerouted queued successor", queued, err)
	}
}

func TestRecoveredStartedRemainsUncertainWithoutReplay(t *testing.T) {
	f := openQueueFixture(t, t.TempDir(), true)
	p1, p2 := registerPrinter(t, f, 21), registerPrinter(t, f, 22)
	j1, j2 := frozenJob(t, p1, 10, true), frozenJob(t, p2, 12, false)
	acceptJob(t, f.queue, j1)
	var sends atomic.Int32
	sender := &nonphysicalSender{call: func(context.Context, printtransport.Destination, []byte) printtransport.Result {
		sends.Add(1)
		return printtransport.Result{State: printtransport.NotSent, Stage: "synthetic"}
	}}
	options := printqueue.ProofOptions{WorkerID: id(900), GuardFactory: func(string) (printtransport.PrinterGuard, error) { return &observedGuard{}, nil }, AfterPersist: func(boundary printqueue.Boundary, _ printqueue.FrozenJob) error {
		if boundary == printqueue.StartedFlushed {
			return errors.New("synthetic interrupted STARTED")
		}
		return nil
	}}
	first, err := printqueue.NewProofScheduler(context.Background(), f.queue, sender, options)
	if err != nil {
		t.Fatal(err)
	}
	if err := first.RunNext(p1.PhysicalPrinterID); err == nil {
		t.Fatal("interruption seam did not retain STARTED")
	}
	if err := first.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := f.storage.Close(); err != nil {
		t.Fatal(err)
	}
	f = openQueueFixture(t, f.dir, false)
	sender.call = func(_ context.Context, d printtransport.Destination, p []byte) printtransport.Result {
		if d.PhysicalPrinterID == p1.PhysicalPrinterID {
			sends.Add(1)
		}
		return syntheticSubmitted(p)
	}
	options.AfterPersist = nil
	scheduler, err := printqueue.NewProofScheduler(context.Background(), f.queue, sender, options)
	if err != nil {
		t.Fatal(err)
	}
	var closed atomic.Bool
	host := proofHost(t, f, scheduler, []string{p1.PhysicalPrinterID, p2.PhysicalPrinterID}, &memoryOwner{}, &closed)
	if err := host.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopHost(t, host)
	if err := host.WithAdmission(context.Background(), f.pins, ReaderVersion, func(ctx context.Context) error { _, err := f.queue.Accept(ctx, jobAuthority(j2), j2); return err }); err != nil {
		t.Fatal("uncertain P1 disabled P2 persisted admission", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if o, err := scheduler.Wait(ctx, j2.JobID); err != nil || o.Primary != printqueue.Submitted {
		t.Fatal("P2 failed during P1 reconciliation hold", o, err)
	}
	if o, err := f.queue.Outcome(context.Background(), j1.JobID); err != nil || o.Primary != printqueue.Uncertain || o.Phase != "hold" {
		t.Fatal("STARTED was reset or replayed", o, err)
	}
	if sends.Load() != 0 {
		t.Fatal("recovery emitted primary or beep")
	}
	health, err := host.Health(context.Background())
	if err != nil || !health.Ready || len(health.PrinterHolds) != 1 || health.PrinterHolds[0].PhysicalPrinterID != p1.PhysicalPrinterID {
		t.Fatal("recovery hold not scoped to P1", health, err)
	}
	if err := CheckUpgrade(f.pins, health, ReaderVersion); !errors.Is(err, ErrHeld) {
		t.Fatal("uncertain compatibility state allowed upgrade", err)
	}
}

func TestCanceledActualQueueProbeDoesNotStopHealthyHost(t *testing.T) {
	f := openQueueFixture(t, t.TempDir(), true)
	printer := registerPrinter(t, f, 21)
	sender := &nonphysicalSender{call: func(context.Context, printtransport.Destination, []byte) printtransport.Result {
		t.Error("empty queue performed I/O")
		return printtransport.Result{State: printtransport.NotSent, Stage: "synthetic"}
	}}
	scheduler, err := printqueue.NewProofScheduler(context.Background(), f.queue, sender, printqueue.ProofOptions{WorkerID: id(900), GuardFactory: func(string) (printtransport.PrinterGuard, error) { return &observedGuard{}, nil }})
	if err != nil {
		t.Fatal(err)
	}
	var closed atomic.Bool
	owner := &memoryOwner{}
	host := proofHost(t, f, scheduler, []string{printer.PhysicalPrinterID}, owner, &closed)
	if err := host.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopHost(t, host)
	// The real single-connection SQLite pool is held by a transaction. Both
	// probe requests reach a genuine query wait and time out independently.
	blocker, err := f.storage.DB.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback()
	for _, admission := range []bool{false, true} {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
		var result error
		if admission {
			result = host.WithAdmission(ctx, f.pins, ReaderVersion, func(context.Context) error { t.Error("canceled probe admitted callback"); return nil })
		} else {
			_, result = host.Health(ctx)
		}
		cancel()
		if !errors.Is(result, context.DeadlineExceeded) {
			t.Fatal("request deadline was hidden", result)
		}
		if owner.closed.Load() || closed.Load() {
			t.Fatal("request timeout closed the healthy host")
		}
	}
	if err := blocker.Rollback(); err != nil {
		t.Fatal(err)
	}
	health, err := host.Health(context.Background())
	if err != nil || !health.Ready || health.State != Running {
		t.Fatal("caller timeout latched or stopped host", health, err)
	}
	if err := host.WithAdmission(context.Background(), f.pins, ReaderVersion, func(context.Context) error { return nil }); err != nil {
		t.Fatal("normal admission failed after unrelated canceled request", err)
	}
}
