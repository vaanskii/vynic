package printcluster

import (
	"bytes"
	"context"
	"database/sql"
	"io"
	"net"
	"path/filepath"
	"testing"
	"time"
	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

func TestNormalizedPayloadDedupIncrementalAndCorruption(t *testing.T) {
	pin := stationPin(t, 1)
	cluster := startCluster(t, pin)
	n := cluster.leader()
	ctx := context.Background()
	a := stationCaller(pin.Peers[0])
	c := stationCatalog(t, pin)
	if e := n.InstallStations(ctx, a, c); e != nil {
		t.Fatal(e)
	}
	j := stationJob(c, pin.Peers[0], 1, 512*1024, 0)
	receipt, e := n.SubmitStation(ctx, a, testUUID(18000), j)
	if e != nil {
		t.Fatal(e)
	}
	j2 := stationJob(c, pin.Peers[0], 2, len(j.Payload), 1)
	if _, e = n.SubmitStation(ctx, a, testUUID(18001), j2); e != nil {
		t.Fatal(e)
	}
	var count int
	if e = n.fsm.db.QueryRow("SELECT count(*) FROM printcluster_payloads WHERE digest=?", j.PayloadDigest).Scan(&count); e != nil || count != 1 {
		t.Fatal("payload not deduplicated", count, e)
	}
	// A state/result transition must not rewrite immutable bytes or job metadata.
	for _, q := range []string{`CREATE TRIGGER forbid_blob_insert BEFORE INSERT ON printcluster_payloads BEGIN SELECT RAISE(ABORT,'payload rewrite'); END`, `CREATE TRIGGER forbid_blob_update BEFORE UPDATE ON printcluster_payloads BEGIN SELECT RAISE(ABORT,'payload rewrite'); END`, `CREATE TRIGGER forbid_job_update BEFORE UPDATE ON printcluster_rows WHEN NEW.kind='station_job' BEGIN SELECT RAISE(ABORT,'job rewrite'); END`} {
		if _, e = n.fsm.db.Exec(q); e != nil {
			t.Fatal(e)
		}
	}
	if _, e = n.BeginStationAttempt(ctx, a, j.ID, testUUID(18002), 2); e != nil {
		t.Fatal(e)
	}
	if e = n.FinishStationAttempt(ctx, a, j.ID, testUUID(18002), 3, printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: uint32(len(j.Payload))}); e != nil {
		t.Fatal(e)
	}
	retry, e := n.SubmitStation(ctx, a, testUUID(18000), j)
	if e != nil || retry != receipt {
		t.Fatal("exact receipt changed", e)
	}
	// End immutable-write traps before restoring into a new independent store.
	snap, e := n.fsm.Snapshot()
	if e != nil {
		t.Fatal(e)
	}
	restored, e := openProjection(t.TempDir(), pin)
	if e != nil {
		t.Fatal(e)
	}
	defer restored.close()
	if e = restored.Restore(io.NopCloser(bytes.NewReader(snap.(*projectionSnapshot).raw))); e != nil {
		t.Fatal(e)
	}
	if !bytes.Equal(restored.state.Stations.Jobs[j.ID].Job.Payload, j.Payload) {
		t.Fatal("snapshot omitted bytes")
	}
	if e = n.CompactStationHistory(ctx, a, printstation.DiagnosticRetentionMillis+10); e != nil {
		t.Fatal(e)
	}
	if _, ok := n.fsm.state.Stations.Jobs[j2.ID]; !ok {
		t.Fatal("queued job pruned")
	}
	if e = n.fsm.db.QueryRow("SELECT count(*) FROM printcluster_payloads WHERE digest=?", j.PayloadDigest).Scan(&count); e != nil || count != 1 {
		t.Fatal("payload deleted while queued job references it", e)
	}
	if _, e = n.SubmitStation(ctx, a, testUUID(18000), j); e == nil {
		t.Fatal("retired identity replayed")
	}
	if e = n.Close(); e != nil {
		t.Fatal(e)
	}
	cluster.nodes[0] = nil
	db, e := sql.Open("sqlite", filepath.Join(cluster.dirs[0], "projection.sqlite"))
	if e != nil {
		t.Fatal(e)
	}
	if _, e = db.Exec("DROP TRIGGER forbid_blob_update"); e != nil {
		t.Fatal(e)
	}
	if _, e = db.Exec("UPDATE printcluster_payloads SET bytes=zeroblob(length) WHERE digest=?", j.PayloadDigest); e != nil {
		t.Fatal(e)
	}
	db.Close()
	if f, e := openProjection(cluster.dirs[0], pin); e == nil {
		f.close()
		t.Fatal("corrupted payload reopened")
	}
}

func TestNormalizedOldReaderRefusedWithoutSchemaMutation(t *testing.T) {
	pin := stationPin(t, 1)
	dir := t.TempDir()
	db, e := sql.Open("sqlite", filepath.Join(dir, "projection.sqlite"))
	if e != nil {
		t.Fatal(e)
	}
	if _, e = db.Exec("CREATE TABLE printcluster_projection(id INTEGER PRIMARY KEY,schema_version INTEGER); INSERT INTO printcluster_projection VALUES(1,1)"); e != nil {
		t.Fatal(e)
	}
	db.Close()
	if f, e := openProjection(dir, pin); e == nil {
		f.close()
		t.Fatal("old projection opened without explicit migration")
	}
	db, e = sql.Open("sqlite", filepath.Join(dir, "projection.sqlite"))
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	var tables int
	if e = db.QueryRow("SELECT count(*) FROM sqlite_master WHERE type='table'").Scan(&tables); e != nil || tables != 1 {
		t.Fatal("refusal changed old schema", tables, e)
	}
}

func TestNormalizedProtocolRefusesOldPeer(t *testing.T) {
	pin := stationPin(t, 1)
	stream, e := newProofStream(pin, pin.Peers[0].ID)
	if e != nil {
		t.Fatal(e)
	}
	done := make(chan error, 1)
	go func() {
		c, e := stream.Accept()
		if c != nil {
			c.Close()
			done <- ErrInvalid
		} else {
			done <- e
		}
	}()
	old, e := net.DialTimeout("tcp", pin.Peers[0].Address, time.Second)
	if e != nil {
		stream.Close()
		t.Fatal(e)
	}
	if _, e = io.WriteString(old, "vynic-proof/"+pin.Peers[0].ID); e != nil {
		t.Fatal(e)
	}
	old.SetReadDeadline(time.Now().Add(3 * time.Second))
	var b [1]byte
	_, e = old.Read(b[:])
	old.Close()
	if e != io.EOF {
		stream.Close()
		t.Fatalf("old peer not refused: %v", e)
	}
	stream.Close()
	if e = <-done; e == nil || e == ErrInvalid {
		t.Fatal("old stream was accepted")
	}
}
