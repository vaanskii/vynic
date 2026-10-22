package server

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"net"
	"net/url"
	"slices"
	"strings"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/store"
)

const OperationalProofCapability = "operational.coordination.proof.v1"
const OperationalProofQueueCapability = "operational.print.queue.proof.v1"
const operationalProofPeerHost = "vynic-edge-operational-proof"

// OperationalProofServer is registered only by an explicit isolated fixture.
// Its postimage API never becomes a production business or dispatch API.
// The separate wrapper avoids the Foundation/OrdersTables method collisions.
type OperationalProofServer struct {
	pb.UnimplementedOperationalProofServer
	store        *store.Store
	identity     store.Identity
	clientRoots  *x509.CertPool
	clientCAHash []byte
	queueProof   bool
}

// NewOperationalProof verifies already pinned authority and an explicitly
// supplied fixture client CA. It does not bind installations or pin grants.
func NewOperationalProof(ctx context.Context, s *store.Store, fixtureClientCA []byte) (*OperationalProofServer, error) {
	if s == nil || len(fixtureClientCA) == 0 || len(fixtureClientCA) > 16384 {
		return nil, store.ErrOperationalAuthority
	}
	block, rest := pem.Decode(fixtureClientCA)
	if block == nil || block.Type != "CERTIFICATE" || len(bytes.TrimSpace(rest)) != 0 || !bytes.Equal(bytes.TrimSpace(fixtureClientCA), bytes.TrimSpace(pem.EncodeToMemory(block))) {
		return nil, errors.New("one canonical pinned fixture CA certificate required")
	}
	ca, err := x509.ParseCertificate(block.Bytes)
	if err != nil || !ca.BasicConstraintsValid || !ca.IsCA || ca.KeyUsage&x509.KeyUsageCertSign == 0 {
		return nil, errors.New("invalid pinned fixture client CA")
	}
	info, err := s.PinnedOperationalProofInfo(ctx)
	if err != nil {
		return nil, err
	}
	id, err := s.Identity()
	if err != nil {
		return nil, err
	}
	if info.Mode != store.OperationalProofMode || info.VenueID != id.VenueID || info.InstallationID != id.InstallationID {
		return nil, store.ErrOperationalAuthority
	}
	// The fixture hands this exact pin to Dart only after official x509
	// preflight. Dart's public certificate API cannot inspect SAN/EKU; future
	// production provisioning requires independently qualified attestation.
	serverBlock, trailing := pem.Decode(id.Certificate)
	if serverBlock == nil || serverBlock.Type != "CERTIFICATE" || len(bytes.TrimSpace(trailing)) != 0 {
		return nil, errors.New("one fixture server certificate required")
	}
	serverLeaf, err := x509.ParseCertificate(serverBlock.Bytes)
	if err != nil || serverLeaf.IsCA || !serverLeaf.BasicConstraintsValid || len(serverLeaf.DNSNames) != 1 || serverLeaf.DNSNames[0] != "vynic-edge.local" || len(serverLeaf.URIs) != 0 || len(serverLeaf.IPAddresses) != 0 || len(serverLeaf.EmailAddresses) != 0 || len(serverLeaf.ExtKeyUsage) != 1 || serverLeaf.ExtKeyUsage[0] != x509.ExtKeyUsageServerAuth || serverLeaf.KeyUsage&x509.KeyUsageDigitalSignature == 0 || time.Now().Before(serverLeaf.NotBefore) || !time.Now().Before(serverLeaf.NotAfter) {
		return nil, errors.New("fixture server certificate SAN, purpose or validity differs")
	}
	roots := x509.NewCertPool()
	roots.AddCert(ca)
	digest := sha256.Sum256(ca.Raw)
	return &OperationalProofServer{store: s, identity: id, clientRoots: roots, clientCAHash: digest[:]}, nil
}

// NewQueuedOperationalProof is an explicit isolated queue-admission fixture.
// Its opaque postimage contract cannot be promoted into production by config.
// Every queued RPC additionally requires a registered four-UUID certificate,
// current paired secret and the exact queue protocol capability.
func NewQueuedOperationalProof(ctx context.Context, s *store.Store, fixtureClientCA []byte) (*OperationalProofServer, error) {
	proof, err := NewOperationalProof(ctx, s, fixtureClientCA)
	if err != nil {
		return nil, err
	}
	proof.queueProof = true
	return proof, nil
}

