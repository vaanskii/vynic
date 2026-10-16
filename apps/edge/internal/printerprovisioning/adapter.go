package printerprovisioning

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"

	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/printqueue"
)

// Validator adapts validation to the optional held local server seam. Each
// invocation reads fresh trusted state. Construction has no storage, clock,
// certificate generation, network, queue or current-state side effects.
type Validator struct {
	grantRaw []byte
	read     ReadTrustedState
}

func NewValidator(signedGrantRaw []byte, read ReadTrustedState) (*Validator, error) {
	if read == nil {
		return nil, ErrState
	}
	if _, err := decodeSigned(signedGrantRaw); err != nil {
		return nil, err
	}
	return &Validator{grantRaw: bytes.Clone(signedGrantRaw), read: read}, nil
}

func (v *Validator) Validate(ctx context.Context, peer AuthenticatedPeer, pins printhost.Pins, job printqueue.FrozenJob) error {
	if v == nil || v.read == nil {
		return ErrState
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	current, err := v.read(ctx)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrState, err)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	bound, err := ValidateCandidate(v.grantRaw, current, peer, job.Raw())
	if err != nil {
		return err
	}
	frozen, err := bound.FrozenJob()
	if err != nil {
		return ErrInvalid
	}
	left, err := json.Marshal(job)
	if err != nil {
		return ErrInvalid
	}
	right, err := json.Marshal(frozen)
	if err != nil || !bytes.Equal(left, right) || job.Digest() != frozen.Digest() {
		return ErrInvalid
	}
	if pins.Validate() != nil || string(pins.Scope) != string(current.Scope) || pins.ClusterID != current.ClusterID || pins.MembershipSHA256 != current.MembershipSHA256 || pins.VenueID != current.Authorization.VenueID || pins.InstallationID != current.Authorization.InstallationID || pins.DeviceID != current.Authorization.DeviceID || pins.HostID != current.Authorization.HostID || pins.AuthorityEpoch != current.Authorization.AuthorityEpoch || pins.RouteRevision != frozen.RouteRevision || pins.ConfigRevision != frozen.ConfigRevision || pins.RegistryRevision != frozen.RegistryRevision || pins.BindingRevision != frozen.BindingRevision || pins.CapabilityProfileSHA256 != SHA256(frozen.CapabilityProfile) {
		return ErrBinding
	}
	return nil
}
