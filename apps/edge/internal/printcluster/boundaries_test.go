package printcluster

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/hashicorp/raft"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
)

func TestStartedBeepAcrossElectionStaysHeldOtherPrinterProgresses(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	j := newJob(t, base, 91, 0)
	submit(t, n, a, j)
	next := newJob(t, base, 92, 0)
	submit(t, n, a, next)
	ctx, cancel := proofContext()
	defer cancel()
	worker := executor(t, n)
	x, e := n.ClaimLogical(ctx, worker, j.JobID, testUUID(4901))
	if e != nil {
		t.Fatal(e)
	}
	if e = n.MarkPrimaryStarted(ctx, worker, x); e != nil {
		t.Fatal(e)
	}
	if e = n.MarkPrimarySubmitted(ctx, worker, x); e != nil {
		t.Fatal(e)
	}
	if e = n.MarkBeepStarted(ctx, worker, x); e != nil {
		t.Fatal(e)
	}
	c.stop(n)
	n = c.leader()
	v, e := n.ReadJob(ctx, j.JobID)
	if e != nil || v.PrimaryState != "SUBMITTED" || v.BeepState != "UNCERTAIN" {
		t.Fatalf("primary lost or beep repeated: %+v %v", v, e)
	}
	if _, e = n.ClaimLogical(ctx, executor(t, n), next.JobID, testUUID(4902)); !errors.Is(e, ErrBusy) {
		t.Fatalf("uncertain original beep lifetime crossed: %v", e)
	}
	otherConfig, e := DecodeConfig(mutate(t, cfg.Raw(), func(m map[string]any) {
		m["physicalPrinterId"] = testUUID(1991)
		m["routeId"] = testUUID(1992)
		m["destination"].(map[string]any)["host"] = "192.168.10.30"
	}))
	if e != nil {
		t.Fatal(e)
	}
	install(t, n, a, otherConfig)
	otherJob, e := DecodeJob(mutate(t, newJob(t, base, 93, 0).Raw(), func(m map[string]any) {
		m["physicalPrinterId"] = otherConfig.PhysicalPrinterID
		m["routeId"] = otherConfig.RouteID
		m["configSha256"] = otherConfig.Digest()
	}))
	if e != nil {
		t.Fatal(e)
	}
	submit(t, n, a, otherJob)
	if _, e = n.ClaimLogical(ctx, executor(t, n), otherJob.JobID, testUUID(4903)); e != nil {
		t.Fatal("unrelated printer blocked", e)
	}
}

type localSyntheticSender struct{ writes [][]byte }

func (s *localSyntheticSender) Physical() bool { return false }
func (s *localSyntheticSender) Send(_ context.Context, _ printtransport.Destination, b []byte) printtransport.Result {
	s.writes = append(s.writes, bytes.Clone(b))
	return printtransport.Result{State: printtransport.Submitted, Stage: "isolated synthetic LOCAL only", WriteAttempted: true, BytesWritten: uint32(len(b))}
}

type localSyntheticGuard struct{}

func (localSyntheticGuard) Context(ctx context.Context) context.Context { return ctx }
func (localSyntheticGuard) Close() error                                { return nil }

