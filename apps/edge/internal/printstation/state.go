package printstation

import (
	"bytes"
	"encoding/json"
	"fmt"
	"slices"

	"vynic.local/edge/internal/printtransport"
)

type JobState string

const (
	Queued      JobState = "QUEUED"
	Dispatching JobState = "DISPATCHING"
	Submitted   JobState = "SUBMITTED"
	Uncertain   JobState = "UNCERTAIN"
	Failed      JobState = "FAILED"
	Reconciled  JobState = "RECONCILED"
)

type Outcome string

const (
	NotSubmitted  Outcome = "NOT_SUBMITTED"
	AcceptedBytes Outcome = "SUBMITTED"
	Unknown       Outcome = "UNCERTAIN"
)

type Reprint struct {
	OriginalID string `json:"originalId"`
	ActorID    string `json:"actorId"`
	Reason     string `json:"reason"`
	At         int64  `json:"at"`
}
type Job struct {
	Version        int      `json:"version"`
	ID             string   `json:"id"`
	VenueID        string   `json:"venueId"`
	StationID      string   `json:"stationId"`
	SourceDeviceID string   `json:"sourceDeviceId"`
	EffectID       string   `json:"effectId"`
	OutputKind     string   `json:"outputKind"`
	BusinessRef    string   `json:"businessRef"`
	ConfigDigest   string   `json:"configDigest"`
	CreatedAt      int64    `json:"createdAt"`
	Payload        []byte   `json:"payload"`
	PayloadDigest  string   `json:"payloadDigest"`
	Reprint        *Reprint `json:"reprint,omitempty"`
}

func (j Job) Validate() error {
	if j.Version != 1 || !id(j.ID) || !id(j.VenueID) || !id(j.StationID) || !id(j.SourceDeviceID) || !label(j.EffectID) || !label(j.OutputKind) || !label(j.BusinessRef) || j.CreatedAt <= 0 || len(j.ConfigDigest) != 64 || len(j.Payload) == 0 || len(j.Payload) > printtransport.MaxTransmissionBytes || Digest(j.Payload) != j.PayloadDigest {
		return ErrInvalid
	}
	if j.Reprint == nil {
		if j.ID != OutputID(j.VenueID, j.EffectID, j.StationID, j.OutputKind) {
			return ErrInvalid
		}
	} else if !id(j.Reprint.OriginalID) || j.Reprint.OriginalID == j.ID || !id(j.Reprint.ActorID) || !label(j.Reprint.Reason) || j.Reprint.At <= 0 {
		return ErrInvalid
	}
	return nil
}

type Attempt struct {
	ID           string  `json:"id"`
	JobID        string  `json:"jobId"`
	Number       int     `json:"number"`
	PrinterID    string  `json:"printerId"`
	ControllerID string  `json:"controllerId"`
	StartedAt    int64   `json:"startedAt"`
	FinishedAt   int64   `json:"finishedAt,omitempty"`
	Outcome      Outcome `json:"outcome,omitempty"`
	Diagnostic   string  `json:"diagnostic,omitempty"`
}
type Record struct {
	Job         Job       `json:"job"`
	Sequence    uint64    `json:"sequence"`
	CommitIndex uint64    `json:"commitIndex"`
	State       JobState  `json:"state"`
	NextRoute   int       `json:"nextRoute"`
	Attempts    []Attempt `json:"attempts"`
	Resolution  *Reprint  `json:"resolution,omitempty"` // actor/reason/time, not a rewritten result
}
type State struct {
	RetiredBefore int64                 `json:"retiredBefore,omitempty"`
	Version       int                   `json:"version"`
	VenueID       string                `json:"venueId"`
	Current       string                `json:"current"`
	Catalogs      map[string]Catalog    `json:"catalogs"`
	Jobs          map[string]*Record    `json:"jobs"`
	Sequences     map[string]uint64     `json:"sequences"`
	RouteStates   map[string]RouteState `json:"routeStates"`
}