// OperationalProofTerminalURI is the exact client-certificate purpose/scope.
// CommonName, request tenant strings and unverified metadata are not authority.
func OperationalProofTerminalURI(venueID, installationID, terminalID string) (*url.URL, error) {
	if !validID(venueID) || !validID(installationID) || !validID(terminalID) {
		return nil, store.ErrDenied
	}
	return &url.URL{Scheme: "spiffe", Host: operationalProofPeerHost, Path: "/" + venueID + "/" + installationID + "/" + terminalID}, nil
}

func OperationalProofOriginURI(venueID, installationID, terminalID, originInstallationID string) (*url.URL, error) {
	u, err := OperationalProofTerminalURI(venueID, installationID, terminalID)
	if err != nil || !validID(originInstallationID) {
		return nil, store.ErrDenied
	}
	u.Path += "/" + originInstallationID
	return u, nil
}

type operationalProofPeer struct {
	terminal string
	origin   string
}

func (s *OperationalProofServer) terminalPeer(ctx context.Context) (operationalProofPeer, error) {
	var result operationalProofPeer
	p, ok := peer.FromContext(ctx)
	if !ok {
		return result, status.Error(codes.Unauthenticated, "verified proof terminal certificate required")
	}
	info, ok := p.AuthInfo.(credentials.TLSInfo)
	if !ok || info.State.Version < tls.VersionTLS13 || len(info.State.VerifiedChains) == 0 || len(info.State.PeerCertificates) == 0 {
		return result, status.Error(codes.Unauthenticated, "verified TLS 1.3 proof terminal required")
	}
	leaf := info.State.PeerCertificates[0]
	intermediates := x509.NewCertPool()
	for _, cert := range info.State.PeerCertificates[1:] {
		intermediates.AddCert(cert)
	}
	// A live channel is insufficient: certificate validity and current terminal
	// revocation are rechecked for every RPC, not only at TLS handshake time.
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: s.clientRoots, Intermediates: intermediates, CurrentTime: time.Now(), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}); err != nil {
		return result, status.Error(codes.Unauthenticated, "proof terminal certificate no longer valid")
	}
	if leaf.IsCA || len(leaf.ExtKeyUsage) != 1 || leaf.ExtKeyUsage[0] != x509.ExtKeyUsageClientAuth || len(leaf.URIs) != 1 || len(leaf.DNSNames) != 0 || len(leaf.IPAddresses) != 0 || len(leaf.EmailAddresses) != 0 {
		return result, status.Error(codes.Unauthenticated, "one proof-purpose terminal URI required")
	}
	u := leaf.URIs[0]
	parts := strings.Split(u.Path, "/")
	if (len(parts) != 4 && len(parts) != 5) || parts[0] != "" {
		return result, status.Error(codes.Unauthenticated, "invalid proof terminal URI")
	}
	expected, err := OperationalProofTerminalURI(parts[1], parts[2], parts[3])
	if len(parts) == 5 {
		expected, err = OperationalProofOriginURI(parts[1], parts[2], parts[3], parts[4])
		result.origin = parts[4]
	}
	if err != nil || u.String() != expected.String() {
		return result, status.Error(codes.Unauthenticated, "noncanonical proof terminal URI")
	}
	if parts[1] != s.identity.VenueID || parts[2] != s.identity.InstallationID {
		return result, status.Error(codes.PermissionDenied, "certificate belongs to another proof authority")
	}
	result.terminal = parts[3]
	return result, nil
}

func proofNoUnknown(message proto.Message) bool {
	if message == nil {
		return false
	}
	m := message.ProtoReflect()
	if !m.IsValid() || len(m.GetUnknown()) != 0 {
		return false
	}
	valid := true
	m.Range(func(field protoreflect.FieldDescriptor, value protoreflect.Value) bool {
		if field.Kind() == protoreflect.MessageKind {
			if field.IsList() {
				list := value.List()
				for i := 0; i < list.Len(); i++ {
					if !proofNoUnknown(list.Get(i).Message().Interface()) {
						valid = false
						break
					}
				}
			} else {
				valid = proofNoUnknown(value.Message().Interface())
			}
		}
		return valid
	})
	return valid
}

