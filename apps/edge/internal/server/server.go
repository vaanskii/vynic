package server

import (
	"context"
	"crypto/tls"
	"errors"
	"log/slog"
	"net"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/status"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/store"
)

type Server struct {
	pb.UnimplementedFoundationServer
	pb.UnimplementedOrdersTablesServer
	store    *store.Store
	identity store.Identity
	BootID   string
	streams  atomic.Int32
}

func New(s *store.Store) (*Server, error) {
	id, err := s.Identity()
	if err != nil {
		return nil, err
	}
	if id.VenueID == "" {
		return nil, errors.New("installation must be bound before serving")
	}
	return &Server{store: s, identity: id, BootID: uuid.NewString()}, nil
}
func (s *Server) scope(v *pb.Scope) error {
	if v == nil || v.Protocol == nil {
		return status.Error(codes.InvalidArgument, "scope and protocol required")
	}
	if v.VenueId != s.identity.VenueID || v.InstallationId != s.identity.InstallationID {
		return status.Error(codes.PermissionDenied, "Venue/installation mismatch")
	}
	if v.Protocol.Major != 1 || v.Protocol.Minor > 1 {
		return status.Error(codes.FailedPrecondition, "unsupported protocol; server=1.1")
	}
	for _, c := range v.Protocol.RequiredCapabilities {
		if c != "foundation.status" && c != "orders_tables.shadow" {
			return status.Error(codes.FailedPrecondition, "unsupported required capability")
		}
	}
	return nil
}
func validID(v string) bool {
	id, e := uuid.Parse(v)
	return e == nil && id != uuid.Nil && id.String() == v
}
func rpcError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, store.ErrDenied) {
		return status.Error(codes.Unauthenticated, "invalid or revoked credential")
	}
	if errors.Is(err, store.ErrConflict) {
		return status.Error(codes.AlreadyExists, "identity conflict")
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return status.FromContextError(err).Err()
	}
	slog.Error("foundation storage operation failed", "error", err)
	return status.Error(codes.Internal, "local persistence failed")
}
func (s *Server) auth(ctx context.Context, a *pb.AuthenticatedRequest) error {
	if a == nil {
		return status.Error(codes.Unauthenticated, "terminal authentication required")
	}
	if err := s.scope(a.Scope); err != nil {
		return err
	}
	if !validID(a.TerminalId) || !store.ValidSecret(a.TerminalSecret) {
		return status.Error(codes.Unauthenticated, "invalid terminal credential")
	}
	return rpcError(s.store.Authenticate(ctx, a.TerminalId, a.TerminalSecret))
}
func (s *Server) Pair(ctx context.Context, r *pb.PairRequest) (*pb.PairResponse, error) {
	if err := s.scope(r.Scope); err != nil {
		return nil, err
	}
	if !validID(r.RequestId) || !validID(r.TerminalId) || !store.ValidSecret(r.Ticket) || !store.ValidSecret(r.TerminalSecret) || len(r.DisplayName) < 1 || len(r.DisplayName) > 100 {
		return nil, status.Error(codes.InvalidArgument, "invalid pairing fields")
	}
	if err := s.store.Pair(ctx, r.Ticket, r.RequestId, r.TerminalId, r.TerminalSecret, r.DisplayName); err != nil {
		return nil, rpcError(err)
	}
	return &pb.PairResponse{TerminalId: r.TerminalId, InstallationId: s.identity.InstallationID, VenueId: s.identity.VenueID}, nil
}
func (s *Server) response(terminal, session string) *pb.StatusResponse {
	return &pb.StatusResponse{InstallationId: s.identity.InstallationID, VenueId: s.identity.VenueID, Protocol: &pb.Protocol{Major: 1, Minor: 1}, Mode: "FOUNDATION_ONLY", BusinessMutationsEnabled: false, SchemaVersion: store.SchemaVersion, BootId: s.BootID, TerminalId: terminal, SessionId: session, ConnectedStreams: uint32(s.streams.Load()), Capabilities: []string{"foundation.status", "orders_tables.shadow"}}
}
func (s *Server) Handshake(ctx context.Context, r *pb.HandshakeRequest) (*pb.StatusResponse, error) {
	if err := s.auth(ctx, r.Auth); err != nil {
		return nil, err
	}
	if !validID(r.SessionId) || len(r.ClientVersion) < 1 || len(r.ClientVersion) > 100 {
		return nil, status.Error(codes.InvalidArgument, "session UUID/client version required")
	}
	if err := s.store.Session(ctx, r.Auth.TerminalId, r.SessionId, r.ClientVersion, s.BootID); err != nil {
		return nil, rpcError(err)
	}
	return s.response(r.Auth.TerminalId, r.SessionId), nil
}
func (s *Server) Status(ctx context.Context, r *pb.AuthenticatedRequest) (*pb.StatusResponse, error) {
	if err := s.auth(ctx, r); err != nil {
		return nil, err
	}
	return s.response(r.TerminalId, ""), nil
}
func (s *Server) WatchStatus(r *pb.AuthenticatedRequest, stream grpc.ServerStreamingServer[pb.StatusResponse]) error {
	if err := s.auth(stream.Context(), r); err != nil {
		return err
	}
	n := s.streams.Add(1)
	defer s.streams.Add(-1)
	if n > 64 {
		return status.Error(codes.ResourceExhausted, "connection limit reached")
	}
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		if err := stream.Send(s.response(r.TerminalId, "")); err != nil {
			return err
		}
		select {
		case <-stream.Context().Done():
			return status.FromContextError(stream.Context().Err()).Err()
		case <-ticker.C:
		}
	}
}

// Serve uses TLS on loopback as well as LAN. Caller owns Store lifetime.
func (s *Server) Serve(ctx context.Context, listener net.Listener) error {
	cert, err := tls.X509KeyPair(s.identity.Certificate, s.identity.TLSKey)
	if err != nil {
		return err
	}
	g := grpc.NewServer(grpc.Creds(credentials.NewTLS(&tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13})), grpc.MaxRecvMsgSize(1<<20), grpc.MaxConcurrentStreams(64))
	pb.RegisterFoundationServer(g, s)
	pb.RegisterOrdersTablesServer(g, s)
	h := health.NewServer()
	healthpb.RegisterHealthServer(g, h)
	h.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	h.SetServingStatus(pb.Foundation_ServiceDesc.ServiceName, healthpb.HealthCheckResponse_SERVING)
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			h.Shutdown()
			timer := time.AfterFunc(3*time.Second, g.Stop)
			g.GracefulStop()
			timer.Stop()
		case <-done:
		}
	}()
	err = g.Serve(listener)
	close(done)
	if errors.Is(err, grpc.ErrServerStopped) {
		return nil
	}
	return err
}
