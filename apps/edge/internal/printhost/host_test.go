package printhost

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
)

func id(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }

func gatewayPins() Pins {
	return Pins{Role: PrintGateway, Scope: Local, OwnershipPolicy: LocalHost, VenueID: id(1), InstallationID: id(2), DeviceID: id(3), HostID: id(4), GatewayHostID: id(4), AuthorityEpoch: 1, ProtocolVersion: ProtocolVersion, HelperProtocolVersion: printtransport.HelperProtocolVersion, DatabaseSchemaVersion: store.SchemaVersion, MinimumReaderVersion: ReaderVersion, RouteRevision: 1, ConfigRevision: 1, RegistryRevision: 1, BindingRevision: 1, CapabilityRevision: 1, CapabilityProfileSHA256: strings.Repeat("1", 64), HostBinarySHA256: strings.Repeat("2", 64), HelperBinarySHA256: strings.Repeat("3", 64)}
}

type memoryOwner struct{ closed atomic.Bool }

func (o *memoryOwner) Close() error { o.closed.Store(true); return nil }

type fence struct{ closed atomic.Bool }

func (f *fence) FenceAdmission() { f.closed.Store(true) }

type drainFunc func(context.Context) error

func (f drainFunc) Stop(ctx context.Context) error { return f(ctx) }

type syntheticHost struct {
	owner    *memoryOwner
	fence    *fence
	probeMu  sync.Mutex
	evidence Evidence
	closed   atomic.Bool
	started  atomic.Bool
	worker   DrainWorker
	closeErr error
}

func newSynthetic(p Pins) *syntheticHost {
	return &syntheticHost{owner: &memoryOwner{}, fence: &fence{}, evidence: Evidence{Pins: p, RecoveryComplete: true}, worker: drainFunc(func(context.Context) error { return nil })}
}

func (f *syntheticHost) snapshot(context.Context) (Evidence, error) {
	f.probeMu.Lock()
	defer f.probeMu.Unlock()
	evidence := f.evidence
	evidence.PrinterHolds = append([]PrinterHold(nil), evidence.PrinterHolds...)
	return evidence, nil
}

