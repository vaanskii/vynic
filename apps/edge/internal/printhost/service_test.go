package printhost

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func awaitStatus(t *testing.T, statuses <-chan ServiceStatus, state ServiceState) {
	t.Helper()
	timeout := time.NewTimer(2 * time.Second)
	defer timeout.Stop()
	for {
		select {
		case status := <-statuses:
			if status.State == state {
				return
			}
		case <-timeout.C:
			t.Fatal("service did not report expected state", state)
		}
	}
}

func TestControlServiceKeepsStopPendingUntilActualDrain(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	release := make(chan struct{})
	f.worker = drainFunc(func(context.Context) error { <-release; return nil })
	h := f.host(t, pins)
	commands := make(chan ServiceCommand)
	statuses := make(chan ServiceStatus, 64)
	result := make(chan error, 1)
	go func() {
		result <- ControlService(h, commands, func(s ServiceStatus) { statuses <- s }, func(err error) { t.Errorf("unexpected diagnostic: %v", err) }, 5*time.Millisecond)
	}()
	awaitStatus(t, statuses, ServiceRunning)
	commands <- ServiceStop
	awaitStatus(t, statuses, ServiceStopPending)
	commands <- ServiceInterrogate
	awaitStatus(t, statuses, ServiceStopPending)
	if f.closed.Load() || f.owner.closed.Load() {
		t.Fatal("SCM stop released uncompleted drain")
	}
	select {
	case err := <-result:
		t.Fatal("service exited while original lifetime retained", err)
	default:
	}
	if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { t.Error("post-stop admission entered"); return nil }); !errors.Is(err, ErrUnavailable) {
		t.Fatal(err)
	}
	close(release)
	select {
	case err := <-result:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("settled service did not exit")
	}
	awaitStatus(t, statuses, ServiceStopped)
	if !f.closed.Load() || !f.owner.closed.Load() {
		t.Fatal("settled service resources remained open")
	}
}

