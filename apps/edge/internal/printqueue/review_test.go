package printqueue

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"

	"vynic.local/edge/internal/printtransport"
)

func TestPrimaryCapabilitiesMustBeImplementedBeforeAdmission(t *testing.T) {
	for name, value := range map[string]any{"protocol": 2, "paperWidthMm": 39, "rasterWidthDots": 65, "language": "windowsDriverRendered", "cutter": "unknown", "encoding": "text"} {
		t.Run(name, func(t *testing.T) {
			j := job(t, 10, 21, 1, false)
			var profile map[string]any
			if err := json.Unmarshal(j.CapabilityProfile, &profile); err != nil {
				t.Fatal(err)
			}
			profile[name] = value
			j.CapabilityProfile, _ = json.Marshal(profile)
			raw, _ := json.Marshal(j)
			if _, err := DecodeFrozenJob(raw); !errors.Is(err, ErrInvalid) {
				t.Fatalf("unsupported primary %s admitted: %v", name, err)
			}
		})
	}
	j := job(t, 10, 21, 1, false)
	var profile map[string]any
	_ = json.Unmarshal(j.CapabilityProfile, &profile)
	profile["hiddenLanguageProbe"] = true
	j.CapabilityProfile, _ = json.Marshal(profile)
	raw, _ := json.Marshal(j)
	if _, err := DecodeFrozenJob(raw); !errors.Is(err, ErrInvalid) {
		t.Fatal("unknown primary field")
	}
}

func TestContradictoryNativeResultsAreUncertain(t *testing.T) {
	for name, result := range map[string]printtransport.Result{
		"created native job":     {State: printtransport.NotSent, JobID: 17},
		"write attempted":        {State: printtransport.NotSent, WriteAttempted: true},
		"partial bytes":          {State: printtransport.NotSent, BytesWritten: 1},
		"unknown state":          {State: "future-success"},
		"accepted without write": {State: printtransport.Submitted},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			if err := f.store.Register(background, registry(21)); err != nil {
				t.Fatal(err)
			}
			j := job(t, 10, 21, 1, false)
			admitJob(t, f, j)
			s := scheduler(t, f, &fakeSender{call: func(context.Context, printtransport.Destination, []byte) printtransport.Result { return result }}, proofOptions())
			if err := s.RunNext(uuid(21)); err != nil {
				t.Fatal(err)
			}
			o, err := f.store.Outcome(background, j.JobID)
			if err != nil || o.Primary != Uncertain || o.Phase != "hold" {
				t.Fatalf("contradictory result released printer: %+v %v", o, err)
			}
			if err = s.RunNext(uuid(21)); !errors.Is(err, ErrBusy) {
				t.Fatal("uncertainty barrier")
			}
		})
	}
}

func TestLiveOldGuardKeepsHeadQueuedAndOtherPrinterContinues(t *testing.T) {
	f := newFixture(t)
	for _, p := range []int{21, 22} {
		if err := f.store.Register(background, registry(p)); err != nil {
			t.Fatal(err)
		}
	}
	j := job(t, 10, 21, 1, true)
	admitJob(t, f, j)
	admitJob(t, f, job(t, 11, 22, 2, false))
	held := true
	options := proofOptions()
	options.GuardFactory = func(id string) (printtransport.PrinterGuard, error) {
		if id == uuid(21) && held {
			return nil, errors.New("old helper still owns its native lifetime")
		}
		return &fakeGuard{}, nil
	}
	calls := 0
	s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		calls++
		return accepted(p)
	}}, options)
	if err := s.RunNext(uuid(21)); !errors.Is(err, ErrBusy) {
		t.Fatal(err)
	}
	o, err := f.store.Outcome(background, j.JobID)
	if err != nil || o.Primary != Queued || calls != 0 || count(t, f.db, "pq_attempt") != 0 {
		t.Fatalf("guard contention spent primary: %+v %v calls=%d", o, err, calls)
	}
	if err = s.RunNext(uuid(22)); err != nil || calls != 1 {
		t.Fatal("other printer stalled", err)
	}
	// The fixture's positive old-native release is explicit, not lease expiry.
	held = false
	if err = s.RunNext(uuid(21)); err != nil || calls != 3 {
		t.Fatal("fenced head did not progress exactly once", err, calls)
	}
	o, err = f.store.Outcome(background, j.JobID)
	if err != nil || o.Primary != Submitted || o.Beep != BeepSubmitted {
		t.Fatal(o, err)
	}
}

