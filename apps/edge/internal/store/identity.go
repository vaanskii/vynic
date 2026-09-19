package store

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"
)

type Identity struct {
	InstallationID string `json:"installationId"`
	PublicKey      string `json:"publicKey"`
	VenueID        string `json:"venueId,omitempty"`
	Certificate    []byte `json:"-"`
	TLSKey         []byte `json:"-"`
}

func (s *Store) Init() (Identity, error) {
	var count int
	if err := s.DB.QueryRow("SELECT count(*) FROM installation").Scan(&count); err != nil {
		return Identity{}, err
	}
	if count > 0 {
		return s.Identity()
	}
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return Identity{}, err
	}
	tlsPriv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return Identity{}, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return Identity{}, err
	}
	template := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: "vynic-edge.local"}, DNSNames: []string{"vynic-edge.local"}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().AddDate(5, 0, 0), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &tlsPriv.PublicKey, tlsPriv)
	if err != nil {
		return Identity{}, err
	}
	pk, err := x509.MarshalPKCS8PrivateKey(tlsPriv)
	if err != nil {
		return Identity{}, err
	}
	id := Identity{InstallationID: uuid.NewString(), PublicKey: base64.RawURLEncoding.EncodeToString(pub), Certificate: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), TLSKey: pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pk})}
	_, err = s.DB.Exec("INSERT INTO installation(singleton,id,public_key,private_key,certificate,tls_key,created_at) VALUES(1,?,?,?,?,?,?)", id.InstallationID, id.PublicKey, []byte(priv), id.Certificate, id.TLSKey, time.Now().Unix())
	return id, err
}
func (s *Store) Identity() (Identity, error) {
	var id Identity
	var venue sql.NullString
	var private []byte
	err := s.DB.QueryRow("SELECT id,public_key,private_key,venue_id,certificate,tls_key FROM installation WHERE singleton=1").Scan(&id.InstallationID, &id.PublicKey, &private, &venue, &id.Certificate, &id.TLSKey)
	if err != nil {
		return id, err
	}
	id.VenueID = venue.String
	if _, err = uuid.Parse(id.InstallationID); err != nil {
		return id, errors.New("invalid installation identity")
	}
	if len(private) != ed25519.PrivateKeySize || base64.RawURLEncoding.EncodeToString(ed25519.PrivateKey(private).Public().(ed25519.PublicKey)) != id.PublicKey {
		return id, errors.New("installation key mismatch")
	}
	if _, err = tls.X509KeyPair(id.Certificate, id.TLSKey); err != nil {
		return id, err
	}
	return id, nil
}

type Grant struct {
	Version        int    `json:"version"`
	Purpose        string `json:"purpose"`
	Mode           string `json:"mode"`
	InstallationID string `json:"installationId"`
	VenueID        string `json:"venueId"`
	PublicKey      string `json:"publicKey"`
	IssuedAt       int64  `json:"issuedAt"`
	ExpiresAt      int64  `json:"expiresAt"`
}

func (s *Store) Bind(raw string, cloudPEM []byte) error {
	parts := strings.Split(strings.TrimSpace(raw), ".")
	if len(parts) != 2 {
		return errors.New("invalid grant")
	}
	block, _ := pem.Decode(cloudPEM)
	if block == nil {
		return errors.New("missing trusted Cloud public key")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return err
	}
	pub, ok := key.(ed25519.PublicKey)
	if !ok {
		return errors.New("Cloud key must be Ed25519")
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !ed25519.Verify(pub, []byte(parts[0]), sig) {
		return errors.New("invalid grant signature")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return err
	}
	var g Grant
	if err = json.Unmarshal(payload, &g); err != nil {
		return err
	}
	now := time.Now().Unix()
	if g.Version != 1 || g.Purpose != "vynic-edge-foundation" || g.Mode != "FOUNDATION_ONLY" || g.IssuedAt > now+30 || g.ExpiresAt <= now || g.ExpiresAt <= g.IssuedAt || g.ExpiresAt-g.IssuedAt > 600 {
		return errors.New("expired or incompatible foundation grant")
	}
	if _, err = uuid.Parse(g.VenueID); err != nil {
		return errors.New("invalid Venue")
	}
	id, err := s.Identity()
	if err != nil {
		return err
	}
	if g.InstallationID != id.InstallationID || g.PublicKey != id.PublicKey {
		return errors.New("grant belongs to another installation")
	}
	if id.VenueID != "" && id.VenueID != g.VenueID {
		return errors.New("Venue binding is immutable")
	}
	_, err = s.DB.Exec("UPDATE installation SET venue_id=?,binding_grant=? WHERE singleton=1", g.VenueID, raw)
	return err
}
func Secret() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}
func ValidSecret(v string) bool {
	b, e := base64.RawURLEncoding.DecodeString(v)
	return e == nil && len(b) == 32 && base64.RawURLEncoding.EncodeToString(b) == v
}
func Hash(v string) string { sum := sha256.Sum256([]byte(v)); return hex.EncodeToString(sum[:]) }
