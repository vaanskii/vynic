package store_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

const proofEpoch uint64 = 41

func proofGrant(t *testing.T, id store.Identity) (store.OperationalProofGrant, ed25519.PrivateKey) {
	t.Helper()
	_, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().Unix()
	return store.OperationalProofGrant{Version: 1, Purpose: store.OperationalProofPurpose, Mode: store.OperationalProofMode, GrantID: uuid.NewString(), InstallationID: id.InstallationID, VenueID: id.VenueID, PublicKey: id.PublicKey, AuthorityEpoch: proofEpoch, IssuedAt: now, ExpiresAt: now + 600}, private
}

func signProofGrant(t *testing.T, g store.OperationalProofGrant, private ed25519.PrivateKey) (string, []byte) {
	t.Helper()
	encoded, err := json.Marshal(g)
	if err != nil {
		t.Fatal(err)
	}
	payload := base64.RawURLEncoding.EncodeToString(encoded)
	raw := payload + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(private, []byte(payload)))
	der, err := x509.MarshalPKIXPublicKey(private.Public())
	if err != nil {
		t.Fatal(err)
	}
	return raw, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})
}

func operationalTerminal(t *testing.T, s *store.Store) store.OperationalAuth {
	t.Helper()
	a := terminal(t, s)
	return store.OperationalAuth{TerminalID: a.TerminalId, TerminalSecret: a.TerminalSecret}
}

func boundProof(t *testing.T, dir string) (*store.Store, store.Identity, store.OperationalAuth) {
	t.Helper()
	s, id := testutil.Bound(t, dir)
	g, private := proofGrant(t, id)
	raw, trust := signProofGrant(t, g, private)
	if err := s.PinOperationalProofAuthority(context.Background(), raw, trust); err != nil {
		s.Close()
		t.Fatal(err)
	}
	return s, id, operationalTerminal(t, s)
}

func operationalWrite(kind store.OperationalEntityKind, id string, revision uint64, document string) store.OperationalWrite {
	return store.OperationalWrite{Kind: kind, ID: id, ExpectedRevision: revision, Document: []byte(document)}
}

func operationalIntent(auth store.OperationalAuth, writes ...store.OperationalWrite) *store.OperationalCommit {
	return &store.OperationalCommit{Auth: auth, RequestID: uuid.NewString(), AuthorityEpoch: proofEpoch, Writes: writes}
}

