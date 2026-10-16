package printcluster

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/hashicorp/raft"
)

func testUUID(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }
func golden(t *testing.T, name string) (ConfigSnapshot, Job) {
	t.Helper()
	craw, e := os.ReadFile(filepath.Join("testdata", name+".config.json"))
	if e != nil {
		t.Fatal(e)
	}
	jraw, e := os.ReadFile(filepath.Join("testdata", name+".job.json"))
	if e != nil {
		t.Fatal(e)
	}
	c, e := DecodeConfig(craw)
	if e != nil {
		t.Fatal(e)
	}
	j, e := DecodeJob(jraw)
	if e != nil {
		t.Fatal(e)
	}
	return c, j
}
func mutate(t *testing.T, raw []byte, change func(map[string]any)) []byte {
	t.Helper()
	var m map[string]any
	if e := json.Unmarshal(raw, &m); e != nil {
		t.Fatal(e)
	}
	change(m)
	b, e := json.Marshal(m)
	if e != nil {
		t.Fatal(e)
	}
	return b
}
func newJob(t *testing.T, base Job, n, primarySize int) Job {
	t.Helper()
	raw := mutate(t, base.Raw(), func(m map[string]any) {
		m["jobId"] = testUUID(1000 + n)
		m["effectId"] = testUUID(2000 + n)
		m["requestId"] = testUUID(3000 + n)
		if primarySize > 0 {
			b := bytes.Repeat([]byte{0x51}, primarySize)
			m["primaryBytes"] = b
			m["primarySha256"] = sha(b)
		}
	})
	j, e := DecodeJob(raw)
	if e != nil {
		t.Fatal(e)
	}
	return j
}
func freeAddress(t *testing.T) string {
	t.Helper()
	l, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	a := l.Addr().String()
	if e = l.Close(); e != nil {
		t.Fatal(e)
	}
	return a
}
func testPin(t *testing.T, count int, scope string, base Job, withNonvoter, withClient bool) ClusterConfig {
	t.Helper()
	p := ClusterConfig{Version: 1, Scope: scope, ClusterID: base.ClusterID, VenueID: base.VenueID, Voters: count}
	total := count
	if withNonvoter {
		total++
	}
	for i := 0; i < total; i++ {
		role := Voter
		if i == count {
			role = Nonvoter
		}
		peer := Peer{ID: testUUID(101 + i), Address: freeAddress(t), Role: role, FullData: true, TerminalID: testUUID(501 + i), InstallationID: testUUID(601 + i), DeviceID: testUUID(701 + i), Admin: i == 0}
		if i == 0 {
			peer.TerminalID = base.OriginTerminalID
			peer.InstallationID = base.OriginInstallationID
			peer.DeviceID = testUUID(4)
		}
		p.Peers = append(p.Peers, peer)
	}
	if withClient {
		p.Peers = append(p.Peers, Peer{ID: testUUID(201), Role: Client, TerminalID: testUUID(801), InstallationID: testUUID(901), DeviceID: testUUID(1001)})
	}
	return p
}

type testCluster struct {
	pin   ClusterConfig
	nodes []*Node
	dirs  []string
	t     *testing.T
}

