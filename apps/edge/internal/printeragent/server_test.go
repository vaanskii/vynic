package printeragent

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

type testCA struct {
	certificate *x509.Certificate
	key         *ecdsa.PrivateKey
	pem         []byte
}

func newCA(t *testing.T) testCA {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "isolated-printer-agent-test-CA"}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return testCA{cert, key, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})}
}
func issue(t *testing.T, ca testCA, template *x509.Certificate) (tls.Certificate, []byte, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.CreateCertificate(rand.Reader, template, ca.certificate, &key.PublicKey, ca.key)
	if err != nil {
		t.Fatal(err)
	}
	certPem := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	keyPem := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	pair, err := tls.X509KeyPair(certPem, keyPem)
	if err != nil {
		t.Fatal(err)
	}
	return pair, certPem, keyPem
}
func template(usage x509.ExtKeyUsage) *x509.Certificate {
	return &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{usage}}
}

type heldWorker struct{}

func (heldWorker) Stop(context.Context) error { return nil }

const fixtureProfile = `{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"partial","encoding":"georgianViaRaster","beep":{"capability":"epsonEscA97Pattern","enabled":false}}`

type fixture struct {
	store                           *store.Store
	host                            *printhost.Host
	config                          Config
	ca                              testCA
	client                          tls.Certificate
	serverPEM, clientPEM, clientKey []byte
	clientID                        string
	deviceInstallationID            string
}

