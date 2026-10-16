package printcluster

import (
	"bytes"
	"context"
	"encoding/json"
	"reflect"

	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

// Station commands reuse the existing majority log, chunk admission, durable
// projection and snapshots. They never call transport or confer physical rights.
type stationCommand struct {
	Op              string                  `json:"op"`
	Catalog         *printstation.Catalog   `json:"catalog,omitempty"`
	JobID           string                  `json:"jobId,omitempty"`
	AttemptID       string                  `json:"attemptId,omitempty"`
	At              int64                   `json:"at,omitempty"`
	TransportResult printtransport.Result   `json:"transportResult,omitempty"`
	PrinterID       string                  `json:"printerId,omitempty"`
	RouteState      printstation.RouteState `json:"routeState,omitempty"`
	ActorID         string                  `json:"actorId,omitempty"`
	Reason          string                  `json:"reason,omitempty"`
}

func (s *projection) stationAuthority(a Caller) printstation.Authority {
	p, _ := s.Pin.peer(a.MemberID)
	return printstation.Authority{VenueID: s.Pin.VenueID, DeviceID: p.DeviceID, ControllerID: p.ID, Admin: p.Admin}
}
func stationError(e error) error {
	switch e {
	case nil:
		return nil
	case printstation.ErrScope:
		return ErrScope
	case printstation.ErrReuse:
		return ErrReuse
	case printstation.ErrCapacity:
		return ErrCapacity
	case printstation.ErrInvalid:
		return ErrInvalid
	case printstation.ErrConfig:
		return ErrConfig
	default:
		return ErrBusy
	}
}
func (s *projection) applyStation(c command, index uint64) result {
	if c.Station == nil {
		return result{Err: ErrInvalid}
	}
	x := c.Station
	if s.Stations == nil {
		s.Stations = printstation.New(s.Pin.VenueID)
	}
	a := s.stationAuthority(c.Caller)
	switch x.Op {
	case "admitPayload":
		return s.admitRetainedPayload(c, index)
	case "compact":
		removed, e := s.Stations.Compact(a, x.At)
		if e != nil {
			return result{Err: stationError(e)}
		}
		retired := map[string]bool{}
		for _, id := range removed {
			retired[id] = true
		}
		for id, r := range s.Requests {
			if r.Meta.StationJob && ((r.Receipt != nil && retired[r.Meta.JobID]) || (r.Rejection != "" && r.Meta.StationMetadata != nil && r.Meta.StationMetadata.CreatedAt <= s.Stations.RetiredBefore)) {
				delete(s.Requests, id)
			}
		}
		return result{}
	case "config":
		if len(s.Configs) != 0 {
			return result{Err: ErrConfig}
		}
		if x.Catalog == nil {
			return result{Err: ErrInvalid}
		}
		for _, controller := range x.Catalog.Controllers {
			p, ok := s.Pin.peer(controller.ID)
			if s.Pin.Version == 2 {
				p, ok = s.Pin.peer(controller.InstallationID)
			}
			if !ok || p.DeviceID != controller.DeviceID || p.InstallationID != controller.InstallationID {
				return result{Err: ErrScope}
			}
		}
		// A station snapshot cannot claim LOCAL authority in a shared cluster.
		for _, station := range x.Catalog.Stations {
			if string(station.Scope) != s.Pin.Scope {
				return result{Err: ErrScope}
			}
		}
		return result{Err: stationError(s.Stations.Install(a, *x.Catalog))}
	case "begin":
		attempt, e := s.Stations.Begin(a, x.JobID, x.AttemptID, x.At)
		if e != nil {
			return result{Err: stationError(e)}
		}
		return result{StationAttempt: &attempt}
	case "finish":
		return result{Err: stationError(s.Stations.Finish(a, x.JobID, x.AttemptID, x.At, x.TransportResult))}
	case "routeState":
		return result{Err: stationError(s.Stations.SetRouteState(a, x.PrinterID, x.RouteState))}
	case "skipUnavailable":
		return result{Err: stationError(s.Stations.SkipUnavailable(a, x.JobID, x.AttemptID, x.Reason, x.At))}
	case "reconcileProof":
		return result{Err: stationError(s.Stations.ReconcileProof(a, x.JobID, x.ActorID, x.Reason, x.At))}
	default:
		return result{Err: ErrInvalid}
	}
}
func stationReceipt(r *printstation.Record) Receipt {
	return Receipt{Status: "ACCEPTED", JobID: r.Job.ID, InputSHA256: sha(printstation.Encode(r.Job)), Sequence: r.Sequence, CommitIndex: r.CommitIndex}
}
func (s *projection) finalizeStation(c command, request *requestRecord, raw []byte, index uint64, reject func(error) result) result {
	var j printstation.Job
	if request.Meta.StationMetadata != nil {
		j = *request.Meta.StationMetadata
		j.Payload = raw
		if sha(printstation.Encode(j)) != request.Meta.Digest {
			return reject(ErrReuse)
		}
	} else {
		if strict(raw, MaxEnvelopeBytes, &j) != nil || string(raw) != string(printstation.Encode(j)) {
			return reject(ErrInvalid)
		}
	}
	if j.Validate() != nil || j.ID != request.Meta.JobID || request.Meta.EffectID != j.ID || s.Stations == nil {
		return reject(ErrInvalid)
	}
	if _, exists := s.Jobs[j.ID]; exists {
		return reject(ErrReuse)
	}
	if retained := retainedPayload(s, j.PayloadDigest, len(j.Payload)); retained != nil {
		if !bytes.Equal(retained, j.Payload) {
			return reject(ErrReuse)
		}
		j.Payload = retained
	}
	row, e := s.Stations.Admit(s.stationAuthority(c.Caller), j, index)
	if e != nil {
		return reject(stationError(e))
	}
	// Intern the verified immutable bytes shared with a retained payload. The
	// returned record remains an owned copy; FSM records never mutate bytes.
	s.Stations.Jobs[j.ID].Job.Payload = j.Payload
	receipt := stationReceipt(row)
	request.Receipt = &receipt
	delete(s.Stages, request.Meta.RequestID)
	return result{Receipt: &receipt, StationRecord: row}
}
func (n *Node) InstallStations(ctx context.Context, a Caller, c printstation.Catalog) error {
	_, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "config", Catalog: &c}})
	return e
}
func (n *Node) SubmitStation(ctx context.Context, a Caller, requestID string, j printstation.Job) (Receipt, error) {
	if !uuid(requestID) || j.Validate() != nil || !n.currentPin().authorize(a, false) {
		return Receipt{}, ErrInvalid
	}
	p, _ := n.currentPin().peer(a.MemberID)
	if j.VenueID != n.pin.VenueID || j.SourceDeviceID != p.DeviceID {
		return Receipt{}, ErrScope
	}
	raw, m := stationSubmission(a, requestID, j)
	n.fsm.mu.RLock()
	retained := retainedPayload(n.fsm.state, j.PayloadDigest, len(j.Payload)) != nil
	n.fsm.mu.RUnlock()
	if retained {
		r, e := n.apply(ctx, command{Op: "station", Caller: a, Meta: &m, Station: &stationCommand{Op: "admitPayload"}})
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
		r, e := n.apply(ctx, command{Op: "chunk", Caller: a, Meta: &m, ChunkIndex: i, Chunk: raw[i*ChunkBytes : i*ChunkBytes+m.chunkLength(i)]})
		if e != nil {
			return Receipt{}, e
		}
		if r.Receipt != nil {
			return *r.Receipt, nil
		}
	}
	r, e := n.apply(ctx, command{Op: "finalize", Caller: a, Meta: &m})
	if e != nil {
		return Receipt{}, e
	}
	if r.Receipt == nil {
		return Receipt{}, ErrStorage
	}
	return *r.Receipt, nil
}
func (n *Node) BeginStationAttempt(ctx context.Context, a Caller, jobID, attemptID string, at int64) (printstation.Attempt, error) {
	r, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "begin", JobID: jobID, AttemptID: attemptID, At: at}})
	if e != nil {
		return printstation.Attempt{}, e
	}
	if r.StationAttempt == nil {
		return printstation.Attempt{}, ErrStorage
	}
	return *r.StationAttempt, nil
}
func (n *Node) FinishStationAttempt(ctx context.Context, a Caller, jobID, attemptID string, at int64, outcome printtransport.Result) error {
	_, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "finish", JobID: jobID, AttemptID: attemptID, At: at, TransportResult: outcome}})
	return e
}
func (n *Node) SetStationRouteState(ctx context.Context, a Caller, printer string, state printstation.RouteState) error {
	_, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "routeState", PrinterID: printer, RouteState: state}})
	return e
}
func (n *Node) ReconcileStationProof(ctx context.Context, a Caller, job, actor, reason string, at int64) error {
	_, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "reconcileProof", JobID: job, ActorID: actor, Reason: reason, At: at}})
	return e
}

