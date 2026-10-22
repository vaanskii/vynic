package printqueue

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/gofrs/flock"
	"vynic.local/edge/internal/printtransport"
)

type Boundary string

const (
	StartedFlushed      Boundary = "startedFlushed"
	PrimaryFlushed      Boundary = "primaryFlushed"
	BeepReservedFlushed Boundary = "beepReservedFlushed"
	BeepFlushed         Boundary = "beepFlushed"
	CompletedFlushed    Boundary = "completedFlushed"
)

type ProofOptions struct {
	WorkerID     string
	GuardFactory printtransport.GuardFactory
	// AfterPersist is an injected nonphysical crash/fault seam. An error stops
	// this dispatch; it never rolls back a flushed boundary or retries I/O.
	AfterPersist func(Boundary, FrozenJob) error
}

type Scheduler struct {
	store       *Store
	sender      printtransport.Sender
	options     ProofOptions
	processLock *flock.Flock
	mu          sync.Mutex
	stopping    bool
	started     bool
	active      sync.WaitGroup
	stop        chan struct{}
	drained     chan struct{}
	stopOnce    sync.Once
	closeOnce   sync.Once
	closeErr    error
	errors      chan error
}

// NewProofScheduler cannot attach a real transport. Its process lock proves
// only same-file synthetic worker exclusion; copied roots/alternate hosts,
// relay authentication and hardware writer fencing remain production gates.
func NewProofScheduler(ctx context.Context, store *Store, sender printtransport.Sender, options ProofOptions) (*Scheduler, error) {
	if sender == nil || sender.Physical() {
		return nil, ErrActivationPending
	}
	if !CanonicalUUID(options.WorkerID) || options.GuardFactory == nil {
		return nil, ErrInvalid
	}
	var sequence int
	var name, path string
	if err := store.db.QueryRowContext(ctx, "PRAGMA database_list").Scan(&sequence, &name, &path); err != nil {
		return nil, err
	}
	if path == "" || name != "main" {
		return nil, ErrSchema
	}
	lock := flock.New(path + ".pq-proof-worker.lock")
	acquired, err := lock.TryLock()
	if err != nil || !acquired {
		if err == nil {
			err = ErrBusy
		}
		return nil, errors.Join(err, lock.Close())
	}
	if err = store.recover(ctx); err != nil {
		return nil, errors.Join(err, lock.Close())
	}
	return &Scheduler{store: store, sender: sender, options: options, processLock: lock, stop: make(chan struct{}), drained: make(chan struct{}), errors: make(chan error, 32)}, nil
}

func (s *Scheduler) persisted(boundary Boundary, j FrozenJob) error {
	if s.options.AfterPersist != nil {
		// A fault observer cannot mutate the bytes/profile about to be sent.
		copy, err := DecodeFrozenJob(j.Raw())
		if err != nil {
			return err
		}
		return s.options.AfterPersist(boundary, copy)
	}
	return nil
}

