package server_test

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/server"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

const wireFixtureEpoch uint64 = 41

type proofFixtureCredential struct {
	TerminalID  string `json:"terminalId"`
	Secret      string `json:"terminalSecret"`
	Origin      string `json:"originInstallationId"`
	Certificate []byte `json:"certificate"`
	Key         []byte `json:"key"`
}
type proofWireFixture struct {
	VenueID           string                   `json:"venueId"`
	InstallationID    string                   `json:"installationId"`
	GrantFingerprint  string                   `json:"grantFingerprint"`
	Epoch             uint64                   `json:"epoch"`
	ServerCertificate []byte                   `json:"serverCertificate"`
	ClientCA          []byte                   `json:"clientCa"`
	Clients           []proofFixtureCredential `json:"clients"`
	Registries        []printqueue.Registry    `json:"registries"`
	ControlID         string                   `json:"controlId"`
	TableID           string                   `json:"tableId"`
	LostRequestID     string                   `json:"lostRequestId"`
}
type proofFixtureCommand struct {
	Mode         string `json:"mode"`
	Address      string `json:"address"`
	Client       int    `json:"client"`
	Request      []byte `json:"request"`
	Gate         string `json:"gate"`
	ExpectedCode string `json:"expectedCode"`
}
type proofFixtureOutput struct {
	PID         int    `json:"pid"`
	Code        string `json:"code"`
	Result      []byte `json:"result"`
	FrameSHA256 string `json:"frameSha256"`
}

// Only the synthetic fixture credential file contains keys. This durable client
// frame contains no credential: the generator-produced pending message has Auth
// cleared and is fsynced before a transport call. Whole replay events retain the
// frozen effects and queue receipts before the exact own ACK is settled.
type proofProcessFrame struct {
	VenueID, InstallationID, TerminalID, Origin, GrantFingerprint string
	Epoch, Cursor                                                 uint64
	Pending                                                       []byte
	Events                                                        [][]byte
	LastResult                                                    []byte
}

func proofFixtureWrite(t *testing.T, path string, body any) {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(path+".new", os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.Write(raw); err != nil {
		t.Fatal(err)
	}
	if err = f.Sync(); err != nil {
		t.Fatal(err)
	}
	if err = f.Close(); err != nil {
		t.Fatal(err)
	}
	if err = os.Rename(path+".new", path); err != nil {
		t.Fatal(err)
	}
}
func proofFixtureRead(t *testing.T, path string, body any) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, body); err != nil {
		t.Fatal(err)
	}
}
func proofMarshal(t *testing.T, m proto.Message) []byte {
	t.Helper()
	raw, err := (proto.MarshalOptions{Deterministic: true}).Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}
func proofSigned(t *testing.T, body any, key ed25519.PrivateKey) (string, []byte) {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	payload := base64.RawURLEncoding.EncodeToString(raw)
	der, err := x509.MarshalPKIXPublicKey(key.Public())
	if err != nil {
		t.Fatal(err)
	}
	return payload + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(key, []byte(payload))), pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})
}
func proofCA(t *testing.T) (*x509.Certificate, *ecdsa.PrivateKey, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	cert := &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: "temporary isolated proof CA"}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), BasicConstraintsValid: true, IsCA: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature}
	der, err := x509.CreateCertificate(rand.Reader, cert, cert, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, err = x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return cert, key, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
}
func proofClientCertificate(t *testing.T, ca *x509.Certificate, signer *ecdsa.PrivateKey, uris []*url.URL) ([]byte, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	cert := &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}, URIs: uris, BasicConstraintsValid: true}
	der, err := x509.CreateCertificate(rand.Reader, cert, ca, &key.PublicKey, signer)
	if err != nil {
		t.Fatal(err)
	}
	private, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: private})
}

