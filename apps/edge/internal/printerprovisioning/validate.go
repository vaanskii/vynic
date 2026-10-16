package printerprovisioning

import (
	"bytes"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/hex"
	"math"
	"net/url"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
)

func digest(s string) bool {
	d, err := hex.DecodeString(s)
	return err == nil && len(d) == 32 && hex.EncodeToString(d) == s
}

func revision(n uint64) bool { return n > 0 && n <= math.MaxInt64 }

func validAuthorization(a Authorization) bool {
	for _, id := range []string{a.VenueID, a.DeviceID, a.InstallationID, a.HostID, a.TerminalID, a.OriginInstallationID, a.ClientID} {
		if !printqueue.CanonicalUUID(id) {
			return false
		}
	}
	return revision(a.AuthorityEpoch) && revision(a.Generation) && digest(a.ClientCertificateSHA256)
}

func validScope(scope Scope, clusterID, membership string) bool {
	switch scope {
	case Local:
		return clusterID == "" && membership == ""
	case VenueShared:
		return printqueue.CanonicalUUID(clusterID) && digest(membership)
	default:
		return false
	}
}

func decodeSigned(raw []byte) (SignedGrant, error) {
	var s SignedGrant
	if strict(raw, MaxGrantBytes, &s) != nil || len(s.Body) == 0 || len(s.Body) > MaxBodyBytes || len(s.Signature) != ed25519.SignatureSize {
		return SignedGrant{}, ErrInvalid
	}
	return s, nil
}

func decodeBody(raw []byte) (GrantBody, error) {
	var b GrantBody
	if strict(raw, MaxBodyBytes, &b) != nil || nestedObject(raw, "authorization", Authorization{}) != nil || b.Version != Version || b.Purpose != Purpose || !printqueue.CanonicalUUID(b.GrantID) || !validAuthorization(b.Authorization) || !validScope(b.Scope, b.ClusterID, b.MembershipSHA256) || !digest(b.RouteSHA256) || SHA256(b.RouteRaw) != b.RouteSHA256 {
		return GrantBody{}, ErrInvalid
	}
	return b, nil
}

func decodeRoute(raw []byte) (Route, error) {
	var r Route
	if strict(raw, MaxRouteBytes, &r) != nil || nestedObject(raw, "destination", printtransport.Destination{}) != nil || r.Version != Version || !printqueue.CanonicalUUID(r.PhysicalPrinterID) || !printqueue.CanonicalUUID(r.AliasID) || !printqueue.CanonicalUUID(r.Destination.WorkerHostID) || r.PhysicalPrinterID != r.Destination.PhysicalPrinterID || r.Destination.DocumentName != "" {
		return Route{}, ErrBinding
	}
	for _, n := range []uint64{r.RouteRevision, r.ConfigRevision, r.BindingRevision, r.RegistryRevision} {
		if !revision(n) {
			return Route{}, ErrBinding
		}
	}
	d := r.Destination
	d.DocumentName = "candidate route validation"
	if printtransport.ValidateDestination(d) != nil || !digest(r.CapabilityProfileSHA256) || SHA256(r.CapabilityProfile) != r.CapabilityProfileSHA256 {
		return Route{}, ErrBinding
	}
	return r, nil
}

func validateState(s TrustedState) error {
	if len(s.IssuerPublicKey) != ed25519.PublicKeySize || !validAuthorization(s.Authorization) || !printqueue.CanonicalUUID(s.CurrentGrantID) || !digest(s.CurrentGrantBodySHA256) || !revision(s.HighWaterGeneration) || s.Authorization.Generation != s.HighWaterGeneration || s.RevokedThroughGeneration > math.MaxInt64 || s.Now.IsZero() || s.Now.Unix() <= 0 || s.MaxLifetimeSeconds <= 0 || !validScope(s.Scope, s.ClusterID, s.MembershipSHA256) {
		return ErrState
	}
	if _, err := decodeRoute(s.RouteRaw); err != nil {
		return ErrState
	}
	return nil
}