func operationalCommit(t *testing.T, s *store.Store, r *store.OperationalCommit) *store.OperationalCommitResult {
	t.Helper()
	result, err := s.CommitOperational(context.Background(), r)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func operationalClone(t *testing.T, r *store.OperationalCommit) *store.OperationalCommit {
	t.Helper()
	raw, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	var cloned store.OperationalCommit
	if err = json.Unmarshal(raw, &cloned); err != nil {
		t.Fatal(err)
	}
	cloned.Auth = r.Auth
	return &cloned
}

func operationalSnapshot(t *testing.T, s *store.Store, auth store.OperationalAuth) *store.OperationalSnapshot {
	t.Helper()
	result, err := s.OperationalProjectionSnapshot(context.Background(), auth, proofEpoch)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func operationalCounts(t *testing.T, s *store.Store) (requests, events, effects int) {
	t.Helper()
	if err := s.DB.QueryRow("SELECT (SELECT count(*) FROM op_request),(SELECT count(*) FROM op_event),(SELECT count(*) FROM op_effect)").Scan(&requests, &events, &effects); err != nil {
		t.Fatal(err)
	}
	return
}

func TestOperationalExpandedKindsRoundTripReplayAndSnapshot(t *testing.T) {
	for _, kind := range []store.OperationalEntityKind{store.OperationalControl, store.OperationalAuditReport, store.OperationalClosure, store.OperationalAdvance, store.OperationalExpense, store.OperationalStaff, store.OperationalPolicy} {
		t.Run(string(kind), func(t *testing.T) {
			ctx := context.Background()
			dir := t.TempDir()
			s, _, auth := boundProof(t, dir)
			id := uuid.NewString()
			// The proof preserves opaque complete JSON bytes. It does not require
			// planner-specific control, policy, staff or financial fields.
			documents := []string{" {\n \"opaque\": \"ქართული\", \"value\": 1 }\n", `{"opaque":"updated","value":2}`}
			create := operationalIntent(auth, operationalWrite(kind, id, 0, documents[0]))
			create.Reads = []store.OperationalRead{{Kind: kind, ID: id}}
			update := operationalIntent(auth, operationalWrite(kind, id, 1, documents[1]))
			update.Reads = []store.OperationalRead{{Kind: kind, ID: id, ExpectedRevision: 1}}
			remove := operationalIntent(auth, store.OperationalWrite{Kind: kind, ID: id, ExpectedRevision: 2, Tombstone: true})
			requests := []*store.OperationalCommit{create, update, remove}
			results := make([]*store.OperationalCommitResult, 0, len(requests))
			for i, request := range requests {
				result := operationalCommit(t, s, request)
				if result.Outcome != store.OperationalCommitted || result.HeadSequence != uint64(i+1) || result.Event == nil || len(result.Event.Entities) != 1 {
					t.Fatal("expanded kind did not commit", result)
				}
				entity := result.Event.Entities[0]
				var document []byte
				if i < len(documents) {
					document = []byte(documents[i])
				}
				if entity.Kind != kind || entity.ID != id || entity.Revision != uint64(i+1) || entity.Tombstone != (i == 2) || !bytes.Equal(entity.Document, document) {
					t.Fatal("expanded kind changed opaque postimage", entity)
				}
				snapshot := operationalSnapshot(t, s, auth)
				if snapshot.Sequence != result.HeadSequence || len(snapshot.Entities) != 1 || !reflect.DeepEqual(snapshot.Entities[0], entity) {
					t.Fatal("snapshot changed expanded kind", snapshot)
				}
				results = append(results, result)
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			var err error
			s, err = store.Open(dir, false)
			if err != nil {
				t.Fatal(err)
			}
			defer s.Close()
			for i, request := range requests {
				if retried := operationalCommit(t, s, request); !reflect.DeepEqual(retried, results[i]) {
					t.Fatal("restart changed exact expanded-kind result", retried)
				}
				lookedUp, err := s.OperationalResult(ctx, auth, proofEpoch, request.RequestID)
				if err != nil || !reflect.DeepEqual(lookedUp, results[i]) {
					t.Fatal("lookup changed expanded-kind result", lookedUp, err)
				}
			}
			replay, err := s.OperationalReplay(ctx, auth, proofEpoch, 0, 0)
			if err != nil || replay.HeadSequence != 3 || replay.NextSequence != 3 || len(replay.Events) != 3 {
				t.Fatal("expanded-kind replay missing events", replay, err)
			}
			for i, event := range replay.Events {
				if !reflect.DeepEqual(event, *results[i].Event) {
					t.Fatal("replay changed expanded-kind bytes", event)
				}
			}
			resurrection := operationalCommit(t, s, operationalIntent(auth, operationalWrite(kind, id, 3, `{}`)))
			if resurrection.Outcome != store.OperationalConflict || resurrection.HeadSequence != 3 || len(resurrection.Current) != 1 || !reflect.DeepEqual(resurrection.Current[0], results[2].Event.Entities[0]) {
				t.Fatal("expanded kind resurrected retained identity", resurrection)
			}
		})
	}
}

func TestOperationalProofAuthorityIsSeparateSignedAndImmutable(t *testing.T) {
	ctx := context.Background()
	s, id := testutil.Bound(t, t.TempDir())
	defer s.Close()
	auth := operationalTerminal(t, s)
	if _, err := s.OperationalProjectionSnapshot(ctx, auth, proofEpoch); !errors.Is(err, store.ErrOperationalAuthority) {
		t.Fatal("foundation binding granted proof authority", err)
	}
	var count int
	if err := s.DB.QueryRow("SELECT count(*) FROM op_authority").Scan(&count); err != nil || count != 0 {
		t.Fatal("migration created authority", count, err)
	}
	legacy, legacyTrust := testutil.Grant(t, id, time.Now().Unix(), time.Now().Unix()+600)
	if err := s.PinOperationalProofAuthority(ctx, legacy, legacyTrust); !errors.Is(err, store.ErrOperationalAuthority) {
		t.Fatal("foundation grant admitted as operational proof", err)
	}
	g, private := proofGrant(t, id)
	for _, name := range []string{"purpose", "mode", "version", "installation", "venue", "public-key", "zero-epoch", "overflow-epoch", "grant-id", "expired", "future", "long-validity", "tampered", "no-trust", "wrong-trust"} {
		t.Run(name, func(t *testing.T) {
			changed := g
			switch name {
			case "purpose":
				changed.Purpose = "vynic-edge-foundation"
			case "mode":
				changed.Mode = "PRODUCTION"
			case "version":
				changed.Version = 2
			case "installation":
				changed.InstallationID = uuid.NewString()
			case "venue":
				changed.VenueID = uuid.NewString()
			case "public-key":
				changed.PublicKey = store.Secret()
			case "zero-epoch":
				changed.AuthorityEpoch = 0
			case "overflow-epoch":
				changed.AuthorityEpoch = math.MaxUint64
			case "grant-id":
				changed.GrantID = "not-a-uuid"
			case "expired":
				changed.IssuedAt -= 700
				changed.ExpiresAt -= 700
			case "future":
				changed.IssuedAt += 60
				changed.ExpiresAt += 60
			case "long-validity":
				changed.ExpiresAt++
			}
			raw, trust := signProofGrant(t, changed, private)
			switch name {
			case "tampered":
				raw = "x" + raw
			case "no-trust":
				trust = nil
			case "wrong-trust":
				_, differentKey := proofGrant(t, id)
				_, trust = signProofGrant(t, changed, differentKey)
			}
			if err := s.PinOperationalProofAuthority(ctx, raw, trust); !errors.Is(err, store.ErrOperationalAuthority) {
				t.Fatal("invalid proof grant admitted", err)
			}
		})
	}
	raw, trust := signProofGrant(t, g, private)
	if err := s.PinOperationalProofAuthority(ctx, raw, trust); err != nil {
		t.Fatal(err)
	}
	if err := s.PinOperationalProofAuthority(ctx, raw, trust); err != nil {
		t.Fatal("same grant retry refused", err)
	}
	_, anotherSigner := proofGrant(t, id)
	resigned, differentTrust := signProofGrant(t, g, anotherSigner)
	if err := s.PinOperationalProofAuthority(ctx, resigned, differentTrust); !errors.Is(err, store.ErrOperationalAuthority) {
		t.Fatal("changed signer replaced pinned fixture trust", err)
	}
	g.AuthorityEpoch++
	changed, _ := signProofGrant(t, g, private)
	if err := s.PinOperationalProofAuthority(ctx, changed, trust); !errors.Is(err, store.ErrOperationalAuthority) {
		t.Fatal("changed grant advanced proof epoch", err)
	}
	snap := operationalSnapshot(t, s, auth)
	shadow, err := s.ProjectionSnapshot(ctx, 1)
	if err != nil || snap.Mode != store.OperationalProofMode || snap.Sequence != 0 || shadow.Mode != "SHADOW" {
		t.Fatal("proof changed Phase2A authority", snap, shadow, err)
	}
	// The legacy binding API may reissue a same-Venue foundation grant. The
	// existing proof pin must fail closed rather than silently adopting it.
	newBinding, newTrust := testutil.Grant(t, id, time.Now().Unix(), time.Now().Unix()+600)
	if err = s.Bind(newBinding, newTrust); err != nil {
		t.Fatal(err)
	}
	if _, err = s.OperationalProjectionSnapshot(ctx, auth, proofEpoch); !errors.Is(err, store.ErrOperationalAuthority) {
		t.Fatal("changed foundation binding retained proof rights", err)
	}
}

func TestOperationalProofAuthorityRequiresExistingFoundationBinding(t *testing.T) {
	s, err := store.Open(t.TempDir(), true)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	id, err := s.Init()
	if err != nil {
		t.Fatal(err)
	}
	id.VenueID = uuid.NewString()
	g, private := proofGrant(t, id)
	raw, trust := signProofGrant(t, g, private)
	if err = s.PinOperationalProofAuthority(context.Background(), raw, trust); !errors.Is(err, store.ErrOperationalAuthority) {
		t.Fatal("proof grant bypassed missing foundation binding", err)
	}
	restored, err := s.Identity()
	if err != nil || restored.VenueID != "" {
		t.Fatal("proof admission wrote foundation tenant binding", restored, err)
	}
}

func TestOperationalReadDependencyConflictAndImmutableExactResults(t *testing.T) {
	ctx := context.Background()
	s, _, a := boundProof(t, t.TempDir())
	defer s.Close()
	b := operationalTerminal(t, s)
	orderID, reservationID := uuid.NewString(), uuid.NewString()
	first := operationalIntent(a, operationalWrite(store.OperationalOrder, orderID, 0, `{"state":"open"}`), operationalWrite(store.OperationalReservation, reservationID, 0, `{"state":"booked"}`))
	first.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte(`{"action":"create"}`)}, {ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte(`{"target":"frozen-printer","bytes":"frozen"}`)}}
	first.ApplicationData = []byte(`{"correlation":"first"}`)
	accepted := operationalCommit(t, s, first)
	if accepted.Outcome != store.OperationalCommitted || accepted.Event.Sequence != 1 || len(accepted.Event.Entities) != 2 || len(accepted.Event.Effects) != 2 {
		t.Fatal(accepted)
	}
	stale := operationalIntent(a, operationalWrite(store.OperationalOrder, orderID, 1, `{"state":"activated"}`))
	stale.Reads = []store.OperationalRead{{Kind: store.OperationalReservation, ID: reservationID, ExpectedRevision: 1}}
	stale.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte(`{"action":"activate"}`)}}
	operationalCommit(t, s, operationalIntent(b, operationalWrite(store.OperationalReservation, reservationID, 1, `{"state":"cancelled"}`)))
	conflict := operationalCommit(t, s, stale)
	if conflict.Outcome != store.OperationalConflict || conflict.HeadSequence != 2 || conflict.Event != nil || len(conflict.Current) != 2 || conflict.Current[0].Kind != store.OperationalReservation || conflict.Current[0].Revision != 2 || conflict.Current[1].Revision != 1 {
		t.Fatal("read-only dependency did not fence write", conflict)
	}
	requests, events, effects := operationalCounts(t, s)
	if requests != 3 || events != 2 || effects != 2 {
		t.Fatal("conflict wrote state/effect or forgot exact result", requests, events, effects)
	}
	operationalCommit(t, s, operationalIntent(b, operationalWrite(store.OperationalOrder, orderID, 1, `{"state":"later"}`), operationalWrite(store.OperationalReservation, reservationID, 2, `{"state":"later"}`)))
	if retried := operationalCommit(t, s, stale); !reflect.DeepEqual(conflict, retried) {
		t.Fatal("persisted conflict changed after later edits", conflict, retried)
	}
	if retried := operationalCommit(t, s, first); !reflect.DeepEqual(accepted, retried) {
		t.Fatal("lost ACK success changed after later edits")
	}
	got, err := s.OperationalResult(ctx, a, proofEpoch, stale.RequestID)
	if err != nil || !reflect.DeepEqual(got, conflict) {
		t.Fatal("GetResult lost conflict", got, err)
	}
	for _, name := range []string{"revision", "invalid-revision", "empty-writes", "effect", "application-data", "other-terminal"} {
		t.Run(name, func(t *testing.T) {
			changed := operationalClone(t, first)
			switch name {
			case "revision":
				changed.Writes[0].ExpectedRevision = 1
			case "invalid-revision":
				changed.Writes[0].ExpectedRevision = math.MaxUint64
			case "empty-writes":
				changed.Writes = nil
			case "effect":
				changed.Effects[0].Payload = []byte("changed immutable payload")
			case "application-data":
				changed.ApplicationData = []byte("changed")
			case "other-terminal":
				changed.Auth = b
			}
			if _, err := s.CommitOperational(ctx, changed); !errors.Is(err, store.ErrRequestReuse) {
				t.Fatal("changed retry reached new intent/revision validation", err)
			}
		})
	}
}