func New(venue string) *State {
	return &State{Version: 1, VenueID: venue, Catalogs: map[string]Catalog{}, Jobs: map[string]*Record{}, Sequences: map[string]uint64{}, RouteStates: map[string]RouteState{}}
}
func clone[T any](v T) T {
	switch x := any(v).(type) {
	case Job:
		x.Payload = bytes.Clone(x.Payload)
		if x.Reprint != nil {
			r := *x.Reprint
			x.Reprint = &r
		}
		return any(x).(T)
	case *Record:
		if x == nil {
			return v
		}
		r := *x
		r.Job = clone(x.Job)
		r.Attempts = slices.Clone(x.Attempts)
		if x.Resolution != nil {
			a := *x.Resolution
			r.Resolution = &a
		}
		return any(&r).(T)
	}

	var result T
	if err := json.Unmarshal(Encode(v), &result); err != nil {
		panic(fmt.Errorf("clone validated station value: %w", err))
	}
	return result
}
func (s *State) Install(a Authority, c Catalog) error {
	if !a.Admin || a.VenueID != s.VenueID || c.VenueID != s.VenueID {
		return ErrScope
	}
	if err := c.Validate(); err != nil {
		return err
	}
	h := c.Digest()
	if _, ok := s.Catalogs[h]; ok {
		if s.Current != h {
			return ErrConfig
		}
		return nil
	}
	if len(s.Catalogs) >= 64 {
		return ErrCapacity
	}
	if old, ok := s.Catalogs[s.Current]; ok {
		if c.Revision <= old.Revision {
			return ErrConfig
		}
		for _, catalog := range s.Catalogs {
			for _, prior := range catalog.Controllers {
				if next, exists := c.Controller(prior.ID); exists && (prior.InstallationID != next.InstallationID || prior.DeviceID != next.DeviceID) {
					return ErrHeld
				}
			}
			for _, prior := range catalog.Stations {
				if next, exists := c.Station(prior.ID); exists && (prior.Scope != next.Scope || prior.OwnerDeviceID != next.OwnerDeviceID) {
					return ErrHeld
				}
			}
			for _, prior := range catalog.Printers {
				for _, next := range c.Printers {
					if endpoint(prior) == endpoint(next) && prior.ID != next.ID {
						return ErrConfig
					}
					// This API cannot transfer hardware ownership or repoint an alias.
					if prior.ID == next.ID && (prior.ControllerID != next.ControllerID || !bytes.Equal(Encode(prior.Destination), Encode(next.Destination))) {
						return ErrHeld
					}
				}
			}
		}
		for _, record := range s.Jobs {
			if record.State == Submitted || record.State == Reconciled {
				continue
			}
			frozen := s.Catalogs[record.Job.ConfigDigest]
			station, _ := frozen.Station(record.Job.StationID)
			for _, physical := range station.Routes {
				prior, _ := frozen.Printer(physical)
				next, exists := c.Printer(physical)
				if exists && !bytes.Equal(prior.Profile, next.Profile) {
					return ErrHeld
				}
			}
		}
		for _, prior := range old.Stations {
			if next, exists := c.Station(prior.ID); exists && (prior.Scope != next.Scope || prior.OwnerDeviceID != next.OwnerDeviceID) {
				return ErrHeld
			}
		}
		for _, prior := range old.Controllers {
			if next, exists := c.Controller(prior.ID); exists && (prior.InstallationID != next.InstallationID || prior.DeviceID != next.DeviceID) {
				return ErrHeld
			}
		}
	}
	s.Catalogs[h] = clone(c)
	s.Current = h
	return nil
}
func (s *State) Admit(a Authority, j Job, index uint64) (*Record, error) {
	if j.Validate() != nil || index == 0 {
		return nil, ErrInvalid
	}
	if a.VenueID != s.VenueID || j.VenueID != s.VenueID || a.DeviceID != j.SourceDeviceID {
		return nil, ErrScope
	}
	if old, ok := s.Jobs[j.ID]; ok {
		if !bytes.Equal(Encode(old.Job), Encode(j)) {
			return nil, ErrReuse
		}
		return clone(old), nil
	}
	if j.CreatedAt <= s.RetiredBefore {
		return nil, ErrConfig
	}
	if s.pending() >= 128 {
		return nil, ErrCapacity
	}
	c, ok := s.Catalogs[j.ConfigDigest]
	if !ok || j.ConfigDigest != s.Current {
		return nil, ErrConfig
	}
	station, ok := c.Station(j.StationID)
	if !ok || !station.Enabled {
		return nil, ErrConfig
	}
	if station.Scope == Local && station.OwnerDeviceID != a.DeviceID {
		return nil, ErrScope
	}
	if j.Reprint != nil {
		if !a.Admin {
			return nil, ErrScope
		}
		old, ok := s.Jobs[j.Reprint.OriginalID]
		if !ok || old.Job.StationID != j.StationID || old.Job.BusinessRef != j.BusinessRef || old.Job.PayloadDigest != j.PayloadDigest || !bytes.Equal(old.Job.Payload, j.Payload) {
			return nil, ErrConfig
		}
		// A copy never clears the original hold. Reconcile it first.
		if old.State != Submitted && old.State != Reconciled {
			return nil, ErrHeld
		}
	}
	s.Sequences[j.StationID]++
	r := &Record{Job: clone(j), Sequence: s.Sequences[j.StationID], CommitIndex: index, State: Queued, Attempts: []Attempt{}}
	s.Jobs[j.ID] = r
	return clone(r), nil
}
func (s *State) Head(station string) *Record {
	var head *Record
	for _, r := range s.Jobs {
		if r.Job.StationID != station || r.State == Submitted || r.State == Reconciled {
			continue
		}
		if head == nil || r.Sequence < head.Sequence {
			head = r
		}
	}
	return clone(head)
}
func (s *State) route(r *Record) (PhysicalPrinter, error) {
	c := s.Catalogs[r.Job.ConfigDigest]
	station, ok := c.Station(r.Job.StationID)
	if !ok || r.NextRoute >= len(station.Routes) {
		return PhysicalPrinter{}, ErrHeld
	}
	p, ok := c.Printer(station.Routes[r.NextRoute])
	if !ok {
		return p, ErrConfig
	}
	return p, nil
}
func (s *State) physicalHeld(physical string) bool {
	for _, r := range s.Jobs {
		if r.State != Dispatching && r.State != Uncertain {
			continue
		}
		for _, a := range r.Attempts {
			if a.PrinterID == physical && (a.Outcome == "" || a.Outcome == Unknown) {
				return true
			}
		}
	}
	return false
}