func validatePeer(s TrustedState, peer AuthenticatedPeer) error {
	a := s.Authorization
	if peer.ClientID != a.ClientID || len(peer.CertificateDER) == 0 || len(peer.CertificateDER) > 16384 || SHA256(peer.CertificateDER) != a.ClientCertificateSHA256 {
		return ErrScope
	}
	leaf, err := x509.ParseCertificate(peer.CertificateDER)
	if err != nil || !bytes.Equal(leaf.Raw, peer.CertificateDER) || leaf.IsCA || !leaf.BasicConstraintsValid || len(leaf.ExtKeyUsage) != 1 || leaf.ExtKeyUsage[0] != x509.ExtKeyUsageClientAuth || leaf.KeyUsage&x509.KeyUsageDigitalSignature == 0 || s.Now.Before(leaf.NotBefore) || !s.Now.Before(leaf.NotAfter) || len(leaf.URIs) != 1 || len(leaf.DNSNames) != 0 || len(leaf.IPAddresses) != 0 || len(leaf.EmailAddresses) != 0 {
		return ErrScope
	}
	want := (&url.URL{Scheme: "spiffe", Host: "vynic-printer-agent", Path: "/" + a.HostID + "/" + a.ClientID}).String()
	if leaf.URIs[0].String() != want {
		return ErrScope
	}
	return nil
}

// ValidateCandidate verifies the exact signed body using the separately pinned
// issuer, then binds a complete strict v1 job to current registration and route.
// It does not verify a TLS chain, persist freshness/revocation state, execute a
// queue transaction, or authorize physical I/O. Those remain external gates.
func ValidateCandidate(signedGrantRaw []byte, current TrustedState, peer AuthenticatedPeer, frozenJobRaw []byte) (ValidatedJob, error) {
	grantRaw := bytes.Clone(signedGrantRaw)
	jobRaw := bytes.Clone(frozenJobRaw)
	current.IssuerPublicKey = bytes.Clone(current.IssuerPublicKey)
	current.RouteRaw = bytes.Clone(current.RouteRaw)
	peer.CertificateDER = bytes.Clone(peer.CertificateDER)
	if err := validateState(current); err != nil {
		return ValidatedJob{}, err
	}
	signed, err := decodeSigned(grantRaw)
	if err != nil {
		return ValidatedJob{}, err
	}
	if !ed25519.Verify(current.IssuerPublicKey, SignatureInput(signed.Body), signed.Signature) {
		return ValidatedJob{}, ErrSignature
	}
	body, err := decodeBody(signed.Body)
	if err != nil {
		return ValidatedJob{}, err
	}
	if body.Authorization.Generation <= current.RevokedThroughGeneration {
		return ValidatedJob{}, ErrRevoked
	}
	if body.Authorization.Generation != current.HighWaterGeneration {
		return ValidatedJob{}, ErrStale
	}
	if body.Authorization != current.Authorization || body.Scope != current.Scope || body.ClusterID != current.ClusterID || body.MembershipSHA256 != current.MembershipSHA256 {
		return ValidatedJob{}, ErrScope
	}
	now := current.Now.Unix()
	if body.IssuedAt <= 0 || body.NotBefore < body.IssuedAt || body.ExpiresAt <= body.NotBefore || body.ExpiresAt-body.IssuedAt > current.MaxLifetimeSeconds || body.IssuedAt > now || body.NotBefore > now || now >= body.ExpiresAt {
		return ValidatedJob{}, ErrLifetime
	}
	if body.GrantID != current.CurrentGrantID || SHA256(signed.Body) != current.CurrentGrantBodySHA256 {
		return ValidatedJob{}, ErrStale
	}
	if !bytes.Equal(body.RouteRaw, current.RouteRaw) {
		return ValidatedJob{}, ErrBinding
	}
	route, err := decodeRoute(body.RouteRaw)
	if err != nil {
		return ValidatedJob{}, err
	}
	if err := validatePeer(current, peer); err != nil {
		return ValidatedJob{}, err
	}
	job, err := printqueue.DecodeFrozenJob(jobRaw)
	if err != nil {
		return ValidatedJob{}, ErrInvalid
	}
	a := current.Authorization
	if job.VenueID != a.VenueID || job.DeviceID != a.DeviceID || job.InstallationID != a.InstallationID || job.Destination.WorkerHostID != a.HostID || job.AuthorityEpoch != a.AuthorityEpoch || job.TerminalID != a.TerminalID || job.OriginInstallationID != a.OriginInstallationID {
		return ValidatedJob{}, ErrScope
	}
	destination := job.Destination
	destination.DocumentName = ""
	if job.PhysicalPrinterID != route.PhysicalPrinterID || job.AliasID != route.AliasID || job.RouteRevision != route.RouteRevision || job.ConfigRevision != route.ConfigRevision || job.BindingRevision != route.BindingRevision || job.RegistryRevision != route.RegistryRevision || destination != route.Destination || !bytes.Equal(job.CapabilityProfile, route.CapabilityProfile) {
		return ValidatedJob{}, ErrBinding
	}
	return ValidatedJob{jobRaw: jobRaw, grantRaw: grantRaw, grantBody: bytes.Clone(signed.Body), routeRaw: bytes.Clone(body.RouteRaw), scope: body.Scope}, nil
}
