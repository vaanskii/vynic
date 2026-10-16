package printerprovisioning

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"time"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printstation"
)

const ProductionPurpose = "VYNIC_PRINTER_PRODUCTION"
const ProductionDomain = "vynic/printer-provisioning/production/v1\x00"
const EnrollmentDomain = "vynic/printer-enrollment/v1\x00"
const OfflineSeconds int64 = 7 * 24 * 60 * 60
const MaxProductionBody = 512 << 10
const MaxProductionGrant = 1 << 20

type ProductionMember struct {
	InstallationID    string `json:"installationId"`
	DeviceID          string `json:"deviceId"`
	PublicKey         string `json:"publicKey"`
	CertificateSHA256 string `json:"certificateSha256"`
	Authorized        bool   `json:"authorized"`
	Role              string `json:"role"`
	EndpointHint      string `json:"endpointHint"`
}
type ProductionBody struct {
	Version           uint32             `json:"version"`
	Purpose           string             `json:"purpose"`
	VenueID           string             `json:"venueId"`
	ClusterID         string             `json:"clusterId"`
	Generation        uint64             `json:"generation"`
	Revision          uint64             `json:"revision"`
	IssuedAt          int64              `json:"issuedAt"`
	NotBefore         int64              `json:"notBefore"`
	ExpiresAt         int64              `json:"expiresAt"`
	OfflineMaxSeconds int64              `json:"offlineMaxSeconds"`
	Topology          string             `json:"topology"`
	Members           []ProductionMember `json:"members"`
	CatalogRaw        []byte             `json:"catalogRaw"`
}

func productionInput(b []byte) []byte { return append([]byte(ProductionDomain), mustDigestBytes(b)...) }
func mustDigestBytes(b []byte) []byte { h := sha256.Sum256(b); return h[:] }
func rawKey(s string) (ed25519.PublicKey, error) {
	b, e := base64.RawURLEncoding.DecodeString(s)
	if e != nil || len(b) != 32 || base64.RawURLEncoding.EncodeToString(b) != s {
		return nil, ErrInvalid
	}
	return ed25519.PublicKey(b), nil
}
func (b ProductionBody) member(id string) (ProductionMember, error) {
	for _, m := range b.Members {
		if m.InstallationID == id {
			return m, nil
		}
	}
	return ProductionMember{}, ErrScope
}
func (b ProductionBody) catalog() (printstation.Catalog, error) {
	var c printstation.Catalog
	if len(b.CatalogRaw) == 0 {
		return c, ErrBinding
	}
	if strict(b.CatalogRaw, 128<<10, &c) != nil || c.Validate() != nil || c.VenueID != b.VenueID || c.Revision != b.Revision {
		return c, ErrBinding
	}
	for _, k := range c.Controllers {
		m, e := b.member(k.InstallationID)
		if e != nil || m.DeviceID != k.DeviceID {
			return c, ErrScope
		}
	}
	for _, s := range c.Stations {
		if s.Scope == printstation.Shared && b.Topology == "LOCAL_ONLY" {
			return c, ErrBinding
		}
	}
	return c, nil
}

