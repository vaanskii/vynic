// Package printpeer connects production-authorized installations to the existing
// logical queue. It intentionally has no physical dispatch or printer transport.
package printpeer

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"sync"
	"time"

	"github.com/hashicorp/raft"
	"vynic.local/edge/internal/printcluster"
	"vynic.local/edge/internal/printerprovisioning"
)

// Listener factory is private; subprocess fixtures replace it before startup
// to place a real TCP fault relay in front of the signed endpoint.
var listenTCP = net.Listen

const maxFrame = 16 << 20
const rpcTimeout = 8 * time.Second

var ErrDenied = errors.New("printer peer authorization/configuration denied")
var ErrUnknown = errors.New("admission outcome unknown; query or retry exact identity")

type envelope struct {
	Version int             `json:"version"`
	Venue   string          `json:"venue"`
	Cluster string          `json:"cluster"`
	Kind    string          `json:"kind"`
	Body    json.RawMessage `json:"body"`
}
type response struct {
	Body   json.RawMessage `json:"body,omitempty"`
	Error  string          `json:"error,omitempty"`
	Leader string          `json:"leader,omitempty"`
}

func encode(v any) []byte {
	b, e := json.Marshal(v)
	if e != nil {
		panic(e)
	}
	return b
}
func decode(b []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		return e
	}
	if d.Decode(new(any)) != io.EOF {
		return ErrDenied
	}
	return nil
}
func writeFrame(w io.Writer, v any) error {
	b, e := json.Marshal(v)
	if e != nil || len(b) > maxFrame {
		return ErrDenied
	}
	var h [4]byte
	binary.BigEndian.PutUint32(h[:], uint32(len(b)))
	if _, e = w.Write(h[:]); e != nil {
		return e
	}
	_, e = w.Write(b)
	return e
}
func readFrame(r io.Reader, v any) error {
	var h [4]byte
	if _, e := io.ReadFull(r, h[:]); e != nil {
		return e
	}
	n := binary.BigEndian.Uint32(h[:])
	if n == 0 || n > maxFrame {
		return ErrDenied
	}
	b := make([]byte, n)
	if _, e := io.ReadFull(r, b); e != nil {
		return e
	}
	return decode(b, v)
}

type Transport struct {
	store                               *printerprovisioning.ProductionStore
	id, device, venue, cluster, address string
	listener                            net.Listener
	consumer                            chan raft.RPC
	done                                chan struct{}
	once                                sync.Once
	wg                                  sync.WaitGroup
	mu                                  sync.Mutex
	connections                         map[net.Conn]bool
	slots                               chan struct{}
	requests                            chan struct{}
	outgoing                            chan struct{}
	handler                             func(context.Context, printerprovisioning.AuthenticatedMember, envelope) response
}

func NewTransport(store *printerprovisioning.ProductionStore) (*Transport, error) {
	b, e := store.Inventory()
	if e != nil {
		return nil, e
	}
	id, device, _ := store.RuntimeIdentity()
	address := ""
	for _, m := range b.Members {
		if m.InstallationID == id {
			address = m.EndpointHint
		}
	}
	t := &Transport{store: store, id: id, device: device, venue: b.VenueID, cluster: b.ClusterID, address: address, consumer: make(chan raft.RPC, 16), done: make(chan struct{}), connections: map[net.Conn]bool{}, slots: make(chan struct{}, 32), requests: make(chan struct{}, 8), outgoing: make(chan struct{}, 32)}
	if address != "" {
		t.listener, e = listenTCP("tcp", address)
		if e != nil {
			return nil, e
		}
	}
	return t, nil
}
func (t *Transport) Start(handler func(context.Context, printerprovisioning.AuthenticatedMember, envelope) response) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.handler = handler
	if t.listener != nil {
		t.wg.Add(1)
		go t.accept()
	}
}