func newProofWireFixture(t *testing.T, dir string) proofWireFixture {
	t.Helper()
	ctx := context.Background()
	s, id := testutil.Bound(t, filepath.Join(dir, "gateway"))
	defer s.Close()
	_, issuer, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().Unix()
	g := store.OperationalProofGrant{Version: 1, Purpose: store.OperationalProofPurpose, Mode: store.OperationalProofMode, GrantID: uuid.NewString(), InstallationID: id.InstallationID, VenueID: id.VenueID, PublicKey: id.PublicKey, AuthorityEpoch: wireFixtureEpoch, IssuedAt: now, ExpiresAt: now + 600}
	raw, trust := proofSigned(t, g, issuer)
	if err = s.PinOperationalProofAuthority(ctx, raw, trust); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256([]byte(raw))
	ca, caKey, caPEM := proofCA(t)
	caDigest := sha256.Sum256(ca.Raw)
	f := proofWireFixture{VenueID: id.VenueID, InstallationID: id.InstallationID, GrantFingerprint: hex.EncodeToString(digest[:]), Epoch: wireFixtureEpoch, ServerCertificate: id.Certificate, ClientCA: caPEM, ControlID: uuid.NewString(), TableID: uuid.NewString(), LostRequestID: uuid.NewString()}
	for i := 0; i < 3; i++ {
		c := proofFixtureCredential{TerminalID: uuid.NewString(), Secret: store.Secret(), Origin: uuid.NewString()}
		ticket, err := s.IssueTicket()
		if err != nil {
			t.Fatal(err)
		}
		if err = s.Pair(ctx, ticket, uuid.NewString(), c.TerminalID, c.Secret, fmt.Sprintf("isolated POS %d", i+1)); err != nil {
			t.Fatal(err)
		}
		u, err := server.OperationalProofOriginURI(id.VenueID, id.InstallationID, c.TerminalID, c.Origin)
		if err != nil {
			t.Fatal(err)
		}
		c.Certificate, c.Key = proofClientCertificate(t, ca, caKey, []*url.URL{u})
		origin := store.OperationalProofOriginGrant{Version: 1, Purpose: store.OperationalProofOriginPurpose, Mode: store.OperationalProofMode, GrantID: uuid.NewString(), VenueID: id.VenueID, InstallationID: id.InstallationID, TerminalID: c.TerminalID, OriginInstallationID: c.Origin, AuthorityEpoch: wireFixtureEpoch, ClientCASHA256: hex.EncodeToString(caDigest[:]), AuthorityGrantSHA256: f.GrantFingerprint, IssuedAt: now, ExpiresAt: now + 600}
		raw, _ := proofSigned(t, origin, issuer)
		if err = s.BindOperationalProofOrigin(ctx, store.OperationalAuth{TerminalID: c.TerminalID, TerminalSecret: c.Secret}, raw, trust); err != nil {
			t.Fatal(err)
		}
		f.Clients = append(f.Clients, c)
	}
	// Reissued certificate with a different origin, wrong CA, duplicate SAN,
	// noncanonical URI, foreign Venue and old base-purpose certificate.
	first := f.Clients[0]
	for _, name := range []string{"changed-origin", "wrong-ca", "duplicate-uri", "encoded-uri", "foreign-venue", "base"} {
		c := first
		var uri *url.URL
		var uris []*url.URL
		issuerCA, issuerKey := ca, caKey
		switch name {
		case "changed-origin":
			uri, _ = server.OperationalProofOriginURI(f.VenueID, f.InstallationID, c.TerminalID, uuid.NewString())
		case "wrong-ca":
			issuerCA, issuerKey, _ = proofCA(t)
			uri, _ = server.OperationalProofOriginURI(f.VenueID, f.InstallationID, c.TerminalID, c.Origin)
		case "duplicate-uri":
			uri, _ = server.OperationalProofOriginURI(f.VenueID, f.InstallationID, c.TerminalID, c.Origin)
			uris = []*url.URL{uri, uri}
		case "encoded-uri":
			uri, _ = server.OperationalProofOriginURI(f.VenueID, f.InstallationID, c.TerminalID, c.Origin)
			uri.RawPath = "/%" + fmt.Sprintf("%02x", f.VenueID[0]) + f.VenueID[1:] + "/" + f.InstallationID + "/" + c.TerminalID + "/" + c.Origin
		case "foreign-venue":
			uri, _ = server.OperationalProofOriginURI(uuid.NewString(), f.InstallationID, c.TerminalID, c.Origin)
		case "base":
			uri, _ = server.OperationalProofTerminalURI(f.VenueID, f.InstallationID, c.TerminalID)
			c.Origin = ""
		}
		if uris == nil {
			uris = []*url.URL{uri}
		}
		c.Certificate, c.Key = proofClientCertificate(t, issuerCA, issuerKey, uris)
		f.Clients = append(f.Clients, c)
	}
	device, worker := uuid.NewString(), uuid.NewString()
	q, err := printqueue.NewProofStore(ctx, s.DB, printqueue.GatewayIdentity{VenueID: f.VenueID, InstallationID: f.InstallationID, DeviceID: device, WorkerHostID: worker, Epoch: f.Epoch})
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		physical := uuid.NewString()
		r := printqueue.Registry{PhysicalPrinterID: physical, VenueID: f.VenueID, InstallationID: f.InstallationID, DeviceID: device, WorkerHostID: worker, AuthorityEpoch: f.Epoch, BindingRevision: 1, ConfigRevision: 1, RegistryRevision: 1, Aliases: []string{uuid.NewString(), uuid.NewString()}, Destination: printtransport.Destination{PhysicalPrinterID: physical, WorkerHostID: worker, Transport: printtransport.TCP, Host: fmt.Sprintf("192.168.50.%d", 10+i), Port: 9100}}
		if err = q.Register(ctx, r); err != nil {
			t.Fatal(err)
		}
		f.Registries = append(f.Registries, r)
	}
	proofFixtureWrite(t, filepath.Join(dir, "fixture.json"), f)
	return f
}
func (f proofWireFixture) auth(index int) *pb.AuthenticatedRequest {
	c := f.Clients[index]
	caps := []string{server.OperationalProofCapability}
	if c.Origin != "" {
		caps = append(caps, server.OperationalProofQueueCapability)
	}
	return &pb.AuthenticatedRequest{TerminalId: c.TerminalID, TerminalSecret: c.Secret, Scope: &pb.Scope{VenueId: f.VenueID, InstallationId: f.InstallationID, Protocol: &pb.Protocol{Major: 1, Minor: 3, RequiredCapabilities: caps}}}
}
func (f proofWireFixture) job(t *testing.T, client, printer, alias int, request string) *pb.ProofEffect {
	t.Helper()
	r, c := f.Registries[printer], f.Clients[client]
	d := r.Destination
	d.DocumentName = "frozen synthetic Georgian raster + cut"
	primary := []byte{0x1b, 0x40, 0xff, 0, 0x1d, 0x56, 0}
	hash := sha256.Sum256(primary)
	j := printqueue.FrozenJob{Version: 1, JobID: uuid.NewString(), EffectID: uuid.NewString(), RequestID: request, TerminalID: c.TerminalID, VenueID: f.VenueID, InstallationID: f.InstallationID, OriginInstallationID: c.Origin, DeviceID: r.DeviceID, PhysicalPrinterID: r.PhysicalPrinterID, AliasID: r.Aliases[alias], AttemptID: uuid.NewString(), BeepAttemptID: uuid.NewString(), AuthorityEpoch: f.Epoch, RouteRevision: 1, ConfigRevision: 1, BindingRevision: 1, RegistryRevision: 1, Destination: d, CapabilityProfile: json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"partial","encoding":"georgianViaRaster","beep":{"capability":"epsonEscA97Pattern","enabled":false}}`), PrimaryBytes: primary, PrimarySHA256: hex.EncodeToString(hash[:])}
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = printqueue.DecodeFrozenJob(raw); err != nil {
		t.Fatal(err)
	}
	return &pb.ProofEffect{Id: j.EffectID, Kind: pb.ProofEffect_PRINT, Payload: raw}
}
func (f proofWireFixture) request(t *testing.T, client int, revision uint64, requestID string) *pb.ProofCommitRequest {
	t.Helper()
	if requestID == "" {
		requestID = uuid.NewString()
	}
	r := &pb.ProofCommitRequest{RequestId: requestID, AuthorityEpoch: f.Epoch, PrintAdmission: store.OperationalPrintAdmission, OriginInstallationId: f.Clients[client].Origin, Reads: []*pb.ProofRead{{Kind: pb.ProofEntity_OPERATIONAL_CONTROL, Id: f.ControlID, ExpectedRevision: revision}}, Writes: []*pb.ProofWrite{{Kind: pb.ProofEntity_OPERATIONAL_CONTROL, Id: f.ControlID, ExpectedRevision: revision, Document: []byte(fmt.Sprintf(`{"lastOrderId":%d}`, revision+1))}, {Kind: pb.ProofEntity_TABLE, Id: f.TableID, ExpectedRevision: revision, Document: []byte(`{"synthetic":true}`)}}}
	r.Effects = []*pb.ProofEffect{f.job(t, client, 0, client%2, requestID)}
	return r
}

type proofLossServer struct {
	*server.OperationalProofServer
	lost       string
	lostMarker string
	once       sync.Once
}

func (s *proofLossServer) Commit(ctx context.Context, r *pb.ProofCommitRequest) (*pb.ProofCommitResult, error) {
	result, err := s.OperationalProofServer.Commit(ctx, r)
	if err != nil {
		return nil, err
	}
	lose := false
	if r.RequestId == s.lost {
		s.once.Do(func() {
			// The synthetic fault is spent across gateway restart too. This is
			// fixture fault injection only; durable business truth is in SQLite.
			file, err := os.OpenFile(s.lostMarker, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			if err == nil {
				err = file.Sync()
				err = errors.Join(err, file.Close())
				lose = err == nil
			}
		})
	}
	if lose {
		return nil, status.Error(codes.Unavailable, "synthetic network ACK lost after durable COMMIT")
	}
	return result, nil
}

func proofGatewayProcess(t *testing.T, dir string, f proofWireFixture) {
	t.Helper()
	s, err := store.Open(filepath.Join(dir, "gateway"), false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	proof, err := server.NewQueuedOperationalProof(context.Background(), s, f.ClientCA)
	if err != nil {
		t.Fatal(err)
	}
	id, err := s.Identity()
	if err != nil {
		t.Fatal(err)
	}
	cert, err := tls.X509KeyPair(id.Certificate, id.TLSKey)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(f.ClientCA) {
		t.Fatal("fixture CA")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	g := grpc.NewServer(grpc.Creds(credentials.NewTLS(&tls.Config{Certificates: []tls.Certificate{cert}, ClientCAs: roots, ClientAuth: tls.RequireAndVerifyClientCert, MinVersion: tls.VersionTLS13})), grpc.MaxRecvMsgSize(store.OperationalMaxRequestBytes+(64<<10)), grpc.MaxSendMsgSize(store.OperationalMaxResultBytes+(1<<20)))
	pb.RegisterOperationalProofServer(g, &proofLossServer{OperationalProofServer: proof, lost: f.LostRequestID, lostMarker: filepath.Join(dir, "lost-ack-spent")})
	done := make(chan error, 1)
	go func() { done <- g.Serve(listener) }()
	proofFixtureWrite(t, filepath.Join(dir, "gateway-ready.json"), map[string]any{"address": listener.Addr().String(), "pid": os.Getpid()})
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	deadline := time.NewTimer(60 * time.Second)
	defer deadline.Stop()
	for {
		select {
		case err := <-done:
			if err != nil {
				t.Fatal(err)
			}
			return
		case <-deadline.C:
			g.Stop()
			t.Fatal("fixture stop timeout")
		case <-ticker.C:
			if _, err := os.Stat(filepath.Join(dir, "gateway-stop")); err == nil {
				g.GracefulStop()
				if err := <-done; err != nil {
					t.Fatal(err)
				}
				return
			}
		}
	}
}
func proofProcessConnect(t *testing.T, f proofWireFixture, c proofFixtureCommand) (pb.OperationalProofClient, *grpc.ClientConn) {
	t.Helper()
	credential := f.Clients[c.Client]
	cert, err := tls.X509KeyPair(credential.Certificate, credential.Key)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(f.ServerCertificate) {
		t.Fatal("fixture server pin")
	}
	conn, err := grpc.NewClient(c.Address, grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{RootCAs: roots, ServerName: "vynic-edge.local", Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13})), grpc.WithDefaultCallOptions(grpc.MaxCallRecvMsgSize(store.OperationalMaxResultBytes+(1<<20)), grpc.MaxCallSendMsgSize(store.OperationalMaxRequestBytes+(64<<10))))
	if err != nil {
		t.Fatal(err)
	}
	return pb.NewOperationalProofClient(conn), conn
}
func proofClientProcess(t *testing.T, dir string, f proofWireFixture, c proofFixtureCommand, outputPath string) {
	t.Helper()
	client, connection := proofProcessConnect(t, f, c)
	defer connection.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out := proofFixtureOutput{PID: os.Getpid()}
	framePath := filepath.Join(dir, fmt.Sprintf("client-%d.frame.json", c.Client))
	var frame proofProcessFrame
	credential := f.Clients[c.Client]
	if _, err := os.Stat(framePath); err == nil {
		proofFixtureRead(t, framePath, &frame)
	} else {
		frame = proofProcessFrame{VenueID: f.VenueID, InstallationID: f.InstallationID, TerminalID: credential.TerminalID, Origin: credential.Origin, GrantFingerprint: f.GrantFingerprint, Epoch: f.Epoch}
	}
	if frame.VenueID != f.VenueID || frame.InstallationID != f.InstallationID || frame.TerminalID != credential.TerminalID || frame.Origin != credential.Origin || frame.GrantFingerprint != f.GrantFingerprint || frame.Epoch != f.Epoch {
		t.Fatal("immutable client binding")
	}
	r := new(pb.ProofCommitRequest)
	if len(c.Request) > 0 {
		if err := proto.Unmarshal(c.Request, r); err != nil {
			t.Fatal(err)
		}
	}
	var result *pb.ProofCommitResult
	var err error
	if c.Mode == "probe" {
		if r.Auth == nil {
			r.Auth = f.auth(c.Client)
		}
		result, err = client.Commit(ctx, r)
	} else if c.Mode == "status" {
		_, err = client.Status(ctx, f.auth(c.Client))
	} else if c.Mode == "get" {
		result, err = client.GetResult(ctx, &pb.ProofResultRequest{Auth: f.auth(c.Client), AuthorityEpoch: f.Epoch, RequestId: r.RequestId})
	} else {
		if _, err = client.Status(ctx, f.auth(c.Client)); err != nil {
			t.Fatal(err)
		}
		if c.Mode == "commit" {
			r.Auth = nil
			pending := proofMarshal(t, r)
			if len(frame.Pending) != 0 && !bytes.Equal(frame.Pending, pending) {
				t.Fatal("one immutable pending request")
			}
			frame.Pending = pending
			proofFixtureWrite(t, framePath, frame)
			proofFixtureWrite(t, outputPath+".prepared", map[string]any{"pid": os.Getpid(), "pendingSha256": fmt.Sprintf("%x", sha256.Sum256(frame.Pending))})
			if c.Gate != "" {
				for {
					if _, err := os.Stat(c.Gate); err == nil {
						break
					}
					select {
					case <-ctx.Done():
						t.Fatal("gate timeout")
					case <-time.After(5 * time.Millisecond):
					}
				}
			}
			r.Auth = f.auth(c.Client)
			result, err = client.Commit(ctx, r)
		} else if c.Mode == "resolve" {
			if len(frame.Pending) == 0 {
				t.Fatal("lost ACK pending absent")
			}
			if err = proto.Unmarshal(frame.Pending, r); err != nil {
				t.Fatal(err)
			}
			result, err = client.GetResult(ctx, &pb.ProofResultRequest{Auth: f.auth(c.Client), AuthorityEpoch: f.Epoch, RequestId: r.RequestId})
		} else if c.Mode == "retry" {
			r.Auth = f.auth(c.Client)
			result, err = client.Commit(ctx, r)
		} else {
			t.Fatal("fixture command", c.Mode)
		}
		if err == nil {
			if result.Mode != store.OperationalProofMode || result.RequestId != r.RequestId || result.TerminalId != credential.TerminalID || result.AuthorityEpoch != f.Epoch || result.PrintAdmission != r.PrintAdmission || result.OriginInstallationId != r.OriginInstallationId {
				t.Fatal("result identity changed")
			}
			if c.Mode == "retry" {
				if !bytes.Equal(frame.LastResult, proofMarshal(t, result)) {
					t.Fatal("exact ACK retry changed")
				}
			} else {
				var observed *pb.ProofEvent
				for frame.Cursor < result.HeadSequence {
					page, e := client.Replay(ctx, &pb.ProofReplayRequest{Auth: f.auth(c.Client), AuthorityEpoch: f.Epoch, AfterSequence: frame.Cursor, Limit: 100})
					if e != nil {
						t.Fatal(e)
					}
					if page.AfterSequence != frame.Cursor || len(page.Events) == 0 || page.HeadSequence < result.HeadSequence {
						t.Fatal("replay gap")
					}
					for _, event := range page.Events {
						if event.Sequence > result.HeadSequence {
							break
						}
						if event.Sequence != frame.Cursor+1 || event.AuthorityEpoch != f.Epoch {
							t.Fatal("noncontiguous event")
						}
						frame.Events = append(frame.Events, proofMarshal(t, event))
						frame.Cursor = event.Sequence
						if event.RequestId == r.RequestId {
							observed = event
						}
						proofFixtureWrite(t, framePath, frame)
					}
				}
				if result.Outcome == pb.ProofCommitResult_COMMITTED {
					if observed == nil || !proto.Equal(observed, result.Event) {
						t.Fatal("ACK missing exact replayed own event")
					}
					if len(result.Event.PrintReceipts) != len(r.Effects) {
						t.Fatal("queued effect receipts incomplete")
					}
				} else if result.Outcome != pb.ProofCommitResult_CONFLICT || result.Event != nil {
					t.Fatal("canonical conflict")
				}
				frame.LastResult = proofMarshal(t, result)
				frame.Pending = nil
				proofFixtureWrite(t, framePath, frame)
			}
		}
	}
	out.Code = status.Code(err).String()
	if c.ExpectedCode != "" && out.Code != c.ExpectedCode {
		t.Fatalf("expected %s, got %s (%v)", c.ExpectedCode, out.Code, err)
	}
	if result != nil {
		out.Result = proofMarshal(t, result)
	}
	if raw, e := os.ReadFile(framePath); e == nil {
		out.FrameSHA256 = fmt.Sprintf("%x", sha256.Sum256(raw))
	}
	proofFixtureWrite(t, outputPath, out)
}

// These child tests run as independent OS processes. The entrypoint is test-only:
// there is no command/service startup, enrollment RPC or physical dispatch API.
func TestOperationalProofProcess(t *testing.T) {
	dir := os.Getenv("VYNIC_OPERATIONAL_WIRE_DIR")
	role := os.Getenv("VYNIC_OPERATIONAL_WIRE_ROLE")
	if dir == "" || role == "" {
		t.Skip("isolated child process only")
	}
	var f proofWireFixture
	if role == "dart-gateway" {
		f = newProofWireFixture(t, dir)
	} else {
		proofFixtureRead(t, filepath.Join(dir, "fixture.json"), &f)
	}
	if role == "gateway" || role == "dart-gateway" {
		proofGatewayProcess(t, dir, f)
		return
	}
	var c proofFixtureCommand
	path := os.Getenv("VYNIC_OPERATIONAL_WIRE_COMMAND")
	proofFixtureRead(t, path, &c)
	proofClientProcess(t, dir, f, c, path+".out")
}

type proofChild struct {
	command *exec.Cmd
	log     *bytes.Buffer
	done    chan error
}

func proofStartChild(t *testing.T, dir, role, path string) *proofChild {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^TestOperationalProofProcess$", "-test.v")
	cmd.Env = append(os.Environ(), "VYNIC_OPERATIONAL_WIRE_DIR="+dir, "VYNIC_OPERATIONAL_WIRE_ROLE="+role, "VYNIC_OPERATIONAL_WIRE_COMMAND="+path)
	log := new(bytes.Buffer)
	cmd.Stdout = log
	cmd.Stderr = log
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	child := &proofChild{command: cmd, log: log, done: make(chan error, 1)}
	go func() { child.done <- cmd.Wait() }()
	t.Cleanup(func() { cmd.Process.Kill() })
	return child
}
func proofChildWait(t *testing.T, c *proofChild) {
	t.Helper()
	select {
	case err := <-c.done:
		if err != nil {
			t.Fatalf("child process failed: %v\n%s", err, c.log)
		}
	case <-time.After(15 * time.Second):
		c.command.Process.Kill()
		t.Fatal("child timeout")
	}
}
func proofWaitFile(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path); err == nil {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("fixture file timeout", filepath.Base(path))
}
func proofStartGateway(t *testing.T, dir string) (*proofChild, string, int) {
	t.Helper()
	os.Remove(filepath.Join(dir, "gateway-stop"))
	os.Remove(filepath.Join(dir, "gateway-ready.json"))
	child := proofStartChild(t, dir, "gateway", "")
	proofWaitFile(t, filepath.Join(dir, "gateway-ready.json"))
	var ready struct {
		Address string
		PID     int
	}
	proofFixtureRead(t, filepath.Join(dir, "gateway-ready.json"), &ready)
	return child, ready.Address, ready.PID
}
func proofStopGateway(t *testing.T, dir string, c *proofChild) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, "gateway-stop"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	proofChildWait(t, c)
}
func proofRunCommand(t *testing.T, dir string, c proofFixtureCommand) proofFixtureOutput {
	t.Helper()
	path := filepath.Join(dir, "command-"+uuid.NewString()+".json")
	proofFixtureWrite(t, path, c)
	child := proofStartChild(t, dir, "client", path)
	proofChildWait(t, child)
	var out proofFixtureOutput
	proofFixtureRead(t, path+".out", &out)
	return out
}

func TestOperationalProofThreeProcessesGatewayAtomicRaceLostACKAndRestart(t *testing.T) {
	dir := t.TempDir()
	f := newProofWireFixture(t, dir)
	gateway, address, gatewayPID := proofStartGateway(t, dir)
	gate := filepath.Join(dir, "release-race")
	children := make([]*proofChild, 3)
	paths := make([]string, 3)
	requests := make([]*pb.ProofCommitRequest, 3)
	for i := range children {
		requests[i] = f.request(t, i, 0, "")
		paths[i] = filepath.Join(dir, "race-"+strconv.Itoa(i)+".json")
		proofFixtureWrite(t, paths[i], proofFixtureCommand{Mode: "commit", Client: i, Address: address, Request: proofMarshal(t, requests[i]), Gate: gate, ExpectedCode: "OK"})
		children[i] = proofStartChild(t, dir, "client", paths[i])
	}
	for _, path := range paths {
		proofWaitFile(t, path+".out.prepared")
	}
	if err := os.WriteFile(gate, nil, 0600); err != nil {
		t.Fatal(err)
	}
	pids := map[int]bool{gatewayPID: true}
	committed, conflicts := 0, 0
	for i, child := range children {
		proofChildWait(t, child)
		var out proofFixtureOutput
		proofFixtureRead(t, paths[i]+".out", &out)
		if pids[out.PID] {
			t.Fatal("process instances not independent")
		}
		pids[out.PID] = true
		result := new(pb.ProofCommitResult)
		if err := proto.Unmarshal(out.Result, result); err != nil {
			t.Fatal(err)
		}
		if result.Outcome == pb.ProofCommitResult_COMMITTED {
			committed++
		} else if result.Outcome == pb.ProofCommitResult_CONFLICT {
			conflicts++
		} else {
			t.Fatal(result.Outcome)
		}
	}
	if committed != 1 || conflicts != 2 || len(pids) != 4 {
		t.Fatal("one canonical control/table contender must win", committed, conflicts, pids)
	}
	t.Logf("actual mutual TLS gRPC: gateway plus three independent client process IDs %v", pids)
	lost := f.request(t, 0, 1, f.LostRequestID)
	lost.Effects = append(lost.Effects, f.job(t, 0, 1, 0, lost.RequestId))
	out := proofRunCommand(t, dir, proofFixtureCommand{Mode: "commit", Client: 0, Address: address, Request: proofMarshal(t, lost), ExpectedCode: "Unavailable"})
	if out.Code != "Unavailable" {
		t.Fatal(out)
	}
	var pending proofProcessFrame
	proofFixtureRead(t, filepath.Join(dir, "client-0.frame.json"), &pending)
	if len(pending.Pending) == 0 || pending.Cursor != 1 || len(pending.Events) != 1 {
		t.Fatal("lost network ACK projected optimistic success")
	}
	rawPending := new(pb.ProofCommitRequest)
	if err := proto.Unmarshal(pending.Pending, rawPending); err != nil || rawPending.Auth != nil || rawPending.RequestId != lost.RequestId {
		t.Fatal("pending contains credentials or changed identity", err)
	}
	if bytes.Contains(pending.Pending, []byte(f.Clients[0].Secret)) {
		t.Fatal("durable credential")
	}
	proofStopGateway(t, dir, gateway)
	s, err := store.Open(filepath.Join(dir, "gateway"), false)
	if err != nil {
		t.Fatal(err)
	}
	for _, check := range []struct {
		table string
		want  int
	}{{"op_request", 4}, {"op_event", 2}, {"op_effect", 3}, {"pq_job", 3}, {"pq_receipt", 3}} {
		var count int
		if err = s.DB.QueryRow("SELECT count(*) FROM " + check.table).Scan(&count); err != nil || count != check.want {
			t.Fatal("atomic gateway rows", check.table, count, err)
		}
	}
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	gateway, address, _ = proofStartGateway(t, dir)
	out = proofRunCommand(t, dir, proofFixtureCommand{Mode: "resolve", Client: 0, Address: address, ExpectedCode: "OK"})
	settled := new(pb.ProofCommitResult)
	if err := proto.Unmarshal(out.Result, settled); err != nil {
		t.Fatal(err)
	}
	proofFixtureRead(t, filepath.Join(dir, "client-0.frame.json"), &pending)
	if pending.Cursor != 2 || len(pending.Events) != 2 || len(pending.Pending) != 0 || len(settled.Event.PrintReceipts) != 2 {
		t.Fatal("restart lost exact effects/receipts")
	}
	retry := proofRunCommand(t, dir, proofFixtureCommand{Mode: "retry", Client: 0, Address: address, Request: proofMarshal(t, lost), ExpectedCode: "OK"})
	if !bytes.Equal(out.Result, retry.Result) || out.FrameSHA256 != retry.FrameSHA256 {
		t.Fatal("identical durable ACK retry changed frame/result")
	}
	changed := proto.Clone(lost).(*pb.ProofCommitRequest)
	changed.ApplicationData = []byte("different frozen intent")
	proofRunCommand(t, dir, proofFixtureCommand{Mode: "probe", Client: 0, Address: address, Request: proofMarshal(t, changed), ExpectedCode: "AlreadyExists"})
	for _, check := range []struct {
		name   string
		client int
		code   string
	}{{"reissued-origin", 3, "Unauthenticated"}, {"wrong-ca", 4, "Unavailable"}, {"duplicate-SAN", 5, "Unauthenticated"}, {"encoded-SAN", 6, "Unauthenticated"}, {"foreign-Venue-certificate", 7, "PermissionDenied"}} {
		t.Run(check.name, func(t *testing.T) {
			proofRunCommand(t, dir, proofFixtureCommand{Mode: "status", Client: check.client, Address: address, ExpectedCode: check.code})
		})
	}
	t.Run("base-cert-queued-result", func(t *testing.T) {
		proofRunCommand(t, dir, proofFixtureCommand{Mode: "get", Client: 8, Address: address, Request: proofMarshal(t, lost), ExpectedCode: "Unauthenticated"})
	})
	for _, name := range []string{"wrong-Venue", "wrong-epoch", "wrong-host", "wrong-envelope-origin", "request-origin", "unknown-wire-field", "changed-mode"} {
		t.Run(name, func(t *testing.T) {
			r := f.request(t, 0, 2, "")
			code := "InvalidArgument"
			switch name {
			case "wrong-Venue":
				r.Auth = f.auth(0)
				r.Auth.Scope.VenueId = uuid.NewString()
				code = "PermissionDenied"
			case "wrong-epoch":
				r.AuthorityEpoch++
				code = "FailedPrecondition"
			case "wrong-host", "wrong-envelope-origin":
				var j printqueue.FrozenJob
				json.Unmarshal(r.Effects[0].Payload, &j)
				if name == "wrong-host" {
					j.Destination.WorkerHostID = uuid.NewString()
					code = "FailedPrecondition"
				} else {
					j.OriginInstallationID = uuid.NewString()
					code = "PermissionDenied"
				}
				r.Effects[0].Payload, _ = json.Marshal(j)
			case "request-origin":
				r.OriginInstallationId = uuid.NewString()
			case "unknown-wire-field":
				r.ProtoReflect().SetUnknown([]byte{0xa0, 0x06, 0x01})
			case "changed-mode":
				r.PrintAdmission = "PRODUCTION"
			}
			prior, _ := os.ReadFile(filepath.Join(dir, "client-0.frame.json"))
			proofRunCommand(t, dir, proofFixtureCommand{Mode: "probe", Client: 0, Address: address, Request: proofMarshal(t, r), ExpectedCode: code})
			after, _ := os.ReadFile(filepath.Join(dir, "client-0.frame.json"))
			if !bytes.Equal(prior, after) {
				t.Fatal("probe changed durable client frame")
			}
		})
	}
	proofStopGateway(t, dir, gateway)
	s, err = store.Open(filepath.Join(dir, "gateway"), false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	var jobs int
	if err = s.DB.QueryRow("SELECT count(*) FROM pq_job").Scan(&jobs); err != nil || jobs != 3 {
		t.Fatal("retry/refused scope enqueued", jobs, err)
	}
}

func TestOperationalProofFreshCertificateTerminalRevocationAndFoundationIsolation(t *testing.T) {
	dir := t.TempDir()
	f := newProofWireFixture(t, dir)
	s, err := store.Open(filepath.Join(dir, "gateway"), false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	proof, err := server.NewQueuedOperationalProof(context.Background(), s, f.ClientCA)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- proof.Serve(ctx, listener) }()
	defer func() {
		cancel()
		if err := <-done; err != nil {
			t.Error(err)
		}
	}()
	client, connection := proofProcessConnect(t, f, proofFixtureCommand{Client: 0, Address: listener.Addr().String()})
	defer connection.Close()
	callCtx, stop := context.WithTimeout(ctx, 5*time.Second)
	defer stop()
	if _, err := client.Status(callCtx, f.auth(0)); err != nil {
		t.Fatal(err)
	}
	if _, err := pb.NewFoundationClient(connection).Status(callCtx, f.auth(0)); status.Code(err) != codes.Unimplemented {
		t.Fatal("proof accidentally registers normal Foundation", err)
	}
	if err := s.Revoke(f.Clients[0].TerminalID); err != nil {
		t.Fatal(err)
	}
	if _, err := client.Status(callCtx, f.auth(0)); status.Code(err) != codes.Unauthenticated {
		t.Fatal("live TLS channel bypassed revoked terminal", err)
	}
	base, baseConnection := proofProcessConnect(t, f, proofFixtureCommand{Client: 8, Address: listener.Addr().String()})
	defer baseConnection.Close()
	if _, err := base.Status(callCtx, f.auth(8)); status.Code(err) != codes.Unauthenticated {
		t.Fatal("base identity revived revoked terminal", err)
	}
	// The ordinary server keeps its existing mode and protocol; no proof grant
	// or queue capability is attached to normal startup by the additive source.
	normal, err := server.New(s)
	if err != nil {
		t.Fatal(err)
	}
	normalListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	normalCtx, normalCancel := context.WithCancel(context.Background())
	normalDone := make(chan error, 1)
	go func() { normalDone <- normal.Serve(normalCtx, normalListener) }()
	defer func() {
		normalCancel()
		if err := <-normalDone; err != nil {
			t.Error(err)
		}
	}()
	_, normalConnection := proofProcessConnect(t, f, proofFixtureCommand{Client: 1, Address: normalListener.Addr().String()})
	defer normalConnection.Close()
	normalAuth := f.auth(1)
	normalAuth.Scope.Protocol = &pb.Protocol{Major: 1, Minor: 1}
	normalStatus, err := pb.NewFoundationClient(normalConnection).Status(callCtx, normalAuth)
	if err != nil || normalStatus.Mode != "FOUNDATION_ONLY" || normalStatus.BusinessMutationsEnabled || normalStatus.Protocol.Minor != 1 || normalStatus.SchemaVersion != store.SchemaVersion {
		t.Fatal("ordinary startup changed authority", normalStatus, err)
	}
	if _, err := pb.NewOperationalProofClient(normalConnection).Status(callCtx, f.auth(1)); status.Code(err) != codes.Unimplemented {
		t.Fatal("ordinary startup accidentally exposes proof or queue RPC", err)
	}
}

func TestOperationalProofConstructorPreflightsServerPinWithX509(t *testing.T) {
	for _, name := range []string{"SAN", "EKU", "expired", "not-yet-valid", "extra-SAN"} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			f := newProofWireFixture(t, dir)
			s, err := store.Open(filepath.Join(dir, "gateway"), false)
			if err != nil {
				t.Fatal(err)
			}
			defer s.Close()
			key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
			if err != nil {
				t.Fatal(err)
			}
			leaf := &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: "vynic-edge.local"}, DNSNames: []string{"vynic-edge.local"}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true}
			switch name {
			case "SAN":
				leaf.DNSNames = []string{"another-host.local"}
			case "EKU":
				leaf.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
			case "expired":
				leaf.NotBefore = time.Now().Add(-time.Hour)
				leaf.NotAfter = time.Now().Add(-time.Minute)
			case "not-yet-valid":
				leaf.NotBefore = time.Now().Add(time.Hour)
				leaf.NotAfter = time.Now().Add(2 * time.Hour)
			case "extra-SAN":
				leaf.DNSNames = append(leaf.DNSNames, "another-host.local")
			}
			der, err := x509.CreateCertificate(rand.Reader, leaf, leaf, &key.PublicKey, key)
			if err != nil {
				t.Fatal(err)
			}
			private, err := x509.MarshalPKCS8PrivateKey(key)
			if err != nil {
				t.Fatal(err)
			}
			// Disposable qualification fixture only; no production identity
			// rotation or provisioning API is introduced.
			if _, err = s.DB.Exec("UPDATE installation SET certificate=?,tls_key=?", pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: private})); err != nil {
				t.Fatal(err)
			}
			if server, err := server.NewQueuedOperationalProof(context.Background(), s, f.ClientCA); err == nil || server != nil {
				t.Fatal("unqualified server pin handed to Dart", name, err)
			}
		})
	}
}