func TestOperationalThreeClientsExactlyOneCASWinner(t *testing.T) {
	s, _, a := boundProof(t, t.TempDir())
	defer s.Close()
	clients := []store.OperationalAuth{a, operationalTerminal(t, s), operationalTerminal(t, s)}
	id := uuid.NewString()
	operationalCommit(t, s, operationalIntent(a, operationalWrite(store.OperationalOrder, id, 0, `{"state":"initial"}`)))
	requests := make([]*store.OperationalCommit, len(clients))
	for i, auth := range clients {
		requests[i] = operationalIntent(auth, operationalWrite(store.OperationalOrder, id, 1, `{"state":"edited"}`))
		requests[i].Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte("audit")}, {ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte("print")}}
	}
	type attempt struct {
		index  int
		result *store.OperationalCommitResult
		err    error
	}
	results := make(chan attempt, len(clients))
	var wg sync.WaitGroup
	for i, request := range requests {
		wg.Add(1)
		go func(index int, r *store.OperationalCommit) {
			defer wg.Done()
			result, err := s.CommitOperational(context.Background(), r)
			results <- attempt{index, result, err}
		}(i, request)
	}
	wg.Wait()
	close(results)
	winners := 0
	for attempt := range results {
		if attempt.err != nil {
			t.Fatal(attempt.err)
		}
		if attempt.result.Outcome == store.OperationalCommitted {
			winners++
		}
		if retried := operationalCommit(t, s, requests[attempt.index]); !reflect.DeepEqual(retried, attempt.result) {
			t.Fatal("concurrent client result changed on retry")
		}
	}
	snapshot := operationalSnapshot(t, s, a)
	requestCount, eventCount, effectCount := operationalCounts(t, s)
	if winners != 1 || snapshot.Sequence != 2 || len(snapshot.Entities) != 1 || snapshot.Entities[0].Revision != 2 || requestCount != 4 || eventCount != 2 || effectCount != 2 {
		t.Fatal("3-client CAS was not atomic", winners, snapshot, requestCount, eventCount, effectCount)
	}
}

func TestOperationalSnapshotAndReplayUseOneConsistentHeadDuringWrites(t *testing.T) {
	ctx := context.Background()
	s, _, auth := boundProof(t, t.TempDir())
	defer s.Close()
	id := uuid.NewString()
	operationalCommit(t, s, operationalIntent(auth, operationalWrite(store.OperationalOrder, id, 0, `{}`)))
	finished := make(chan error, 1)
	go func() {
		for revision := uint64(1); revision <= 20; revision++ {
			r := operationalIntent(auth, operationalWrite(store.OperationalOrder, id, revision, `{}`))
			if _, err := s.CommitOperational(ctx, r); err != nil {
				finished <- err
				return
			}
		}
		finished <- nil
	}()
	for i := 0; i < 20; i++ {
		snapshot := operationalSnapshot(t, s, auth)
		if len(snapshot.Entities) != 1 || snapshot.Entities[0].Revision != snapshot.Sequence {
			t.Fatal("snapshot mixed different commits", snapshot)
		}
		page, err := s.OperationalReplay(ctx, auth, proofEpoch, 0, 100)
		if err != nil || page.NextSequence != page.HeadSequence || len(page.Events) != int(page.HeadSequence) {
			t.Fatal("replay mixed head and events from different commits", page, err)
		}
		for _, event := range page.Events {
			if len(event.Entities) != 1 || event.Entities[0].Revision != event.Sequence {
				t.Fatal("event postimage did not match its committed sequence", event)
			}
		}
	}
	if err := <-finished; err != nil {
		t.Fatal(err)
	}
}

