package printpeer

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"os"
	"path/filepath"
	"sync"
	"time"
	"vynic.local/edge/internal/printcluster"
	"vynic.local/edge/internal/printerprovisioning"
	"vynic.local/edge/internal/printstation"
)

type Runtime struct {
	store           *printerprovisioning.ProductionStore
	transport       *Transport
	dir, id, device string
	mu              sync.RWMutex
	configMu        sync.Mutex
	node            *printcluster.Node
	local           *printcluster.LocalStationSpool
	done            chan struct{}
	wg              sync.WaitGroup
	closeOnce       sync.Once
	lastConfigError string
}
type Status struct {
	Installation       string            `json:"installation"`
	Leader             string            `json:"leader"`
	Role               string            `json:"role"`
	Membership         map[string]string `json:"membership"`
	MembershipIndex    uint64            `json:"membershipIndex"`
	PhysicalWriter     string            `json:"physicalWriter"`
	ConfigurationError string            `json:"configurationError,omitempty"`
}
type submitRequest struct {
	RequestID string           `json:"requestId"`
	Job       printstation.Job `json:"job"`
}
type queryRequest struct {
	StationID string `json:"stationId"`
	JobID     string `json:"jobId"`
}

func Open(dir string, store *printerprovisioning.ProductionStore) (*Runtime, error) {
	if !filepath.IsAbs(dir) {
		return nil, ErrDenied
	}
	if e := os.MkdirAll(dir, 0700); e != nil {
		return nil, e
	}
	real, e := filepath.EvalSymlinks(dir)
	if e != nil {
		return nil, e
	}
	t, e := NewTransport(store)
	if e != nil {
		return nil, e
	}
	id, device, _ := store.RuntimeIdentity()
	r := &Runtime{store: store, transport: t, dir: real, id: id, device: device, done: make(chan struct{})}
	if e = r.ensureNode(); e != nil {
		t.Close()
		return nil, e
	}
	t.Start(r.handle)
	r.wg.Add(1)
	go r.maintain()
	return r, nil
}
func (r *Runtime) ensureNode() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	b, e := r.store.Inventory()
	if e != nil {
		return e
	}
	role := ""
	for _, m := range b.Members {
		if m.InstallationID == r.id {
			role = m.Role
		}
	}
	if role != "VOTER" || r.node != nil {
		return nil
	}
	if e = r.transport.enableVoterListener(); e != nil {
		return e
	}
	_, _, issuer := r.store.RuntimeIdentity()
	pin := printcluster.ProductionPin(b, issuer)
	dir := filepath.Join(r.dir, "shared")
	_, e = os.Stat(filepath.Join(dir, "raft.bolt"))
	fresh := errors.Is(e, os.ErrNotExist)
	if e != nil && !fresh {
		return e
	}
	if e = r.store.ReserveQueue(b.ClusterID, dir, fresh); e != nil {
		return e
	}
	r.node, e = printcluster.OpenAuthenticated(dir, pin, r.id, r.transport)
	return e
}
func (r *Runtime) nodeValue() *printcluster.Node { r.mu.RLock(); defer r.mu.RUnlock(); return r.node }

