package store_test

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"sync"
	"testing"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

func terminal(t *testing.T, s *store.Store) *pb.AuthenticatedRequest {
	t.Helper()
	ticket, e := s.IssueTicket()
	if e != nil {
		t.Fatal(e)
	}
	a := &pb.AuthenticatedRequest{TerminalId: uuid.NewString(), TerminalSecret: store.Secret()}
	if e = s.Pair(context.Background(), ticket, uuid.NewString(), a.TerminalId, a.TerminalSecret, "coordination"); e != nil {
		t.Fatal(e)
	}
	return a
}
func entity(kind pb.ProjectionEntity_Kind, id string, d any, revision uint64) *pb.EntityChange {
	raw, _ := json.Marshal(d)
	return &pb.EntityChange{ExpectedRevision: revision, Entity: &pb.ProjectionEntity{Kind: kind, Id: id, Document: raw}}
}
func order(id, line string, tables []string, revision uint64) *pb.EntityChange {
	return entity(pb.ProjectionEntity_ORDER, id, map[string]any{"orderUuid": id, "status": "pending", "tableIds": tables, "orderId": 1, "floor": "first", "createdAt": "2026-09-20T12:00:00.000", "createdBy": "test", "totalAmount": 4.0, "includeServiceFee": false, "items": []any{map[string]any{"lineUuid": line, "itemKey": "Tea", "itemName": "Tea", "quantity": 1, "unitPrice": 4.0, "total": 4.0}}}, revision)
}
func table(id, active string, revision uint64) *pb.EntityChange {
	var occupant any
	if active != "" {
		occupant = active
	}
	return entity(pb.ProjectionEntity_TABLE, id, map[string]any{"tableId": id, "activeOrderUuid": occupant, "floor": "first", "tableNumber": "1"}, revision)
}
func intent(a *pb.AuthenticatedRequest, changes ...*pb.EntityChange) *pb.CommitIntent {
	return &pb.CommitIntent{Auth: a, RequestId: uuid.NewString(), AuthorityEpoch: 1, Changes: changes}
}
func commit(t *testing.T, s *store.Store, r *pb.CommitIntent) *pb.CommitResult {
	t.Helper()
	v, e := s.CommitIntent(context.Background(), r)
	if e != nil {
		t.Fatal(e)
	}
	return v
}
func TestCoordinationAtomicConflictIdempotencyReplay(t *testing.T) {
	dir := t.TempDir()
	s, _ := testutil.Bound(t, dir)
	defer func() { s.Close() }()
	a, b := terminal(t, s), terminal(t, s)
	oid, tid, line := uuid.NewString(), uuid.NewString(), uuid.NewString()
	first := intent(a, order(oid, line, []string{tid}, 0), table(tid, oid, 0))
	accepted := commit(t, s, first)
	if accepted.Event.Sequence != 1 || len(accepted.Event.Entities) != 2 {
		t.Fatal(accepted)
	}
	if got := commit(t, s, first); !proto.Equal(got, accepted) {
		t.Fatal("lost ACK retry changed result")
	}
	changed := proto.Clone(first).(*pb.CommitIntent)
	changed.Auth = b
	if _, e := s.CommitIntent(context.Background(), changed); !errors.Is(e, store.ErrRequestReuse) {
		t.Fatal(e)
	}
	changed = proto.Clone(first).(*pb.CommitIntent)
	changed.Changes[0].ExpectedRevision = 1
	if _, e := s.CommitIntent(context.Background(), changed); !errors.Is(e, store.ErrRequestReuse) {
		t.Fatal(e)
	}
	stale := intent(b, order(oid, line, []string{tid}, 0), table(tid, oid, 1))
	rejected := commit(t, s, stale)
	if rejected.Outcome != pb.CommitResult_CONFLICT || len(rejected.Current) != 2 || rejected.Current[0].Revision != 1 {
		t.Fatal(rejected)
	}
	// Two distinct terminals holding the same revision: exactly one wins.
	requests := []*pb.CommitIntent{intent(a, order(oid, line, []string{tid}, 1)), intent(b, order(oid, line, []string{tid}, 1))}
	var wg sync.WaitGroup
	results := make(chan *pb.CommitResult, 2)
	errs := make(chan error, 2)
	for _, r := range requests {
		wg.Add(1)
		go func() { defer wg.Done(); v, e := s.CommitIntent(context.Background(), r); results <- v; errs <- e }()
	}
	wg.Wait()
	close(results)
	close(errs)
	for e := range errs {
		if e != nil {
			t.Fatal(e)
		}
	}
	wins := 0
	for v := range results {
		if v.Outcome == pb.CommitResult_COMMITTED {
			wins++
		}
	}
	if wins != 1 {
		t.Fatal("not exactly one winner", wins)
	}
	// A stale Table prevents an otherwise current Order from changing.
	got := commit(t, s, intent(a, order(oid, line, []string{tid}, 2), table(tid, oid, 0)))
	if got.Outcome != pb.CommitResult_CONFLICT || got.Current[0].Revision != 2 {
		t.Fatal(got)
	}
	// Moving an Order between Tables is one event; dangling occupancy rolls back.
	secondTable := uuid.NewString()
	invalid := intent(a, order(oid, line, []string{secondTable}, 2), table(secondTable, oid, 0))
	if _, e := s.CommitIntent(context.Background(), invalid); !errors.Is(e, store.ErrIntent) {
		t.Fatal(e)
	}
	moved := commit(t, s, intent(a, order(oid, line, []string{secondTable}, 2), table(tid, "", 1), table(secondTable, oid, 0)))
	if moved.Event.Sequence != 3 {
		t.Fatal(moved)
	}
	dead := &pb.EntityChange{ExpectedRevision: 3, Entity: &pb.ProjectionEntity{Kind: pb.ProjectionEntity_ORDER, Id: oid, Tombstone: true}}
	deleted := commit(t, s, intent(b, dead, table(secondTable, "", 1)))
	if deleted.Event.Sequence != 4 {
		t.Fatal(deleted)
	}
	if got := commit(t, s, intent(a, order(oid, line, []string{}, 4))); got.Outcome != pb.CommitResult_CONFLICT || !got.Current[0].Tombstone {
		t.Fatal(got)
	}
	if !proto.Equal(commit(t, s, stale), rejected) {
		t.Fatal("conflict retry changed after later edits")
	}
	snap, e := s.ProjectionSnapshot(context.Background(), 1)
	if e != nil || snap.Sequence != 4 || snap.Mode != "SHADOW" {
		t.Fatal(snap, e)
	}
	page, e := s.Replay(context.Background(), 1, 0, 2)
	if e != nil || len(page.Events) != 2 || page.HeadSequence != 4 {
		t.Fatal(page, e)
	}
	page, e = s.Replay(context.Background(), 1, 2, 2)
	if e != nil || len(page.Events) != 2 || !page.Events[1].Entities[0].Tombstone {
		t.Fatal(page, e)
	}
	if _, e = s.Replay(context.Background(), 1, 5, 0); !errors.Is(e, store.ErrIntent) {
		t.Fatal(e)
	}
	first.AuthorityEpoch = 2
	if _, e = s.CommitIntent(context.Background(), first); !errors.Is(e, store.ErrEpoch) {
		t.Fatal(e)
	}
	first.AuthorityEpoch = 1
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e = store.Open(dir, false)
	if e != nil {
		t.Fatal(e)
	}
	if !proto.Equal(commit(t, s, first), accepted) {
		t.Fatal("restart forgot request result")
	}
	after, e := s.ProjectionSnapshot(context.Background(), 1)
	if e != nil || !proto.Equal(after, snap) {
		t.Fatal("restart changed snapshot", e)
	}
}
func TestCoordinationRollsBackEventAndStateWhenResultCannotPersist(t *testing.T) {
	s, _ := testutil.Bound(t, t.TempDir())
	defer s.Close()
	a := terminal(t, s)
	if _, e := s.DB.Exec("CREATE TRIGGER fail_result BEFORE INSERT ON request_result BEGIN SELECT RAISE(ABORT,'injected disk write failure'); END"); e != nil {
		t.Fatal(e)
	}
	r := intent(a, order(uuid.NewString(), uuid.NewString(), []string{}, 0))
	if _, e := s.CommitIntent(context.Background(), r); e == nil {
		t.Fatal("false ACK")
	}
	snap, e := s.ProjectionSnapshot(context.Background(), 1)
	if e != nil || snap.Sequence != 0 || len(snap.Entities) != 0 {
		t.Fatal("partial transaction", snap, e)
	}
}
func TestCoordinationMigrationFromPhase1(t *testing.T) {
	dir := t.TempDir()
	s, id := testutil.Bound(t, dir)
	a := terminal(t, s)
	for _, q := range []string{"DROP TABLE request_result", "DROP TABLE committed_event", "DROP TABLE projection", "DROP TABLE coordination", "DELETE FROM schema_migration WHERE version=2", "PRAGMA user_version=1"} {
		if _, e := s.DB.Exec(q); e != nil {
			t.Fatal(e)
		}
	}
	s.Close()
	s, e := store.Open(dir, false)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	restored, e := s.Identity()
	if e != nil || restored.InstallationID != id.InstallationID {
		t.Fatal(e)
	}
	if e = s.Authenticate(context.Background(), a.TerminalId, a.TerminalSecret); e != nil {
		t.Fatal(e)
	}
	snap, e := s.ProjectionSnapshot(context.Background(), 1)
	if e != nil || snap.Sequence != 0 {
		t.Fatal(e)
	}
}
func TestCoordinationCrashRecovery(t *testing.T) {
	if dir := os.Getenv("VYNIC_COORDINATION_CRASH_DIR"); dir != "" {
		s, e := store.Open(dir, false)
		if e != nil {
			t.Fatal(e)
		}
		a := terminal(t, s)
		r := intent(a, order(uuid.NewString(), uuid.NewString(), []string{}, 0))
		commit(t, s, r)
		tx, e := s.DB.Begin()
		if e != nil {
			t.Fatal(e)
		}
		if _, e = tx.Exec("UPDATE coordination SET sequence=1234"); e != nil {
			t.Fatal(e)
		}
		os.Exit(17)
	}
	dir := t.TempDir()
	s, _ := testutil.Bound(t, dir)
	s.Close()
	cmd := exec.Command(os.Args[0], "-test.run=^TestCoordinationCrashRecovery$")
	cmd.Env = append(os.Environ(), "VYNIC_COORDINATION_CRASH_DIR="+dir)
	var exit *exec.ExitError
	if e := cmd.Run(); !errors.As(e, &exit) || exit.ExitCode() != 17 {
		t.Fatal(e)
	}
	s, e := store.Open(dir, false)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	snap, e := s.ProjectionSnapshot(context.Background(), 1)
	if e != nil || snap.Sequence != 1 || len(snap.Entities) != 1 {
		t.Fatal(snap, e)
	}
	var events, results int
	s.DB.QueryRow("SELECT count(*) FROM committed_event").Scan(&events)
	s.DB.QueryRow("SELECT count(*) FROM request_result").Scan(&results)
	if events != 1 || results != 1 {
		t.Fatal(events, results)
	}
}

