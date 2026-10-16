// Package printeragent provides authenticated loopback printer infrastructure.
// It holds every job admission and physical call until authoritative offline
// Device/origin/route provisioning exists. A profile is not such authority.
package printeragent

import (
	"bytes"
	"context"
	"crypto"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"math"
	"net"
	"net/url"
	"reflect"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printerprovisioning"
	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
)

const ServerName = "vynic-printer-agent.local"
const Capability = "printer.agent.health.v1"
const HeldProvisioning = "HELD_PROVISIONING: signed Device, terminal, origin and physical-route authority unavailable"

type HealthSource interface {
	Health(context.Context) (printhost.Health, error)
}

// ClientPin authorizes infrastructure observations only. Neither this local
// certificate pin nor any claimed job tenant becomes production authority.
type ClientPin struct {
	ClientID          string `json:"clientId"`
	CertificateSHA256 string `json:"certificateSha256"`
}

type ClientObservation = printerprovisioning.AuthenticatedPeer

// Candidate validation is optional and cannot enable admission. A qualified
// production issuer/current-state/cutover bridge is still absent in this API.
type LocalCandidate interface {
	Validate(context.Context, ClientObservation, printhost.Pins, printqueue.FrozenJob) error
}

type Config struct {
	Pins        printhost.Pins
	Certificate tls.Certificate
	ClientCA    []byte
	Clients     []ClientPin
	Health      HealthSource
	Candidate   LocalCandidate
}

type Server struct {
	pb.UnimplementedPrinterAgentServer
	pins            printhost.Pins
	root            *x509.CertPool
	health          HealthSource
	candidate       LocalCandidate
	serverNotBefore time.Time
	serverNotAfter  time.Time
	now             func() time.Time
	clientsMu       sync.RWMutex
	clients         map[string]string
	fenced          atomic.Bool
	grpc            *grpc.Server
	lifeMu          sync.Mutex
	served          bool
	stopOnce        sync.Once
	stopDone        chan struct{}
}

