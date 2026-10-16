// Package printhost composes one printer host lifecycle. It installs no service,
// grants no operational authority, and supplies no physical activation path.
package printhost

import (
	"encoding/hex"
	"errors"
	"fmt"
	"math"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
	"vynic.local/edge/internal/store"
)

const ProtocolVersion uint32 = 1
const ReaderVersion uint32 = 2

type Role string

const (
	POSAgent     Role = "posAgent"
	PrintGateway Role = "printGateway"
)

type Scope string

const (
	Local       Scope = "LOCAL"
	VenueShared Scope = "VENUE_SHARED"
)

type OwnershipPolicy string

const (
	LocalHost          OwnershipPolicy = "localHost"
	QualifiedGateway   OwnershipPolicy = "qualifiedGateway"
	ClusterLogicalOnly OwnershipPolicy = "clusterLogicalOnly"
)

var (
	ErrUnavailable     = errors.New("printer host unavailable")
	ErrVersionMismatch = errors.New("printer host version mismatch")
	ErrBindingMismatch = errors.New("printer host binding mismatch")
	ErrRole            = errors.New("printer host role refused")
	ErrHeld            = errors.New("printer host held for reconciliation")
	ErrAlreadyRunning  = errors.New("printer host already started")
)

// Pins come from trusted installation/configuration evidence, never a job or
// unauthenticated health response. They are values without mutable references.
// Digests bind the exact qualified host/helper artifacts and profile; they do
// not prove signatures, account access, authentication or physical capability.
type Pins struct {
	Scope                   Scope           `json:"scope"`
	OwnershipPolicy         OwnershipPolicy `json:"ownershipPolicy"`
	ClusterID               string          `json:"clusterId"`
	MembershipSHA256        string          `json:"membershipSha256"`
	Role                    Role            `json:"role"`
	VenueID                 string          `json:"venueId"`
	InstallationID          string          `json:"installationId"`
	DeviceID                string          `json:"deviceId"`
	HostID                  string          `json:"hostId"`
	GatewayHostID           string          `json:"gatewayHostId"`
	AuthorityEpoch          uint64          `json:"authorityEpoch"`
	ProtocolVersion         uint32          `json:"protocolVersion"`
	HelperProtocolVersion   uint16          `json:"helperProtocolVersion"`
	DatabaseSchemaVersion   uint32          `json:"databaseSchemaVersion"`
	MinimumReaderVersion    uint32          `json:"minimumReaderVersion"`
	RouteRevision           uint64          `json:"routeRevision"`
	ConfigRevision          uint64          `json:"configRevision"`
	RegistryRevision        uint64          `json:"registryRevision"`
	BindingRevision         uint64          `json:"bindingRevision"`
	CapabilityRevision      uint64          `json:"capabilityRevision"`
	CapabilityProfileSHA256 string          `json:"capabilityProfileSha256"`
	HostBinarySHA256        string          `json:"hostBinarySha256"`
	HelperBinarySHA256      string          `json:"helperBinarySha256"`
}

