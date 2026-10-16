package printerprovisioning

import (
	"bytes"
	"crypto/ed25519"
	"database/sql"
	"encoding/json"
	"errors"
	"time"
)

// RuntimeIdentity returns public bindings only. No credential is exported.
func (s *ProductionStore) RuntimeIdentity() (string, string, ed25519.PublicKey) {
	return s.id, s.device, bytes.Clone(s.issuer)
}
func (p AuthenticatedMember) InstallationID() string { return p.installation }
func (p AuthenticatedMember) DeviceID() string       { return p.device }

// CurrentGrant revalidates expiry, revocation and durable time before exporting
// an exact signed snapshot for the replicated configuration journal.
func (s *ProductionStore) CurrentGrant() ([]byte, error) {
	if _, e := s.current(); e != nil {
		return nil, e
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var raw []byte
	e := s.db.QueryRow("SELECT grant FROM authorization WHERE singleton=1").Scan(&raw)
	return raw, e
}

// ReserveQueue prevents a lost queue directory from silently bootstrapping a
// replacement cluster under a retained installation identity. Failure during
// initial creation fails closed and requires explicit recovery, never deletion.
func (s *ProductionStore) ReserveQueue(cluster, path string, fresh bool) error {
	if _, e := s.current(); e != nil {
		return e
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, e := s.db.Exec("CREATE TABLE IF NOT EXISTS runtime_queue (cluster TEXT PRIMARY KEY,path TEXT NOT NULL)"); e != nil {
		return e
	}
	var old string
	e := s.db.QueryRow("SELECT path FROM runtime_queue WHERE cluster=?", cluster).Scan(&old)
	if e == nil {
		if old != path || fresh {
			return ErrState
		}
		return nil
	}
	if !errors.Is(e, sql.ErrNoRows) {
		return e
	}
	// Only a new, explicitly owned queue may reserve a new marker.
	if !fresh {
		return ErrState
	}
	_, e = s.db.Exec("INSERT INTO runtime_queue VALUES(?,?)", cluster, path)
	return e
}

// VerifyHistoricalProduction is only for replay of an already committed
// configuration log. It does not grant live authority; every network operation
// still checks ProductionStore at the current time.
func VerifyHistoricalProduction(raw []byte, issuer ed25519.PublicKey) (ProductionBody, error) {
	var g SignedGrant
	var b ProductionBody
	if strict(raw, MaxProductionGrant, &g) != nil || json.Unmarshal(g.Body, &b) != nil {
		return b, ErrInvalid
	}
	return VerifyProduction(raw, issuer, time.Unix(b.IssuedAt, 0))
}
func CheckProductionEvolution(old, next ProductionBody) error { return checkEvolution(old, next) }
