package printerdaemon

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"

	"vynic.local/edge/internal/printeragent"
	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
)

type Daemon struct {
	mu           sync.Mutex
	config       Config
	host         *printhost.Host
	server       *printeragent.Server
	listener     net.Listener
	rpcErr       error
	setupErr     error
	stopping     bool
	failed       chan error
	closed       chan struct{}
	probeGate    chan struct{}
	closeStorage func(*store.Store) error
}

// Private fault seams cannot supply a sender or enable physical dispatch.
type daemonHooks struct {
	acquire      printhost.AcquireOwner
	closeStorage func(*store.Store) error
}

// New validates every artifact, certificate and dedicated state reference
// before opening a writer. It supplies no sender/activation option. An existing
// separately provisioned software fixture can run; live provisioning is held.
func New(config Config, executable string) (*Daemon, error) {
	return newWithHooks(config, executable, daemonHooks{})
}

func newWithHooks(config Config, executable string, hooks daemonHooks) (*Daemon, error) {
	validated, err := preflight(config, executable)
	if err != nil {
		return nil, err
	}
	d := &Daemon{config: validated.config, failed: make(chan error, 1), closed: make(chan struct{}), probeGate: make(chan struct{}, 1)}
	d.closeStorage = hooks.closeStorage
	if d.closeStorage == nil {
		d.closeStorage = func(storage *store.Store) error { return storage.Close() }
	}
	d.host, err = printhost.NewHost(printhost.Config{Pins: d.config.Pins, Acquire: hooks.acquire}, d.open)
	if err != nil {
		return nil, err
	}
	clients := make([]printeragent.ClientPin, len(d.config.Clients))
	for i, client := range d.config.Clients {
		clients[i] = printeragent.ClientPin{ClientID: client.ClientID, CertificateSHA256: client.CertificateSHA256}
	}
	d.server, err = printeragent.NewServer(printeragent.Config{Pins: d.config.Pins, Certificate: validated.certificate, ClientCA: validated.clientCA, Clients: clients, Health: d})
	if err != nil {
		return nil, fmt.Errorf("%w: authenticated listener preflight: %w", ErrConfig, err)
	}
	return d, nil
}

// heldSender cannot perform physical I/O. Its GuardFactory always refuses a
// claim and the scheduler is never started, so even an accidental future call
// cannot turn a queued envelope into a transport attempt.
type heldSender struct{}

func (heldSender) Physical() bool { return false }
func (heldSender) Send(context.Context, printtransport.Destination, []byte) printtransport.Result {
	return printtransport.Result{State: printtransport.NotSent, Stage: PhysicalHoldReason}
}

type runtimeFence struct {
	daemon *Daemon
	server *printeragent.Server
	queue  *printqueue.Store
}

func (f runtimeFence) FenceAdmission() {
	f.daemon.mu.Lock()
	f.daemon.stopping = true
	f.daemon.mu.Unlock()
	f.server.Fence()
	if f.queue != nil {
		f.queue.FenceAdmission()
	}
}

type runtimeWorker struct {
	server    *printeragent.Server
	scheduler *printqueue.Scheduler
}

func (w runtimeWorker) Stop(ctx context.Context) error {
	// Both original queue lifetimes and RPC handlers must settle before closing
	// storage/host ownership. A public wait deadline never cancels this drain.
	if w.scheduler != nil {
		if queueErr := w.scheduler.Stop(ctx); queueErr != nil {
			return queueErr
		}
	}
	return w.server.Stop(ctx)
}

