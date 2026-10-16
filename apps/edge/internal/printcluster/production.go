package printcluster

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"net"
	"strconv"

	"github.com/hashicorp/raft"
	"vynic.local/edge/internal/printerprovisioning"
	"vynic.local/edge/internal/printstation"
)

// ProductionPin derives storage identity and historical caller bindings from
// verified production inventory. It never authorizes a network caller itself.
func ProductionPin(b printerprovisioning.ProductionBody, issuer ed25519.PublicKey) ClusterConfig {
	p := ClusterConfig{Version: 2, Scope: VenueShared, ClusterID: b.ClusterID, VenueID: b.VenueID, Issuer: base64.RawStdEncoding.EncodeToString(issuer)}
	for _, m := range b.Members {
		q := Peer{ID: m.InstallationID, InstallationID: m.InstallationID, TerminalID: m.DeviceID, DeviceID: m.DeviceID, Role: m.Role, Admin: m.Role == Voter}
		if m.Role == Voter {
			q.FullData = true
			q.Address = m.EndpointHint
			p.Voters++
		}
		p.Peers = append(p.Peers, q)
	}
	return canonicalPin(p)
}
func (p ClusterConfig) validateProduction() error {
	key, e := base64.RawStdEncoding.DecodeString(p.Issuer)
	if e != nil || len(key) != 32 || !uuid(p.ClusterID) || !uuid(p.VenueID) || (p.Scope != VenueShared && p.Scope != Local) || (p.Voters != 1 && p.Voters != 3) || len(p.Peers) > 256 || len(p.Peers) < p.Voters {
		return ErrMembership
	}
	ids, addresses := map[string]bool{}, map[string]bool{}
	voters := 0
	for _, q := range p.Peers {
		if !uuid(q.ID) || q.ID != q.InstallationID || !uuid(q.DeviceID) || q.TerminalID != q.DeviceID || ids[q.ID] {
			return ErrMembership
		}
		ids[q.ID] = true
		switch q.Role {
		case Voter:
			h, port, e := net.SplitHostPort(q.Address)
			portNumber, pe := strconv.Atoi(port)
			if e != nil || pe != nil || portNumber < 1 || portNumber > 65535 || net.ParseIP(h) == nil || addresses[q.Address] || !q.FullData {
				return ErrMembership
			}
			addresses[q.Address] = true
			voters++
		case Client:
			if q.FullData || q.Address != "" {
				return ErrMembership
			}
		default:
			return ErrMembership
		}
	}
	if voters != p.Voters {
		return ErrMembership
	}
	return nil
}
func (n *Node) currentPin() ClusterConfig {
	n.fsm.mu.RLock()
	defer n.fsm.mu.RUnlock()
	return n.fsm.state.Pin
}

// OpenAuthenticated uses the existing Bolt log, FULL/WAL normalized projection,
// payload table and snapshots. The caller supplies the production TLS transport.
// It never bootstraps; first creation requires a separate explicit action.
func OpenAuthenticated(dir string, pin ClusterConfig, id string, transport interface {
	raft.Transport
	Close() error
}) (*Node, error) {
	if pin.Version != 2 || transport == nil || pin.validateProduction() != nil {
		return nil, ErrScope
	}
	return openNode(dir, pin, id, transport)
}
func OpenLocalAuthenticated(dir string, pin ClusterConfig) (*LocalStationSpool, error) {
	if pin.Version != 2 || pin.Scope != Local || pin.validateProduction() != nil || len(pin.Peers) != 1 {
		return nil, ErrScope
	}
	return openLocalStation(dir, pin)
}
func (s *projection) productionConfig(c command) result {
	if s.Pin.Version != 2 {
		return result{Err: ErrScope}
	}
	key, e := base64.RawStdEncoding.DecodeString(s.Pin.Issuer)
	if e != nil {
		return result{Err: ErrScope}
	}
	b, e := printerprovisioning.VerifyHistoricalProduction(c.Raw, key)
	if e != nil {
		return result{Err: ErrConfig}
	}
	next := ProductionPin(b, key)
	if next.validateProduction() != nil || pinDigest(next) != pinDigest(s.Pin) {
		return result{Err: ErrScope}
	}
	if len(s.ProductionGrant) > 0 {
		old, e := printerprovisioning.VerifyHistoricalProduction(s.ProductionGrant, key)
		if e != nil {
			return result{Err: ErrStorage}
		}
		if b.Generation < old.Generation {
			return result{Err: ErrConfig}
		}
		if printerprovisioning.CheckProductionEvolution(old, b) != nil {
			return result{Err: ErrConfig}
		}
		// This stage supports stable voters and controlled 1 -> 3 expansion only.
		// Shrink/replacement/address movement needs its own reviewed transition.
		for _, p := range s.Pin.Peers {
			q, ok := next.peer(p.ID)
			if !ok || p.DeviceID != q.DeviceID {
				return result{Err: ErrScope}
			}
			if p.Role == Voter && (q.Role != Voter || q.Address != p.Address) {
				return result{Err: ErrMembership}
			}
		}
	}
	p, ok := next.peer(c.Caller.MemberID)
	if !ok || p.Role != Voter || !next.authorize(c.Caller, true) {
		return result{Err: ErrScope}
	}
	var full printstation.Catalog
	if json.Unmarshal(b.CatalogRaw, &full) != nil {
		return result{Err: ErrConfig}
	}
	catalog, e := full.ForQueue(printstation.Shared, "")
	if e != nil {
		return result{Err: ErrConfig}
	}
	if s.Stations == nil {
		s.Stations = printstation.New(b.VenueID)
	}
	if e = s.Stations.Install(printstation.Authority{VenueID: b.VenueID, DeviceID: p.DeviceID, Admin: true}, catalog); e != nil {
		return result{Err: stationError(e)}
	}
	s.Pin = next
	s.ProductionGrant = bytes.Clone(c.Raw)
	return result{}
}

