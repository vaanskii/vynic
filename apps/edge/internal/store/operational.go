package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"math"

	"vynic.local/edge/internal/printqueue"
)

// These are deliberate isolated proof bounds, not a production sizing claim.
// A 12 MiB frozen effect accommodates an 8 MiB raster encoded in a PrintJob;
// the full encoded request must still fit 16 MiB. Tombstones, conflict results,
// events and frozen effects all consume retained capacity. There is no pruning.
const (
	OperationalMaxRequestBytes     = 16 << 20
	OperationalMaxDocumentBytes    = 1 << 20
	OperationalMaxEffectBytes      = 12 << 20
	OperationalMaxApplicationBytes = 1 << 20
	OperationalMaxEventBytes       = 18 << 20
	OperationalMaxResultBytes      = 48 << 20
	OperationalMaxSnapshotBytes    = 48 << 20
	OperationalMaxReplayBytes      = 32 << 20
	OperationalMaxStateBytes       = 32 << 20
	OperationalMaxJournalBytes     = 128 << 20
	OperationalMaxEntities         = 2048
	OperationalMaxRequests         = 10000
	OperationalMaxEvents           = 10000
	OperationalMaxEffects          = 20000
	OperationalMaxWrites           = 128
	OperationalMaxReads            = 256
	OperationalMaxRequestEffects   = 128
	OperationalMaxReplayEvents     = 100
	OperationalPrintAdmission      = "vynic-print-queue.v1"
)

type OperationalEntityKind string

const (
	OperationalOrder       OperationalEntityKind = "ORDER"
	OperationalTable       OperationalEntityKind = "TABLE"
	OperationalReservation OperationalEntityKind = "RESERVATION"
	OperationalPackage     OperationalEntityKind = "PACKAGE"
	OperationalSale        OperationalEntityKind = "SALE"
	OperationalDay         OperationalEntityKind = "DAY"
	OperationalControl     OperationalEntityKind = "OPERATIONAL_CONTROL"
	OperationalAuditReport OperationalEntityKind = "AUDIT_REPORT"
	OperationalClosure     OperationalEntityKind = "CLOSURE"
	OperationalAdvance     OperationalEntityKind = "ADVANCE"
	OperationalExpense     OperationalEntityKind = "EXPENSE"
	OperationalStaff       OperationalEntityKind = "STAFF"
	OperationalPolicy      OperationalEntityKind = "OPERATIONAL_POLICY"
)

type OperationalEntity struct {
	Kind      OperationalEntityKind `json:"kind"`
	ID        string                `json:"id"`
	Revision  uint64                `json:"revision"`
	Tombstone bool                  `json:"tombstone"`
	Document  []byte                `json:"document"`
}

// Revision 0 with Tombstone false means absence, not a retained deletion.
// Read dependencies fence decisions based on entities that are not being written.
type OperationalRead struct {
	Kind              OperationalEntityKind `json:"kind"`
	ID                string                `json:"id"`
	ExpectedRevision  uint64                `json:"expectedRevision"`
	ExpectedTombstone bool                  `json:"expectedTombstone"`
}

// Document is a complete JSON object postimage, never a patch. The store does
// not implement restaurant pricing, permission, lifecycle or linkage rules.
// Proof callers must supply the complete read set and their domain validation.
type OperationalWrite struct {
	Kind             OperationalEntityKind `json:"kind"`
	ID               string                `json:"id"`
	ExpectedRevision uint64                `json:"expectedRevision"`
	Tombstone        bool                  `json:"tombstone"`
	Document         []byte                `json:"document"`
}

type OperationalEffectKind string

const (
	OperationalAudit OperationalEffectKind = "AUDIT"
	OperationalPrint OperationalEffectKind = "PRINT"
)

// Payload is the frozen audit record or print job, including the print target
// and rendered bytes. The foundation never regenerates or dispatches it.
type OperationalEffect struct {
	ID      string                `json:"id"`
	Kind    OperationalEffectKind `json:"kind"`
	Payload []byte                `json:"payload"`
}