func newFixture(t *testing.T, dir string) *fixture {
	t.Helper()
	s, id := testutil.Bound(t, filepath.Join(dir, "state"))
	ca := newCA(t)
	serverTemplate := template(x509.ExtKeyUsageServerAuth)
	serverTemplate.DNSNames = []string{ServerName}
	server, serverPEM, _ := issue(t, ca, serverTemplate)
	clientID, hostID, deviceID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	uri, err := ClientURI(hostID, clientID)
	if err != nil {
		t.Fatal(err)
	}
	clientTemplate := template(x509.ExtKeyUsageClientAuth)
	clientTemplate.URIs = []*url.URL{uri}
	client, clientPEM, clientKey := issue(t, ca, clientTemplate)
	profileHash := sha256.Sum256([]byte(fixtureProfile))
	pins := printhost.Pins{Scope: printhost.Local, OwnershipPolicy: printhost.LocalHost, Role: printhost.POSAgent, VenueID: id.VenueID, InstallationID: id.InstallationID, DeviceID: deviceID, HostID: hostID, GatewayHostID: hostID, AuthorityEpoch: 1, ProtocolVersion: 1, HelperProtocolVersion: printtransport.HelperProtocolVersion, DatabaseSchemaVersion: store.SchemaVersion, MinimumReaderVersion: printhost.ReaderVersion, RouteRevision: 1, ConfigRevision: 1, RegistryRevision: 1, BindingRevision: 1, CapabilityRevision: 1, CapabilityProfileSHA256: hex.EncodeToString(profileHash[:]), HostBinarySHA256: strings.Repeat("b", 64), HelperBinarySHA256: strings.Repeat("c", 64)}
	q, err := printqueue.NewProofStore(context.Background(), s.DB, printqueue.GatewayIdentity{VenueID: pins.VenueID, InstallationID: pins.InstallationID, DeviceID: deviceID, WorkerHostID: hostID, Epoch: 1})
	if err != nil {
		t.Fatal(err)
	}
	probe, err := printhost.QueueProbe(q, pins, []string{uuid.NewString()})
	if err != nil {
		t.Fatal(err)
	}
	host, err := printhost.NewHost(printhost.Config{Pins: pins}, func(context.Context, printhost.Pins) (printhost.Components, error) {
		return printhost.Components{Queue: q, Worker: heldWorker{}, Probe: probe, Start: func() error { return nil }, Close: s.Close, HasPrinterWriter: true}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if err = host.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := host.Stop(ctx); err != nil {
			t.Error(err)
		}
	})
	hash := sha256.Sum256(client.Certificate[0])
	return &fixture{store: s, host: host, config: Config{Pins: pins, Certificate: server, ClientCA: ca.pem, Clients: []ClientPin{{ClientID: clientID, CertificateSHA256: hex.EncodeToString(hash[:])}}, Health: host}, ca: ca, client: client, serverPEM: serverPEM, clientPEM: clientPEM, clientKey: clientKey, clientID: clientID, deviceInstallationID: uuid.NewString()}
}
func (f *fixture) auth() *pb.PrinterAgentAuth {
	return &pb.PrinterAgentAuth{HostId: f.config.Pins.HostID, ClientId: f.clientID, ProtocolMajor: 1, ReaderVersion: 2, RequiredCapabilities: []string{Capability}}
}
func connect(t *testing.T, address string, f *fixture, client tls.Certificate) (pb.PrinterAgentClient, *grpc.ClientConn) {
	t.Helper()
	roots := x509.NewCertPool()
	roots.AddCert(f.ca.certificate)
	conn, err := grpc.NewClient(address, grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{RootCAs: roots, ServerName: ServerName, Certificates: []tls.Certificate{client}, MinVersion: tls.VersionTLS13})))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return pb.NewPrinterAgentClient(conn), conn
}
func serve(t *testing.T, s *Server) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- s.Serve(context.Background(), listener) }()
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := s.Stop(ctx); err != nil {
			t.Error(err)
		}
		select {
		case err := <-done:
			if err != nil {
				t.Error(err)
			}
		case <-ctx.Done():
			t.Error("server did not drain")
		}
	})
	return listener.Addr().String()
}
func requireCode(t *testing.T, want codes.Code, err error) {
	t.Helper()
	if status.Code(err) != want {
		t.Fatalf("want %s got %v", want, err)
	}
}
func (f *fixture) envelope(t *testing.T) []byte {
	t.Helper()
	primary := []byte{0x1b, 0x40, 0, 0xff, 0x1d, 0x56, 0x00}
	hash := sha256.Sum256(primary)
	p := f.config.Pins
	j := printqueue.FrozenJob{Version: 1, JobID: uuid.NewString(), EffectID: uuid.NewString(), RequestID: uuid.NewString(), TerminalID: f.clientID, VenueID: p.VenueID, InstallationID: p.InstallationID, OriginInstallationID: f.deviceInstallationID, AuthorityEpoch: p.AuthorityEpoch, DeviceID: p.DeviceID, PhysicalPrinterID: uuid.NewString(), AliasID: uuid.NewString(), RouteRevision: p.RouteRevision, ConfigRevision: p.ConfigRevision, RegistryRevision: p.RegistryRevision, BindingRevision: p.BindingRevision, AttemptID: uuid.NewString(), BeepAttemptID: uuid.NewString(), PrimaryBytes: primary, PrimarySHA256: hex.EncodeToString(hash[:]), CapabilityProfile: json.RawMessage(fixtureProfile)}
	j.Destination = printtransport.Destination{PhysicalPrinterID: j.PhysicalPrinterID, WorkerHostID: p.HostID, Transport: printtransport.TCP, Host: "192.168.50.50", Port: 9100, DocumentName: "synthetic-only"}
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = printqueue.DecodeFrozenJob(raw); err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestAuthenticatedHealthStrictHeldBytesAndZeroQueueWrites(t *testing.T) {
	f := newFixture(t, t.TempDir())
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	client, _ := connect(t, serve(t, s), f, f.client)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	h, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()})
	if err != nil {
		t.Fatal(err)
	}
	if !h.SoftwareReady || h.PhysicalState != pb.PrinterAgentPhysicalState_PRINTER_AGENT_PHYSICAL_HELD || h.AdmissionState != pb.PrinterAgentAdmissionState_PRINTER_AGENT_ADMISSION_HELD_PROVISIONING || !proto.Equal(h.Pins, wirePins(f.config.Pins)) {
		t.Fatal("software health implies unsafe readiness", h)
	}
	raw := f.envelope(t)
	j, err := printqueue.DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	r := &pb.PrinterAgentSubmitLocalRequest{Auth: f.auth(), RequestId: j.RequestID, JobId: j.JobID, FrozenEnvelope: raw, EnvelopeSha256: j.Digest()}
	before := append([]byte(nil), raw...)
	for i := 0; i < 2; i++ {
		result, err := client.SubmitLocal(ctx, r)
		requireCode(t, codes.FailedPrecondition, err)
		if result != nil || !strings.Contains(err.Error(), "HELD_PROVISIONING") {
			t.Fatal("fabricated acceptance", result, err)
		}
	}
	if string(before) != string(r.FrozenEnvelope) {
		t.Fatal("immutable bytes changed")
	}
	result, err := client.GetLocalResult(ctx, &pb.PrinterAgentGetLocalResultRequest{Auth: f.auth(), RequestId: j.RequestID, JobId: j.JobID, EnvelopeSha256: j.Digest()})
	requireCode(t, codes.FailedPrecondition, err)
	if result != nil {
		t.Fatal("fabricated receipt")
	}
	for _, table := range []string{"pq_job", "pq_receipt", "pq_claim", "pq_attempt", "pq_beep", "op_entity", "op_request", "op_event", "op_effect"} {
		var count int
		if err := f.store.DB.QueryRow("SELECT count(*) FROM " + table).Scan(&count); err != nil || count != 0 {
			t.Fatal("held API wrote state", table, count, err)
		}
	}
	for name, mutate := range map[string]func(*pb.PrinterAgentSubmitLocalRequest){"wrongHash": func(r *pb.PrinterAgentSubmitLocalRequest) { r.EnvelopeSha256 = strings.Repeat("d", 64) }, "changedExactBytes": func(r *pb.PrinterAgentSubmitLocalRequest) { r.FrozenEnvelope = append(r.FrozenEnvelope, ' ') }, "wrongJob": func(r *pb.PrinterAgentSubmitLocalRequest) { r.JobId = uuid.NewString() }, "unknownWire": func(r *pb.PrinterAgentSubmitLocalRequest) { r.ProtoReflect().SetUnknown([]byte{0xf8, 0x07, 1}) }} {
		t.Run(name, func(t *testing.T) {
			copy := proto.Clone(r).(*pb.PrinterAgentSubmitLocalRequest)
			mutate(copy)
			_, err := client.SubmitLocal(ctx, copy)
			requireCode(t, codes.InvalidArgument, err)
		})
	}
	for _, field := range []string{"venueId", "deviceId", "installationId", "authorityEpoch", "routeRevision", "configRevision", "bindingRevision", "registryRevision"} {
		t.Run(field, func(t *testing.T) {
			var body map[string]any
			if err := json.Unmarshal(raw, &body); err != nil {
				t.Fatal(err)
			}
			if strings.HasSuffix(field, "Id") {
				body[field] = uuid.NewString()
			} else {
				body[field] = 2
			}
			changed, err := json.Marshal(body)
			if err != nil {
				t.Fatal(err)
			}
			job, err := printqueue.DecodeFrozenJob(changed)
			if err != nil {
				t.Fatal(err)
			}
			copy := proto.Clone(r).(*pb.PrinterAgentSubmitLocalRequest)
			copy.FrozenEnvelope = changed
			copy.EnvelopeSha256 = job.Digest()
			_, err = client.SubmitLocal(ctx, copy)
			requireCode(t, codes.PermissionDenied, err)
		})
	}
}

