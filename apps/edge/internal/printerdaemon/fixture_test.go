package printerdaemon

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
	"math/big"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printeragent"
	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

// Test-only provisioning: no runnable production command issues credentials,
// initializes a default Edge root or asserts Device/origin authority.
type softwareFixture struct {
	root, configPath, clientPath string
	config                       Config
	client                       ClientProfile
	ca                           *x509.Certificate
	caKey                        *ecdsa.PrivateKey
}

func canonicalTemp(t *testing.T) string {
	t.Helper()
	path, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return path
}
func bytesHash(raw []byte) string { h := sha256.Sum256(raw); return hex.EncodeToString(h[:]) }
func writeBytes(t *testing.T, path string, raw []byte) Artifact {
	t.Helper()
	if err := os.WriteFile(path, raw, 0600); err != nil {
		t.Fatal(err)
	}
	return Artifact{Path: path, SHA256: bytesHash(raw)}
}
func writeJSON(t *testing.T, path string, value any) Artifact {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return writeBytes(t, path, raw)
}
func fileArtifact(t *testing.T, path string) Artifact {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return Artifact{Path: path, SHA256: bytesHash(raw)}
}

func certPair(t *testing.T, template, issuer *x509.Certificate, signer *ecdsa.PrivateKey) ([]byte, []byte, *x509.Certificate, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	if issuer == nil {
		issuer, signer = template, key
	}
	der, err := x509.CreateCertificate(rand.Reader, template, issuer, &key.PublicKey, signer)
	if err != nil {
		t.Fatal(err)
	}
	certificate, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	encodedKey, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: encodedKey}), certificate, key
}
func baseLeaf() *x509.Certificate {
	return &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: "synthetic held software fixture"}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature}
}
func fixture(t *testing.T, executable string) softwareFixture {
	t.Helper()
	root := canonicalTemp(t)
	state := filepath.Join(root, "printer-state")
	storage, identity := testutil.Bound(t, state)
	if err := storage.Close(); err != nil {
		t.Fatal(err)
	}
	if executable == "" {
		var err error
		executable, err = os.Executable()
		if err != nil {
			t.Fatal(err)
		}
		executable, err = filepath.EvalSymlinks(executable)
		if err != nil {
			t.Fatal(err)
		}
	}
	agent := fileArtifact(t, executable)
	helper := writeBytes(t, filepath.Join(root, "held-helper.bin"), []byte("unexecuted synthetic helper"))
	profile := writeBytes(t, filepath.Join(root, "capability-profile.json"), []byte("{\"protocol\":1,\"paperWidthMm\":80,\"rasterWidthDots\":576,\"language\":\"escposRaster\",\"cutter\":\"none\",\"encoding\":\"georgianViaRaster\",\"beep\":{\"capability\":\"unknown\",\"enabled\":false}}"))
	hostID, deviceID, clientID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	pins := printhost.Pins{Scope: printhost.Local, OwnershipPolicy: printhost.LocalHost, Role: printhost.PrintGateway, VenueID: identity.VenueID, InstallationID: identity.InstallationID, DeviceID: deviceID, HostID: hostID, GatewayHostID: hostID, AuthorityEpoch: 1, ProtocolVersion: 1, HelperProtocolVersion: 1, DatabaseSchemaVersion: store.SchemaVersion, MinimumReaderVersion: 2, RouteRevision: 1, ConfigRevision: 1, RegistryRevision: 1, BindingRevision: 1, CapabilityRevision: 1, CapabilityProfileSHA256: profile.SHA256, HostBinarySHA256: agent.SHA256, HelperBinarySHA256: helper.SHA256}
	caTemplate := baseLeaf()
	caTemplate.IsCA = true
	caTemplate.KeyUsage = x509.KeyUsageCertSign | x509.KeyUsageCRLSign
	caPEM, _, ca, caKey := certPair(t, caTemplate, nil, nil)
	serverTemplate := baseLeaf()
	serverTemplate.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}
	serverTemplate.DNSNames = []string{printeragent.ServerName}
	serverPEM, serverKeyPEM, serverLeaf, _ := certPair(t, serverTemplate, ca, caKey)
	clientTemplate := baseLeaf()
	clientTemplate.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
	uri, err := printeragent.ClientURI(hostID, clientID)
	if err != nil {
		t.Fatal(err)
	}
	clientTemplate.URIs = []*url.URL{uri}
	clientPEM, clientKeyPEM, clientLeaf, _ := certPair(t, clientTemplate, ca, caKey)
	serverPath, serverKeyPath, caPath := filepath.Join(root, "server.pem"), filepath.Join(root, "server-key.pem"), filepath.Join(root, "client-ca.pem")
	clientCertPath, clientKeyPath := filepath.Join(root, "client.pem"), filepath.Join(root, "client-key.pem")
	writeBytes(t, serverPath, serverPEM)
	writeBytes(t, serverKeyPath, serverKeyPEM)
	writeBytes(t, caPath, caPEM)
	writeBytes(t, clientCertPath, clientPEM)
	writeBytes(t, clientKeyPath, clientKeyPEM)
	cfg := Config{Version: 1, Profile: LocalHeld, DispatchPolicy: DispatchHeld, Pins: pins, StateDirectory: state, ListenAddress: "127.0.0.1:0", Agent: agent, Helper: HelperArtifact{Path: helper.Path, SHA256: helper.SHA256, ProtocolVersion: 1}, CapabilityProfile: profile, TLS: TLSPaths{ServerCertificatePath: serverPath, ServerPrivateKeyPath: serverKeyPath, ClientCAPath: caPath}, Clients: []ClientPin{{ClientID: clientID, CertificateSHA256: bytesHash(clientLeaf.Raw)}}}
	client := ClientProfile{Version: 1, ProvisionStatus: ProvisioningHeld, ListenAddress: cfg.ListenAddress, ClientID: clientID, CurrentDeviceInstallationID: uuid.NewString(), Pins: pins, ServerCertificatePath: serverPath, ServerCertificateSHA256: bytesHash(serverLeaf.Raw), ClientCertificatePath: clientCertPath, ClientPrivateKeyPath: clientKeyPath, ClientCertificateSHA256: bytesHash(clientLeaf.Raw)}
	f := softwareFixture{root: root, configPath: filepath.Join(root, "daemon.json"), clientPath: filepath.Join(root, "client-profile.json"), config: cfg, client: client, ca: ca, caKey: caKey}
	f.save(t)
	return f
}
func (f *softwareFixture) save(t *testing.T) {
	t.Helper()
	f.client.Pins = f.config.Pins
	f.client.ListenAddress = f.config.ListenAddress
	writeJSON(t, filepath.Join(f.config.StateDirectory, StateMarkerFilename), StateMarker{Version: 1, Purpose: StatePurpose, SchemaVersion: store.SchemaVersion, Pins: f.config.Pins})
	writeJSON(t, f.configPath, f.config)
	writeJSON(t, f.clientPath, f.client)
}
func fixedLoopback(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	if err = listener.Close(); err != nil {
		t.Fatal(err)
	}
	return address
}
func connectFixture(t *testing.T, f softwareFixture, address string) (pb.PrinterAgentClient, *grpc.ClientConn) {
	t.Helper()
	certificate, err := tls.LoadX509KeyPair(f.client.ClientCertificatePath, f.client.ClientPrivateKeyPath)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(f.ca)
	tlsConfig := &tls.Config{MinVersion: tls.VersionTLS13, ServerName: printeragent.ServerName, RootCAs: roots, Certificates: []tls.Certificate{certificate}, VerifyConnection: func(state tls.ConnectionState) error {
		if len(state.PeerCertificates) != 1 || bytesHash(state.PeerCertificates[0].Raw) != f.client.ServerCertificateSHA256 {
			return ErrConfig
		}
		return nil
	}}
	conn, err := grpc.NewClient(address, grpc.WithTransportCredentials(credentials.NewTLS(tlsConfig)))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := conn.Close(); err != nil {
			t.Error(err)
		}
	})
	return pb.NewPrinterAgentClient(conn), conn
}
func healthAuth(f softwareFixture) *pb.PrinterAgentAuth {
	return &pb.PrinterAgentAuth{HostId: f.config.Pins.HostID, ClientId: f.client.ClientID, ProtocolMajor: 1, ProtocolMinor: 0, ReaderVersion: 2, RequiredCapabilities: []string{printeragent.Capability}}
}
func stopDaemon(t *testing.T, d *Daemon) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := d.Stop(ctx); err != nil {
		t.Error(err)
	}
}
func queueIdentity(f softwareFixture) printqueue.GatewayIdentity {
	p := f.config.Pins
	return printqueue.GatewayIdentity{VenueID: p.VenueID, InstallationID: p.InstallationID, DeviceID: p.DeviceID, WorkerHostID: p.HostID, Epoch: p.AuthorityEpoch}
}
func testRegistry(f softwareFixture) printqueue.Registry {
	p := f.config.Pins
	id := uuid.NewString()
	return printqueue.Registry{PhysicalPrinterID: id, VenueID: p.VenueID, InstallationID: p.InstallationID, AuthorityEpoch: p.AuthorityEpoch, DeviceID: p.DeviceID, WorkerHostID: p.HostID, BindingRevision: 1, ConfigRevision: 1, RegistryRevision: 1, Aliases: []string{uuid.NewString()}, Destination: printtransport.Destination{PhysicalPrinterID: id, WorkerHostID: p.HostID, Transport: printtransport.TCP, Host: "127.0.0.1", Port: 9100}}
}
func frozenJob(t *testing.T, f softwareFixture, r printqueue.Registry, beep bool) printqueue.FrozenJob {
	t.Helper()
	d := r.Destination
	d.DocumentName = "synthetic retained fixture"
	profile, err := os.ReadFile(f.config.CapabilityProfile.Path)
	if err != nil {
		t.Fatal(err)
	}
	if beep {
		profile = []byte("{\"protocol\":1,\"paperWidthMm\":80,\"rasterWidthDots\":576,\"language\":\"escposRaster\",\"cutter\":\"none\",\"encoding\":\"georgianViaRaster\",\"beep\":{\"capability\":\"epsonEscA97Pattern\",\"enabled\":true}}")
	}
	primary := []byte("synthetic fixture only")
	j := printqueue.FrozenJob{Version: 1, JobID: uuid.NewString(), EffectID: uuid.NewString(), RequestID: uuid.NewString(), TerminalID: uuid.NewString(), VenueID: r.VenueID, InstallationID: r.InstallationID, OriginInstallationID: uuid.NewString(), AuthorityEpoch: 1, DeviceID: r.DeviceID, PhysicalPrinterID: r.PhysicalPrinterID, AliasID: r.Aliases[0], RouteRevision: 1, ConfigRevision: 1, BindingRevision: 1, RegistryRevision: 1, AttemptID: uuid.NewString(), BeepAttemptID: uuid.NewString(), Destination: d, CapabilityProfile: profile, PrimaryBytes: primary, PrimarySHA256: bytesHash(primary)}
	raw, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	j, err = printqueue.DecodeFrozenJob(raw)
	if err != nil {
		t.Fatal(err)
	}
	return j
}

type syntheticGuard struct{}

func (syntheticGuard) Context(c context.Context) context.Context { return c }
func (syntheticGuard) Close() error                              { return nil }

type syntheticSender struct{ sends int }

func (s *syntheticSender) Physical() bool { return false }
func (s *syntheticSender) Send(_ context.Context, _ printtransport.Destination, raw []byte) printtransport.Result {
	s.sends++
	return printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: uint32(len(raw)), Stage: "synthetic"}
}