type OperationalCommit struct {
	Auth                 OperationalAuth     `json:"-"`
	RequestID            string              `json:"requestId"`
	AuthorityEpoch       uint64              `json:"authorityEpoch"`
	Reads                []OperationalRead   `json:"reads"`
	Writes               []OperationalWrite  `json:"writes"`
	Effects              []OperationalEffect `json:"effects"`
	ApplicationData      []byte              `json:"applicationData"`
	PrintAdmission       string              `json:"printAdmission,omitempty"`
	OriginInstallationID string              `json:"originInstallationId,omitempty"`
}

type OperationalOutcome string

const (
	OperationalCommitted OperationalOutcome = "COMMITTED"
	OperationalConflict  OperationalOutcome = "CONFLICT"
)

type OperationalEvent struct {
	Mode                 string               `json:"mode"`
	AuthorityEpoch       uint64               `json:"authorityEpoch"`
	Sequence             uint64               `json:"sequence"`
	RequestID            string               `json:"requestId"`
	TerminalID           string               `json:"terminalId"`
	Entities             []OperationalEntity  `json:"entities"`
	Effects              []OperationalEffect  `json:"effects"`
	PrintAdmission       string               `json:"printAdmission,omitempty"`
	OriginInstallationID string               `json:"originInstallationId,omitempty"`
	PrintReceipts        []printqueue.Receipt `json:"printReceipts,omitempty"`
}

// All outcome, identity, epoch, sequence and revision fields are store-owned.
// ApplicationData is merely opaque caller data on a successful commit; it
// cannot override the canonical result and is included in the immutable digest.
// Current contains the complete read/write preimages on a persisted conflict.
type OperationalCommitResult struct {
	Mode                 string              `json:"mode"`
	RequestID            string              `json:"requestId"`
	TerminalID           string              `json:"terminalId"`
	Outcome              OperationalOutcome  `json:"outcome"`
	AuthorityEpoch       uint64              `json:"authorityEpoch"`
	HeadSequence         uint64              `json:"headSequence"`
	Event                *OperationalEvent   `json:"event,omitempty"`
	Current              []OperationalEntity `json:"current,omitempty"`
	ApplicationData      []byte              `json:"applicationData,omitempty"`
	PrintAdmission       string              `json:"printAdmission,omitempty"`
	OriginInstallationID string              `json:"originInstallationId,omitempty"`
}

type OperationalSnapshot struct {
	Mode           string              `json:"mode"`
	InstallationID string              `json:"installationId"`
	VenueID        string              `json:"venueId"`
	AuthorityEpoch uint64              `json:"authorityEpoch"`
	Sequence       uint64              `json:"sequence"`
	Entities       []OperationalEntity `json:"entities"`
}

type OperationalReplayPage struct {
	Mode           string             `json:"mode"`
	AuthorityEpoch uint64             `json:"authorityEpoch"`
	HeadSequence   uint64             `json:"headSequence"`
	AfterSequence  uint64             `json:"afterSequence"`
	NextSequence   uint64             `json:"nextSequence"`
	Events         []OperationalEvent `json:"events"`
}

type operationalKey struct {
	kind OperationalEntityKind
	id   string
}

func operationalKind(kind OperationalEntityKind) bool {
	switch kind {
	case OperationalOrder, OperationalTable, OperationalReservation, OperationalPackage, OperationalSale, OperationalDay,
		OperationalControl, OperationalAuditReport, OperationalClosure, OperationalAdvance, OperationalExpense, OperationalStaff, OperationalPolicy:
		return true
	}
	return false
}

