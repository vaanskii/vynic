package printeligibility

import (
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func id(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }
func claim(owner int, term, index uint64) Assignment {
	return Assignment{ClusterID: id(1), PhysicalPrinterID: id(2), JobID: id(3), AttemptID: id(4), ExecutorID: id(owner),
		PayloadSHA256: strings.Repeat("a", 64), JobSHA256: strings.Repeat("b", 64), ConfigSHA256: strings.Repeat("c", 64),
		Term: term, CommitIndex: index, MembershipGeneration: 1, BindingGeneration: 1}
}
func gate(t *testing.T, boot int, clock *atomic.Int64) *ProofGate {
	t.Helper()
	g, err := NewProofGate(id(boot), func() time.Duration { return time.Duration(clock.Load()) })
	if err != nil {
		t.Fatal(err)
	}
	return g
}
func refresh(t *testing.T, g *ProofGate, boot int, a Assignment, lifetime, hold time.Duration) {
	t.Helper()
	if err := g.Refresh(Evidence{Assignment: a, BootID: id(boot), MajorityConfirmed: true}, lifetime, hold); err != nil {
		t.Fatal(err)
	}
}

func TestLeaseAndBootEvidenceCannotAuthorizeSharedPhysicalDispatch(t *testing.T) {
	var clock atomic.Int64
	g := gate(t, 10, &clock)
	a := claim(5, 1, 7)
	refresh(t, g, 10, a, time.Second, 100*time.Millisecond)
	if !errors.Is(g.CheckLogical(a), ErrLease) {
		t.Fatal("previous-lease interval ignored")
	}
	clock.Store(int64(100 * time.Millisecond))
	if err := g.CheckLogical(a); err != nil {
		t.Fatal(err)
	}
	if !errors.Is(g.CheckPhysical(a), ErrPhysicalFencePending) {
		t.Fatal("lease incorrectly became physical fence")
	}
	changed := a
	changed.ConfigSHA256 = strings.Repeat("d", 64)
	if !errors.Is(g.CheckLogical(changed), ErrLease) {
		t.Fatal("retargeted config accepted")
	}
	g.LoseQuorum()
	if !errors.Is(g.CheckLogical(a), ErrLease) {
		t.Fatal("minority retained logical permit")
	}
	if err := g.Refresh(Evidence{Assignment: a, BootID: id(11), MajorityConfirmed: true}, time.Second, 0); !errors.Is(err, ErrEvidence) {
		t.Fatal("lease restored into another boot")
	}
	if err := g.Refresh(Evidence{Assignment: a, BootID: id(10)}, time.Second, 0); !errors.Is(err, ErrEvidence) {
		t.Fatal("minority renewed lease")
	}
}

func TestGenerationHighWaterSurvivesQuorumLossAndClockRegression(t *testing.T) {
	var clock atomic.Int64
	g := gate(t, 10, &clock)
	a := claim(5, 3, 9)
	refresh(t, g, 10, a, time.Second, 0)
	g.LoseQuorum()
	stale := a
	stale.Term = 2
	stale.CommitIndex = 8
	if err := g.Refresh(Evidence{Assignment: stale, BootID: id(10), MajorityConfirmed: true}, time.Second, 0); !errors.Is(err, ErrEvidence) {
		t.Fatal("stale term revived")
	}
	refresh(t, g, 10, a, time.Second, 0)
	clock.Store(int64(200 * time.Millisecond))
	if err := g.CheckLogical(a); err != nil {
		t.Fatal(err)
	}
	clock.Store(int64(100 * time.Millisecond))
	if !errors.Is(g.CheckLogical(a), ErrEvidence) {
		t.Fatal("backwards clock accepted")
	}
	clock.Store(int64(300 * time.Millisecond))
	if err := g.Refresh(Evidence{Assignment: a, BootID: id(10), MajorityConfirmed: true}, time.Second, 0); !errors.Is(err, ErrEvidence) {
		t.Fatal("clock fault automatically cleared")
	}
}

func TestBindingAndRetainedJobIdentityCannotBeRewrittenByHigherIndex(t *testing.T) {
	var clock atomic.Int64
	g := gate(t, 10, &clock)
	a := claim(5, 3, 9)
	a.BindingGeneration = 4
	refresh(t, g, 10, a, time.Second, 0)
	g.LoseQuorum()
	changed := a
	changed.CommitIndex = 10
	changed.JobSHA256 = strings.Repeat("d", 64)
	if err := g.Refresh(Evidence{Assignment: changed, BootID: id(10), MajorityConfirmed: true}, time.Second, 0); !errors.Is(err, ErrEvidence) {
		t.Fatal("retained job rewritten")
	}
	regressed := a
	regressed.JobID = id(30)
	regressed.CommitIndex = 11
	regressed.BindingGeneration = 3
	if err := g.Refresh(Evidence{Assignment: regressed, BootID: id(10), MajorityConfirmed: true}, time.Second, 0); !errors.Is(err, ErrEvidence) {
		t.Fatal("binding generation regressed")
	}
}

// This expected-unsafe case deliberately bypasses CheckPhysical to demonstrate
// why adding only a quorum lease/check immediately before Write is inadequate.
// Loopback bytes are synthetic; no printer, service or Venue is contacted.
func TestExpectedUnsafeLeaseOnlyRAWPausedSenderCounterexample(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	received := make(chan byte, 2)
	readErrors := make(chan error, 2)
	go func() {
		for i := 0; i < 2; i++ {
			c, e := listener.Accept()
			if e != nil {
				readErrors <- e
				return
			}
			go func() {
				defer c.Close()
				_ = c.SetReadDeadline(time.Now().Add(3 * time.Second))
				var b [1]byte
				_, e := io.ReadFull(c, b[:])
				if e != nil {
					readErrors <- e
					return
				}
				received <- b[0]
			}()
		}
	}()
	oldSocket, err := net.DialTimeout("tcp", listener.Addr().String(), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = oldSocket.Close() })
	var oldClock, newClock atomic.Int64
	old := gate(t, 10, &oldClock)
	newOwner := gate(t, 11, &newClock)
	a := claim(5, 1, 7)
	b := claim(6, 2, 8)
	refresh(t, old, 10, a, 100*time.Millisecond, 0)
	if err := old.CheckLogical(a); err != nil {
		t.Fatal(err)
	}
	// The old process is paused AFTER its last quorum/lease check.
	old.LoseQuorum()
	oldClock.Store(int64(200 * time.Millisecond))
	newClock.Store(int64(200 * time.Millisecond))
	refresh(t, newOwner, 11, b, 200*time.Millisecond, 50*time.Millisecond)
	newClock.Store(int64(260 * time.Millisecond))
	if err := newOwner.CheckLogical(b); err != nil {
		t.Fatal(err)
	}
	if !errors.Is(newOwner.CheckPhysical(b), ErrPhysicalFencePending) {
		t.Fatal("missing RAW fence accepted")
	}
	newSocket, err := net.DialTimeout("tcp", listener.Addr().String(), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer newSocket.Close()
	if _, err = newSocket.Write([]byte{'B'}); err != nil {
		t.Fatal(err)
	}
	waitByte := func(want byte) {
		t.Helper()
		select {
		case got := <-received:
			if got != want {
				t.Fatalf("got %c want %c", got, want)
			}
		case e := <-readErrors:
			t.Fatal(e)
		case <-time.After(3 * time.Second):
			t.Fatal("loopback receive timed out")
		}
	}
	waitByte('B')
	// It resumes without another check, despite all lease/safety times elapsing.
	if _, err = oldSocket.Write([]byte{'A'}); err != nil {
		t.Fatal(err)
	}
	waitByte('A')
	if !errors.Is(old.CheckLogical(a), ErrLease) {
		t.Fatal("old logical grant unexpectedly current")
	}
}

func TestBufferedTCPBytesSurviveSenderSocketClose(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	client, err := net.DialTimeout("tcp", listener.Addr().String(), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	server, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	_ = server.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err = client.Write([]byte("SYNTHETIC")); err != nil {
		t.Fatal(err)
	}
	if err = client.Close(); err != nil {
		t.Fatal(err)
	}
	var bytes [9]byte
	if _, err = io.ReadFull(server, bytes[:]); err != nil {
		t.Fatal(err)
	}
	if string(bytes[:]) != "SYNTHETIC" {
		t.Fatal("buffered data mismatch")
	}
}
