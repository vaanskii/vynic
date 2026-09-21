package store

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"time"
)

var ErrDenied = errors.New("invalid or revoked credential")
var ErrConflict = errors.New("pairing or session identity conflicts")

func (s *Store) IssueTicket() (string, error) {
	id, err := s.Identity()
	if err != nil {
		return "", err
	}
	if id.VenueID == "" {
		return "", errors.New("installation not bound")
	}
	token := Secret()
	_, err = s.DB.Exec("INSERT INTO pairing_ticket(verifier,expires_at) VALUES(?,?)", Hash(token), time.Now().Add(10*time.Minute).Unix())
	return token, err
}

// Pair commits consumption and identity together. A lost response retries the
// same client-persisted secret/request rather than issuing another credential.
func (s *Store) Pair(ctx context.Context, ticket, requestID, terminalID, secret, name string) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var expiry int64
	var oldRequest, oldTerminal, digest sql.NullString
	err = tx.QueryRowContext(ctx, "SELECT expires_at,request_id,terminal_id,request_digest FROM pairing_ticket WHERE verifier=?", Hash(ticket)).Scan(&expiry, &oldRequest, &oldTerminal, &digest)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrDenied
	}
	if err != nil {
		return err
	}
	canonical, _ := json.Marshal([]string{requestID, terminalID, Hash(secret), name})
	fingerprint := Hash(string(canonical))
	if oldRequest.Valid {
		if oldRequest.String != requestID || oldTerminal.String != terminalID || digest.String != fingerprint {
			return ErrConflict
		}
		var revoked sql.NullInt64
		if err = tx.QueryRowContext(ctx, "SELECT revoked_at FROM terminal WHERE id=?", terminalID).Scan(&revoked); err != nil {
			return err
		}
		if revoked.Valid {
			return ErrDenied
		}
		return tx.Commit()
	}
	if expiry <= time.Now().Unix() {
		return ErrDenied
	}
	var exists int
	if err = tx.QueryRowContext(ctx, "SELECT (SELECT count(*) FROM terminal WHERE id=?) + (SELECT count(*) FROM pairing_ticket WHERE request_id=?)", terminalID, requestID).Scan(&exists); err != nil {
		return err
	}
	if exists > 0 {
		return ErrConflict
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO terminal(id,display_name,verifier,created_at) VALUES(?,?,?,?)", terminalID, name, Hash(secret), time.Now().Unix())
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, "UPDATE pairing_ticket SET request_id=?,terminal_id=?,request_digest=? WHERE verifier=?", requestID, terminalID, fingerprint, Hash(ticket))
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Store) Authenticate(ctx context.Context, terminalID, secret string) error {
	var verifier string
	var revoked sql.NullInt64
	err := s.DB.QueryRowContext(ctx, "SELECT verifier,revoked_at FROM terminal WHERE id=?", terminalID).Scan(&verifier, &revoked)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrDenied
	}
	if err != nil {
		return err
	}
	if revoked.Valid || subtle.ConstantTimeCompare([]byte(verifier), []byte(Hash(secret))) != 1 {
		return ErrDenied
	}
	return nil
}
func (s *Store) Session(ctx context.Context, terminalID, sessionID, version, bootID string) error {
	now := time.Now().Unix()
	res, err := s.DB.ExecContext(ctx, `INSERT INTO session(id,terminal_id,client_version,created_at,last_seen_at,last_boot_id) VALUES(?,?,?,?,?,?)
 ON CONFLICT(id) DO UPDATE SET last_seen_at=excluded.last_seen_at,last_boot_id=excluded.last_boot_id
 WHERE session.terminal_id=excluded.terminal_id AND session.client_version=excluded.client_version`, sessionID, terminalID, version, now, now, bootID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return ErrConflict
	}
	return nil
}
func (s *Store) Revoke(terminalID string) error {
	res, err := s.DB.Exec("UPDATE terminal SET revoked_at=COALESCE(revoked_at,?) WHERE id=?", time.Now().Unix(), terminalID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return ErrDenied
	}
	return nil
}
