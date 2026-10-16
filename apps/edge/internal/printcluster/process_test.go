package printcluster

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// The HTTP controls below exist only in the child test binary, not Node or any
// application router. They are explicitly unauthenticated loopback fixtures.
// A relay retains original trusted Caller and envelope; it cannot mint origin
// authority. This proves synthetic fan-in, not production forwarding auth.
type processFixture struct {
	Marker   string            `json:"marker"`
	Root     string            `json:"root"`
	Pin      ClusterConfig     `json:"pin"`
	Controls map[string]string `json:"controls"`
}
type processCall struct {
	Op         string      `json:"op"`
	Raw        []byte      `json:"raw"`
	Caller     Caller      `json:"caller"`
	JobID      string      `json:"jobId"`
	AttemptID  string      `json:"attemptId"`
	Assignment *Assignment `json:"assignment"`
}
type processReply struct {
	MemberID     string      `json:"memberId"`
	Leader       bool        `json:"leader"`
	Term         uint64      `json:"term"`
	Error        string      `json:"error"`
	Receipt      Receipt     `json:"receipt"`
	Raw          []byte      `json:"raw"`
	ConfigRaw    []byte      `json:"configRaw"`
	State        string      `json:"state"`
	PrimaryState string      `json:"primaryState"`
	Assignment   *Assignment `json:"assignment"`
}