func TestFreshMutualTLSClientScopePinRevocationAndProtocol(t *testing.T) {
	f := newFixture(t, t.TempDir())
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	address := serve(t, s)
	client, _ := connect(t, address, f, f.client)
	for name, mutate := range map[string]func(*pb.PrinterAgentAuth){"wrongHost": func(a *pb.PrinterAgentAuth) { a.HostId = uuid.NewString() }, "foreignClient": func(a *pb.PrinterAgentAuth) { a.ClientId = uuid.NewString() }, "oldVersion": func(a *pb.PrinterAgentAuth) { a.ProtocolMinor = 1 }, "oldReader": func(a *pb.PrinterAgentAuth) { a.ReaderVersion = 1 }, "unknownCap": func(a *pb.PrinterAgentAuth) { a.RequiredCapabilities = []string{"printer.agent.enable"} }, "unknownNestedWire": func(a *pb.PrinterAgentAuth) { a.ProtoReflect().SetUnknown([]byte{0xf8, 7, 1}) }} {
		t.Run(name, func(t *testing.T) {
			a := f.auth()
			mutate(a)
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			_, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: a})
			if err == nil {
				t.Fatal("invalid auth admitted")
			}
		})
	}
	for _, kind := range []string{"wrongCA", "reissuedUnpinned", "wrongHost", "duplicatePurpose", "extraDNS", "encodedURI", "wrongEKU"} {
		t.Run(kind, func(t *testing.T) {
			ca := f.ca
			tmpl := template(x509.ExtKeyUsageClientAuth)
			u, _ := ClientURI(f.config.Pins.HostID, f.clientID)
			tmpl.URIs = []*url.URL{u}
			switch kind {
			case "wrongCA":
				ca = newCA(t)
			case "wrongHost":
				u.Host = "other-printer-purpose"
			case "duplicatePurpose":
				tmpl.URIs = append(tmpl.URIs, u)
			case "extraDNS":
				tmpl.DNSNames = []string{"extra.local"}
			case "encodedURI":
				u.RawPath = "/" + f.config.Pins.HostID + "/%" + "30" + f.clientID[1:]
			case "wrongEKU":
				tmpl.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}
			}
			pair, _, _ := issue(t, ca, tmpl)
			bad, _ := connect(t, address, f, pair)
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			_, err := bad.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()})
			if err == nil {
				t.Fatal("certificate purpose/pin bypass")
			}
		})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if _, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()}); err != nil {
		t.Fatal(err)
	}
	s.RevokeClient(f.clientID)
	_, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()})
	requireCode(t, codes.Unauthenticated, err)
}