// Initialize is explicit; ordinary startup/discovery/retry never bootstraps.
func (r *Runtime) Initialize(ctx context.Context) error {
	b, e := r.store.Inventory()
	if e != nil {
		return e
	}
	if b.Revision != 1 {
		return ErrDenied
	}
	n := r.nodeValue()
	if n == nil {
		return ErrDenied
	}
	return n.Bootstrap(ctx)
}
func (r *Runtime) maintain() {
	defer r.wg.Done()
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		select {
		case <-r.done:
			return
		case <-timer.C:
			ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
			e := r.Refresh(ctx)
			r.mu.Lock()
			r.lastConfigError = ""
			if e != nil {
				r.lastConfigError = e.Error()
			}
			r.mu.Unlock()
			cancel()
		}
	}
}
func (r *Runtime) Refresh(ctx context.Context) error {
	r.configMu.Lock()
	defer r.configMu.Unlock()
	if e := r.ensureNode(); e != nil {
		return e
	}
	n := r.nodeValue()
	if n == nil || !n.IsLeader() {
		return nil
	}
	raw, e := r.store.CurrentGrant()
	if e != nil {
		return e
	}
	return n.ConfigureProduction(ctx, raw)
}
func (r *Runtime) Status() Status {
	r.mu.RLock()
	configError := r.lastConfigError
	r.mu.RUnlock()
	s := Status{ConfigurationError: configError, Installation: r.id, PhysicalWriter: "HELD", Membership: map[string]string{}}
	b, e := r.store.Inventory()
	if e != nil {
		s.ConfigurationError = e.Error()
		return s
	}
	for _, m := range b.Members {
		if m.InstallationID == r.id {
			s.Role = m.Role
		}
	}
	if n := r.nodeValue(); n != nil {
		s.Leader = n.LeaderID()
		s.MembershipIndex, s.Membership = n.ProductionStatus()
	}
	return s
}
func (r *Runtime) Catalog(scope printstation.Scope) (printstation.Catalog, error) {
	b, e := r.store.Inventory()
	if e != nil {
		return printstation.Catalog{}, e
	}
	var full printstation.Catalog
	if json.Unmarshal(b.CatalogRaw, &full) != nil {
		return full, ErrDenied
	}
	owner := ""
	if scope == printstation.Local {
		owner = r.device
	}
	return full.ForQueue(scope, owner)
}
func (r *Runtime) checkJob(j printstation.Job, device string) error {
	c, e := r.Catalog(printstation.Shared)
	if e != nil {
		return e
	}
	s, ok := c.Station(j.StationID)
	if !ok || !s.Enabled || s.Scope != printstation.Shared || j.VenueID != c.VenueID || j.SourceDeviceID != device || j.ConfigDigest != c.Digest() || j.Validate() != nil || j.Reprint != nil {
		return ErrDenied
	}
	return nil
}
func (r *Runtime) handle(ctx context.Context, peer printerprovisioning.AuthenticatedMember, req envelope) response {
	n := r.nodeValue()
	if n == nil {
		return response{Error: "no shared replica"}
	}
	if !n.IsLeader() {
		return response{Error: "leader required", Leader: n.LeaderID()}
	}
	switch req.Kind {
	case "submit":
		var q submitRequest
		if decode(req.Body, &q) != nil || r.checkJob(q.Job, peer.DeviceID()) != nil {
			return response{Error: "denied"}
		}
		if _, e := r.store.Authorize(peer, q.Job.StationID, ""); e != nil {
			return response{Error: "denied"}
		}
		if e := r.Refresh(ctx); e != nil {
			return response{Error: "configuration unavailable"}
		}
		a := printcluster.Caller{MemberID: peer.InstallationID(), InstallationID: peer.InstallationID(), TerminalID: peer.DeviceID()}
		receipt, e := n.SubmitStation(ctx, a, q.RequestID, q.Job)
		if e != nil {
			return response{Error: e.Error()}
		}
		return response{Body: encode(receipt)}
	case "query":
		var q queryRequest
		if decode(req.Body, &q) != nil {
			return response{Error: "denied"}
		}
		if _, e := r.store.Authorize(peer, q.StationID, ""); e != nil {
			return response{Error: "denied"}
		}
		c, e := r.Catalog(printstation.Shared)
		if e != nil {
			return response{Error: "denied"}
		}
		if _, ok := c.Station(q.StationID); !ok {
			return response{Error: "denied"}
		}
		v, e := n.StationAdmission(ctx, q.StationID, q.JobID)
		if e != nil {
			return response{Error: e.Error()}
		}
		return response{Body: encode(v)}
	default:
		return response{Error: "unknown operation"}
	}
}

