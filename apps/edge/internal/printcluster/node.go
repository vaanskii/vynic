package printcluster

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/raft"
	boltdb "github.com/hashicorp/raft-boltdb/v2"
)

// Node is a replicated logical queue. Its proof and authenticated constructors
// share durable storage. Neither can send physical bytes or grant a writer permit.
type Node struct {
	mu        sync.Mutex
	memberMu  sync.Mutex
	pin       ClusterConfig
	id        string
	raft      *raft.Raft
	bolt      *boltdb.BoltStore
	fsm       *durableFSM
	transport interface {
		raft.Transport
		Close() error
	}
	stream   *proofStream
	closed   bool
	closeErr error
}

func OpenLoopbackProof(dir string, pin ClusterConfig, memberID string) (*Node, error) {
	if !proofDirectory(dir) {
		return nil, ErrStorage
	}
	return openNode(dir, pin, memberID, nil)
}

func openNode(dir string, pin ClusterConfig, memberID string, transport interface {
	raft.Transport
	Close() error
}) (*Node, error) {
	if pin.validate() != nil {
		return nil, ErrMembership
	}
	p, ok := pin.peer(memberID)
	if !ok || p.Role == Client {
		return nil, ErrMembership
	}
	// Clone caller-owned slices before retaining the trusted membership pin.
	pin = canonicalPin(pin)
	if e := os.MkdirAll(dir, 0700); e != nil {
		return nil, e
	}
	_, boltErr := os.Stat(filepath.Join(dir, "raft.bolt"))
	_, projectionErr := os.Stat(filepath.Join(dir, "projection.sqlite"))
	boltExists, projectionExists := boltErr == nil, projectionErr == nil
	if (boltErr != nil && !os.IsNotExist(boltErr)) || (projectionErr != nil && !os.IsNotExist(projectionErr)) {
		return nil, ErrStorage
	}
	if boltExists != projectionExists {
		return nil, ErrStorage
	}
	if !boltExists {
		if entries, e := os.ReadDir(filepath.Join(dir, "snapshots")); e == nil && len(entries) > 0 {
			return nil, ErrStorage
		}
	}
	b, e := boltdb.NewBoltStore(filepath.Join(dir, "raft.bolt"))
	if e != nil {
		return nil, e
	}
	n := &Node{pin: pin, id: memberID, bolt: b}
	ready := false
	defer func() {
		if !ready {
			_ = n.Close()
		}
	}()
	f, e := openProjection(dir, pin)
	if e != nil {
		return nil, e
	}
	n.fsm = f
	// Persist local member identity separately from the common cluster pin.
	const localKey = "vynic-printcluster-member-v1"
	old, e := b.Get([]byte(localKey))
	if e != nil && !errors.Is(e, boltdb.ErrKeyNotFound) {
		return nil, e
	}
	if len(old) > 0 && string(old) != memberID {
		return nil, ErrMembership
	}
	if boltExists && len(old) == 0 {
		return nil, ErrStorage
	}
	if len(old) == 0 {
		if e = b.Set([]byte(localKey), []byte(memberID)); e != nil {
			return nil, e
		}
	}
	var s *proofStream
	if transport == nil {
		s, e = newProofStream(pin, memberID)
		if e != nil {
			return nil, e
		}
		n.stream = s
	}
	logger := hclog.New(&hclog.LoggerOptions{Name: "printcluster-proof", Output: io.Discard, Level: hclog.Error})
	n.transport = transport
	if transport == nil {
		n.transport = raft.NewNetworkTransportWithConfig(&raft.NetworkTransportConfig{Stream: s, MaxPool: 3, MaxRPCsInFlight: 1, Timeout: 750 * time.Millisecond, Logger: logger})
	}
	snaps, e := raft.NewFileSnapshotStoreWithLogger(filepath.Join(dir, "snapshots"), 3, logger)
	if e != nil {
		return nil, e
	}
	last, e := b.LastIndex()
	if e != nil {
		return nil, e
	}
	snapshotMeta, e := snaps.List()
	if e != nil {
		return nil, e
	}
	for _, s := range snapshotMeta {
		if s.Index > last {
			last = s.Index
		}
	}
	if f.state.AppliedIndex > last {
		return nil, ErrStorage
	}
	cfg := raft.DefaultConfig()
	cfg.LocalID = raft.ServerID(memberID)
	cfg.Logger = logger
	// Keep the upstream election/heartbeat/lease defaults. Aggressive fixture
	// timers can create spurious leadership loss under bounded JSON/SQLite I/O.
	cfg.CommitTimeout = 20 * time.Millisecond
	if pin.Version == 2 {
		cfg.MaxAppendEntries = 4
	}
	cfg.SnapshotInterval = 20 * time.Second
	cfg.SnapshotThreshold = 64
	cfg.TrailingLogs = 32
	r, e := raft.NewRaft(cfg, f, b, b, snaps, n.transport)
	if e != nil {
		return nil, e
	}
	n.raft = r
	f.mu.Lock()
	f.onFailure = func() { _ = r.Shutdown().Error() }
	f.mu.Unlock()
	ready = true
	return n, nil
}