func TestIndependentLOCALDurableQueueWorksDuringActualSharedQuorumLoss(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	submit(t, n, a, newJob(t, base, 95, 0))
	for _, p := range c.nodes {
		if p != n {
			c.stop(p)
		}
	}
	ctx, cancel := proofContext()
	defer cancel()
	if r, e := n.Submit(ctx, a, newJob(t, base, 96, 0)); e == nil || r.Status == "ACCEPTED" {
		t.Fatal("shared minority admitted without majority")
	}
	// Use the independent existing LOCAL v1 queue, with its real durable SQLite
	// schema, original fixed owner envelope and a strictly nonphysical sender.
	raw, e := os.ReadFile("../printqueue/testdata/dart_tcp.json")
	if e != nil {
		t.Fatal(e)
	}
	raw = mutate(t, raw, func(m map[string]any) {
		m["capabilityProfile"].(map[string]any)["beep"].(map[string]any)["enabled"] = false
	})
	j, e := printqueue.DecodeFrozenJob(raw)
	if e != nil {
		t.Fatal(e)
	}
	db, e := store.Open(t.TempDir(), true)
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	identity := printqueue.GatewayIdentity{VenueID: j.VenueID, InstallationID: j.InstallationID, DeviceID: j.DeviceID, WorkerHostID: j.Destination.WorkerHostID, Epoch: j.AuthorityEpoch}
	local, e := printqueue.NewProofStore(ctx, db.DB, identity)
	if e != nil {
		t.Fatal(e)
	}
	d := j.Destination
	d.DocumentName = ""
	r := printqueue.Registry{PhysicalPrinterID: j.PhysicalPrinterID, VenueID: j.VenueID, InstallationID: j.InstallationID, AuthorityEpoch: j.AuthorityEpoch, DeviceID: j.DeviceID, WorkerHostID: j.Destination.WorkerHostID, BindingRevision: j.BindingRevision, ConfigRevision: j.ConfigRevision, RegistryRevision: j.RegistryRevision, Destination: d, Aliases: []string{j.AliasID}}
	if e = local.Register(ctx, r); e != nil {
		t.Fatal(e)
	}
	authority := printqueue.Authority{VenueID: j.VenueID, InstallationID: j.InstallationID, OriginInstallationID: j.OriginInstallationID, TerminalID: j.TerminalID, Epoch: j.AuthorityEpoch}
	receipt, e := local.Accept(ctx, authority, j)
	if e != nil {
		t.Fatal(e)
	}
	sender := &localSyntheticSender{}
	worker, e := printqueue.NewProofScheduler(ctx, local, sender, printqueue.ProofOptions{WorkerID: testUUID(4995), GuardFactory: func(string) (printtransport.PrinterGuard, error) { return localSyntheticGuard{}, nil }})
	if e != nil {
		t.Fatal(e)
	}
	defer worker.Stop(context.Background())
	if e = worker.RunNext(j.PhysicalPrinterID); e != nil {
		t.Fatal(e)
	}
	outcome, e := local.Outcome(ctx, j.JobID)
	if e != nil || outcome.Primary != printqueue.Submitted || len(sender.writes) != 1 || !bytes.Equal(sender.writes[0], j.PrimaryBytes) {
		t.Fatalf("independent local queue failed: %+v %v", outcome, e)
	}
	if retry, e := local.Accept(ctx, authority, j); e != nil || retry != receipt {
		t.Fatal("local durability/idempotency changed by shared outage")
	}
	if n.PhysicalDispatchStatus() != ErrPhysicalHeld {
		t.Fatal("shared quorum loss opened hardware")
	}
}

func TestStagingCapacityScopeAndChunkReceipts(t *testing.T) {
	_, base := golden(t, "shared_tcp")
	pin := testPin(t, 1, VenueShared, base, false, false)
	s := initial(pin)
	s.MembershipGeneration = 1
	a := Caller{MemberID: pin.Peers[0].ID, TerminalID: base.OriginTerminalID, InstallationID: base.OriginInstallationID}
	for i := 0; i < MaxStagedJobs; i++ {
		m := chunkMeta{RequestID: testUUID(6000 + i), JobID: testUUID(6100 + i), EffectID: testUUID(6200 + i), Digest: sha([]byte{byte(i)}), TotalBytes: ChunkBytes + 1, TotalChunks: 2, Caller: a}
		r := s.stage(command{Caller: a, Meta: &m, ChunkIndex: 0, Chunk: make([]byte, ChunkBytes)})
		if r.Err != nil || r.Receipt != nil {
			t.Fatal("partial staging admitted or refused", r.Err)
		}
	}
	m := chunkMeta{RequestID: testUUID(6999), JobID: testUUID(6998), EffectID: testUUID(6997), Digest: sha([]byte("capacity")), TotalBytes: ChunkBytes + 1, TotalChunks: 2, Caller: a}
	if r := s.stage(command{Caller: a, Meta: &m, ChunkIndex: 0, Chunk: make([]byte, ChunkBytes)}); !errors.Is(r.Err, ErrCapacity) {
		t.Fatal("staging capacity unbounded")
	}
	if len(s.Jobs) != 0 || len(s.NextSequence) != 0 {
		t.Fatal("chunks consumed FIFO position")
	}
	changed := *s.Requests[testUUID(6000)]
	meta := changed.Meta
	meta.Digest = sha([]byte("changed"))
	if r := s.stage(command{Caller: a, Meta: &meta, ChunkIndex: 0, Chunk: make([]byte, ChunkBytes)}); !errors.Is(r.Err, ErrReuse) {
		t.Fatal("interleaved request digest altered")
	}
	meta = changed.Meta
	meta.Caller.InstallationID = testUUID(999)
	if r := s.stage(command{Caller: meta.Caller, Meta: &meta, ChunkIndex: 0, Chunk: make([]byte, ChunkBytes)}); r.Err == nil {
		t.Fatal("client authority manufactured by chunk")
	}
	large := initial(pin)
	for i := 0; i < 2; i++ {
		meta := m
		meta.RequestID = testUUID(7000 + i)
		meta.JobID = testUUID(7100 + i)
		meta.EffectID = testUUID(7200 + i)
		meta.TotalBytes = MaxEnvelopeBytes
		meta.TotalChunks = (meta.TotalBytes + ChunkBytes - 1) / ChunkBytes
		if r := large.stage(command{Caller: a, Meta: &meta, ChunkIndex: 0, Chunk: make([]byte, ChunkBytes)}); r.Err != nil {
			t.Fatal(r.Err)
		}
	}
	m.TotalBytes = MaxEnvelopeBytes
	m.TotalChunks = (m.TotalBytes + ChunkBytes - 1) / ChunkBytes
	if r := large.stage(command{Caller: a, Meta: &m, ChunkIndex: 0, Chunk: make([]byte, ChunkBytes)}); !errors.Is(r.Err, ErrCapacity) {
		t.Fatal("reserved staged byte bound exceeded")
	}
}