func (f *syntheticHost) host(t *testing.T, pins Pins) *Host {
	t.Helper()
	h, err := NewHost(Config{Pins: pins, POSHostIDs: []string{id(5)}, Acquire: func(string) (Owner, error) { return f.owner, nil }}, func(context.Context, Pins) (Components, error) {
		return Components{Queue: f.fence, Worker: f.worker, Probe: ProbeFunc(f.snapshot), Start: func() error { f.started.Store(true); return nil }, Close: func() error { f.closed.Store(true); return f.closeErr }, HasPrinterWriter: pins.Role == PrintGateway}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func stopHost(t *testing.T, host *Host) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := host.Stop(ctx); err != nil {
		t.Fatal(err)
	}
}

func TestPinsAndTopologyRefuseBeforeOpeningResources(t *testing.T) {
	for _, test := range []struct {
		name   string
		change func(*Pins)
	}{
		{"foreign role", func(p *Pins) { p.Role = "automaticFailover" }},
		{"malformed venue", func(p *Pins) { p.VenueID = "../venue" }},
		{"old helper", func(p *Pins) { p.HelperProtocolVersion = 0 }},
		{"old reader", func(p *Pins) { p.MinimumReaderVersion = 1 }},
		{"old database", func(p *Pins) { p.DatabaseSchemaVersion-- }},
		{"zero revision", func(p *Pins) { p.BindingRevision = 0 }},
		{"future revision", func(p *Pins) { p.RegistryRevision = 1 << 63 }},
		{"unknown profile", func(p *Pins) { p.CapabilityProfileSHA256 = "" }},
		{"unbound artifact", func(p *Pins) { p.HelperBinarySHA256 = strings.Repeat("A", 64) }},
	} {
		t.Run(test.name, func(t *testing.T) {
			pins := gatewayPins()
			test.change(&pins)
			opened := false
			_, err := NewHost(Config{Pins: pins, POSHostIDs: []string{id(5)}}, func(context.Context, Pins) (Components, error) { opened = true; return Components{}, nil })
			if err == nil || opened {
				t.Fatal("invalid configuration opened a host")
			}
		})
	}
	_, err := NewHost(Config{Pins: func() Pins {
		p := gatewayPins()
		p.Scope, p.OwnershipPolicy, p.ClusterID, p.MembershipSHA256 = VenueShared, QualifiedGateway, id(6), strings.Repeat("7", 64)
		return p
	}(), POSHostIDs: []string{id(4)}, AvailabilityProfile: IndependentGateway}, func(context.Context, Pins) (Components, error) { return Components{}, nil })
	if !errors.Is(err, ErrRole) {
		t.Fatal("gateway was accepted on a configured POS host", err)
	}
}

func TestSharedPhysicalSenderRemainsHeld(t *testing.T) {
	pins := gatewayPins()
	pins.Role, pins.HostID = POSAgent, id(5)
	pins.Scope, pins.OwnershipPolicy = VenueShared, ClusterLogicalOnly
	pins.ClusterID, pins.MembershipSHA256, pins.GatewayHostID = id(6), strings.Repeat("7", 64), ""
	f := newSynthetic(pins)
	h, err := NewHost(Config{Pins: pins, POSHostIDs: []string{id(5)}, Acquire: func(string) (Owner, error) { return f.owner, nil }}, func(context.Context, Pins) (Components, error) {
		return Components{Queue: f.fence, Worker: f.worker, Probe: ProbeFunc(f.snapshot), Start: func() error { f.started.Store(true); return nil }, Close: func() error { f.closed.Store(true); return nil }, HasPrinterWriter: true, PhysicalSender: true}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := h.Start(context.Background()); !errors.Is(err, printqueue.ErrActivationPending) {
		t.Fatal("shared physical sender activated without a downstream fence", err)
	}
	stopHost(t, h)
	if f.started.Load() || !f.closed.Load() || !f.owner.closed.Load() {
		t.Fatal("shared physical refusal did not drain/close without scheduling")
	}
}

func TestHealthChecksEveryFrozenPinAndOldReader(t *testing.T) {
	pins := gatewayPins()
	health := Health{Version: ProtocolVersion, Pins: pins, State: Running, Ready: true}
	changes := []func(*Pins){
		func(p *Pins) { p.VenueID = id(101) }, func(p *Pins) { p.InstallationID = id(102) }, func(p *Pins) { p.DeviceID = id(103) },
		func(p *Pins) { p.HostID = id(104); p.GatewayHostID = id(104) }, func(p *Pins) { p.AuthorityEpoch++ },
		func(p *Pins) { p.RouteRevision++ }, func(p *Pins) { p.ConfigRevision++ }, func(p *Pins) { p.RegistryRevision++ },
		func(p *Pins) { p.BindingRevision++ }, func(p *Pins) { p.CapabilityRevision++ },
		func(p *Pins) { p.CapabilityProfileSHA256 = strings.Repeat("4", 64) },
		func(p *Pins) { p.HostBinarySHA256 = strings.Repeat("5", 64) }, func(p *Pins) { p.HelperBinarySHA256 = strings.Repeat("6", 64) },
		func(p *Pins) { p.ProtocolVersion++ }, func(p *Pins) { p.HelperProtocolVersion++ }, func(p *Pins) { p.DatabaseSchemaVersion-- },
	}
	for i, change := range changes {
		observed := health
		change(&observed.Pins)
		if err := CheckHealth(pins, observed, ReaderVersion); err == nil {
			t.Fatalf("changed pin %d accepted", i)
		}
	}
	if err := CheckHealth(pins, health, 1); !errors.Is(err, ErrVersionMismatch) {
		t.Fatal("old-reader rollback admitted", err)
	}
	health.BlockedReason = "P1 original send retained"
	health.PrinterHolds = []PrinterHold{{PhysicalPrinterID: id(21), Reason: "original send retained"}}
	if err := CheckHealth(pins, health, ReaderVersion); err != nil {
		t.Fatal("a printer hold disabled legitimate queue admission", err)
	}
	if err := CheckUpgrade(pins, health, ReaderVersion); !errors.Is(err, ErrHeld) {
		t.Fatal("upgrade ignored retained original send", err)
	}
}

func TestTrustedPinChangeLatchesWithoutClientMismatchDenial(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	h := f.host(t, pins)
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopHost(t, h)
	foreign := pins
	foreign.VenueID = id(100)
	called := false
	if err := h.WithAdmission(context.Background(), foreign, ReaderVersion, func(context.Context) error { called = true; return nil }); !errors.Is(err, ErrBindingMismatch) || called {
		t.Fatal("foreign admission succeeded", err)
	}
	if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { return nil }); err != nil {
		t.Fatal("untrusted client mismatch latched the host", err)
	}
	f.probeMu.Lock()
	f.evidence.Pins.BindingRevision++
	f.probeMu.Unlock()
	if _, err := h.Health(context.Background()); !errors.Is(err, ErrBindingMismatch) {
		t.Fatal("changed trusted evidence admitted", err)
	}
	f.probeMu.Lock()
	f.evidence.Pins = pins
	f.probeMu.Unlock()
	if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { called = true; return nil }); !errors.Is(err, ErrBindingMismatch) || called {
		t.Fatal("trusted pin change automatically cleared", err)
	}
}

func TestStopWaitsCommitAndRetainsOwnershipAfterDeadline(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	h := f.host(t, pins)
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	entered, release, result := make(chan struct{}), make(chan struct{}), make(chan error, 1)
	go func() {
		result <- h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { close(entered); <-release; return nil })
	}()
	<-entered
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err := h.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("Stop did not wait admitted commit", err)
	}
	if f.closed.Load() || f.owner.closed.Load() || !f.fence.closed.Load() {
		t.Fatal("deadline released durable ownership or left admission open")
	}
	if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { t.Error("new callback entered"); return nil }); !errors.Is(err, ErrUnavailable) {
		t.Fatal("new admission survived stop", err)
	}
	close(release)
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	stopHost(t, h)
	if !f.closed.Load() || !f.owner.closed.Load() {
		t.Fatal("settled host resources remained open")
	}
}

