// Package printerprovisioning validates printer-only candidate grants against
// separately trusted current state. It issues no grant, stores no high-water
// mark, admits no job, and never upgrades Foundation or ISOLATED_PROOF authority.
package printerprovisioning

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
)

const (
	Version         = 1
	Purpose         = "VYNIC_PRINTER_ONLY_CANDIDATE"
	SignatureDomain = "vynic/printer-provisioning/candidate/v1\x00"
	MaxGrantBytes   = 256 << 10
	MaxBodyBytes    = 96 << 10
	MaxRouteBytes   = 80 << 10
	AdmissionHold   = "HELD_PROVISIONING: candidate validation does not enable production admission"
)

type Scope string

const (
	Local       Scope = "LOCAL"
	VenueShared Scope = "VENUE_SHARED"
)

var (
	ErrInvalid   = errors.New("invalid printer candidate grant")
	ErrSignature = errors.New("printer candidate signature refused")
	ErrScope     = errors.New("printer candidate authority mismatch")
	ErrStale     = errors.New("printer candidate authorization generation differs")
	ErrRevoked   = errors.New("printer candidate authorization revoked")
	ErrLifetime  = errors.New("printer candidate lifetime refused")
	ErrBinding   = errors.New("printer candidate route binding differs")
	ErrState     = errors.New("trusted current printer state unavailable")
)

// Authorization is a complete current registration supplied by the server.
// ClientID names the authenticated observation pin; TerminalID and Origin are
// separately registered identities, never inferred from a client job or URI.
type Authorization struct {
	VenueID                 string `json:"venueId"`
	DeviceID                string `json:"deviceId"`
	InstallationID          string `json:"installationId"`
	HostID                  string `json:"hostId"`
	AuthorityEpoch          uint64 `json:"authorityEpoch"`
	TerminalID              string `json:"terminalId"`
	OriginInstallationID    string `json:"originInstallationId"`
	ClientID                string `json:"clientId"`
	ClientCertificateSHA256 string `json:"clientCertificateSha256"`
	Generation              uint64 `json:"generation"`
}

// Route retains one explicit alias of one physical printer. Destination has
// the registry's empty DocumentName; the strict frozen job retains its own
// immutable document label, primary bytes (including cut), and exact digest.
// Endpoint spelling and profile JSON bytes must match exactly; this validator
// neither discovers aliases nor retargets equivalent IP/queue spellings.
type Route struct {
	Version                 uint32                     `json:"version"`
	PhysicalPrinterID       string                     `json:"physicalPrinterId"`
	AliasID                 string                     `json:"aliasId"`
	RouteRevision           uint64                     `json:"routeRevision"`
	ConfigRevision          uint64                     `json:"configRevision"`
	BindingRevision         uint64                     `json:"bindingRevision"`
	RegistryRevision        uint64                     `json:"registryRevision"`
	Destination             printtransport.Destination `json:"destination"`
	CapabilityProfile       json.RawMessage            `json:"capabilityProfile"`
	CapabilityProfileSHA256 string                     `json:"capabilityProfileSha256"`
}

// SignedGrant carries base64 raw body bytes and one Ed25519 signature. The
// issuer key is deliberately absent. Sign SignatureInput(body), not a
// reserialized JSON object; byte reordering changes the signed digest.
type SignedGrant struct {
	Body      []byte `json:"body"`
	Signature []byte `json:"signature"`
}

type GrantBody struct {
	Version          uint32        `json:"version"`
	Purpose          string        `json:"purpose"`
	GrantID          string        `json:"grantId"`
	Authorization    Authorization `json:"authorization"`
	IssuedAt         int64         `json:"issuedAt"`
	NotBefore        int64         `json:"notBefore"`
	ExpiresAt        int64         `json:"expiresAt"`
	Scope            Scope         `json:"scope"`
	ClusterID        string        `json:"clusterId"`
	MembershipSHA256 string        `json:"membershipSha256"`
	RouteRaw         []byte        `json:"routeRaw"`
	RouteSHA256      string        `json:"routeSha256"`
}

// TrustedState must come from a server-owned current registration, trusted
// clock and pinned issuer configuration, independently of SignedGrant. Exact
// current generation must equal the persisted high-water mark; no storage or
// cache here can establish rollback resistance. RevokedThroughGeneration=0
// means no revoked generation. Lifetime policy has no implicit default.
type TrustedState struct {
	IssuerPublicKey          ed25519.PublicKey
	Authorization            Authorization
	CurrentGrantID           string
	CurrentGrantBodySHA256   string
	HighWaterGeneration      uint64
	RevokedThroughGeneration uint64
	Scope                    Scope
	ClusterID                string
	MembershipSHA256         string
	RouteRaw                 []byte
	Now                      time.Time
	MaxLifetimeSeconds       int64
}

// AuthenticatedPeer must be captured from freshly verified, currently pinned
// mutual TLS. This package checks purpose/validity/DER identity, but is not a
// replacement for chain verification or authoritative terminal registration.
type AuthenticatedPeer struct {
	ClientID       string
	CertificateDER []byte
}

type ReadTrustedState func(context.Context) (TrustedState, error)

func SHA256(raw []byte) string {
	h := sha256.Sum256(raw)
	return hex.EncodeToString(h[:])
}

func SignatureInput(body []byte) []byte {
	h := sha256.Sum256(body)
	return append([]byte(SignatureDomain), h[:]...)
}

// ValidatedJob is an immutable validation-only artifact. It has no queue
// receipt, print authority conversion, transport, or production activation.
type ValidatedJob struct {
	jobRaw    []byte
	grantRaw  []byte
	grantBody []byte
	routeRaw  []byte
	scope     Scope
}

func (v ValidatedJob) Raw() []byte                    { return bytes.Clone(v.jobRaw) }
func (v ValidatedJob) GrantRaw() []byte               { return bytes.Clone(v.grantRaw) }
func (v ValidatedJob) RouteRaw() []byte               { return bytes.Clone(v.routeRaw) }
func (v ValidatedJob) Digest() string                 { return SHA256(v.jobRaw) }
func (v ValidatedJob) GrantBodySHA256() string        { return SHA256(v.grantBody) }
func (v ValidatedJob) RouteSHA256() string            { return SHA256(v.routeRaw) }
func (v ValidatedJob) Scope() Scope                   { return v.scope }
func (v ValidatedJob) AdmissionBlockedReason() string { return AdmissionHold }
func (v ValidatedJob) FrozenJob() (printqueue.FrozenJob, error) {
	return printqueue.DecodeFrozenJob(v.jobRaw)
}