func TestCompletedNotSentClaimRecoversWithoutReprinting(t *testing.T) {
	f := newFixture(t)
	if err := f.store.Register(background, registry(21)); err != nil {
		t.Fatal(err)
	}
	j := job(t, 10, 21, 1, false)
	admitJob(t, f, j)
	admitJob(t, f, job(t, 11, 21, 2, false))
	options := proofOptions()
	options.AfterPersist = func(b Boundary, _ FrozenJob) error {
		if b == PrimaryFlushed {
			return errors.New("crash after confirmed refusal")
		}
		return nil
	}
	s := scheduler(t, f, &fakeSender{call: func(context.Context, printtransport.Destination, []byte) printtransport.Result {
		return printtransport.Result{State: printtransport.NotSent}
	}}, options)
	if err := s.RunNext(uuid(21)); err == nil {
		t.Fatal("fault seam")
	}
	if count(t, f.db, "pq_claim") != 1 {
		t.Fatal("fixture lacks retained claim")
	}
	if err := s.Stop(background); err != nil {
		t.Fatal(err)
	}
	fresh, err := NewProofStore(background, f.db, identity())
	if err != nil {
		t.Fatal(err)
	}
	f.store = fresh
	calls := 0
	recovered := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		calls++
		return accepted(p)
	}}, proofOptions())
	if count(t, f.db, "pq_claim") != 0 {
		t.Fatal("completed claim wedged printer")
	}
	if err = recovered.RunNext(uuid(21)); err != nil || calls != 1 {
		t.Fatal("later job blocked", err, calls)
	}
	o, err := fresh.Outcome(background, j.JobID)
	if err != nil || o.Primary != NotSent {
		t.Fatal("refused primary replayed", o, err)
	}
}

func TestQueueCapacityAndConfigChangeRetainExactReceipts(t *testing.T) {
	f := newFixture(t)
	r := registry(21)
	if err := f.store.Register(background, r); err != nil {
		t.Fatal(err)
	}
	j := job(t, 10, 21, 1, false)
	first := admitJob(t, f, j)
	s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		return accepted(p)
	}}, proofOptions())
	if err := s.RunNext(uuid(21)); err != nil {
		t.Fatal(err)
	}
	r.RegistryRevision++
	r.ConfigRevision++
	if err := f.store.Register(background, r); err != nil {
		t.Fatal(err)
	}
	if retry, err := f.store.Accept(background, authority(j), j); err != nil || retry != first {
		t.Fatal("config change rewrote accepted retry", retry, err)
	}
	stale := job(t, 11, 21, 1, false)
	if _, err := f.store.Accept(background, authority(stale), stale); !errors.Is(err, ErrBinding) {
		t.Fatal("new stale-config admission", err)
	}
	for n := 20; n < 20+MaxPendingPerPrinter; n++ {
		queued := modify(t, job(t, n, 21, 1, false), func(j *FrozenJob) { j.ConfigRevision = r.ConfigRevision; j.RegistryRevision = r.RegistryRevision })
		admitJob(t, f, queued)
	}
	full := modify(t, job(t, 999, 21, 1, false), func(j *FrozenJob) { j.ConfigRevision = r.ConfigRevision; j.RegistryRevision = r.RegistryRevision })
	if _, err := f.store.Accept(background, authority(full), full); !errors.Is(err, ErrCapacity) {
		t.Fatal("pending capacity bypass", err)
	}
	var sequence int
	if err := f.db.QueryRow("SELECT next_sequence FROM pq_registry").Scan(&sequence); err != nil || sequence != MaxPendingPerPrinter+2 {
		t.Fatal("rejected admission consumed sequence", sequence, err)
	}
	if retry, err := f.store.Accept(background, authority(j), j); err != nil || retry != first {
		t.Fatal("capacity froze read-only receipt", retry, err)
	}
}

func TestMultipleDatabaseConnectionsCannotPassDurabilityProbe(t *testing.T) {
	f := newFixture(t)
	f.db.SetMaxOpenConns(2)
	if _, err := NewProofStore(background, f.db, identity()); !errors.Is(err, ErrSchema) {
		t.Fatal("pooled connection-local FULL/FK mismatch admitted", err)
	}
	f.db.SetMaxOpenConns(1)
}

func TestFaultObserverCannotMutateFrozenSendBytes(t *testing.T) {
	f := newFixture(t)
	if err := f.store.Register(background, registry(21)); err != nil {
		t.Fatal(err)
	}
	j := job(t, 10, 21, 1, false)
	admitJob(t, f, j)
	options := proofOptions()
	options.AfterPersist = func(_ Boundary, observed FrozenJob) error {
		observed.PrimaryBytes[0] = 'x'
		observed.CapabilityProfile[0] = '['
		return nil
	}
	calls := 0
	s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		calls++
		if !bytes.Equal(p, j.PrimaryBytes) {
			t.Fatal("fault observer changed immutable transmission")
		}
		return accepted(p)
	}}, options)
	if err := s.RunNext(uuid(21)); err != nil || calls != 1 {
		t.Fatal(err, calls)
	}
}