func TestEffectiveModesFutureSchemaAndSnapshotFailure(t *testing.T) {
	_, base := golden(t, "shared_tcp")
	pin := testPin(t, 1, VenueShared, base, false, false)
	dir := t.TempDir()
	f, e := openProjection(dir, pin)
	if e != nil {
		t.Fatal(e)
	}
	if e = verifySQLiteDurability(f.db); e != nil {
		t.Fatal(e)
	}
	if _, e = f.db.Exec("PRAGMA synchronous=NORMAL"); e != nil {
		t.Fatal(e)
	}
	if e = verifySQLiteDurability(f.db); !errors.Is(e, ErrStorage) {
		t.Fatal("mode drift accepted")
	}
	if _, e = f.db.Exec("PRAGMA synchronous=FULL"); e != nil {
		t.Fatal(e)
	}
	if _, e = f.db.Exec("PRAGMA ignore_check_constraints=ON"); e != nil {
		t.Fatal(e)
	}
	if _, e = f.db.Exec("UPDATE printcluster_projection SET schema_version=3"); e != nil {
		t.Fatal(e)
	}
	if e = f.close(); e != nil {
		t.Fatal(e)
	}
	if reopened, e := openProjection(dir, pin); e == nil {
		_ = reopened.close()
		t.Fatal("future schema accepted")
	}
	f, e = openProjection(t.TempDir(), pin)
	if e != nil {
		t.Fatal(e)
	}
	defer f.close()
	snapshot, e := f.Snapshot()
	if e != nil {
		t.Fatal(e)
	}
	sink := &failedSnapshotSink{}
	if e = snapshot.Persist(sink); e == nil || !sink.canceled {
		t.Fatal("snapshot failure reported durable success")
	}
}

type failedSnapshotSink struct{ canceled bool }

func (*failedSnapshotSink) ID() string                { return "synthetic" }
func (*failedSnapshotSink) Write([]byte) (int, error) { return 0, io.ErrShortWrite }
func (*failedSnapshotSink) Close() error              { return nil }
func (s *failedSnapshotSink) Cancel() error           { s.canceled = true; return nil }

func TestLeaderOnlyClaimAndReprintProvenance(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	j := newJob(t, base, 99, 0)
	submit(t, n, a, j)
	ctx, cancel := proofContext()
	defer cancel()
	for _, p := range c.pin.Peers {
		if p.ID == n.id {
			continue
		}
		caller, _ := n.caller(p.ID)
		if _, e := n.ClaimLogical(ctx, caller, j.JobID, testUUID(4999)); !errors.Is(e, ErrAssignment) {
			t.Fatal("nonleader logical dispatcher permitted")
		}
	}
	bad, e := DecodeJob(mutate(t, newJob(t, base, 100, 0).Raw(), func(m map[string]any) {
		m["reprintOf"] = j.JobID
		m["primaryBytes"] = []byte("unrelated correction")
		m["primarySha256"] = sha([]byte("unrelated correction"))
	}))
	if e != nil {
		t.Fatal(e)
	}
	if _, e = n.Reprint(ctx, a, bad, "synthetic manual actor"); !errors.Is(e, ErrConfig) {
		t.Fatalf("unrelated business payload labeled reprint: %v", e)
	}
}