func startCluster(t *testing.T, pin ClusterConfig) *testCluster {
	t.Helper()
	c := &testCluster{pin: pin, t: t}
	for _, p := range pin.Peers {
		if p.Role != Voter {
			continue
		}
		dir := filepath.Join(t.TempDir(), p.ID)
		n, e := OpenLoopbackProof(dir, pin, p.ID)
		if e != nil {
			t.Fatal(e)
		}
		c.nodes = append(c.nodes, n)
		c.dirs = append(c.dirs, dir)
	}
	t.Cleanup(func() {
		for _, n := range c.nodes {
			if n != nil {
				if e := n.Close(); e != nil {
					t.Log("close:", e)
				}
			}
		}
	})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if e := c.nodes[0].Bootstrap(ctx); e != nil {
		t.Fatal(e)
	}
	c.leader()
	return c
}
func (c *testCluster) leader() *Node {
	c.t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		for _, n := range c.nodes {
			if n == nil || !n.IsLeader() {
				continue
			}
			// A race-instrumented multi-megabyte projection can take longer than
			// a small RPC probe. Await the actual committed sync; do not enqueue
			// a stream of timed-out durable commands as a polling substitute.
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			started := time.Now()
			e := n.SyncLogicalState(ctx)
			cancel()
			if e != nil || time.Since(started) > 400*time.Millisecond {
				c.t.Logf("leader sync probe id=%s state=%s term=%d elapsed=%s err=%v", n.id, n.raft.State(), n.Term(), time.Since(started), e)
				if n.fsm.mu.TryRLock() {
					c.t.Logf("durable FSM broken=%v applied=%d term=%d stages=%d encodedBytes=%d", n.fsm.broken, n.fsm.state.AppliedIndex, n.fsm.state.Term, len(n.fsm.state.Stages), len(n.fsm.encoded))
					n.fsm.mu.RUnlock()
				} else {
					c.t.Log("durable FSM is applying; probe did not establish synchronization")
				}
			}
			if e == nil {
				return n
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	c.t.Fatal("no verified leader completed durable synchronization within bounded fixture budget")
	return nil
}
func (c *testCluster) index(n *Node) int {
	for i, v := range c.nodes {
		if v == n {
			return i
		}
	}
	return -1
}
func (c *testCluster) stop(n *Node) {
	c.t.Helper()
	i := c.index(n)
	if i < 0 {
		c.t.Fatal("unknown node")
	}
	if e := n.Close(); e != nil {
		c.t.Fatal(e)
	}
	c.nodes[i] = nil
}
func (c *testCluster) restart(i int) *Node {
	c.t.Helper()
	n, e := OpenLoopbackProof(c.dirs[i], c.pin, c.pin.Peers[i].ID)
	if e != nil {
		c.t.Fatal(e)
	}
	c.nodes[i] = n
	return n
}
func proofContext() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 45*time.Second)
}
func origin(t *testing.T, n *Node) Caller {
	t.Helper()
	a, e := n.caller(n.pin.Peers[0].ID)
	if e != nil {
		t.Fatal(e)
	}
	return a
}
func executor(t *testing.T, n *Node) Caller {
	t.Helper()
	a, e := n.caller(n.id)
	if e != nil {
		t.Fatal(e)
	}
	return a
}
func install(t *testing.T, n *Node, a Caller, c ConfigSnapshot) {
	t.Helper()
	ctx, cancel := proofContext()
	defer cancel()
	h, e := n.InstallConfig(ctx, a, c)
	if e != nil || h != c.Digest() {
		t.Fatalf("install %q %v", h, e)
	}
}
func submit(t *testing.T, n *Node, a Caller, j Job) Receipt {
	t.Helper()
	ctx, cancel := proofContext()
	defer cancel()
	r, e := n.Submit(ctx, a, j)
	if e != nil {
		t.Fatal(e)
	}
	return r
}
func allReplicas(t *testing.T, c *testCluster, j Job, r Receipt) {
	t.Helper()
	deadline := time.Now().Add(12 * time.Second)
	for time.Now().Before(deadline) {
		all := true
		for _, n := range c.nodes {
			if n == nil {
				continue
			}
			v, e := n.InspectReplica(j.JobID)
			if e != nil || v.Receipt != r || !bytes.Equal(v.Job.Raw(), j.Raw()) {
				all = false
				break
			}
		}
		if all {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("full-data replicas did not retain exact job/receipt")
}

func TestActualDartContractGoldens(t *testing.T) {
	for _, name := range []string{"shared_tcp", "local_tcp", "shared_usb", "unknown_beep"} {
		t.Run(name, func(t *testing.T) {
			c, j := golden(t, name)
			if j.ConfigSHA256 != c.Digest() || !j.matches(c) {
				t.Fatal("Go/Dart exact frozen contract mismatch")
			}
			if !bytes.Equal(j.Raw(), j.raw) || !bytes.Equal(c.Raw(), c.raw) {
				t.Fatal("retained raw changed")
			}
			if name == "unknown_beep" && initialBeep(j.CapabilityProfile) != "SKIPPED" {
				t.Fatal("unknown optional beep must silently skip")
			}
		})
	}
}
func TestStrictContractAndFrozenVisibleFields(t *testing.T) {
	c, j := golden(t, "shared_tcp")
	for _, tc := range []struct {
		name   string
		change func(map[string]any)
	}{
		{"unknown key", func(m map[string]any) { m["workerHostId"] = testUUID(5) }},
		{"route not uuid", func(m map[string]any) { m["routeId"] = "legacy_route" }},
		{"uppercase uuid", func(m map[string]any) { m["jobId"] = "00000000-0000-4000-8000-00000000000A" }},
		{"fraction revision", func(m map[string]any) { m["routeRevision"] = 1.5 }},
		{"zero revision", func(m map[string]any) { m["configRevision"] = 0 }},
		{"primary changed", func(m map[string]any) { m["primaryBytes"] = []byte("changed") }},
		{"primary unknown core", func(m map[string]any) { m["capabilityProfile"].(map[string]any)["rawCommand"] = "evil" }},
		{"unknown renderer held", func(m map[string]any) { m["capabilityProfile"].(map[string]any)["language"] = "windowsDriverRendered" }},
		{"tenant malformed", func(m map[string]any) { m["venueId"] = "other" }},
		{"reprint self", func(m map[string]any) { m["reprintOf"] = m["jobId"] }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, e := DecodeJob(mutate(t, j.Raw(), tc.change)); e == nil {
				t.Fatal("invalid job accepted")
			}
		})
	}
	for _, tc := range []struct {
		name   string
		change func(map[string]any)
	}{
		{"shared fixed tcp owner rejected", func(m map[string]any) { m["ownership"].(map[string]any)["kind"] = "device" }},
		{"foreign cluster owner", func(m map[string]any) { m["ownership"].(map[string]any)["ownerId"] = testUUID(99) }},
		{"control host", func(m map[string]any) { m["destination"].(map[string]any)["host"] = "evil\n" }},
		{"extra destination", func(m map[string]any) { m["destination"].(map[string]any)["raw"] = "arbitrary" }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, e := DecodeConfig(mutate(t, c.Raw(), tc.change)); e == nil {
				t.Fatal("invalid config accepted")
			}
		})
	}
	t.Run("duplicate nested key", func(t *testing.T) {
		raw := bytes.Replace(j.Raw(), []byte(`"role":"kitchen"`), []byte(`"role":"kitchen","role":"bar"`), 1)
		if _, e := DecodeJob(raw); e == nil {
			t.Fatal("duplicate accepted")
		}
	})
	t.Run("overdeep", func(t *testing.T) {
		raw := bytes.Repeat([]byte("["), 40)
		raw = append(raw, bytes.Repeat([]byte("]"), 40)...)
		if _, e := DecodeJob(raw); e == nil {
			t.Fatal("deep JSON accepted")
		}
	})
	t.Run("mutation job", func(t *testing.T) {
		j.PrimaryBytes[0] ^= 1
		if _, e := j.fresh(); e == nil {
			t.Fatal("exported field mutation accepted")
		}
	})
	t.Run("mutation config", func(t *testing.T) {
		c.Ownership.Generation++
		if _, e := c.fresh(); e == nil {
			t.Fatal("exported field mutation accepted")
		}
	})
}
func TestFixedFullDataMembershipPolicy(t *testing.T) {
	_, j := golden(t, "shared_tcp")
	for _, n := range []int{1, 2, 3, 5} {
		t.Run(fmt.Sprint(n), func(t *testing.T) {
			p := testPin(t, n, VenueShared, j, false, true)
			if p.validate() != nil {
				t.Fatal("valid pin refused")
			}
		})
	}
	for _, tc := range []struct {
		name   string
		change func(*ClusterConfig)
	}{
		{"four voters refused", func(p *ClusterConfig) { p.Voters = 4 }},
		{"witness refused", func(p *ClusterConfig) { p.Peers[2].FullData = false }},
		{"non-loopback refused", func(p *ClusterConfig) { p.Peers[0].Address = "192.0.2.1:1234" }},
		{"port overflow refused", func(p *ClusterConfig) { p.Peers[0].Address = "127.0.0.1:99999" }},
		{"duplicate id refused", func(p *ClusterConfig) { p.Peers[1].ID = p.Peers[0].ID }},
		{"duplicate device refused", func(p *ClusterConfig) { p.Peers[1].DeviceID = p.Peers[0].DeviceID }},
		{"duplicate installation refused", func(p *ClusterConfig) { p.Peers[1].InstallationID = p.Peers[0].InstallationID }},
		{"LOCAL not three", func(p *ClusterConfig) { p.Scope = Local }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := testPin(t, 3, VenueShared, j, false, false)
			tc.change(&p)
			if p.validate() == nil {
				t.Fatal("unsafe membership accepted")
			}
		})
	}
}