func (s *OperationalProofServer) auth(ctx context.Context, a *pb.AuthenticatedRequest) (store.OperationalAuth, error) {
	var result store.OperationalAuth
	identity, err := s.terminalPeer(ctx)
	if err != nil {
		return result, err
	}
	if a == nil || a.Scope == nil || a.Scope.Protocol == nil || !proofNoUnknown(a) {
		return result, status.Error(codes.Unauthenticated, "complete proof authentication required")
	}
	if a.Scope.VenueId != s.identity.VenueID || a.Scope.InstallationId != s.identity.InstallationID || a.TerminalId != identity.terminal {
		return result, status.Error(codes.PermissionDenied, "request differs from certificate-bound proof identity")
	}
	protocol := a.Scope.Protocol
	if protocol.Major != 1 || protocol.Minor != 3 {
		return result, status.Error(codes.FailedPrecondition, "isolated proof requires protocol 1.3")
	}
	seen := make(map[string]bool)
	for _, capability := range protocol.RequiredCapabilities {
		if seen[capability] || (capability != OperationalProofCapability && !(s.queueProof && identity.origin != "" && capability == OperationalProofQueueCapability)) {
			return result, status.Error(codes.FailedPrecondition, "unsupported required proof capability")
		}
		seen[capability] = true
	}
	if !seen[OperationalProofCapability] {
		return result, status.Error(codes.FailedPrecondition, "explicit isolated proof capability required")
	}
	if !validID(a.TerminalId) || !store.ValidSecret(a.TerminalSecret) {
		return result, status.Error(codes.Unauthenticated, "invalid proof terminal credential")
	}
	result = store.OperationalAuth{TerminalID: identity.terminal, TerminalSecret: a.TerminalSecret, OriginInstallationID: identity.origin}
	if identity.origin != "" {
		result.ClientCASHA256 = bytes.Clone(s.clientCAHash)
	}
	return result, nil
}

func operationalProofError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, store.ErrOperationalAuthority), errors.Is(err, store.ErrOperationalEpoch):
		return status.Error(codes.FailedPrecondition, "pinned proof authority or epoch mismatch")
	case errors.Is(err, store.ErrOperationalIntent):
		return status.Error(codes.InvalidArgument, "invalid isolated proof request")
	case errors.Is(err, store.ErrRequestReuse):
		return status.Error(codes.AlreadyExists, "immutable proof request ID reused")
	case errors.Is(err, store.ErrOperationalCapacity):
		return status.Error(codes.ResourceExhausted, "isolated proof retained capacity reached")
	case errors.Is(err, store.ErrOperationalResultNotFound):
		return status.Error(codes.NotFound, "no retained result for this terminal")
	case errors.Is(err, store.ErrOperationalCorrupt):
		return status.Error(codes.DataLoss, "isolated proof record failed consistency checks")
	case errors.Is(err, printqueue.ErrInvalid):
		return status.Error(codes.InvalidArgument, "strict frozen print envelope required")
	case errors.Is(err, printqueue.ErrScope):
		return status.Error(codes.PermissionDenied, "frozen print scope differs from authenticated authority")
	case errors.Is(err, printqueue.ErrReuse):
		return status.Error(codes.AlreadyExists, "immutable print identity reused")
	case errors.Is(err, printqueue.ErrBinding), errors.Is(err, printqueue.ErrSchema):
		return status.Error(codes.FailedPrecondition, "frozen print binding or queue schema differs")
	case errors.Is(err, printqueue.ErrCapacity):
		return status.Error(codes.ResourceExhausted, "isolated print retained capacity reached")
	case errors.Is(err, printqueue.ErrBusy):
		return status.Error(codes.FailedPrecondition, "print owner is fenced")
	default:
		return rpcError(err)
	}
}

func (s *OperationalProofServer) Status(ctx context.Context, r *pb.AuthenticatedRequest) (*pb.ProofStatus, error) {
	auth, err := s.auth(ctx, r)
	if err != nil {
		return nil, err
	}
	info, err := s.store.OperationalProofStatus(ctx, auth)
	if err != nil {
		return nil, operationalProofError(err)
	}
	capabilities := []string{OperationalProofCapability}
	if s.queueProof && auth.OriginInstallationID != "" {
		capabilities = append(capabilities, OperationalProofQueueCapability)
	}
	return &pb.ProofStatus{Mode: info.Mode, VenueId: info.VenueID, InstallationId: info.InstallationID, AuthorityEpoch: info.AuthorityEpoch, HeadSequence: info.HeadSequence, GrantSha256: info.GrantSHA256, Protocol: &pb.Protocol{Major: 1, Minor: 3}, Capabilities: capabilities, Limits: proofLimits(), OriginInstallationId: auth.OriginInstallationID}, nil
}