// Begin is durable before any transport call. Only the configured controller may
// claim it. A missing RPC response is not permission to issue another attempt.
func (s *State) Begin(a Authority, jobID, attemptID string, at int64) (Attempt, error) {
	if a.VenueID != s.VenueID || !id(a.ControllerID) {
		return Attempt{}, ErrScope
	}
	if !id(attemptID) || at <= 0 {
		return Attempt{}, ErrInvalid
	}
	r, ok := s.Jobs[jobID]
	if !ok {
		return Attempt{}, ErrNoWork
	}
	for _, row := range s.Jobs {
		for _, attempt := range row.Attempts {
			if attempt.ID == attemptID {
				return Attempt{}, ErrReuse
			}
		}
	}
	head := s.Head(r.Job.StationID)
	if head == nil || head.Job.ID != jobID || r.State != Queued {
		return Attempt{}, ErrHeld
	}
	p, err := s.route(r)
	if err != nil {
		return Attempt{}, err
	}
	if p.ControllerID != a.ControllerID {
		return Attempt{}, ErrScope
	}
	current := s.Catalogs[s.Current]
	currentStation, exists := current.Station(r.Job.StationID)
	if !exists || !currentStation.Enabled {
		return Attempt{}, ErrHeld
	}
	if s.physicalHeld(p.ID) {
		return Attempt{}, ErrHeld
	}
	state := s.RouteStates[p.ID]
	if state == Held || state == RouteUncertain || state == Offline || state == Unreachable {
		return Attempt{}, ErrHeld
	}
	if len(r.Attempts) >= 8 {
		return Attempt{}, ErrCapacity
	}
	x := Attempt{ID: attemptID, JobID: jobID, Number: len(r.Attempts) + 1, PrinterID: p.ID, ControllerID: p.ControllerID, StartedAt: at}
	active, exists := current.Printer(p.ID)
	if !p.Enabled || !exists || !active.Enabled || state == Disabled {
		x.Outcome = NotSubmitted
		x.FinishedAt = at
		x.Diagnostic = "route disabled before dispatch"
		r.Attempts = append(r.Attempts, x)
		s.advance(r)
		return x, nil
	}
	r.Attempts = append(r.Attempts, x)
	r.State = Dispatching
	return x, nil
}
func (s *State) advance(r *Record) {
	r.NextRoute++
	station, _ := s.Catalogs[r.Job.ConfigDigest].Station(r.Job.StationID)
	r.State = Queued
	if r.NextRoute >= len(station.Routes) {
		r.State = Failed
	}
}