func TestOperationalLostACKRestartAndFrozenEightMiBRaster(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	s, _, auth := boundProof(t, dir)
	defer func() { s.Close() }()
	raster := bytes.Repeat([]byte{0xa5}, 8<<20)
	frozenPrint, err := json.Marshal(struct {
		Target string `json:"target"`
		Raster []byte `json:"raster"`
	}{"fixture-printer-only", raster})
	if err != nil || len(frozenPrint) > store.OperationalMaxEffectBytes {
		t.Fatal("8 MiB raster does not fit explicit proof effect bound", err)
	}
	id := uuid.NewString()
	request := operationalIntent(auth, operationalWrite(store.OperationalOrder, id, 0, `{"state":"committed"}`))
	request.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte("frozen audit")}, {ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: frozenPrint}}
	request.ApplicationData = []byte("correlation")
	originalRequest := operationalClone(t, request)
	accepted := operationalCommit(t, s, request)
	canonical, err := json.Marshal(accepted)
	if err != nil {
		t.Fatal(err)
	}
	var exact []byte
	if err = s.DB.QueryRow("SELECT result FROM op_request WHERE request_id=?", request.RequestID).Scan(&exact); err != nil || !bytes.Equal(canonical, exact) {
		t.Fatal("store did not persist exact canonical ACK", err)
	}
	// Mutating caller-owned slices after return cannot change stored/replayed
	// entities or effects. The store froze them before hashing/committing.
	request.Writes[0].Document[0] = 'x'
	request.Effects[1].Payload[0] = 'x'
	if !bytes.Equal(accepted.Event.Effects[1].Payload, originalRequest.Effects[1].Payload) {
		t.Fatal("returned result aliases caller print payload")
	}
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	s, err = store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	retry := operationalCommit(t, s, originalRequest)
	if !reflect.DeepEqual(retry, accepted) {
		t.Fatal("restart forgot exact lost ACK result")
	}
	result, err := s.OperationalResult(ctx, auth, proofEpoch, request.RequestID)
	if err != nil || !reflect.DeepEqual(result, accepted) {
		t.Fatal("restart GetResult changed success", err)
	}
	replayed, err := s.OperationalReplay(ctx, auth, proofEpoch, 0, 0)
	if err != nil || replayed.HeadSequence != 1 || replayed.NextSequence != 1 || len(replayed.Events) != 1 || !bytes.Equal(replayed.Events[0].Effects[1].Payload, originalRequest.Effects[1].Payload) {
		t.Fatal("frozen print payload did not survive restart/replay", err)
	}
	if !bytes.Equal(operationalSnapshot(t, s, auth).Entities[0].Document, originalRequest.Writes[0].Document) {
		t.Fatal("caller mutation changed projection")
	}
	for revision := uint64(1); revision < 3; revision++ {
		r := operationalIntent(auth, operationalWrite(store.OperationalOrder, id, revision, `{"state":"later"}`))
		r.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: originalRequest.Effects[1].Payload}}
		operationalCommit(t, s, r)
	}
	page, err := s.OperationalReplay(ctx, auth, proofEpoch, 0, 100)
	if err != nil || page.HeadSequence != 3 || page.NextSequence != 2 || len(page.Events) != 2 {
		t.Fatal("large-event replay was not byte bounded", page, err)
	}
	encodedPage, err := json.Marshal(page)
	if err != nil || len(encodedPage) > store.OperationalMaxReplayBytes {
		t.Fatal("replay exceeded encoded page bound", len(encodedPage), err)
	}
	lastPage, err := s.OperationalReplay(ctx, auth, proofEpoch, page.NextSequence, 100)
	if err != nil || len(lastPage.Events) != 1 || lastPage.NextSequence != 3 {
		t.Fatal("byte-bounded replay skipped event", lastPage, err)
	}
}

