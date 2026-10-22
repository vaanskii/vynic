package printhost

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sync"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
)

type AdmissionFence interface{ FenceAdmission() }
type DrainWorker interface{ Stop(context.Context) error }
type HealthProbe interface {
	Snapshot(context.Context) (Evidence, error)
}
type ProbeFunc func(context.Context) (Evidence, error)

func (f ProbeFunc) Snapshot(ctx context.Context) (Evidence, error) { return f(ctx) }

type Owner interface{ Close() error }
type AcquireOwner func(string) (Owner, error)

func missing(value any) bool {
	if value == nil {
		return true
	}
	switch reflect.ValueOf(value).Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return reflect.ValueOf(value).IsNil()
	}
	return false
}

// Components are exclusively owned by a host after Open succeeds. Open performs
// queue recovery but must not start scheduling or physical I/O. Start schedules
// work without blocking on a send. Worker.Stop must wait actual primary+beep
// lifetimes; Close releases durable resources only after that drain succeeds.
type Components struct {
	Queue            AdmissionFence
	Worker           DrainWorker
	Probe            HealthProbe
	Start            func() error
	Close            func() error
	HasPrinterWriter bool
	PhysicalSender   bool
}

type OpenFunc func(context.Context, Pins) (Components, error)

type Config struct {
	AvailabilityProfile AvailabilityProfile
	Pins                Pins
	POSHostIDs          []string
	Acquire             AcquireOwner
}

type AvailabilityProfile string

const IndependentGateway AvailabilityProfile = "independentGateway"

// Host owns no renderer, device credential, network listener or service manager.
// A future authenticated composition must own those boundaries independently.
type Host struct {
	mu          sync.Mutex
	pins        Pins
	acquire     AcquireOwner
	open        OpenFunc
	state       State
	owner       Owner
	components  Components
	held        error
	active      uint64
	probes      uint64
	idle        chan struct{}
	startupDone chan struct{}
	stopStarted chan struct{}
	stopDone    chan struct{}
	stopOnce    sync.Once
	stopErr     error
}

func NewHost(config Config, open OpenFunc) (*Host, error) {
	if err := config.Pins.Validate(); err != nil {
		return nil, err
	}
	if open == nil || len(config.POSHostIDs) > 64 {
		return nil, ErrUnavailable
	}
	if config.AvailabilityProfile != "" && config.AvailabilityProfile != IndependentGateway {
		return nil, ErrRole
	}
	seen := make(map[string]bool)
	for _, id := range config.POSHostIDs {
		if !printqueue.CanonicalUUID(id) || seen[id] {
			return nil, ErrRole
		}
		seen[id] = true
	}
	if config.AvailabilityProfile == IndependentGateway {
		if len(config.POSHostIDs) == 0 || config.Pins.Role != PrintGateway || config.Pins.OwnershipPolicy != QualifiedGateway || config.Pins.HostID != config.Pins.GatewayHostID || seen[config.Pins.HostID] {
			return nil, fmt.Errorf("%w: independent gateway profile requires an outside-POS host", ErrRole)
		}
	}
	acquire := config.Acquire
	if acquire == nil {
		acquire = func(hostID string) (Owner, error) {
			// Role-independent key: a second role/configuration cannot open a
			// second service writer for this same stable host identity.
			return printtransport.AcquirePrinterGuard("service-host:" + hostID)
		}
	}
	idle := make(chan struct{})
	close(idle)
	return &Host{pins: config.Pins, acquire: acquire, open: open, state: New, idle: idle, startupDone: make(chan struct{}), stopStarted: make(chan struct{}), stopDone: make(chan struct{})}, nil
}

func (h *Host) Start(ctx context.Context) (result error) {
	h.mu.Lock()
	if h.state != New {
		h.mu.Unlock()
		return ErrAlreadyRunning
	}
	h.state = Starting
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		if result != nil {
			h.held = errors.Join(h.held, result)
			if h.state != Draining {
				h.state = Held
			}
		}
		close(h.startupDone)
		h.mu.Unlock()
		if result != nil {
			h.beginStop()
		}
	}()
	owner, err := h.acquire(h.pins.HostID)
	if err != nil {
		return fmt.Errorf("%w: host owner: %v", ErrUnavailable, err)
	}
	if missing(owner) {
		return fmt.Errorf("%w: host owner missing", ErrUnavailable)
	}
	h.mu.Lock()
	h.owner = owner
	h.mu.Unlock()
	components, err := h.open(ctx, h.pins)
	if err != nil {
		return fmt.Errorf("%w: open: %v", ErrUnavailable, err)
	}
	h.mu.Lock()
	h.components = components
	h.mu.Unlock()
	if missing(components.Queue) || missing(components.Worker) || missing(components.Probe) || components.Start == nil || components.Close == nil {
		return fmt.Errorf("%w: incomplete lifecycle composition", ErrUnavailable)
	}
	if h.pins.Role == PrintGateway && !components.HasPrinterWriter || components.PhysicalSender && !components.HasPrinterWriter {
		return ErrRole
	}
	if h.pins.Scope == VenueShared && components.PhysicalSender {
		// Cluster quorum/epoch is not a downstream RAW fence. This candidate
		// has no verified fence implementation and cannot activate one.
		return printqueue.ErrActivationPending
	}
	evidence, err := components.Probe.Snapshot(ctx)
	if err != nil {
		return fmt.Errorf("%w: health probe: %v", ErrUnavailable, err)
	}
	if err := h.checkEvidence(evidence); err != nil {
		return err
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.state == Draining {
		return ErrUnavailable
	}
	// Start is a nonblocking scheduler entrance, serialized with Stop's gate.
	if err := components.Start(); err != nil {
		return fmt.Errorf("%w: worker start: %v", ErrUnavailable, err)
	}
	h.state = Running
	return nil
}