func httpFixtureCall(ctx context.Context, address string, c processCall) (processReply, error) {
	var reply processReply
	raw, e := json.Marshal(c)
	if e != nil {
		return reply, e
	}
	req, e := http.NewRequestWithContext(ctx, http.MethodPost, "http://"+address+"/call", bytes.NewReader(raw))
	if e != nil {
		return reply, e
	}
	client := &http.Client{Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true}, Timeout: 45 * time.Second}
	defer client.CloseIdleConnections()
	res, e := client.Do(req)
	if e != nil {
		return reply, e
	}
	defer res.Body.Close()
	b, e := io.ReadAll(io.LimitReader(res.Body, 2*MaxStateBytes))
	if e != nil {
		return reply, e
	}
	if strict(b, 2*MaxStateBytes, &reply) != nil {
		return reply, fmt.Errorf("invalid fixture response")
	}
	return reply, nil
}
func TestRaftProcessFixture(t *testing.T) {
	path := os.Getenv("VYNIC_PRINTCLUSTER_FIXTURE_JSON")
	if path == "" {
		t.Skip("subprocess fixture only")
	}
	raw, e := os.ReadFile(path)
	if e != nil {
		t.Fatal(e)
	}
	var f processFixture
	if strict(raw, 64*1024, &f) != nil || f.Marker != "synthetic-only-no-physical-send" || f.Pin.validate() != nil {
		t.Fatal("invalid explicit fixture")
	}
	id := os.Getenv("VYNIC_PRINTCLUSTER_FIXTURE_MEMBER")
	peer, ok := f.Pin.peer(id)
	if !ok || !loopbackAddress(f.Controls[id]) {
		t.Fatal("unknown fixture member")
	}
	var n *Node
	if peer.Role != Client {
		n, e = OpenLoopbackProof(filepath.Join(f.Root, id), f.Pin, id)
		if e != nil {
			t.Fatal(e)
		}
		defer n.Close()
	}
	listener, e := net.Listen("tcp", f.Controls[id])
	if e != nil {
		t.Fatal(e)
	}
	defer listener.Close()
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 40*time.Second)
		defer cancel()
		var c processCall
		b, e := io.ReadAll(io.LimitReader(r.Body, 2*MaxEnvelopeBytes))
		if e != nil || strict(b, 2*MaxEnvelopeBytes, &c) != nil {
			http.Error(w, "invalid synthetic command", 400)
			return
		}
		out := processReply{MemberID: id}
		if n != nil {
			out.Leader = n.IsLeader()
			out.Term = n.Term()
		}
		var failure error
		switch c.Op {
		case "status":
		case "relaySubmit":
			if !f.Pin.authorize(c.Caller, false) {
				failure = ErrScope
				break
			}
			var leaderAddress string
			for _, p := range f.Pin.Peers {
				if p.Role != Voter {
					continue
				}
				probeCtx, probeCancel := context.WithTimeout(ctx, time.Second)
				pout, err := httpFixtureCall(probeCtx, f.Controls[p.ID], processCall{Op: "status"})
				probeCancel()
				if err == nil && pout.Leader {
					leaderAddress = f.Controls[p.ID]
					break
				}
			}
			if leaderAddress == "" {
				failure = ErrNoQuorum
				break
			}
			c.Op = "submit"
			out, failure = httpFixtureCall(ctx, leaderAddress, c)
		default:
			if n == nil {
				failure = ErrMembership
				break
			}
			switch c.Op {
			case "bootstrap":
				failure = n.Bootstrap(ctx)
			case "config":
				conf, err := DecodeConfig(c.Raw)
				failure = err
				if err == nil {
					_, failure = n.InstallConfig(ctx, c.Caller, conf)
				}
			case "submit":
				j, err := DecodeJob(c.Raw)
				failure = err
				if err == nil {
					out.Receipt, failure = n.Submit(ctx, c.Caller, j)
				}
			case "claim":
				a, err := n.caller(n.id)
				failure = err
				if err == nil {
					x, err := n.ClaimLogical(ctx, a, c.JobID, c.AttemptID)
					failure = err
					if err == nil {
						out.Assignment = &x
					}
				}
			case "started":
				if c.Assignment == nil {
					failure = ErrInvalid
				} else {
					a, _ := n.caller(n.id)
					failure = n.MarkPrimaryStarted(ctx, a, *c.Assignment)
				}
			case "read", "inspect":
				var v JobView
				if c.Op == "read" {
					v, failure = n.ReadJob(ctx, c.JobID)
				} else {
					v, failure = n.InspectReplica(c.JobID)
				}
				if failure == nil {
					out.Raw = v.Job.Raw()
					out.Receipt = v.Receipt
					out.State = v.State
					out.PrimaryState = v.PrimaryState
					out.Assignment = v.Assignment
					n.fsm.mu.RLock()
					out.ConfigRaw = bytes.Clone(n.fsm.state.Configs[v.Job.ConfigSHA256])
					n.fsm.mu.RUnlock()
				}
			case "physical":
				failure = n.PhysicalDispatchStatus()
			default:
				failure = ErrInvalid
			}
		}
		if failure != nil {
			out.Error = failure.Error()
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(out)
	})
	server := &http.Server{Handler: handler, ReadHeaderTimeout: time.Second, ReadTimeout: 45 * time.Second, WriteTimeout: 45 * time.Second, MaxHeaderBytes: 4096}
	// The parent owns child process lifetime. No application startup or OS
	// service/credentials/configuration is touched by this fixture.
	if e = server.Serve(listener); e != nil && e != http.ErrServerClosed {
		t.Fatal(e)
	}
}

type childProcess struct {
	cmd    *exec.Cmd
	log    *os.File
	waited bool
}

