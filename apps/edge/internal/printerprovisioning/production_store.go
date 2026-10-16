package printerprovisioning

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/gofrs/flock"
	guuid "github.com/google/uuid"
	_ "modernc.org/sqlite"
	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printstation"
)

type EnrollmentRequest struct {
	InstallationID string `json:"installationId"`
	PublicKey      string `json:"publicKey"`
	Certificate    []byte `json:"certificate"`
	Proof          []byte `json:"proof"`
}

// ProductionStore is a dedicated, machine-bound installation store. Keep its
// directory outside POS/Hive backup/restore. Open does not import old identities
// or initialize a replacement when a nonempty store is corrupt.
type ProductionStore struct {
	mu         sync.Mutex
	db         *sql.DB
	lock       *flock.Flock
	issuer     ed25519.PublicKey
	device, id string
	key        ed25519.PrivateKey
	cert       []byte
	now        func() time.Time
}

func OpenProduction(directory, deviceID string, issuer ed25519.PublicKey) (*ProductionStore, error) {
	machine, e := productionMachineID()
	if e != nil {
		return nil, e
	}
	return openProduction(directory, deviceID, issuer, machine, time.Now)
}
func openProduction(directory, deviceID string, issuer ed25519.PublicKey, machine string, now func() time.Time) (_ *ProductionStore, err error) {
	if !printqueue.CanonicalUUID(deviceID) || len(issuer) != 32 || machine == "" || now == nil {
		return nil, ErrState
	}
	if err = os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	if err = secureProductionDirectory(directory); err != nil {
		return nil, err
	}
	directory, err = filepath.EvalSymlinks(directory)
	if err != nil {
		return nil, err
	}
	lock := flock.New(filepath.Join(directory, "production.lock"))
	ok, e := lock.TryLock()
	if e != nil || !ok {
		return nil, fmt.Errorf("%w: installation already open: %v", ErrState, e)
	}
	s := &ProductionStore{lock: lock, device: deviceID, issuer: bytes.Clone(issuer), now: now}
	defer func() {
		if err != nil {
			if s.db != nil {
				s.db.Close()
			}
			lock.Unlock()
		}
	}()
	path := filepath.Join(directory, "production.sqlite")
	_, statErr := os.Stat(path)
	fresh := errors.Is(statErr, os.ErrNotExist)
	if statErr != nil && !fresh {
		return nil, statErr
	}
	s.db, err = sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	s.db.SetMaxOpenConns(1)
	if _, err = s.db.Exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000"); err != nil {
		return nil, err
	}
	if fresh {
		pub, key, e := ed25519.GenerateKey(rand.Reader)
		if e != nil {
			return nil, e
		}
		s.key = key
		s.id = guuid.NewString()
		serial, e := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
		if e != nil {
			return nil, e
		}
		uri := &url.URL{Scheme: "spiffe", Host: "vynic-printer-production", Path: "/" + s.id}
		n := now()
		template := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: "Vynic printer installation"}, URIs: []*url.URL{uri}, NotBefore: n.Add(-time.Minute), NotAfter: n.AddDate(5, 0, 0), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth, x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true}
		s.cert, e = x509.CreateCertificate(rand.Reader, template, template, pub, key)
		if e != nil {
			return nil, e
		}
		protectedKey, e := protectProductionKey(key)
		if e != nil {
			return nil, e
		}
		tx, e := s.db.Begin()
		if e != nil {
			return nil, e
		}
		defer tx.Rollback()
		_, e = tx.Exec(`CREATE TABLE identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1), version INTEGER NOT NULL CHECK(version=1), installation TEXT NOT NULL, device TEXT NOT NULL, machine TEXT NOT NULL, issuer BLOB NOT NULL, private_key BLOB NOT NULL, certificate BLOB NOT NULL);
CREATE TABLE authorization (singleton INTEGER PRIMARY KEY CHECK(singleton=1), grant BLOB NOT NULL, observed_at INTEGER NOT NULL);
INSERT INTO identity VALUES (1,1,?,?,?,?,?,?);`, s.id, s.device, SHA256([]byte(machine)), s.issuer, protectedKey, s.cert)
		if e != nil {
			return nil, e
		}
		if e = tx.Commit(); e != nil {
			return nil, e
		}
		if e = os.Chmod(path, 0600); e != nil {
			return nil, e
		}
	} else {
		var device, machineHash string
		var pub []byte
		var version int
		err = s.db.QueryRow("SELECT version,installation,device,machine,issuer,private_key,certificate FROM identity WHERE singleton=1").Scan(&version, &s.id, &device, &machineHash, &pub, &s.key, &s.cert)
		if err != nil {
			return nil, err
		}
		s.key, err = unprotectProductionKey(s.key)
		if err != nil {
			return nil, err
		}
		if version != 1 || !printqueue.CanonicalUUID(s.id) || s.id == device || device != s.device || machineHash != SHA256([]byte(machine)) || !bytes.Equal(pub, s.issuer) || len(s.key) != 64 {
			return nil, ErrScope
		}
	}
	if e = s.validateOwnCertificate(); e != nil {
		return nil, e
	}
	// Validate a stored snapshot at its observed time, even if now expired. Never
	// erase a revoked/expired grant to make the machine appear newly enrolled.
	var raw []byte
	var observed int64
	e = s.db.QueryRow("SELECT grant,observed_at FROM authorization WHERE singleton=1").Scan(&raw, &observed)
	if e != nil && !errors.Is(e, sql.ErrNoRows) {
		return nil, e
	}
	if e == nil {
		b, e := VerifyProduction(raw, s.issuer, time.Unix(observed, 0))
		if e != nil {
			return nil, e
		}
		if e = s.bindSelf(b); e != nil {
			return nil, e
		}
	}
	return s, nil
}
func (s *ProductionStore) validateOwnCertificate() error {
	c, e := x509.ParseCertificate(s.cert)
	if e != nil {
		return e
	}
	pub, ok := c.PublicKey.(ed25519.PublicKey)
	if !ok || !bytes.Equal(pub, s.key.Public().(ed25519.PublicKey)) || c.CheckSignature(c.SignatureAlgorithm, c.RawTBSCertificate, c.Signature) != nil || len(c.URIs) != 1 || c.URIs[0].String() != "spiffe://vynic-printer-production/"+s.id || c.IsCA {
		return ErrScope
	}
	return nil
}
func (s *ProductionStore) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return errors.Join(s.db.Close(), s.lock.Unlock())
}
func (s *ProductionStore) Enrollment() EnrollmentRequest {
	input := []byte(EnrollmentDomain + s.device + "\x00" + s.id + "\x00" + SHA256(s.cert))
	return EnrollmentRequest{s.id, base64.RawURLEncoding.EncodeToString(s.key.Public().(ed25519.PublicKey)), bytes.Clone(s.cert), ed25519.Sign(s.key, input)}
}
func (s *ProductionStore) bindSelf(b ProductionBody) error {
	m, e := b.member(s.id)
	if e != nil || m.DeviceID != s.device || m.PublicKey != base64.RawURLEncoding.EncodeToString(s.key.Public().(ed25519.PublicKey)) || m.CertificateSHA256 != SHA256(s.cert) {
		return ErrScope
	}
	return nil
}
func (s *ProductionStore) Apply(raw []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	b, e := VerifyProduction(raw, s.issuer, now)
	if e != nil {
		return e
	}
	if e = s.bindSelf(b); e != nil {
		return e
	}
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	var oldRaw []byte
	var observed int64
	e = tx.QueryRow("SELECT grant,observed_at FROM authorization WHERE singleton=1").Scan(&oldRaw, &observed)
	if e != nil && !errors.Is(e, sql.ErrNoRows) {
		return e
	}
	if e == nil {
		if now.Unix() < observed {
			return ErrLifetime
		}
		old, e := VerifyProduction(oldRaw, s.issuer, time.Unix(observed, 0))
		if e != nil {
			return e
		}
		if e = checkEvolution(old, b); e != nil {
			return e
		}
	}
	// Commit revocation even for this installation; denial must survive reboot.
	_, e = tx.Exec("INSERT INTO authorization VALUES(1,?,?) ON CONFLICT(singleton) DO UPDATE SET grant=excluded.grant,observed_at=excluded.observed_at", bytes.Clone(raw), now.Unix())
	if e != nil {
		return e
	}
	return tx.Commit()
}
func (s *ProductionStore) current() (ProductionBody, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var raw []byte
	var observed int64
	if e := s.db.QueryRow("SELECT grant,observed_at FROM authorization WHERE singleton=1").Scan(&raw, &observed); e != nil {
		return ProductionBody{}, fmt.Errorf("%w: %v", ErrState, e)
	}
	now := s.now()
	if now.Unix() < observed {
		return ProductionBody{}, ErrLifetime
	}
	b, e := VerifyProduction(raw, s.issuer, now)
	if e != nil {
		return b, e
	}
	if e = s.bindSelf(b); e != nil {
		return b, e
	}
	self, _ := b.member(s.id)
	if !self.Authorized {
		return b, ErrRevoked
	}
	// Persist time before returning any authorization. A rollback below any
	// observed authorization time is refused across process restarts.
	_, e = s.db.Exec("UPDATE authorization SET observed_at=? WHERE singleton=1", now.Unix())
	return b, e
}