// VerifyProduction verifies issuer authenticity and policy, without treating a
// signed catalog as permission for a caller-supplied identity. Store binds self,
// retains freshness/revocation, and authenticates peers separately.
func VerifyProduction(raw []byte, issuer ed25519.PublicKey, now time.Time) (ProductionBody, error) {
	var signed SignedGrant
	var b ProductionBody
	if len(issuer) != 32 || strict(raw, MaxProductionGrant, &signed) != nil || len(signed.Body) > MaxProductionBody || !ed25519.Verify(issuer, productionInput(signed.Body), signed.Signature) {
		return b, ErrSignature
	}
	if strict(signed.Body, MaxProductionBody, &b) != nil || b.Version != 1 || b.Purpose != ProductionPurpose || !printqueue.CanonicalUUID(b.VenueID) || !printqueue.CanonicalUUID(b.ClusterID) || b.Generation == 0 || b.Generation > 2147483646 || b.Revision > 2147483646 || len(b.Members) < 1 || len(b.Members) > 256 {
		return b, ErrInvalid
	}
	n := now.Unix()
	if b.OfflineMaxSeconds != OfflineSeconds || b.IssuedAt <= 0 || b.NotBefore != b.IssuedAt || b.ExpiresAt <= b.IssuedAt || b.ExpiresAt-b.IssuedAt > OfflineSeconds || n < b.NotBefore || n >= b.ExpiresAt {
		return b, ErrLifetime
	}
	ids, devices, keys, certs := map[string]bool{}, map[string]bool{}, map[string]bool{}, map[string]bool{}
	voters := 0
	var fields struct {
		Members []json.RawMessage `json:"members"`
	}
	if json.Unmarshal(signed.Body, &fields) != nil {
		return b, ErrInvalid
	}
	for i, m := range b.Members {
		if exactObject(fields.Members[i], m) != nil || !printqueue.CanonicalUUID(m.InstallationID) || !printqueue.CanonicalUUID(m.DeviceID) || m.InstallationID == m.DeviceID || ids[m.InstallationID] || keys[m.PublicKey] || certs[m.CertificateSHA256] || !digest(m.CertificateSHA256) {
			return b, ErrInvalid
		}
		if _, e := rawKey(m.PublicKey); e != nil {
			return b, e
		}
		if m.Authorized && devices[m.DeviceID] {
			return b, ErrScope
		}
		if m.Authorized {
			devices[m.DeviceID] = true
		}
		ids[m.InstallationID] = true
		keys[m.PublicKey] = true
		certs[m.CertificateSHA256] = true
		if m.Role == "VOTER" {
			voters++
		} else if m.Role != "CLIENT" {
			return b, ErrInvalid
		}
		if m.EndpointHint != "" {
			host, port, e := net.SplitHostPort(m.EndpointHint)
			p, pe := strconv.Atoi(port)
			if e != nil || net.ParseIP(host) == nil || pe != nil || p < 1 || p > 65535 {
				return b, ErrInvalid
			}
		}
	}
	want, ok := map[string]int{"LOCAL_ONLY": 0, "SINGLE_REPLICA": 1, "THREE_REPLICAS": 3}[b.Topology]
	if !ok || voters != want {
		return b, ErrBinding
	}
	if len(b.CatalogRaw) > 0 {
		if _, e := b.catalog(); e != nil {
			return b, e
		}
	} else if b.Topology != "LOCAL_ONLY" {
		return b, ErrBinding
	}
	return b, nil
}
func sameMemberIdentity(a, b ProductionMember) bool {
	return a.InstallationID == b.InstallationID && a.DeviceID == b.DeviceID && a.PublicKey == b.PublicKey && a.CertificateSHA256 == b.CertificateSHA256
}
func checkEvolution(old, next ProductionBody) error {
	if next.Generation < old.Generation || next.Revision < old.Revision {
		return ErrStale
	}
	if old.ClusterID != next.ClusterID || old.VenueID != next.VenueID {
		return ErrScope
	}
	if next.Generation == old.Generation && !bytes.Equal(printstation.Encode(old), printstation.Encode(next)) {
		return ErrStale
	}
	if next.Revision == old.Revision && (!bytes.Equal(old.CatalogRaw, next.CatalogRaw) || old.Topology != next.Topology) {
		return ErrStale
	}
	for _, m := range old.Members {
		n, e := next.member(m.InstallationID)
		if e != nil || !sameMemberIdentity(m, n) || (!m.Authorized && n.Authorized) {
			return ErrRevoked
		}
		if next.Revision == old.Revision && (m.Role != n.Role || m.EndpointHint != n.EndpointHint) {
			return ErrStale
		}
	}
	return nil
}

// authorize is invoked against a fresh, durable verified snapshot on every
// operation, including existing TLS connections. It grants no physical permit.
func authorize(b ProductionBody, installation, device, station, controller string) (printstation.Authority, error) {
	m, e := b.member(installation)
	if e != nil || m.DeviceID != device {
		return printstation.Authority{}, ErrScope
	}
	if !m.Authorized {
		return printstation.Authority{}, ErrRevoked
	}
	c, e := b.catalog()
	if e != nil {
		return printstation.Authority{}, e
	}
	a := printstation.Authority{VenueID: b.VenueID, DeviceID: m.DeviceID}
	if station != "" {
		s, ok := c.Station(station)
		if !ok || !s.Enabled || (s.Scope == printstation.Local && s.OwnerDeviceID != m.DeviceID) {
			return a, ErrScope
		}
	}
	if controller != "" {
		k, ok := c.Controller(controller)
		if !ok || k.InstallationID != m.InstallationID || k.DeviceID != device {
			return a, ErrScope
		}
		a.ControllerID = k.ID
	}
	if station == "" && controller == "" {
		return a, fmt.Errorf("%w: explicit station or controller required", ErrScope)
	}
	return a, nil
}
