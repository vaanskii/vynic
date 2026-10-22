package printcluster

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"

	"github.com/gofrs/flock"
	"github.com/hashicorp/raft"
	"vynic.local/edge/internal/printstation"
)

// LocalStationSpool reuses the same FULL/WAL projection and station state machine
// without starting Raft or requiring quorum. It is restricted to disposable
// proof roots and holds one process lock through durable closure.
type LocalStationSpool struct {
	mu     sync.Mutex
	fsm    *durableFSM
	pin    ClusterConfig
	lock   *flock.Flock
	closed bool
}

func OpenLocalStationProof(dir string, pin ClusterConfig) (*LocalStationSpool, error) {
	if !proofDirectory(dir) || pin.validate() != nil || pin.Scope != Local || pin.Voters != 1 || len(pin.Peers) != 1 {
		return nil, ErrScope
	}
	return openLocalStation(dir, pin)
}
func openLocalStation(dir string, pin ClusterConfig) (*LocalStationSpool, error) {
	// Resolve aliases before locking; two paths to the same directory must
	// exclude each other. No database is opened before process exclusion.
	if e := os.MkdirAll(dir, 0700); e != nil {
		return nil, e
	}
	real, e := filepath.EvalSymlinks(dir)
	if e != nil {
		return nil, e
	}
	l := flock.New(filepath.Join(real, ".station.lock"))
	ok, e := l.TryLock()
	if e != nil || !ok {
		return nil, errors.Join(ErrBusy, e, l.Close())
	}
	if _, e = os.Stat(filepath.Join(dir, "raft.bolt")); !os.IsNotExist(e) {
		return nil, errors.Join(ErrScope, l.Close())
	}
	f, e := openProjection(dir, pin)
	if e != nil {
		return nil, errors.Join(e, l.Close())
	}
	s := &LocalStationSpool{fsm: f, pin: pin, lock: l}
	a := Caller{pin.Peers[0].ID, pin.Peers[0].TerminalID, pin.Peers[0].InstallationID}
	if _, e = s.apply(command{Op: "sync", Caller: a}); e != nil {
		return nil, errors.Join(e, s.Close())
	}
	return s, nil
}
func (s *LocalStationSpool) apply(c command) (result, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return result{}, ErrStorage
	}
	c.Version = 2
	b, e := json.Marshal(c)
	if e != nil || len(b) > raft.SuggestedMaxDataSize {
		return result{}, ErrInvalid
	}
	term := s.fsm.state.Term
	if term == 0 || c.Op == "sync" {
		term++
	}
	r, ok := s.fsm.Apply(&raft.Log{Index: s.fsm.state.AppliedIndex + 1, Term: term, Data: b}).(result)
	if !ok {
		return result{}, ErrStorage
	}
	return r, r.Err
}
func (s *LocalStationSpool) Install(a Caller, c printstation.Catalog) error {
	_, e := s.apply(command{Op: "station", Caller: a, Station: &stationCommand{Op: "config", Catalog: &c}})
	return e
}
func (s *LocalStationSpool) Submit(a Caller, requestID string, j printstation.Job) (Receipt, error) {
	if !uuid(requestID) || j.Validate() != nil {
		return Receipt{}, ErrInvalid
	}
	raw, m := stationSubmission(a, requestID, j)
	s.fsm.mu.RLock()
	retained := retainedPayload(s.fsm.state, j.PayloadDigest, len(j.Payload)) != nil
	s.fsm.mu.RUnlock()
	if retained {
		r, e := s.apply(command{Op: "station", Caller: a, Meta: &m, Station: &stationCommand{Op: "admitPayload"}})
		if e == nil && r.Receipt != nil {
			return *r.Receipt, nil
		}
		if e != ErrPayloadMissing {
			if e == nil {
				e = ErrStorage
			}
			return Receipt{}, e
		}
	}
	for i := 0; i < m.TotalChunks; i++ {
		r, e := s.apply(command{Op: "chunk", Caller: a, Meta: &m, ChunkIndex: i, Chunk: raw[i*ChunkBytes : i*ChunkBytes+m.chunkLength(i)]})
		if e != nil {
			return Receipt{}, e
		}
		if r.Receipt != nil {
			return *r.Receipt, nil
		}
	}
	r, e := s.apply(command{Op: "finalize", Caller: a, Meta: &m})
	if e != nil {
		return Receipt{}, e
	}
	if r.Receipt == nil {
		return Receipt{}, ErrStorage
	}
	return *r.Receipt, nil
}
func (s *LocalStationSpool) Inspect(job string) (printstation.Record, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.fsm.broken || s.fsm.state.Stations == nil {
		return printstation.Record{}, ErrStorage
	}
	r, ok := s.fsm.state.Stations.Jobs[job]
	if !ok {
		return printstation.Record{}, ErrInvalid
	}
	var copy printstation.Record
	e := json.Unmarshal(printstation.Encode(r), &copy)
	return copy, e
}
func (s *LocalStationSpool) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	if e := s.fsm.close(); e != nil {
		return e
	}
	s.closed = true
	return s.lock.Close()
}

// Context cancellation before a call does not turn a retained attempt into a
// safe fallback. Actual sender lifetimes belong to the host's retained drain.
func (s *LocalStationSpool) Begin(ctx context.Context, a Caller, job, attempt string, at int64) (printstation.Attempt, error) {
	if e := ctx.Err(); e != nil {
		return printstation.Attempt{}, e
	}
	r, e := s.apply(command{Op: "station", Caller: a, Station: &stationCommand{Op: "begin", JobID: job, AttemptID: attempt, At: at}})
	if e != nil {
		return printstation.Attempt{}, e
	}
	return *r.StationAttempt, nil
}