func digest(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, c := range value {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func (p Pins) Validate() error {
	if p.Role != POSAgent && p.Role != PrintGateway {
		return ErrRole
	}
	for _, id := range []string{p.VenueID, p.InstallationID, p.DeviceID, p.HostID} {
		if !printqueue.CanonicalUUID(id) {
			return fmt.Errorf("%w: noncanonical identity", ErrBindingMismatch)
		}
	}
	for _, revision := range []uint64{p.AuthorityEpoch, p.RouteRevision, p.ConfigRevision, p.RegistryRevision, p.BindingRevision, p.CapabilityRevision} {
		if revision == 0 || revision > math.MaxInt64 {
			return fmt.Errorf("%w: invalid revision", ErrBindingMismatch)
		}
	}
	if p.ProtocolVersion != ProtocolVersion || p.HelperProtocolVersion != printtransport.HelperProtocolVersion || p.DatabaseSchemaVersion != store.SchemaVersion || p.MinimumReaderVersion != ReaderVersion {
		return ErrVersionMismatch
	}
	for _, value := range []string{p.CapabilityProfileSHA256, p.HostBinarySHA256, p.HelperBinarySHA256} {
		if !digest(value) {
			return fmt.Errorf("%w: invalid artifact/profile digest", ErrBindingMismatch)
		}
	}
	switch p.Scope {
	case Local:
		if p.OwnershipPolicy != LocalHost || p.GatewayHostID != p.HostID || p.ClusterID != "" || p.MembershipSHA256 != "" {
			return ErrBindingMismatch
		}
	case VenueShared:
		if !printqueue.CanonicalUUID(p.ClusterID) || !digest(p.MembershipSHA256) {
			return ErrBindingMismatch
		}
		switch p.OwnershipPolicy {
		case ClusterLogicalOnly:
			if p.GatewayHostID != "" {
				return ErrBindingMismatch
			}
		case QualifiedGateway:
			if !printqueue.CanonicalUUID(p.GatewayHostID) {
				return ErrBindingMismatch
			}
		default:
			return ErrBindingMismatch
		}
	default:
		return ErrBindingMismatch
	}
	return nil
}

// ComparePins holds a stale reader, changed artifact/profile and every changed
// configuration revision. A caller must perform an explicit compatible upgrade
// and construct a new host; this never rewrites state or promotes a new owner.
func ComparePins(expected, observed Pins, reader uint32) error {
	if err := expected.Validate(); err != nil {
		return err
	}
	if err := observed.Validate(); err != nil {
		return err
	}
	if reader < expected.MinimumReaderVersion || observed.ProtocolVersion != expected.ProtocolVersion || observed.HelperProtocolVersion != expected.HelperProtocolVersion || observed.DatabaseSchemaVersion != expected.DatabaseSchemaVersion || observed.MinimumReaderVersion != expected.MinimumReaderVersion || observed.HostBinarySHA256 != expected.HostBinarySHA256 || observed.HelperBinarySHA256 != expected.HelperBinarySHA256 {
		return ErrVersionMismatch
	}
	if observed != expected {
		return ErrBindingMismatch
	}
	return nil
}

type State string

const (
	New      State = "new"
	Starting State = "starting"
	Running  State = "running"
	Draining State = "draining"
	Stopped  State = "stopped"
	Held     State = "held"
)

// Evidence must be captured by the trusted composition after exclusive queue
// recovery. STARTED attempts become UNCERTAIN in printqueue, never replayed here.
type Evidence struct {
	Pins             Pins
	RecoveryComplete bool
	BlockedReason    string
	PrinterHolds     []PrinterHold
}

type PrinterHold struct {
	PhysicalPrinterID string `json:"physicalPrinterId"`
	Reason            string `json:"reason"`
}

type Health struct {
	Version uint32 `json:"version"`
	Pins    Pins   `json:"pins"`
	State   State  `json:"state"`
	// Ready means admission to the bounded durable queue, not paper delivery
	// or readiness to upgrade; affected-printer holds remain visible below.
	Ready            bool          `json:"ready"`
	ActiveAdmissions uint64        `json:"activeAdmissions"`
	BlockedReason    string        `json:"blockedReason"`
	PrinterHolds     []PrinterHold `json:"printerHolds"`
}

// CheckHealth is read-only client admission. Flutter may report the returned
// refusal; it gains neither a replacement writer nor SCM permissions.
func CheckHealth(expected Pins, observed Health, reader uint32) error {
	if observed.Version != ProtocolVersion {
		return ErrVersionMismatch
	}
	if err := ComparePins(expected, observed.Pins, reader); err != nil {
		return err
	}
	if observed.State != Running {
		return ErrUnavailable
	}
	if !observed.Ready {
		return ErrUnavailable
	}
	return nil
}

// CheckUpgrade is a readiness observation. A future installer still needs its
// own admission freeze and retained ownership through replacement/attestation.
func CheckUpgrade(expected Pins, observed Health, reader uint32) error {
	if err := CheckHealth(expected, observed, reader); err != nil {
		return err
	}
	if observed.ActiveAdmissions != 0 || observed.BlockedReason != "" || len(observed.PrinterHolds) != 0 {
		return fmt.Errorf("%w: admitted operation or retained printer hold has not settled", ErrHeld)
	}
	return nil
}