func validateOperationalCommit(r *OperationalCommit) error {
	if len(r.Writes) == 0 || len(r.Writes) > OperationalMaxWrites || len(r.Reads) > OperationalMaxReads || len(r.Effects) > OperationalMaxRequestEffects || len(r.ApplicationData) > OperationalMaxApplicationBytes {
		return ErrOperationalIntent
	}
	reads := make(map[operationalKey]OperationalRead)
	for _, d := range r.Reads {
		k := operationalKey{d.Kind, d.ID}
		if !operationalKind(d.Kind) || !canonicalUUID(d.ID) || d.ExpectedRevision > math.MaxInt64 || (d.ExpectedRevision == 0 && d.ExpectedTombstone) {
			return ErrOperationalIntent
		}
		if _, exists := reads[k]; exists {
			return ErrOperationalIntent
		}
		reads[k] = d
	}
	writes := make(map[operationalKey]bool)
	for _, w := range r.Writes {
		k := operationalKey{w.Kind, w.ID}
		if !operationalKind(w.Kind) || !canonicalUUID(w.ID) || writes[k] || w.ExpectedRevision >= math.MaxInt64 || len(w.Document) > OperationalMaxDocumentBytes {
			return ErrOperationalIntent
		}
		writes[k] = true
		if read, exists := reads[k]; exists && (read.ExpectedRevision != w.ExpectedRevision || read.ExpectedTombstone) {
			return ErrOperationalIntent
		}
		if w.Tombstone {
			// Creating an absent tombstone would retire an identity without a
			// previously committed entity; this proof only deletes live entities.
			if w.ExpectedRevision == 0 || len(w.Document) != 0 {
				return ErrOperationalIntent
			}
		} else {
			var object map[string]json.RawMessage
			if json.Unmarshal(w.Document, &object) != nil || object == nil {
				return ErrOperationalIntent
			}
		}
	}
	effects := make(map[string]bool)
	for _, e := range r.Effects {
		if !canonicalUUID(e.ID) || effects[e.ID] || (e.Kind != OperationalAudit && e.Kind != OperationalPrint) || len(e.Payload) == 0 || len(e.Payload) > OperationalMaxEffectBytes {
			return ErrOperationalIntent
		}
		effects[e.ID] = true
	}
	return nil
}

func operationalEntity(ctx context.Context, tx *sql.Tx, kind OperationalEntityKind, id string) (OperationalEntity, error) {
	e := OperationalEntity{Kind: kind, ID: id, Document: []byte{}}
	err := tx.QueryRowContext(ctx, "SELECT revision,tombstone,document FROM op_entity WHERE kind=? AND id=?", kind, id).Scan(&e.Revision, &e.Tombstone, &e.Document)
	if errors.Is(err, sql.ErrNoRows) {
		return e, nil
	}
	if err == nil && e.Document == nil {
		// SQLite drivers may scan an empty BLOB as nil. Keep the complete
		// retained tombstone image identical to the committed empty bytes.
		e.Document = []byte{}
	}
	return e, err
}

func operationalStoredResult(raw []byte, requestID, terminalID string, epoch, head uint64, outcome OperationalOutcome, sequence sql.NullInt64) (*OperationalCommitResult, error) {
	var result OperationalCommitResult
	if len(raw) > OperationalMaxResultBytes || json.Unmarshal(raw, &result) != nil || result.Mode != OperationalProofMode || result.RequestID != requestID || result.TerminalID != terminalID || result.AuthorityEpoch != epoch || result.HeadSequence > head || result.Outcome != outcome || !operationalMetadata(result.PrintAdmission, result.OriginInstallationID) {
		return nil, ErrOperationalCorrupt
	}
	switch result.Outcome {
	case OperationalCommitted:
		if !sequence.Valid || sequence.Int64 <= 0 || result.Event == nil || result.Event.Sequence != uint64(sequence.Int64) || result.HeadSequence != uint64(sequence.Int64) || result.Event.AuthorityEpoch != epoch || result.Event.RequestID != requestID || result.Event.TerminalID != terminalID || result.Event.Mode != OperationalProofMode || result.Event.PrintAdmission != result.PrintAdmission || result.Event.OriginInstallationID != result.OriginInstallationID || !operationalEventMetadata(result.Event) || len(result.Current) != 0 {
			return nil, ErrOperationalCorrupt
		}
	case OperationalConflict:
		if sequence.Valid || result.Event != nil || len(result.Current) == 0 || len(result.ApplicationData) != 0 {
			return nil, ErrOperationalCorrupt
		}
	default:
		return nil, ErrOperationalCorrupt
	}
	return &result, nil
}

// CommitOperational is an isolated store primitive, deliberately unattached to
// the normal server. Callers cannot elect/advance authority or dispatch effects.
// Envelope bounds and authentication precede lookup; the immutable request
// digest is checked before any new revision/schema/capacity validation. Both
// successful and conflicted results survive subsequent edits, lost ACKs/restart.
func (s *Store) CommitOperational(ctx context.Context, r *OperationalCommit) (*OperationalCommitResult, error) {
	if r == nil || r.PrintAdmission != "" || r.OriginInstallationID != "" {
		return nil, ErrOperationalIntent
	}
	return s.commitOperational(ctx, r, false)
}