// Inventory returns signed-and-verified endpoint hints and roles, never LAN trust.
func (s *ProductionStore) Inventory() (ProductionBody, error) { return s.current() }

// AuthenticatedMember has no exported fields: a client cannot manufacture it
// from job JSON. It must come from a successfully verified TLS connection.
type AuthenticatedMember struct{ installation, device, certificate string }

func (s *ProductionStore) peerCertificate(der []byte, expected string) (AuthenticatedMember, error) {
	b, e := s.current()
	if e != nil {
		return AuthenticatedMember{}, e
	}
	cert, e := x509.ParseCertificate(der)
	if e != nil || len(cert.URIs) != 1 || len(cert.DNSNames) > 0 || len(cert.IPAddresses) > 0 || len(cert.EmailAddresses) > 0 || cert.IsCA || !cert.BasicConstraintsValid || cert.KeyUsage != x509.KeyUsageDigitalSignature || len(cert.ExtKeyUsage) != 2 {
		return AuthenticatedMember{}, ErrScope
	}
	if cert.ExtKeyUsage[0] != x509.ExtKeyUsageClientAuth || cert.ExtKeyUsage[1] != x509.ExtKeyUsageServerAuth || cert.CheckSignature(cert.SignatureAlgorithm, cert.RawTBSCertificate, cert.Signature) != nil {
		return AuthenticatedMember{}, ErrScope
	}
	now := s.now()
	if now.Before(cert.NotBefore) || !now.Before(cert.NotAfter) {
		return AuthenticatedMember{}, ErrLifetime
	}
	for _, m := range b.Members {
		if SHA256(der) != m.CertificateSHA256 {
			continue
		}
		if !m.Authorized {
			return AuthenticatedMember{}, ErrRevoked
		}
		if expected != "" && expected != m.InstallationID {
			return AuthenticatedMember{}, ErrScope
		}
		key, e := rawKey(m.PublicKey)
		if e != nil {
			return AuthenticatedMember{}, e
		}
		pub, ok := cert.PublicKey.(ed25519.PublicKey)
		if !ok || !bytes.Equal(key, pub) || cert.URIs[0].String() != "spiffe://vynic-printer-production/"+m.InstallationID {
			return AuthenticatedMember{}, ErrScope
		}
		return AuthenticatedMember{m.InstallationID, m.DeviceID, m.CertificateSHA256}, nil
	}
	return AuthenticatedMember{}, ErrScope
}
func (s *ProductionStore) Authenticate(state tls.ConnectionState) (AuthenticatedMember, error) {
	if !state.HandshakeComplete || state.Version != tls.VersionTLS13 || len(state.PeerCertificates) != 1 {
		return AuthenticatedMember{}, ErrScope
	}
	return s.peerCertificate(state.PeerCertificates[0].Raw, "")
}
func (s *ProductionStore) Authorize(peer AuthenticatedMember, stationID, controllerID string) (printstation.Authority, error) {
	b, e := s.current()
	if e != nil {
		return printstation.Authority{}, e
	}
	m, e := b.member(peer.installation)
	if e != nil || peer.certificate != m.CertificateSHA256 {
		return printstation.Authority{}, ErrScope
	}
	return authorize(b, peer.installation, peer.device, stationID, controllerID)
}

