package server_test

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"net"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/server"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

func connect(t *testing.T, s *store.Store, id store.Identity) (pb.FoundationClient, func()) {
	t.Helper()
	srv, e := server.New(s)
	if e != nil {
		t.Fatal(e)
	}
	listener, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- srv.Serve(ctx, listener) }()
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(id.Certificate)
	conn, e := grpc.NewClient(listener.Addr().String(), grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{RootCAs: roots, ServerName: "vynic-edge.local", MinVersion: tls.VersionTLS13})))
	if e != nil {
		t.Fatal(e)
	}
	return pb.NewFoundationClient(conn), func() {
		conn.Close()
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Error(err)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("shutdown timed out")
		}
	}
}
func TestPairingAuthenticationAndRestart(t *testing.T) {
	dir := t.TempDir()
	s, id := testutil.Bound(t, dir)
	ticketA, e := s.IssueTicket()
	if e != nil {
		t.Fatal(e)
	}
	ticketB, e := s.IssueTicket()
	if e != nil {
		t.Fatal(e)
	}
	client, stop := connect(t, s, id)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	scope := &pb.Scope{VenueId: id.VenueID, InstallationId: id.InstallationID, Protocol: &pb.Protocol{Major: 1}}
	pair := func(ticket string) *pb.PairRequest {
		return &pb.PairRequest{Scope: scope, Ticket: ticket, RequestId: uuid.NewString(), TerminalId: uuid.NewString(), TerminalSecret: store.Secret(), DisplayName: "test terminal"}
	}
	a, b := pair(ticketA), pair(ticketB)
	for _, r := range []*pb.PairRequest{a, b, a} {
		if _, e = client.Pair(ctx, r); e != nil {
			t.Fatal(e)
		}
	}
	if a.TerminalId == b.TerminalId {
		t.Fatal("shared terminal identity")
	}
	t.Run("consumed ticket rejects changed identity and secret", func(t *testing.T) {
		for _, field := range []string{"id", "secret", "request", "name"} {
			r := proto.Clone(a).(*pb.PairRequest)
			switch field {
			case "id":
				r.TerminalId = uuid.NewString()
			case "secret":
				r.TerminalSecret = store.Secret()
			case "request":
				r.RequestId = uuid.NewString()
			case "name":
				r.DisplayName = "changed"
			}
			_, e := client.Pair(ctx, r)
			if status.Code(e) != codes.AlreadyExists {
				t.Fatal(e)
			}
		}
	})
	auth := func(r *pb.PairRequest) *pb.AuthenticatedRequest {
		return &pb.AuthenticatedRequest{Scope: r.Scope, TerminalId: r.TerminalId, TerminalSecret: r.TerminalSecret}
	}
	aa, bb := auth(a), auth(b)
	t.Run("bad credential", func(t *testing.T) {
		r := proto.Clone(aa).(*pb.AuthenticatedRequest)
		r.TerminalSecret = store.Secret()
		_, e := client.Status(ctx, r)
		if status.Code(e) != codes.Unauthenticated {
			t.Fatal(e)
		}
	})
	t.Run("scope and protocol refusal", func(t *testing.T) {
		for _, field := range []string{"venue", "edge", "major", "minor", "capability"} {
			r := proto.Clone(aa).(*pb.AuthenticatedRequest)
			want := codes.FailedPrecondition
			switch field {
			case "venue":
				r.Scope.VenueId = uuid.NewString()
				want = codes.PermissionDenied
			case "edge":
				r.Scope.InstallationId = uuid.NewString()
				want = codes.PermissionDenied
			case "major":
				r.Scope.Protocol.Major = 2
			case "minor":
				r.Scope.Protocol.Minor = 1
			case "capability":
				r.Scope.Protocol.RequiredCapabilities = []string{"orders.write"}
			}
			_, e := client.Status(ctx, r)
			if status.Code(e) != want {
				t.Fatalf("%s: %v", field, e)
			}
		}
	})
	session := uuid.NewString()
	hs := &pb.HandshakeRequest{Auth: aa, SessionId: session, ClientVersion: "test/1"}
	before, e := client.Handshake(ctx, hs)
	if e != nil {
		t.Fatal(e)
	}
	if before.Mode != "FOUNDATION_ONLY" || before.BusinessMutationsEnabled {
		t.Fatal(before)
	}
	t.Run("session replay and collision", func(t *testing.T) {
		if _, e := client.Handshake(ctx, hs); e != nil {
			t.Fatal(e)
		}
		_, e := client.Handshake(ctx, &pb.HandshakeRequest{Auth: bb, SessionId: session, ClientVersion: "test/1"})
		if status.Code(e) != codes.AlreadyExists {
			t.Fatal(e)
		}
	})
	wctx, wcancel := context.WithCancel(ctx)
	streamA, e := client.WatchStatus(wctx, aa)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = streamA.Recv(); e != nil {
		t.Fatal(e)
	}
	streamB, e := client.WatchStatus(wctx, bb)
	if e != nil {
		t.Fatal(e)
	}
	msg, e := streamB.Recv()
	if e != nil || msg.ConnectedStreams != 2 {
		t.Fatalf("two connections: %v %v", msg, e)
	}
	wcancel()
	stop()
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e = store.Open(dir, false)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	client, stop = connect(t, s, id)
	defer stop()
	after, e := client.Handshake(ctx, hs)
	if e != nil {
		t.Fatal(e)
	}
	if after.InstallationId != before.InstallationId || after.BootId == before.BootId || after.SessionId != before.SessionId || after.ConnectedStreams != 0 {
		t.Fatal(after)
	}
	if _, e = client.Pair(ctx, a); e != nil {
		t.Fatal("pair retry after restart", e)
	}
	var count int
	if e = s.DB.QueryRow("SELECT count(*) FROM session").Scan(&count); e != nil || count != 1 {
		t.Fatalf("session durability %d %v", count, e)
	}
	if e = s.Revoke(a.TerminalId); e != nil {
		t.Fatal(e)
	}
	if _, e = client.Status(ctx, aa); status.Code(e) != codes.Unauthenticated {
		t.Fatal(e)
	}
	if _, e = client.Pair(ctx, a); status.Code(e) != codes.Unauthenticated {
		t.Fatal(e)
	}
}
func TestPairingExpiryAndInvalidTicket(t *testing.T) {
	s, id := testutil.Bound(t, t.TempDir())
	defer s.Close()
	ticket, e := s.IssueTicket()
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.DB.Exec("UPDATE pairing_ticket SET expires_at=0"); e != nil {
		t.Fatal(e)
	}
	client, stop := connect(t, s, id)
	defer stop()
	for _, tok := range []string{ticket, store.Secret()} {
		_, e = client.Pair(context.Background(), &pb.PairRequest{Scope: &pb.Scope{VenueId: id.VenueID, InstallationId: id.InstallationID, Protocol: &pb.Protocol{Major: 1}}, Ticket: tok, RequestId: uuid.NewString(), TerminalId: uuid.NewString(), TerminalSecret: store.Secret(), DisplayName: "test"})
		if status.Code(e) != codes.Unauthenticated {
			t.Fatal(e)
		}
	}
}