// SkipUnavailable commits that no dispatch reservation was issued for this
// route. It can race with Begin: only one transition wins. A health timeout
// after Begin can never use this path, even if the controller stops responding.
func (s *State) SkipUnavailable(a Authority, jobID, attemptID, reason string, at int64) error {
	if !a.Admin || a.VenueID != s.VenueID {
		return ErrScope
	}
	if !id(attemptID) || !label(reason) || at <= 0 {
		return ErrInvalid
	}
	r, ok := s.Jobs[jobID]
	if !ok {
		return ErrNoWork
	}
	head := s.Head(r.Job.StationID)
	if r.State != Queued || head == nil || head.Job.ID != jobID {
		return ErrHeld
	}
	station, ok := s.Catalogs[s.Current].Station(r.Job.StationID)
	if !ok || !station.Enabled {
		return ErrHeld
	}
	for _, row := range s.Jobs {
		for _, x := range row.Attempts {
			if x.ID == attemptID {
				return ErrReuse
			}
		}
	}
	p, e := s.route(r)
	if e != nil {
		return e
	}
	r.Attempts = append(r.Attempts, Attempt{ID: attemptID, JobID: jobID, Number: len(r.Attempts) + 1, PrinterID: p.ID, ControllerID: p.ControllerID, StartedAt: at, FinishedAt: at, Outcome: NotSubmitted, Diagnostic: "no dispatch reservation: " + reason})
	s.advance(r)
	return nil
}

// Finish requires the actual synchronous transport result, never a client wait
// timeout. Anything inconsistent with definite zero-byte pre-dispatch failure
// is uncertainty; it cannot authorize backup selection.
func (s *State) Finish(a Authority, jobID, attemptID string, at int64, result printtransport.Result) error {
	if a.VenueID != s.VenueID {
		return ErrScope
	}
	r, ok := s.Jobs[jobID]
	if !ok || len(r.Attempts) == 0 {
		return ErrInvalid
	}
	x := &r.Attempts[len(r.Attempts)-1]
	if x.ID != attemptID || x.ControllerID != a.ControllerID {
		return ErrScope
	}
	if r.State != Dispatching || x.Outcome != "" || at < x.StartedAt {
		return ErrHeld
	}
	x.FinishedAt = at
	x.Diagnostic = result.Stage + ": " + result.Detail
	if len(x.Diagnostic) > 512 {
		x.Diagnostic = x.Diagnostic[:512]
	}
	switch {
	case result.State == printtransport.NotSent && !result.WriteAttempted && result.BytesWritten == 0 && result.JobID == 0 && len(result.Stage) <= 256 && len(result.Detail) <= 4096:
		x.Outcome = NotSubmitted
		s.advance(r)
	case result.State == printtransport.Submitted && result.WriteAttempted && int(result.BytesWritten) == len(r.Job.Payload) && len(result.Stage) <= 256 && len(result.Detail) <= 4096:
		x.Outcome = AcceptedBytes
		r.State = Submitted
	default:
		x.Outcome = Unknown
		r.State = Uncertain
	}
	return nil
}

