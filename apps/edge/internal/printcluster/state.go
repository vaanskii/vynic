package printcluster

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"reflect"
	"sort"
	"strings"

	"github.com/hashicorp/raft"
	"vynic.local/edge/internal/printstation"
)

type chunkMeta struct {
	StationMetadata *printstation.Job `json:"stationMetadata,omitempty"`
	StationJob      bool              `json:"stationJob,omitempty"`
	RequestID       string            `json:"requestId"`
	JobID           string            `json:"jobId"`
	EffectID        string            `json:"effectId"`
	Digest          string            `json:"digest"`
	TotalBytes      int               `json:"totalBytes"`
	TotalChunks     int               `json:"totalChunks"`
	Caller          Caller            `json:"caller"`
	ReprintReason   string            `json:"reprintReason"`
}

func (m chunkMeta) valid(pin ClusterConfig) bool {
	if m.StationMetadata != nil {
		j := m.StationMetadata
		if !m.StationJob || j.Payload != nil || j.ID != m.JobID || j.ID != m.EffectID || !hash(j.PayloadDigest) {
			return false
		}
	}
	return uuid(m.RequestID) && uuid(m.JobID) && uuid(m.EffectID) && hash(m.Digest) && m.TotalBytes > 0 && m.TotalBytes <= MaxEnvelopeBytes && m.TotalChunks == (m.TotalBytes+ChunkBytes-1)/ChunkBytes && pin.authorize(m.Caller, false) && (m.ReprintReason == "" || text(m.ReprintReason, 512))
}
func (m chunkMeta) chunkLength(i int) int {
	if i < 0 || i >= m.TotalChunks {
		return 0
	}
	if i == m.TotalChunks-1 {
		return m.TotalBytes - i*ChunkBytes
	}
	return ChunkBytes
}

type requestRecord struct {
	Meta        chunkMeta      `json:"meta"`
	ChunkHashes map[int]string `json:"chunkHashes"`
	Receipt     *Receipt       `json:"receipt"`
	Rejection   string         `json:"rejection"`
}
type stagedJob struct {
	Chunks map[int][]byte `json:"chunks"`
}
type storedJob struct {
	Raw               []byte      `json:"raw"`
	PhysicalPrinterID string      `json:"physicalPrinterId"`
	Receipt           Receipt     `json:"receipt"`
	State             string      `json:"state"`
	PrimaryState      string      `json:"primaryState"`
	BeepState         string      `json:"beepState"`
	Assignment        *Assignment `json:"assignment"`
}
type auditRecord struct {
	Index        uint64 `json:"index"`
	Kind         string `json:"kind"`
	JobID        string `json:"jobId"`
	ReprintOf    string `json:"reprintOf"`
	Actor        Caller `json:"actor"`
	Reason       string `json:"reason"`
	ConfigDigest string `json:"configDigest,omitempty"`
}
type membershipRecord struct {
	Address string `json:"address"`
	Role    string `json:"role"`
}
type projection struct {
	ProductionGrant      []byte                      `json:"productionGrant,omitempty"`
	SnapshotBlobs        map[string][]byte           `json:"snapshotBlobs,omitempty"`
	Stations             *printstation.State         `json:"stations,omitempty"`
	Version              uint32                      `json:"version"`
	Pin                  ClusterConfig               `json:"pin"`
	AppliedIndex         uint64                      `json:"appliedIndex"`
	Term                 uint64                      `json:"term"`
	MembershipGeneration uint64                      `json:"membershipGeneration"`
	Members              map[string]membershipRecord `json:"members"`
	Configs              map[string][]byte           `json:"configs"`
	CurrentConfigs       map[string]string           `json:"currentConfigs"`
	Requests             map[string]*requestRecord   `json:"requests"`
	Stages               map[string]*stagedJob       `json:"stages"`
	Jobs                 map[string]*storedJob       `json:"jobs"`
	Effects              map[string]string           `json:"effects"`
	NextSequence         map[string]uint64           `json:"nextSequence"`
	Attempts             map[string]Assignment       `json:"attempts"`
	Audit                []auditRecord               `json:"audit"`
}

func initial(pin ClusterConfig) *projection {
	return &projection{Version: 2, Pin: pin, Members: map[string]membershipRecord{}, Configs: map[string][]byte{}, CurrentConfigs: map[string]string{}, Requests: map[string]*requestRecord{}, Stages: map[string]*stagedJob{}, Jobs: map[string]*storedJob{}, Effects: map[string]string{}, NextSequence: map[string]uint64{}, Attempts: map[string]Assignment{}, Audit: []auditRecord{}}
}
func canonicalPin(c ClusterConfig) ClusterConfig {
	c.Peers = append([]Peer(nil), c.Peers...)
	sort.Slice(c.Peers, func(i, j int) bool { return c.Peers[i].ID < c.Peers[j].ID })
	return c
}
func pinDigest(c ClusterConfig) string {
	if c.Version == 2 {
		c.Peers = nil
		c.Voters = 0
	}
	b, _ := json.Marshal(canonicalPin(c))
	return sha(b)
}