// ConfigureProduction journals the signed inventory/catalog before changing
// Raft suffrage. A retry after any interruption resumes from committed state.
func (n *Node) ConfigureProduction(ctx context.Context, raw []byte) error {
	n.memberMu.Lock()
	defer n.memberMu.Unlock()
	a, e := n.caller(n.id)
	if e != nil {
		return e
	}
	n.fsm.mu.RLock()
	same := bytes.Equal(n.fsm.state.ProductionGrant, raw)
	if !same && len(n.fsm.state.ProductionGrant) > 0 {
		key, _ := base64.RawStdEncoding.DecodeString(n.pin.Issuer)
		old, oe := printerprovisioning.VerifyHistoricalProduction(n.fsm.state.ProductionGrant, key)
		next, ne := printerprovisioning.VerifyHistoricalProduction(raw, key)
		// Independent refreshes have distinct issuance generations. An older but
		// current local grant for exactly the same configuration needs no log entry.
		same = oe == nil && ne == nil && old.Revision == next.Revision && bytes.Equal(old.CatalogRaw, next.CatalogRaw) && bytes.Equal(encodeInventory(old), encodeInventory(next))
	}
	complete := true
	for _, p := range n.fsm.state.Pin.Peers {
		if p.Role == Voter && n.fsm.state.Members[p.ID].Role != Voter {
			complete = false
		}
	}
	n.fsm.mu.RUnlock()
	if same && complete {
		return nil
	}
	if !same {
		if _, e = n.apply(ctx, command{Op: "productionConfig", Caller: a, Raw: raw}); e != nil {
			return e
		}
	}
	pin := n.currentPin()
	for _, p := range pin.Peers {
		if p.Role != Voter {
			continue
		}
		conf := n.raft.GetConfiguration()
		if e = waitFuture(ctx, conf); e != nil {
			return e
		}
		exists := false
		for _, q := range conf.Configuration().Servers {
			if string(q.ID) == p.ID {
				if string(q.Address) != p.Address {
					return ErrMembership
				}
				exists = q.Suffrage == raft.Voter
			}
		}
		if exists {
			continue
		}
		// AddVoter uses Hashicorp's serialized configuration log and quorum rules.
		// It can temporarily require both of two voters; never promises HA mid-change.
		if e = waitFuture(ctx, n.raft.AddVoter(raft.ServerID(p.ID), raft.ServerAddress(p.Address), conf.Index(), timeout(ctx))); e != nil {
			return ErrCommitUnknown
		}
	}
	return n.leader(ctx)
}
func (n *Node) LeaderID() string { _, id := n.raft.LeaderWithID(); return string(id) }
func (n *Node) ProductionStatus() (uint64, map[string]string) {
	n.fsm.mu.RLock()
	defer n.fsm.mu.RUnlock()
	m := map[string]string{}
	for id, p := range n.fsm.state.Members {
		m[id] = p.Role
	}
	return n.fsm.state.MembershipGeneration, m
}
func (n *Node) StationAdmission(ctx context.Context, station, job string) (Receipt, error) {
	if e := n.leader(ctx); e != nil {
		return Receipt{}, e
	}
	n.fsm.mu.RLock()
	defer n.fsm.mu.RUnlock()
	if n.fsm.state.Stations == nil {
		return Receipt{}, ErrInvalid
	}
	r, ok := n.fsm.state.Stations.Jobs[job]
	if !ok || r.Job.StationID != station {
		return Receipt{}, ErrInvalid
	}
	return stationReceipt(r), nil
}

func encodeInventory(b printerprovisioning.ProductionBody) []byte {
	v, _ := json.Marshal(struct {
		Topology string
		Members  []printerprovisioning.ProductionMember
	}{b.Topology, b.Members})
	return v
}

// Signed journal state is verified on reopen/snapshot restore as well as apply.
func validateProductionJournal(s *projection) error {
	if s.Pin.Version != 2 || len(s.ProductionGrant) == 0 {
		return nil
	}
	key, e := base64.RawStdEncoding.DecodeString(s.Pin.Issuer)
	if e != nil {
		return ErrConfig
	}
	b, e := printerprovisioning.VerifyHistoricalProduction(s.ProductionGrant, key)
	if e != nil {
		return ErrConfig
	}
	pin := ProductionPin(b, key)
	if !bytes.Equal(printstation.Encode(canonicalPin(pin)), printstation.Encode(canonicalPin(s.Pin))) {
		return ErrMembership
	}
	var full printstation.Catalog
	if json.Unmarshal(b.CatalogRaw, &full) != nil {
		return ErrConfig
	}
	c, e := full.ForQueue(printstation.Shared, "")
	if e != nil || s.Stations == nil || s.Stations.Current != c.Digest() {
		return ErrConfig
	}
	return nil
}
