package printqueue

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"testing"

	"vynic.local/edge/internal/printtransport"
)

func canonicalEffect(t *testing.T, tx *sql.Tx, j FrozenJob, payload []byte) {
	t.Helper()
	if _, err := tx.Exec("INSERT INTO op_event(sequence,authority_epoch,request_id,terminal_id,event) VALUES(1,1,?,?,?)", j.RequestID, j.TerminalID, []byte(`{"complete":"event"}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec("INSERT INTO op_effect(id,kind,request_id,event_sequence,ordinal,payload) VALUES(?,'PRINT',?,1,0,?)", j.EffectID, j.RequestID, payload); err != nil {
		t.Fatal(err)
	}
}

func finishBusinessResult(tx *sql.Tx, j FrozenJob, result []byte) error {
	_, err := tx.Exec("INSERT INTO op_request(request_id,terminal_id,authority_epoch,digest,outcome,event_sequence,result) VALUES(?,?,1,?,'COMMITTED',1,?)", j.RequestID, j.TerminalID, bytes.Repeat([]byte{1}, 32), result)
	return err
}

func TestAtomicCanonicalPrintAdmissionRollbackAndExactRetry(t *testing.T) {
	f := newFixture(t)
	j := job(t, 10, 21, 1, false)
	if err := f.store.Register(background, registry(21)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec("INSERT INTO terminal(id,display_name,verifier,created_at) VALUES(?,'synthetic','synthetic',0)", j.TerminalID); err != nil {
		t.Fatal(err)
	}
	// A result failure after queue insertion must roll back canonical entities,
	// event/effect, admission receipt, reservations and the sequence together.
	tx, err := f.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	canonicalEffect(t, tx, j, j.Raw())
	if _, err = tx.Exec("INSERT INTO op_entity(kind,id,revision,tombstone,document) VALUES('ORDER',?,1,0,?)", uuid(500), []byte(`{"committed":true}`)); err != nil {
		t.Fatal(err)
	}
	if _, err = AdmitTx(background, tx, authority(j), j); err != nil {
		t.Fatal(err)
	}
	if err = finishBusinessResult(tx, j, []byte{}); err == nil {
		t.Fatal("invalid result succeeded")
	}
	if err = tx.Rollback(); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"op_entity", "op_event", "op_effect", "op_request", "pq_job", "pq_receipt", "pq_beep"} {
		if count(t, f.db, table) != 0 {
			t.Fatal("partial commit", table)
		}
	}
	var sequence int
	if err = f.db.QueryRow("SELECT next_sequence FROM pq_registry").Scan(&sequence); err != nil || sequence != 1 {
		t.Fatal("rollback spent sequence")
	}
	// Opaque proof PRINT payloads cannot accidentally activate typed dispatch.
	tx, err = f.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	canonicalEffect(t, tx, j, []byte(`{"legacy":"opaque"}`))
	if _, err = AdmitTx(background, tx, authority(j), j); !errors.Is(err, ErrInvalid) {
		t.Fatalf("opaque PRINT accepted: %v", err)
	}
	if err = tx.Rollback(); err != nil {
		t.Fatal(err)
	}
	if count(t, f.db, "pq_job") != 0 || count(t, f.db, "op_effect") != 0 {
		t.Fatal("opaque PRINT partial admission")
	}
	tx, err = f.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	canonicalEffect(t, tx, j, j.Raw())
	first, err := AdmitTx(background, tx, authority(j), j)
	if err != nil {
		t.Fatal(err)
	}
	if err = finishBusinessResult(tx, j, []byte(`{"complete":"result"}`)); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	tx, err = f.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	retry, err := AdmitTx(background, tx, authority(j), j)
	if err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if first != retry || first.Sequence != 1 || count(t, f.db, "pq_job") != 1 || count(t, f.db, "op_effect") != 1 {
		t.Fatal("exact canonical retry changed admission")
	}
}

func TestUnsupportedUnknownAndMalformedBeepDoesNotLosePrimary(t *testing.T) {
	for _, beep := range []string{`{"capability":"unknown","enabled":true}`, `{"capability":"epsonEscA97Pattern","enabled":"bad"}`, `{"capability":"unsupported","enabled":true}`, `"malformed"`, `null`, `{"Capability":"epsonEscA97Pattern","Enabled":true}`, `{"capability":"epsonEscA97Pattern","enabled":true,"extra":1}`, `{"capability":"epsonEscA97Pattern"}`} {
		t.Run(beep, func(t *testing.T) {
			f := newFixture(t)
			if err := f.store.Register(background, registry(21)); err != nil {
				t.Fatal(err)
			}
			j := modify(t, job(t, 10, 21, 1, false), func(j *FrozenJob) {
				var profile map[string]json.RawMessage
				if err := json.Unmarshal(j.CapabilityProfile, &profile); err != nil {
					t.Fatal(err)
				}
				profile["beep"] = []byte(beep)
				j.CapabilityProfile, _ = json.Marshal(profile)
			})
			admitJob(t, f, j)
			calls := 0
			s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
				calls++
				return accepted(p)
			}}, proofOptions())
			if err := s.RunNext(uuid(21)); err != nil {
				t.Fatal(err)
			}
			o, err := f.store.Outcome(background, j.JobID)
			if err != nil || o.Primary != Submitted || o.Beep != BeepSkipped || calls != 1 {
				t.Fatalf("primary lost for optional beep: %+v calls=%d %v", o, calls, err)
			}
		})
	}
}