func TestCloseFailureRetainsOwnerAndVisibleDiagnostic(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	f.closeErr = errors.New("synthetic durable close failed")
	h := f.host(t, pins)
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := h.Stop(context.Background()); !errors.Is(err, f.closeErr) {
		t.Fatal("close failure hidden", err)
	}
	if f.owner.closed.Load() {
		t.Fatal("failed durable close freed the host owner")
	}
	health, err := h.Health(context.Background())
	if !errors.Is(err, f.closeErr) || health.State != Held || !strings.Contains(health.BlockedReason, "durable close") {
		t.Fatal("held close has no visible diagnostic", health, err)
	}
}

func TestHostGuardExcludesSecondRoleUntilActualDrain(t *testing.T) {
	pins := gatewayPins()
	pins.HostID, pins.GatewayHostID = uuid.NewString(), ""
	pins.GatewayHostID = pins.HostID
	f := newSynthetic(pins)
	release := make(chan struct{})
	f.worker = drainFunc(func(context.Context) error { <-release; return nil })
	open := func(context.Context, Pins) (Components, error) {
		return Components{Queue: f.fence, Worker: f.worker, Probe: ProbeFunc(f.snapshot), Start: func() error { return nil }, Close: func() error { return nil }, HasPrinterWriter: true}, nil
	}
	config := Config{Pins: pins, POSHostIDs: []string{id(5)}}
	h, err := NewHost(config, open)
	if err != nil {
		t.Fatal(err)
	}
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err := h.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	opened := atomic.Bool{}
	other, err := NewHost(config, func(context.Context, Pins) (Components, error) { opened.Store(true); return Components{}, nil })
	if err != nil {
		t.Fatal(err)
	}
	if err := other.Start(context.Background()); !errors.Is(err, ErrUnavailable) || opened.Load() {
		t.Fatal("second writer opened while original drain retained", err)
	}
	stopHost(t, other)
	close(release)
	stopHost(t, h)
	owner, err := printtransport.AcquirePrinterGuard("service-host:" + pins.HostID)
	if err != nil {
		t.Fatal("settled service owner was not released", err)
	}
	if err := owner.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestConcurrentAdmissionsAndHealthAreDrained(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	h := f.host(t, pins)
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	const clients = 10
	entered := make(chan struct{}, clients)
	release := make(chan struct{})
	results := make(chan error, clients)
	for i := 0; i < clients; i++ {
		go func() {
			results <- h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { entered <- struct{}{}; <-release; return nil })
		}()
	}
	for i := 0; i < clients; i++ {
		<-entered
	}
	health, err := h.Health(context.Background())
	if err != nil || health.ActiveAdmissions != clients {
		t.Fatal("concurrent admissions lost", health, err)
	}
	if err := CheckUpgrade(pins, health, ReaderVersion); !errors.Is(err, ErrHeld) {
		t.Fatal("upgrade entered during commit", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err := h.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	close(release)
	for i := 0; i < clients; i++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	stopHost(t, h)
}

func TestStopDuringOpenPreventsWorkerStartAndWaitsResourceOwner(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	opened, releaseOpen := make(chan struct{}), make(chan struct{})
	h, err := NewHost(Config{Pins: pins, Acquire: func(string) (Owner, error) { return f.owner, nil }}, func(context.Context, Pins) (Components, error) {
		close(opened)
		<-releaseOpen
		return Components{Queue: f.fence, Worker: f.worker, Probe: ProbeFunc(f.snapshot), Start: func() error { f.started.Store(true); return nil }, Close: func() error { f.closed.Store(true); return nil }, HasPrinterWriter: true}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	started := make(chan error, 1)
	go func() { started <- h.Start(context.Background()) }()
	awaitSignal(t, opened)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err := h.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("stop abandoned original resource open", err)
	}
	if f.owner.closed.Load() || f.closed.Load() {
		t.Fatal("startup deadline released resource owner")
	}
	close(releaseOpen)
	if err := <-started; !errors.Is(err, ErrUnavailable) {
		t.Fatal("worker started after stop closed admission", err)
	}
	stopHost(t, h)
	if f.started.Load() || !f.closed.Load() || !f.owner.closed.Load() {
		t.Fatal("startup did not drain resources without scheduling")
	}
}

func TestSharedClusterPinsAreExplicitAndImmutable(t *testing.T) {
	pins := gatewayPins()
	pins.Scope, pins.OwnershipPolicy, pins.GatewayHostID = VenueShared, ClusterLogicalOnly, ""
	pins.ClusterID, pins.MembershipSHA256 = id(600), strings.Repeat("a", 64)
	f := newSynthetic(pins)
	h := f.host(t, pins)
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopHost(t, h)
	for _, change := range []func(*Pins){func(p *Pins) { p.ClusterID = id(601) }, func(p *Pins) { p.MembershipSHA256 = strings.Repeat("b", 64) }} {
		expected := pins
		change(&expected)
		if err := h.WithAdmission(context.Background(), expected, ReaderVersion, func(context.Context) error { t.Error("changed membership admitted"); return nil }); !errors.Is(err, ErrBindingMismatch) {
			t.Fatal("dynamic membership/discovery admitted", err)
		}
	}
	if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { return nil }); err != nil {
		t.Fatal("foreign membership request modified captured pins", err)
	}
}

func TestHealthHoldCopiesDoNotMutateTrustedEvidence(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	f.evidence.PrinterHolds = []PrinterHold{{PhysicalPrinterID: id(21), Reason: "uncertain head"}}
	f.evidence.BlockedReason = "printer hold retained"
	h := f.host(t, pins)
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer stopHost(t, h)
	first, err := h.Health(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	first.PrinterHolds[0].PhysicalPrinterID = id(22)
	first.Pins.BindingRevision++
	next, err := h.Health(context.Background())
	if err != nil || next.Pins != pins || next.PrinterHolds[0].PhysicalPrinterID != id(21) {
		t.Fatal("returned health alias mutated host evidence", next, err)
	}
}
