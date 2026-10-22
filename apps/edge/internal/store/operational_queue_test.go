package store_test

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/google/uuid"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

type queueProofFixture struct {
	s        *store.Store
	id       store.Identity
	auth     store.OperationalAuth
	origin   store.OperationalProofOriginGrant
	raw      string
	trust    []byte
	signer   ed25519.PrivateKey
	registry printqueue.Registry
}

func queueProof(t *testing.T, dir string) queueProofFixture {
	t.Helper()
	s, id := testutil.Bound(t, dir)
	g, signer := proofGrant(t, id)
	raw, trust := signProofGrant(t, g, signer)
	if err := s.PinOperationalProofAuthority(context.Background(), raw, trust); err != nil {
		t.Fatal(err)
	}
	auth := operationalTerminal(t, s)
	ca := sha256.Sum256([]byte("isolated synthetic CA digest; no network credential"))
	auth.OriginInstallationID = uuid.NewString()
	auth.ClientCASHA256 = ca[:]
	grantHash := sha256.Sum256([]byte(raw))
	now := time.Now().Unix()
	origin := store.OperationalProofOriginGrant{Version: 1, Purpose: store.OperationalProofOriginPurpose, Mode: store.OperationalProofMode, GrantID: uuid.NewString(), VenueID: id.VenueID, InstallationID: id.InstallationID, TerminalID: auth.TerminalID, OriginInstallationID: auth.OriginInstallationID, AuthorityEpoch: proofEpoch, ClientCASHA256: hex.EncodeToString(ca[:]), AuthorityGrantSHA256: hex.EncodeToString(grantHash[:]), IssuedAt: now, ExpiresAt: now + 600}
	encoded := signOrigin(t, origin, signer)
	if err := s.BindOperationalProofOrigin(context.Background(), auth, encoded, trust); err != nil {
		t.Fatal(err)
	}
	physical, device, worker, alias := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	registry := printqueue.Registry{PhysicalPrinterID: physical, VenueID: id.VenueID, InstallationID: id.InstallationID, DeviceID: device, WorkerHostID: worker, AuthorityEpoch: proofEpoch, BindingRevision: 1, ConfigRevision: 1, RegistryRevision: 1, Aliases: []string{alias}, Destination: printtransport.Destination{PhysicalPrinterID: physical, WorkerHostID: worker, Transport: printtransport.TCP, Host: "192.168.50.10", Port: 9100}}
	q, err := printqueue.NewProofStore(context.Background(), s.DB, printqueue.GatewayIdentity{VenueID: id.VenueID, InstallationID: id.InstallationID, DeviceID: device, WorkerHostID: worker, Epoch: proofEpoch})
	if err != nil {
		t.Fatal(err)
	}
	if err = q.Register(context.Background(), registry); err != nil {
		t.Fatal(err)
	}
	return queueProofFixture{s: s, id: id, auth: auth, origin: origin, raw: encoded, trust: trust, signer: signer, registry: registry}
}

func signOrigin(t *testing.T, g store.OperationalProofOriginGrant, signer ed25519.PrivateKey) string {
	t.Helper()
	encoded, err := json.Marshal(g)
	if err != nil {
		t.Fatal(err)
	}
	payload := base64.RawURLEncoding.EncodeToString(encoded)
	return payload + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(signer, []byte(payload)))
}

func queuedIntent(t *testing.T, f queueProofFixture) *store.OperationalCommit {
	t.Helper()
	r := operationalIntent(f.auth, operationalWrite(store.OperationalControl, uuid.NewString(), 0, `{"lastOrderId":1}`))
	r.PrintAdmission = store.OperationalPrintAdmission
	r.OriginInstallationID = f.auth.OriginInstallationID
	job := frozenQueueJob(t, f, r.RequestID, uuid.NewString())
	r.Effects = []store.OperationalEffect{{ID: job.EffectID, Kind: store.OperationalPrint, Payload: job.Raw()}}
	return r
}