// CommitOperationalQueued is an explicit isolated fixture capability. Every
// PRINT must be a strict versioned envelope admitted in the same transaction
// as all postimages, frozen effects, queue receipts and the canonical outcome.
// It provides no production planner/dispatch capability. The registered origin
// is authenticated again inside the transaction, including exact ACK retries.
func (s *Store) CommitOperationalQueued(ctx context.Context, r *OperationalCommit) (*OperationalCommitResult, error) {
	if r == nil || r.PrintAdmission != OperationalPrintAdmission || !canonicalUUID(r.OriginInstallationID) || r.OriginInstallationID != r.Auth.OriginInstallationID || len(r.Auth.ClientCASHA256) != sha256.Size {
		return nil, ErrOperationalIntent
	}
	return s.commitOperational(ctx, r, true)
}

func (s *Store) commitOperational(ctx context.Context, r *OperationalCommit, queued bool) (*OperationalCommitResult, error) {
	if !canonicalUUID(r.RequestID) {
		return nil, ErrOperationalIntent
	}
	if !canonicalUUID(r.Auth.TerminalID) || !ValidSecret(r.Auth.TerminalSecret) {
		return nil, ErrDenied
	}
	raw, err := json.Marshal(r)
	if err != nil || len(raw) > OperationalMaxRequestBytes {
		return nil, ErrOperationalIntent
	}
	digest := sha256.Sum256(raw)
	// Freeze input bytes before SQLite work; caller slices never become mutable
	// event/effect documents after hashing. Credentials remain memory-only.
	var frozen OperationalCommit
	if err = json.Unmarshal(raw, &frozen); err != nil {
		return nil, ErrOperationalIntent
	}
	frozen.Auth = r.Auth
	frozen.Auth.ClientCASHA256 = bytes.Clone(r.Auth.ClientCASHA256)
	r = &frozen
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	a, err := operationalState(ctx, tx, r.Auth, r.AuthorityEpoch)
	if err != nil {
		return nil, err
	}
	var owner string
	var priorDigest, priorResult []byte
	var priorEpoch uint64
	var priorOutcome OperationalOutcome
	var priorSequence sql.NullInt64
	err = tx.QueryRowContext(ctx, "SELECT terminal_id,authority_epoch,digest,outcome,event_sequence,result FROM op_request WHERE request_id=?", r.RequestID).Scan(&owner, &priorEpoch, &priorDigest, &priorOutcome, &priorSequence, &priorResult)
	if err == nil {
		if owner != r.Auth.TerminalID || priorEpoch != a.epoch || !bytes.Equal(priorDigest, digest[:]) {
			return nil, ErrRequestReuse
		}
		result, e := operationalStoredResult(priorResult, r.RequestID, owner, a.epoch, a.head, priorOutcome, priorSequence)
		if e != nil {
			return nil, e
		}
		if e = tx.Commit(); e != nil {
			return nil, e
		}
		return result, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	if err = validateOperationalCommit(r); err != nil {
		return nil, err
	}
	result := &OperationalCommitResult{Mode: OperationalProofMode, RequestID: r.RequestID, TerminalID: r.Auth.TerminalID, Outcome: OperationalCommitted, AuthorityEpoch: a.epoch, HeadSequence: a.head, PrintAdmission: r.PrintAdmission, OriginInstallationID: r.OriginInstallationID}
	current := make(map[operationalKey]OperationalEntity)
	read := func(kind OperationalEntityKind, id string) (OperationalEntity, error) {
		k := operationalKey{kind, id}
		if e, ok := current[k]; ok {
			return e, nil
		}
		e, eErr := operationalEntity(ctx, tx, kind, id)
		if eErr == nil {
			current[k] = e
			result.Current = append(result.Current, e)
		}
		return e, eErr
	}
	for _, d := range r.Reads {
		e, eErr := read(d.Kind, d.ID)
		if eErr != nil {
			return nil, eErr
		}
		if e.Revision != d.ExpectedRevision || e.Tombstone != d.ExpectedTombstone {
			result.Outcome = OperationalConflict
		}
	}
	for _, w := range r.Writes {
		e, eErr := read(w.Kind, w.ID)
		if eErr != nil {
			return nil, eErr
		}
		if e.Revision != w.ExpectedRevision || e.Tombstone {
			result.Outcome = OperationalConflict
		}
	}
	var eventSequence any
	if result.Outcome == OperationalCommitted {
		if a.head >= math.MaxInt64 {
			return nil, ErrOperationalCapacity
		}
		event := &OperationalEvent{Mode: OperationalProofMode, AuthorityEpoch: a.epoch, Sequence: a.head + 1, RequestID: r.RequestID, TerminalID: r.Auth.TerminalID, Effects: r.Effects, PrintAdmission: r.PrintAdmission, OriginInstallationID: r.OriginInstallationID}
		for _, w := range r.Writes {
			document := w.Document
			if document == nil {
				document = []byte{}
			}
			e := OperationalEntity{Kind: w.Kind, ID: w.ID, Revision: w.ExpectedRevision + 1, Tombstone: w.Tombstone, Document: document}
			if _, err = tx.ExecContext(ctx, "INSERT INTO op_entity(kind,id,revision,tombstone,document) VALUES(?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,tombstone=excluded.tombstone,document=excluded.document", e.Kind, e.ID, e.Revision, e.Tombstone, e.Document); err != nil {
				return nil, err
			}
			event.Entities = append(event.Entities, e)
		}
		// Event/request FKs are deferred until COMMIT. Freeze the canonical
		// effects first so AdmitTx can verify their exact identities and bytes;
		// then serialize the event with its store-owned queue receipts.
		for ordinal, effect := range event.Effects {
			if _, err = tx.ExecContext(ctx, "INSERT INTO op_effect(id,kind,request_id,event_sequence,ordinal,payload) VALUES(?,?,?,?,?,?)", effect.ID, effect.Kind, r.RequestID, event.Sequence, ordinal, effect.Payload); err != nil {
				return nil, err
			}
			if queued && effect.Kind == OperationalPrint {
				job, decodeErr := printqueue.DecodeFrozenJob(effect.Payload)
				if decodeErr != nil {
					return nil, decodeErr
				}
				if job.EffectID != effect.ID || job.RequestID != r.RequestID {
					return nil, printqueue.ErrScope
				}
				receipt, admitErr := printqueue.AdmitTx(ctx, tx, printqueue.Authority{VenueID: a.venueID, InstallationID: a.installationID, OriginInstallationID: r.Auth.OriginInstallationID, TerminalID: r.Auth.TerminalID, Epoch: a.epoch}, job)
				if admitErr != nil {
					return nil, admitErr
				}
				event.PrintReceipts = append(event.PrintReceipts, receipt)
			}
		}
		eventBytes, e := json.Marshal(event)
		if e != nil {
			return nil, e
		}
		if len(eventBytes) > OperationalMaxEventBytes {
			return nil, ErrOperationalCapacity
		}
		if _, err = tx.ExecContext(ctx, "INSERT INTO op_event(sequence,authority_epoch,request_id,terminal_id,event) VALUES(?,?,?,?,?)", event.Sequence, a.epoch, r.RequestID, r.Auth.TerminalID, eventBytes); err != nil {
			return nil, err
		}
		if _, err = tx.ExecContext(ctx, "UPDATE op_authority SET sequence=? WHERE singleton=1", event.Sequence); err != nil {
			return nil, err
		}
		result.Event = event
		result.HeadSequence = event.Sequence
		result.Current = nil
		result.ApplicationData = r.ApplicationData
		eventSequence = event.Sequence
	}
	resultBytes, err := json.Marshal(result)
	if err != nil {
		return nil, err
	}
	if len(resultBytes) > OperationalMaxResultBytes {
		return nil, ErrOperationalCapacity
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO op_request(request_id,terminal_id,authority_epoch,digest,outcome,event_sequence,result) VALUES(?,?,?,?,?,?,?)", r.RequestID, r.Auth.TerminalID, a.epoch, digest[:], result.Outcome, eventSequence, resultBytes); err != nil {
		return nil, err
	}
	if err = operationalCapacity(ctx, tx); err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}

func operationalCapacity(ctx context.Context, tx *sql.Tx) error {
	var entities, documents, requests, results, events, eventBytes, effects, payloads int64
	err := tx.QueryRowContext(ctx, `SELECT
 (SELECT count(*) FROM op_entity), (SELECT COALESCE(sum(length(document)),0) FROM op_entity),
 (SELECT count(*) FROM op_request), (SELECT COALESCE(sum(length(result)),0) FROM op_request),
 (SELECT count(*) FROM op_event), (SELECT COALESCE(sum(length(event)),0) FROM op_event),
 (SELECT count(*) FROM op_effect), (SELECT COALESCE(sum(length(payload)),0) FROM op_effect)`).Scan(&entities, &documents, &requests, &results, &events, &eventBytes, &effects, &payloads)
	if err != nil {
		return err
	}
	if entities > OperationalMaxEntities || documents > OperationalMaxStateBytes || requests > OperationalMaxRequests || events > OperationalMaxEvents || effects > OperationalMaxEffects || results > OperationalMaxJournalBytes || eventBytes > OperationalMaxJournalBytes-results || payloads > OperationalMaxJournalBytes-results-eventBytes {
		return ErrOperationalCapacity
	}
	return nil
}

// OperationalResult returns only the requesting active terminal's exact stored
// result. It does not expose another terminal's result or mutate retry identity.
func (s *Store) OperationalResult(ctx context.Context, auth OperationalAuth, epoch uint64, requestID string) (*OperationalCommitResult, error) {
	if !canonicalUUID(requestID) {
		return nil, ErrOperationalIntent
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	a, err := operationalState(ctx, tx, auth, epoch)
	if err != nil {
		return nil, err
	}
	var raw []byte
	var outcome OperationalOutcome
	var sequence sql.NullInt64
	err = tx.QueryRowContext(ctx, "SELECT outcome,event_sequence,result FROM op_request WHERE request_id=? AND terminal_id=? AND authority_epoch=?", requestID, auth.TerminalID, a.epoch).Scan(&outcome, &sequence, &raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrOperationalResultNotFound
	}
	if err != nil {
		return nil, err
	}
	result, err := operationalStoredResult(raw, requestID, auth.TerminalID, a.epoch, a.head, outcome, sequence)
	if err != nil {
		return nil, err
	}
	if result.PrintAdmission != "" && result.OriginInstallationID != auth.OriginInstallationID {
		return nil, ErrDenied
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}

// OperationalProjectionSnapshot reads the head and all retained entities from
// one consistent transaction. Capacity bounds make it a complete bounded
// snapshot, avoiding inconsistent pages from separately changing transactions.
func (s *Store) OperationalProjectionSnapshot(ctx context.Context, auth OperationalAuth, epoch uint64) (*OperationalSnapshot, error) {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	a, err := operationalState(ctx, tx, auth, epoch)
	if err != nil {
		return nil, err
	}
	rows, err := tx.QueryContext(ctx, "SELECT kind,id,revision,tombstone,document FROM op_entity ORDER BY kind,id LIMIT ?", OperationalMaxEntities+1)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := &OperationalSnapshot{Mode: OperationalProofMode, InstallationID: a.installationID, VenueID: a.venueID, AuthorityEpoch: a.epoch, Sequence: a.head, Entities: []OperationalEntity{}}
	bytesRead := 0
	for rows.Next() {
		var e OperationalEntity
		if err = rows.Scan(&e.Kind, &e.ID, &e.Revision, &e.Tombstone, &e.Document); err != nil {
			return nil, err
		}
		if e.Document == nil {
			e.Document = []byte{}
		}
		bytesRead += len(e.Document)
		if len(result.Entities) >= OperationalMaxEntities || bytesRead > OperationalMaxStateBytes {
			return nil, ErrOperationalCapacity
		}
		result.Entities = append(result.Entities, e)
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	if err = rows.Close(); err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		return nil, err
	}
	if len(encoded) > OperationalMaxSnapshotBytes {
		return nil, ErrOperationalCapacity
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}

// OperationalReplay returns a contiguous, count/byte bounded page and the head
// from the same transaction. NextSequence is the last returned sequence, so a
// byte-limited page can be resumed without skipping a large frozen print event.
func (s *Store) OperationalReplay(ctx context.Context, auth OperationalAuth, epoch, after uint64, limit uint32) (*OperationalReplayPage, error) {
	if limit == 0 {
		limit = OperationalMaxReplayEvents
	}
	if limit > OperationalMaxReplayEvents || after > math.MaxInt64 {
		return nil, ErrOperationalIntent
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	a, err := operationalState(ctx, tx, auth, epoch)
	if err != nil {
		return nil, err
	}
	if after > a.head {
		return nil, ErrOperationalIntent
	}
	rows, err := tx.QueryContext(ctx, "SELECT sequence,authority_epoch,request_id,terminal_id,event FROM op_event WHERE sequence>? ORDER BY sequence LIMIT ?", after, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := &OperationalReplayPage{Mode: OperationalProofMode, AuthorityEpoch: a.epoch, HeadSequence: a.head, AfterSequence: after, NextSequence: after, Events: []OperationalEvent{}}
	bytesRead := 0
	for rows.Next() {
		var sequence, eventEpoch uint64
		var requestID, terminalID string
		var raw []byte
		if err = rows.Scan(&sequence, &eventEpoch, &requestID, &terminalID, &raw); err != nil {
			return nil, err
		}
		if len(raw) > OperationalMaxEventBytes || sequence != result.NextSequence+1 || sequence > a.head || eventEpoch != a.epoch {
			return nil, ErrOperationalCorrupt
		}
		// Reserve bounded page metadata/commas. Every admitted single event fits.
		if bytesRead+len(raw) > OperationalMaxReplayBytes-4096 {
			break
		}
		var event OperationalEvent
		if json.Unmarshal(raw, &event) != nil || event.Mode != OperationalProofMode || event.Sequence != sequence || event.AuthorityEpoch != eventEpoch || event.RequestID != requestID || event.TerminalID != terminalID || !operationalEventMetadata(&event) {
			return nil, ErrOperationalCorrupt
		}
		result.Events = append(result.Events, event)
		result.NextSequence = sequence
		bytesRead += len(raw)
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	if err = rows.Close(); err != nil {
		return nil, err
	}
	if result.NextSequence < a.head && len(result.Events) == 0 {
		return nil, ErrOperationalCorrupt
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}

func operationalMetadata(admission, origin string) bool {
	return (admission == "" && origin == "") || (admission == OperationalPrintAdmission && canonicalUUID(origin))
}

func operationalEventMetadata(event *OperationalEvent) bool {
	if !operationalMetadata(event.PrintAdmission, event.OriginInstallationID) {
		return false
	}
	if event.PrintAdmission == "" {
		return len(event.PrintReceipts) == 0
	}
	// Admission receipts are part of the immutable canonical event, linked to
	// every frozen PRINT. Historical replay does not consult mutable registry or
	// observer origin and never re-admits or dispatches these effects.
	index := make(map[string]printqueue.Receipt)
	jobs := make(map[string]bool)
	for _, receipt := range event.PrintReceipts {
		if receipt.Version != 1 || !canonicalUUID(receipt.JobID) || !canonicalUUID(receipt.EffectID) || !canonicalUUID(receipt.PhysicalPrinterID) || receipt.Sequence == 0 || receipt.Sequence > math.MaxInt64 || !operationalSHA256(receipt.AdmissionSHA256) || jobs[receipt.JobID] {
			return false
		}
		if _, exists := index[receipt.EffectID]; exists {
			return false
		}
		index[receipt.EffectID] = receipt
		jobs[receipt.JobID] = true
	}
	for _, effect := range event.Effects {
		if effect.Kind != OperationalPrint {
			if _, exists := index[effect.ID]; exists {
				return false
			}
			continue
		}
		job, err := printqueue.DecodeFrozenJob(effect.Payload)
		receipt, exists := index[effect.ID]
		if err != nil || !exists || job.EffectID != effect.ID || job.RequestID != event.RequestID || job.TerminalID != event.TerminalID || job.AuthorityEpoch != event.AuthorityEpoch || job.OriginInstallationID != event.OriginInstallationID || receipt.JobID != job.JobID || receipt.PhysicalPrinterID != job.PhysicalPrinterID || receipt.AdmissionSHA256 != job.Digest() {
			return false
		}
		delete(index, effect.ID)
	}
	return len(index) == 0
}