func TestOperationalAtomicRollbackOfPostimagesEventsEffectsAndResult(t *testing.T) {
	for _, table := range []string{"op_entity", "op_event", "op_effect", "op_request", "op_authority"} {
		t.Run(table, func(t *testing.T) {
			s, _, auth := boundProof(t, t.TempDir())
			defer s.Close()
			action := "INSERT"
			if table == "op_authority" {
				action = "UPDATE"
			}
			if _, err := s.DB.Exec("CREATE TRIGGER fail_operational_write BEFORE " + action + " ON " + table + " BEGIN SELECT RAISE(ABORT,'injected durable write failure'); END"); err != nil {
				t.Fatal(err)
			}
			r := operationalIntent(auth, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{"state":"new"}`), operationalWrite(store.OperationalTable, uuid.NewString(), 0, `{"state":"occupied"}`))
			r.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte("audit")}, {ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte("print")}}
			if result, err := s.CommitOperational(context.Background(), r); err == nil || result != nil {
				t.Fatal("false ACK after injected write failure", result, err)
			}
			snapshot := operationalSnapshot(t, s, auth)
			requests, events, effects := operationalCounts(t, s)
			if snapshot.Sequence != 0 || len(snapshot.Entities) != 0 || requests != 0 || events != 0 || effects != 0 {
				t.Fatal("partial operational transaction", snapshot, requests, events, effects)
			}
			if _, err := s.OperationalResult(context.Background(), auth, proofEpoch, r.RequestID); !errors.Is(err, store.ErrOperationalResultNotFound) {
				t.Fatal("rolled-back request was reported durable", err)
			}
			if _, err := s.DB.Exec("DROP TRIGGER fail_operational_write"); err != nil {
				t.Fatal(err)
			}
			if result := operationalCommit(t, s, r); result.HeadSequence != 1 {
				t.Fatal("retry after rollback did not use original sequence", result)
			}
		})
	}
}

func TestOperationalWrongEpochTerminalAndTransactionalRevocation(t *testing.T) {
	ctx := context.Background()
	s, _, a := boundProof(t, t.TempDir())
	defer s.Close()
	b := operationalTerminal(t, s)
	r := operationalIntent(a, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{"state":"open"}`))
	accepted := operationalCommit(t, s, r)
	if result, err := s.OperationalResult(ctx, b, proofEpoch, r.RequestID); !errors.Is(err, store.ErrOperationalResultNotFound) || result != nil {
		t.Fatal("another terminal read result", result, err)
	}
	for _, epoch := range []uint64{0, proofEpoch - 1, proofEpoch + 1, math.MaxUint64} {
		changed := operationalClone(t, r)
		changed.AuthorityEpoch = epoch
		if _, err := s.CommitOperational(ctx, changed); !errors.Is(err, store.ErrOperationalEpoch) {
			t.Fatal("retry bypassed epoch fence", epoch, err)
		}
		if _, err := s.OperationalResult(ctx, a, epoch, r.RequestID); !errors.Is(err, store.ErrOperationalEpoch) {
			t.Fatal("GetResult bypassed epoch fence", epoch, err)
		}
		if _, err := s.OperationalProjectionSnapshot(ctx, a, epoch); !errors.Is(err, store.ErrOperationalEpoch) {
			t.Fatal("snapshot bypassed epoch fence", epoch, err)
		}
		if _, err := s.OperationalReplay(ctx, a, epoch, 0, 1); !errors.Is(err, store.ErrOperationalEpoch) {
			t.Fatal("replay bypassed epoch fence", epoch, err)
		}
	}
	for _, wrong := range []store.OperationalAuth{{TerminalID: uuid.NewString(), TerminalSecret: store.Secret()}, {TerminalID: a.TerminalID, TerminalSecret: store.Secret()}} {
		changed := operationalClone(t, r)
		changed.Auth = wrong
		if _, err := s.CommitOperational(ctx, changed); !errors.Is(err, store.ErrDenied) {
			t.Fatal("unknown terminal/wrong secret admitted", err)
		}
	}
	// A successful earlier transport check must not authorize a later commit.
	if err := s.Authenticate(ctx, a.TerminalID, a.TerminalSecret); err != nil {
		t.Fatal(err)
	}
	if err := s.Revoke(a.TerminalID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CommitOperational(ctx, r); !errors.Is(err, store.ErrDenied) {
		t.Fatal("revoked terminal retried a stored result", err)
	}
	fresh := operationalIntent(a, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{"state":"denied"}`))
	if _, err := s.CommitOperational(ctx, fresh); !errors.Is(err, store.ErrDenied) {
		t.Fatal("stale transport authentication authorized commit", err)
	}
	if _, err := s.OperationalResult(ctx, a, proofEpoch, r.RequestID); !errors.Is(err, store.ErrDenied) {
		t.Fatal("revoked terminal read result", err)
	}
	if _, err := s.OperationalProjectionSnapshot(ctx, a, proofEpoch); !errors.Is(err, store.ErrDenied) {
		t.Fatal("revoked terminal read snapshot", err)
	}
	if _, err := s.OperationalReplay(ctx, a, proofEpoch, 0, 1); !errors.Is(err, store.ErrDenied) {
		t.Fatal("revoked terminal read replay", err)
	}
	snapshot := operationalSnapshot(t, s, b)
	if snapshot.Sequence != accepted.HeadSequence || len(snapshot.Entities) != 1 {
		t.Fatal("denied commit changed state", snapshot)
	}
}

func TestOperationalTombstonesRetainIdentityAndCapacity(t *testing.T) {
	s, _, auth := boundProof(t, t.TempDir())
	defer s.Close()
	ids := make([]string, store.OperationalMaxEntities)
	for i := range ids {
		ids[i] = uuid.NewString()
	}
	for start := 0; start < len(ids); start += store.OperationalMaxWrites {
		writes := make([]store.OperationalWrite, 0, store.OperationalMaxWrites)
		for _, id := range ids[start : start+store.OperationalMaxWrites] {
			writes = append(writes, operationalWrite(store.OperationalOrder, id, 0, `{"state":"live"}`))
		}
		operationalCommit(t, s, operationalIntent(auth, writes...))
	}
	var last *store.OperationalCommit
	var lastResult *store.OperationalCommitResult
	for start := 0; start < len(ids); start += store.OperationalMaxWrites {
		writes := make([]store.OperationalWrite, 0, store.OperationalMaxWrites)
		for _, id := range ids[start : start+store.OperationalMaxWrites] {
			writes = append(writes, store.OperationalWrite{Kind: store.OperationalOrder, ID: id, ExpectedRevision: 1, Tombstone: true})
		}
		last = operationalIntent(auth, writes...)
		lastResult = operationalCommit(t, s, last)
	}
	snapshot := operationalSnapshot(t, s, auth)
	if len(snapshot.Entities) != store.OperationalMaxEntities {
		t.Fatal("deletion released retained identity capacity", len(snapshot.Entities))
	}
	for _, e := range snapshot.Entities {
		if !e.Tombstone || e.Revision != 2 || len(e.Document) != 0 {
			t.Fatal("invalid retained tombstone", e)
		}
	}
	beforeRequests, beforeEvents, beforeEffects := operationalCounts(t, s)
	overflow := operationalIntent(auth, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{}`))
	overflow.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte("never dispatched")}}
	if result, err := s.CommitOperational(context.Background(), overflow); !errors.Is(err, store.ErrOperationalCapacity) || result != nil {
		t.Fatal("tombstones did not count toward entity capacity", result, err)
	}
	requests, events, effects := operationalCounts(t, s)
	if requests != beforeRequests || events != beforeEvents || effects != beforeEffects || operationalSnapshot(t, s, auth).Sequence != snapshot.Sequence {
		t.Fatal("capacity refusal left partial commit")
	}
	if retry := operationalCommit(t, s, last); !reflect.DeepEqual(retry, lastResult) {
		t.Fatal("retained capacity blocked exact ACK retry")
	}
	resurrection := operationalCommit(t, s, operationalIntent(auth, operationalWrite(store.OperationalOrder, ids[0], 2, `{"state":"resurrected"}`)))
	if resurrection.Outcome != store.OperationalConflict || len(resurrection.Current) != 1 || !resurrection.Current[0].Tombstone || resurrection.HeadSequence != snapshot.Sequence {
		t.Fatal("same-ID resurrection admitted", resurrection)
	}
	// Tombstones can be read dependencies: a decision based on retained absence
	// is distinct from an expectation that an identity has never existed.
	readTombstone := operationalIntent(auth, store.OperationalWrite{Kind: store.OperationalOrder, ID: ids[1], ExpectedRevision: 2, Tombstone: true})
	readTombstone.Reads = []store.OperationalRead{{Kind: store.OperationalOrder, ID: ids[0], ExpectedRevision: 2, ExpectedTombstone: true}}
	if result := operationalCommit(t, s, readTombstone); result.Outcome != store.OperationalConflict {
		t.Fatal("writing an already deleted entity was admitted", result)
	}
}