func TestMissingJobSnapshotDoesNotPanic(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 1, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	submit(t, n, a, base)
	snapshot, e := n.fsm.Snapshot()
	if e != nil {
		t.Fatal(e)
	}
	var s projection
	if e = json.Unmarshal(snapshot.(*projectionSnapshot).raw, &s); e != nil {
		t.Fatal(e)
	}
	s.Jobs[base.JobID] = nil
	raw, _ := json.Marshal(s)
	before := bytes.Clone(n.fsm.encoded)
	if e = n.fsm.Restore(io.NopCloser(bytes.NewReader(raw))); e == nil {
		t.Fatal("null job restored")
	}
	if !bytes.Equal(before, n.fsm.encoded) {
		t.Fatal("malformed restore changed state")
	}
}

func TestTwoPOSPlusThirdFullReplicaMajority(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	pin := testPin(t, 3, VenueShared, base, false, false)
	c := startCluster(t, pin)
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	j := newJob(t, base, 111, 0)
	r := submit(t, n, a, j)
	allReplicas(t, c, j, r)
	t.Log("three fixed FULLDATA voters: two synthetic POS peers and one independent third full replica; no metadata witness")
	for _, v := range c.nodes {
		if v != n {
			c.stop(v)
			break
		}
	}
	submit(t, n, a, newJob(t, base, 112, 0))
	for _, v := range c.nodes {
		if v != nil && v != n {
			c.stop(v)
			break
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if r, e := n.Submit(ctx, a, newJob(t, base, 113, 0)); e == nil || r.Status == "ACCEPTED" {
		t.Fatal("one voter fell back to standalone")
	}
}

var _ raft.SnapshotSink = (*failedSnapshotSink)(nil)

func TestOnlyTemporaryProofDirectories(t *testing.T) {
	for _, dir := range []string{"relative", "//remote/share", "smb://remote/path", "/unqualified-printcluster-root"} {
		if proofDirectory(dir) {
			t.Fatal("unqualified directory accepted", dir)
		}
	}
	if !proofDirectory(filepath.Join(t.TempDir(), "owned")) {
		t.Fatal("local temporary fixture directory refused")
	}
}

func TestExplicitTwoVoterFailSafeNeverFallsBack(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 2, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	j := newJob(t, base, 121, 0)
	r := submit(t, n, a, j)
	allReplicas(t, c, j, r)
	for _, p := range c.nodes {
		if p != n {
			c.stop(p)
			break
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if r, e := n.Submit(ctx, a, newJob(t, base, 122, 0)); e == nil || r.Status == "ACCEPTED" {
		t.Fatal("explicit 2-voter mode fell back to standalone")
	}
	if n.PhysicalDispatchStatus() != ErrPhysicalHeld {
		t.Fatal("two-voter topology activated hardware")
	}
}
func TestAssignedPlusUnreferencedNullJobRestoreRefused(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 1, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	submit(t, n, a, base)
	ctx, cancel := proofContext()
	defer cancel()
	if _, e := n.ClaimLogical(ctx, a, base.JobID, testUUID(9121)); e != nil {
		t.Fatal(e)
	}
	snapshot, e := n.fsm.Snapshot()
	if e != nil {
		t.Fatal(e)
	}
	var s projection
	if e = json.Unmarshal(snapshot.(*projectionSnapshot).raw, &s); e != nil {
		t.Fatal(e)
	}
	s.Jobs[testUUID(9199)] = nil
	raw, _ := json.Marshal(s)
	before := bytes.Clone(n.fsm.encoded)
	for i := 0; i < 32; i++ {
		if e = n.fsm.Restore(io.NopCloser(bytes.NewReader(raw))); e == nil {
			t.Fatal("cross-entry null job restored")
		}
	}
	if !bytes.Equal(before, n.fsm.encoded) {
		t.Fatal("invalid restore changed live state")
	}
}
