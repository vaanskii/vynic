package printcluster

import (
	"database/sql"
	_ "embed"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"time"

	"github.com/hashicorp/raft"
	_ "modernc.org/sqlite"
)

//go:embed schema.sql
var projectionDDL string

type durableFSM struct {
	mu                  sync.RWMutex
	db                  *sql.DB
	state               *projection
	rows                map[rowKey]durableRow
	rowHashes           map[rowKey]string
	rowSizes            map[rowKey]int
	payloadPersistTime  time.Duration
	payloadPersistCount uint64
	encoded             []byte
	broken              bool
	onFailure           func()
	// Only tests set this before starting a node. It executes inside the same
	// SQL transaction, after the candidate write, to prove atomic rollback.
	afterWrite func() error
}

func openProjection(dir string, pin ClusterConfig) (*durableFSM, error) {
	path := filepath.Join(dir, "projection.sqlite")
	_, statErr := os.Stat(path)
	existed := statErr == nil
	if statErr != nil && !os.IsNotExist(statErr) {
		return nil, statErr
	}
	db, e := sql.Open("sqlite", path)
	if e != nil {
		return nil, e
	}
	db.SetMaxOpenConns(1)
	ok := false
	defer func() {
		if !ok {
			_ = db.Close()
		}
	}()
	if existed {
		var existingVersion int
		if e = db.QueryRow("SELECT schema_version FROM printcluster_projection WHERE id=1").Scan(&existingVersion); e != nil {
			return nil, ErrStorage
		}
		if existingVersion != 2 {
			return nil, ErrMembership
		}
	}
	for _, q := range []string{"PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL", "PRAGMA busy_timeout=5000", "PRAGMA foreign_keys=ON", projectionDDL} {
		if _, e = db.Exec(q); e != nil {
			return nil, e
		}
	}
	if e = verifySQLiteDurability(db); e != nil {
		return nil, e
	}
	f := &durableFSM{db: db, state: initial(pin), rows: map[rowKey]durableRow{}, rowHashes: map[rowKey]string{}}
	var raw []byte
	var cluster, digest string
	var index uint64
	var version int
	e = db.QueryRow("SELECT schema_version,cluster_id,pin_sha256,applied_index,state_json FROM printcluster_projection WHERE id=1").Scan(&version, &cluster, &digest, &index, &raw)
	if e == nil {
		if version != 2 || cluster != pin.ClusterID || digest != pinDigest(pin) {
			return nil, ErrMembership
		}
		if e = f.loadNormalized(raw, pin, index); e != nil {
			return nil, e
		}
	} else if e == sql.ErrNoRows {
		if existed {
			return nil, ErrStorage
		}
		if _, e = f.publish(f.state); e != nil {
			return nil, e
		}
	} else {
		return nil, e
	}
	ok = true
	return f, nil
}
func verifySQLiteDurability(db *sql.DB) error {
	var mode string
	var synchronous int
	if db.QueryRow("PRAGMA journal_mode").Scan(&mode) != nil || db.QueryRow("PRAGMA synchronous").Scan(&synchronous) != nil || mode != "wal" || synchronous != 2 || db.Stats().MaxOpenConnections != 1 {
		return ErrStorage
	}
	return nil
}
func (f *durableFSM) fail() {
	f.broken = true
	if f.onFailure != nil {
		go f.onFailure()
	}
}
func (f *durableFSM) clone() (*projection, error) { return transitionCopy(f.state), nil }
func (f *durableFSM) publish(s *projection) ([]byte, error) {
	raw, e := f.writeNormalized(s)
	if e != nil {
		return nil, e
	}
	f.state = s
	f.encoded = raw
	return raw, nil
}
func (f *durableFSM) Apply(l *raft.Log) interface{} {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.broken {
		return result{Err: ErrStorage}
	}
	if l.Index <= f.state.AppliedIndex {
		// Raft replays committed logs after restarting. Durable state already
		// contains their exact result and FIFO position; never apply again.
		return result{}
	}
	var c command
	invalid := strict(l.Data, raft.SuggestedMaxDataSize, &c) != nil
	s, e := f.clone()
	if e != nil {
		f.fail()
		return result{Err: ErrStorage}
	}
	r := result{Err: ErrInvalid}
	if !invalid {
		r = s.apply(c, l.Index, l.Term)
	} else {
		s.advanceTerm(l.Term)
	}
	s.AppliedIndex = l.Index
	if len(s.Audit) > 2048 {
		e = ErrCapacity
	} else {
		_, e = f.publish(s)
	}
	if e != nil {
		if e == ErrCapacity {
			// A committed command cannot be silently lost. Retain its rejection
			// and applied index in a bounded projection, without publishing the
			// discarded candidate's accepted receipt or sequence.
			fallback, ce := f.clone()
			if ce != nil {
				f.fail()
				return result{Err: ErrStorage}
			}
			fallback.advanceTerm(l.Term)
			fallback.AppliedIndex = l.Index
			if c.Meta != nil {
				if rr, ok := fallback.Requests[c.Meta.RequestID]; ok && rr.Receipt == nil && reflect.DeepEqual(rr.Meta, *c.Meta) {
					rr.Rejection = "capacity"
					delete(fallback.Stages, c.Meta.RequestID)
				}
			}
			if _, ce = f.publish(fallback); ce != nil {
				f.fail()
				return result{Err: ErrStorage}
			}
			return result{Err: ErrCapacity}
		}
		f.fail()
		return result{Err: ErrStorage}
	}
	return r
}
func (f *durableFSM) StoreConfiguration(index uint64, c raft.Configuration) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.broken || index <= f.state.AppliedIndex {
		return
	}
	m, e := membersFromRaft(f.state.Pin, c)
	if e != nil {
		f.fail()
		return
	}
	s, e := f.clone()
	if e != nil {
		f.fail()
		return
	}
	s.Members = m
	s.MembershipGeneration = index
	s.AppliedIndex = index
	if s.Stations != nil {
		s.Stations.Interrupt()
	}
	// A membership change invalidates every previous logical assignment.
	// STARTED remains uncertain; an unstarted claim can safely be released.
	for _, j := range s.Jobs {
		if j.Assignment == nil {
			continue
		}
		if j.State == "ASSIGNED" {
			j.State = "ACCEPTED"
			j.Assignment = nil
		}
		if j.State == "DISPATCHING" {
			j.State = "UNCERTAIN"
			j.PrimaryState = "UNCERTAIN"
		}
		if j.BeepState == "STARTED" {
			j.BeepState = "UNCERTAIN"
		} else if j.State == "PRIMARY_SUBMITTED" && j.BeepState == "NOT_STARTED" {
			j.BeepState = "SKIPPED"
		}
	}
	if _, e = f.publish(s); e != nil {
		f.fail()
	}
}
func (f *durableFSM) Snapshot() (raft.FSMSnapshot, error) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	if f.broken {
		return nil, ErrStorage
	}
	// Full verification and serialization happen only at snapshot/reopen, never
	// for each chunk, reservation or result. Snapshot admission is byte bounded.
	if e := validateProjection(f.state, f.state.Pin); e != nil {
		return nil, e
	}
	raw, e := json.Marshal(snapshotProjection(f.state))
	if e != nil {
		return nil, e
	}
	if len(raw) > MaxStateBytes {
		return nil, ErrCapacity
	}
	return &projectionSnapshot{raw: raw}, nil
}