// RunNext owns one actual primary + optional beep lifetime. It has no public
// timeout context. A transport panic becomes uncertain, never safe-to-replay.
func (s *Scheduler) RunNext(physicalID string) (err error) {
	if !CanonicalUUID(physicalID) {
		return ErrInvalid
	}
	s.mu.Lock()
	if s.stopping {
		s.mu.Unlock()
		return ErrBusy
	}
	// A still-live helper/other worker is a barrier, not a spent primary.
	// Guard acquisition performs no document submission and is nonblocking.
	guard, guardErr := s.options.GuardFactory(physicalID)
	if guardErr != nil {
		s.mu.Unlock()
		return fmt.Errorf("%w: printer guard: %v", ErrBusy, guardErr)
	}
	if guard == nil {
		s.mu.Unlock()
		return errors.New("guard factory returned no ownership")
	}
	s.active.Add(1)
	j, err := s.store.claim(context.Background(), physicalID, s.options.WorkerID)
	s.mu.Unlock()
	defer s.active.Done()
	defer func() { err = errors.Join(err, guard.Close()) }()
	if err != nil {
		return err
	}
	if err = s.persisted(StartedFlushed, j); err != nil {
		return err
	}
	workerContext := guard.Context(context.Background())
	primary := s.send(workerContext, j.Destination, j.PrimaryBytes)
	primary = normalizeResult(primary, len(j.PrimaryBytes))
	if err = s.store.settlePrimary(context.Background(), j, primary); err != nil {
		return err
	}
	if err = s.persisted(PrimaryFlushed, j); err != nil {
		return err
	}
	if primary.State == printtransport.Uncertain {
		return nil
	}
	if primary.State == printtransport.Submitted {
		command, skip := optionalBeep(j.CapabilityProfile)
		if command == nil {
			if err = s.store.settleBeep(context.Background(), j, BeepSkipped, printtransport.Result{State: printtransport.NotSent, Stage: "beep skipped", Detail: skip}); err != nil {
				return err
			}
		} else {
			if err = s.store.reserveBeep(context.Background(), j); err != nil {
				return err
			}
			if err = s.persisted(BeepReservedFlushed, j); err != nil {
				return err
			}
			beep := normalizeResult(s.send(workerContext, j.Destination, command), len(command))
			state := BeepUncertain
			if beep.State == printtransport.Submitted {
				state = BeepSubmitted
			}
			if beep.State == printtransport.NotSent {
				state = BeepNotSent
			}
			if err = s.store.settleBeep(context.Background(), j, state, beep); err != nil {
				return err
			}
		}
		if err = s.persisted(BeepFlushed, j); err != nil {
			return err
		}
	}
	if err = s.store.complete(context.Background(), j); err != nil {
		return err
	}
	return s.persisted(CompletedFlushed, j)
}

func (s *Scheduler) send(ctx context.Context, destination printtransport.Destination, payload []byte) (result printtransport.Result) {
	defer func() {
		if value := recover(); value != nil {
			result = printtransport.Result{State: printtransport.Uncertain, Stage: "transport panic", Detail: fmt.Sprint(value), WriteAttempted: true}
		}
	}()
	return s.sender.Send(ctx, destination, append([]byte(nil), payload...))
}

// Start runs background workers independent of any Flutter/UI lifetime. There
// is one goroutine per explicitly registered physical printer; SQL admission
// and claims enforce order even if RunNext is also called by another worker.
func (s *Scheduler) Start(physicalIDs []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.started || s.stopping || len(physicalIDs) == 0 {
		return ErrBusy
	}
	seen := make(map[string]bool)
	for _, id := range physicalIDs {
		if !CanonicalUUID(id) || seen[id] {
			return ErrInvalid
		}
		seen[id] = true
	}
	s.started = true
	for _, id := range physicalIDs {
		s.active.Add(1)
		go func() {
			defer s.active.Done()
			ticker := time.NewTicker(10 * time.Millisecond)
			defer ticker.Stop()
			for {
				select {
				case <-s.stop:
					return
				default:
				}
				err := s.RunNext(id)
				if err != nil && !errors.Is(err, ErrNoWork) && !errors.Is(err, ErrBusy) {
					select {
					case s.errors <- err:
					default:
					}
					return // a persistence error never triggers another send
				}
				select {
				case <-s.stop:
					return
				case <-ticker.C:
				}
			}
		}()
	}
	return nil
}

func (s *Scheduler) Errors() <-chan error { return s.errors }

// Wait has a public deadline only. Its timeout changes no job, attempt, worker
// context, native ownership or retry policy. The returned pending outcome is
// evidence for the caller to query again using the same immutable identities.
func (s *Scheduler) Wait(ctx context.Context, jobID string) (Outcome, error) {
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		o, err := s.store.Outcome(context.Background(), jobID)
		if err != nil {
			return o, err
		}
		if o.Phase == "complete" || o.Phase == "hold" {
			return o, nil
		}
		select {
		case <-ctx.Done():
			return o, ctx.Err()
		case <-ticker.C:
		}
	}
}

// Stop first closes admission and claim entrance. The scheduler/process lock
// remains held if the public deadline expires. A later Stop can finish after
// the actual synchronous primary and beep futures have settled and flushed.
func (s *Scheduler) Stop(ctx context.Context) error {
	s.mu.Lock()
	s.stopping = true
	s.mu.Unlock()
	s.store.FenceAdmission()
	s.stopOnce.Do(func() { close(s.stop); go func() { s.active.Wait(); close(s.drained) }() })
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-s.drained:
		s.closeOnce.Do(func() { s.closeErr = s.processLock.Close() })
		return s.closeErr
	}
}