func startProcess(t *testing.T, path, id, root string) *childProcess {
	t.Helper()
	log, e := os.OpenFile(filepath.Join(root, id+".process.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		t.Fatal(e)
	}
	cmd := exec.Command(os.Args[0], "-test.run=^TestRaftProcessFixture$", "-test.timeout=3m")
	cmd.Env = append(os.Environ(), "VYNIC_PRINTCLUSTER_FIXTURE_JSON="+path, "VYNIC_PRINTCLUSTER_FIXTURE_MEMBER="+id)
	cmd.Stdout = log
	cmd.Stderr = log
	if e = cmd.Start(); e != nil {
		_ = log.Close()
		t.Fatal(e)
	}
	return &childProcess{cmd: cmd, log: log}
}
func (p *childProcess) kill() error {
	if p == nil || p.waited {
		return nil
	}
	e := p.cmd.Process.Kill()
	w := p.cmd.Wait()
	p.waited = true
	_ = p.log.Close()
	if e != nil {
		return e
	}
	if exit, ok := w.(*exec.ExitError); ok && !exit.Success() {
		return nil
	}
	return w
}
func processReady(t *testing.T, address string) {
	t.Helper()
	deadline := time.Now().Add(12 * time.Second)
	for time.Now().Before(deadline) {
		ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
		_, e := httpFixtureCall(ctx, address, processCall{Op: "status"})
		cancel()
		if e == nil {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("child process listener not ready")
}
func processLeader(t *testing.T, f processFixture, dead string) string {
	t.Helper()
	deadline := time.Now().Add(12 * time.Second)
	for time.Now().Before(deadline) {
		for _, p := range f.Pin.Peers {
			if p.Role != Voter || p.ID == dead {
				continue
			}
			ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
			reply, e := httpFixtureCall(ctx, f.Controls[p.ID], processCall{Op: "status"})
			cancel()
			if e == nil && reply.Leader {
				return p.ID
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("surviving child processes did not elect leader")
	return ""
}
func callProcess(t *testing.T, f processFixture, id string, c processCall) processReply {
	t.Helper()
	ctx, cancel := proofContext()
	defer cancel()
	r, e := httpFixtureCall(ctx, f.Controls[id], c)
	if e != nil || r.Error != "" {
		t.Fatalf("child %s op %s: %v %s", id, c.Op, e, r.Error)
	}
	return r
}
func TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery(t *testing.T) {
	cfg, base := golden(t, "shared_tcp")
	pin := testPin(t, 3, VenueShared, base, false, true)
	root := t.TempDir()
	f := processFixture{Marker: "synthetic-only-no-physical-send", Root: root, Pin: pin, Controls: map[string]string{}}
	for _, p := range pin.Peers {
		f.Controls[p.ID] = freeAddress(t)
	}
	raw, _ := json.Marshal(f)
	path := filepath.Join(root, "fixture.json")
	if e := os.WriteFile(path, raw, 0600); e != nil {
		t.Fatal(e)
	}
	children := map[string]*childProcess{}
	t.Cleanup(func() {
		for id, p := range children {
			if e := p.kill(); e != nil {
				t.Log("child cleanup", id, e)
			}
		}
	})
	for _, p := range pin.Peers {
		children[p.ID] = startProcess(t, path, p.ID, root)
		processReady(t, f.Controls[p.ID])
	}
	callProcess(t, f, pin.Peers[0].ID, processCall{Op: "bootstrap"})
	leaderID := processLeader(t, f, "")
	a := Caller{MemberID: pin.Peers[0].ID, TerminalID: base.OriginTerminalID, InstallationID: base.OriginInstallationID}
	callProcess(t, f, leaderID, processCall{Op: "config", Caller: a, Raw: cfg.Raw()})
	for _, count := range []int{2, 3, 4} {
		t.Run(fmt.Sprintf("identical_job_actual_%d_process_POS_relays", count), func(t *testing.T) {
			j := newJob(t, base, 80+count, 600*1024)
			var wg sync.WaitGroup
			results := make(chan processReply, count)
			errs := make(chan error, count)
			for i := 0; i < count; i++ {
				id := pin.Peers[i].ID
				wg.Add(1)
				go func() {
					defer wg.Done()
					ctx, cancel := proofContext()
					defer cancel()
					r, e := httpFixtureCall(ctx, f.Controls[id], processCall{Op: "relaySubmit", Caller: a, Raw: j.Raw()})
					results <- r
					errs <- e
				}()
			}
			wg.Wait()
			close(results)
			close(errs)
			for e := range errs {
				if e != nil {
					t.Fatal(e)
				}
			}
			var first *Receipt
			for r := range results {
				if r.Error != "" || r.Receipt.Status != "ACCEPTED" {
					t.Fatalf("relay failure %s", r.Error)
				}
				if first == nil {
					v := r.Receipt
					first = &v
				} else if *first != r.Receipt {
					t.Fatal("fanin assigned multiple receipts")
				}
			}
			for _, p := range pin.Peers[:3] {
				deadline := time.Now().Add(8 * time.Second)
				for {
					ctx, cancel := context.WithTimeout(context.Background(), time.Second)
					out, e := httpFixtureCall(ctx, f.Controls[p.ID], processCall{Op: "inspect", JobID: j.JobID})
					cancel()
					if e == nil && out.Error == "" && bytes.Equal(out.Raw, j.Raw()) && out.Receipt == *first {
						break
					}
					if time.Now().After(deadline) {
						t.Fatal("FULL voter missing exact fanin payload")
					}
					time.Sleep(20 * time.Millisecond)
				}
			}
		})
	}
	// The first job is FIFO head; keep its admitted config/payload and mark a
	// synthetic STARTED before SIGKILL. The new leader may never resend it.
	j := newJob(t, base, 82, 600*1024)
	oldReceipt := callProcess(t, f, leaderID, processCall{Op: "submit", Caller: a, Raw: j.Raw()}).Receipt
	claim := callProcess(t, f, leaderID, processCall{Op: "claim", JobID: j.JobID, AttemptID: testUUID(4882)})
	callProcess(t, f, leaderID, processCall{Op: "started", Assignment: claim.Assignment})
	oldTerm := callProcess(t, f, leaderID, processCall{Op: "status"}).Term
	if e := children[leaderID].kill(); e != nil {
		t.Fatal(e)
	}
	children[leaderID] = nil
	t.Logf("actual SIGKILL of Raft leader process %s; original term=%d, remaining FULL voters=2/3", leaderID, oldTerm)
	newLeader := processLeader(t, f, leaderID)
	if newLeader == leaderID {
		t.Fatal("killed process reported leader")
	}
	v := callProcess(t, f, newLeader, processCall{Op: "read", JobID: j.JobID})
	if v.State != "UNCERTAIN" || v.PrimaryState != "UNCERTAIN" || v.Receipt != oldReceipt || !bytes.Equal(v.Raw, j.Raw()) || !bytes.Equal(v.ConfigRaw, cfg.Raw()) {
		t.Fatal("SIGKILL recovery lost immutable job/config or resent STARTED")
	}
	if retry := callProcess(t, f, newLeader, processCall{Op: "submit", Caller: a, Raw: j.Raw()}).Receipt; retry != oldReceipt {
		t.Fatal("new leader retry changed accepted result")
	}
	children[leaderID] = startProcess(t, path, leaderID, root)
	processReady(t, f.Controls[leaderID])
	deadline := time.Now().Add(12 * time.Second)
	for {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		v, e := httpFixtureCall(ctx, f.Controls[leaderID], processCall{Op: "inspect", JobID: j.JobID})
		cancel()
		if e == nil && v.Error == "" && v.State == "UNCERTAIN" && v.Receipt == oldReceipt && bytes.Equal(v.Raw, j.Raw()) && bytes.Equal(v.ConfigRaw, cfg.Raw()) {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("cold restarted leader did not rejoin with retained exact work")
		}
		time.Sleep(20 * time.Millisecond)
	}
	for _, p := range pin.Peers[:3] {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		held, e := httpFixtureCall(ctx, f.Controls[p.ID], processCall{Op: "physical"})
		cancel()
		if e != nil || !strings.Contains(held.Error, "held pending downstream fencing") {
			t.Fatal("process quorum opened physical RAW printing")
		}
	}
	t.Log("actual cold process restart rejoined fixed 3-voter membership; majority acceptance is logical only; no physical Send performed")
}
