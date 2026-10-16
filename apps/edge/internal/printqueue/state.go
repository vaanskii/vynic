package printqueue

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"vynic.local/edge/internal/printtransport"
)

var ErrNoWork = errors.New("printer has no queued work")

func (s *Store) claim(ctx context.Context, physicalID, workerID string) (FrozenJob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.fenced {
		return FrozenJob{}, ErrBusy
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return FrozenJob{}, err
	}
	defer tx.Rollback()
	var raw []byte
	var phase string
	err = tx.QueryRowContext(ctx, "SELECT envelope,phase FROM pq_job WHERE physical_id=? AND phase!='complete' ORDER BY sequence LIMIT 1", physicalID).Scan(&raw, &phase)
	if errors.Is(err, sql.ErrNoRows) {
		return FrozenJob{}, ErrNoWork
	}
	if err != nil {
		return FrozenJob{}, err
	}
	if phase != "queued" {
		return FrozenJob{}, ErrBusy
	}
	j, err := DecodeFrozenJob(raw)
	if err != nil {
		return FrozenJob{}, err
	}
	// Revalidate the captured registry before STARTED; never rewrite a frozen
	// destination if a database/config was altered while a job was queued.
	r, err := readRegistry(ctx, tx, physicalID)
	if err != nil {
		return FrozenJob{}, err
	}
	d := j.Destination
	d.DocumentName = ""
	if r.Destination != d || r.BindingRevision != j.BindingRevision || r.ConfigRevision != j.ConfigRevision || r.RegistryRevision != j.RegistryRevision || r.VenueID != j.VenueID || r.InstallationID != j.InstallationID || r.AuthorityEpoch != j.AuthorityEpoch || r.DeviceID != j.DeviceID || !contains(r.Aliases, j.AliasID) {
		return FrozenJob{}, ErrBinding
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO pq_claim(physical_id,job_id,worker_id,state) VALUES(?,?,?,'running')", physicalID, j.JobID, workerID); err != nil {
		return FrozenJob{}, fmt.Errorf("%w: %v", ErrBusy, err)
	}
	if _, err = tx.ExecContext(ctx, "UPDATE pq_job SET primary_state='started',phase='primary' WHERE job_id=?", j.JobID); err != nil {
		return FrozenJob{}, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO pq_attempt(attempt_id,job_id,state) VALUES(?,?,'started')", j.AttemptID, j.JobID); err != nil {
		return FrozenJob{}, err
	}
	if err = tx.Commit(); err != nil {
		return FrozenJob{}, err
	}
	return j, nil
}

func normalizeResult(result printtransport.Result, length int) printtransport.Result {
	if result.State != printtransport.NotSent && result.State != printtransport.Submitted && result.State != printtransport.Uncertain || result.State == printtransport.NotSent && (result.WriteAttempted || result.BytesWritten != 0 || result.JobID != 0) || result.State == printtransport.Submitted && (result.BytesWritten != uint32(length) || !result.WriteAttempted) || result.BytesWritten > uint32(length) || len(result.Stage) > 256 || len(result.Detail) > 4096 {
		return printtransport.Result{State: printtransport.Uncertain, Stage: "invalid transport result", Detail: "transport result did not establish a safe disposition", WriteAttempted: true}
	}
	return result
}

func (s *Store) settlePrimary(ctx context.Context, j FrozenJob, result printtransport.Result) error {
	result = normalizeResult(result, len(j.PrimaryBytes))
	raw, err := json.Marshal(result)
	if err != nil {
		return err
	}
	phase := "complete"
	if result.State == printtransport.Submitted {
		phase = "beep"
	}
	if result.State == printtransport.Uncertain {
		phase = "hold"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, "UPDATE pq_attempt SET state=?,result=? WHERE attempt_id=?", result.State, raw, j.AttemptID); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "UPDATE pq_job SET primary_state=?,primary_result=?,phase=? WHERE job_id=?", result.State, raw, phase, j.JobID); err != nil {
		return err
	}
	if result.State == printtransport.Uncertain {
		if _, err = tx.ExecContext(ctx, "UPDATE pq_claim SET state='hold' WHERE job_id=?", j.JobID); err != nil {
			return err
		}
	}
	if result.State != printtransport.Submitted {
		skip, _ := json.Marshal(printtransport.Result{State: printtransport.NotSent, Stage: "beep skipped", Detail: "primary was not accepted"})
		if _, err = tx.ExecContext(ctx, "UPDATE pq_beep SET state='skipped',result=? WHERE job_id=?", skip, j.JobID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) reserveBeep(ctx context.Context, j FrozenJob) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var primary string
	if err = tx.QueryRowContext(ctx, "SELECT primary_state FROM pq_job WHERE job_id=?", j.JobID).Scan(&primary); err != nil {
		return err
	}
	if primary != "submitted" {
		return ErrBusy
	}
	if _, err = tx.ExecContext(ctx, "UPDATE pq_beep SET state='reserved' WHERE job_id=?", j.JobID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) settleBeep(ctx context.Context, j FrozenJob, state BeepState, result printtransport.Result) error {
	raw, err := json.Marshal(result)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err = s.db.ExecContext(ctx, "UPDATE pq_beep SET state=?,result=? WHERE job_id=?", state, raw, j.JobID)
	return err
}

func (s *Store) complete(ctx context.Context, j FrozenJob) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var state PrimaryState
	var phase string
	if err = tx.QueryRowContext(ctx, "SELECT primary_state,phase FROM pq_job WHERE job_id=?", j.JobID).Scan(&state, &phase); err != nil {
		return err
	}
	if phase == "hold" {
		return ErrBusy
	}
	if state == Submitted && phase == "beep" {
		if _, err = tx.ExecContext(ctx, "UPDATE pq_job SET phase='complete' WHERE job_id=?", j.JobID); err != nil {
			return err
		}
	}
	if _, err = tx.ExecContext(ctx, "DELETE FROM pq_claim WHERE job_id=?", j.JobID); err != nil {
		return err
	}
	return tx.Commit()
}