type projectionSnapshot struct{ raw []byte }

func (s *projectionSnapshot) Persist(sink raft.SnapshotSink) error {
	if count, e := sink.Write(s.raw); e != nil || count != len(s.raw) {
		_ = sink.Cancel()
		if e == nil {
			return io.ErrShortWrite
		}
		return e
	}
	if e := sink.Close(); e != nil {
		_ = sink.Cancel()
		return e
	}
	return nil
}
func (s *projectionSnapshot) Release() {}
func (f *durableFSM) Restore(reader io.ReadCloser) error {
	raw, e := io.ReadAll(io.LimitReader(reader, MaxStateBytes+1))
	closeErr := reader.Close()
	if e != nil {
		return e
	}
	if closeErr != nil {
		return closeErr
	}
	var s projection
	if strict(raw, MaxStateBytes, &s) != nil || hydrateSnapshot(&s) != nil {
		return ErrInvalid
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if e = validateProjection(&s, f.state.Pin); e != nil {
		return e
	}
	if _, e = f.publish(&s); e != nil {
		f.fail()
		return e
	}
	f.broken = false
	return nil
}
func (f *durableFSM) close() error { return f.db.Close() }
func (f *durableFSM) generation() uint64 {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.state.MembershipGeneration
}
func (f *durableFSM) view(id string) (JobView, error) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	if f.broken {
		return JobView{}, ErrStorage
	}
	st, ok := f.state.Jobs[id]
	if !ok {
		return JobView{}, ErrInvalid
	}
	j, e := DecodeJob(st.Raw)
	if e != nil {
		return JobView{}, e
	}
	v := JobView{Job: j, Receipt: st.Receipt, State: st.State, PrimaryState: st.PrimaryState, BeepState: st.BeepState}
	if st.Assignment != nil {
		a := *st.Assignment
		v.Assignment = &a
	}
	return v, nil
}