func serviceHostWithProbe(t *testing.T, f *syntheticHost, pins Pins, probe ProbeFunc) *Host {
	t.Helper()
	h, err := NewHost(Config{Pins: pins, Acquire: func(string) (Owner, error) { return f.owner, nil }}, func(context.Context, Pins) (Components, error) {
		return Components{Queue: f.fence, Worker: f.worker, Probe: probe, Start: func() error { f.started.Store(true); return nil }, Close: func() error { f.closed.Store(true); return f.closeErr }, HasPrinterWriter: true}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func TestControlServiceObservesTrustedRuntimeFailureWithoutSCMCommand(t *testing.T) {
	storageFailure := errors.New("synthetic durable storage failed")
	for _, test := range []struct {
		name    string
		pinFail bool
		wantErr error
	}{
		{name: "pin mismatch", pinFail: true, wantErr: ErrBindingMismatch},
		{name: "storage failure", wantErr: storageFailure},
	} {
		t.Run(test.name, func(t *testing.T) {
			pins := gatewayPins()
			f := newSynthetic(pins)
			var fail atomic.Bool
			releaseDrain := make(chan struct{})
			var releaseOnce sync.Once
			release := func() { releaseOnce.Do(func() { close(releaseDrain) }) }
			f.worker = drainFunc(func(context.Context) error { <-releaseDrain; return nil })
			h := serviceHostWithProbe(t, f, pins, func(ctx context.Context) (Evidence, error) {
				evidence, err := f.snapshot(ctx)
				if fail.Load() {
					if test.pinFail {
						evidence.Pins.BindingRevision++
					} else {
						return Evidence{}, storageFailure
					}
				}
				return evidence, err
			})
			defer func() { release(); stopHost(t, h) }()
			commands := make(chan ServiceCommand)
			statuses := make(chan ServiceStatus, 256)
			diagnostics := make(chan error, 8)
			result := make(chan error, 1)
			go func() {
				result <- ControlService(h, commands, func(s ServiceStatus) { statuses <- s }, func(err error) { diagnostics <- err }, 5*time.Millisecond)
			}()
			awaitStatus(t, statuses, ServiceRunning)
			fail.Store(true)
			if _, err := h.Health(context.Background()); !errors.Is(err, test.wantErr) {
				t.Fatal("trusted runtime failure was hidden", err)
			}
			// No SCM command has been sent. The host's own lifecycle event
			// must move the service into pending while the original drain waits.
			awaitStatus(t, statuses, ServiceStopPending)
			if f.closed.Load() || f.owner.closed.Load() {
				t.Fatal("runtime failure released an uncompleted original drain")
			}
			if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { t.Error("held service admitted callback"); return nil }); !errors.Is(err, test.wantErr) {
				t.Fatal("held service lost its original failure", err)
			}
			select {
			case err := <-result:
				t.Fatal("service exited before actual runtime drain", err)
			default:
			}
			release()
			select {
			case err := <-result:
				if !errors.Is(err, test.wantErr) {
					t.Fatal("service exit lost original runtime failure", err)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("runtime-stopped host remained service Running")
			}
			awaitStatus(t, statuses, ServiceStopped)
			select {
			case err := <-diagnostics:
				if !errors.Is(err, test.wantErr) {
					t.Fatal("runtime failure diagnostic lost original reason", err)
				}
			default:
				t.Fatal("runtime service failure had no diagnostic")
			}
			if !f.closed.Load() || !f.owner.closed.Load() {
				t.Fatal("settled runtime service resources remained open")
			}
		})
	}
}

func TestControlServiceCallerCancellationKeepsRunning(t *testing.T) {
	pins := gatewayPins()
	f := newSynthetic(pins)
	var block atomic.Bool
	probeEntered := make(chan struct{}, 1)
	h := serviceHostWithProbe(t, f, pins, func(ctx context.Context) (Evidence, error) {
		if block.Load() {
			probeEntered <- struct{}{}
			<-ctx.Done()
			return Evidence{}, ctx.Err()
		}
		return f.snapshot(ctx)
	})
	defer stopHost(t, h)
	commands := make(chan ServiceCommand)
	statuses := make(chan ServiceStatus, 256)
	result := make(chan error, 1)
	go func() {
		result <- ControlService(h, commands, func(s ServiceStatus) { statuses <- s }, func(err error) { t.Errorf("caller cancellation stopped service: %v", err) }, 5*time.Millisecond)
	}()
	awaitStatus(t, statuses, ServiceRunning)
	for _, test := range []struct {
		name      string
		admission bool
		wantErr   error
	}{
		{name: "canceled health", wantErr: context.Canceled},
		{name: "deadline admission", admission: true, wantErr: context.DeadlineExceeded},
	} {
		t.Run(test.name, func(t *testing.T) {
			block.Store(true)
			var ctx context.Context
			var cancel context.CancelFunc
			if test.admission {
				ctx, cancel = context.WithTimeout(context.Background(), 50*time.Millisecond)
			} else {
				ctx, cancel = context.WithCancel(context.Background())
			}
			defer cancel()
			request := make(chan error, 1)
			go func() {
				if test.admission {
					request <- h.WithAdmission(ctx, pins, ReaderVersion, func(context.Context) error { t.Error("canceled probe admitted callback"); return nil })
				} else {
					_, err := h.Health(ctx)
					request <- err
				}
			}()
			select {
			case <-probeEntered:
			case <-time.After(2 * time.Second):
				t.Fatal("request did not enter blocked probe")
			}
			if !test.admission {
				cancel()
			}
			if err := <-request; !errors.Is(err, test.wantErr) {
				t.Fatal("caller failure was hidden", err)
			}
			block.Store(false)
			health, err := h.Health(context.Background())
			if err != nil || health.State != Running || !health.Ready || f.closed.Load() || f.owner.closed.Load() {
				t.Fatal("caller cancellation changed healthy host lifecycle", health, err)
			}
			if err := h.WithAdmission(context.Background(), pins, ReaderVersion, func(context.Context) error { return nil }); err != nil {
				t.Fatal("normal admission failed after caller cancellation", err)
			}
			commands <- ServiceInterrogate
			awaitStatus(t, statuses, ServiceRunning)
			select {
			case err := <-result:
				t.Fatal("service exited for caller cancellation", err)
			default:
			}
		})
	}
	commands <- ServiceStop
	awaitStatus(t, statuses, ServiceStopped)
	if err := <-result; err != nil {
		t.Fatal(err)
	}
}

func TestMissingOwnerRefusesBeforeResourceOpen(t *testing.T) {
	var typedNil *memoryOwner
	for _, owner := range []Owner{nil, typedNil} {
		pins := gatewayPins()
		opened := false
		h, err := NewHost(Config{Pins: pins, Acquire: func(string) (Owner, error) { return owner, nil }}, func(context.Context, Pins) (Components, error) { opened = true; return Components{}, nil })
		if err != nil {
			t.Fatal(err)
		}
		if err := h.Start(context.Background()); !errors.Is(err, ErrUnavailable) || opened {
			t.Fatal("ownerless service opened resources", err)
		}
		stopHost(t, h)
	}
}

func TestLocalAgentMayCoLocateButSharedPinsRequireStableMembership(t *testing.T) {
	pins := gatewayPins()
	pins.Role = POSAgent
	f := newSynthetic(pins)
	h, err := NewHost(Config{Pins: pins, POSHostIDs: []string{pins.HostID}, Acquire: func(string) (Owner, error) { return f.owner, nil }}, func(context.Context, Pins) (Components, error) {
		return Components{Queue: f.fence, Worker: f.worker, Probe: ProbeFunc(f.snapshot), Start: func() error { return nil }, Close: func() error { return nil }, HasPrinterWriter: true}, nil
	})
	if err != nil {
		t.Fatal("LOCAL colocated agent was generically forbidden", err)
	}
	if err := h.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	stopHost(t, h)
	pins.Scope, pins.OwnershipPolicy, pins.GatewayHostID = VenueShared, ClusterLogicalOnly, ""
	if err := pins.Validate(); !errors.Is(err, ErrBindingMismatch) {
		t.Fatal("dynamic/unbound cluster configuration accepted", err)
	}
}