func frozenQueueJob(t *testing.T, f queueProofFixture, request, effect string) printqueue.FrozenJob {
	t.Helper()
	primary := []byte{0x1b, 0x40, 0xff, 0, 0x1d, 0x56, 0}
	digest := sha256.Sum256(primary)
	r := f.registry
	d := r.Destination
	d.DocumentName = "synthetic immutable proof"
	j := printqueue.FrozenJob{Version: 1, JobID: uuid.NewString(), EffectID: effect, RequestID: request, TerminalID: f.auth.TerminalID, VenueID: f.id.VenueID, InstallationID: f.id.InstallationID, OriginInstallationID: f.auth.OriginInstallationID, DeviceID: r.DeviceID, PhysicalPrinterID: r.PhysicalPrinterID, AliasID: r.Aliases[0], AttemptID: uuid.NewString(), BeepAttemptID: uuid.NewString(), AuthorityEpoch: proofEpoch, RouteRevision: 1, ConfigRevision: 1, BindingRevision: 1, RegistryRevision: 1, Destination: d, CapabilityProfile: json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"partial","encoding":"georgianViaRaster","beep":{"capability":"epsonEscA97Pattern","enabled":false}}`), PrimaryBytes: primary, PrimarySHA256: hex.EncodeToString(digest[:])}
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	j, err = printqueue.DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	return j
}

func queueRows(t *testing.T, s *store.Store) [5]int {
	t.Helper()
	var counts [5]int
	for i, name := range []string{"op_entity", "op_request", "op_event", "op_effect", "pq_job"} {
		if err := s.DB.QueryRow("SELECT count(*) FROM " + name).Scan(&counts[i]); err != nil {
			t.Fatal(err)
		}
	}
	return counts
}

func TestOperationalOriginSignedImmutableAndCurrentTerminal(t *testing.T) {
	f := queueProof(t, t.TempDir())
	defer f.s.Close()
	ctx := context.Background()
	if err := f.s.BindOperationalProofOrigin(ctx, f.auth, f.raw, f.trust); err != nil {
		t.Fatal("exact origin retry", err)
	}
	for _, name := range []string{"origin", "ca", "issuer", "grant", "purpose", "mode", "epoch", "unsigned"} {
		t.Run(name, func(t *testing.T) {
			g, signer, trust := f.origin, f.signer, f.trust
			switch name {
			case "origin":
				g.OriginInstallationID = uuid.NewString()
			case "ca":
				g.ClientCASHA256 = hex.EncodeToString(make([]byte, 32))
			case "issuer":
				_, signer = proofGrant(t, f.id)
				_, trust = signProofGrant(t, store.OperationalProofGrant{}, signer)
			case "grant":
				g.GrantID = uuid.NewString()
			case "purpose":
				g.Purpose = store.OperationalProofPurpose
			case "mode":
				g.Mode = "PRODUCTION"
			case "epoch":
				g.AuthorityEpoch++
			}
			raw := signOrigin(t, g, signer)
			if name == "unsigned" {
				raw = base64.RawURLEncoding.EncodeToString([]byte(`{}`))
			}
			if err := f.s.BindOperationalProofOrigin(ctx, f.auth, raw, trust); !errors.Is(err, store.ErrOperationalAuthority) {
				t.Fatal("origin reissue/rotation admitted", err)
			}
		})
	}
	for _, sql := range []string{"UPDATE op_terminal_origin SET origin_installation_id='changed'", "DELETE FROM op_terminal_origin"} {
		if _, err := f.s.DB.Exec(sql); err == nil {
			t.Fatal("mutable origin", sql)
		}
	}
	if _, err := f.s.OperationalProofStatus(ctx, f.auth); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"wrong-origin", "wrong-ca", "missing-ca"} {
		t.Run(name, func(t *testing.T) {
			auth := f.auth
			switch name {
			case "wrong-origin":
				auth.OriginInstallationID = uuid.NewString()
			case "wrong-ca":
				auth.ClientCASHA256 = make([]byte, 32)
			case "missing-ca":
				auth.ClientCASHA256 = nil
			}
			if _, err := f.s.OperationalProofStatus(ctx, auth); !errors.Is(err, store.ErrDenied) {
				t.Fatal("certificate origin not transaction fenced", err)
			}
		})
	}
	if err := f.s.Revoke(f.auth.TerminalID); err != nil {
		t.Fatal(err)
	}
	if err := f.s.BindOperationalProofOrigin(ctx, f.auth, f.raw, f.trust); !errors.Is(err, store.ErrDenied) {
		t.Fatal("revoked origin retry", err)
	}
	if _, err := f.s.OperationalProofStatus(ctx, f.auth); !errors.Is(err, store.ErrDenied) {
		t.Fatal("revoked live channel authorized", err)
	}
}

func TestOperationalQueuedAtomicReceiptsRetryRestartAndObserverOrigin(t *testing.T) {
	dir := t.TempDir()
	f := queueProof(t, dir)
	ctx := context.Background()
	r := queuedIntent(t, f)
	second := frozenQueueJob(t, f, r.RequestID, uuid.NewString())
	r.Effects = append(r.Effects, store.OperationalEffect{ID: second.EffectID, Kind: store.OperationalPrint, Payload: second.Raw()})
	result, err := f.s.CommitOperationalQueued(ctx, r)
	if err != nil {
		t.Fatal(err)
	}
	if result.PrintAdmission != store.OperationalPrintAdmission || result.OriginInstallationID != f.auth.OriginInstallationID || len(result.Event.PrintReceipts) != 2 || result.Event.PrintReceipts[0].Sequence != 1 || result.Event.PrintReceipts[1].Sequence != 2 {
		t.Fatal("missing canonical receipts", result)
	}
	if got := queueRows(t, f.s); got != [5]int{1, 1, 1, 2, 2} {
		t.Fatal("atomic rows", got)
	}
	if retry, err := f.s.CommitOperationalQueued(ctx, r); err != nil || !reflect.DeepEqual(retry, result) {
		t.Fatal("last ACK retry", retry, err)
	}
	base := f.auth
	base.OriginInstallationID = ""
	base.ClientCASHA256 = nil
	if _, err := f.s.OperationalResult(ctx, base, proofEpoch, r.RequestID); !errors.Is(err, store.ErrDenied) {
		t.Fatal("base three-UUID auth read queued result", err)
	}
	// Observer replay preserves producer origin without pretending it belongs
	// to the observing terminal. No queue admission occurs during replay.
	observer := operationalTerminal(t, f.s)
	page, err := f.s.OperationalReplay(ctx, observer, proofEpoch, 0, 0)
	if err != nil || !reflect.DeepEqual(page.Events[0], *result.Event) {
		t.Fatal("observer origin altered receipt", page, err)
	}
	if err := f.s.Close(); err != nil {
		t.Fatal(err)
	}
	f.s, err = store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	defer f.s.Close()
	got, err := f.s.OperationalResult(ctx, f.auth, proofEpoch, r.RequestID)
	if err != nil || !reflect.DeepEqual(got, result) {
		t.Fatal("restart result", got, err)
	}
	if retry, err := f.s.CommitOperationalQueued(ctx, r); err != nil || !reflect.DeepEqual(retry, result) {
		t.Fatal("restart retry", retry, err)
	}
	if rows := queueRows(t, f.s); rows != [5]int{1, 1, 1, 2, 2} {
		t.Fatal("duplicate queue on restart", rows)
	}
	changed := operationalClone(t, r)
	changed.Auth = f.auth
	changed.Effects[0].Payload = bytes.Clone(changed.Effects[0].Payload)
	changed.ApplicationData = []byte("changed")
	if _, err := f.s.CommitOperationalQueued(ctx, changed); !errors.Is(err, store.ErrRequestReuse) {
		t.Fatal("changed immutable retry", err)
	}
	baseIntent := operationalClone(t, r)
	baseIntent.Auth = f.auth
	baseIntent.PrintAdmission = ""
	baseIntent.OriginInstallationID = ""
	if _, err := f.s.CommitOperational(ctx, baseIntent); !errors.Is(err, store.ErrRequestReuse) {
		t.Fatal("cross-mode request ID", err)
	}
}

func TestOperationalQueuedRefusalRollsBackEveryRecord(t *testing.T) {
	for _, name := range []string{"opaque-print", "wrong-effect", "wrong-host", "wrong-origin", "missing-registration", "queue-insert", "queue-capacity"} {
		t.Run(name, func(t *testing.T) {
			f := queueProof(t, t.TempDir())
			defer f.s.Close()
			r := queuedIntent(t, f)
			var cleanup func()
			switch name {
			case "opaque-print":
				r.Effects = append(r.Effects, store.OperationalEffect{ID: uuid.NewString(), Kind: store.OperationalPrint, Payload: []byte("old inert bytes")})
			case "wrong-effect":
				r.Effects[0].ID = uuid.NewString()
			case "wrong-host":
				var j printqueue.FrozenJob
				json.Unmarshal(r.Effects[0].Payload, &j)
				j.Destination.WorkerHostID = uuid.NewString()
				r.Effects[0].Payload, _ = json.Marshal(j)
			case "wrong-origin":
				r.Auth.OriginInstallationID = uuid.NewString()
				r.OriginInstallationID = r.Auth.OriginInstallationID
			case "missing-registration":
				r.Auth = operationalTerminal(t, f.s)
				r.Auth.OriginInstallationID = uuid.NewString()
				r.Auth.ClientCASHA256 = f.auth.ClientCASHA256
				r.OriginInstallationID = r.Auth.OriginInstallationID
			case "queue-insert":
				if _, err := f.s.DB.Exec("CREATE TRIGGER fixture_queue_refusal BEFORE INSERT ON pq_receipt BEGIN SELECT RAISE(ABORT,'fixture refused'); END"); err != nil {
					t.Fatal(err)
				}
				cleanup = func() { f.s.DB.Exec("DROP TRIGGER fixture_queue_refusal") }
			case "queue-capacity":
				var ddl string
				if err := f.s.DB.QueryRow("SELECT sql FROM sqlite_master WHERE name='pq_registry_update'").Scan(&ddl); err != nil {
					t.Fatal(err)
				}
				for _, sql := range []string{"DROP TRIGGER pq_registry_update", "UPDATE pq_registry SET next_sequence=9223372036854775807", ddl} {
					if _, err := f.s.DB.Exec(sql); err != nil {
						t.Fatal(err)
					}
				}
			}
			if cleanup != nil {
				defer cleanup()
			}
			if result, err := f.s.CommitOperationalQueued(context.Background(), r); err == nil || result != nil {
				t.Fatal("queued refusal committed", result, err)
			}
			if rows := queueRows(t, f.s); rows != [5]int{} {
				t.Fatal("partial business/effect/queue/outcome", rows)
			}
			var head uint64
			if err := f.s.DB.QueryRow("SELECT sequence FROM op_authority").Scan(&head); err != nil || head != 0 {
				t.Fatal("partial head", head, err)
			}
		})
	}
}

func TestOperationalQueuedConflictPersistsWithoutEffects(t *testing.T) {
	f := queueProof(t, t.TempDir())
	defer f.s.Close()
	r := queuedIntent(t, f)
	committed, err := f.s.CommitOperationalQueued(context.Background(), r)
	if err != nil {
		t.Fatal(err)
	}
	stale := queuedIntent(t, f)
	stale.Writes = r.Writes
	conflict, err := f.s.CommitOperationalQueued(context.Background(), stale)
	if err != nil || conflict.Outcome != store.OperationalConflict || conflict.Event != nil || conflict.OriginInstallationID != f.auth.OriginInstallationID {
		t.Fatal("canonical conflict", conflict, err)
	}
	if retry, err := f.s.CommitOperationalQueued(context.Background(), stale); err != nil || !reflect.DeepEqual(retry, conflict) {
		t.Fatal("durable conflict changed", retry, err)
	}
	if rows := queueRows(t, f.s); rows != [5]int{1, 2, 1, 1, 1} {
		t.Fatal("stale effects published", rows, committed)
	}
	if _, err := f.s.CommitOperational(context.Background(), r); !errors.Is(err, store.ErrOperationalIntent) {
		t.Fatal("old inert path accepted queue discriminator", err)
	}
}
