package store

import "context"

// OperationalProofInfo describes an already pinned isolated proof. It neither
// pins a grant nor authorizes production work or physical effect dispatch.
type OperationalProofInfo struct {
	Mode           string
	InstallationID string
	VenueID        string
	AuthorityEpoch uint64
	HeadSequence   uint64
	GrantSHA256    []byte
}

// PinnedOperationalProofInfo is a local fixture-construction precondition. It
// has no RPC registration or unauthenticated network counterpart.
func (s *Store) PinnedOperationalProofInfo(ctx context.Context) (*OperationalProofInfo, error) {
	return s.operationalProofInfo(ctx, nil)
}

// OperationalProofStatus authenticates the current active terminal within the
// same consistent transaction as authority, immutable binding and head reads.
func (s *Store) OperationalProofStatus(ctx context.Context, auth OperationalAuth) (*OperationalProofInfo, error) {
	return s.operationalProofInfo(ctx, &auth)
}

func (s *Store) operationalProofInfo(ctx context.Context, auth *OperationalAuth) (*OperationalProofInfo, error) {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if auth != nil {
		if err = operationalAuthenticate(ctx, tx, *auth); err != nil {
			return nil, err
		}
	}
	a, err := operationalAuthorityRecord(ctx, tx)
	if err != nil {
		return nil, err
	}
	if err = operationalAuthorityBinding(ctx, tx, a); err != nil {
		return nil, err
	}
	result := &OperationalProofInfo{
		Mode: OperationalProofMode, InstallationID: a.installationID,
		VenueID: a.venueID, AuthorityEpoch: a.epoch, HeadSequence: a.head,
		GrantSHA256: append([]byte(nil), a.grantHash...),
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}