// TLSConfig uses TLS 1.3 and exact certificates pinned by production Cloud
// authority. Self-signed leaf trust is established by VerifyConnection, including
// validity, purpose, key and current membership; discovery never adds a pin.
func (s *ProductionStore) TLSConfig(server bool, expectedInstallation string) (*tls.Config, error) {
	if _, e := s.current(); e != nil {
		return nil, e
	}
	if !server && !printqueue.CanonicalUUID(expectedInstallation) {
		return nil, ErrScope
	}
	c := &tls.Config{MinVersion: tls.VersionTLS13, MaxVersion: tls.VersionTLS13, Certificates: []tls.Certificate{{Certificate: [][]byte{bytes.Clone(s.cert)}, PrivateKey: s.key}}, SessionTicketsDisabled: true}
	if server {
		c.ClientAuth = tls.RequireAnyClientCert
	} else {
		c.InsecureSkipVerify = true
	} // mandatory authenticated pin check below replaces PKI hostname verification
	c.VerifyConnection = func(state tls.ConnectionState) error {
		if state.Version != tls.VersionTLS13 || len(state.PeerCertificates) != 1 {
			return ErrScope
		}
		_, e := s.peerCertificate(state.PeerCertificates[0].Raw, expectedInstallation)
		return e
	}
	return c, nil
}
func (s *ProductionStore) MarshalEnrollment() ([]byte, error) { return json.Marshal(s.Enrollment()) }