func TestConcurrentTicketConsumption(t *testing.T) {
	s, id := testutil.Bound(t, t.TempDir())
	defer s.Close()
	ticket, err := s.IssueTicket()
	if err != nil {
		t.Fatal(err)
	}
	client, stop := connect(t, s, id)
	defer stop()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		go func() {
			_, err := client.Pair(ctx, &pb.PairRequest{Scope: &pb.Scope{VenueId: id.VenueID, InstallationId: id.InstallationID, Protocol: &pb.Protocol{Major: 1}}, Ticket: ticket, RequestId: uuid.NewString(), TerminalId: uuid.NewString(), TerminalSecret: store.Secret(), DisplayName: "racing terminal"})
			results <- err
		}()
	}
	successes, conflicts := 0, 0
	for i := 0; i < 2; i++ {
		switch status.Code(<-results) {
		case codes.OK:
			successes++
		case codes.AlreadyExists:
			conflicts++
		default:
			t.Fatal("unexpected concurrent pairing result")
		}
	}
	if successes != 1 || conflicts != 1 {
		t.Fatalf("%d successes %d conflicts", successes, conflicts)
	}
	var n int
	if err = s.DB.QueryRow("SELECT count(*) FROM terminal").Scan(&n); err != nil || n != 1 {
		t.Fatalf("%d terminals %v", n, err)
	}
}

func TestShutdownDrainsThenBoundsActiveStreams(t *testing.T) {
	s, id := testutil.Bound(t, t.TempDir())
	defer s.Close()
	ticket, err := s.IssueTicket()
	if err != nil {
		t.Fatal(err)
	}
	terminal, secret := uuid.NewString(), store.Secret()
	if err = s.Pair(context.Background(), ticket, uuid.NewString(), terminal, secret, "active"); err != nil {
		t.Fatal(err)
	}
	srv, err := server.New(s)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- srv.Serve(ctx, listener) }()
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(id.Certificate)
	conn, err := grpc.NewClient(listener.Addr().String(), grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{RootCAs: roots, ServerName: "vynic-edge.local", MinVersion: tls.VersionTLS13})))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	stream, err := pb.NewFoundationClient(conn).WatchStatus(context.Background(), &pb.AuthenticatedRequest{Scope: &pb.Scope{VenueId: id.VenueID, InstallationId: id.InstallationID, Protocol: &pb.Protocol{Major: 1}}, TerminalId: terminal, TerminalSecret: secret})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = stream.Recv(); err != nil {
		t.Fatal(err)
	}
	cancel()
	select {
	case err = <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("active stream prevented clean shutdown")
	}
}