func (n *Node) SkipUnavailableStationRoute(ctx context.Context, a Caller, job, attempt, reason string, at int64) error {
	_, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "skipUnavailable", JobID: job, AttemptID: attempt, Reason: reason, At: at}})
	return e
}
func (n *Node) ReadStation(ctx context.Context, jobID string) (printstation.Record, error) {
	if e := n.SyncLogicalState(ctx); e != nil {
		return printstation.Record{}, e
	}
	return n.InspectStationReplica(jobID)
}
func (n *Node) InspectStationReplica(jobID string) (printstation.Record, error) {
	n.fsm.mu.RLock()
	defer n.fsm.mu.RUnlock()
	if n.fsm.broken {
		return printstation.Record{}, ErrStorage
	}
	if n.fsm.state.Stations == nil {
		return printstation.Record{}, ErrInvalid
	}
	r, ok := n.fsm.state.Stations.Jobs[jobID]
	if !ok {
		return printstation.Record{}, ErrInvalid
	}
	var copy printstation.Record
	if e := json.Unmarshal(printstation.Encode(r), &copy); e != nil {
		return copy, e
	}
	return copy, nil
}

// Job metadata and rendered payload have distinct stable identities. Chunk log
// entries transfer raw payload bytes once; finalization refers to their digest.
func stationSubmission(a Caller, requestID string, j printstation.Job) ([]byte, chunkMeta) {
	digest := sha(printstation.Encode(j))
	raw := j.Payload
	j.Payload = nil
	return raw, chunkMeta{StationJob: true, StationMetadata: &j, RequestID: requestID, JobID: j.ID, EffectID: j.ID, Digest: digest, TotalBytes: len(raw), TotalChunks: (len(raw) + ChunkBytes - 1) / ChunkBytes, Caller: a}
}

