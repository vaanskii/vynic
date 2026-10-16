package printcluster

import (
	"io"
	"net"
	"sync"
	"time"

	"github.com/hashicorp/raft"
)

// This transport is exclusively a synthetic loopback fixture. The declared
// peer hello identifies connections for adversarial partitions, not credential
// authentication. Production uses the separate printpeer TLS transport.
type proofStream struct {
	net.Listener
	mu          sync.Mutex
	id          string
	addresses   map[string]string
	blocked     map[string]bool
	connections map[*proofConn]string
	closed      bool
}
type proofConn struct {
	net.Conn
	owner *proofStream
}

func (c *proofConn) Close() error {
	c.owner.mu.Lock()
	delete(c.owner.connections, c)
	c.owner.mu.Unlock()
	return c.Conn.Close()
}
func newProofStream(pin ClusterConfig, id string) (*proofStream, error) {
	p, ok := pin.peer(id)
	if !ok || p.Role == Client {
		return nil, ErrMembership
	}
	l, e := net.Listen("tcp", p.Address)
	if e != nil {
		return nil, e
	}
	s := &proofStream{Listener: l, id: id, addresses: map[string]string{}, blocked: map[string]bool{}, connections: map[*proofConn]string{}}
	for _, p := range pin.Peers {
		if p.Role != Client {
			s.addresses[p.Address] = p.ID
		}
	}
	return s, nil
}
func (s *proofStream) track(conn net.Conn, peer string) (net.Conn, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.blocked[peer] {
		_ = conn.Close()
		return nil, ErrNoQuorum
	}
	c := &proofConn{Conn: conn, owner: s}
	s.connections[c] = peer
	return c, nil
}
func (s *proofStream) Dial(address raft.ServerAddress, timeout time.Duration) (net.Conn, error) {
	s.mu.Lock()
	id, ok := s.addresses[string(address)]
	blocked := s.closed || s.blocked[id]
	s.mu.Unlock()
	if !ok || blocked {
		return nil, ErrNoQuorum
	}
	c, e := net.DialTimeout("tcp", string(address), timeout)
	if e != nil {
		return nil, e
	}
	_ = c.SetWriteDeadline(time.Now().Add(timeout))
	if _, e = io.WriteString(c, "vynic-proof-storage2/"+s.id); e != nil {
		_ = c.Close()
		return nil, e
	}
	_ = c.SetWriteDeadline(time.Time{})
	return s.track(c, id)
}
func (s *proofStream) Accept() (net.Conn, error) {
	for {
		c, e := s.Listener.Accept()
		if e != nil {
			return nil, e
		}
		_ = c.SetReadDeadline(time.Now().Add(time.Second))
		b := make([]byte, len("vynic-proof-storage2/")+36)
		_, e = io.ReadFull(c, b)
		_ = c.SetReadDeadline(time.Time{})
		if e != nil || string(b[:len("vynic-proof-storage2/")]) != "vynic-proof-storage2/" {
			_ = c.Close()
			continue
		}
		id := string(b[len("vynic-proof-storage2/"):])
		known := false
		for _, p := range s.addresses {
			if p == id {
				known = true
				break
			}
		}
		if !known {
			_ = c.Close()
			continue
		}
		tracked, e := s.track(c, id)
		if e != nil {
			continue
		}
		return tracked, nil
	}
}
func (s *proofStream) block(id string, blocked bool) {
	s.mu.Lock()
	s.blocked[id] = blocked
	var conns []*proofConn
	if blocked {
		for c, p := range s.connections {
			if p == id {
				conns = append(conns, c)
			}
		}
	}
	s.mu.Unlock()
	for _, c := range conns {
		_ = c.Close()
	}
}
func (s *proofStream) Close() error {
	s.mu.Lock()
	s.closed = true
	conns := make([]*proofConn, 0, len(s.connections))
	for c := range s.connections {
		conns = append(conns, c)
	}
	s.mu.Unlock()
	e := s.Listener.Close()
	for _, c := range conns {
		_ = c.Close()
	}
	return e
}
