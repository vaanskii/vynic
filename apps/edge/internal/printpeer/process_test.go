//go:build printerfixture

package printpeer

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"vynic.local/edge/internal/printcluster"
	"vynic.local/edge/internal/printerprovisioning"
	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

type fixtureCommand struct {
	Op      string
	Grant   []byte
	Request string
	Job     printstation.Job
	Station string
	ID      string
	Now     int64
	Target  string
}
type fixtureResult struct {
	Error      string
	Enrollment printerprovisioning.EnrollmentRequest
	Status     Status
	Receipt    printcluster.Receipt
	Digest     string
}

func TestPeerProcess(t *testing.T) {
	if os.Getenv("VYNIC_PEER_FIXTURE") != "1" {
		t.Skip("subprocess entrypoint")
	}
	if bind := os.Getenv("VYNIC_PEER_BIND"); bind != "" {
		listenTCP = func(network, _ string) (net.Listener, error) { return net.Listen(network, bind) }
	}
	pub, e := base64.RawStdEncoding.DecodeString(os.Getenv("VYNIC_PEER_ISSUER"))
	if e != nil {
		t.Fatal(e)
	}
	var clockMu sync.Mutex
	var clock int64
	now := func() time.Time {
		clockMu.Lock()
		defer clockMu.Unlock()
		if clock != 0 {
			return time.Unix(clock, 0)
		}
		return time.Now()
	}
	s, e := printerprovisioning.OpenProcessFixture(filepath.Join(os.Getenv("VYNIC_PEER_DIR"), "identity"), os.Getenv("VYNIC_PEER_DEVICE"), pub, now)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	enc := json.NewEncoder(os.Stdout)
	dec := json.NewDecoder(os.Stdin)
	_ = enc.Encode(fixtureResult{Enrollment: s.Enrollment()})
	var r *Runtime
	var held *tls.Conn
	defer func() {
		if r != nil {
			r.Close()
		}
	}()
	for {
		var c fixtureCommand
		if e = dec.Decode(&c); e == io.EOF {
			return
		} else if e != nil {
			t.Fatal(e)
		}
		out := fixtureResult{}
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		switch c.Op {
		case "grant":
			e = s.Apply(c.Grant)
			if e == nil && r == nil {
				r, e = Open(filepath.Join(os.Getenv("VYNIC_PEER_DIR"), "queues"), s)
			}
			if e == nil {
				e = r.Refresh(ctx)
			}
		case "bootstrap":
			e = r.Initialize(ctx)
		case "status":
			out.Status = r.Status()
			e = nil
		case "submit":
			out.Receipt, e = r.Submit(ctx, c.Request, c.Job)
		case "local":
			out.Receipt, e = r.SubmitLocal(c.Request, c.Job)
		case "query":
			out.Receipt, e = r.Admission(ctx, c.Station, c.ID)
		case "snapshot":
			e = r.Snapshot(ctx)
		case "clock":
			clockMu.Lock()
			clock = c.Now
			clockMu.Unlock()
			e = nil
		case "dropAck":
			m, ce := r.transport.current(c.Target, false)
			if ce != nil {
				e = ce
				break
			}
			cfg, ce := s.TLSConfig(false, c.Target)
			if ce != nil {
				e = ce
				break
			}
			conn, ce := tls.DialWithDialer(&net.Dialer{Timeout: time.Second}, "tcp", m.EndpointHint, cfg)
			if ce != nil {
				e = ce
				break
			}
			conn.SetDeadline(time.Now().Add(rpcTimeout))
			e = writeFrame(conn, envelope{1, r.transport.venue, r.transport.cluster, "submit", encode(submitRequest{c.Request, c.Job})})
			conn.Close()
			if e == nil {
				e = ErrUnknown
			}
		case "inspect":
			var record printstation.Record
			record, e = r.nodeValue().InspectStationReplica(c.ID)
			if e == nil {
				out.Digest = printerprovisioning.SHA256(record.Job.Payload)
			}
		case "connect":
			m, ce := r.transport.current(c.Target, false)
			if ce != nil {
				e = ce
				break
			}
			cfg, ce := s.TLSConfig(false, c.Target)
			if ce != nil {
				e = ce
				break
			}
			held, e = tls.DialWithDialer(&net.Dialer{Timeout: time.Second}, "tcp", m.EndpointHint, cfg)
		case "connectedSubmit":
			if held == nil {
				e = ErrDenied
				break
			}
			held.SetDeadline(time.Now().Add(time.Second))
			e = writeFrame(held, envelope{1, r.transport.venue, r.transport.cluster, "submit", encode(submitRequest{c.Request, c.Job})})
			if e == nil {
				var reply response
				e = readFrame(held, &reply)
				if e == nil && reply.Error != "" {
					e = fmt.Errorf("remote refused")
				}
			}
			held.Close()
			held = nil
		case "rawSubmit":
			var rec printcluster.Receipt
			_, e = r.transport.exchange(ctx, c.Target, false, "submit", submitRequest{c.Request, c.Job}, &rec, nil)
			out.Receipt = rec
		case "raftAsClient":
			_, e = r.transport.exchange(ctx, c.Target, false, "raft/vote", map[string]any{}, nil, nil)
		case "stop":
			cancel()
			_ = enc.Encode(out)
			return
		default:
			e = fmt.Errorf("unknown fixture command")
		}
		cancel()
		if e != nil {
			out.Error = e.Error()
		}
		_ = enc.Encode(out)
	}
}