// recover runs only after the scheduler owns the database-specific exclusive
// worker process lock. It establishes no fencing for another host or a copied
// database. STARTED is always uncertain; there is no automatic primary replay.
func (s *Store) recover(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, "SELECT envelope,primary_state,phase FROM pq_job WHERE phase IN ('primary','beep') OR (phase='complete' AND EXISTS(SELECT 1 FROM pq_claim WHERE pq_claim.job_id=pq_job.job_id)) ORDER BY physical_id,sequence")
	if err != nil {
		return err
	}
	type pending struct {
		job   FrozenJob
		state PrimaryState
		phase string
	}
	var jobs []pending
	for rows.Next() {
		var p pending
		var raw []byte
		if err = rows.Scan(&raw, &p.state, &p.phase); err != nil {
			rows.Close()
			return err
		}
		p.job, err = DecodeFrozenJob(raw)
		if err != nil {
			rows.Close()
			return err
		}
		jobs = append(jobs, p)
	}
	err = rows.Err()
	closeErr := rows.Close()
	if err = errors.Join(err, closeErr); err != nil {
		return err
	}
	for _, p := range jobs {
		j := p.job
		if p.state == Started {
			result, _ := json.Marshal(printtransport.Result{State: printtransport.Uncertain, Stage: "restart", Detail: "durable STARTED has no confirmed settlement", WriteAttempted: true})
			if _, err = tx.ExecContext(ctx, "UPDATE pq_attempt SET state='uncertain',result=? WHERE attempt_id=?", result, j.AttemptID); err != nil {
				return err
			}
			if _, err = tx.ExecContext(ctx, "UPDATE pq_job SET primary_state='uncertain',primary_result=?,phase='hold' WHERE job_id=?", result, j.JobID); err != nil {
				return err
			}
			if _, err = tx.ExecContext(ctx, "UPDATE pq_claim SET state='hold' WHERE job_id=?", j.JobID); err != nil {
				return err
			}
			skip, _ := json.Marshal(printtransport.Result{State: printtransport.NotSent, Stage: "beep skipped", Detail: "primary uncertain after restart"})
			if _, err = tx.ExecContext(ctx, "UPDATE pq_beep SET state='skipped',result=? WHERE job_id=?", skip, j.JobID); err != nil {
				return err
			}
		} else {
			var beep BeepState
			if err = tx.QueryRowContext(ctx, "SELECT state FROM pq_beep WHERE job_id=?", j.JobID).Scan(&beep); err != nil {
				return err
			}
			if beep == BeepPending || beep == BeepReserved {
				state := BeepSkipped
				transportState := printtransport.NotSent
				if beep == BeepReserved {
					state = BeepUncertain
					transportState = printtransport.Uncertain
				}
				result, _ := json.Marshal(printtransport.Result{State: transportState, Stage: "restart", Detail: "optional beep is never replayed", WriteAttempted: beep == BeepReserved})
				if _, err = tx.ExecContext(ctx, "UPDATE pq_beep SET state=?,result=? WHERE job_id=?", state, result, j.JobID); err != nil {
					return err
				}
			}
			if p.phase == "beep" {
				if _, err = tx.ExecContext(ctx, "UPDATE pq_job SET phase='complete' WHERE job_id=?", j.JobID); err != nil {
					return err
				}
			}
			if _, err = tx.ExecContext(ctx, "DELETE FROM pq_claim WHERE job_id=?", j.JobID); err != nil {
				return err
			}
		}
	}
	return tx.Commit()
}