func digest(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, c := range value {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}

// NewServer performs only static validation. It never starts a listener,
// probes Host.Health, generates credentials, enrolls a client or opens a queue.
func NewServer(c Config) (*Server, error) {
	if c.Pins.Validate() != nil || c.Health == nil || len(c.Clients) == 0 || len(c.Clients) > 64 || len(c.ClientCA) == 0 || len(c.ClientCA) > 16384 {
		return nil, errors.New("invalid explicit printer agent configuration")
	}
	v := reflect.ValueOf(c.Health)
	switch v.Kind() {
	case reflect.Chan, reflect.Func, reflect.Map, reflect.Pointer, reflect.Interface, reflect.Slice:
		if v.IsNil() {
			return nil, errors.New("printer agent health source missing")
		}
	}
	if c.Candidate != nil {
		v := reflect.ValueOf(c.Candidate)
		switch v.Kind() {
		case reflect.Chan, reflect.Func, reflect.Map, reflect.Pointer, reflect.Interface, reflect.Slice:
			if v.IsNil() {
				return nil, errors.New("printer candidate validator missing")
			}
		}
	}
	block, rest := pem.Decode(c.ClientCA)
	if block == nil || block.Type != "CERTIFICATE" || len(bytes.TrimSpace(rest)) != 0 {
		return nil, errors.New("one explicit client CA required")
	}
	ca, err := x509.ParseCertificate(block.Bytes)
	if err != nil || !ca.IsCA || !ca.BasicConstraintsValid || ca.KeyUsage&x509.KeyUsageCertSign == 0 || time.Now().Before(ca.NotBefore) || !time.Now().Before(ca.NotAfter) {
		return nil, errors.New("invalid current client CA")
	}
	if len(c.Certificate.Certificate) != 1 {
		return nil, errors.New("one pinned server leaf required")
	}
	leaf, err := x509.ParseCertificate(c.Certificate.Certificate[0])
	if err != nil || leaf.IsCA || !leaf.BasicConstraintsValid || len(leaf.DNSNames) != 1 || leaf.DNSNames[0] != ServerName || len(leaf.URIs) != 0 || len(leaf.IPAddresses) != 0 || len(leaf.EmailAddresses) != 0 || len(leaf.ExtKeyUsage) != 1 || leaf.ExtKeyUsage[0] != x509.ExtKeyUsageServerAuth || leaf.KeyUsage&x509.KeyUsageDigitalSignature == 0 || time.Now().Before(leaf.NotBefore) || !time.Now().Before(leaf.NotAfter) {
		return nil, errors.New("server pin purpose, SAN or validity differs")
	}
	signer, ok := c.Certificate.PrivateKey.(crypto.Signer)
	if !ok {
		return nil, errors.New("server private key unavailable")
	}
	pub, err := x509.MarshalPKIXPublicKey(signer.Public())
	if err != nil || !bytes.Equal(pub, leaf.RawSubjectPublicKeyInfo) {
		return nil, errors.New("server key differs from certificate")
	}
	// Retain an independent key/certificate so external config mutation cannot
	// change the listener identity after its explicit pin was validated.
	keyDER, err := x509.MarshalPKCS8PrivateKey(c.Certificate.PrivateKey)
	if err != nil {
		return nil, errors.New("server key cannot be frozen")
	}
	key, err := x509.ParsePKCS8PrivateKey(keyDER)
	if err != nil {
		return nil, errors.New("server key cannot be frozen")
	}
	certificate := tls.Certificate{Certificate: [][]byte{bytes.Clone(leaf.Raw)}, PrivateKey: key, Leaf: leaf}
	root := x509.NewCertPool()
	root.AddCert(ca)
	s := &Server{pins: c.Pins, root: root, health: c.Health, candidate: c.Candidate, serverNotBefore: leaf.NotBefore, serverNotAfter: leaf.NotAfter, now: time.Now, clients: make(map[string]string), stopDone: make(chan struct{})}
	for _, pin := range c.Clients {
		if !printqueue.CanonicalUUID(pin.ClientID) || !digest(pin.CertificateSHA256) || s.clients[pin.ClientID] != "" {
			return nil, errors.New("invalid or duplicate client observation pin")
		}
		s.clients[pin.ClientID] = pin.CertificateSHA256
	}
	s.grpc = grpc.NewServer(grpc.Creds(credentials.NewTLS(&tls.Config{Certificates: []tls.Certificate{certificate}, ClientCAs: root, ClientAuth: tls.RequireAndVerifyClientCert, MinVersion: tls.VersionTLS13, MaxVersion: tls.VersionTLS13})), grpc.MaxRecvMsgSize(printqueue.MaxEnvelopeBytes+(64<<10)), grpc.MaxSendMsgSize(256<<10), grpc.MaxConcurrentStreams(32))
	pb.RegisterPrinterAgentServer(s.grpc, s)
	return s, nil
}

func ClientURI(hostID, clientID string) (*url.URL, error) {
	if !printqueue.CanonicalUUID(hostID) || !printqueue.CanonicalUUID(clientID) {
		return nil, errors.New("invalid printer agent identity")
	}
	return &url.URL{Scheme: "spiffe", Host: "vynic-printer-agent", Path: "/" + hostID + "/" + clientID}, nil
}

// RevokeClient is a local owner action, never an enrollment/revocation RPC.
// The exact active observation pin is checked again on every live TLS call.
func (s *Server) RevokeClient(clientID string) {
	s.clientsMu.Lock()
	delete(s.clients, clientID)
	s.clientsMu.Unlock()
}

func strictMessage(m proto.Message) bool {
	if m == nil || !m.ProtoReflect().IsValid() {
		return false
	}
	valid := true
	var check func(protoreflect.Message)
	check = func(message protoreflect.Message) {
		if len(message.GetUnknown()) != 0 {
			valid = false
			return
		}
		message.Range(func(field protoreflect.FieldDescriptor, value protoreflect.Value) bool {
			if field.IsList() && field.Message() != nil {
				list := value.List()
				for i := 0; i < list.Len(); i++ {
					check(list.Get(i).Message())
				}
			} else if field.Message() != nil {
				check(value.Message())
			}
			return valid
		})
	}
	check(m.ProtoReflect())
	return valid
}

func (s *Server) authenticate(ctx context.Context, a *pb.PrinterAgentAuth) (string, error) {
	if s.fenced.Load() {
		return "", status.Error(codes.Unavailable, "printer agent stopping")
	}
	now := s.now()
	if now.Before(s.serverNotBefore) || !now.Before(s.serverNotAfter) {
		return "", status.Error(codes.Unauthenticated, "server pin no longer valid")
	}
	p, ok := peer.FromContext(ctx)
	if !ok {
		return "", status.Error(codes.Unauthenticated, "printer agent mutual TLS required")
	}
	info, ok := p.AuthInfo.(credentials.TLSInfo)
	if !ok || info.State.Version != tls.VersionTLS13 || len(info.State.VerifiedChains) == 0 || len(info.State.PeerCertificates) == 0 {
		return "", status.Error(codes.Unauthenticated, "verified printer client required")
	}
	leaf := info.State.PeerCertificates[0]
	if leaf.IsCA || len(leaf.ExtKeyUsage) != 1 || leaf.ExtKeyUsage[0] != x509.ExtKeyUsageClientAuth || leaf.KeyUsage&x509.KeyUsageDigitalSignature == 0 || len(leaf.URIs) != 1 || len(leaf.DNSNames) != 0 || len(leaf.IPAddresses) != 0 || len(leaf.EmailAddresses) != 0 {
		return "", status.Error(codes.Unauthenticated, "client purpose differs")
	}
	intermediates := x509.NewCertPool()
	for _, cert := range info.State.PeerCertificates[1:] {
		intermediates.AddCert(cert)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: s.root, Intermediates: intermediates, CurrentTime: now, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}); err != nil {
		return "", status.Error(codes.Unauthenticated, "client certificate no longer valid")
	}
	uri := leaf.URIs[0]
	parts := strings.Split(uri.Path, "/")
	if len(parts) != 3 {
		return "", status.Error(codes.Unauthenticated, "client scope differs")
	}
	want, err := ClientURI(s.pins.HostID, parts[2])
	if err != nil || uri.String() != want.String() {
		return "", status.Error(codes.Unauthenticated, "client scope differs")
	}
	hash := sha256.Sum256(leaf.Raw)
	s.clientsMu.RLock()
	expected := s.clients[parts[2]]
	s.clientsMu.RUnlock()
	if expected == "" || expected != hex.EncodeToString(hash[:]) {
		return "", status.Error(codes.Unauthenticated, "client observation pin absent or revoked")
	}
	if a == nil || !strictMessage(a) || a.HostId != s.pins.HostID || a.ClientId != parts[2] {
		return "", status.Error(codes.PermissionDenied, "printer profile identity differs")
	}
	if a.ProtocolMajor != 1 || a.ProtocolMinor != 0 || a.ReaderVersion != printhost.ReaderVersion || !slices.Equal(a.RequiredCapabilities, []string{Capability}) {
		return "", status.Error(codes.FailedPrecondition, "printer agent protocol differs")
	}
	return parts[2], nil
}