type process struct {
	t                         *testing.T
	cmd                       *exec.Cmd
	in                        io.WriteCloser
	dec                       *json.Decoder
	dir, device, pub, address string
	bind                      string
	enrollment                printerprovisioning.EnrollmentRequest
	mu                        sync.Mutex
	stopped                   bool
	log                       *os.File
}

func (p *process) start() {
	p.stopped = false
	p.cmd = exec.Command(os.Args[0], "-test.run=^TestPeerProcess$", "-test.timeout=5m")
	p.cmd.Env = append(os.Environ(), "VYNIC_PEER_FIXTURE=1", "VYNIC_PEER_DIR="+p.dir, "VYNIC_PEER_DEVICE="+p.device, "VYNIC_PEER_ISSUER="+p.pub, "VYNIC_PEER_BIND="+p.bind)
	var e error
	p.in, e = p.cmd.StdinPipe()
	if e != nil {
		p.t.Fatal(e)
	}
	out, e := p.cmd.StdoutPipe()
	if e != nil {
		p.t.Fatal(e)
	}
	p.dec = json.NewDecoder(out)
	p.log, e = os.OpenFile(filepath.Join(p.dir, "stderr.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if e != nil {
		p.t.Fatal(e)
	}
	p.cmd.Stderr = p.log
	if e = p.cmd.Start(); e != nil {
		p.t.Fatal(e)
	}
	var r fixtureResult
	if e = p.dec.Decode(&r); e != nil {
		raw, _ := os.ReadFile(filepath.Join(p.dir, "stderr.log"))
		p.t.Fatalf("process start: %v %s", e, raw)
	}
	if p.enrollment.InstallationID != "" && p.enrollment.InstallationID != r.Enrollment.InstallationID {
		p.t.Fatal("identity changed")
	}
	p.enrollment = r.Enrollment
}
func (p *process) call(c fixtureCommand) fixtureResult {
	p.mu.Lock()
	defer p.mu.Unlock()
	if e := json.NewEncoder(p.in).Encode(c); e != nil {
		p.t.Fatal(e)
	}
	var r fixtureResult
	if e := p.dec.Decode(&r); e != nil {
		raw, _ := os.ReadFile(filepath.Join(p.dir, "stderr.log"))
		p.t.Fatalf("process response %s: %v %s", c.Op, e, raw)
	}
	return r
}
func (p *process) stop(kill bool) {
	if p.stopped {
		return
	}
	p.stopped = true
	if kill {
		_ = p.cmd.Process.Kill()
	} else {
		p.call(fixtureCommand{Op: "stop"})
	}
	p.in.Close()
	_ = p.cmd.Wait()
	p.log.Close()
	raw, e := os.ReadFile(filepath.Join(p.dir, "stderr.log"))
	if e != nil {
		p.t.Error(e)
	} else if bytes.Contains(raw, []byte("WARNING: DATA RACE")) {
		p.t.Errorf("child race detector:\n%s", raw)
	}
}

type fleet struct {
	t       *testing.T
	nodes   []*process
	key     ed25519.PrivateKey
	body    printerprovisioning.ProductionBody
	catalog printstation.Catalog
}

func newFleet(t *testing.T, count, voters int) *fleet {
	t.Helper()
	pub, key, _ := ed25519.GenerateKey(rand.Reader)
	f := &fleet{t: t, key: key}
	now := time.Now().Unix()
	f.body = printerprovisioning.ProductionBody{Version: 1, Purpose: printerprovisioning.ProductionPurpose, VenueID: uuid.NewString(), ClusterID: uuid.NewString(), Generation: 1, Revision: 1, IssuedAt: now, NotBefore: now, ExpiresAt: now + printerprovisioning.OfflineSeconds, OfflineMaxSeconds: printerprovisioning.OfflineSeconds, Topology: "SINGLE_REPLICA"}
	if voters == 3 {
		f.body.Topology = "THREE_REPLICAS"
	}
	if voters == 0 {
		f.body.Topology = "LOCAL_ONLY"
	}
	for i := 0; i < count; i++ {
		dir := t.TempDir()
		p := &process{t: t, dir: dir, device: uuid.NewString(), pub: base64.RawStdEncoding.EncodeToString(pub)}
		l, e := net.Listen("tcp", "127.0.0.1:0")
		if e != nil {
			t.Fatal(e)
		}
		p.address = l.Addr().String()
		l.Close()
		p.start()
		t.Cleanup(func() { p.stop(true) })
		f.nodes = append(f.nodes, p)
		role := "CLIENT"
		if i < voters {
			role = "VOTER"
		}
		en := p.enrollment
		f.body.Members = append(f.body.Members, printerprovisioning.ProductionMember{InstallationID: en.InstallationID, DeviceID: p.device, PublicKey: en.PublicKey, CertificateSHA256: printerprovisioning.SHA256(en.Certificate), Authorized: true, Role: role, EndpointHint: p.address})
	}
	c := printstation.Catalog{Version: 1, VenueID: f.body.VenueID, Revision: 1, Rules: []printstation.Rule{}}
	p := f.nodes[0]
	controller := uuid.NewString()
	c.Controllers = []printstation.Controller{{ID: controller, InstallationID: p.enrollment.InstallationID, DeviceID: p.device, Name: "fixed controller"}}
	for i, name := range []string{"Main Kitchen", "Bar", "Cold Kitchen", "Desserts", "Expo"} {
		pid := uuid.NewString()
		c.Printers = append(c.Printers, printstation.PhysicalPrinter{ID: pid, Name: name, ControllerID: controller, Destination: printtransport.Destination{PhysicalPrinterID: pid, WorkerHostID: controller, Transport: printtransport.TCP, Host: fmt.Sprintf("192.168.254.%d", i+1), Port: 9100, DocumentName: "never sent"}, Profile: json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"none","encoding":"georgianViaRaster"}`), Enabled: true, FailoverMode: printstation.FixedController})
		scope := printstation.Shared
		owner := ""
		if voters == 0 {
			scope = printstation.Local
			owner = p.device
		}
		c.Stations = append(c.Stations, printstation.Station{ID: uuid.NewString(), Name: name, Role: "custom", Scope: scope, OwnerDeviceID: owner, Enabled: true, Routes: []string{pid}})
	}
	f.catalog = c
	f.body.CatalogRaw = encode(c)
	return f
}
func (f *fleet) signed() []byte {
	b := encode(f.body)
	input := append([]byte(printerprovisioning.ProductionDomain), digestBytes(b)...)
	return encode(printerprovisioning.SignedGrant{Body: b, Signature: ed25519.Sign(f.key, input)})
}
func (f *fleet) apply() {
	for _, p := range f.nodes {
		if p.stopped {
			continue
		}
		r := p.call(fixtureCommand{Op: "grant", Grant: f.signed()})
		if r.Error != "" && r.Error != "cluster has no verified leader quorum" {
			f.t.Fatal("grant", r.Error)
		}
	}
}
func (f *fleet) ready(want int) *process {
	f.t.Helper()
	deadline := time.Now().Add(25 * time.Second)
	for time.Now().Before(deadline) {
		for _, p := range f.nodes {
			if p.stopped {
				continue
			}
			s := p.call(fixtureCommand{Op: "status"}).Status
			if s.PhysicalWriter != "HELD" {
				f.t.Fatal("physical writer")
			}
			if s.Leader == p.enrollment.InstallationID && len(s.Membership) == want {
				return p
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	f.t.Fatal("no ready majority leader")
	return nil
}
func (f *fleet) start(voters int) {
	f.apply()
	if voters > 0 {
		r := f.nodes[0].call(fixtureCommand{Op: "bootstrap"})
		if r.Error != "" {
			f.t.Fatal(r.Error)
		}
		f.ready(voters)
	}
}
func (f *fleet) job(p *process, n, size, station int) printstation.Job {
	c, e := f.catalog.ForQueue(printstation.Shared, "")
	if f.body.Topology == "LOCAL_ONLY" {
		c, e = f.catalog.ForQueue(printstation.Local, p.device)
	}
	if e != nil {
		f.t.Fatal(e)
	}
	effect := fmt.Sprintf("ticket-%d", n)
	payload := bytes.Repeat([]byte{byte(n % 251)}, size)
	sid := c.Stations[station].ID
	return printstation.Job{Version: 1, ID: printstation.OutputID(c.VenueID, effect, sid, "production"), VenueID: c.VenueID, StationID: sid, SourceDeviceID: p.device, EffectID: effect, OutputKind: "production", BusinessRef: effect, ConfigDigest: c.Digest(), CreatedAt: time.Now().Unix(), Payload: payload, PayloadDigest: printerprovisioning.SHA256(payload)}
}
func digestBytes(b []byte) []byte { h := sha256.Sum256(b); return h[:] }
func TestPeerProcessTopology(t *testing.T) {
	for _, count := range []int{1, 2, 3, 4, 10} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			v := 1
			if count >= 3 {
				v = 3
			}
			f := newFleet(t, count, v)
			f.start(v)
			for i, p := range f.nodes {
				for station := 0; station < 5; station++ {
					j := f.job(p, i*5+station, 4096, station)
					req := uuid.NewString()
					out := p.call(fixtureCommand{Op: "submit", Request: req, Job: j})
					if out.Error != "" {
						t.Fatal("submit", out.Error)
					}
					again := p.call(fixtureCommand{Op: "submit", Request: req, Job: j})
					if again.Error != "" || again.Receipt != out.Receipt {
						t.Fatal("exact retry", again)
					}
					if out.Receipt.Sequence != uint64(i+1) {
						t.Fatal("FIFO", out)
					}
					q := p.call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
					if q.Error != "" || q.Receipt != out.Receipt {
						t.Fatal("query", q)
					}
				}
			}
		})
	}
}
func TestPeerProcessLocalOnly(t *testing.T) {
	f := newFleet(t, 1, 0)
	f.start(0)
	p := f.nodes[0]
	j := f.job(p, 1, 1024, 0)
	req := uuid.NewString()
	a := p.call(fixtureCommand{Op: "local", Request: req, Job: j})
	if a.Error != "" {
		t.Fatal(a.Error)
	}
	p.stop(true)
	p.start()
	f.apply()
	b := p.call(fixtureCommand{Op: "local", Request: req, Job: j})
	if b.Error != "" || b.Receipt != a.Receipt {
		t.Fatal(b)
	}
	if s := p.call(fixtureCommand{Op: "status"}).Status; len(s.Membership) != 0 {
		t.Fatal("local Raft dependency")
	}
}

func TestPeerProcessRecovery(t *testing.T) {
	f := newFleet(t, 4, 3)
	f.start(3)
	leader := f.ready(3)
	client := f.nodes[3]
	j := f.job(client, 700, 700<<10, 0)
	req := uuid.NewString()
	lost := client.call(fixtureCommand{Op: "dropAck", Target: leader.enrollment.InstallationID, Request: req, Job: j})
	if lost.Error == "" {
		t.Fatal("did not discard ACK")
	}
	receipt := client.call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
	if receipt.Error != "" {
		t.Fatal(receipt.Error)
	}
	client.stop(false)
	client.start()
	f.apply()
	leader.stop(true)
	next := f.ready(3)
	if next == leader {
		t.Fatal("dead leader")
	}
	retry := client.call(fixtureCommand{Op: "submit", Request: req, Job: j})
	if retry.Error != "" || retry.Receipt != receipt.Receipt {
		t.Fatal("lost ACK/leader durable recovery", retry)
	}
	// Kill another voter: a lone voter cannot acknowledge a new job.
	var other *process
	for _, p := range f.nodes[:3] {
		if p != leader && p != next {
			other = p
		}
	}
	other.stop(true)
	minorityJob := f.job(client, 701, 4096, 1)
	minorityReq := uuid.NewString()
	bad := client.call(fixtureCommand{Op: "submit", Request: minorityReq, Job: minorityJob})
	if bad.Error == "" {
		t.Fatal("minority committed")
	}
	other.start()
	f.apply()
	f.ready(3)
	ok := client.call(fixtureCommand{Op: "submit", Request: minorityReq, Job: minorityJob})
	if ok.Error != "" {
		t.Fatal("majority recovery", ok.Error)
	}
	leader.start()
	f.apply()
	f.ready(3)
	again := leader.call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
	if again.Error != "" || again.Receipt != receipt.Receipt {
		t.Fatal("rejoin", again)
	}
	leader = f.ready(3)
	if out := leader.call(fixtureCommand{Op: "snapshot"}); out.Error != "" {
		t.Fatal("snapshot", out.Error)
	}
	for _, p := range f.nodes {
		p.stop(true)
	}
	for _, p := range f.nodes {
		p.start()
	}
	f.apply()
	f.ready(3)
	end := f.nodes[3].call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
	if end.Error != "" || end.Receipt != receipt.Receipt {
		t.Fatal("all restart", end)
	}
	for _, p := range f.nodes[:3] {
		v := p.call(fixtureCommand{Op: "inspect", ID: j.ID})
		if v.Error != "" || v.Digest != j.PayloadDigest {
			t.Fatal("full replica payload", v)
		}
	}
}
func TestPeerProcessJoinAndExpansion(t *testing.T) {
	f := newFleet(t, 3, 1)
	// First signed inventory contains POS1 only, then enrollment adds clients.
	all := append([]printerprovisioning.ProductionMember(nil), f.body.Members...)
	for i := 1; i < len(all); i++ {
		all[i].EndpointHint = ""
	}
	f.body.Members = all[:1]
	one := f.nodes[:1]
	rest := f.nodes[1:]
	f.nodes = one
	f.start(1)
	j := f.job(one[0], 800, 1024, 0)
	req := uuid.NewString()
	accepted := one[0].call(fixtureCommand{Op: "submit", Request: req, Job: j})
	if accepted.Error != "" {
		t.Fatal(accepted.Error)
	}
	f.nodes = append(one, rest...)
	f.body.Members = all
	f.body.Generation++
	f.apply()
	f.ready(1)
	for i, p := range rest {
		r := p.call(fixtureCommand{Op: "submit", Request: uuid.NewString(), Job: f.job(p, 810+i, 1024, 1)})
		if r.Error != "" {
			t.Fatal("new client", r.Error)
		}
	}
	f.body.Generation++
	f.body.Revision++
	f.body.Topology = "THREE_REPLICAS"
	for i := range f.body.Members {
		f.body.Members[i].Role = "VOTER"
		f.body.Members[i].EndpointHint = f.nodes[i].address
	}
	f.catalog.Revision++
	f.body.CatalogRaw = encode(f.catalog)
	// Provision joining replicas first; the established host then journals the
	// signed transition into its existing log. No fresh bootstrap is issued.
	raw := f.signed()
	for _, p := range rest {
		r := p.call(fixtureCommand{Op: "grant", Grant: raw})
		if r.Error != "" {
			t.Fatal(r.Error)
		}
	}
	r := one[0].call(fixtureCommand{Op: "grant", Grant: raw})
	if r.Error != "" {
		t.Fatal(r.Error)
	}
	f.ready(3)
	// Source failure after controlled expansion preserves prior exact receipts.
	one[0].stop(true)
	f.ready(3)
	q := rest[0].call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
	if q.Error != "" || q.Receipt != accepted.Receipt {
		t.Fatal("existing queue lost", q)
	}
	one[0].start()
	f.apply()
	f.ready(3)
}
func TestPeerProcessSecurity(t *testing.T) {
	f := newFleet(t, 2, 1)
	f.start(1)
	client := f.nodes[1]
	leader := f.nodes[0]
	target := leader.enrollment.InstallationID
	j := f.job(client, 900, 1024, 0)
	t.Run("client_cannot_raft", func(t *testing.T) {
		if r := client.call(fixtureCommand{Op: "raftAsClient", Target: target}); r.Error == "" {
			t.Fatal("client joined raft")
		}
	})
	t.Run("foreign_device", func(t *testing.T) {
		bad := j
		bad.SourceDeviceID = uuid.NewString()
		if r := client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: bad}); r.Error == "" {
			t.Fatal("device spoof")
		}
	})
	t.Run("unknown_station", func(t *testing.T) {
		bad := j
		bad.StationID = uuid.NewString()
		if r := client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: bad}); r.Error == "" {
			t.Fatal("unknown station")
		}
	})
	t.Run("foreign_venue", func(t *testing.T) {
		bad := j
		bad.VenueID = uuid.NewString()
		if r := client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: bad}); r.Error == "" {
			t.Fatal("venue spoof")
		}
	})
	t.Run("tampered_grant", func(t *testing.T) {
		var g printerprovisioning.SignedGrant
		_ = json.Unmarshal(f.signed(), &g)
		g.Body[10] ^= 1
		if r := client.call(fixtureCommand{Op: "grant", Grant: encode(g)}); r.Error == "" {
			t.Fatal("tampered")
		}
	})
	t.Run("stale_generation", func(t *testing.T) {
		old := f.signed()
		f.body.Generation++
		f.apply()
		if r := client.call(fixtureCommand{Op: "grant", Grant: old}); r.Error == "" {
			t.Fatal("stale")
		}
	})
	t.Run("clock_rollback", func(t *testing.T) {
		r := client.call(fixtureCommand{Op: "clock", Now: f.body.IssuedAt - 1})
		if r.Error != "" {
			t.Fatal(r)
		}
		if r = client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: j}); r.Error == "" {
			t.Fatal("rollback")
		}
		client.call(fixtureCommand{Op: "clock"})
	})
	t.Run("expiry", func(t *testing.T) {
		client.call(fixtureCommand{Op: "clock", Now: f.body.ExpiresAt})
		if r := client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: j}); r.Error == "" {
			t.Fatal("expired")
		}
		client.call(fixtureCommand{Op: "clock"})
	})
	t.Run("learned_revocation", func(t *testing.T) {
		f.body.Generation++
		f.body.Members[1].Authorized = false
		r := leader.call(fixtureCommand{Op: "grant", Grant: f.signed()})
		if r.Error != "" {
			t.Fatal(r.Error)
		}
		if r = client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: j}); r.Error == "" {
			t.Fatal("revoked")
		}
		leader.stop(true)
		leader.start()
		r = leader.call(fixtureCommand{Op: "grant", Grant: f.signed()})
		if r.Error != "" {
			t.Fatal(r.Error)
		}
		f.ready(1)
		if r = client.call(fixtureCommand{Op: "rawSubmit", Target: target, Request: uuid.NewString(), Job: j}); r.Error == "" {
			t.Fatal("revoked restart")
		}
	})
}

func TestPeerProcessPerformance(t *testing.T) {
	for _, count := range []int{1, 3, 10} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			v := 1
			if count >= 3 {
				v = 3
			}
			f := newFleet(t, count, v)
			f.start(v)
			for _, size := range []int{4 << 10, 512 << 10} {
				var samples []float64
				var mu sync.Mutex
				var wg sync.WaitGroup
				for round := 0; round < 2; round++ {
					for i, p := range f.nodes {
						j := f.job(p, 10000+size+round*count+i, size, round%2)
						wg.Add(1)
						go func() {
							defer wg.Done()
							start := time.Now()
							r := p.call(fixtureCommand{Op: "submit", Request: uuid.NewString(), Job: j})
							ms := float64(time.Since(start).Microseconds()) / 1000
							if r.Error != "" {
								t.Errorf("network admission: %s", r.Error)
							}
							mu.Lock()
							samples = append(samples, ms)
							mu.Unlock()
						}()
					}
					wg.Wait()
				}
				sort.Float64s(samples)
				t.Logf("PERFORMANCE %s", encode(map[string]any{"sources": count, "voters": v, "payloadBytes": size, "samplesMs": samples, "p50Ms": samples[(len(samples)-1)/2], "p95Ms": samples[int(float64(len(samples)-1)*.95)], "maxMs": samples[len(samples)-1], "transport": "separate-process TCP TLS1.3 loopback", "payloads": "distinct per job"}))
			}
		})
	}
}

func TestPeerProcessOpenConnectionRevocation(t *testing.T) {
	f := newFleet(t, 2, 1)
	f.start(1)
	client, server := f.nodes[1], f.nodes[0]
	j := f.job(client, 1001, 1024, 0)
	if r := client.call(fixtureCommand{Op: "connect", Target: server.enrollment.InstallationID}); r.Error != "" {
		t.Fatal(r.Error)
	}
	f.body.Generation++
	f.body.Members[1].Authorized = false
	if r := server.call(fixtureCommand{Op: "grant", Grant: f.signed()}); r.Error != "" {
		t.Fatal(r.Error)
	}
	if r := client.call(fixtureCommand{Op: "connectedSubmit", Request: uuid.NewString(), Job: j}); r.Error == "" {
		t.Fatal("open session retained revoked authority")
	}
}
func TestPeerProcessForeignIdentity(t *testing.T) {
	for _, mode := range []string{"unknown", "foreignVenue", "wrongCluster", "mismatchedCertificate"} {
		t.Run(mode, func(t *testing.T) {
			f := newFleet(t, 1, 1)
			f.start(1)
			other := newFleet(t, 1, 0)
			member := other.body.Members[0]
			member.Role = "CLIENT"
			other.body.Members = append(append([]printerprovisioning.ProductionMember(nil), f.body.Members...), member)
			other.body.Topology = f.body.Topology
			other.body.VenueID = f.body.VenueID
			other.body.ClusterID = f.body.ClusterID
			other.catalog = f.catalog
			if mode == "foreignVenue" {
				other.body.VenueID = uuid.NewString()
				other.catalog.VenueID = other.body.VenueID
			}
			if mode == "wrongCluster" {
				other.body.ClusterID = uuid.NewString()
			}
			other.body.CatalogRaw = encode(other.catalog)
			if mode != "unknown" {
				if mode == "mismatchedCertificate" {
					member.CertificateSHA256 = printerprovisioning.SHA256([]byte("different DER"))
				}
				f.body.Members = append(f.body.Members, member)
				f.body.Generation++
				f.apply()
			}
			other.apply()
			p := other.nodes[0]
			j := other.job(p, 1002, 1024, 0)
			out := p.call(fixtureCommand{Op: "rawSubmit", Target: f.nodes[0].enrollment.InstallationID, Request: uuid.NewString(), Job: j})
			if out.Error == "" {
				t.Fatal("foreign peer accepted")
			}
		})
	}
}
func TestPeerProcessLocalScopeAndTamperedMembership(t *testing.T) {
	f := newFleet(t, 2, 1)
	f.catalog.Stations[4].Scope = printstation.Local
	f.catalog.Stations[4].OwnerDeviceID = f.nodes[0].device
	f.body.CatalogRaw = encode(f.catalog)
	f.start(1)
	p := f.nodes[1]
	j := f.job(p, 1003, 1024, 0)
	j.StationID = f.catalog.Stations[4].ID
	if r := p.call(fixtureCommand{Op: "rawSubmit", Target: f.nodes[0].enrollment.InstallationID, Request: uuid.NewString(), Job: j}); r.Error == "" {
		t.Fatal("foreign LOCAL")
	}
	f.body.Generation++
	f.body.Members[1].Role = "VOTER"
	if r := p.call(fixtureCommand{Op: "grant", Grant: f.signed()}); r.Error == "" {
		t.Fatal("two voters configuration accepted")
	}
}
func TestPeerProcessNoImplicitBootstrap(t *testing.T) {
	f := newFleet(t, 3, 3)
	f.apply()
	for _, p := range f.nodes {
		if s := p.call(fixtureCommand{Op: "status"}).Status; s.Leader != "" || len(s.Membership) != 0 {
			t.Fatal("implicit bootstrap")
		}
	}
	// A newly provisioned expansion replica cannot bootstrap revision two.
	f.body.Generation++
	f.body.Revision++
	f.catalog.Revision++
	f.body.CatalogRaw = encode(f.catalog)
	f.apply()
	if r := f.nodes[1].call(fixtureCommand{Op: "bootstrap"}); r.Error == "" {
		t.Fatal("expansion peer bootstrapped another cluster")
	}
}

func TestPeerProcessInterruptedExpansion(t *testing.T) {
	f := newFleet(t, 3, 1)
	f.start(1)
	first := f.nodes[0]
	j := f.job(first, 1100, 4096, 0)
	accepted := first.call(fixtureCommand{Op: "submit", Request: uuid.NewString(), Job: j})
	if accepted.Error != "" {
		t.Fatal(accepted.Error)
	}
	f.body.Generation++
	f.body.Revision++
	f.body.Topology = "THREE_REPLICAS"
	f.catalog.Revision++
	f.body.CatalogRaw = encode(f.catalog)
	for i := range f.body.Members {
		f.body.Members[i].Role = "VOTER"
	}
	for _, p := range f.nodes[1:] {
		if r := p.call(fixtureCommand{Op: "grant", Grant: f.signed()}); r.Error != "" {
			t.Fatal(r.Error)
		}
		p.stop(true)
	}
	// The established host commits the target, then cannot finish promotion while
	// both new replicas are absent. Kill and resume from its durable journal.
	r := first.call(fixtureCommand{Op: "grant", Grant: f.signed()})
	if r.Error == "" {
		t.Fatal("expansion claimed quorum without new replicas")
	}
	first.stop(true)
	for _, p := range f.nodes {
		p.start()
	}
	f.apply()
	f.ready(3)
	q := f.nodes[2].call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
	if q.Error != "" || q.Receipt != accepted.Receipt {
		t.Fatal("interrupted transition lost queue", q)
	}
}
func TestPeerProcessUnauthenticatedAndOversize(t *testing.T) {
	f := newFleet(t, 1, 1)
	f.start(1)
	c, e := net.DialTimeout("tcp", f.nodes[0].address, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	c.SetDeadline(time.Now().Add(time.Second))
	_ = writeFrame(c, envelope{Version: 1})
	var reply response
	if readFrame(c, &reply) == nil {
		t.Fatal("plaintext accepted")
	}
	c.Close()
	var b bytes.Buffer
	_ = binary.Write(&b, binary.BigEndian, uint32(maxFrame+1))
	if readFrame(&b, &reply) == nil {
		t.Fatal("oversize accepted")
	}
}

// tcpRelay forwards opaque TLS bytes. Partitioning closes actual TCP streams;
// it never calls a simulated Raft transport or changes authentication results.
type tcpRelay struct {
	listener net.Listener
	target   string
	mu       sync.Mutex
	blocked  bool
	conns    map[net.Conn]bool
	wg       sync.WaitGroup
}

func newRelay(t *testing.T, address, target string) *tcpRelay {
	l, e := net.Listen("tcp", address)
	if e != nil {
		t.Fatal(e)
	}
	r := &tcpRelay{listener: l, target: target, conns: map[net.Conn]bool{}}
	r.wg.Add(1)
	go func() {
		defer r.wg.Done()
		for {
			c, e := l.Accept()
			if e != nil {
				return
			}
			r.mu.Lock()
			if r.blocked {
				r.mu.Unlock()
				c.Close()
				continue
			}
			r.conns[c] = true
			r.mu.Unlock()
			r.wg.Add(1)
			go func() {
				defer r.wg.Done()
				defer func() { r.mu.Lock(); delete(r.conns, c); r.mu.Unlock(); c.Close() }()
				up, e := net.DialTimeout("tcp", target, time.Second)
				if e != nil {
					return
				}
				defer up.Close()
				done := make(chan struct{})
				go func() { io.Copy(up, c); up.Close(); close(done) }()
				io.Copy(c, up)
				c.Close()
				<-done
			}()
		}
	}()
	t.Cleanup(func() { l.Close(); r.block(true); r.wg.Wait() })
	return r
}
func (r *tcpRelay) block(b bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.blocked = b
	if b {
		for c := range r.conns {
			c.Close()
		}
	}
}
func TestPeerProcessTCPPartition(t *testing.T) {
	f := newFleet(t, 4, 3)
	relays := map[*process]*tcpRelay{}
	for _, p := range f.nodes[:3] {
		p.stop(true)
		l, e := net.Listen("tcp", "127.0.0.1:0")
		if e != nil {
			t.Fatal(e)
		}
		p.bind = l.Addr().String()
		l.Close()
		relays[p] = newRelay(t, p.address, p.bind)
		p.start()
	}
	f.start(3)
	leader := f.ready(3)
	client := f.nodes[3]
	j := f.job(client, 1200, 4096, 0)
	req := uuid.NewString()
	before := client.call(fixtureCommand{Op: "submit", Request: req, Job: j})
	if before.Error != "" {
		t.Fatal(before.Error)
	}
	for p, r := range relays {
		if p != leader {
			r.block(true)
		}
	}
	blockedJob := f.job(client, 1201, 4096, 1)
	blockedReq := uuid.NewString()
	if out := client.call(fixtureCommand{Op: "submit", Request: blockedReq, Job: blockedJob}); out.Error == "" {
		t.Fatal("minority network partition committed")
	}
	for _, r := range relays {
		r.block(false)
	}
	f.ready(3)
	after := client.call(fixtureCommand{Op: "submit", Request: blockedReq, Job: blockedJob})
	if after.Error != "" {
		t.Fatal("TCP reconnect", after.Error)
	}
	exact := client.call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID})
	if exact.Error != "" || exact.Receipt != before.Receipt {
		t.Fatal("partition changed receipt", exact)
	}
}

func TestPeerProcessOpenConnectionExpiry(t *testing.T) {
	f := newFleet(t, 2, 1)
	f.start(1)
	client, server := f.nodes[1], f.nodes[0]
	j := f.job(client, 1300, 1024, 0)
	if r := client.call(fixtureCommand{Op: "connect", Target: server.enrollment.InstallationID}); r.Error != "" {
		t.Fatal(r.Error)
	}
	server.call(fixtureCommand{Op: "clock", Now: f.body.ExpiresAt})
	if r := client.call(fixtureCommand{Op: "connectedSubmit", Request: uuid.NewString(), Job: j}); r.Error == "" {
		t.Fatal("open session extended expired authority")
	}
	server.call(fixtureCommand{Op: "clock"})
}

func TestPeerProcessOfflineWindow(t *testing.T) {
	f := newFleet(t, 2, 1)
	f.start(1)
	for _, p := range f.nodes {
		p.call(fixtureCommand{Op: "clock", Now: f.body.ExpiresAt - 1})
	}
	j := f.job(f.nodes[1], 1400, 1024, 0)
	out := f.nodes[1].call(fixtureCommand{Op: "submit", Request: uuid.NewString(), Job: j})
	if out.Error != "" {
		t.Fatal("valid offline grant", out.Error)
	}
	for _, p := range f.nodes {
		p.call(fixtureCommand{Op: "clock", Now: f.body.ExpiresAt})
	}
	if out = f.nodes[1].call(fixtureCommand{Op: "query", Station: j.StationID, ID: j.ID}); out.Error == "" {
		t.Fatal("expired receipt query")
	}
}
func TestPeerProcessLostStoreRefusesReplacement(t *testing.T) {
	f := newFleet(t, 1, 1)
	f.start(1)
	p := f.nodes[0]
	p.stop(true)
	if e := os.RemoveAll(filepath.Join(p.dir, "queues", "shared")); e != nil {
		t.Fatal(e)
	}
	p.start()
	if out := p.call(fixtureCommand{Op: "grant", Grant: f.signed()}); out.Error == "" {
		t.Fatal("lost queue silently replaced")
	}
}