type healthFunc func(context.Context) (printhost.Health, error)

func (f healthFunc) Health(ctx context.Context) (printhost.Health, error) { return f(ctx) }

type candidateFunc func(context.Context, ClientObservation, printhost.Pins, printqueue.FrozenJob) error

func (f candidateFunc) Validate(ctx context.Context, peer ClientObservation, pins printhost.Pins, job printqueue.FrozenJob) error {
	return f(ctx, peer, pins, job)
}

func TestCandidateReceivesFreshCopiedDERAndNeverAdmits(t *testing.T) {
	f := newFixture(t, t.TempDir())
	raw := f.envelope(t)
	job, err := printqueue.DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int64
	f.config.Candidate = candidateFunc(func(_ context.Context, p ClientObservation, pins printhost.Pins, j printqueue.FrozenJob) error {
		if p.ClientID != f.clientID || string(p.CertificateDER) != string(f.client.Certificate[0]) || pins != f.config.Pins || string(j.Raw()) != string(raw) {
			t.Error("candidate did not receive authenticated frozen inputs")
		}
		p.CertificateDER[0] = 0 // Only this detached observation may change.
		if calls.Add(1) == 2 {
			return errors.New("synthetic current registration revoked")
		}
		return nil
	})
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	client, _ := connect(t, serve(t, s), f, f.client)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	r := &pb.PrinterAgentSubmitLocalRequest{Auth: f.auth(), RequestId: job.RequestID, JobId: job.JobID, FrozenEnvelope: raw, EnvelopeSha256: job.Digest()}
	for i := 0; i < 2; i++ {
		result, err := client.SubmitLocal(ctx, r)
		requireCode(t, codes.FailedPrecondition, err)
		if result != nil || !strings.Contains(err.Error(), "HELD_PROVISIONING") {
			t.Fatal("candidate validation activated admission", result, err)
		}
	}
	if calls.Load() != 2 {
		t.Fatal("current registration validation cached", calls.Load())
	}
	if _, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()}); err != nil {
		t.Fatal("validator mutated original TLS certificate", err)
	}
	var count int
	if err = f.store.DB.QueryRow("SELECT count(*) FROM pq_job").Scan(&count); err != nil || count != 0 {
		t.Fatal("candidate created job", count, err)
	}
}