func wirePins(p printhost.Pins) *pb.PrinterAgentPins {
	return &pb.PrinterAgentPins{Scope: string(p.Scope), OwnershipPolicy: string(p.OwnershipPolicy), ClusterId: p.ClusterID, MembershipSha256: p.MembershipSHA256, Role: string(p.Role), VenueId: p.VenueID, InstallationId: p.InstallationID, DeviceId: p.DeviceID, HostId: p.HostID, GatewayHostId: p.GatewayHostID, AuthorityEpoch: p.AuthorityEpoch, ProtocolVersion: p.ProtocolVersion, HelperProtocolVersion: uint32(p.HelperProtocolVersion), DatabaseSchemaVersion: p.DatabaseSchemaVersion, MinimumReaderVersion: p.MinimumReaderVersion, RouteRevision: p.RouteRevision, ConfigRevision: p.ConfigRevision, RegistryRevision: p.RegistryRevision, BindingRevision: p.BindingRevision, CapabilityRevision: p.CapabilityRevision, CapabilityProfileSha256: p.CapabilityProfileSHA256, HostBinarySha256: p.HostBinarySHA256, HelperBinarySha256: p.HelperBinarySHA256}
}

func (s *Server) Health(ctx context.Context, r *pb.PrinterAgentHealthRequest) (*pb.PrinterAgentHealthResponse, error) {
	if !strictMessage(r) {
		return nil, status.Error(codes.InvalidArgument, "unknown printer health fields")
	}
	client, err := s.authenticate(ctx, r.Auth)
	if err != nil {
		return nil, err
	}
	h, probeErr := s.health.Health(ctx)
	if ctx.Err() != nil {
		return nil, status.FromContextError(ctx.Err()).Err()
	}
	if printhost.ComparePins(s.pins, h.Pins, printhost.ReaderVersion) != nil || h.Version != printhost.ProtocolVersion {
		return nil, status.Error(codes.FailedPrecondition, "printer profile evidence changed")
	}
	states := map[printhost.State]pb.PrinterAgentLifecycle{printhost.New: pb.PrinterAgentLifecycle_PRINTER_AGENT_NEW, printhost.Starting: pb.PrinterAgentLifecycle_PRINTER_AGENT_STARTING, printhost.Running: pb.PrinterAgentLifecycle_PRINTER_AGENT_RUNNING, printhost.Draining: pb.PrinterAgentLifecycle_PRINTER_AGENT_DRAINING, printhost.Stopped: pb.PrinterAgentLifecycle_PRINTER_AGENT_STOPPED, printhost.Held: pb.PrinterAgentLifecycle_PRINTER_AGENT_HELD}
	state, ok := states[h.State]
	if !ok || len(h.PrinterHolds) > 64 || h.ActiveAdmissions > math.MaxInt64 || h.Ready && h.State != printhost.Running {
		return nil, status.Error(codes.DataLoss, "printer health evidence invalid")
	}
	result := &pb.PrinterAgentHealthResponse{ProtocolVersion: 1, Pins: wirePins(s.pins), ClientId: client, State: state, SoftwareReady: probeErr == nil && h.Ready, PhysicalState: pb.PrinterAgentPhysicalState_PRINTER_AGENT_PHYSICAL_HELD, AdmissionState: pb.PrinterAgentAdmissionState_PRINTER_AGENT_ADMISSION_HELD_PROVISIONING, ActiveAdmissions: h.ActiveAdmissions, HoldReasons: []pb.PrinterAgentHoldReason{pb.PrinterAgentHoldReason_PRINTER_AGENT_PROVISIONING_UNQUALIFIED, pb.PrinterAgentHoldReason_PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING}}
	if s.pins.Scope == printhost.VenueShared {
		result.HoldReasons = append(result.HoldReasons, pb.PrinterAgentHoldReason_PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED)
	}
	if probeErr != nil || !h.Ready {
		result.HoldReasons = append(result.HoldReasons, pb.PrinterAgentHoldReason_PRINTER_AGENT_HOST_UNAVAILABLE)
	}
	if h.BlockedReason != "" || len(h.PrinterHolds) != 0 {
		result.HoldReasons = append(result.HoldReasons, pb.PrinterAgentHoldReason_PRINTER_AGENT_RETAINED_QUEUE_HOLD)
	}
	seen := make(map[string]bool)
	for _, hold := range h.PrinterHolds {
		if !printqueue.CanonicalUUID(hold.PhysicalPrinterID) || seen[hold.PhysicalPrinterID] || len(hold.Reason) == 0 || len(hold.Reason) > 512 {
			return nil, status.Error(codes.DataLoss, "printer hold evidence invalid")
		}
		seen[hold.PhysicalPrinterID] = true
		result.PrinterHolds = append(result.PrinterHolds, &pb.PrinterAgentPrinterHold{PhysicalPrinterId: hold.PhysicalPrinterID, Reason: hold.Reason})
	}
	return result, nil
}