func (h *Host) checkEvidence(e Evidence) error {
	if err := ComparePins(h.pins, e.Pins, ReaderVersion); err != nil {
		return err
	}
	if !e.RecoveryComplete {
		return fmt.Errorf("%w: exclusive queue recovery incomplete", ErrHeld)
	}
	return nil
}

func (h *Host) enter(probe bool) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.held != nil {
		return h.held
	}
	if h.state != Running {
		return ErrUnavailable
	}
	if h.active+h.probes == 0 {
		h.idle = make(chan struct{})
	}
	if probe {
		h.probes++
	} else {
		h.active++
	}
	return nil
}

func (h *Host) leave(probe bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if probe {
		h.probes--
	} else {
		h.active--
	}
	if h.active+h.probes == 0 {
		close(h.idle)
	}
}

func (h *Host) probe(ctx context.Context) (Evidence, error) {
	evidence, err := h.components.Probe.Snapshot(ctx)
	if err != nil {
		if ctx.Err() != nil && errors.Is(err, ctx.Err()) {
			// A client stopped waiting; it did not change storage, pins or
			// original worker ownership. Another request may still proceed.
			return evidence, ctx.Err()
		}
		err = fmt.Errorf("%w: health probe: %w", ErrUnavailable, err)
		h.mu.Lock()
		h.held = errors.Join(h.held, err)
		h.mu.Unlock()
		h.beginStop()
		return evidence, err
	}
	if err := h.checkEvidence(evidence); err != nil {
		// Trusted local evidence changed underneath this fixed composition.
		// A later apparently good response cannot automatically clear it.
		h.mu.Lock()
		h.held = errors.Join(h.held, err)
		h.mu.Unlock()
		h.beginStop()
		return evidence, err
	}
	return evidence, nil
}

// WithAdmission wraps the transaction entrance, including its commit/flush.
// It does not wrap a public Wait deadline around an original transport call.
func (h *Host) WithAdmission(ctx context.Context, expected Pins, reader uint32, action func(context.Context) error) error {
	if err := ComparePins(h.pins, expected, reader); err != nil {
		return err
	}
	if action == nil {
		return ErrUnavailable
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := h.enter(false); err != nil {
		return err
	}
	defer h.leave(false)
	if _, err := h.probe(ctx); err != nil {
		return err
	}
	return action(ctx)
}

func (h *Host) Health(ctx context.Context) (Health, error) {
	h.mu.Lock()
	status := Health{Version: ProtocolVersion, Pins: h.pins, State: h.state, ActiveAdmissions: h.active}
	held := h.held
	h.mu.Unlock()
	if held != nil {
		status.BlockedReason = held.Error()
		return status, held
	}
	if err := h.enter(true); err != nil {
		return status, err
	}
	defer h.leave(true)
	evidence, err := h.probe(ctx)
	status.BlockedReason = evidence.BlockedReason
	status.PrinterHolds = append([]PrinterHold(nil), evidence.PrinterHolds...)
	if err != nil && status.BlockedReason == "" {
		status.BlockedReason = err.Error()
	}
	h.mu.Lock()
	status.State, status.ActiveAdmissions = h.state, h.active
	h.mu.Unlock()
	status.Ready = err == nil && status.State == Running
	return status, err
}

func (h *Host) beginStop() {
	h.stopOnce.Do(func() {
		h.mu.Lock()
		if h.state == New {
			close(h.startupDone)
		}
		h.state = Draining
		close(h.stopStarted)
		h.mu.Unlock()
		go h.drain()
	})
}

func (h *Host) drain() {
	<-h.startupDone
	h.mu.Lock()
	components, owner := h.components, h.owner
	idle := h.idle
	h.mu.Unlock()
	if !missing(components.Queue) {
		components.Queue.FenceAdmission()
	}
	var result error
	if !missing(components.Worker) {
		// A Stop caller timeout cannot cancel or abandon this original drain.
		result = components.Worker.Stop(context.Background())
	}
	<-idle
	if result == nil && components.Close != nil {
		result = components.Close()
	}
	if result == nil && owner != nil {
		result = owner.Close()
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	h.stopErr = result
	if result != nil {
		h.state = Held
		h.held = errors.Join(h.held, result)
	} else {
		h.state = Stopped
	}
	close(h.stopDone)
}

// Stop immediately disables new host transactions. Deadline only bounds this
// wait: all ownership stays retained until actual worker/resource close settles.
// A failed close stays held; no automatic restart, takeover or replay follows.
func (h *Host) Stop(ctx context.Context) error {
	h.beginStop()
	select {
	case <-h.stopDone:
		h.mu.Lock()
		defer h.mu.Unlock()
		return h.stopErr
	case <-ctx.Done():
		return ctx.Err()
	}
}