func TestLostHealthACKReconnectHasNoAdmissionOrOptimisticReceipt(t *testing.T) {
	f := newFixture(t, t.TempDir())
	entered, release := make(chan struct{}), make(chan struct{})
	var once atomic.Bool
	f.config.Health = healthFunc(func(ctx context.Context) (printhost.Health, error) {
		h, err := f.host.Health(ctx)
		if once.CompareAndSwap(false, true) {
			close(entered)
			<-release
		}
		return h, err
	})
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	address := serve(t, s)
	first, connection := connect(t, address, f, f.client)
	done := make(chan error, 1)
	go func() {
		_, err := first.Health(context.Background(), &pb.PrinterAgentHealthRequest{Auth: f.auth()})
		done <- err
	}()
	<-entered
	if err := connection.Close(); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err == nil {
		t.Fatal("lost ACK fabricated healthy response")
	}
	close(release)
	second, _ := connect(t, address, f, f.client)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	h, err := second.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()})
	if err != nil {
		t.Fatal(err)
	}
	if !h.SoftwareReady || h.AdmissionState != pb.PrinterAgentAdmissionState_PRINTER_AGENT_ADMISSION_HELD_PROVISIONING || h.PhysicalState != pb.PrinterAgentPhysicalState_PRINTER_AGENT_PHYSICAL_HELD {
		t.Fatal("reconnect changed held truth")
	}
	var count int
	if err = f.store.DB.QueryRow("SELECT count(*) FROM pq_receipt").Scan(&count); err != nil || count != 0 {
		t.Fatal("health created receipt", count, err)
	}
}
func TestStopTimeoutRetainsActualHealthHandlerAndFencesNewRPC(t *testing.T) {
	f := newFixture(t, t.TempDir())
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	f.config.Health = healthFunc(func(ctx context.Context) (printhost.Health, error) {
		h, err := f.host.Health(ctx)
		once.Do(func() { close(entered); <-release })
		return h, err
	})
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	client, _ := connect(t, serve(t, s), f, f.client)
	done := make(chan error, 1)
	go func() {
		_, err := client.Health(context.Background(), &pb.PrinterAgentHealthRequest{Auth: f.auth()})
		done <- err
	}()
	<-entered
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := s.Stop(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("active handler was released", err)
	}
	select {
	case <-s.stopDone:
		t.Fatal("graceful lifetime abandoned")
	default:
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if err := s.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestConstructorPreflightAndChangedHealthFailClosed(t *testing.T) {
	f := newFixture(t, t.TempDir())
	for _, kind := range []string{"wrongServerName", "extraServerURI", "wrongEKU", "expired", "notYetValid"} {
		t.Run(kind, func(t *testing.T) {
			tmpl := template(x509.ExtKeyUsageServerAuth)
			tmpl.DNSNames = []string{ServerName}
			switch kind {
			case "wrongServerName":
				tmpl.DNSNames = []string{"wrong.local"}
			case "extraServerURI":
				u, _ := ClientURI(f.config.Pins.HostID, f.clientID)
				tmpl.URIs = []*url.URL{u}
			case "wrongEKU":
				tmpl.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
			case "expired":
				tmpl.NotBefore = time.Now().Add(-2 * time.Hour)
				tmpl.NotAfter = time.Now().Add(-time.Hour)
			case "notYetValid":
				tmpl.NotBefore = time.Now().Add(time.Hour)
				tmpl.NotAfter = time.Now().Add(2 * time.Hour)
			}
			pair, _, _ := issue(t, f.ca, tmpl)
			c := f.config
			c.Certificate = pair
			if _, err := NewServer(c); err == nil {
				t.Fatal("bad server pin accepted")
			}
		})
	}
	f.config.Health = healthFunc(func(ctx context.Context) (printhost.Health, error) {
		h, err := f.host.Health(ctx)
		h.Pins.RouteRevision++
		return h, err
	})
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	client, _ := connect(t, serve(t, s), f, f.client)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()})
	requireCode(t, codes.FailedPrecondition, err)
}

