package printqueue

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"vynic.local/edge/internal/printtransport"
)

// This is a nonproduction loopback protocol fixture: three independent Go
// relay services/databases and one independent executor database. Static test
// peer tuples stand in for authentication; it does not qualify real TLS/host
// fencing, quorum replication, a network partition or physical printer I/O.
func TestThreeIndependentRelaysToTwoPrinterExecutor(t *testing.T) {
	f := newFixture(t)
	for _, p := range []int{21, 22} {
		if err := f.store.Register(background, registry(p)); err != nil {
			t.Fatal(err)
		}
	}
	var gatewayMu sync.Mutex
	lostACK := false
	peers := make(map[string]string)
	for client := 1; client <= 3; client++ {
		peers[uuid(client+200)] = uuid(client + 100)
	}
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxEnvelopeBytes))
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		j, err := DecodeFrozenJob(raw)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		origin := r.Header.Get("X-Synthetic-Verified-Origin")
		terminal := peers[origin]
		if terminal == "" || terminal != j.TerminalID || origin != j.OriginInstallationID {
			http.Error(w, "synthetic peer tuple mismatch", 403)
			return
		}
		a := Authority{VenueID: identity().VenueID, InstallationID: identity().InstallationID, Epoch: 1, OriginInstallationID: origin, TerminalID: terminal}
		receipt, err := f.store.Accept(r.Context(), a, j)
		if err != nil {
			http.Error(w, err.Error(), 409)
			return
		}
		gatewayMu.Lock()
		drop := j.JobID == uuid(10) && !lostACK
		if drop {
			lostACK = true
		}
		gatewayMu.Unlock()
		if drop {
			// Admission is committed, then the actual loopback ACK is lost.
			conn, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error(err)
				return
			}
			if err = conn.Close(); err != nil {
				t.Error(err)
			}
			return
		}
		if err = json.NewEncoder(w).Encode(receipt); err != nil {
			t.Error(err)
		}
	}))
	defer gateway.Close()
	type relay struct {
		db     *sql.DB
		server *httptest.Server
	}
	var relays []relay
	for client := 1; client <= 3; client++ {
		origin, terminal := uuid(client+200), uuid(client+100)
		db := openDB(t, filepath.Join(t.TempDir(), fmt.Sprintf("relay%d.sqlite", client)), 6)
		if _, err := db.Exec("CREATE TABLE fixture_relay_outbox(job_id TEXT PRIMARY KEY,digest TEXT NOT NULL,body BLOB NOT NULL,receipt BLOB)"); err != nil {
			t.Fatal(err)
		}
		var mu sync.Mutex
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxEnvelopeBytes))
			if err != nil {
				http.Error(w, err.Error(), 400)
				return
			}
			j, err := DecodeFrozenJob(raw)
			if err != nil || j.OriginInstallationID != origin || j.TerminalID != terminal {
				http.Error(w, "invalid synthetic origin", 400)
				return
			}
			mu.Lock()
			defer mu.Unlock()
			tx, err := db.BeginTx(r.Context(), nil)
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			defer tx.Rollback()
			var storedDigest string
			var storedRaw, receiptRaw []byte
			err = tx.QueryRow("SELECT digest,body,receipt FROM fixture_relay_outbox WHERE job_id=?", j.JobID).Scan(&storedDigest, &storedRaw, &receiptRaw)
			if err == sql.ErrNoRows {
				// Business effect and relay outbox enter one local transaction.
				var sequence int
				if err = tx.QueryRow("SELECT coalesce(max(sequence),0)+1 FROM op_event").Scan(&sequence); err != nil {
					http.Error(w, err.Error(), 500)
					return
				}
				if _, err = tx.Exec("INSERT INTO terminal(id,display_name,verifier,created_at) VALUES(?,'synthetic','synthetic',0) ON CONFLICT(id) DO NOTHING", terminal); err != nil {
					http.Error(w, err.Error(), 500)
					return
				}
				if _, err = tx.Exec("INSERT INTO op_event(sequence,authority_epoch,request_id,terminal_id,event) VALUES(?,1,?,?,?)", sequence, j.RequestID, terminal, []byte(`{"complete":"synthetic business event"}`)); err != nil {
					http.Error(w, err.Error(), 500)
					return
				}
				if _, err = tx.Exec("INSERT INTO op_effect(id,kind,request_id,event_sequence,ordinal,payload) VALUES(?,'PRINT',?,?,0,?)", j.EffectID, j.RequestID, sequence, raw); err != nil {
					http.Error(w, err.Error(), 500)
					return
				}
				if _, err = tx.Exec("INSERT INTO fixture_relay_outbox(job_id,digest,body) VALUES(?,?,?)", j.JobID, j.Digest(), raw); err != nil {
					http.Error(w, err.Error(), 500)
					return
				}
				if _, err = tx.Exec("INSERT INTO op_request(request_id,terminal_id,authority_epoch,digest,outcome,event_sequence,result) VALUES(?,?,1,?,'COMMITTED',?,?)", j.RequestID, terminal, bytes.Repeat([]byte{1}, 32), sequence, []byte(`{"complete":"synthetic business result"}`)); err != nil {
					http.Error(w, err.Error(), 500)
					return
				}
				storedRaw = raw
			} else if err != nil {
				http.Error(w, err.Error(), 500)
				return
			} else if storedDigest != j.Digest() || !bytes.Equal(storedRaw, raw) {
				http.Error(w, "immutable relay identity reused", 409)
				return
			}
			if err = tx.Commit(); err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			if receiptRaw != nil {
				_, err = w.Write(receiptRaw)
				if err != nil {
					t.Error(err)
				}
				return
			}
			req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, gateway.URL, bytes.NewReader(storedRaw))
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			req.Header.Set("X-Synthetic-Verified-Origin", origin)
			response, err := http.DefaultClient.Do(req)
			if err != nil {
				http.Error(w, "gateway ACK unavailable", 503)
				return
			}
			defer response.Body.Close()
			receiptRaw, err = io.ReadAll(response.Body)
			if err != nil {
				http.Error(w, err.Error(), 503)
				return
			}
			if response.StatusCode != 200 {
				http.Error(w, string(receiptRaw), response.StatusCode)
				return
			}
			if _, err = db.Exec("UPDATE fixture_relay_outbox SET receipt=? WHERE job_id=?", receiptRaw, j.JobID); err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			if _, err = w.Write(receiptRaw); err != nil {
				t.Error(err)
			}
		}))
		t.Cleanup(server.Close)
		relays = append(relays, relay{db, server})
	}
	post := func(server *httptest.Server, j FrozenJob) (Receipt, int) {
		t.Helper()
		response, err := http.Post(server.URL, "application/json", bytes.NewReader(j.Raw()))
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		var receipt Receipt
		if response.StatusCode == 200 {
			if err = json.NewDecoder(response.Body).Decode(&receipt); err != nil {
				t.Fatal(err)
			}
		}
		return receipt, response.StatusCode
	}
	j1 := job(t, 10, 21, 1, false)
	j2 := job(t, 11, 21, 2, false)
	j3 := job(t, 12, 22, 3, false)
	if _, status := post(relays[0].server, j1); status != 503 || count(t, f.db, "pq_job") != 1 {
		t.Fatalf("lost ACK did not retain owner admission: %d", status)
	}
	first, status := post(relays[0].server, j1)
	if status != 200 || first.Sequence != 1 || count(t, relays[0].db, "op_effect") != 1 || count(t, f.db, "pq_job") != 1 {
		t.Fatal("relay retry created duplicate", status)
	}
	if _, status = post(relays[1].server, j2); status != 200 {
		t.Fatal(status)
	}
	if _, status = post(relays[2].server, j3); status != 200 {
		t.Fatal(status)
	}
	// Turning off one relay leaves the other independent services and executor.
	relays[0].server.Close()
	j4 := job(t, 13, 21, 2, false)
	j5 := job(t, 14, 22, 3, false)
	if r, status := post(relays[1].server, j4); status != 200 || r.Sequence != 3 {
		t.Fatal("POS2 new admission stopped with POS1", status)
	}
	if r, status := post(relays[2].server, j5); status != 200 || r.Sequence != 2 {
		t.Fatal("POS3 new admission stopped with POS1", status)
	}
	for _, j := range []FrozenJob{j1, j2, j3, j4, j5} {
		var frozen []byte
		if err := f.db.QueryRow("SELECT envelope FROM pq_job WHERE job_id=?", j.JobID).Scan(&frozen); err != nil || !bytes.Equal(frozen, j.Raw()) {
			t.Fatal("relay rewrote immutable envelope", err)
		}
	}
	var sentMu sync.Mutex
	sent := make(map[string][]string)
	s := scheduler(t, f, &fakeSender{call: func(_ context.Context, d printtransport.Destination, p []byte) printtransport.Result {
		sentMu.Lock()
		sent[d.PhysicalPrinterID] = append(sent[d.PhysicalPrinterID], d.DocumentName)
		sentMu.Unlock()
		return accepted(p)
	}}, proofOptions())
	if err := s.Start([]string{uuid(21), uuid(22)}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(background, 2*time.Second)
	defer cancel()
	for _, j := range []FrozenJob{j1, j2, j3, j4, j5} {
		o, err := s.Wait(ctx, j.JobID)
		if err != nil || o.Primary != Submitted {
			t.Fatal(o, err)
		}
	}
	sentMu.Lock()
	defer sentMu.Unlock()
	if fmt.Sprint(sent[uuid(21)]) != fmt.Sprint([]string{j1.Destination.DocumentName, j2.Destination.DocumentName, j4.Destination.DocumentName}) || fmt.Sprint(sent[uuid(22)]) != fmt.Sprint([]string{j3.Destination.DocumentName, j5.Destination.DocumentName}) {
		t.Fatal("physical FIFO violated", sent)
	}
	t.Log("three loopback Go relay services with separate WAL databases; one relay stopped; remaining relays admitted new immutable jobs; two independent executor FIFOs; no physical I/O")
}