// Interrupt records uncertainty only. Leader/process loss never reallocates a
// physical writer and never advances a fallback cursor.
func (s *State) Interrupt() {
	for _, r := range s.Jobs {
		if r.State == Dispatching {
			r.State = Uncertain
			x := &r.Attempts[len(r.Attempts)-1]
			x.Outcome = Unknown
			x.Diagnostic = "dispatch completion not durably recorded"
		}
	}
}
func (s *State) SetRouteState(a Authority, printer string, state RouteState) error {
	if !a.Admin || a.VenueID != s.VenueID {
		return ErrScope
	}
	if _, ok := s.Catalogs[s.Current].Printer(printer); !ok {
		return ErrConfig
	}
	if !slices.Contains([]RouteState{Available, Offline, Unreachable, Held, RouteUncertain, Disabled}, state) {
		return ErrInvalid
	}
	s.RouteStates[printer] = state
	return nil
}

// ReconcileProof is deliberately not a production RPC: the caller's assertion
// cannot establish physical drain/fencing. Physical activation is still held.
func (s *State) ReconcileProof(a Authority, jobID, actor, reason string, at int64) error {
	if !a.Admin || a.VenueID != s.VenueID {
		return ErrScope
	}
	if !id(actor) || !label(reason) || at <= 0 {
		return ErrInvalid
	}
	r, ok := s.Jobs[jobID]
	if !ok || (r.State != Uncertain && r.State != Failed) {
		return ErrHeld
	}
	r.Resolution = &Reprint{OriginalID: jobID, ActorID: actor, Reason: reason, At: at}
	r.State = Reconciled
	return nil
}