func (n *Node) CompactStationHistory(ctx context.Context, a Caller, now int64) error {
	_, e := n.apply(ctx, command{Op: "station", Caller: a, Station: &stationCommand{Op: "compact", At: now}})
	return e
}

func retainedPayload(s *projection, digest string, length int) []byte {
	if s.Stations == nil {
		return nil
	}
	for _, r := range s.Stations.Jobs {
		if r.Job.PayloadDigest == digest && len(r.Job.Payload) == length {
			return r.Job.Payload
		}
	}
	return nil
}
func (s *projection) admitRetainedPayload(c command, index uint64) result {
	m := c.Meta
	if m == nil || m.StationMetadata == nil || !m.valid(s.Pin) || m.Caller != c.Caller {
		return result{Err: ErrInvalid}
	}
	if old, ok := s.Requests[m.RequestID]; ok {
		if !reflect.DeepEqual(old.Meta, *m) {
			return result{Err: ErrReuse}
		}
		if old.Receipt != nil {
			return result{Receipt: old.Receipt}
		}
		if old.Rejection != "" {
			return result{Err: rejection(old.Rejection)}
		}
	}
	payload := retainedPayload(s, m.StationMetadata.PayloadDigest, m.TotalBytes)
	if payload == nil {
		return result{Err: ErrPayloadMissing}
	}
	if s.pendingRequests() >= 256 {
		return result{Err: ErrCapacity}
	}
	r := &requestRecord{Meta: *m, ChunkHashes: map[int]string{}}
	for i := 0; i < m.TotalChunks; i++ {
		r.ChunkHashes[i] = sha(payload[i*ChunkBytes : i*ChunkBytes+m.chunkLength(i)])
	}
	s.Requests[m.RequestID] = r
	reject := func(e error) result { r.Rejection = code(e); delete(s.Stages, m.RequestID); return result{Err: e} }
	return s.finalizeStation(c, r, payload, index, reject)
}