func TestEstablishedChannelServerExpiryAndTypedNilHealthSource(t *testing.T) {
	f := newFixture(t, t.TempDir())
	var nilHealth healthFunc
	bad := f.config
	bad.Health = nilHealth
	if _, err := NewServer(bad); err == nil {
		t.Fatal("typed nil health source admitted")
	}
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	var clock atomic.Int64
	clock.Store(time.Now().UnixNano())
	s.now = func() time.Time { return time.Unix(0, clock.Load()) }
	client, _ := connect(t, serve(t, s), f, f.client)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if _, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()}); err != nil {
		t.Fatal(err)
	}
	clock.Store(s.serverNotAfter.UnixNano())
	_, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: f.auth()})
	requireCode(t, codes.Unauthenticated, err)
	if !strings.Contains(err.Error(), "server pin no longer valid") {
		t.Fatal("server validity not checked on established channel", err)
	}
}

// Actual child process for Dart/runtime/widget integration; no installed
// service, live certificate or physical sender is involved.
func TestPrinterAgentProcess(t *testing.T) {
	dir := os.Getenv("VYNIC_PRINTER_AGENT_FIXTURE_DIR")
	if dir == "" {
		t.Skip("isolated fixture process only")
	}
	f := newFixture(t, dir)
	s, err := NewServer(f.config)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- s.Serve(context.Background(), listener) }()
	for name, raw := range map[string][]byte{"server.pem": f.serverPEM, "client.pem": f.clientPEM, "client.key": f.clientKey} {
		if err := os.WriteFile(filepath.Join(dir, name), raw, 0600); err != nil {
			t.Fatal(err)
		}
	}
	serverHash := sha256.Sum256(f.config.Certificate.Certificate[0])
	clientHash := sha256.Sum256(f.client.Certificate[0])
	profile := map[string]any{"version": 1, "provisionStatus": "HELD_PROVISIONING", "listenAddress": listener.Addr().String(), "clientId": f.clientID, "currentDeviceInstallationId": f.deviceInstallationID, "pins": f.config.Pins, "serverCertificatePath": filepath.Join(dir, "server.pem"), "serverCertificateSha256": hex.EncodeToString(serverHash[:]), "clientCertificatePath": filepath.Join(dir, "client.pem"), "clientPrivateKeyPath": filepath.Join(dir, "client.key"), "clientCertificateSha256": hex.EncodeToString(clientHash[:])}
	raw, err := json.Marshal(profile)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(dir, "profile.json"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	raw = f.envelope(t)
	if err = os.WriteFile(filepath.Join(dir, "envelope.json"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(dir, "ready"), []byte(listener.Addr().String()), 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(time.Minute)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(filepath.Join(dir, "stop")); err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err = s.Stop(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-done; err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"pq_job", "pq_receipt", "pq_claim", "pq_attempt", "pq_beep"} {
		var count int
		if err := f.store.DB.QueryRow("SELECT count(*) FROM " + table).Scan(&count); err != nil || count != 0 {
			t.Fatal("held wire admitted or dispatched", table, count, err)
		}
	}
}