// All clients use actual peer RPC, including a source on the leader host.
// Timeouts leave commit outcome unknown; exact identity/bytes must be retained.
func (r *Runtime) Submit(ctx context.Context, request string, j printstation.Job) (printcluster.Receipt, error) {
	if r.checkJob(j, r.device) != nil {
		return printcluster.Receipt{}, ErrDenied
	}
	return r.call(ctx, "submit", submitRequest{request, j})
}
func (r *Runtime) Admission(ctx context.Context, station, job string) (printcluster.Receipt, error) {
	c, e := r.Catalog(printstation.Shared)
	if e != nil {
		return printcluster.Receipt{}, e
	}
	if _, ok := c.Station(station); !ok {
		return printcluster.Receipt{}, ErrDenied
	}
	return r.call(ctx, "query", queryRequest{station, job})
}
func (r *Runtime) call(ctx context.Context, kind string, arg any) (printcluster.Receipt, error) {
	var out printcluster.Receipt
	deadline, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	hint := ""
	for round := 0; round < 6; round++ {
		b, e := r.store.Inventory()
		if e != nil {
			return out, e
		}
		peers := []string{}
		if hint != "" {
			peers = append(peers, hint)
		}
		for _, m := range b.Members {
			if m.Authorized && m.Role == "VOTER" && m.InstallationID != hint {
				peers = append(peers, m.InstallationID)
			}
		}
		for _, id := range peers {
			reply, e := r.transport.exchange(deadline, id, false, kind, arg, &out, nil)
			if e == nil {
				return out, nil
			}
			if reply.Leader != "" {
				hint = reply.Leader
			}
			if deadline.Err() != nil {
				return printcluster.Receipt{}, ErrUnknown
			}
		}
		select {
		case <-deadline.Done():
			return printcluster.Receipt{}, ErrUnknown
		case <-time.After(time.Duration(1<<round) * 100 * time.Millisecond):
		}
	}
	return printcluster.Receipt{}, ErrUnknown
}

// LOCAL admission reuses the existing exclusive spool without network/quorum.
func (r *Runtime) SubmitLocal(request string, j printstation.Job) (printcluster.Receipt, error) {
	r.configMu.Lock()
	defer r.configMu.Unlock()
	c, e := r.Catalog(printstation.Local)
	if e != nil {
		return printcluster.Receipt{}, e
	}
	s, ok := c.Station(j.StationID)
	if !ok || !s.Enabled || j.SourceDeviceID != r.device || j.VenueID != c.VenueID || j.ConfigDigest != c.Digest() || j.Reprint != nil {
		return printcluster.Receipt{}, ErrDenied
	}
	a := printcluster.Caller{MemberID: r.id, InstallationID: r.id, TerminalID: r.device}
	if r.local == nil {
		b, e := r.store.Inventory()
		if e != nil {
			return printcluster.Receipt{}, e
		}
		_, _, issuer := r.store.RuntimeIdentity()
		p := printcluster.ProductionPin(b, issuer)
		p.Scope = printcluster.Local
		p.ClusterID = uuid.NewSHA1(uuid.MustParse(b.ClusterID), []byte(r.device)).String()
		p.Voters = 1
		p.Peers = []printcluster.Peer{{ID: r.id, InstallationID: r.id, TerminalID: r.device, DeviceID: r.device, Role: printcluster.Voter, Address: "127.0.0.1:1", FullData: true, Admin: true}}
		dir := filepath.Join(r.dir, "local")
		_, e = os.Stat(filepath.Join(dir, "projection.sqlite"))
		fresh := errors.Is(e, os.ErrNotExist)
		if e != nil && !fresh {
			return printcluster.Receipt{}, e
		}
		if e = r.store.ReserveQueue(p.ClusterID, dir, fresh); e != nil {
			return printcluster.Receipt{}, e
		}
		r.local, e = printcluster.OpenLocalAuthenticated(dir, p)
		if e != nil {
			return printcluster.Receipt{}, e
		}
	}
	if e = r.local.Install(a, c); e != nil {
		return printcluster.Receipt{}, e
	}
	return r.local.Submit(a, request, j)
}
func (r *Runtime) Close() error {
	var e error
	r.closeOnce.Do(func() {
		close(r.done)
		r.wg.Wait()
		if n := r.nodeValue(); n != nil {
			e = n.Close()
		} else {
			e = r.transport.Close()
		}
		if r.local != nil {
			e = errors.Join(e, r.local.Close())
		}
	})
	return e
}
func (r *Runtime) Snapshot(ctx context.Context) error {
	if _, e := r.store.Inventory(); e != nil {
		return e
	}
	if n := r.nodeValue(); n != nil {
		return n.Snapshot(ctx)
	}
	return ErrDenied
}