func TestOperationalSequenceRevisionAndInputBounds(t *testing.T) {
	t.Run("sequence-overflow", func(t *testing.T) {
		s, _, auth := boundProof(t, t.TempDir())
		defer s.Close()
		// Boundary injection restores the exact migration-owned trigger before
		// exercising the API; the proof exposes no head/epoch mutation method.
		var ddl string
		if err := s.DB.QueryRow("SELECT sql FROM sqlite_master WHERE name='op_authority_update'").Scan(&ddl); err != nil {
			t.Fatal(err)
		}
		for _, q := range []string{"DROP TRIGGER op_authority_update", "UPDATE op_authority SET sequence=9223372036854775807", ddl} {
			if _, err := s.DB.Exec(q); err != nil {
				t.Fatal(err)
			}
		}
		r := operationalIntent(auth, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{}`))
		if result, err := s.CommitOperational(context.Background(), r); !errors.Is(err, store.ErrOperationalCapacity) || result != nil {
			t.Fatal("overflowed durable sequence", result, err)
		}
		if _, err := s.DB.Exec("UPDATE op_authority SET sequence=sequence+1"); err == nil {
			t.Fatal("SQLite numeric overflow escaped integer sequence constraint")
		}
		requests, events, effects := operationalCounts(t, s)
		if requests != 0 || events != 0 || effects != 0 {
			t.Fatal("overflow left durable records", requests, events, effects)
		}
	})
	t.Run("revision-overflow", func(t *testing.T) {
		s, _, auth := boundProof(t, t.TempDir())
		defer s.Close()
		id := uuid.NewString()
		if _, err := s.DB.Exec("INSERT INTO op_entity(kind,id,revision,tombstone,document) VALUES('ORDER',?,9223372036854775807,0,?)", id, []byte(`{}`)); err != nil {
			t.Fatal(err)
		}
		r := operationalIntent(auth, operationalWrite(store.OperationalOrder, id, math.MaxInt64, `{}`))
		if _, err := s.CommitOperational(context.Background(), r); !errors.Is(err, store.ErrOperationalIntent) {
			t.Fatal("entity revision could overflow", err)
		}
		if _, err := s.DB.Exec("UPDATE op_entity SET revision=revision+1 WHERE id=?", id); err == nil {
			t.Fatal("SQLite numeric overflow escaped integer revision constraint")
		}
	})
	t.Run("request-and-document-bounds", func(t *testing.T) {
		s, _, auth := boundProof(t, t.TempDir())
		defer s.Close()
		for _, name := range []string{"document", "effect", "application-data", "invalid-json", "unknown-write-kind", "unknown-read-kind", "non-canonical-id", "duplicate-write", "duplicate-read", "inconsistent-read-write", "duplicate-effect"} {
			t.Run(name, func(t *testing.T) {
				r := operationalIntent(auth, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{}`))
				switch name {
				case "document":
					r.Writes[0].Document = bytes.Repeat([]byte{'a'}, store.OperationalMaxDocumentBytes+1)
				case "effect":
					r.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: bytes.Repeat([]byte{'a'}, store.OperationalMaxEffectBytes+1)}}
				case "application-data":
					r.ApplicationData = bytes.Repeat([]byte{'a'}, store.OperationalMaxApplicationBytes+1)
				case "invalid-json":
					r.Writes[0].Document = []byte(`[]`)
				case "unknown-write-kind":
					r.Writes[0].Kind = "FUTURE_KIND"
				case "unknown-read-kind":
					r.Reads = []store.OperationalRead{{Kind: "FUTURE_KIND", ID: uuid.NewString()}}
				case "non-canonical-id":
					r.Writes[0].Kind = store.OperationalControl
					r.Writes[0].ID = "venue-control"
				case "duplicate-write":
					r.Writes = append(r.Writes, r.Writes[0])
				case "duplicate-read":
					d := store.OperationalRead{Kind: store.OperationalTable, ID: uuid.NewString()}
					r.Reads = []store.OperationalRead{d, d}
				case "inconsistent-read-write":
					r.Reads = []store.OperationalRead{{Kind: r.Writes[0].Kind, ID: r.Writes[0].ID, ExpectedRevision: 1}}
				case "duplicate-effect":
					e := store.OperationalEffect{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte("audit")}
					r.Effects = []store.OperationalEffect{e, e}
				}
				if _, err := s.CommitOperational(context.Background(), r); !errors.Is(err, store.ErrOperationalIntent) {
					t.Fatal("invalid bounded intent admitted", err)
				}
			})
		}
		if _, err := s.OperationalReplay(context.Background(), auth, proofEpoch, math.MaxUint64, 1); !errors.Is(err, store.ErrOperationalIntent) {
			t.Fatal("overflow cursor admitted", err)
		}
		if _, err := s.OperationalReplay(context.Background(), auth, proofEpoch, 0, 101); !errors.Is(err, store.ErrOperationalIntent) {
			t.Fatal("overflow replay limit admitted", err)
		}
		if _, err := s.OperationalReplay(context.Background(), auth, proofEpoch, 1, 1); !errors.Is(err, store.ErrOperationalIntent) {
			t.Fatal("cursor beyond head admitted", err)
		}
		requests, events, effects := operationalCounts(t, s)
		if requests != 0 || events != 0 || effects != 0 {
			t.Fatal("invalid input wrote records", requests, events, effects)
		}
	})
}

func TestOperationalMigrationPreservesPopulatedPhase2A(t *testing.T) {
	dir := t.TempDir()
	s, identity := testutil.Bound(t, dir)
	a := terminal(t, s)
	request := intent(a, order(uuid.NewString(), uuid.NewString(), []string{}, 0))
	accepted := commit(t, s, request)
	operationalDropEmptyQueueFixture(t, s.DB)
	for _, q := range []string{"DROP TABLE op_effect", "DROP TABLE op_event", "DROP TABLE op_request", "DROP TABLE op_entity", "DROP TABLE op_authority", "DELETE FROM schema_migration WHERE version>=3", "PRAGMA user_version=2"} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	s, err := store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	restored, err := s.Identity()
	if err != nil || restored.InstallationID != identity.InstallationID || restored.VenueID != identity.VenueID {
		t.Fatal("migration changed installation binding", restored, err)
	}
	if retried := commit(t, s, request); !proto.Equal(retried, accepted) {
		t.Fatal("migration changed Phase2A exact result")
	}
	var authorities, ledger, version int
	if err = s.DB.QueryRow("SELECT count(*) FROM op_authority").Scan(&authorities); err != nil {
		t.Fatal(err)
	}
	if err = s.DB.QueryRow("SELECT count(*) FROM schema_migration").Scan(&ledger); err != nil {
		t.Fatal(err)
	}
	if err = s.DB.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		t.Fatal(err)
	}
	if authorities != 0 || ledger != store.SchemaVersion || version != store.SchemaVersion {
		t.Fatal("additive upgrade promoted authority or lost migration ledger", authorities, ledger, version)
	}
}

var operationalFixtureTables = []string{"installation", "pairing_ticket", "terminal", "session", "coordination", "projection", "committed_event", "request_result", "op_authority", "op_entity", "op_request", "op_event", "op_effect"}