// Validate is used on every persisted projection and snapshot restore.
func (s *State) Validate() error {
	if s == nil || s.Version != 1 || !id(s.VenueID) || s.Catalogs == nil || s.Jobs == nil || s.Sequences == nil || s.RouteStates == nil || s.RetiredBefore < 0 || s.pending() > 128 || len(s.Catalogs) > 64 {
		return ErrInvalid
	}
	if s.Current != "" {
		if _, ok := s.Catalogs[s.Current]; !ok {
			return ErrConfig
		}
	}
	for hash, c := range s.Catalogs {
		if c.Validate() != nil || c.VenueID != s.VenueID || c.Digest() != hash {
			return ErrConfig
		}
		if c.Revision > s.Catalogs[s.Current].Revision {
			return ErrConfig
		}
	}
	for printer, state := range s.RouteStates {
		if !id(printer) || !slices.Contains([]RouteState{Available, Offline, Unreachable, Held, RouteUncertain, Disabled}, state) {
			return ErrInvalid
		}
		known := false
		for _, c := range s.Catalogs {
			if _, ok := c.Printer(printer); ok {
				known = true
			}
		}
		if !known {
			return ErrConfig
		}
	}
	sequences := map[string]bool{}
	attempts := map[string]bool{}
	counts := map[string]uint64{}
	for key, r := range s.Jobs {
		if r == nil || r.Job.Validate() != nil || key != r.Job.ID || r.Job.VenueID != s.VenueID || r.Sequence == 0 || r.CommitIndex == 0 || r.NextRoute < 0 || len(r.Attempts) > 8 {
			return ErrInvalid
		}
		catalog, ok := s.Catalogs[r.Job.ConfigDigest]
		if !ok {
			return ErrConfig
		}
		station, ok := catalog.Station(r.Job.StationID)
		if !ok || r.NextRoute > len(station.Routes) || (station.Scope == Local && station.OwnerDeviceID != r.Job.SourceDeviceID) {
			return ErrConfig
		}
		seq := fmt.Sprintf("%s/%d", r.Job.StationID, r.Sequence)
		if sequences[seq] || r.Sequence > s.Sequences[r.Job.StationID] {
			return ErrInvalid
		}
		sequences[seq] = true
		counts[r.Job.StationID]++
		if !slices.Contains([]JobState{Queued, Dispatching, Submitted, Uncertain, Failed, Reconciled}, r.State) {
			return ErrInvalid
		}
		for i, x := range r.Attempts {
			if !id(x.ID) || attempts[x.ID] || x.JobID != key || x.Number != i+1 || i >= len(station.Routes) || station.Routes[i] != x.PrinterID || x.StartedAt <= 0 || (x.FinishedAt != 0 && x.FinishedAt < x.StartedAt) {
				return ErrInvalid
			}
			attempts[x.ID] = true
			p, _ := catalog.Printer(x.PrinterID)
			if x.ControllerID != p.ControllerID || !slices.Contains([]Outcome{"", NotSubmitted, AcceptedBytes, Unknown}, x.Outcome) {
				return ErrInvalid
			}
			if i < len(r.Attempts)-1 && x.Outcome != NotSubmitted {
				return ErrInvalid
			}
		}
		if r.State == Queued {
			if r.NextRoute != len(r.Attempts) || r.NextRoute >= len(station.Routes) {
				return ErrInvalid
			}
			if len(r.Attempts) > 0 && r.Attempts[len(r.Attempts)-1].Outcome != NotSubmitted {
				return ErrInvalid
			}
		}
		if r.State == Dispatching || r.State == Submitted || r.State == Uncertain {
			if len(r.Attempts) == 0 || r.NextRoute != len(r.Attempts)-1 {
				return ErrInvalid
			}
			last := r.Attempts[len(r.Attempts)-1]
			want := Outcome("")
			if r.State == Submitted {
				want = AcceptedBytes
			}
			if r.State == Uncertain {
				want = Unknown
			}
			if last.Outcome != want {
				return ErrInvalid
			}
			if r.State == Submitted && last.FinishedAt == 0 {
				return ErrInvalid
			}
		}
		if r.State == Failed && (r.NextRoute != len(station.Routes) || len(r.Attempts) != len(station.Routes)) {
			return ErrInvalid
		}
		if r.State == Failed && r.Attempts[len(r.Attempts)-1].Outcome != NotSubmitted {
			return ErrInvalid
		}
		if (r.State == Reconciled) != (r.Resolution != nil) {
			return ErrInvalid
		}
		if r.Resolution != nil {
			x := r.Resolution
			if x.OriginalID != key || !id(x.ActorID) || !label(x.Reason) || x.At <= 0 || len(r.Attempts) == 0 {
				return ErrInvalid
			}
			last := r.Attempts[len(r.Attempts)-1]
			if last.Outcome != Unknown && last.Outcome != NotSubmitted {
				return ErrInvalid
			}
		}
		if r.Job.Reprint != nil {
			old, ok := s.Jobs[r.Job.Reprint.OriginalID]
			if !ok || old == nil || old.Job.StationID != r.Job.StationID || old.Job.BusinessRef != r.Job.BusinessRef || old.Job.PayloadDigest != r.Job.PayloadDigest {
				return ErrInvalid
			}
		}
	}
	for station, n := range s.Sequences {
		if n == 0 || counts[station] > n {
			return ErrInvalid
		}
	}
	return nil
}