func (d *Daemon) open(ctx context.Context, pins printhost.Pins) (printhost.Components, error) {
	if err := verifyState(d.config); err != nil {
		return printhost.Components{}, err
	}
	storage, err := store.Open(d.config.StateDirectory, false)
	if err != nil {
		return printhost.Components{}, err
	}
	fail := func(err error) (printhost.Components, error) {
		// Transfer cleanup responsibility before the probe fails. Host then
		// retains ownership if durable resource closure cannot be confirmed.
		d.mu.Lock()
		d.setupErr = err
		d.mu.Unlock()
		return printhost.Components{
			Queue: runtimeFence{daemon: d, server: d.server}, Worker: runtimeWorker{server: d.server},
			Probe: printhost.ProbeFunc(func(context.Context) (printhost.Evidence, error) { return printhost.Evidence{Pins: pins}, err }),
			Start: func() error { return err }, Close: func() error { return d.closeResources(storage) }, HasPrinterWriter: true,
		}, nil
	}
	if err = verifyMarker(d.config); err != nil {
		return fail(err)
	}
	var installation, venue string
	if err = storage.DB.QueryRowContext(ctx, "SELECT id,venue_id FROM installation WHERE singleton=1").Scan(&installation, &venue); err != nil || installation != pins.InstallationID || venue != pins.VenueID {
		return fail(errors.Join(ErrConfig, err))
	}
	queue, err := printqueue.NewProofStore(ctx, storage.DB, printqueue.GatewayIdentity{VenueID: pins.VenueID, InstallationID: pins.InstallationID, DeviceID: pins.DeviceID, WorkerHostID: pins.HostID, Epoch: pins.AuthorityEpoch})
	if err != nil {
		return fail(err)
	}
	scheduler, err := printqueue.NewProofScheduler(ctx, queue, heldSender{}, printqueue.ProofOptions{WorkerID: pins.HostID, GuardFactory: func(string) (printtransport.PrinterGuard, error) { return nil, printqueue.ErrActivationPending }})
	if err != nil {
		return fail(err)
	}
	probe := printhost.ProbeFunc(func(ctx context.Context) (printhost.Evidence, error) {
		select {
		case d.probeGate <- struct{}{}:
			defer func() { <-d.probeGate }()
		case <-ctx.Done():
			return printhost.Evidence{}, ctx.Err()
		}
		d.mu.Lock()
		rpcErr := d.rpcErr
		d.mu.Unlock()
		evidence := printhost.Evidence{Pins: pins, RecoveryComplete: true}
		if rpcErr != nil {
			return evidence, rpcErr
		}
		for _, artifact := range []Artifact{d.config.Agent, {Path: d.config.Helper.Path, SHA256: d.config.Helper.SHA256}, d.config.CapabilityProfile} {
			if _, err := checkArtifact(artifact, 128<<20); err != nil {
				return evidence, err
			}
		}
		if err := verifyMarker(d.config); err != nil {
			return evidence, err
		}
		var err error
		evidence.BlockedReason, err = queue.BlockedReason(ctx)
		if err != nil {
			return evidence, err
		}
		rows, err := storage.DB.QueryContext(ctx, "SELECT physical_id FROM pq_registry ORDER BY physical_id LIMIT 65")
		if err != nil {
			return evidence, err
		}
		var physicalIDs []string
		for rows.Next() {
			var id string
			if err = rows.Scan(&id); err != nil {
				break
			}
			physicalIDs = append(physicalIDs, id)
		}
		readErr := errors.Join(err, rows.Err(), rows.Close())
		if readErr != nil || len(physicalIDs) > 64 {
			return evidence, errors.Join(readErr, ErrConfig)
		}
		for _, id := range physicalIDs {
			reason, err := queue.PrinterBlockedReason(ctx, id)
			if err != nil {
				return evidence, err
			}
			if reason != "" {
				evidence.PrinterHolds = append(evidence.PrinterHolds, printhost.PrinterHold{PhysicalPrinterID: id, Reason: reason})
			}
		}
		return evidence, nil
	})
	return printhost.Components{
		Queue: runtimeFence{daemon: d, server: d.server, queue: queue}, Worker: runtimeWorker{server: d.server, scheduler: scheduler}, Probe: probe,
		Start: func() error {
			listener, err := net.Listen("tcp", d.config.ListenAddress)
			if err != nil {
				return err
			}
			d.mu.Lock()
			d.listener = listener
			d.mu.Unlock()
			go func() {
				if err := d.server.Serve(context.Background(), listener); err != nil {
					d.mu.Lock()
					if d.stopping {
						d.mu.Unlock()
						return // shutdown won the race before Serve accepted the listener
					}
					d.rpcErr = err
					d.mu.Unlock()
					d.failed <- err
					// The trusted failure follows the normal retained host drain;
					// Windows ControlService observes that same lifecycle event.
					// The original rpcErr is retained above and delivered on failed;
					// Health is called only to latch it and trigger that drain. Its
					// duplicate error cannot replace or hide the original failure.
					_, _ = d.host.Health(context.Background())
				}
			}()
			// Intentionally no scheduler.Start: physical claims stay held.
			return nil
		},
		Close: func() error { return d.closeResources(storage) }, HasPrinterWriter: true, PhysicalSender: false,
	}, nil
}

func (d *Daemon) Host() *printhost.Host { return d.host }

func (d *Daemon) Pins() printhost.Pins { return d.config.Pins }

func (d *Daemon) closeResources(storage *store.Store) error {
	d.mu.Lock()
	listener := d.listener
	d.mu.Unlock()
	if listener != nil {
		if err := listener.Close(); err != nil && !errors.Is(err, net.ErrClosed) {
			return err
		}
	}
	if err := d.closeStorage(storage); err != nil {
		return err
	}
	close(d.closed)
	return nil
}

func (d *Daemon) Start(ctx context.Context) error {
	err := d.host.Start(ctx)
	d.mu.Lock()
	setupErr := d.setupErr
	d.mu.Unlock()
	return errors.Join(err, setupErr)
}

func (d *Daemon) Address() string {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.listener == nil {
		return ""
	}
	return d.listener.Addr().String()
}

func (d *Daemon) Health(ctx context.Context) (printhost.Health, error) {
	return d.host.Health(ctx)
}

func (d *Daemon) Wait(ctx context.Context) error {
	select {
	case err := <-d.failed:
		return err
	case <-d.closed:
		health, err := d.host.Health(context.Background())
		if health.BlockedReason == "" {
			return nil
		}
		return err
	case <-ctx.Done():
		return nil
	}
}

func (d *Daemon) Stop(ctx context.Context) error {
	d.mu.Lock()
	d.stopping = true
	d.mu.Unlock()
	d.server.Fence()
	return d.host.Stop(ctx)
}