// Fixture construction removes only empty future-schema tables. Production
// never offers a database downgrade or discards retained queue evidence.
func operationalDropEmptyQueueFixture(t *testing.T, db *sql.DB) {
	t.Helper()
	for _, name := range []string{"op_terminal_origin", "pq_beep", "pq_attempt", "pq_claim", "pq_receipt", "pq_job", "pq_alias", "pq_registry"} {
		var count int
		if err := db.QueryRow("SELECT count(*) FROM " + name).Scan(&count); err != nil || count != 0 {
			t.Fatal("legacy fixture cannot discard print queue records", name, count, err)
		}
		if _, err := db.Exec("DROP TABLE " + name); err != nil {
			t.Fatal(err)
		}
	}
}

func operationalQueryRows(t *testing.T, db *sql.DB, query string) [][]any {
	t.Helper()
	rows, err := db.Query(query)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	columns, err := rows.Columns()
	if err != nil {
		t.Fatal(err)
	}
	var result [][]any
	for rows.Next() {
		values := make([]any, len(columns))
		targets := make([]any, len(columns))
		for i := range values {
			targets[i] = &values[i]
		}
		if err = rows.Scan(targets...); err != nil {
			t.Fatal(err)
		}
		for i, value := range values {
			if b, ok := value.([]byte); ok {
				values[i] = append([]byte{}, b...)
			}
		}
		result = append(result, values)
	}
	if err = rows.Err(); err != nil {
		t.Fatal(err)
	}
	return result
}

func operationalStoredRows(t *testing.T, db *sql.DB) map[string][][]any {
	t.Helper()
	result := make(map[string][][]any)
	for _, table := range operationalFixtureTables {
		result[table] = operationalQueryRows(t, db, "SELECT * FROM "+table+" ORDER BY 1,2")
	}
	return result
}

