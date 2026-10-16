package printqueue

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	_ "modernc.org/sqlite"
	"vynic.local/edge/internal/printtransport"
)

var background = context.Background()

func uuid(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }
func identity() GatewayIdentity {
	return GatewayIdentity{VenueID: uuid(1), InstallationID: uuid(2), DeviceID: uuid(3), WorkerHostID: uuid(4), Epoch: 1}
}

func openDB(t *testing.T, path string, version int) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	for _, pragma := range []string{"PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL", "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000"} {
		if _, err = db.Exec(pragma); err != nil {
			t.Fatal(err)
		}
	}
	var current int
	if err = db.QueryRow("PRAGMA user_version").Scan(&current); err != nil {
		t.Fatal(err)
	}
	if current == 0 {
		files, err := filepath.Glob("../store/migrations/*.sql")
		if err != nil {
			t.Fatal(err)
		}
		tx, err := db.Begin()
		if err != nil {
			t.Fatal(err)
		}
		for _, file := range files[:version] {
			raw, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = tx.Exec(string(raw)); err != nil {
				t.Fatalf("migration %s: %v", file, err)
			}
		}
		if _, err = tx.Exec(fmt.Sprintf("PRAGMA user_version=%d", version)); err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		if err := db.Close(); err != nil {
			t.Error(err)
		}
	})
	return db
}

type fixture struct {
	db    *sql.DB
	store *Store
	path  string
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	path := filepath.Join(t.TempDir(), "gateway.sqlite")
	db := openDB(t, path, 6)
	s, err := NewProofStore(background, db, identity())
	if err != nil {
		t.Fatal(err)
	}
	return fixture{db, s, path}
}

func registry(printer int) Registry {
	i := identity()
	return Registry{PhysicalPrinterID: uuid(printer), VenueID: i.VenueID, InstallationID: i.InstallationID, AuthorityEpoch: i.Epoch, DeviceID: i.DeviceID, WorkerHostID: i.WorkerHostID, BindingRevision: 1, ConfigRevision: 1, RegistryRevision: 1, Aliases: []string{uuid(printer + 1000), uuid(printer + 2000)}, Destination: printtransport.Destination{PhysicalPrinterID: uuid(printer), WorkerHostID: i.WorkerHostID, Transport: printtransport.TCP, Host: "127.0.0.1", Port: uint16(9000 + printer)}}
}