type command struct {
	Station              *stationCommand `json:"station,omitempty"`
	Version              uint32          `json:"version"`
	Op                   string          `json:"op"`
	Caller               Caller          `json:"caller"`
	Raw                  []byte          `json:"raw,omitempty"`
	Meta                 *chunkMeta      `json:"meta,omitempty"`
	ChunkIndex           int             `json:"chunkIndex,omitempty"`
	Chunk                []byte          `json:"chunk,omitempty"`
	JobID                string          `json:"jobId,omitempty"`
	AttemptID            string          `json:"attemptId,omitempty"`
	ExecutorID           string          `json:"executorId,omitempty"`
	Assignment           *Assignment     `json:"assignment,omitempty"`
	Reason               string          `json:"reason,omitempty"`
	MembershipGeneration uint64          `json:"membershipGeneration"`
	LeaderID             string          `json:"leaderId"`
}
type result struct {
	StationRecord  *printstation.Record
	StationAttempt *printstation.Attempt
	Receipt        *Receipt
	Assignment     *Assignment
	ConfigDigest   string
	Err            error
}

// Every state transition, including interruption and optional beep state, is
// a committed FSM transition. No replica independently "recovers" a print.
func (s *projection) advanceTerm(term uint64) {
	if term <= s.Term {
		return
	}
	s.Term = term
	if s.Stations != nil {
		s.Stations.Interrupt()
	}
	for _, j := range s.Jobs {
		if j.Assignment == nil || j.Assignment.LeaderTerm >= term {
			continue
		}
		switch j.State {
		case "ASSIGNED":
			j.State = "ACCEPTED"
			j.Assignment = nil
		case "DISPATCHING":
			j.State = "UNCERTAIN"
			j.PrimaryState = "UNCERTAIN"
		}
		if j.BeepState == "STARTED" {
			j.BeepState = "UNCERTAIN"
		} else if j.State == "PRIMARY_SUBMITTED" && j.BeepState == "NOT_STARTED" {
			j.BeepState = "SKIPPED"
		}
	}
}
func (s *projection) apply(c command, index, term uint64) result {
	if c.Version == 2 && c.Op == "productionConfig" {
		return s.productionConfig(c)
	}
	if c.Version != 2 || !s.Pin.authorize(c.Caller, false) {
		return result{Err: ErrScope}
	}
	s.advanceTerm(term)
	if c.Op == "sync" {
		return result{}
	}
	if c.MembershipGeneration != s.MembershipGeneration {
		return result{Err: ErrMembership}
	}
	switch c.Op {
	case "station":
		return s.applyStation(c, index)
	case "config":
		return s.installConfig(c, index)
	case "chunk":
		return s.stage(c)
	case "finalize":
		return s.finalize(c, index)
	case "claim":
		return s.claim(c, index, term)
	case "primaryStarted", "primarySubmitted", "beepStarted", "beepSubmitted", "beepUncertain", "beepSkipped", "uncertain":
		return s.transition(c, index, term)
	case "resolveNotPrinted":
		return s.resolve(c, index)
	default:
		return result{Err: ErrInvalid}
	}
}
func endpoint(c ConfigSnapshot) string {
	var d struct {
		Kind, Host, QueueName, OwnerDeviceID string
		Port                                 uint16
	}
	_ = json.Unmarshal(c.Destination, &d)
	if d.Kind == "tcp" {
		h := strings.TrimSuffix(strings.ToLower(d.Host), ".")
		if ip := net.ParseIP(h); ip != nil {
			h = ip.String()
		}
		return fmt.Sprintf("tcp/%s/%d", h, d.Port)
	}
	return "windowsSpooler/" + d.OwnerDeviceID + "/" + strings.ToLower(d.QueueName)
}
func (s *projection) installConfig(cmd command, index uint64) result {
	if s.Stations != nil && s.Stations.Current != "" {
		return result{Err: ErrConfig}
	}
	if !s.Pin.authorize(cmd.Caller, true) {
		return result{Err: ErrScope}
	}
	c, e := DecodeConfig(cmd.Raw)
	if e != nil {
		return result{Err: e}
	}
	if !c.bound(s.Pin) {
		return result{Err: ErrScope}
	}
	if raw, ok := s.Configs[c.digest]; ok {
		if !bytes.Equal(raw, c.raw) {
			return result{Err: ErrReuse}
		}
		return result{ConfigDigest: c.digest}
	}
	if len(s.Configs) >= 256 {
		return result{Err: ErrCapacity}
	}
	for _, raw := range s.Configs {
		old, _ := DecodeConfig(raw)
		if endpoint(c) == endpoint(old) && c.PhysicalPrinterID != old.PhysicalPrinterID {
			return result{Err: ErrConfig}
		}
		if c.RouteID == old.RouteID && c.PhysicalPrinterID != old.PhysicalPrinterID {
			return result{Err: ErrConfig}
		}
		if c.RouteID == old.RouteID && c.ConfigRevision == old.ConfigRevision {
			return result{Err: ErrReuse}
		}
	}
	if h, ok := s.CurrentConfigs[c.RouteID]; ok {
		old, _ := DecodeConfig(s.Configs[h])
		if c.ConfigRevision <= old.ConfigRevision || c.RouteRevision < old.RouteRevision || c.Ownership.Generation < old.Ownership.Generation {
			return result{Err: ErrConfig}
		}
		if !samePhysicalBinding(c, old) && s.hasUnfinished(c.PhysicalPrinterID) {
			return result{Err: ErrBusy}
		}
	}
	for route, h := range s.CurrentConfigs {
		if route == c.RouteID {
			continue
		}
		old, _ := DecodeConfig(s.Configs[h])
		if old.PhysicalPrinterID == c.PhysicalPrinterID && !samePhysicalBinding(c, old) {
			return result{Err: ErrConfig}
		}
	}
	s.Configs[c.digest] = bytes.Clone(c.raw)
	s.CurrentConfigs[c.RouteID] = c.digest
	s.Audit = append(s.Audit, auditRecord{Index: index, Kind: "CONFIG_FROZEN", Actor: cmd.Caller, ConfigDigest: c.digest})
	return result{ConfigDigest: c.digest}
}
func samePhysicalBinding(a, b ConfigSnapshot) bool {
	return endpoint(a) == endpoint(b) && a.Ownership == b.Ownership && equalJSON(a.Destination, b.Destination)
}
func (s *projection) hasUnfinished(physical string) bool { return s.head(physical) != "" }
func (s *projection) stage(c command) result {
	if c.Meta == nil || !c.Meta.valid(s.Pin) || c.Caller != c.Meta.Caller || c.ChunkIndex < 0 || c.ChunkIndex >= c.Meta.TotalChunks || len(c.Chunk) != c.Meta.chunkLength(c.ChunkIndex) {
		return result{Err: ErrInvalid}
	}
	m := *c.Meta
	r, known := s.Requests[m.RequestID]
	if known {
		if !reflect.DeepEqual(r.Meta, m) {
			return result{Err: ErrReuse}
		}
		if h, ok := r.ChunkHashes[c.ChunkIndex]; ok && h != sha(c.Chunk) {
			return result{Err: ErrReuse}
		}
		if r.Receipt != nil {
			return result{Receipt: r.Receipt}
		}
		if r.Rejection != "" {
			return result{Err: rejection(r.Rejection)}
		}
	} else {
		if s.pendingRequests() >= 256 || len(s.Stages) >= MaxStagedJobs {
			return result{Err: ErrCapacity}
		}
		total := m.TotalBytes
		for id := range s.Stages {
			total += s.Requests[id].Meta.TotalBytes
		}
		if total > MaxStagedBytes {
			return result{Err: ErrCapacity}
		}
		r = &requestRecord{Meta: m, ChunkHashes: map[int]string{}}
		s.Requests[m.RequestID] = r
		s.Stages[m.RequestID] = &stagedJob{Chunks: map[int][]byte{}}
	}
	st := s.Stages[m.RequestID]
	if st == nil {
		return result{Err: ErrStorage}
	}
	if old, ok := st.Chunks[c.ChunkIndex]; ok {
		if !bytes.Equal(old, c.Chunk) {
			return result{Err: ErrReuse}
		}
		return result{}
	}
	st.Chunks[c.ChunkIndex] = bytes.Clone(c.Chunk)
	r.ChunkHashes[c.ChunkIndex] = sha(c.Chunk)
	return result{}
}
func rejection(code string) error {
	switch code {
	case "config":
		return ErrConfig
	case "scope":
		return ErrScope
	case "reuse":
		return ErrReuse
	case "capacity":
		return ErrCapacity
	case "renderer":
		return ErrRenderer
	default:
		return ErrInvalid
	}
}
func code(err error) string {
	switch err {
	case ErrConfig:
		return "config"
	case ErrScope:
		return "scope"
	case ErrReuse:
		return "reuse"
	case ErrCapacity:
		return "capacity"
	case ErrRenderer:
		return "renderer"
	default:
		return "invalid"
	}
}
func (s *projection) finalize(c command, index uint64) result {
	if c.Meta == nil || !c.Meta.valid(s.Pin) || c.Meta.Caller != c.Caller {
		return result{Err: ErrInvalid}
	}
	r, ok := s.Requests[c.Meta.RequestID]
	if !ok {
		return result{Err: ErrInvalid}
	}
	if !reflect.DeepEqual(r.Meta, *c.Meta) {
		return result{Err: ErrReuse}
	}
	if r.Receipt != nil {
		return result{Receipt: r.Receipt}
	}
	if r.Rejection != "" {
		return result{Err: rejection(r.Rejection)}
	}
	st := s.Stages[r.Meta.RequestID]
	if st == nil || len(st.Chunks) != r.Meta.TotalChunks {
		return result{Err: ErrInvalid}
	}
	raw := make([]byte, 0, r.Meta.TotalBytes)
	for i := 0; i < r.Meta.TotalChunks; i++ {
		b, ok := st.Chunks[i]
		if !ok {
			return result{Err: ErrInvalid}
		}
		raw = append(raw, b...)
	}
	reject := func(e error) result { r.Rejection = code(e); delete(s.Stages, r.Meta.RequestID); return result{Err: e} }
	want := r.Meta.Digest
	if r.Meta.StationMetadata != nil {
		want = r.Meta.StationMetadata.PayloadDigest
	}
	if sha(raw) != want {
		return reject(ErrInvalid)
	}
	if r.Meta.StationJob {
		return s.finalizeStation(c, r, raw, index, reject)
	}
	j, e := DecodeJob(raw)
	if e != nil {
		return reject(e)
	}
	if s.Stations != nil {
		if _, exists := s.Stations.Jobs[j.JobID]; exists {
			return reject(ErrReuse)
		}
	}
	if j.RequestID != r.Meta.RequestID || j.JobID != r.Meta.JobID || j.EffectID != r.Meta.EffectID {
		return reject(ErrReuse)
	}
	if !j.bound(s.Pin, c.Caller) {
		return reject(ErrScope)
	}
	confRaw, ok := s.Configs[j.ConfigSHA256]
	if !ok {
		return reject(ErrConfig)
	}
	conf, _ := DecodeConfig(confRaw)
	if !j.matches(conf) {
		return reject(ErrConfig)
	}
	if existing, ok := s.Jobs[j.JobID]; ok {
		if bytes.Equal(existing.Raw, raw) {
			r.Receipt = &existing.Receipt
			delete(s.Stages, j.RequestID)
			return result{Receipt: r.Receipt}
		}
		return reject(ErrReuse)
	}
	if _, ok := s.Effects[j.EffectID]; ok {
		return reject(ErrReuse)
	}
	if s.CurrentConfigs[j.RouteID] != j.ConfigSHA256 {
		return reject(ErrConfig)
	}
	if len(s.Jobs) >= MaxJobs {
		return reject(ErrCapacity)
	}
	if j.ReprintOf != nil {
		if !s.Pin.authorize(c.Caller, true) || !text(r.Meta.ReprintReason, 512) {
			return reject(ErrScope)
		}
		original, ok := s.Jobs[*j.ReprintOf]
		if !ok || original == nil {
			return reject(ErrInvalid)
		}
		old, _ := DecodeJob(original.Raw)
		if j.PhysicalPrinterID != old.PhysicalPrinterID || j.RouteID != old.RouteID || j.ConfigSHA256 != old.ConfigSHA256 || j.PrimarySHA256 != old.PrimarySHA256 || !bytes.Equal(j.PrimaryBytes, old.PrimaryBytes) || !j.matches(conf) {
			return reject(ErrConfig)
		}
		s.Audit = append(s.Audit, auditRecord{Index: index, Kind: "MANUAL_REPRINT", JobID: j.JobID, ReprintOf: *j.ReprintOf, Actor: c.Caller, Reason: r.Meta.ReprintReason})
	} else if r.Meta.ReprintReason != "" {
		return reject(ErrInvalid)
	}
	seq := s.NextSequence[j.PhysicalPrinterID] + 1
	s.NextSequence[j.PhysicalPrinterID] = seq
	receipt := Receipt{Status: "ACCEPTED", JobID: j.JobID, InputSHA256: j.digest, Sequence: seq, CommitIndex: index}
	r.Receipt = &receipt
	s.Jobs[j.JobID] = &storedJob{Raw: bytes.Clone(raw), PhysicalPrinterID: j.PhysicalPrinterID, Receipt: receipt, State: "ACCEPTED", PrimaryState: "NOT_STARTED", BeepState: initialBeep(j.CapabilityProfile)}
	s.Effects[j.EffectID] = j.JobID
	delete(s.Stages, j.RequestID)
	return result{Receipt: &receipt}
}
func initialBeep(raw []byte) string {
	var p struct{ Beep json.RawMessage }
	if json.Unmarshal(raw, &p) != nil {
		return "SKIPPED"
	}
	var b struct {
		Capability string `json:"capability"`
		Enabled    bool   `json:"enabled"`
	}
	if strict(p.Beep, 1024, &b) != nil || !keys(p.Beep, []string{"capability", "enabled"}) || b.Capability != "epsonEscA97Pattern" || !b.Enabled {
		return "SKIPPED"
	}
	return "NOT_STARTED"
}
func (s *projection) head(physical string) string {
	id := ""
	var seq uint64
	for key, stored := range s.Jobs {
		if stored == nil {
			continue
		}
		settledBeep := stored.BeepState == "SKIPPED" || stored.BeepState == "SUBMITTED"
		if stored.PhysicalPrinterID != physical || (stored.State == "PRIMARY_SUBMITTED" && settledBeep) || stored.State == "RESOLVED_NOT_PRINTED" {
			continue
		}
		if id == "" || stored.Receipt.Sequence < seq {
			id = key
			seq = stored.Receipt.Sequence
		}
	}
	return id
}
func (s *projection) claim(c command, index, term uint64) result {
	if !uuid(c.JobID) || !uuid(c.AttemptID) || !uuid(c.ExecutorID) {
		return result{Err: ErrInvalid}
	}
	if c.ExecutorID != c.Caller.MemberID || c.ExecutorID != c.LeaderID {
		return result{Err: ErrScope}
	}
	m, ok := s.Members[c.ExecutorID]
	if !ok || m.Role == Client {
		return result{Err: ErrMembership}
	}
	stored, ok := s.Jobs[c.JobID]
	if !ok {
		return result{Err: ErrInvalid}
	}
	j, _ := DecodeJob(stored.Raw)
	conf, _ := DecodeConfig(s.Configs[j.ConfigSHA256])
	p, _ := s.Pin.peer(c.ExecutorID)
	if conf.Ownership.Kind == "device" && conf.Ownership.OwnerID != p.DeviceID {
		return result{Err: ErrAssignment}
	}
	if old, ok := s.Attempts[c.AttemptID]; ok {
		if old.JobID != c.JobID || old.ExecutorMemberID != c.ExecutorID {
			return result{Err: ErrReuse}
		}
		if stored.Assignment == nil || *stored.Assignment != old || old.LeaderTerm != term || old.MembershipGeneration != s.MembershipGeneration {
			return result{Err: ErrAssignment}
		}
		return result{Assignment: &old}
	}
	if len(s.Attempts) >= 512 {
		return result{Err: ErrCapacity}
	}
	if stored.State != "ACCEPTED" || s.head(j.PhysicalPrinterID) != j.JobID {
		return result{Err: ErrBusy}
	}
	a := Assignment{ClusterID: s.Pin.ClusterID, Scope: s.Pin.Scope, JobID: j.JobID, PhysicalPrinterID: j.PhysicalPrinterID, AttemptID: c.AttemptID, ExecutorMemberID: c.ExecutorID, LeaderTerm: term, MembershipGeneration: s.MembershipGeneration, ConfigSHA256: j.ConfigSHA256, PrimarySHA256: j.PrimarySHA256, CommitIndex: index}
	stored.Assignment = &a
	stored.State = "ASSIGNED"
	s.Attempts[a.AttemptID] = a
	return result{Assignment: &a}
}
func (s *projection) transition(c command, index, term uint64) result {
	if c.Assignment == nil {
		return result{Err: ErrAssignment}
	}
	a := *c.Assignment
	stored, ok := s.Jobs[a.JobID]
	if !ok || stored.Assignment == nil || *stored.Assignment != a || a.ExecutorMemberID != c.Caller.MemberID || a.LeaderTerm != term || a.MembershipGeneration != s.MembershipGeneration {
		return result{Err: ErrAssignment}
	}
	switch c.Op {
	case "primaryStarted":
		if stored.State == "DISPATCHING" && stored.PrimaryState == "STARTED" {
			return result{}
		}
		if stored.State != "ASSIGNED" || stored.PrimaryState != "NOT_STARTED" {
			return result{Err: ErrAssignment}
		}
		stored.State = "DISPATCHING"
		stored.PrimaryState = "STARTED"
	case "primarySubmitted":
		if stored.State == "PRIMARY_SUBMITTED" {
			return result{}
		}
		if stored.State != "DISPATCHING" || stored.PrimaryState != "STARTED" {
			return result{Err: ErrAssignment}
		}
		stored.State = "PRIMARY_SUBMITTED"
		stored.PrimaryState = "SUBMITTED"
	case "beepStarted":
		if stored.BeepState == "STARTED" {
			return result{}
		}
		if stored.State != "PRIMARY_SUBMITTED" || stored.BeepState != "NOT_STARTED" {
			return result{Err: ErrAssignment}
		}
		stored.BeepState = "STARTED"
	case "beepSubmitted":
		if stored.BeepState == "SUBMITTED" {
			return result{}
		}
		if stored.State != "PRIMARY_SUBMITTED" || stored.BeepState != "STARTED" {
			return result{Err: ErrAssignment}
		}
		stored.BeepState = "SUBMITTED"
	case "beepSkipped":
		if stored.State != "PRIMARY_SUBMITTED" || stored.BeepState != "NOT_STARTED" {
			return result{Err: ErrAssignment}
		}
		stored.BeepState = "SKIPPED"
	case "beepUncertain":
		if stored.State != "PRIMARY_SUBMITTED" || stored.BeepState != "STARTED" || !text(c.Reason, 512) {
			return result{Err: ErrAssignment}
		}
		stored.BeepState = "UNCERTAIN"
		s.Audit = append(s.Audit, auditRecord{Index: index, Kind: "BEEP_UNCERTAIN", JobID: a.JobID, Actor: c.Caller, Reason: c.Reason})
	case "uncertain":
		if !text(c.Reason, 512) {
			return result{Err: ErrInvalid}
		}
		if stored.State == "UNCERTAIN" {
			return result{}
		}
		if stored.State != "DISPATCHING" {
			return result{Err: ErrAssignment}
		}
		stored.State = "UNCERTAIN"
		stored.PrimaryState = "UNCERTAIN"
		s.Audit = append(s.Audit, auditRecord{Index: index, Kind: "PRIMARY_UNCERTAIN", JobID: a.JobID, Actor: c.Caller, Reason: c.Reason})
	}
	return result{}
}
func (s *projection) resolve(c command, index uint64) result {
	if !s.Pin.authorize(c.Caller, true) || !text(c.Reason, 512) {
		return result{Err: ErrScope}
	}
	j, ok := s.Jobs[c.JobID]
	if !ok || j.State != "UNCERTAIN" {
		return result{Err: ErrBusy}
	}
	j.State = "RESOLVED_NOT_PRINTED"
	s.Audit = append(s.Audit, auditRecord{Index: index, Kind: "OPERATOR_NOT_PRINTED", JobID: c.JobID, Actor: c.Caller, Reason: c.Reason})
	return result{}
}