func (s *Server) SubmitLocal(ctx context.Context, r *pb.PrinterAgentSubmitLocalRequest) (*pb.PrinterAgentSubmissionResult, error) {
	if !strictMessage(r) {
		return nil, status.Error(codes.InvalidArgument, "unknown local job fields")
	}
	client, err := s.authenticate(ctx, r.Auth)
	if err != nil {
		return nil, err
	}
	if !printqueue.CanonicalUUID(r.RequestId) || !printqueue.CanonicalUUID(r.JobId) || !digest(r.EnvelopeSha256) {
		return nil, status.Error(codes.InvalidArgument, "invalid immutable local identity")
	}
	job, err := printqueue.DecodeFrozenJob(bytes.Clone(r.FrozenEnvelope))
	if err != nil || job.RequestID != r.RequestId || job.JobID != r.JobId || job.Digest() != r.EnvelopeSha256 {
		return nil, status.Error(codes.InvalidArgument, "frozen envelope identity or digest differs")
	}
	if s.pins.Scope != printhost.Local || job.VenueID != s.pins.VenueID || job.InstallationID != s.pins.InstallationID || job.DeviceID != s.pins.DeviceID || job.AuthorityEpoch != s.pins.AuthorityEpoch || job.Destination.WorkerHostID != s.pins.HostID || job.RouteRevision != s.pins.RouteRevision || job.ConfigRevision != s.pins.ConfigRevision || job.RegistryRevision != s.pins.RegistryRevision || job.BindingRevision != s.pins.BindingRevision {
		return nil, status.Error(codes.PermissionDenied, "local frozen profile differs")
	}
	profileHash := sha256.Sum256(job.CapabilityProfile)
	if hex.EncodeToString(profileHash[:]) != s.pins.CapabilityProfileSHA256 {
		return nil, status.Error(codes.PermissionDenied, "local capability profile differs")
	}
	if s.candidate != nil {
		p, _ := peer.FromContext(ctx) // authenticate already verified this TLS peer.
		info := p.AuthInfo.(credentials.TLSInfo)
		observation := ClientObservation{ClientID: client, CertificateDER: bytes.Clone(info.State.PeerCertificates[0].Raw)}
		if err := s.candidate.Validate(ctx, observation, s.pins, job); err != nil {
			return nil, status.Error(codes.FailedPrecondition, HeldProvisioning)
		}
	}
	// Terminal/origin, route contents and production Device identity have no
	// authoritative signed local registration. Do not infer it from the job,
	// TLS observation pin, bare host profile or ISOLATED_PROOF tables.
	return nil, status.Error(codes.FailedPrecondition, HeldProvisioning)
}