func TestCoordinationRejectsUnreplayableOrOutOfScopeDocuments(t *testing.T) {
	s, _ := testutil.Bound(t, t.TempDir())
	defer s.Close()
	a := terminal(t, s)
	for _, name := range []string{"payment", "line-type", "line-field", "timestamp", "duplicate-line"} {
		t.Run(name, func(t *testing.T) {
			change := order(uuid.NewString(), uuid.NewString(), []string{}, 0)
			var doc map[string]any
			if e := json.Unmarshal(change.Entity.Document, &doc); e != nil {
				t.Fatal(e)
			}
			lines := doc["items"].([]any)
			switch name {
			case "payment":
				doc["paymentMethod"] = "cash"
			case "line-type":
				lines[0].(map[string]any)["quantity"] = "bad"
			case "line-field":
				lines[0].(map[string]any)["payment"] = "bad"
			case "timestamp":
				doc["createdAt"] = "not-a-date"
			case "duplicate-line":
				doc["items"] = append(lines, lines[0])
			}
			change.Entity.Document, _ = json.Marshal(doc)
			if _, e := s.CommitIntent(context.Background(), intent(a, change)); !errors.Is(e, store.ErrIntent) {
				t.Fatal(e)
			}
		})
	}
	snap, e := s.ProjectionSnapshot(context.Background(), 1)
	if e != nil || snap.Sequence != 0 || len(snap.Entities) != 0 {
		t.Fatal(snap, e)
	}
}
