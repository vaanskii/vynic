package printqueue

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"sync"

	"vynic.local/edge/internal/printtransport"
)

const MaxPendingPerPrinter = 256
const MaxRetainedJobs = 4096
const MaxJournalBytes = 128 << 20

// Reserve room for all three bounded primary/attempt/beep results before I/O.
const settlementReservationBytes = 32768

type GatewayIdentity struct {
	VenueID        string
	InstallationID string
	DeviceID       string
	WorkerHostID   string
	Epoch          uint64
}

type Store struct {
	db       *sql.DB
	identity GatewayIdentity
	mu       sync.Mutex
	fenced   bool
}

// NewProofStore is deliberately isolated. The caller owns the database's
// exclusive installation/process lock and exact migration attestation. It
// never creates/upgrades a database or enables a production sender.
func NewProofStore(ctx context.Context, db *sql.DB, identity GatewayIdentity) (*Store, error) {
	// Connection-local FULL/FK settings must govern every queue transaction.
	if db.Stats().MaxOpenConnections != 1 {
		return nil, ErrSchema
	}
	for _, id := range []string{identity.VenueID, identity.InstallationID, identity.DeviceID, identity.WorkerHostID} {
		if !CanonicalUUID(id) {
			return nil, ErrScope
		}
	}
	if !boundedRevision(identity.Epoch) {
		return nil, ErrScope
	}
	var version, synchronous, foreignKeys int
	var journal string
	if err := db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return nil, err
	}
	if err := db.QueryRowContext(ctx, "PRAGMA synchronous").Scan(&synchronous); err != nil {
		return nil, err
	}
	if err := db.QueryRowContext(ctx, "PRAGMA foreign_keys").Scan(&foreignKeys); err != nil {
		return nil, err
	}
	if err := db.QueryRowContext(ctx, "PRAGMA journal_mode").Scan(&journal); err != nil {
		return nil, err
	}
	if version != 6 || synchronous != 2 || foreignKeys != 1 || journal != "wal" {
		return nil, ErrSchema
	}
	var count int
	if err := db.QueryRowContext(ctx, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('pq_registry','pq_alias','pq_job','pq_receipt','pq_claim','pq_attempt','pq_beep')").Scan(&count); err != nil {
		return nil, err
	}
	if count != 7 {
		return nil, ErrSchema
	}
	if err := db.QueryRowContext(ctx, "SELECT count(*) FROM pq_registry WHERE venue_id!=? OR installation_id!=? OR epoch!=? OR device_id!=? OR worker_host_id!=?", identity.VenueID, identity.InstallationID, identity.Epoch, identity.DeviceID, identity.WorkerHostID).Scan(&count); err != nil {
		return nil, err
	}
	if count != 0 {
		return nil, ErrScope
	}
	return &Store{db: db, identity: identity}, nil
}

func readRegistry(ctx context.Context, tx *sql.Tx, physicalID string) (Registry, error) {
	var r Registry
	var raw []byte
	err := tx.QueryRowContext(ctx, "SELECT physical_id,venue_id,installation_id,epoch,device_id,worker_host_id,binding_revision,config_revision,registry_revision,destination FROM pq_registry WHERE physical_id=?", physicalID).Scan(&r.PhysicalPrinterID, &r.VenueID, &r.InstallationID, &r.AuthorityEpoch, &r.DeviceID, &r.WorkerHostID, &r.BindingRevision, &r.ConfigRevision, &r.RegistryRevision, &raw)
	if err != nil {
		return r, err
	}
	if err = json.Unmarshal(raw, &r.Destination); err != nil {
		return r, err
	}
	rows, err := tx.QueryContext(ctx, "SELECT alias_id FROM pq_alias WHERE physical_id=? ORDER BY alias_id", physicalID)
	if err != nil {
		return r, err
	}
	defer rows.Close()
	for rows.Next() {
		var alias string
		if err = rows.Scan(&alias); err != nil {
			return r, err
		}
		r.Aliases = append(r.Aliases, alias)
	}
	return r, rows.Err()
}