// Construct a real schema-3 fixture from original migrations 001..003 and
// copied old-kind records. This is test setup, never a state downgrade API.
func operationalSchema3Fixture(t *testing.T, sourceDir string) (string, *sql.DB) {
	t.Helper()
	dir := t.TempDir()
	db, err := sql.Open("sqlite", filepath.Join(dir, "edge.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	db.SetMaxOpenConns(1)
	if _, err = db.Exec("PRAGMA foreign_keys=ON"); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec("ATTACH DATABASE ? AS fixture", filepath.Join(sourceDir, "edge.db")); err != nil {
		t.Fatal(err)
	}
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if _, err = tx.Exec("CREATE TABLE schema_migration(version INTEGER PRIMARY KEY, checksum TEXT NOT NULL)"); err != nil {
		t.Fatal(err)
	}
	for i, name := range []string{"001_foundation.sql", "002_orders_tables.sql", "003_operational_coordination.sql"} {
		migration, err := os.ReadFile(filepath.Join("migrations", name))
		if err != nil {
			t.Fatal(err)
		}
		if _, err = tx.Exec(string(migration)); err != nil {
			t.Fatal(err)
		}
		checksum := sha256.Sum256(migration)
		if _, err = tx.Exec("INSERT INTO schema_migration VALUES(?,?)", i+1, hex.EncodeToString(checksum[:])); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = tx.Exec("DELETE FROM coordination"); err != nil {
		t.Fatal(err)
	}
	for _, table := range operationalFixtureTables {
		if _, err = tx.Exec("INSERT INTO " + table + " SELECT * FROM fixture." + table); err != nil {
			t.Fatal(err)
		}
	}
	for _, query := range []string{"PRAGMA application_id=1448693321", "PRAGMA user_version=3"} {
		if _, err = tx.Exec(query); err != nil {
			t.Fatal(err)
		}
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec("DETACH DATABASE fixture"); err != nil {
		t.Fatal(err)
	}
	return dir, db
}

func TestOperationalMigrationPreservesPopulatedSchema3AndGuards(t *testing.T) {
	ctx := context.Background()
	sourceDir := t.TempDir()
	s, identity, auth := boundProof(t, sourceDir)
	shadowAuth := terminal(t, s)
	shadowRequest := intent(shadowAuth, order(uuid.NewString(), uuid.NewString(), []string{}, 0))
	shadowResult := commit(t, s, shadowRequest)
	writes := make([]store.OperationalWrite, 0, 6)
	for _, kind := range []store.OperationalEntityKind{store.OperationalOrder, store.OperationalTable, store.OperationalReservation, store.OperationalPackage, store.OperationalSale, store.OperationalDay} {
		writes = append(writes, operationalWrite(kind, uuid.NewString(), 0, " {\n \"opaque\": \"ქართული\", \"value\": 1 }\n"))
	}
	create := operationalIntent(auth, writes...)
	create.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte(`{"audit":"frozen"}`)}, {ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte{0, 0xff, 0x1b, 0x40}}}
	created := operationalCommit(t, s, create)
	change := operationalIntent(auth, operationalWrite(store.OperationalOrder, writes[0].ID, 1, `{"updated":true}`), store.OperationalWrite{Kind: store.OperationalDay, ID: writes[5].ID, ExpectedRevision: 1, Tombstone: true})
	changed := operationalCommit(t, s, change)
	stale := operationalIntent(auth, operationalWrite(store.OperationalOrder, writes[0].ID, 1, `{}`))
	conflicted := operationalCommit(t, s, stale)
	if conflicted.Outcome != store.OperationalConflict {
		t.Fatal("schema-3 fixture lacks stored conflict", conflicted)
	}
	wantSnapshot := operationalSnapshot(t, s, auth)
	wantReplay, err := s.OperationalReplay(ctx, auth, proofEpoch, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	dir, db := operationalSchema3Fixture(t, sourceDir)
	wantRows := operationalStoredRows(t, db)
	wantTriggers := operationalQueryRows(t, db, "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
	if err = db.Close(); err != nil {
		t.Fatal(err)
	}
	s, err = store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if !reflect.DeepEqual(operationalStoredRows(t, s.DB), wantRows) {
		t.Fatal("schema-4 migration changed stored identity, revisions, tombstones or frozen bytes")
	}
	// Schemas 5/6 add queue/origin guards; every preexisting guard must still
	// match the exact original definition captured from the schema-3 fixture.
	if !reflect.DeepEqual(operationalQueryRows(t, s.DB, "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND substr(name,1,3)!='pq_' AND name NOT IN ('op_terminal_origin_update','op_terminal_origin_delete') ORDER BY name"), wantTriggers) {
		t.Fatal("schema-4 migration changed immutable guards")
	}
	restored, err := s.Identity()
	if err != nil || !reflect.DeepEqual(restored, identity) {
		t.Fatal("schema-4 migration changed binding", restored, err)
	}
	if !reflect.DeepEqual(operationalSnapshot(t, s, auth), wantSnapshot) {
		t.Fatal("schema-4 migration changed proof snapshot")
	}
	replay, err := s.OperationalReplay(ctx, auth, proofEpoch, 0, 0)
	if err != nil || !reflect.DeepEqual(replay, wantReplay) {
		t.Fatal("schema-4 migration changed exact replay", replay, err)
	}
	for i, request := range []*store.OperationalCommit{create, change, stale} {
		if retried := operationalCommit(t, s, request); !reflect.DeepEqual(retried, []*store.OperationalCommitResult{created, changed, conflicted}[i]) {
			t.Fatal("schema-4 migration changed immutable result", retried)
		}
	}
	if retried := commit(t, s, shadowRequest); !proto.Equal(retried, shadowResult) {
		t.Fatal("schema-4 migration changed Phase2A result")
	}
	for _, query := range []string{
		"UPDATE op_authority SET sequence=sequence", "UPDATE op_authority SET venue_id='changed',sequence=sequence+1", "DELETE FROM op_authority",
		"UPDATE op_entity SET revision=revision", "UPDATE op_entity SET kind='EXPENSE',revision=revision+1 WHERE kind='ORDER'", "UPDATE op_entity SET id='changed',revision=revision+1 WHERE kind='ORDER'", "UPDATE op_entity SET tombstone=0,document=x'7b7d',revision=revision+1 WHERE tombstone=1", "DELETE FROM op_entity",
		"UPDATE op_request SET result=result", "DELETE FROM op_request", "UPDATE op_event SET event=event", "DELETE FROM op_event", "UPDATE op_effect SET payload=payload", "DELETE FROM op_effect",
	} {
		if _, err = s.DB.Exec(query); err == nil {
			t.Fatal("migration weakened immutable guard", query)
		}
	}
	if !reflect.DeepEqual(operationalStoredRows(t, s.DB), wantRows) {
		t.Fatal("rejected immutable writes changed rows")
	}
	var version, ledger int
	if err = s.DB.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		t.Fatal(err)
	}
	if err = s.DB.QueryRow("SELECT count(*) FROM schema_migration").Scan(&ledger); err != nil {
		t.Fatal(err)
	}
	if version != store.SchemaVersion || ledger != store.SchemaVersion {
		t.Fatal("migration did not retain contiguous current-schema ledger", version, ledger)
	}
	if result := operationalCommit(t, s, operationalIntent(auth, operationalWrite(store.OperationalControl, uuid.NewString(), 0, `{}`))); result.Outcome != store.OperationalCommitted {
		t.Fatal("upgraded fixture rejected expanded kind", result)
	}
}

func TestOperationalSchema4MigrationRejectsEntitySchemaDrift(t *testing.T) {
	sourceDir := t.TempDir()
	s, _, auth := boundProof(t, sourceDir)
	operationalCommit(t, s, operationalIntent(auth, operationalWrite(store.OperationalOrder, uuid.NewString(), 0, `{"preserved":true}`)))
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	for _, mutation := range []string{
		"DROP TRIGGER op_entity_update", "DROP TRIGGER op_entity_delete",
		"DROP TRIGGER op_entity_update; CREATE TRIGGER op_entity_update BEFORE UPDATE ON op_entity BEGIN SELECT 1; END",
		"CREATE TRIGGER unexpected_entity_trigger BEFORE UPDATE ON op_entity BEGIN SELECT 1; END",
		"ALTER TABLE op_entity ADD COLUMN unexpected TEXT", "CREATE INDEX unexpected_entity_index ON op_entity(revision)",
	} {
		t.Run(mutation, func(t *testing.T) {
			dir, db := operationalSchema3Fixture(t, sourceDir)
			if _, err := db.Exec(mutation); err != nil {
				t.Fatal(err)
			}
			wantRows := operationalStoredRows(t, db)
			wantShape := operationalQueryRows(t, db, "SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")
			if err := db.Close(); err != nil {
				t.Fatal(err)
			}
			if upgraded, err := store.Open(dir, false); err == nil {
				upgraded.Close()
				t.Fatal("migration silently repaired or discarded schema drift")
			}
			db, err := sql.Open("sqlite", filepath.Join(dir, "edge.db"))
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()
			if !reflect.DeepEqual(operationalStoredRows(t, db), wantRows) || !reflect.DeepEqual(operationalQueryRows(t, db, "SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name"), wantShape) {
				t.Fatal("failed migration changed schema or exact records")
			}
			var version, ledger int
			if err = db.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
				t.Fatal(err)
			}
			if err = db.QueryRow("SELECT count(*) FROM schema_migration").Scan(&ledger); err != nil {
				t.Fatal(err)
			}
			if version != 3 || ledger != 3 {
				t.Fatal("failed migration advanced schema or ledger", version, ledger)
			}
		})
	}
}

func TestOperationalCrashWorker(t *testing.T) {
	dir := os.Getenv("VYNIC_OPERATIONAL_CRASH_DIR")
	if dir == "" {
		t.Skip("subprocess only")
	}
	s, err := store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	auth := operationalTerminal(t, s)
	id := os.Getenv("VYNIC_OPERATIONAL_ENTITY_ID")
	r := operationalIntent(auth, operationalWrite(store.OperationalOrder, id, 0, `{"state":"committed"}`))
	r.Effects = []store.OperationalEffect{{ID: uuid.NewString(), Kind: store.OperationalAudit, Payload: []byte("durable audit")}, {ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte("durable frozen print")}}
	operationalCommit(t, s, r)
	tx, err := s.DB.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec("UPDATE op_entity SET revision=revision+1,document=? WHERE id=?", []byte(`{"state":"uncommitted"}`), id); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec("UPDATE op_authority SET sequence=sequence+1"); err != nil {
		t.Fatal(err)
	}
	os.Exit(17)
}

func TestOperationalCrashRecoversWholeCommitAndRollsBackOpenTransaction(t *testing.T) {
	dir := t.TempDir()
	s, _, auth := boundProof(t, dir)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	id := uuid.NewString()
	cmd := exec.Command(os.Args[0], "-test.run=^TestOperationalCrashWorker$")
	cmd.Env = append(os.Environ(), "VYNIC_OPERATIONAL_CRASH_DIR="+dir, "VYNIC_OPERATIONAL_ENTITY_ID="+id)
	var exit *exec.ExitError
	if output, err := cmd.CombinedOutput(); !errors.As(err, &exit) || exit.ExitCode() != 17 {
		t.Fatalf("worker did not interrupt transaction: %s %v", output, err)
	}
	s, err := store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	snapshot := operationalSnapshot(t, s, auth)
	requests, events, effects := operationalCounts(t, s)
	if snapshot.Sequence != 1 || len(snapshot.Entities) != 1 || snapshot.Entities[0].Revision != 1 || !bytes.Equal(snapshot.Entities[0].Document, []byte(`{"state":"committed"}`)) || requests != 1 || events != 1 || effects != 2 {
		t.Fatal("crash recovered a partial/uncommitted transaction", snapshot, requests, events, effects)
	}
}
