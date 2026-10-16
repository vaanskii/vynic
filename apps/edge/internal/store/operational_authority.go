package store

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math"
	"strings"
	"time"
)

const OperationalProofPurpose = "vynic-edge-operational-proof"
const OperationalProofMode = "ISOLATED_PROOF"

var ErrOperationalAuthority = errors.New("isolated proof authority absent, incompatible or changed")
var ErrOperationalEpoch = errors.New("wrong isolated proof authority epoch")
var ErrOperationalIntent = errors.New("invalid isolated operational intent")
var ErrOperationalCapacity = errors.New("isolated operational proof capacity reached")
var ErrOperationalCorrupt = errors.New("isolated operational proof record is inconsistent")
var ErrOperationalResultNotFound = errors.New("isolated operational result not found for terminal")

// OperationalProofGrant is a fixture-signed, immutable admission grant. It is
// separate from foundation binding and grants no Cloud or production authority.
// Admission expiry is not an execution lease; this proof has no lease renewal,
// authority rotation, automatic failover, promotion or production cutover API.
type OperationalProofGrant struct {
	Version        int    `json:"version"`
	Purpose        string `json:"purpose"`
	Mode           string `json:"mode"`
	GrantID        string `json:"grantId"`
	InstallationID string `json:"installationId"`
	VenueID        string `json:"venueId"`
	PublicKey      string `json:"publicKey"`
	AuthorityEpoch uint64 `json:"authorityEpoch"`
	IssuedAt       int64  `json:"issuedAt"`
	ExpiresAt      int64  `json:"expiresAt"`
}

type OperationalAuth struct {
	TerminalID     string
	TerminalSecret string
	// These are supplied only from a freshly verified proof certificate and
	// checked against the immutable signed origin registration in the SQL tx.
	OriginInstallationID string
	ClientCASHA256       []byte
}

type operationalAuthority struct {
	installationID string
	venueID        string
	publicKey      string
	epoch          uint64
	head           uint64
	grantHash      []byte
	signerHash     []byte
	bindingHash    []byte
}