// The inert constructor only owns temporary fixture directories. Common
// remote/UNC paths and symlink escapes are refused. Local filesystem/power-loss
// qualification remains separate; this does not certify mounted remote disks.
func proofDirectory(dir string) bool {
	if !filepath.IsAbs(dir) || strings.HasPrefix(dir, "\\\\") || strings.Contains(dir, "://") || strings.HasPrefix(dir, "//") {
		return false
	}
	parent := filepath.Clean(dir)
	tail := []string{}
	for {
		if _, e := os.Stat(parent); e == nil {
			break
		} else if !os.IsNotExist(e) {
			return false
		}
		next := filepath.Dir(parent)
		if next == parent {
			return false
		}
		tail = append(tail, filepath.Base(parent))
		parent = next
	}
	real, e := filepath.EvalSymlinks(parent)
	if e != nil {
		return false
	}
	for i := len(tail) - 1; i >= 0; i-- {
		real = filepath.Join(real, tail[i])
	}
	for _, root := range []string{os.TempDir(), "/tmp"} {
		resolved, e := filepath.EvalSymlinks(root)
		if e != nil {
			continue
		}
		rel, e := filepath.Rel(resolved, real)
		if e == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

// Bootstrap commits exactly the pinned FULLDATA voters. Nonvoters are joined
// explicitly later; clients never join Raft and never affect quorum.
func (n *Node) Bootstrap(ctx context.Context) error {
	var c raft.Configuration
	for _, p := range n.pin.Peers {
		if p.Role == Voter {
			c.Servers = append(c.Servers, raft.Server{ID: raft.ServerID(p.ID), Address: raft.ServerAddress(p.Address), Suffrage: raft.Voter})
		}
	}
	return waitFuture(ctx, n.raft.BootstrapCluster(c))
}
func waitFuture(ctx context.Context, f raft.Future) error {
	ch := make(chan error, 1)
	go func() { ch <- f.Error() }()
	select {
	case e := <-ch:
		return e
	case <-ctx.Done():
		return ErrCommitUnknown
	}
}
func timeout(ctx context.Context) time.Duration {
	if d, ok := ctx.Deadline(); ok {
		v := time.Until(d)
		if v > 0 && v < 3*time.Second {
			return v
		}
	}
	return 3 * time.Second
}
func (n *Node) caller(id string) (Caller, error) {
	p, ok := n.currentPin().peer(id)
	if !ok {
		return Caller{}, ErrScope
	}
	return Caller{MemberID: p.ID, TerminalID: p.TerminalID, InstallationID: p.InstallationID}, nil
}
func (n *Node) leader(ctx context.Context) error {
	n.mu.Lock()
	closed := n.closed
	n.mu.Unlock()
	if closed {
		return ErrNoQuorum
	}
	if n.raft.State() != raft.Leader {
		return ErrNoQuorum
	}
	if e := waitFuture(ctx, n.raft.VerifyLeader()); e != nil {
		return ErrNoQuorum
	}
	if e := waitFuture(ctx, n.raft.Barrier(timeout(ctx))); e != nil {
		return ErrNoQuorum
	}
	n.fsm.mu.RLock()
	broken := n.fsm.broken
	n.fsm.mu.RUnlock()
	if broken {
		return ErrStorage
	}
	return nil
}
func (n *Node) apply(ctx context.Context, c command) (result, error) {
	// Apply itself waits for majority commit and local durable application.
	// VerifyLeader + Barrier before each mutation adds two serialized round
	// trips without strengthening the write receipt. Linearizable reads retain
	// their separate barrier. A lost leadership/timeout remains commit-unknown.
	n.mu.Lock()
	closed := n.closed
	n.mu.Unlock()
	if closed || n.raft.State() != raft.Leader {
		return result{}, ErrNoQuorum
	}
	n.fsm.mu.RLock()
	broken := n.fsm.broken
	n.fsm.mu.RUnlock()
	if broken {
		return result{}, ErrStorage
	}
	if n.fsm.generation() == 0 {
		// Bootstrap may elect the node before StoreConfiguration reaches the
		// FSM. Establish the initial membership once, before the first command.
		if e := waitFuture(ctx, n.raft.Barrier(timeout(ctx))); e != nil {
			return result{}, ErrNoQuorum
		}
	}
	c.Version = 2
	c.LeaderID = n.id
	c.MembershipGeneration = n.fsm.generation()
	b, e := json.Marshal(c)
	if e != nil || len(b) > raft.SuggestedMaxDataSize {
		return result{}, ErrInvalid
	}
	future := n.raft.Apply(b, timeout(ctx))
	if e = waitFuture(ctx, future); e != nil {
		if errors.Is(e, raft.ErrNotLeader) {
			return result{}, ErrNoQuorum
		}
		return result{}, ErrCommitUnknown
	}
	r, ok := future.Response().(result)
	if !ok {
		return result{}, ErrStorage
	}
	if r.Err != nil {
		return r, r.Err
	}
	return r, nil
}
func (n *Node) SyncLogicalState(ctx context.Context) error {
	a, e := n.caller(n.id)
	if e != nil {
		return e
	}
	_, e = n.apply(ctx, command{Op: "sync", Caller: a})
	return e
}
func (n *Node) InstallConfig(ctx context.Context, a Caller, c ConfigSnapshot) (string, error) {
	fresh, e := c.fresh()
	if e != nil {
		return "", e
	}
	if !n.pin.authorize(a, true) || !fresh.bound(n.pin) {
		return "", ErrScope
	}
	r, e := n.apply(ctx, command{Op: "config", Caller: a, Raw: fresh.raw})
	return r.ConfigDigest, e
}
func metaFor(j Job, a Caller, reason string) chunkMeta {
	return chunkMeta{RequestID: j.RequestID, JobID: j.JobID, EffectID: j.EffectID, Digest: j.digest, TotalBytes: len(j.raw), TotalChunks: (len(j.raw) + ChunkBytes - 1) / ChunkBytes, Caller: a, ReprintReason: reason}
}
func (n *Node) submit(ctx context.Context, a Caller, j Job, reason string) (Receipt, error) {
	j, e := j.fresh()
	if e != nil {
		return Receipt{}, e
	}
	if !j.bound(n.pin, a) {
		return Receipt{}, ErrScope
	}
	if j.ReprintOf == nil && reason != "" {
		return Receipt{}, ErrInvalid
	}
	if j.ReprintOf != nil && (!n.pin.authorize(a, true) || !text(reason, 512)) {
		return Receipt{}, ErrScope
	}
	m := metaFor(j, a, reason)
	for i := 0; i < m.TotalChunks; i++ {
		r, e := n.apply(ctx, command{Op: "chunk", Caller: a, Meta: &m, ChunkIndex: i, Chunk: j.raw[i*ChunkBytes : i*ChunkBytes+m.chunkLength(i)]})
		if e != nil {
			return Receipt{}, e
		}
		if r.Receipt != nil {
			return *r.Receipt, nil
		}
	}
	r, e := n.apply(ctx, command{Op: "finalize", Caller: a, Meta: &m})
	if e != nil {
		return Receipt{}, e
	}
	if r.Receipt == nil || r.Receipt.Status != "ACCEPTED" {
		return Receipt{}, ErrStorage
	}
	return *r.Receipt, nil
}
func (n *Node) Submit(ctx context.Context, a Caller, j Job) (Receipt, error) {
	if j.ReprintOf != nil {
		return Receipt{}, ErrScope
	}
	return n.submit(ctx, a, j, "")
}
func (n *Node) Reprint(ctx context.Context, a Caller, j Job, reason string) (Receipt, error) {
	if j.ReprintOf == nil {
		return Receipt{}, ErrInvalid
	}
	return n.submit(ctx, a, j, reason)
}
func (n *Node) ReadJob(ctx context.Context, id string) (JobView, error) {
	if !uuid(id) {
		return JobView{}, ErrInvalid
	}
	if e := n.SyncLogicalState(ctx); e != nil {
		return JobView{}, e
	}
	return n.fsm.view(id)
}

// InspectReplica is a diagnostic copy, never a dispatch authority or quorum
// receipt. Tests use it to verify all FULLDATA replicas retain exact bytes.
func (n *Node) InspectReplica(id string) (JobView, error) { return n.fsm.view(id) }
func (n *Node) ClaimLogical(ctx context.Context, a Caller, jobID, attemptID string) (Assignment, error) {
	if a.MemberID != n.id {
		return Assignment{}, ErrAssignment
	}
	r, e := n.apply(ctx, command{Op: "claim", Caller: a, JobID: jobID, AttemptID: attemptID, ExecutorID: a.MemberID})
	if e != nil {
		return Assignment{}, e
	}
	if r.Assignment == nil {
		return Assignment{}, ErrStorage
	}
	return *r.Assignment, nil
}
func (n *Node) logicalTransition(ctx context.Context, a Caller, assignment Assignment, op, reason string) error {
	_, e := n.apply(ctx, command{Op: op, Caller: a, Assignment: &assignment, Reason: reason})
	return e
}
func (n *Node) MarkPrimaryStarted(ctx context.Context, a Caller, x Assignment) error {
	return n.logicalTransition(ctx, a, x, "primaryStarted", "")
}

// Submitted is a synthetic logical transport result, not evidence of paper,
// delivery, or a permission to send. No printer is contacted by this method.
func (n *Node) MarkPrimarySubmitted(ctx context.Context, a Caller, x Assignment) error {
	return n.logicalTransition(ctx, a, x, "primarySubmitted", "")
}
func (n *Node) MarkBeepStarted(ctx context.Context, a Caller, x Assignment) error {
	return n.logicalTransition(ctx, a, x, "beepStarted", "")
}
func (n *Node) MarkBeepSubmitted(ctx context.Context, a Caller, x Assignment) error {
	return n.logicalTransition(ctx, a, x, "beepSubmitted", "")
}
func (n *Node) MarkBeepSkipped(ctx context.Context, a Caller, x Assignment) error {
	return n.logicalTransition(ctx, a, x, "beepSkipped", "")
}
func (n *Node) MarkBeepUncertain(ctx context.Context, a Caller, x Assignment, reason string) error {
	return n.logicalTransition(ctx, a, x, "beepUncertain", reason)
}
func (n *Node) MarkUncertain(ctx context.Context, a Caller, x Assignment, reason string) error {
	return n.logicalTransition(ctx, a, x, "uncertain", reason)
}
func (n *Node) ResolveNotPrinted(ctx context.Context, a Caller, jobID, reason string) error {
	// This is a committed synthetic operator assertion, not proof that an old
	// native call/buffer is settled or fenced. Physical dispatch stays denied.
	_, e := n.apply(ctx, command{Op: "resolveNotPrinted", Caller: a, JobID: jobID, Reason: reason})
	return e
}
func (n *Node) ChangeNonvoter(ctx context.Context, a Caller, id string, add bool, expectedIndex uint64) error {
	n.memberMu.Lock()
	defer n.memberMu.Unlock()
	if !n.pin.authorize(a, true) {
		return ErrScope
	}
	p, ok := n.currentPin().peer(id)
	if !ok || p.Role != Nonvoter {
		return ErrMembership
	}
	if e := n.leader(ctx); e != nil {
		return e
	}
	c := n.raft.GetConfiguration()
	if e := waitFuture(ctx, c); e != nil {
		return e
	}
	if c.Index() != expectedIndex {
		return ErrMembership
	}
	var f raft.IndexFuture
	if add {
		f = n.raft.AddNonvoter(raft.ServerID(id), raft.ServerAddress(p.Address), expectedIndex, timeout(ctx))
	} else {
		f = n.raft.RemoveServer(raft.ServerID(id), expectedIndex, timeout(ctx))
	}
	if e := waitFuture(ctx, f); e != nil {
		return ErrCommitUnknown
	}
	return n.SyncLogicalState(ctx)
}
func (n *Node) Membership(ctx context.Context) (uint64, map[string]string, error) {
	if e := n.leader(ctx); e != nil {
		return 0, nil, e
	}
	c := n.raft.GetConfiguration()
	if e := waitFuture(ctx, c); e != nil {
		return 0, nil, e
	}
	m := map[string]string{}
	for _, s := range c.Configuration().Servers {
		m[string(s.ID)] = s.Suffrage.String()
	}
	return c.Index(), m, nil
}
func (n *Node) Snapshot(ctx context.Context) error {
	if e := n.SyncLogicalState(ctx); e != nil {
		return e
	}
	return waitFuture(ctx, n.raft.Snapshot())
}
func (n *Node) IsLeader() bool { return n.raft.State() == raft.Leader }
func (n *Node) Term() uint64   { v, _ := strconv.ParseUint(n.raft.Stats()["term"], 10, 64); return v }
func (n *Node) SetProofPeerBlocked(peerID string, blocked bool) error {
	p, ok := n.pin.peer(peerID)
	if !ok || p.Role == Client || peerID == n.id {
		return ErrMembership
	}
	if n.stream == nil {
		return ErrScope
	}
	n.stream.block(peerID, blocked)
	return nil
}
func (n *Node) PhysicalDispatchStatus() error { return ErrPhysicalHeld }
func (n *Node) Close() error {
	n.mu.Lock()
	if n.closed {
		e := n.closeErr
		n.mu.Unlock()
		return e
	}
	n.closed = true
	n.mu.Unlock()
	var errs []error
	if n.raft != nil {
		errs = append(errs, n.raft.Shutdown().Error())
	}
	if n.transport != nil {
		errs = append(errs, n.transport.Close())
	} else if n.stream != nil {
		errs = append(errs, n.stream.Close())
	}
	if n.fsm != nil {
		errs = append(errs, n.fsm.close())
	}
	if n.bolt != nil {
		errs = append(errs, n.bolt.Close())
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	n.closeErr = errors.Join(errs...)
	return n.closeErr
}
