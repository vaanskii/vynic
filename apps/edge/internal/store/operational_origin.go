package store

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math"
	"strings"
	"time"
)

const OperationalProofOriginPurpose = "vynic-edge-operational-proof-origin"

// OperationalProofOriginGrant is issued by the already pinned fixture signer.
// It binds a paired terminal to one origin and one client CA independently of
// job payloads. Expiry bounds initial admission, not an execution lease.
type OperationalProofOriginGrant struct {
	Version              int    `json:"version"`
	Purpose              string `json:"purpose"`
	Mode                 string `json:"mode"`
	GrantID              string `json:"grantId"`
	VenueID              string `json:"venueId"`
	InstallationID       string `json:"installationId"`
	TerminalID           string `json:"terminalId"`
	OriginInstallationID string `json:"originInstallationId"`
	AuthorityEpoch       uint64 `json:"authorityEpoch"`
	ClientCASHA256       string `json:"clientCaSha256"`
	AuthorityGrantSHA256 string `json:"authorityGrantSha256"`
	IssuedAt             int64  `json:"issuedAt"`
	ExpiresAt            int64  `json:"expiresAt"`
}

func operationalOriginGrant(raw string, trust []byte) (OperationalProofOriginGrant, []byte, error) {
	var g OperationalProofOriginGrant
	if raw == "" || raw != strings.TrimSpace(raw) || len(raw) > 8192 {
		return g, nil, ErrOperationalAuthority
	}
	block, rest := pem.Decode(trust)
	if block == nil || block.Type != "PUBLIC KEY" || len(bytes.TrimSpace(rest)) != 0 {
		return g, nil, ErrOperationalAuthority
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	pub, ok := key.(ed25519.PublicKey)
	if err != nil || !ok {
		return g, nil, ErrOperationalAuthority
	}
	parts := strings.Split(raw, ".")
	if len(parts) != 2 {
		return g, nil, ErrOperationalAuthority
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !ed25519.Verify(pub, []byte(parts[0]), sig) {
		return g, nil, ErrOperationalAuthority
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return g, nil, ErrOperationalAuthority
	}
	if json.Unmarshal(payload, &g) != nil {
		return g, nil, ErrOperationalAuthority
	}
	canonical, err := json.Marshal(g)
	if err != nil || !bytes.Equal(canonical, payload) || g.Version != 1 || g.Purpose != OperationalProofOriginPurpose || g.Mode != OperationalProofMode || !canonicalUUID(g.GrantID) || !canonicalUUID(g.VenueID) || !canonicalUUID(g.InstallationID) || !canonicalUUID(g.TerminalID) || !canonicalUUID(g.OriginInstallationID) || g.AuthorityEpoch == 0 || g.AuthorityEpoch > math.MaxInt64 || !operationalSHA256(g.ClientCASHA256) || !operationalSHA256(g.AuthorityGrantSHA256) {
		return g, nil, ErrOperationalAuthority
	}
	signer := sha256.Sum256(block.Bytes)
	return g, signer[:], nil
}

func operationalSHA256(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size && hex.EncodeToString(decoded) == value
}

// BindOperationalProofOrigin is local fixture enrollment only. It authenticates
// the existing paired terminal and accepts only the current proof issuer. No
// server route, normal bootstrap or print envelope calls this method.
// Exact retries are retained; reissue, rotation or rebinding is refused.
func (s *Store) BindOperationalProofOrigin(ctx context.Context, auth OperationalAuth, raw string, fixtureTrustPEM []byte) error {
	g, signer, err := operationalOriginGrant(raw, fixtureTrustPEM)
	if err != nil {
		return err
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = operationalAuthenticateTerminal(ctx, tx, auth); err != nil {
		return err
	}
	a, err := operationalAuthorityRecord(ctx, tx)
	if err != nil {
		return err
	}
	if err = operationalAuthorityBinding(ctx, tx, a); err != nil {
		return err
	}
	if auth.TerminalID != g.TerminalID || g.VenueID != a.venueID || g.InstallationID != a.installationID || g.AuthorityEpoch != a.epoch || g.AuthorityGrantSHA256 != hex.EncodeToString(a.grantHash) || !bytes.Equal(signer, a.signerHash) {
		return ErrOperationalAuthority
	}
	digest := sha256.Sum256([]byte(raw))
	var previous []byte
	err = tx.QueryRowContext(ctx, "SELECT grant_hash FROM op_terminal_origin WHERE terminal_id=?", g.TerminalID).Scan(&previous)
	if err == nil {
		if !bytes.Equal(previous, digest[:]) {
			return ErrOperationalAuthority
		}
		return tx.Commit()
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	now := time.Now().Unix()
	if g.IssuedAt < 0 || g.IssuedAt > now+30 || g.ExpiresAt <= now || g.ExpiresAt <= g.IssuedAt || g.ExpiresAt-g.IssuedAt > 600 {
		return ErrOperationalAuthority
	}
	ca, _ := hex.DecodeString(g.ClientCASHA256)
	_, err = tx.ExecContext(ctx, "INSERT INTO op_terminal_origin(terminal_id,purpose,mode,grant_id,venue_id,installation_id,authority_epoch,origin_installation_id,client_ca_hash,authority_grant_hash,signer_hash,grant_hash,grant) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", g.TerminalID, g.Purpose, g.Mode, g.GrantID, g.VenueID, g.InstallationID, g.AuthorityEpoch, g.OriginInstallationID, ca, a.grantHash, signer, digest[:], []byte(raw))
	if err != nil {
		return err
	}
	return tx.Commit()
}

func operationalAuthenticateOrigin(ctx context.Context, tx *sql.Tx, auth OperationalAuth) error {
	if !canonicalUUID(auth.OriginInstallationID) || len(auth.ClientCASHA256) != sha256.Size {
		return ErrDenied
	}
	a, err := operationalAuthorityRecord(ctx, tx)
	if err != nil {
		return err
	}
	var purpose, mode, venue, installation, origin string
	var epoch uint64
	var ca, grant, signer []byte
	err = tx.QueryRowContext(ctx, "SELECT purpose,mode,venue_id,installation_id,authority_epoch,origin_installation_id,client_ca_hash,authority_grant_hash,signer_hash FROM op_terminal_origin WHERE terminal_id=?", auth.TerminalID).Scan(&purpose, &mode, &venue, &installation, &epoch, &origin, &ca, &grant, &signer)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrDenied
	}
	if err != nil {
		return err
	}
	if purpose != OperationalProofOriginPurpose || mode != OperationalProofMode || venue != a.venueID || installation != a.installationID || epoch != a.epoch || origin != auth.OriginInstallationID || !bytes.Equal(ca, auth.ClientCASHA256) || !bytes.Equal(grant, a.grantHash) || !bytes.Equal(signer, a.signerHash) {
		return ErrDenied
	}
	return nil
}