// PinOperationalProofAuthority requires an explicitly supplied isolated fixture
// trust key. Nothing calls this method from the normal server or bootstrap.
// Reusing the exact grant/key is idempotent; any changed grant/key is refused,
// including an apparently newer epoch. Foundation binding is frozen with it.
func (s *Store) PinOperationalProofAuthority(ctx context.Context, raw string, fixtureTrustPEM []byte) error {
	if raw == "" || raw != strings.TrimSpace(raw) || len(raw) > 8192 {
		return ErrOperationalAuthority
	}
	block, rest := pem.Decode(fixtureTrustPEM)
	if block == nil || block.Type != "PUBLIC KEY" || len(bytes.TrimSpace(rest)) != 0 {
		return ErrOperationalAuthority
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return ErrOperationalAuthority
	}
	pub, ok := key.(ed25519.PublicKey)
	if !ok {
		return ErrOperationalAuthority
	}
	parts := strings.Split(raw, ".")
	if len(parts) != 2 {
		return ErrOperationalAuthority
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !ed25519.Verify(pub, []byte(parts[0]), sig) {
		return ErrOperationalAuthority
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return ErrOperationalAuthority
	}
	var g OperationalProofGrant
	if err = json.Unmarshal(payload, &g); err != nil {
		return ErrOperationalAuthority
	}
	canonical, err := json.Marshal(g)
	// Exact canonical grant encoding rejects duplicate/unknown fields and keeps
	// the signed fixture contract unambiguous without generated wire contracts.
	if err != nil || !bytes.Equal(canonical, payload) || g.Version != 1 || g.Purpose != OperationalProofPurpose || g.Mode != OperationalProofMode || !canonicalUUID(g.GrantID) || !canonicalUUID(g.InstallationID) || !canonicalUUID(g.VenueID) || g.AuthorityEpoch == 0 || g.AuthorityEpoch > math.MaxInt64 {
		return ErrOperationalAuthority
	}
	grantHash := sha256.Sum256([]byte(raw))
	signerHash := sha256.Sum256(block.Bytes)
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	installation, venue, publicKey, binding, err := operationalBinding(ctx, tx)
	if err != nil {
		return err
	}
	if g.InstallationID != installation || g.VenueID != venue || g.PublicKey != publicKey {
		return ErrOperationalAuthority
	}
	bindingHash := sha256.Sum256([]byte(binding))
	var previousGrant, previousSigner, previousBinding []byte
	err = tx.QueryRowContext(ctx, "SELECT grant_hash,signer_hash,binding_hash FROM op_authority WHERE singleton=1").Scan(&previousGrant, &previousSigner, &previousBinding)
	if err == nil {
		if !bytes.Equal(previousGrant, grantHash[:]) || !bytes.Equal(previousSigner, signerHash[:]) || !bytes.Equal(previousBinding, bindingHash[:]) {
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
	_, err = tx.ExecContext(ctx, "INSERT INTO op_authority(singleton,purpose,mode,installation_id,venue_id,public_key,authority_epoch,grant_hash,grant,signer_hash,binding_hash,sequence) VALUES(1,?,?,?,?,?,?,?,?,?,?,0)", g.Purpose, g.Mode, installation, venue, publicKey, g.AuthorityEpoch, grantHash[:], []byte(raw), signerHash[:], bindingHash[:])
	if err != nil {
		return err
	}
	return tx.Commit()
}

func operationalBinding(ctx context.Context, tx *sql.Tx) (installation, venue, publicKey, binding string, err error) {
	var v, b sql.NullString
	err = tx.QueryRowContext(ctx, "SELECT id,venue_id,public_key,binding_grant FROM installation WHERE singleton=1").Scan(&installation, &v, &publicKey, &b)
	if errors.Is(err, sql.ErrNoRows) {
		err = ErrOperationalAuthority
	}
	if err != nil {
		return
	}
	venue, binding = v.String, b.String
	if !canonicalUUID(installation) || !canonicalUUID(venue) || !ValidSecret(publicKey) || !v.Valid || !b.Valid || binding == "" {
		err = ErrOperationalAuthority
	}
	return
}

func operationalAuthenticateTerminal(ctx context.Context, tx *sql.Tx, auth OperationalAuth) error {
	if !canonicalUUID(auth.TerminalID) || !ValidSecret(auth.TerminalSecret) {
		return ErrDenied
	}
	var verifier string
	var revoked sql.NullInt64
	err := tx.QueryRowContext(ctx, "SELECT verifier,revoked_at FROM terminal WHERE id=?", auth.TerminalID).Scan(&verifier, &revoked)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrDenied
	}
	if err != nil {
		return err
	}
	if revoked.Valid || subtle.ConstantTimeCompare([]byte(verifier), []byte(Hash(auth.TerminalSecret))) != 1 {
		return ErrDenied
	}
	return nil
}

func operationalAuthenticate(ctx context.Context, tx *sql.Tx, auth OperationalAuth) error {
	if err := operationalAuthenticateTerminal(ctx, tx, auth); err != nil {
		return err
	}
	if auth.OriginInstallationID != "" || len(auth.ClientCASHA256) != 0 {
		return operationalAuthenticateOrigin(ctx, tx, auth)
	}
	return nil
}

func operationalState(ctx context.Context, tx *sql.Tx, auth OperationalAuth, epoch uint64) (operationalAuthority, error) {
	var a operationalAuthority
	// The credential is rechecked inside the same SQLite transaction as the
	// business commit/result lookup. A previous transport check cannot authorize it.
	if err := operationalAuthenticate(ctx, tx, auth); err != nil {
		return a, err
	}
	a, err := operationalAuthorityRecord(ctx, tx)
	if err != nil {
		return a, err
	}
	if epoch == 0 || epoch > math.MaxInt64 || a.epoch != epoch {
		return a, ErrOperationalEpoch
	}
	if err = operationalAuthorityBinding(ctx, tx, a); err != nil {
		return a, err
	}
	return a, nil
}

func operationalAuthorityRecord(ctx context.Context, tx *sql.Tx) (operationalAuthority, error) {
	var a operationalAuthority
	var purpose, mode string
	err := tx.QueryRowContext(ctx, "SELECT purpose,mode,installation_id,venue_id,public_key,authority_epoch,sequence,grant_hash,signer_hash,binding_hash FROM op_authority WHERE singleton=1").Scan(&purpose, &mode, &a.installationID, &a.venueID, &a.publicKey, &a.epoch, &a.head, &a.grantHash, &a.signerHash, &a.bindingHash)
	if errors.Is(err, sql.ErrNoRows) {
		return a, ErrOperationalAuthority
	}
	if err != nil {
		return a, err
	}
	if purpose != OperationalProofPurpose || mode != OperationalProofMode {
		return a, ErrOperationalAuthority
	}
	if a.epoch == 0 || a.epoch > math.MaxInt64 || a.head > math.MaxInt64 || len(a.grantHash) != sha256.Size || len(a.signerHash) != sha256.Size || len(a.bindingHash) != sha256.Size {
		return a, ErrOperationalCorrupt
	}
	return a, nil
}

func operationalAuthorityBinding(ctx context.Context, tx *sql.Tx, a operationalAuthority) error {
	installation, venue, publicKey, binding, err := operationalBinding(ctx, tx)
	if err != nil {
		return err
	}
	bindingHash := sha256.Sum256([]byte(binding))
	if installation != a.installationID || venue != a.venueID || publicKey != a.publicKey || !bytes.Equal(a.bindingHash, bindingHash[:]) {
		return ErrOperationalAuthority
	}
	return nil
}