func (s *Server) GetLocalResult(ctx context.Context, r *pb.PrinterAgentGetLocalResultRequest) (*pb.PrinterAgentSubmissionResult, error) {
	if !strictMessage(r) {
		return nil, status.Error(codes.InvalidArgument, "unknown local result fields")
	}
	if _, err := s.authenticate(ctx, r.Auth); err != nil {
		return nil, err
	}
	if !printqueue.CanonicalUUID(r.RequestId) || !printqueue.CanonicalUUID(r.JobId) || !digest(r.EnvelopeSha256) {
		return nil, status.Error(codes.InvalidArgument, "invalid immutable result identity")
	}
	return nil, status.Error(codes.FailedPrecondition, HeldProvisioning)
}

func (s *Server) Fence() { s.fenced.Store(true) }

// Stop fences immediately and waits actual graceful handler drain. A caller's
// timeout never releases an active handler/listener or forces resource close.
func (s *Server) Stop(ctx context.Context) error {
	s.Fence()
	s.stopOnce.Do(func() { go func() { s.grpc.GracefulStop(); close(s.stopDone) }() })
	select {
	case <-s.stopDone:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// Serve owns only an explicit loopback TCP listener. No port discovery, service
// spawning or credential/OS configuration is performed here.
func (s *Server) Serve(ctx context.Context, l net.Listener) error {
	if l == nil {
		return errors.New("printer agent listener missing")
	}
	addr, ok := l.Addr().(*net.TCPAddr)
	if !ok || !addr.IP.IsLoopback() {
		return errors.New("printer agent requires loopback TCP")
	}
	s.lifeMu.Lock()
	if s.served || s.fenced.Load() {
		s.lifeMu.Unlock()
		return errors.New("printer agent already served or stopped")
	}
	s.served = true
	s.lifeMu.Unlock()
	defer l.Close()
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			s.Stop(context.Background())
		case <-done:
		}
	}()
	err := s.grpc.Serve(l)
	if errors.Is(err, grpc.ErrServerStopped) {
		return nil
	}
	return err
}