func TestThreeFullVotersMajorityDedupConfigFreezeAndRestart(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, true))
	leader := c.leader()
	a := origin(t, leader)
	install(t, leader, a, cfg)
	j := newJob(t, base, 1, 700*1024)
	r := submit(t, leader, a, j)
	allReplicas(t, c, j, r)
	t.Run("fan-in 2 3 4 preserves original origin and receipt", func(t *testing.T) {
		for _, count := range []int{2, 3, 4} {
			t.Run(fmt.Sprint(count), func(t *testing.T) {
				var wg sync.WaitGroup
				errs := make(chan error, count)
				for i := 0; i < count; i++ {
					wg.Add(1)
					go func() {
						defer wg.Done()
						ctx, cancel := proofContext()
						defer cancel()
						retry, e := leader.Submit(ctx, a, j)
						if e == nil && retry != r {
							e = fmt.Errorf("receipt changed")
						}
						errs <- e
					}()
				}
				wg.Wait()
				close(errs)
				for e := range errs {
					if e != nil {
						t.Fatal(e)
					}
				}
				leader.fsm.mu.RLock()
				n := len(leader.fsm.state.Jobs)
				leader.fsm.mu.RUnlock()
				if n != 1 {
					t.Fatal("duplicate admission")
				}
			})
		}
	})
	t.Run("changed input and actor rejected", func(t *testing.T) {
		changed, e := DecodeJob(mutate(t, j.Raw(), func(m map[string]any) { m["primaryBytes"] = []byte("other"); m["primarySha256"] = sha([]byte("other")) }))
		if e != nil {
			t.Fatal(e)
		}
		ctx, cancel := proofContext()
		defer cancel()
		if _, e = leader.Submit(ctx, a, changed); !errors.Is(e, ErrReuse) {
			t.Fatalf("changed request %v", e)
		}
		wrong := a
		wrong.MemberID = c.pin.Peers[1].ID
		if _, e = leader.Submit(ctx, wrong, j); !errors.Is(e, ErrScope) {
			t.Fatalf("changed actor %v", e)
		}
	})
	t.Run("committed configuration does not follow later endpoint edit", func(t *testing.T) {
		raw := mutate(t, cfg.Raw(), func(m map[string]any) {
			m["configRevision"] = 13
			m["routeRevision"] = 12
			m["ownership"].(map[string]any)["generation"] = 14
			m["destination"].(map[string]any)["host"] = "192.168.10.21"
		})
		next, e := DecodeConfig(raw)
		if e != nil {
			t.Fatal(e)
		}
		ctx, cancel := proofContext()
		defer cancel()
		if _, e = leader.InstallConfig(ctx, a, next); !errors.Is(e, ErrBusy) {
			t.Fatalf("endpoint changed with unfinished frozen work: %v", e)
		}
		x := executor(t, leader)
		assignment, e := leader.ClaimLogical(ctx, x, j.JobID, testUUID(4401))
		if e != nil {
			t.Fatal(e)
		}
		if e = leader.MarkPrimaryStarted(ctx, x, assignment); e != nil {
			t.Fatal(e)
		}
		if e = leader.MarkPrimarySubmitted(ctx, x, assignment); e != nil {
			t.Fatal(e)
		}
		if e = leader.MarkBeepSkipped(ctx, x, assignment); e != nil {
			t.Fatal(e)
		}
		install(t, leader, a, next)
		v, e := leader.ReadJob(ctx, j.JobID)
		if e != nil || v.Job.ConfigSHA256 != cfg.Digest() {
			t.Fatal("accepted job retargeted")
		}
		if retry := submit(t, leader, a, j); retry != r {
			t.Fatal("old retry changed")
		}
		stale := newJob(t, base, 2, 0)
		if _, e = leader.Submit(ctx, a, stale); !errors.Is(e, ErrConfig) {
			t.Fatalf("new stale config admission %v", e)
		}
		if _, e = leader.Submit(ctx, a, stale); !errors.Is(e, ErrConfig) {
			t.Fatalf("stale rejection retry changed %v", e)
		}
	})
	t.Run("cold restart all stores exact retained receipt", func(t *testing.T) {
		ctx, cancel := proofContext()
		defer cancel()
		if e := leader.Snapshot(ctx); e != nil {
			t.Fatal(e)
		}
		for i, n := range c.nodes {
			if n != nil {
				c.stop(n)
			}
			_ = i
		}
		for i := range c.dirs {
			c.restart(i)
		}
		leader = c.leader()
		if retry := submit(t, leader, a, j); retry != r {
			t.Fatal("restart changed durable receipt")
		}
		allReplicas(t, c, j, r)
		if leader.PhysicalDispatchStatus() != ErrPhysicalHeld {
			t.Fatal("quorum enabled physical print")
		}
	})
}
func TestLeaderLossInterruptionsAndOptionalBeepBarriers(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	j1 := newJob(t, base, 10, 0)
	j2 := newJob(t, base, 11, 0)
	submit(t, n, a, j1)
	submit(t, n, a, j2)
	ctx, cancel := proofContext()
	defer cancel()
	exec := executor(t, n)
	assignment, e := n.ClaimLogical(ctx, exec, j1.JobID, testUUID(4010))
	if e != nil {
		t.Fatal(e)
	}
	if e = n.MarkPrimaryStarted(ctx, exec, assignment); e != nil {
		t.Fatal(e)
	}
	old := n
	oldIndex := c.index(old)
	c.stop(old)
	n = c.leader()
	t.Run("new leader marks started uncertain and never resends", func(t *testing.T) {
		v, e := n.ReadJob(ctx, j1.JobID)
		if e != nil || v.State != "UNCERTAIN" || v.PrimaryState != "UNCERTAIN" {
			t.Fatalf("state %s %v", v.State, e)
		}
		if _, e = n.ClaimLogical(ctx, executor(t, n), j1.JobID, testUUID(4011)); !errors.Is(e, ErrBusy) {
			t.Fatalf("uncertain resent %v", e)
		}
		if _, e = n.ClaimLogical(ctx, executor(t, n), j2.JobID, testUUID(4012)); !errors.Is(e, ErrBusy) {
			t.Fatalf("FIFO crossed uncertainty %v", e)
		}
		if e = n.MarkPrimarySubmitted(ctx, exec, assignment); !errors.Is(e, ErrAssignment) {
			t.Fatalf("old claim updated %v", e)
		}
	})
	t.Run("operator settlement allows next immutable job", func(t *testing.T) {
		if e = n.ResolveNotPrinted(ctx, a, j1.JobID, "synthetic operator verified no paper"); e != nil {
			t.Fatal(e)
		}
		exec = executor(t, n)
		assignment, e = n.ClaimLogical(ctx, exec, j2.JobID, testUUID(4020))
		if e != nil {
			t.Fatal(e)
		}
		if e = n.MarkPrimaryStarted(ctx, exec, assignment); e != nil {
			t.Fatal(e)
		}
		if e = n.MarkPrimarySubmitted(ctx, exec, assignment); e != nil {
			t.Fatal(e)
		}
	})
	t.Run("optional beep holds FIFO until settled then never repeats", func(t *testing.T) {
		j3 := newJob(t, base, 12, 0)
		submit(t, n, a, j3)
		if _, e = n.ClaimLogical(ctx, exec, j3.JobID, testUUID(4021)); !errors.Is(e, ErrBusy) {
			t.Fatalf("crossed beep barrier %v", e)
		}
		if e = n.MarkBeepStarted(ctx, exec, assignment); e != nil {
			t.Fatal(e)
		}
		if e = n.MarkBeepUncertain(ctx, exec, assignment, "synthetic optional command interruption"); e != nil {
			t.Fatal(e)
		}
		if e = n.MarkBeepStarted(ctx, exec, assignment); !errors.Is(e, ErrAssignment) {
			t.Fatalf("beep auto-resend %v", e)
		}
		if _, e = n.ClaimLogical(ctx, exec, j3.JobID, testUUID(4022)); !errors.Is(e, ErrBusy) {
			t.Fatalf("uncertain old optional lifetime released FIFO: %v", e)
		}
	})
	t.Run("manual reprint fresh IDs committed actor and reason", func(t *testing.T) {
		raw := mutate(t, newJob(t, base, 13, 0).Raw(), func(m map[string]any) { m["reprintOf"] = j1.JobID })
		rj, e := DecodeJob(raw)
		if e != nil {
			t.Fatal(e)
		}
		r, e := n.Reprint(ctx, a, rj, "synthetic authorized manual reprint")
		if e != nil {
			t.Fatal(e)
		}
		retry, e := n.Reprint(ctx, a, rj, "synthetic authorized manual reprint")
		if e != nil || retry != r {
			t.Fatal("reprint receipt changed")
		}
		if _, e = n.Reprint(ctx, a, rj, "different reason"); !errors.Is(e, ErrReuse) {
			t.Fatalf("reprint reason changed %v", e)
		}
		n.fsm.mu.RLock()
		found := false
		for _, v := range n.fsm.state.Audit {
			if v.Kind == "MANUAL_REPRINT" && v.JobID == rj.JobID && v.Actor == a && v.ReprintOf == j1.JobID {
				found = true
			}
		}
		n.fsm.mu.RUnlock()
		if !found {
			t.Fatal("no committed reprint audit")
		}
	})
	t.Run("old node rejoins without independent recovery", func(t *testing.T) {
		c.restart(oldIndex)
		v, e := n.ReadJob(ctx, j1.JobID)
		if e != nil {
			t.Fatal(e)
		}
		allReplicas(t, c, j1, v.Receipt)
	})
}
func TestMinorityCannotAcceptOrUsePausedOldClaim(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, false))
	old := c.leader()
	a := origin(t, old)
	install(t, old, a, cfg)
	j := newJob(t, base, 20, 0)
	submit(t, old, a, j)
	ctx, cancel := proofContext()
	defer cancel()
	oldCaller := executor(t, old)
	assignment, e := old.ClaimLogical(ctx, oldCaller, j.JobID, testUUID(4050))
	if e != nil {
		t.Fatal(e)
	}
	for _, n := range c.nodes {
		if n != old {
			if e = old.SetProofPeerBlocked(n.id, true); e != nil {
				t.Fatal(e)
			}
			if e = n.SetProofPeerBlocked(old.id, true); e != nil {
				t.Fatal(e)
			}
		}
	}
	time.Sleep(400 * time.Millisecond)
	majority := c.leader()
	if majority == old {
		t.Fatal("isolated minority retained majority authority")
	}
	held, e := old.Submit(ctx, a, newJob(t, base, 21, 0))
	if e == nil || held.Status == "ACCEPTED" {
		t.Fatal("minority accepted")
	}
	if e = majority.MarkPrimaryStarted(ctx, oldCaller, assignment); !errors.Is(e, ErrAssignment) {
		t.Fatalf("paused old claim survived election %v", e)
	}
	replacement, e := majority.ClaimLogical(ctx, executor(t, majority), j.JobID, testUUID(4051))
	if e != nil || replacement.LeaderTerm <= assignment.LeaderTerm {
		t.Fatalf("new majority assignment %v", e)
	}
	submit(t, majority, a, newJob(t, base, 22, 0))
	for _, n := range c.nodes {
		if n != old {
			_ = old.SetProofPeerBlocked(n.id, false)
			_ = n.SetProofPeerBlocked(old.id, false)
		}
	}
}
func TestNonvoterAndClientDoNotCountTowardQuorum(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	pin := testPin(t, 3, VenueShared, base, true, true)
	c := startCluster(t, pin)
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	p := pin.Peers[3]
	dir := t.TempDir()
	follower, e := OpenLoopbackProof(dir, pin, p.ID)
	if e != nil {
		t.Fatal(e)
	}
	defer follower.Close()
	ctx, cancel := proofContext()
	defer cancel()
	index, m, e := n.Membership(ctx)
	if e != nil || len(m) != 3 {
		t.Fatal("clients joined voter configuration")
	}
	if e = n.ChangeNonvoter(ctx, a, p.ID, true, index); e != nil {
		t.Fatal(e)
	}
	index, m, e = n.Membership(ctx)
	if e != nil || m[p.ID] != "Nonvoter" || len(m) != 4 {
		t.Fatal("nonvoter not explicit")
	}
	j := newJob(t, base, 30, 0)
	r := submit(t, n, a, j)
	deadline := time.Now().Add(5 * time.Second)
	for {
		v, e := follower.InspectReplica(j.JobID)
		if e == nil && v.Receipt == r && bytes.Equal(v.Job.Raw(), j.Raw()) {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("nonvoter did not receive full payload")
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Run("stable pinned CAS membership", func(t *testing.T) {
		if e = n.ChangeNonvoter(ctx, a, p.ID, false, index-1); !errors.Is(e, ErrMembership) {
			t.Fatal("stale membership CAS accepted")
		}
		if e = n.ChangeNonvoter(ctx, a, pin.Peers[4].ID, true, index); !errors.Is(e, ErrMembership) {
			t.Fatal("client promoted")
		}
		if e = n.ChangeNonvoter(ctx, a, pin.Peers[1].ID, false, index); !errors.Is(e, ErrMembership) {
			t.Fatal("voter silently removed")
		}
	})
	t.Run("one voter plus nonvoter is not majority", func(t *testing.T) {
		for _, other := range c.nodes {
			if other != n {
				c.stop(other)
			}
		}
		time.Sleep(400 * time.Millisecond)
		ctx2, cancel2 := context.WithTimeout(context.Background(), time.Second)
		defer cancel2()
		if r, e := n.Submit(ctx2, a, newJob(t, base, 31, 0)); e == nil || r.Status == "ACCEPTED" {
			t.Fatal("nonvoter counted toward quorum")
		}
		if n.PhysicalDispatchStatus() != ErrPhysicalHeld {
			t.Fatal("physical dispatch opened")
		}
	})
}

func TestFullRasterChunkingSnapshotRestoreAndBounds(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	pin := testPin(t, 1, VenueShared, base, false, false)
	c := startCluster(t, pin)
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	j := newJob(t, base, 40, 8*1024*1024)
	m := metaFor(j, a, "")
	ctx, cancel := proofContext()
	defer cancel()
	if m.TotalChunks < 40 {
		t.Fatal("large raster not chunked")
	}
	for i := 0; i < m.TotalChunks/2; i++ {
		cmd := command{Op: "chunk", Caller: a, Meta: &m, ChunkIndex: i, Chunk: j.raw[i*ChunkBytes : i*ChunkBytes+m.chunkLength(i)]}
		encoded, _ := json.Marshal(cmd)
		if len(encoded) > raft.SuggestedMaxDataSize {
			t.Fatal("oversized Raft entry")
		}
		if _, e := n.apply(ctx, cmd); e != nil {
			t.Fatal(e)
		}
	}
	t.Run("no admission from incomplete majority durable staging", func(t *testing.T) {
		if _, e := n.InspectReplica(j.JobID); e == nil {
			t.Fatal("partial payload admitted")
		}
		if _, e := n.apply(ctx, command{Op: "finalize", Caller: a, Meta: &m}); !errors.Is(e, ErrInvalid) {
			t.Fatal("incomplete finalize accepted")
		}
	})
	t.Run("snapshot includes staged bytes and rejects tampering atomically", func(t *testing.T) {
		snap, e := n.fsm.Snapshot()
		if e != nil {
			t.Fatal(e)
		}
		raw := bytes.Clone(snap.(*projectionSnapshot).raw)
		f, e := openProjection(t.TempDir(), pin)
		if e != nil {
			t.Fatal(e)
		}
		defer f.close()
		if e = f.Restore(io.NopCloser(bytes.NewReader(raw))); e != nil {
			t.Fatal(e)
		}
		f.mu.RLock()
		st := f.state.Stages[j.RequestID]
		count := len(st.Chunks)
		before := bytes.Clone(f.encoded)
		f.mu.RUnlock()
		if count != m.TotalChunks/2 {
			t.Fatal("staging disappeared from snapshot")
		}
		bad := mutate(t, raw, func(m map[string]any) { m["clusterId"] = "bad" })
		if e = f.Restore(io.NopCloser(bytes.NewReader(bad))); e == nil {
			t.Fatal("tampered snapshot accepted")
		}
		f.mu.RLock()
		after := bytes.Clone(f.encoded)
		f.mu.RUnlock()
		if !bytes.Equal(before, after) {
			t.Fatal("failed restore replaced live state")
		}
	})
	t.Run("changed duplicate or out-of-range chunk refused", func(t *testing.T) {
		bad := bytes.Clone(j.raw[:ChunkBytes])
		bad[0] ^= 1
		if _, e := n.apply(ctx, command{Op: "chunk", Caller: a, Meta: &m, ChunkIndex: 0, Chunk: bad}); !errors.Is(e, ErrReuse) {
			t.Fatal("changed duplicate accepted")
		}
		if _, e := n.apply(ctx, command{Op: "chunk", Caller: a, Meta: &m, ChunkIndex: m.TotalChunks}); !errors.Is(e, ErrInvalid) {
			t.Fatal("out of range chunk accepted")
		}
	})
	if e := n.Snapshot(ctx); e != nil {
		t.Fatal(e)
	}
	idx := c.index(n)
	c.stop(n)
	n = c.restart(idx)
	n = c.leader()
	// The resumed full-envelope transfer has its own bounded lifetime; time
	// spent preparing/snapshotting earlier staging must not consume it.
	cancel()
	ctx, cancel = context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	r := submit(t, n, a, j)
	if r.Status != "ACCEPTED" {
		t.Fatal("full payload not finalized")
	}
	v, e := n.ReadJob(ctx, j.JobID)
	if e != nil || !bytes.Equal(v.Job.PrimaryBytes, j.PrimaryBytes) || !bytes.Equal(v.Job.Raw(), j.Raw()) {
		t.Fatal("raster payload truncated or changed")
	}
	if retry := submit(t, n, a, j); retry != r {
		t.Fatal("large retry changed receipt")
	}
}

func TestProjectionRollbackReplayAndMalformedSnapshots(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	pin := testPin(t, 1, VenueShared, base, false, false)
	dir := t.TempDir()
	f, e := openProjection(dir, pin)
	if e != nil {
		t.Fatal(e)
	}
	defer f.close()
	f.StoreConfiguration(1, raft.Configuration{Servers: []raft.Server{{ID: raft.ServerID(pin.Peers[0].ID), Address: raft.ServerAddress(pin.Peers[0].Address), Suffrage: raft.Voter}}})
	a := Caller{MemberID: pin.Peers[0].ID, TerminalID: base.OriginTerminalID, InstallationID: base.OriginInstallationID}
	cmd := command{Version: 2, Op: "config", Caller: a, Raw: cfg.Raw(), MembershipGeneration: 1}
	raw, _ := json.Marshal(cmd)
	f.afterWrite = func() error { return fmt.Errorf("synthetic after-write failure") }
	r := f.Apply(&raft.Log{Index: 2, Term: 1, Data: raw}).(result)
	if !errors.Is(r.Err, ErrStorage) {
		t.Fatal("storage failure returned success")
	}
	var index uint64
	var persisted []byte
	if e = f.db.QueryRow("SELECT applied_index,state_json FROM printcluster_projection WHERE id=1").Scan(&index, &persisted); e != nil {
		t.Fatal(e)
	}
	if index != 1 || bytes.Contains(persisted, []byte(cfg.Digest())) {
		t.Fatal("SQL transaction leaked config/index")
	}
	f.mu.Lock()
	f.broken = false
	f.afterWrite = nil
	f.mu.Unlock()
	r = f.Apply(&raft.Log{Index: 2, Term: 1, Data: raw}).(result)
	if r.Err != nil || r.ConfigDigest != cfg.Digest() {
		t.Fatal("replay did not recover committed config")
	}
	before := bytes.Clone(f.encoded)
	f.Apply(&raft.Log{Index: 2, Term: 1, Data: raw})
	if !bytes.Equal(before, f.encoded) {
		t.Fatal("replayed applied index mutated state")
	}
	for _, tc := range []struct {
		name   string
		change func(*projection)
	}{
		{"nil journal", func(s *projection) { s.Requests = nil }},
		{"foreign pin", func(s *projection) { s.Pin.ClusterID = testUUID(888) }},
		{"bad config bytes", func(s *projection) { s.Configs[cfg.Digest()] = []byte(`{}`) }},
		{"contradictory enum and missing journal", func(s *projection) {
			s.Jobs[base.JobID] = &storedJob{Raw: base.Raw(), Receipt: Receipt{Status: "ACCEPTED", JobID: base.JobID, InputSHA256: base.Digest(), Sequence: 1, CommitIndex: 2}, State: "PRIMARY_SUBMITTED", PrimaryState: "NOT_STARTED", BeepState: "STARTED"}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var s projection
			snapshot, err := f.Snapshot()
			if err != nil {
				t.Fatal(err)
			}
			if e := json.Unmarshal(snapshot.(*projectionSnapshot).raw, &s); e != nil {
				t.Fatal(e)
			}
			tc.change(&s)
			b, _ := json.Marshal(s)
			if e := f.Restore(io.NopCloser(bytes.NewReader(b))); e == nil {
				t.Fatal("malformed snapshot accepted")
			}
			if !bytes.Equal(before, f.encoded) {
				t.Fatal("restore corrupted prior state")
			}
		})
	}
}
func TestDurableHalfLossAndForeignIdentityRefused(t *testing.T) {
	_, base := golden(t, "shared_tcp")
	pin := testPin(t, 1, VenueShared, base, false, false)
	for _, missing := range []string{"raft.bolt", "projection.sqlite"} {
		t.Run(missing, func(t *testing.T) {
			dir := t.TempDir()
			n, e := OpenLoopbackProof(dir, pin, pin.Peers[0].ID)
			if e != nil {
				t.Fatal(e)
			}
			if e = n.Close(); e != nil {
				t.Fatal(e)
			}
			if e = os.Remove(filepath.Join(dir, missing)); e != nil {
				t.Fatal(e)
			}
			if n, e = OpenLoopbackProof(dir, pin, pin.Peers[0].ID); !errors.Is(e, ErrStorage) {
				if n != nil {
					_ = n.Close()
				}
				t.Fatalf("partial durable state reopened: %v", e)
			}
		})
	}
	t.Run("changed pin address", func(t *testing.T) {
		dir := t.TempDir()
		n, e := OpenLoopbackProof(dir, pin, pin.Peers[0].ID)
		if e != nil {
			t.Fatal(e)
		}
		_ = n.Close()
		changed := canonicalPin(pin)
		changed.Peers[0].Address = freeAddress(t)
		if n, e = OpenLoopbackProof(dir, changed, changed.Peers[0].ID); !errors.Is(e, ErrMembership) {
			if n != nil {
				_ = n.Close()
			}
			t.Fatal("changed membership pin reopened")
		}
	})
}
func TestEndpointAliasesAndFixedDeviceLogicalExecutor(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 3, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	ctx, cancel := proofContext()
	defer cancel()
	alias, e := DecodeConfig(mutate(t, cfg.Raw(), func(m map[string]any) {
		m["physicalPrinterId"] = testUUID(199)
		m["routeId"] = testUUID(198)
		m["destination"].(map[string]any)["host"] = "192.168.10.20."
	}))
	if e != nil {
		t.Fatal(e)
	}
	if _, e = n.InstallConfig(ctx, a, alias); !errors.Is(e, ErrConfig) {
		t.Fatal("same endpoint acquired distinct physical identity")
	}
	usb, uj := golden(t, "shared_usb")
	usbRaw := mutate(t, usb.Raw(), func(m map[string]any) { m["physicalPrinterId"] = testUUID(299); m["routeId"] = testUUID(298) })
	usb, e = DecodeConfig(usbRaw)
	if e != nil {
		t.Fatal(e)
	}
	install(t, n, a, usb)
	uj, e = DecodeJob(mutate(t, uj.Raw(), func(m map[string]any) {
		m["physicalPrinterId"] = usb.PhysicalPrinterID
		m["routeId"] = usb.RouteID
		m["configSha256"] = usb.Digest()
	}))
	if e != nil {
		t.Fatal(e)
	}
	submit(t, n, a, uj)
	wrong, _ := n.caller(c.pin.Peers[1].ID)
	if _, e = n.ClaimLogical(ctx, wrong, uj.JobID, testUUID(499)); !errors.Is(e, ErrAssignment) {
		t.Fatal("fixed Device config executed by another host")
	}
	_, e = n.ClaimLogical(ctx, a, uj.JobID, testUUID(498))
	if n.id == a.MemberID {
		if e != nil {
			t.Fatal(e)
		}
	} else if !errors.Is(e, ErrAssignment) {
		t.Fatal("follower Device ownership became leader dispatch authority")
	}
	if n.PhysicalDispatchStatus() != ErrPhysicalHeld {
		t.Fatal("logical owner activated USB printer")
	}
}

func TestFiveFullVotersRequireThree(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	c := startCluster(t, testPin(t, 5, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	stopped := 0
	for _, v := range c.nodes {
		if v != n && stopped < 2 {
			c.stop(v)
			stopped++
		}
	}
	r := submit(t, n, a, newJob(t, base, 60, 0))
	if r.Status != "ACCEPTED" {
		t.Fatal("3/5 majority refused")
	}
	for _, v := range c.nodes {
		if v != nil && v != n {
			c.stop(v)
			break
		}
	}
	time.Sleep(400 * time.Millisecond)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if r, e := n.Submit(ctx, a, newJob(t, base, 61, 0)); e == nil || r.Status == "ACCEPTED" {
		t.Fatal("2/5 minority accepted")
	}
}

func TestSnapshotResultReceiptStable(t *testing.T) {
	cfg, base := golden(t, "unknown_beep")
	c := startCluster(t, testPin(t, 1, VenueShared, base, false, false))
	n := c.leader()
	a := origin(t, n)
	install(t, n, a, cfg)
	r := submit(t, n, a, base)
	ctx, cancel := proofContext()
	defer cancel()
	v, e := n.ReadJob(ctx, base.JobID)
	if e != nil || v.BeepState != "SKIPPED" {
		t.Fatal("unknown beep affected primary admission")
	}
	snap, e := n.fsm.Snapshot()
	if e != nil {
		t.Fatal(e)
	}
	f, e := openProjection(t.TempDir(), c.pin)
	if e != nil {
		t.Fatal(e)
	}
	defer f.close()
	if e = f.Restore(io.NopCloser(bytes.NewReader(snap.(*projectionSnapshot).raw))); e != nil {
		t.Fatal(e)
	}
	v, e = f.view(base.JobID)
	if e != nil || !reflect.DeepEqual(v.Receipt, r) || !bytes.Equal(v.Job.Raw(), base.Raw()) {
		t.Fatal("snapshot did not retain exact accepted outcome")
	}
}