// A client may initially have no endpoint. Only a verified voter assignment
// can open its first listener; existing endpoint movement is not automatic.
func (t *Transport) enableVoterListener() error {
	m, e := t.current(t.id, true)
	if e != nil || m.EndpointHint == "" {
		return ErrDenied
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	select {
	case <-t.done:
		return ErrDenied
	default:
	}
	if t.listener != nil {
		if t.address != m.EndpointHint {
			return ErrDenied
		}
		return nil
	}
	l, e := listenTCP("tcp", m.EndpointHint)
	if e != nil {
		return e
	}
	t.listener = l
	t.address = m.EndpointHint
	if t.handler != nil {
		t.wg.Add(1)
		go t.accept()
	}
	return nil
}
func (t *Transport) current(peer string, voter bool) (printerprovisioning.ProductionMember, error) {
	b, e := t.store.Inventory()
	if e != nil || b.VenueID != t.venue || b.ClusterID != t.cluster {
		return printerprovisioning.ProductionMember{}, ErrDenied
	}
	selfVoter := false
	var found printerprovisioning.ProductionMember
	for _, m := range b.Members {
		if m.InstallationID == t.id {
			selfVoter = m.Role == "VOTER"
		}
		if m.InstallationID == peer {
			found = m
		}
	}
	if !found.Authorized || (voter && (!selfVoter || found.Role != "VOTER")) {
		return found, ErrDenied
	}
	return found, nil
}
func (t *Transport) track(c net.Conn) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	select {
	case <-t.done:
		return false
	default:
	}
	t.connections[c] = true
	return true
}
func (t *Transport) untrack(c net.Conn) {
	t.mu.Lock()
	delete(t.connections, c)
	t.mu.Unlock()
	c.Close()
}
func (t *Transport) accept() {
	defer t.wg.Done()
	for {
		c, e := t.listener.Accept()
		if e != nil {
			return
		}
		select {
		case t.slots <- struct{}{}:
		default:
			c.Close()
			continue
		}
		if !t.track(c) {
			c.Close()
			<-t.slots
			return
		}
		t.wg.Add(1)
		go func() { defer t.wg.Done(); defer func() { <-t.slots }(); defer t.untrack(c); t.serve(c) }()
	}
}
func (t *Transport) serve(raw net.Conn) {
	raw.SetDeadline(time.Now().Add(rpcTimeout))
	cfg, e := t.store.TLSConfig(true, "")
	if e != nil {
		return
	}
	c := tls.Server(raw, cfg)
	if c.Handshake() != nil {
		return
	}
	peer, e := t.store.Authenticate(c.ConnectionState())
	if e != nil {
		return
	}
	var req envelope
	if readFrame(c, &req) != nil || req.Version != 1 || req.Venue != t.venue || req.Cluster != t.cluster {
		return
	}
	isRaft := len(req.Kind) > 5 && req.Kind[:5] == "raft/"
	if _, e = t.current(peer.InstallationID(), isRaft); e != nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), rpcTimeout)
	defer cancel()
	var reply response
	if isRaft {
		reply = t.serveRaft(ctx, c, peer, req)
	} else {
		select {
		case t.requests <- struct{}{}:
			defer func() { <-t.requests }()
		case <-ctx.Done():
			return
		case <-t.done:
			return
		}
		reply = t.handler(ctx, peer, req)
	}
	if _, e = t.current(peer.InstallationID(), isRaft); e != nil {
		return
	}
	_ = writeFrame(c, reply)
}
func (t *Transport) exchange(ctx context.Context, id string, voter bool, kind string, arg any, out any, data io.Reader) (response, error) {
	var reply response
	select {
	case t.outgoing <- struct{}{}:
		defer func() { <-t.outgoing }()
	case <-ctx.Done():
		return reply, ctx.Err()
	case <-t.done:
		return reply, ErrDenied
	}
	m, e := t.current(id, voter)
	if e != nil || m.EndpointHint == "" || (!voter && m.Role != "VOTER") {
		return reply, ErrDenied
	}
	cfg, e := t.store.TLSConfig(false, id)
	if e != nil {
		return reply, e
	}
	d := net.Dialer{Timeout: 2 * time.Second}
	raw, e := d.DialContext(ctx, "tcp", m.EndpointHint)
	if e != nil {
		return reply, e
	}
	if !t.track(raw) {
		raw.Close()
		return reply, ErrDenied
	}
	defer t.untrack(raw)
	deadline := time.Now().Add(rpcTimeout)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	raw.SetDeadline(deadline)
	stop := context.AfterFunc(ctx, func() { raw.Close() })
	defer stop()
	c := tls.Client(raw, cfg)
	if e = c.HandshakeContext(ctx); e != nil {
		return reply, e
	}
	if e = writeFrame(c, envelope{1, t.venue, t.cluster, kind, encode(arg)}); e != nil {
		return reply, e
	}
	if data != nil {
		snap, ok := arg.(*raft.InstallSnapshotRequest)
		if !ok || snap.Size < 0 || snap.Size > printcluster.MaxStateBytes {
			return reply, ErrDenied
		}
		if _, e = io.CopyN(c, data, snap.Size); e != nil {
			return reply, e
		}
	}
	if e = readFrame(c, &reply); e != nil {
		return reply, e
	}
	if _, e = t.current(id, voter); e != nil {
		return reply, e
	}
	if reply.Error != "" {
		return reply, errors.New(reply.Error)
	}
	if out != nil {
		e = decode(reply.Body, out)
	}
	return reply, e
}
func (t *Transport) Close() error {
	t.once.Do(func() {
		close(t.done)
		t.mu.Lock()
		if t.listener != nil {
			t.listener.Close()
		}
		for c := range t.connections {
			c.Close()
		}
		t.mu.Unlock()
	})
	t.wg.Wait()
	return nil
}
func (t *Transport) Consumer() <-chan raft.RPC { return t.consumer }
func (t *Transport) LocalAddr() raft.ServerAddress {
	t.mu.Lock()
	defer t.mu.Unlock()
	return raft.ServerAddress(t.address)
}
func (t *Transport) EncodePeer(_ raft.ServerID, a raft.ServerAddress) []byte { return []byte(a) }
func (t *Transport) DecodePeer(b []byte) raft.ServerAddress                  { return raft.ServerAddress(b) }
func (t *Transport) SetHeartbeatHandler(func(raft.RPC))                      {}
func (t *Transport) AppendEntriesPipeline(raft.ServerID, raft.ServerAddress) (raft.AppendPipeline, error) {
	return nil, raft.ErrPipelineReplicationNotSupported
}
func (t *Transport) raftCall(id raft.ServerID, target raft.ServerAddress, kind string, arg, out any, data io.Reader) error {
	m, e := t.current(string(id), true)
	if e != nil || m.EndpointHint != string(target) {
		return ErrDenied
	}
	ctx, cancel := context.WithTimeout(context.Background(), rpcTimeout)
	defer cancel()
	_, e = t.exchange(ctx, string(id), true, kind, arg, out, data)
	return e
}
func (t *Transport) AppendEntries(id raft.ServerID, a raft.ServerAddress, r *raft.AppendEntriesRequest, s *raft.AppendEntriesResponse) error {
	return t.raftCall(id, a, "raft/append", r, s, nil)
}
func (t *Transport) RequestVote(id raft.ServerID, a raft.ServerAddress, r *raft.RequestVoteRequest, s *raft.RequestVoteResponse) error {
	return t.raftCall(id, a, "raft/vote", r, s, nil)
}
func (t *Transport) RequestPreVote(id raft.ServerID, a raft.ServerAddress, r *raft.RequestPreVoteRequest, s *raft.RequestPreVoteResponse) error {
	return t.raftCall(id, a, "raft/prevote", r, s, nil)
}
func (t *Transport) TimeoutNow(id raft.ServerID, a raft.ServerAddress, r *raft.TimeoutNowRequest, s *raft.TimeoutNowResponse) error {
	return t.raftCall(id, a, "raft/timeout", r, s, nil)
}
func (t *Transport) InstallSnapshot(id raft.ServerID, a raft.ServerAddress, r *raft.InstallSnapshotRequest, s *raft.InstallSnapshotResponse, data io.Reader) error {
	return t.raftCall(id, a, "raft/snapshot", r, s, data)
}
func (t *Transport) serveRaft(ctx context.Context, c net.Conn, peer printerprovisioning.AuthenticatedMember, r envelope) response {
	var cmd interface{ GetRPCHeader() raft.RPCHeader }
	var reader io.Reader
	switch r.Kind {
	case "raft/append":
		cmd = &raft.AppendEntriesRequest{}
	case "raft/vote":
		cmd = &raft.RequestVoteRequest{}
	case "raft/prevote":
		cmd = &raft.RequestPreVoteRequest{}
	case "raft/timeout":
		cmd = &raft.TimeoutNowRequest{}
	case "raft/snapshot":
		cmd = &raft.InstallSnapshotRequest{}
	default:
		return response{Error: "denied"}
	}
	if decode(r.Body, cmd) != nil || string(cmd.GetRPCHeader().ID) != peer.InstallationID() {
		return response{Error: "denied"}
	}
	if a, ok := cmd.(*raft.AppendEntriesRequest); ok {
		if len(a.Entries) > 4 {
			return response{Error: "bounded append required"}
		}
		for _, l := range a.Entries {
			if l == nil || len(l.Data) > raft.SuggestedMaxDataSize {
				return response{Error: "oversized log"}
			}
		}
	}
	if s, ok := cmd.(*raft.InstallSnapshotRequest); ok {
		if s.Size < 0 || s.Size > printcluster.MaxStateBytes {
			return response{Error: "oversized snapshot"}
		}
		reader = io.LimitReader(c, s.Size)
	}
	ch := make(chan raft.RPCResponse, 1)
	rpc := raft.RPC{Command: cmd, Reader: reader, RespChan: ch}
	select {
	case t.consumer <- rpc:
	case <-ctx.Done():
		return response{Error: "timeout"}
	case <-t.done:
		return response{Error: "closed"}
	}
	select {
	case result := <-ch:
		if result.Error != nil {
			return response{Error: "raft rejected"}
		}
		return response{Body: encode(result.Response)}
	case <-ctx.Done():
		return response{Error: "timeout"}
	case <-t.done:
		return response{Error: "closed"}
	}
}