func (s *Store) Register(ctx context.Context, r Registry) error {
	if err := r.validate(); err != nil {
		return err
	}
	i := s.identity
	if r.VenueID != i.VenueID || r.InstallationID != i.InstallationID || r.AuthorityEpoch != i.Epoch || r.DeviceID != i.DeviceID || r.WorkerHostID != i.WorkerHostID {
		return ErrScope
	}
	r.Aliases = append([]string(nil), r.Aliases...)
	sort.Strings(r.Aliases)
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.fenced {
		return ErrBusy
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	old, err := readRegistry(ctx, tx, r.PhysicalPrinterID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	newRow := errors.Is(err, sql.ErrNoRows)
	if !newRow {
		a, _ := json.Marshal(old)
		b, _ := json.Marshal(r)
		if bytes.Equal(a, b) {
			return tx.Commit()
		}
		if old.VenueID != r.VenueID || old.InstallationID != r.InstallationID || old.AuthorityEpoch != r.AuthorityEpoch || old.DeviceID != r.DeviceID || old.WorkerHostID != r.WorkerHostID {
			return ErrScope
		}
		if r.RegistryRevision != old.RegistryRevision+1 || r.ConfigRevision < old.ConfigRevision || r.BindingRevision < old.BindingRevision {
			return ErrBinding
		}
		var busy int
		if err = tx.QueryRowContext(ctx, "SELECT count(*) FROM pq_job WHERE physical_id=? AND phase!='complete'", r.PhysicalPrinterID).Scan(&busy); err != nil {
			return err
		}
		if busy != 0 {
			return ErrBusy
		}
		for _, alias := range old.Aliases {
			if !contains(r.Aliases, alias) {
				return ErrBinding
			}
		}
	}
	var owner string
	err = tx.QueryRowContext(ctx, "SELECT physical_id FROM pq_registry WHERE endpoint_key=?", endpointKey(r.Destination)).Scan(&owner)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if err == nil && owner != r.PhysicalPrinterID {
		return ErrBinding
	}
	for _, alias := range r.Aliases {
		err = tx.QueryRowContext(ctx, "SELECT physical_id FROM pq_alias WHERE alias_id=?", alias).Scan(&owner)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		if err == nil && owner != r.PhysicalPrinterID {
			return ErrBinding
		}
	}
	destination, err := json.Marshal(r.Destination)
	if err != nil {
		return err
	}
	if newRow {
		_, err = tx.ExecContext(ctx, "INSERT INTO pq_registry(physical_id,venue_id,installation_id,epoch,device_id,worker_host_id,binding_revision,config_revision,registry_revision,destination,endpoint_key) VALUES(?,?,?,?,?,?,?,?,?,?,?)", r.PhysicalPrinterID, r.VenueID, r.InstallationID, r.AuthorityEpoch, r.DeviceID, r.WorkerHostID, r.BindingRevision, r.ConfigRevision, r.RegistryRevision, destination, endpointKey(r.Destination))
	} else {
		_, err = tx.ExecContext(ctx, "UPDATE pq_registry SET binding_revision=?,config_revision=?,registry_revision=?,destination=?,endpoint_key=? WHERE physical_id=?", r.BindingRevision, r.ConfigRevision, r.RegistryRevision, destination, endpointKey(r.Destination), r.PhysicalPrinterID)
	}
	if err != nil {
		return err
	}
	for _, alias := range r.Aliases {
		if _, err = tx.ExecContext(ctx, "INSERT INTO pq_alias(alias_id,physical_id) VALUES(?,?) ON CONFLICT(alias_id) DO NOTHING", alias, r.PhysicalPrinterID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func contains(values []string, target string) bool {
	for _, v := range values {
		if v == target {
			return true
		}
	}
	return false
}

// AdmitTx is the canonical local atomic hook. The matching typed PRINT must
// already exist inside this same transaction. Any unsupported/mismatched
// payload rejects the whole commit; there is no post-commit enqueue fallback.
// Remote relays instead call Store.Accept after independent authentication of
// the committed effect. This package performs no network/authentication work.
func AdmitTx(ctx context.Context, tx *sql.Tx, a Authority, j FrozenJob) (Receipt, error) {
	frozen, err := j.fresh()
	if err != nil {
		return Receipt{}, err
	}
	var kind, request string
	var payload []byte
	if err = tx.QueryRowContext(ctx, "SELECT kind,request_id,payload FROM op_effect WHERE id=?", frozen.EffectID).Scan(&kind, &request, &payload); err != nil {
		return Receipt{}, fmt.Errorf("%w: missing canonical PRINT: %v", ErrInvalid, err)
	}
	if kind != "PRINT" || request != frozen.RequestID || !bytes.Equal(payload, frozen.raw) {
		return Receipt{}, ErrInvalid
	}
	return admit(ctx, tx, a, frozen)
}

// Accept provides the idempotent owner protocol seam for authenticated relays.
// It returns the original immutable admission receipt on an exact retry. The
// current outcome is independently queried; a lost ACK never creates a job.
func (s *Store) Accept(ctx context.Context, a Authority, j FrozenJob) (Receipt, error) {
	if a.VenueID != s.identity.VenueID || a.InstallationID != s.identity.InstallationID || a.Epoch != s.identity.Epoch {
		return Receipt{}, ErrScope
	}
	frozen, err := j.fresh()
	if err != nil {
		return Receipt{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.fenced {
		return Receipt{}, ErrBusy
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Receipt{}, err
	}
	defer tx.Rollback()
	r, err := admit(ctx, tx, a, frozen)
	if err != nil {
		return Receipt{}, err
	}
	if err = tx.Commit(); err != nil {
		return Receipt{}, err
	}
	return r, nil
}

func admit(ctx context.Context, tx *sql.Tx, a Authority, j FrozenJob) (Receipt, error) {
	if !a.matches(j) {
		return Receipt{}, ErrScope
	}
	var id, digest string
	var receiptRaw []byte
	err := tx.QueryRowContext(ctx, "SELECT j.job_id,j.digest,r.receipt FROM pq_job j JOIN pq_receipt r ON r.job_id=j.job_id WHERE j.job_id=? OR j.effect_id=? OR j.attempt_id=?", j.JobID, j.EffectID, j.AttemptID).Scan(&id, &digest, &receiptRaw)
	if err == nil {
		if id != j.JobID || digest != j.digest {
			return Receipt{}, ErrReuse
		}
		var receipt Receipt
		if err = json.Unmarshal(receiptRaw, &receipt); err != nil {
			return Receipt{}, err
		}
		return receipt, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return Receipt{}, err
	}
	r, err := readRegistry(ctx, tx, j.PhysicalPrinterID)
	if errors.Is(err, sql.ErrNoRows) {
		return Receipt{}, ErrBinding
	}
	if err != nil {
		return Receipt{}, err
	}
	if r.VenueID != j.VenueID || r.InstallationID != j.InstallationID || r.AuthorityEpoch != j.AuthorityEpoch || r.DeviceID != j.DeviceID || r.BindingRevision != j.BindingRevision || r.ConfigRevision != j.ConfigRevision || r.RegistryRevision != j.RegistryRevision || !contains(r.Aliases, j.AliasID) {
		return Receipt{}, ErrBinding
	}
	d := j.Destination
	d.DocumentName = ""
	if d != r.Destination {
		return Receipt{}, ErrBinding
	}
	var count int
	if err = tx.QueryRowContext(ctx, "SELECT count(*) FROM pq_job WHERE physical_id=? AND phase!='complete'", j.PhysicalPrinterID).Scan(&count); err != nil {
		return Receipt{}, err
	}
	if count >= MaxPendingPerPrinter {
		return Receipt{}, ErrCapacity
	}
	var jobs, journal int64
	if err = tx.QueryRowContext(ctx, "SELECT count(*),coalesce(sum(length(envelope)+?),0) FROM pq_job", settlementReservationBytes).Scan(&jobs, &journal); err != nil {
		return Receipt{}, err
	}
	if jobs >= MaxRetainedJobs || journal > MaxJournalBytes-int64(len(j.raw))-settlementReservationBytes {
		return Receipt{}, ErrCapacity
	}
	var sequence uint64
	if err = tx.QueryRowContext(ctx, "SELECT next_sequence FROM pq_registry WHERE physical_id=?", j.PhysicalPrinterID).Scan(&sequence); err != nil {
		return Receipt{}, err
	}
	if sequence >= math.MaxInt64 {
		return Receipt{}, ErrCapacity
	}
	if _, err = tx.ExecContext(ctx, "UPDATE pq_registry SET next_sequence=next_sequence+1 WHERE physical_id=?", j.PhysicalPrinterID); err != nil {
		return Receipt{}, err
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO pq_job(job_id,effect_id,request_id,terminal_id,origin_installation_id,physical_id,alias_id,sequence,digest,envelope,attempt_id,primary_state,phase) VALUES(?,?,?,?,?,?,?,?,?,?,?,'queued','queued')", j.JobID, j.EffectID, j.RequestID, j.TerminalID, j.OriginInstallationID, j.PhysicalPrinterID, j.AliasID, sequence, j.digest, j.raw, j.AttemptID)
	if err != nil {
		return Receipt{}, fmt.Errorf("%w: %v", ErrReuse, err)
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO pq_beep(job_id,attempt_id,state) VALUES(?,?,'pending')", j.JobID, j.BeepAttemptID); err != nil {
		return Receipt{}, fmt.Errorf("%w: %v", ErrReuse, err)
	}
	receipt := Receipt{Version: 1, JobID: j.JobID, EffectID: j.EffectID, PhysicalPrinterID: j.PhysicalPrinterID, Sequence: sequence, AdmissionSHA256: j.digest}
	receiptRaw, err = json.Marshal(receipt)
	if err != nil {
		return Receipt{}, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO pq_receipt(job_id,receipt) VALUES(?,?)", j.JobID, receiptRaw); err != nil {
		return Receipt{}, err
	}
	return receipt, nil
}

func (s *Store) Outcome(ctx context.Context, jobID string) (Outcome, error) {
	var o Outcome
	var receipt, primary, beep []byte
	err := s.db.QueryRowContext(ctx, "SELECT r.receipt,j.primary_state,j.primary_result,j.phase,b.state,b.result FROM pq_job j JOIN pq_receipt r ON r.job_id=j.job_id JOIN pq_beep b ON b.job_id=j.job_id WHERE j.job_id=?", jobID).Scan(&receipt, &o.Primary, &primary, &o.Phase, &o.Beep, &beep)
	if err != nil {
		return o, err
	}
	if err = json.Unmarshal(receipt, &o.Receipt); err != nil {
		return o, err
	}
	if primary != nil {
		o.PrimaryResult = &printtransport.Result{}
		if err = json.Unmarshal(primary, o.PrimaryResult); err != nil {
			return o, err
		}
	}
	if beep != nil {
		o.BeepResult = &printtransport.Result{}
		if err = json.Unmarshal(beep, o.BeepResult); err != nil {
			return o, err
		}
	}
	return o, nil
}

// BlockedReason also includes durable unresolved evidence after native exit.
func (s *Store) BlockedReason(ctx context.Context) (string, error) {
	var count int
	if err := s.db.QueryRowContext(ctx, "SELECT count(*) FROM pq_claim").Scan(&count); err != nil {
		return "", err
	}
	if count != 0 {
		return "printer submission or uncertainty is retained", nil
	}
	return "", nil
}

// FenceAdmission waits for an already admitted transaction and prevents new
// relay/config mutations. A business CommitOperationalQueued caller must also
// fence its transaction entrance; the standalone AdmitTx hook owns no host.
func (s *Store) FenceAdmission() { s.mu.Lock(); s.fenced = true; s.mu.Unlock() }

// PrinterBlockedReason is scoped to execution, not venue admission health.
// Other printers and new frozen admissions continue during a held head.
func (s *Store) PrinterBlockedReason(ctx context.Context, physicalID string) (string, error) {
	if !CanonicalUUID(physicalID) {
		return "", ErrInvalid
	}
	var state string
	err := s.db.QueryRowContext(ctx, "SELECT state FROM pq_claim WHERE physical_id=?", physicalID).Scan(&state)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if state == "hold" {
		return "printer holds uncertain submission", nil
	}
	return "printer owns an active submission", nil
}