// Validate the entire bounded snapshot before replacing any live projection.
func validateProjection(s *projection, pin ClusterConfig) error {
	if e := validateProductionJournal(s); e != nil {
		return e
	}
	if pin.Version == 2 {
		if pinDigest(pin) != pinDigest(s.Pin) {
			return ErrMembership
		}
		pin = s.Pin
	}
	if s.Stations != nil && (s.Stations.VenueID != pin.VenueID || s.Stations.Validate() != nil) {
		return ErrInvalid
	}
	if s.SnapshotBlobs != nil || s.Version != 2 || s.Pin.validate() != nil || pinDigest(s.Pin) != pinDigest(pin) || s.AppliedIndex > uint64(1<<63-1) || s.Term > uint64(1<<63-1) || s.MembershipGeneration > s.AppliedIndex || len(s.Configs) > 256 || len(s.Jobs) > MaxJobs || s.pendingRequests() > 256 || len(s.Stages) > MaxStagedJobs || len(s.Attempts) > 512 || len(s.Audit) > 2048 {
		return ErrInvalid
	}
	if s.Members == nil || s.Configs == nil || s.CurrentConfigs == nil || s.Requests == nil || s.Stages == nil || s.Jobs == nil || s.Effects == nil || s.NextSequence == nil || s.Attempts == nil {
		return ErrInvalid
	}
	decodedJobs := map[string]Job{}
	for id, st := range s.Jobs {
		if st == nil {
			return ErrInvalid
		}
		j, e := DecodeJob(st.Raw)
		if e != nil || j.JobID != id || st.PhysicalPrinterID != j.PhysicalPrinterID {
			return ErrInvalid
		}
		decodedJobs[id] = j
	}
	voters := 0
	for id, m := range s.Members {
		p, ok := pin.peer(id)
		if !ok || (p.Role != m.Role && !(pin.Version == 2 && p.Role == Voter && m.Role == Nonvoter)) || p.Address != m.Address || p.Role == Client || !p.FullData {
			return ErrMembership
		}
		if m.Role == Voter {
			voters++
		}
	}
	if s.MembershipGeneration > 0 && ((pin.Version != 2 && voters != pin.Voters) || (pin.Version == 2 && (voters < 1 || voters > pin.Voters))) {
		return ErrMembership
	}
	endpointIDs, routeIDs := map[string]string{}, map[string]string{}
	latest := map[string]ConfigSnapshot{}
	revisions := map[string]bool{}
	for h, raw := range s.Configs {
		c, e := DecodeConfig(raw)
		if e != nil || !c.bound(pin) || c.digest != h {
			return ErrConfig
		}
		if id, ok := endpointIDs[endpoint(c)]; ok && id != c.PhysicalPrinterID {
			return ErrConfig
		}
		endpointIDs[endpoint(c)] = c.PhysicalPrinterID
		if id, ok := routeIDs[c.RouteID]; ok && id != c.PhysicalPrinterID {
			return ErrConfig
		}
		routeIDs[c.RouteID] = c.PhysicalPrinterID
		key := fmt.Sprintf("%s/%d", c.RouteID, c.ConfigRevision)
		if revisions[key] {
			return ErrConfig
		}
		revisions[key] = true
		if old, ok := latest[c.RouteID]; !ok || c.ConfigRevision > old.ConfigRevision {
			latest[c.RouteID] = c
		}
	}
	for route, h := range s.CurrentConfigs {
		c, e := DecodeConfig(s.Configs[h])
		if e != nil || c.RouteID != route || latest[route].digest != h {
			return ErrConfig
		}
	}
	activeBindings := map[string]ConfigSnapshot{}
	for _, h := range s.CurrentConfigs {
		c, _ := DecodeConfig(s.Configs[h])
		if old, ok := activeBindings[c.PhysicalPrinterID]; ok && !samePhysicalBinding(c, old) {
			return ErrConfig
		}
		activeBindings[c.PhysicalPrinterID] = c
	}
	if len(s.CurrentConfigs) != len(latest) {
		return ErrConfig
	}
	total := 0
	for id, r := range s.Requests {
		if r == nil || !r.Meta.valid(pin) || id != r.Meta.RequestID || r.ChunkHashes == nil || (r.Receipt != nil && r.Rejection != "") {
			return ErrInvalid
		}
		for i, h := range r.ChunkHashes {
			if r.Meta.chunkLength(i) == 0 || !hash(h) {
				return ErrInvalid
			}
		}
		if r.Receipt != nil {
			if r.Meta.StationJob {
				if s.Stations == nil {
					return ErrInvalid
				}
				row, ok := s.Stations.Jobs[r.Meta.JobID]
				if !ok || row == nil || row.CommitIndex > s.AppliedIndex {
					return ErrInvalid
				}
				raw := printstation.Encode(row.Job)
				if r.Meta.StationMetadata != nil {
					header := row.Job
					header.Payload = nil
					if !reflect.DeepEqual(header, *r.Meta.StationMetadata) {
						return ErrInvalid
					}
					raw = row.Job.Payload
				}
				if stationReceipt(row) != *r.Receipt || r.Receipt.InputSHA256 != r.Meta.Digest || len(raw) != r.Meta.TotalBytes || len(r.ChunkHashes) != r.Meta.TotalChunks {
					return ErrInvalid
				}
				for i := 0; i < r.Meta.TotalChunks; i++ {
					if sha(raw[i*ChunkBytes:i*ChunkBytes+r.Meta.chunkLength(i)]) != r.ChunkHashes[i] {
						return ErrInvalid
					}
				}
				continue
			}
			j, ok := s.Jobs[r.Meta.JobID]
			if !ok || j == nil || j.Receipt != *r.Receipt || j.Receipt.InputSHA256 != r.Meta.Digest {
				return ErrInvalid
			}
			if len(r.ChunkHashes) != r.Meta.TotalChunks || len(j.Raw) != r.Meta.TotalBytes {
				return ErrInvalid
			}
			for i := 0; i < r.Meta.TotalChunks; i++ {
				if sha(j.Raw[i*ChunkBytes:i*ChunkBytes+r.Meta.chunkLength(i)]) != r.ChunkHashes[i] {
					return ErrInvalid
				}
			}
		}
		if r.Receipt == nil && r.Rejection == "" {
			st, ok := s.Stages[id]
			if !ok || st == nil || st.Chunks == nil {
				return ErrInvalid
			}
			total += r.Meta.TotalBytes
			for i, b := range st.Chunks {
				if len(b) != r.Meta.chunkLength(i) || sha(b) != r.ChunkHashes[i] {
					return ErrInvalid
				}
			}
		}
	}
	if total > MaxStagedBytes {
		return ErrCapacity
	}
	for id := range s.Stages {
		r, ok := s.Requests[id]
		if !ok || r.Receipt != nil || r.Rejection != "" {
			return ErrInvalid
		}
	}
	seenSeq := map[string]bool{}
	counts := map[string]uint64{}
	for id, st := range s.Jobs {
		if st == nil {
			return ErrInvalid
		}
		j := decodedJobs[id]
		r, exists := s.Requests[j.RequestID]
		if j.JobID != id || !exists || r == nil || !j.bound(pin, r.Meta.Caller) {
			return ErrInvalid
		}
		conf, e := DecodeConfig(s.Configs[j.ConfigSHA256])
		if e != nil || !j.matches(conf) {
			return ErrConfig
		}
		if r.Receipt == nil || *r.Receipt != st.Receipt || r.Meta.JobID != j.JobID || r.Meta.EffectID != j.EffectID || r.Meta.Digest != j.digest || r.Meta.TotalBytes != len(j.raw) || st.Receipt.Status != "ACCEPTED" || st.Receipt.JobID != id || st.Receipt.InputSHA256 != j.digest || !revision(st.Receipt.CommitIndex) || st.Receipt.CommitIndex > s.AppliedIndex || !revision(st.Receipt.Sequence) || st.Receipt.Sequence > s.NextSequence[j.PhysicalPrinterID] || s.Effects[j.EffectID] != id {
			return ErrInvalid
		}
		seq := fmt.Sprintf("%s/%d", j.PhysicalPrinterID, st.Receipt.Sequence)
		if seenSeq[seq] {
			return ErrInvalid
		}
		seenSeq[seq] = true
		counts[j.PhysicalPrinterID]++
		switch st.State {
		case "ACCEPTED", "ASSIGNED", "DISPATCHING", "UNCERTAIN", "PRIMARY_SUBMITTED", "RESOLVED_NOT_PRINTED":
		default:
			return ErrInvalid
		}
		switch st.PrimaryState {
		case "NOT_STARTED", "STARTED", "SUBMITTED", "UNCERTAIN":
		default:
			return ErrInvalid
		}
		switch st.BeepState {
		case "SKIPPED", "NOT_STARTED", "STARTED", "SUBMITTED", "UNCERTAIN":
		default:
			return ErrInvalid
		}
		if a := st.Assignment; a != nil {
			if !validAssignment(*a, j, pin) || s.Attempts[a.AttemptID] != *a || a.LeaderTerm > s.Term || a.MembershipGeneration > s.MembershipGeneration {
				return ErrInvalid
			}
		}
		if st.State == "ACCEPTED" {
			if st.Assignment != nil || st.PrimaryState != "NOT_STARTED" {
				return ErrInvalid
			}
		} else if st.Assignment == nil {
			return ErrInvalid
		}
		switch st.State {
		case "ASSIGNED":
			if st.PrimaryState != "NOT_STARTED" {
				return ErrInvalid
			}
		case "DISPATCHING":
			if st.PrimaryState != "STARTED" {
				return ErrInvalid
			}
		case "UNCERTAIN", "RESOLVED_NOT_PRINTED":
			if st.PrimaryState != "UNCERTAIN" {
				return ErrInvalid
			}
		case "PRIMARY_SUBMITTED":
			if st.PrimaryState != "SUBMITTED" {
				return ErrInvalid
			}
		}
		if st.State != "PRIMARY_SUBMITTED" && st.BeepState != initialBeep(j.CapabilityProfile) {
			return ErrInvalid
		}
		if initialBeep(j.CapabilityProfile) == "SKIPPED" && st.BeepState != "SKIPPED" {
			return ErrInvalid
		}
		if (st.State == "ASSIGNED" || st.State == "DISPATCHING" || st.State == "UNCERTAIN") && s.head(j.PhysicalPrinterID) != j.JobID {
			return ErrInvalid
		}
	}
	for id, a := range s.Attempts {
		j, ok := decodedJobs[a.JobID]
		if !ok || id != a.AttemptID {
			return ErrInvalid
		}
		if !validAssignment(a, j, pin) || a.CommitIndex > s.AppliedIndex {
			return ErrInvalid
		}
	}
	for id, job := range s.Effects {
		v, ok := decodedJobs[job]
		if !ok {
			return ErrInvalid
		}
		if v.EffectID != id {
			return ErrInvalid
		}
	}
	for id, n := range s.NextSequence {
		if !uuid(id) || !revision(n) || counts[id] != n {
			return ErrInvalid
		}
	}
	configAudit, reprintAudit := map[string]bool{}, map[string]bool{}
	for _, a := range s.Audit {
		if !revision(a.Index) || a.Index > s.AppliedIndex || !pin.authorize(a.Actor, false) {
			return ErrInvalid
		}
		switch a.Kind {
		case "CONFIG_FROZEN", "MANUAL_REPRINT", "OPERATOR_NOT_PRINTED":
			if !pin.authorize(a.Actor, true) {
				return ErrInvalid
			}
			if a.Kind == "CONFIG_FROZEN" {
				if _, ok := s.Configs[a.ConfigDigest]; !ok || configAudit[a.ConfigDigest] {
					return ErrInvalid
				}
				configAudit[a.ConfigDigest] = true
			}
			if a.Kind == "MANUAL_REPRINT" {
				st, ok := s.Jobs[a.JobID]
				if !ok || st == nil {
					return ErrInvalid
				}
				j := decodedJobs[a.JobID]
				r := s.Requests[j.RequestID]
				if j.ReprintOf == nil || *j.ReprintOf != a.ReprintOf || r.Meta.ReprintReason != a.Reason || r.Meta.Caller != a.Actor || a.Index != st.Receipt.CommitIndex || reprintAudit[a.JobID] {
					return ErrInvalid
				}
				reprintAudit[a.JobID] = true
			}
		case "PRIMARY_UNCERTAIN", "BEEP_UNCERTAIN":
			if !pin.authorize(a.Actor, false) {
				return ErrInvalid
			}
		default:
			return ErrInvalid
		}
	}
	if len(configAudit) != len(s.Configs) {
		return ErrInvalid
	}
	for id, j := range decodedJobs {
		if j.ReprintOf != nil && !reprintAudit[id] {
			return ErrInvalid
		}
	}
	return nil
}
func validAssignment(a Assignment, j Job, pin ClusterConfig) bool {
	p, ok := pin.peer(a.ExecutorMemberID)
	return ok && p.Role != Client && a.ClusterID == j.ClusterID && a.Scope == j.Scope && a.JobID == j.JobID && a.PhysicalPrinterID == j.PhysicalPrinterID && uuid(a.AttemptID) && revision(a.LeaderTerm) && revision(a.MembershipGeneration) && revision(a.CommitIndex) && a.ConfigSHA256 == j.ConfigSHA256 && a.PrimarySHA256 == j.PrimarySHA256
}
func membersFromRaft(pin ClusterConfig, c raft.Configuration) (map[string]membershipRecord, error) {
	m := map[string]membershipRecord{}
	voters := 0
	for _, s := range c.Servers {
		id := string(s.ID)
		p, ok := pin.peer(id)
		if !ok || !p.FullData || p.Address != string(s.Address) || m[id].Address != "" {
			return nil, ErrMembership
		}
		role := Nonvoter
		if s.Suffrage == raft.Voter {
			role = Voter
			voters++
		} else if s.Suffrage != raft.Nonvoter {
			return nil, ErrMembership
		}
		if p.Role != role && !(pin.Version == 2 && p.Role == Voter && role == Nonvoter) {
			return nil, ErrMembership
		}
		m[id] = membershipRecord{Address: p.Address, Role: role}
	}
	if (pin.Version != 2 && voters != pin.Voters) || (pin.Version == 2 && (voters < 1 || voters > pin.Voters)) {
		return nil, ErrMembership
	}
	return m, nil
}

// Terminal station receipts are bounded by the storage byte budget and the
// replicated retention floor. Incomplete/rejected requests retain their own
// admission cap; legacy physical-envelope limits are unchanged.
func (s *projection) pendingRequests() int {
	n := 0
	for _, r := range s.Requests {
		if r == nil || !r.Meta.StationJob || r.Receipt == nil {
			n++
		}
	}
	return n
}