func (s *OperationalProofServer) Commit(ctx context.Context, r *pb.ProofCommitRequest) (*pb.ProofCommitResult, error) {
	if r == nil || !proofNoUnknown(r) {
		return nil, status.Error(codes.InvalidArgument, "known proof commit fields required")
	}
	auth, err := s.auth(ctx, r.Auth)
	if err != nil {
		return nil, err
	}
	request, err := proofCommit(r, auth)
	if err != nil {
		return nil, operationalProofError(err)
	}
	var result *store.OperationalCommitResult
	if r.PrintAdmission != "" {
		if !s.queueProof || auth.OriginInstallationID == "" || !slices.Contains(r.Auth.Scope.Protocol.RequiredCapabilities, OperationalProofQueueCapability) {
			return nil, status.Error(codes.PermissionDenied, "registered isolated queue proof capability required")
		}
		result, err = s.store.CommitOperationalQueued(ctx, request)
	} else {
		result, err = s.store.CommitOperational(ctx, request)
	}
	if err != nil {
		return nil, operationalProofError(err)
	}
	return proofResult(result), nil
}

func (s *OperationalProofServer) GetResult(ctx context.Context, r *pb.ProofResultRequest) (*pb.ProofCommitResult, error) {
	if r == nil || !proofNoUnknown(r) {
		return nil, status.Error(codes.InvalidArgument, "known proof result fields required")
	}
	auth, err := s.auth(ctx, r.Auth)
	if err != nil {
		return nil, err
	}
	result, err := s.store.OperationalResult(ctx, auth, r.AuthorityEpoch, r.RequestId)
	if err != nil {
		return nil, operationalProofError(err)
	}
	if result.PrintAdmission != "" && (!s.queueProof || !slices.Contains(r.Auth.Scope.Protocol.RequiredCapabilities, OperationalProofQueueCapability)) {
		return nil, status.Error(codes.PermissionDenied, "registered isolated queue proof capability required")
	}
	return proofResult(result), nil
}

func (s *OperationalProofServer) Replay(ctx context.Context, r *pb.ProofReplayRequest) (*pb.ProofReplayPage, error) {
	if r == nil || !proofNoUnknown(r) {
		return nil, status.Error(codes.InvalidArgument, "known proof replay fields required")
	}
	auth, err := s.auth(ctx, r.Auth)
	if err != nil {
		return nil, err
	}
	page, err := s.store.OperationalReplay(ctx, auth, r.AuthorityEpoch, r.AfterSequence, r.Limit)
	if err != nil {
		return nil, operationalProofError(err)
	}
	result := &pb.ProofReplayPage{Mode: page.Mode, AuthorityEpoch: page.AuthorityEpoch, AfterSequence: page.AfterSequence, HeadSequence: page.HeadSequence, NextSequence: page.NextSequence}
	for i := range page.Events {
		result.Events = append(result.Events, proofEvent(&page.Events[i]))
	}
	return result, nil
}

func (s *OperationalProofServer) Snapshot(ctx context.Context, r *pb.ProofSnapshotRequest) (*pb.ProofSnapshot, error) {
	if r == nil || !proofNoUnknown(r) {
		return nil, status.Error(codes.InvalidArgument, "known proof snapshot fields required")
	}
	auth, err := s.auth(ctx, r.Auth)
	if err != nil {
		return nil, err
	}
	snapshot, err := s.store.OperationalProjectionSnapshot(ctx, auth, r.AuthorityEpoch)
	if err != nil {
		return nil, operationalProofError(err)
	}
	result := &pb.ProofSnapshot{Mode: snapshot.Mode, VenueId: snapshot.VenueID, InstallationId: snapshot.InstallationID, AuthorityEpoch: snapshot.AuthorityEpoch, Sequence: snapshot.Sequence}
	for _, entity := range snapshot.Entities {
		result.Entities = append(result.Entities, proofEntity(entity))
	}
	return result, nil
}

// Serve is deliberately separate from normal Foundation startup. All five
// proof methods require fresh certificate identity and active paired secrets.
func (s *OperationalProofServer) Serve(ctx context.Context, listener net.Listener) error {
	cert, err := tls.X509KeyPair(s.identity.Certificate, s.identity.TLSKey)
	if err != nil {
		return err
	}
	g := grpc.NewServer(
		grpc.Creds(credentials.NewTLS(&tls.Config{Certificates: []tls.Certificate{cert}, ClientCAs: s.clientRoots, ClientAuth: tls.RequireAndVerifyClientCert, MinVersion: tls.VersionTLS13})),
		grpc.MaxRecvMsgSize(store.OperationalMaxRequestBytes+(64<<10)),
		grpc.MaxSendMsgSize(store.OperationalMaxResultBytes+(1<<20)),
		grpc.MaxConcurrentStreams(64),
	)
	pb.RegisterOperationalProofServer(g, s)
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
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
