package printcluster

import (
	"context"

	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

// StationControllerQueue binds one provisioned caller to a leader resolver. The
// resolver is an explicit proof seam, not network discovery or authentication.
type StationControllerQueue struct {
	Leader func() *Node
	Caller Caller
}

func (q StationControllerQueue) Load(ctx context.Context, job string) (printstation.Work, error) {
	if q.Leader == nil {
		return printstation.Work{}, ErrNoQuorum
	}
	n := q.Leader()
	if n == nil {
		return printstation.Work{}, ErrNoQuorum
	}
	if !n.pin.authorize(q.Caller, false) {
		return printstation.Work{}, ErrScope
	}
	if e := n.SyncLogicalState(ctx); e != nil {
		return printstation.Work{}, e
	}
	n.fsm.mu.RLock()
	defer n.fsm.mu.RUnlock()
	if n.fsm.broken || n.fsm.state.Stations == nil {
		return printstation.Work{}, ErrStorage
	}
	return n.fsm.state.Stations.Work(job)
}
func (q StationControllerQueue) Begin(ctx context.Context, job, attempt string, at int64) (printstation.Attempt, error) {
	if q.Leader == nil {
		return printstation.Attempt{}, ErrNoQuorum
	}
	n := q.Leader()
	if n == nil {
		return printstation.Attempt{}, ErrNoQuorum
	}
	return n.BeginStationAttempt(ctx, q.Caller, job, attempt, at)
}
func (q StationControllerQueue) Finish(ctx context.Context, job, attempt string, at int64, r printtransport.Result) error {
	if q.Leader == nil {
		return ErrNoQuorum
	}
	n := q.Leader()
	if n == nil {
		return ErrNoQuorum
	}
	return n.FinishStationAttempt(ctx, q.Caller, job, attempt, at, r)
}

type LocalStationControllerQueue struct {
	Spool  *LocalStationSpool
	Caller Caller
}

func (q LocalStationControllerQueue) Load(_ context.Context, job string) (printstation.Work, error) {
	if q.Spool == nil {
		return printstation.Work{}, ErrStorage
	}
	s := q.Spool
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.fsm.broken || s.fsm.state.Stations == nil {
		return printstation.Work{}, ErrStorage
	}
	if !s.pin.authorize(q.Caller, false) {
		return printstation.Work{}, ErrScope
	}
	return s.fsm.state.Stations.Work(job)
}
func (q LocalStationControllerQueue) Begin(ctx context.Context, job, attempt string, at int64) (printstation.Attempt, error) {
	if q.Spool == nil {
		return printstation.Attempt{}, ErrStorage
	}
	return q.Spool.Begin(ctx, q.Caller, job, attempt, at)
}
func (q LocalStationControllerQueue) Finish(_ context.Context, job, attempt string, at int64, r printtransport.Result) error {
	if q.Spool == nil {
		return ErrStorage
	}
	_, e := q.Spool.apply(command{Op: "station", Caller: q.Caller, Station: &stationCommand{Op: "finish", JobID: job, AttemptID: attempt, At: at, TransportResult: r}})
	return e
}
