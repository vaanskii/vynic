package server_test

import (
	"context"
	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	"testing"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/server"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

func TestCoordinationRequiresAuthenticatedVenueVersionAndEpoch(t *testing.T) {
	s, id := testutil.Bound(t, t.TempDir())
	defer s.Close()
	srv, e := server.New(s)
	if e != nil {
		t.Fatal(e)
	}
	ticket, _ := s.IssueTicket()
	auth := &pb.AuthenticatedRequest{Scope: &pb.Scope{VenueId: id.VenueID, InstallationId: id.InstallationID, Protocol: &pb.Protocol{Major: 1, Minor: 1}}, TerminalId: uuid.NewString(), TerminalSecret: store.Secret()}
	if e = s.Pair(context.Background(), ticket, uuid.NewString(), auth.TerminalId, auth.TerminalSecret, "A"); e != nil {
		t.Fatal(e)
	}
	for _, name := range []string{"valid", "no-auth", "secret", "venue", "edge", "minor", "epoch", "capability"} {
		t.Run(name, func(t *testing.T) {
			a := proto.Clone(auth).(*pb.AuthenticatedRequest)
			epoch := uint64(1)
			want := codes.OK
			switch name {
			case "no-auth":
				a = nil
				want = codes.Unauthenticated
			case "secret":
				a.TerminalSecret = store.Secret()
				want = codes.Unauthenticated
			case "venue":
				a.Scope.VenueId = uuid.NewString()
				want = codes.PermissionDenied
			case "edge":
				a.Scope.InstallationId = uuid.NewString()
				want = codes.PermissionDenied
			case "minor":
				a.Scope.Protocol.Minor = 0
				want = codes.FailedPrecondition
			case "epoch":
				epoch = 2
				want = codes.FailedPrecondition
			case "capability":
				a.Scope.Protocol.RequiredCapabilities = []string{"orders.authoritative"}
				want = codes.FailedPrecondition
			}
			_, e := srv.Snapshot(context.Background(), &pb.SnapshotRequest{Auth: a, AuthorityEpoch: epoch})
			if status.Code(e) != want {
				t.Fatal(e)
			}
		})
	}
	if _, e = srv.Commit(context.Background(), &pb.CommitIntent{Auth: auth, RequestId: uuid.NewString(), AuthorityEpoch: 1}); status.Code(e) != codes.InvalidArgument {
		t.Fatal(e)
	}
}