func job(t *testing.T, n, printer, client int, beep bool) FrozenJob {
	t.Helper()
	r := registry(printer)
	d := r.Destination
	d.DocumentName = "synthetic " + uuid(n)
	primary := []byte(fmt.Sprintf("synthetic %d\n", n))
	primary = append(primary, 0x1d, 0x56, 0x01)
	hash := sha256.Sum256(primary)
	profile := json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"partial","encoding":"georgianViaRaster","beep":{"capability":"epsonEscA97Pattern","enabled":false}}`)
	if beep {
		profile = bytes.ReplaceAll(profile, []byte("false"), []byte("true"))
	}
	j := FrozenJob{Version: 1, JobID: uuid(n), EffectID: uuid(n + 10000), RequestID: uuid(n + 20000), TerminalID: uuid(client + 100), VenueID: r.VenueID, InstallationID: r.InstallationID, OriginInstallationID: uuid(client + 200), AuthorityEpoch: 1, DeviceID: r.DeviceID, PhysicalPrinterID: r.PhysicalPrinterID, AliasID: r.Aliases[0], RouteRevision: 1, ConfigRevision: 1, BindingRevision: 1, RegistryRevision: 1, AttemptID: uuid(n + 30000), BeepAttemptID: uuid(n + 40000), Destination: d, CapabilityProfile: profile, PrimaryBytes: primary, PrimarySHA256: hex.EncodeToString(hash[:])}
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}

func authority(j FrozenJob) Authority {
	return Authority{VenueID: j.VenueID, InstallationID: j.InstallationID, OriginInstallationID: j.OriginInstallationID, TerminalID: j.TerminalID, Epoch: j.AuthorityEpoch}
}
func modify(t *testing.T, j FrozenJob, change func(*FrozenJob)) FrozenJob {
	t.Helper()
	change(&j)
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	j, err = DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	return j
}
func count(t *testing.T, db *sql.DB, table string) int {
	t.Helper()
	var n int
	if err := db.QueryRow("SELECT count(*) FROM " + table).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}
func admitJob(t *testing.T, f fixture, j FrozenJob) Receipt {
	t.Helper()
	r, err := f.store.Accept(background, authority(j), j)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

type fakeSender struct {
	call     func(context.Context, printtransport.Destination, []byte) printtransport.Result
	physical bool
}

func (s *fakeSender) Physical() bool { return s.physical }
func (s *fakeSender) Send(c context.Context, d printtransport.Destination, p []byte) printtransport.Result {
	return s.call(c, d, p)
}
func accepted(p []byte) printtransport.Result {
	return printtransport.Result{State: printtransport.Submitted, Stage: "synthetic", BytesWritten: uint32(len(p)), WriteAttempted: true}
}

type fakeGuard struct{ close func() error }

func (g *fakeGuard) Context(ctx context.Context) context.Context { return ctx }
func (g *fakeGuard) Close() error {
	if g.close != nil {
		return g.close()
	}
	return nil
}
func proofOptions() ProofOptions {
	return ProofOptions{WorkerID: uuid(900), GuardFactory: func(string) (printtransport.PrinterGuard, error) { return &fakeGuard{}, nil }}
}
func scheduler(t *testing.T, f fixture, sender *fakeSender, options ProofOptions) *Scheduler {
	t.Helper()
	s, err := NewProofScheduler(background, f.store, sender, options)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(background, 2*time.Second)
		defer cancel()
		if err := s.Stop(ctx); err != nil {
			t.Error(err)
		}
	})
	return s
}

func TestDartEnvelopeInteroperability(t *testing.T) {
	for _, transport := range []string{"tcp", "windowsSpooler"} {
		t.Run(transport, func(t *testing.T) {
			raw, err := os.ReadFile("testdata/dart_" + transport + ".json")
			if err != nil {
				t.Fatal(err)
			}
			j, err := DecodeFrozenJob(raw)
			if err != nil {
				t.Fatal(err)
			}
			if j.JobID != uuid(8) || j.VenueID != uuid(2) || j.InstallationID != uuid(1) || j.OriginInstallationID != uuid(3) || j.AuthorityEpoch != 41 || j.RouteRevision != 11 || j.ConfigRevision != 12 || j.BindingRevision != 13 || j.RegistryRevision != 14 || string(j.Destination.Transport) != transport {
				t.Fatalf("unexpected Dart fields: %+v", j)
			}
			if !bytes.Equal(j.PrimaryBytes[:2], []byte{0x1b, 0x40}) || !bytes.Equal(j.PrimaryBytes[len(j.PrimaryBytes)-3:], []byte{0x1d, 0x56, 0x01}) || !bytes.Contains(j.PrimaryBytes, []byte("JOB synthetic-frozen-ticket")) {
				t.Fatalf("header/cut changed: %x", j.PrimaryBytes)
			}
			if !bytes.Equal(j.Raw(), raw) {
				t.Fatal("relay representation changed")
			}
			command, _ := optionalBeep(j.CapabilityProfile)
			if !bytes.Equal(command, []byte{0x1b, 0x28, 0x41, 3, 0, 0x61, 1, 1}) {
				t.Fatal("explicit Epson command")
			}
		})
	}
}

func TestDecoderRejectsAmbiguousOrMutatedIdentity(t *testing.T) {
	j := job(t, 10, 21, 1, false)
	for name, change := range map[string]func(map[string]any){
		"missing":    func(m map[string]any) { delete(m, "registryRevision") },
		"case alias": func(m map[string]any) { m["JobId"] = m["jobId"]; delete(m, "jobId") },
		"destination case alias": func(m map[string]any) {
			d := m["destination"].(map[string]any)
			d["Port"] = d["port"]
			delete(d, "port")
		},
		"zero revision":   func(m map[string]any) { m["bindingRevision"] = 0 },
		"fraction":        func(m map[string]any) { m["authorityEpoch"] = 1.5 },
		"uppercase uuid":  func(m map[string]any) { m["jobId"] = "00000000-0000-4000-8000-00000000000A" },
		"hash mismatch":   func(m map[string]any) { m["primarySha256"] = string(bytes.Repeat([]byte("0"), 64)) },
		"unknown":         func(m map[string]any) { m["hiddenReplay"] = true },
		"null zero field": func(m map[string]any) { m["destination"].(map[string]any)["queueName"] = nil },
		"DNS":             func(m map[string]any) { m["destination"].(map[string]any)["host"] = "printer.local" },
	} {
		t.Run(name, func(t *testing.T) {
			var m map[string]any
			if err := json.Unmarshal(j.Raw(), &m); err != nil {
				t.Fatal(err)
			}
			change(m)
			raw, _ := json.Marshal(m)
			if _, err := DecodeFrozenJob(raw); !errors.Is(err, ErrInvalid) {
				t.Fatalf("accepted: %v", err)
			}
		})
	}
	duplicate := bytes.Replace(j.Raw(), []byte(`"version":1`), []byte(`"version":1,"version":1`), 1)
	if _, err := DecodeFrozenJob(duplicate); !errors.Is(err, ErrInvalid) {
		t.Fatal(err)
	}
	j.PrimaryBytes[0] = 'x'
	if _, err := j.fresh(); !errors.Is(err, ErrInvalid) {
		t.Fatal("mutable caller changed payload")
	}
}

func TestAliasEndpointAndFrozenRetry(t *testing.T) {
	f := newFixture(t)
	r := registry(21)
	if err := f.store.Register(background, r); err != nil {
		t.Fatal(err)
	}
	duplicate := registry(22)
	duplicate.Destination.Host = "::ffff:127.0.0.1"
	duplicate.Destination.Port = r.Destination.Port
	if err := f.store.Register(background, duplicate); !errors.Is(err, ErrBinding) {
		t.Fatalf("equivalent IP admitted: %v", err)
	}
	alias := registry(22)
	alias.Aliases[0] = r.Aliases[0]
	if err := f.store.Register(background, alias); !errors.Is(err, ErrBinding) {
		t.Fatalf("retarget alias: %v", err)
	}
	j := job(t, 10, 21, 1, false)
	receipt := admitJob(t, f, j)
	retry, err := f.store.Accept(background, authority(j), j)
	if err != nil || retry != receipt || count(t, f.db, "pq_job") != 1 {
		t.Fatalf("lost ACK retry: %+v %v", retry, err)
	}
	changed := modify(t, j, func(j *FrozenJob) { j.Destination.DocumentName = "changed label" })
	if _, err = f.store.Accept(background, authority(changed), changed); !errors.Is(err, ErrReuse) {
		t.Fatalf("changed hash: %v", err)
	}
	stale := modify(t, job(t, 11, 21, 1, false), func(j *FrozenJob) { j.BindingRevision = 2 })
	if _, err = f.store.Accept(background, authority(stale), stale); !errors.Is(err, ErrBinding) {
		t.Fatalf("stale binding: %v", err)
	}
	wrong := authority(j)
	wrong.VenueID = uuid(99)
	if _, err = f.store.Accept(background, wrong, j); !errors.Is(err, ErrScope) {
		t.Fatalf("wrong Venue: %v", err)
	}
	r.RegistryRevision++
	r.ConfigRevision++
	if err = f.store.Register(background, r); !errors.Is(err, ErrBusy) {
		t.Fatalf("queued config mutation: %v", err)
	}
	if _, err = f.db.Exec("UPDATE pq_alias SET physical_id=? WHERE alias_id=?", uuid(22), r.Aliases[0]); err == nil {
		t.Fatal("SQL alias mutation")
	}
	if _, err = f.db.Exec("DELETE FROM pq_receipt"); err == nil {
		t.Fatal("receipt deletion")
	}
}

func TestWindowsQueueCanonicalOwnership(t *testing.T) {
	f := newFixture(t)
	r := registry(21)
	r.Destination = printtransport.Destination{PhysicalPrinterID: r.PhysicalPrinterID, WorkerHostID: r.WorkerHostID, Transport: printtransport.WindowsSpooler, QueueName: "Kitchen Queue", ExpectedDriverName: "Synthetic", ExpectedPortName: "USB001"}
	if err := f.store.Register(background, r); err != nil {
		t.Fatal(err)
	}
	other := registry(22)
	other.Destination = r.Destination
	other.Destination.PhysicalPrinterID = other.PhysicalPrinterID
	other.Destination.QueueName = "kitchen queue"
	other.Destination.ExpectedPortName = "USB999"
	if err := f.store.Register(background, other); !errors.Is(err, ErrBinding) {
		t.Fatalf("same queue alternate case/port: %v", err)
	}
}

func TestFIFOAndIndependentPrinterDuringLostACK(t *testing.T) {
	f := newFixture(t)
	for _, p := range []int{21, 22} {
		if err := f.store.Register(background, registry(p)); err != nil {
			t.Fatal(err)
		}
	}
	jobs := []FrozenJob{job(t, 10, 21, 1, false), job(t, 11, 21, 2, false), job(t, 12, 21, 3, false), job(t, 13, 22, 2, false)}
	for _, j := range jobs {
		admitJob(t, f, j)
	}
	entered := make(chan struct{})
	release := make(chan struct{})
	defer close(release)
	var mu sync.Mutex
	var calls []string
	sender := &fakeSender{call: func(_ context.Context, d printtransport.Destination, p []byte) printtransport.Result {
		mu.Lock()
		calls = append(calls, d.DocumentName)
		mu.Unlock()
		if d.PhysicalPrinterID == uuid(21) {
			close(entered)
			<-release
			return printtransport.Result{State: printtransport.Uncertain, Stage: "lost ACK", BytesWritten: uint32(len(p)), WriteAttempted: true}
		}
		return accepted(p)
	}}
	s := scheduler(t, f, sender, proofOptions())
	done := make(chan error, 1)
	go func() { done <- s.RunNext(uuid(21)) }()
	<-entered
	if err := s.RunNext(uuid(21)); !errors.Is(err, ErrBusy) {
		t.Fatalf("second worker: %v", err)
	}
	if err := s.RunNext(uuid(22)); err != nil {
		t.Fatal(err)
	}
	if o, err := f.store.Outcome(background, jobs[3].JobID); err != nil || o.Primary != Submitted {
		t.Fatalf("other printer: %+v %v", o, err)
	}
	ctx, cancel := context.WithTimeout(background, 20*time.Millisecond)
	defer cancel()
	o, err := s.Wait(ctx, jobs[0].JobID)
	if !errors.Is(err, context.DeadlineExceeded) || o.Primary != Started {
		t.Fatalf("public timeout: %+v %v", o, err)
	}
	if reason, err := f.store.BlockedReason(background); err != nil || reason == "" {
		t.Fatal("updater released before native completion")
	}
	// Native future is intentionally unresolved; a caller retry is receipt-only.
	retry, err := f.store.Accept(background, authority(jobs[0]), jobs[0])
	if err != nil || retry.Sequence != 1 {
		t.Fatal(err)
	}
	mu.Lock()
	total := len(calls)
	mu.Unlock()
	if total != 2 {
		t.Fatal("timeout caused replay")
	}
	// Release using a distinct signal so deferred close remains exactly once.
	go func() { release <- struct{}{} }()
	if err = <-done; err != nil {
		t.Fatal(err)
	}
	if err = s.RunNext(uuid(21)); !errors.Is(err, ErrBusy) {
		t.Fatalf("UNCERTAIN barrier: %v", err)
	}
	for _, j := range jobs[1:3] {
		o, err = f.store.Outcome(background, j.JobID)
		if err != nil || o.Primary != Queued {
			t.Fatalf("head overtaken: %+v %v", o, err)
		}
	}
}

func TestThreeClientFIFOAndOptionalBeepSeparate(t *testing.T) {
	f := newFixture(t)
	if err := f.store.Register(background, registry(21)); err != nil {
		t.Fatal(err)
	}
	for n := 10; n < 13; n++ {
		admitJob(t, f, job(t, n, 21, n-9, n == 10))
	}
	var order []string
	options := proofOptions()
	guardCloses := 0
	options.GuardFactory = func(string) (printtransport.PrinterGuard, error) {
		return &fakeGuard{close: func() error { guardCloses++; return nil }}, nil
	}
	s := scheduler(t, f, &fakeSender{call: func(_ context.Context, d printtransport.Destination, p []byte) printtransport.Result {
		if bytes.Equal(p, []byte{0x1b, 0x28, 0x41, 3, 0, 0x61, 1, 1}) {
			o, err := f.store.Outcome(background, uuid(10))
			if err != nil || o.Primary != Submitted || o.Beep != BeepReserved || o.Phase != "beep" {
				t.Fatalf("signal before durable primary/reservation: %+v %v", o, err)
			}
			if guardCloses != 0 {
				t.Fatal("guard released between primary/beep")
			}
			return printtransport.Result{State: printtransport.Uncertain, Stage: "beep lost ACK", WriteAttempted: true}
		}
		order = append(order, d.DocumentName)
		return accepted(p)
	}}, options)
	for n := 10; n < 13; n++ {
		if err := s.RunNext(uuid(21)); err != nil {
			t.Fatal(err)
		}
	}
	for i, label := range order {
		if label != "synthetic "+uuid(10+i) {
			t.Fatalf("FIFO: %v", order)
		}
	}
	o, err := f.store.Outcome(background, uuid(10))
	if err != nil || o.Primary != Submitted || o.Beep != BeepUncertain || o.Phase != "complete" {
		t.Fatalf("beep lost primary result: %+v %v", o, err)
	}
	if len(order) != 3 || guardCloses != 3 {
		t.Fatalf("calls=%v closes=%d", order, guardCloses)
	}
}

func TestStopTimeoutRetainsLifetimeAndRestartIsConservative(t *testing.T) {
	f := newFixture(t)
	if err := f.store.Register(background, registry(21)); err != nil {
		t.Fatal(err)
	}
	j := job(t, 10, 21, 1, true)
	admitJob(t, f, j)
	entered := make(chan struct{})
	release := make(chan struct{})
	closed := make(chan struct{}, 1)
	options := proofOptions()
	options.GuardFactory = func(string) (printtransport.PrinterGuard, error) {
		return &fakeGuard{close: func() error { closed <- struct{}{}; return nil }}, nil
	}
	s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		if bytes.Equal(p, j.PrimaryBytes) {
			close(entered)
			<-release
		}
		return accepted(p)
	}}, options)
	if err := s.Start([]string{uuid(21)}); err != nil {
		t.Fatal(err)
	}
	<-entered
	ctx, cancel := context.WithTimeout(background, 20*time.Millisecond)
	defer cancel()
	if err := s.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	select {
	case <-closed:
		t.Fatal("guard closed at public deadline")
	default:
	}
	newStore, err := NewProofStore(background, f.db, identity())
	if err != nil {
		t.Fatal(err)
	}
	if _, err = NewProofScheduler(background, newStore, &fakeSender{call: func(context.Context, printtransport.Destination, []byte) printtransport.Result {
		t.Fatal("replacement submitted")
		return printtransport.Result{}
	}}, proofOptions()); !errors.Is(err, ErrBusy) {
		t.Fatalf("competing process owner: %v", err)
	}
	if _, err = f.store.Accept(background, authority(j), j); !errors.Is(err, ErrBusy) {
		t.Fatal("stop did not fence admission")
	}
	close(release)
	if err = s.Stop(background); err != nil {
		t.Fatal(err)
	}
	select {
	case <-closed:
	default:
		t.Fatal("late completion did not close guard")
	}
	o, err := f.store.Outcome(background, j.JobID)
	if err != nil || o.Primary != Submitted || o.Beep != BeepSubmitted {
		t.Fatalf("late result: %+v %v", o, err)
	}
}

func TestEveryFlushedDispatchBoundaryRestart(t *testing.T) {
	for _, boundary := range []Boundary{StartedFlushed, PrimaryFlushed, BeepReservedFlushed, BeepFlushed, CompletedFlushed} {
		t.Run(string(boundary), func(t *testing.T) {
			f := newFixture(t)
			if err := f.store.Register(background, registry(21)); err != nil {
				t.Fatal(err)
			}
			j := job(t, 10, 21, 1, true)
			admitJob(t, f, j)
			calls := 0
			sender := &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
				calls++
				return accepted(p)
			}}
			options := proofOptions()
			options.AfterPersist = func(b Boundary, _ FrozenJob) error {
				if b == boundary {
					return errors.New("synthetic crash boundary")
				}
				return nil
			}
			s := scheduler(t, f, sender, options)
			if err := s.RunNext(uuid(21)); err == nil {
				t.Fatal("fault seam not reached")
			}
			if err := s.Stop(background); err != nil {
				t.Fatal(err)
			}
			fresh, err := NewProofStore(background, f.db, identity())
			if err != nil {
				t.Fatal(err)
			}
			f.store = fresh
			recovered := scheduler(t, f, sender, proofOptions())
			o, err := f.store.Outcome(background, j.JobID)
			if err != nil {
				t.Fatal(err)
			}
			if boundary == StartedFlushed {
				if o.Primary != Uncertain || o.Phase != "hold" || calls != 0 {
					t.Fatalf("STARTED replayed: %+v calls=%d", o, calls)
				}
				if err = recovered.RunNext(uuid(21)); !errors.Is(err, ErrBusy) {
					t.Fatal(err)
				}
			} else {
				if o.Primary != Submitted || o.Phase != "complete" {
					t.Fatalf("accepted primary changed: %+v", o)
				}
				if boundary == PrimaryFlushed && o.Beep != BeepSkipped || boundary == BeepReservedFlushed && o.Beep != BeepUncertain {
					t.Fatalf("optional replay policy: %+v", o)
				}
				before := calls
				if err = recovered.RunNext(uuid(21)); !errors.Is(err, ErrNoWork) || calls != before {
					t.Fatal("replayed completed job")
				}
			}
			if retry, err := f.store.Accept(background, authority(j), j); err != nil || retry.Sequence != 1 || count(t, f.db, "pq_job") != 1 {
				t.Fatalf("restart retry: %+v %v", retry, err)
			}
		})
	}
}

func TestOldSchemaAndRealSenderFailClosed(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.sqlite")
	db := openDB(t, path, 4)
	if _, err := NewProofStore(background, db, identity()); !errors.Is(err, ErrSchema) {
		t.Fatal(err)
	}
	var version int
	if err := db.QueryRow("PRAGMA user_version").Scan(&version); err != nil || version != 4 {
		t.Fatal("old database upgraded by queue constructor")
	}
	f := newFixture(t)
	if _, err := NewProofScheduler(background, f.store, &fakeSender{physical: true}, proofOptions()); !errors.Is(err, ErrActivationPending) {
		t.Fatal("physical proof attachment")
	}
}
