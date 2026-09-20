package server

import (
	"context"
	"errors"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/store"
)

func coordinationError(err error) error {
	switch {
	case errors.Is(err, store.ErrEpoch):
		return status.Error(codes.FailedPrecondition, "shadow authority epoch mismatch; bootstrap required")
	case errors.Is(err, store.ErrIntent):
		return status.Error(codes.InvalidArgument, "invalid Order/Table projection or cursor")
	case errors.Is(err, store.ErrRequestReuse):
		return status.Error(codes.AlreadyExists, "request ID reused with different intent or terminal")
	case errors.Is(err, store.ErrProjectionLimit):
		return status.Error(codes.ResourceExhausted, "bounded shadow projection limit")
	default:
		return rpcError(err)
	}
}
func (s *Server) coordinationAuth(ctx context.Context, a *pb.AuthenticatedRequest) error {
	if err := s.auth(ctx, a); err != nil {
		return err
	}
	if a.Scope.Protocol.Minor < 1 {
		return status.Error(codes.FailedPrecondition, "orders_tables.shadow requires protocol 1.1")
	}
	return nil
}
func (s *Server) Commit(ctx context.Context, r *pb.CommitIntent) (*pb.CommitResult, error) {
	if err := s.coordinationAuth(ctx, r.Auth); err != nil {
		return nil, err
	}
	result, err := s.store.CommitIntent(ctx, r)
	return result, coordinationError(err)
}
func (s *Server) Replay(ctx context.Context, r *pb.ReplayRequest) (*pb.ReplayPage, error) {
	if err := s.coordinationAuth(ctx, r.Auth); err != nil {
		return nil, err
	}
	result, err := s.store.Replay(ctx, r.AuthorityEpoch, r.AfterSequence, r.Limit)
	return result, coordinationError(err)
}
func (s *Server) Snapshot(ctx context.Context, r *pb.SnapshotRequest) (*pb.ProjectionSnapshot, error) {
	if err := s.coordinationAuth(ctx, r.Auth); err != nil {
		return nil, err
	}
	result, err := s.store.ProjectionSnapshot(ctx, r.AuthorityEpoch)
	return result, coordinationError(err)
}
