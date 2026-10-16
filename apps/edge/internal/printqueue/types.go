// Package printqueue is an isolated durable gateway queue for already rendered
// bytes. It supplies no business planner, authority discovery or physical
// activation. Transport submission does not establish paper delivery.
package printqueue

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"strconv"
	"strings"

	"vynic.local/edge/internal/printtransport"
)

const AdmissionMode = "vynic-print-queue.v1"
const MaxEnvelopeBytes = 12 * 1024 * 1024

var (
	ErrInvalid           = errors.New("invalid frozen print job")
	ErrScope             = errors.New("print authority mismatch")
	ErrReuse             = errors.New("immutable print identity reused")
	ErrBinding           = errors.New("frozen printer binding mismatch")
	ErrBusy              = errors.New("printer has unresolved work")
	ErrCapacity          = errors.New("print queue capacity exceeded")
	ErrSchema            = errors.New("print queue schema unavailable")
	ErrActivationPending = errors.New("physical print activation pending")
)

// Authority is provided by an authenticated, transaction-validated caller.
// It is never constructed by trusting FrozenJob's tenant/host fields. Remote
// committed-effect authentication and replicated host fencing remain gates.
type Authority struct {
	VenueID              string
	InstallationID       string
	OriginInstallationID string
	TerminalID           string
	Epoch                uint64
}

// FrozenJob is the versioned relay envelope. All IDs are explicit canonical
// lowercase UUIDs; revisions are positive JSON integers <= MaxInt64. Relays
// retain Raw() verbatim so the gateway's exact-byte retry digest stays stable.
// PrimaryBytes include the rendered header and cut. No arbitrary beep bytes
// are accepted. Construction is exclusively through DecodeFrozenJob.
type FrozenJob struct {
	Version              uint32                     `json:"version"`
	JobID                string                     `json:"jobId"`
	EffectID             string                     `json:"effectId"`
	RequestID            string                     `json:"requestId"`
	TerminalID           string                     `json:"terminalId"`
	VenueID              string                     `json:"venueId"`
	InstallationID       string                     `json:"installationId"`
	OriginInstallationID string                     `json:"originInstallationId"`
	AuthorityEpoch       uint64                     `json:"authorityEpoch"`
	DeviceID             string                     `json:"deviceId"`
	PhysicalPrinterID    string                     `json:"physicalPrinterId"`
	AliasID              string                     `json:"aliasId"`
	RouteRevision        uint64                     `json:"routeRevision"`
	ConfigRevision       uint64                     `json:"configRevision"`
	BindingRevision      uint64                     `json:"bindingRevision"`
	RegistryRevision     uint64                     `json:"registryRevision"`
	AttemptID            string                     `json:"attemptId"`
	BeepAttemptID        string                     `json:"beepAttemptId"`
	Destination          printtransport.Destination `json:"destination"`
	CapabilityProfile    json.RawMessage            `json:"capabilityProfile"`
	PrimaryBytes         []byte                     `json:"primaryBytes"`
	PrimarySHA256        string                     `json:"primarySha256"`
	raw                  []byte
	digest               string
}

func (j FrozenJob) Raw() []byte    { return bytes.Clone(j.raw) }
func (j FrozenJob) Digest() string { return j.digest }

func CanonicalUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, c := range s {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return false
			}
		} else if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return s != "00000000-0000-0000-0000-000000000000"
}

func boundedRevision(n uint64) bool { return n > 0 && n <= math.MaxInt64 }

func exactKeys(fields map[string]json.RawMessage, keys []string) bool {
	if len(fields) != len(keys) {
		return false
	}
	for _, key := range keys {
		value, ok := fields[key]
		if !ok || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return false
		}
	}
	return true
}

// Reject duplicate keys at every level: encoding/json alone keeps the last
// value, which would give different language decoders different identities.
func uniqueJSON(d *json.Decoder, depth int) error {
	if depth > 32 {
		return ErrInvalid
	}
	token, err := d.Token()
	if err != nil {
		return err
	}
	delim, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	switch delim {
	case '{':
		seen := make(map[string]bool)
		for d.More() {
			key, err := d.Token()
			if err != nil {
				return err
			}
			name, ok := key.(string)
			if !ok || seen[name] {
				return ErrInvalid
			}
			seen[name] = true
			if err := uniqueJSON(d, depth+1); err != nil {
				return err
			}
		}
	case '[':
		for d.More() {
			if err := uniqueJSON(d, depth+1); err != nil {
				return err
			}
		}
	default:
		return ErrInvalid
	}
	_, err = d.Token()
	return err
}

func DecodeFrozenJob(raw []byte) (FrozenJob, error) {
	var j FrozenJob
	if len(raw) == 0 || len(raw) > MaxEnvelopeBytes {
		return j, ErrInvalid
	}
	check := json.NewDecoder(bytes.NewReader(raw))
	check.UseNumber()
	if err := uniqueJSON(check, 0); err != nil {
		return j, fmt.Errorf("%w: JSON: %v", ErrInvalid, err)
	}
	if _, err := check.Token(); err != io.EOF {
		return j, ErrInvalid
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&j); err != nil {
		return FrozenJob{}, fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil || !exactKeys(fields, []string{"version", "jobId", "effectId", "requestId", "terminalId", "venueId", "installationId", "originInstallationId", "authorityEpoch", "deviceId", "physicalPrinterId", "aliasId", "routeRevision", "configRevision", "bindingRevision", "registryRevision", "attemptId", "beepAttemptId", "destination", "capabilityProfile", "primaryBytes", "primarySha256"}) {
		return FrozenJob{}, ErrInvalid
	}
	for _, value := range fields {
		if bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return FrozenJob{}, ErrInvalid
		}
	}
	// Every field, including irrelevant destination zero values, is required.
	var destinationFields map[string]json.RawMessage
	if err := json.Unmarshal(fields["destination"], &destinationFields); err != nil || !exactKeys(destinationFields, []string{"physicalPrinterId", "workerHostId", "transport", "host", "port", "queueName", "expectedDriverName", "expectedPortName", "documentName"}) {
		return FrozenJob{}, ErrInvalid
	}
	for _, value := range destinationFields {
		if bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return FrozenJob{}, ErrInvalid
		}
	}
	if j.Version != 1 {
		return FrozenJob{}, ErrInvalid
	}
	for _, id := range []string{j.JobID, j.EffectID, j.RequestID, j.TerminalID, j.VenueID, j.InstallationID, j.OriginInstallationID, j.DeviceID, j.PhysicalPrinterID, j.AliasID, j.AttemptID, j.BeepAttemptID, j.Destination.WorkerHostID} {
		if !CanonicalUUID(id) {
			return FrozenJob{}, ErrInvalid
		}
	}
	for _, rev := range []uint64{j.AuthorityEpoch, j.RouteRevision, j.ConfigRevision, j.BindingRevision, j.RegistryRevision} {
		if !boundedRevision(rev) {
			return FrozenJob{}, ErrInvalid
		}
	}
	if j.PhysicalPrinterID != j.Destination.PhysicalPrinterID {
		return FrozenJob{}, ErrInvalid
	}
	if err := printtransport.ValidateDestination(j.Destination); err != nil {
		return FrozenJob{}, fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	profile := bytes.TrimSpace(j.CapabilityProfile)
	if len(profile) < 2 || len(profile) > 65536 || profile[0] != '{' || profile[len(profile)-1] != '}' {
		return FrozenJob{}, ErrInvalid
	}
	if !validPrimaryProfile(profile) {
		return FrozenJob{}, ErrInvalid
	}
	if len(j.PrimaryBytes) == 0 || len(j.PrimaryBytes) > printtransport.MaxTransmissionBytes {
		return FrozenJob{}, ErrInvalid
	}
	h := sha256.Sum256(j.PrimaryBytes)
	if j.PrimarySHA256 != hex.EncodeToString(h[:]) {
		return FrozenJob{}, ErrInvalid
	}
	h = sha256.Sum256(raw)
	j.digest = hex.EncodeToString(h[:])
	j.raw = bytes.Clone(raw)
	return j, nil
}

// fresh prevents a caller mutating exported fields after a successful decode.
func (j FrozenJob) fresh() (FrozenJob, error) {
	frozen, err := DecodeFrozenJob(j.raw)
	if err != nil {
		return FrozenJob{}, err
	}
	a, err := json.Marshal(j)
	if err != nil {
		return FrozenJob{}, err
	}
	b, err := json.Marshal(frozen)
	if err != nil || !bytes.Equal(a, b) || frozen.digest != j.digest {
		return FrozenJob{}, ErrInvalid
	}
	return frozen, nil
}

func (a Authority) matches(j FrozenJob) bool {
	return CanonicalUUID(a.VenueID) && CanonicalUUID(a.InstallationID) && CanonicalUUID(a.OriginInstallationID) && CanonicalUUID(a.TerminalID) && boundedRevision(a.Epoch) &&
		a.VenueID == j.VenueID && a.InstallationID == j.InstallationID && a.OriginInstallationID == j.OriginInstallationID && a.TerminalID == j.TerminalID && a.Epoch == j.AuthorityEpoch
}

// Registry binds aliases to one physical UUID and one captured endpoint.
// Destination.DocumentName must be empty: each frozen job owns that label.
// Scope/host identities cannot be moved by a revision update or timeout.
type Registry struct {
	PhysicalPrinterID string                     `json:"physicalPrinterId"`
	VenueID           string                     `json:"venueId"`
	InstallationID    string                     `json:"installationId"`
	AuthorityEpoch    uint64                     `json:"authorityEpoch"`
	DeviceID          string                     `json:"deviceId"`
	WorkerHostID      string                     `json:"workerHostId"`
	BindingRevision   uint64                     `json:"bindingRevision"`
	ConfigRevision    uint64                     `json:"configRevision"`
	RegistryRevision  uint64                     `json:"registryRevision"`
	Destination       printtransport.Destination `json:"destination"`
	Aliases           []string                   `json:"aliases"`
}

func (r Registry) validate() error {
	for _, id := range []string{r.PhysicalPrinterID, r.VenueID, r.InstallationID, r.DeviceID, r.WorkerHostID} {
		if !CanonicalUUID(id) {
			return ErrInvalid
		}
	}
	for _, n := range []uint64{r.AuthorityEpoch, r.BindingRevision, r.ConfigRevision, r.RegistryRevision} {
		if !boundedRevision(n) {
			return ErrInvalid
		}
	}
	if r.Destination.PhysicalPrinterID != r.PhysicalPrinterID || r.Destination.WorkerHostID != r.WorkerHostID || r.Destination.DocumentName != "" || len(r.Aliases) == 0 || len(r.Aliases) > 128 {
		return ErrInvalid
	}
	d := r.Destination
	d.DocumentName = "registry validation"
	if err := printtransport.ValidateDestination(d); err != nil {
		return fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	seen := make(map[string]bool)
	for _, id := range r.Aliases {
		if !CanonicalUUID(id) || seen[id] {
			return ErrInvalid
		}
		seen[id] = true
	}
	return nil
}

func endpointKey(d printtransport.Destination) string {
	if d.Transport == printtransport.TCP {
		return "tcp:" + net.ParseIP(d.Host).String() + ":" + strconv.Itoa(int(d.Port))
	}
	// Winspool queue names are case-insensitive on their fixed worker host;
	// driver/port changes cannot produce a second active owner of that queue.
	return "windows:" + d.WorkerHostID + ":" + strings.ToLower(d.QueueName)
}

func validPrimaryProfile(raw []byte) bool {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil {
		return false
	}
	for key := range fields {
		if key != "protocol" && key != "paperWidthMm" && key != "rasterWidthDots" && key != "language" && key != "cutter" && key != "encoding" && key != "beep" {
			return false
		}
	}
	var p struct {
		Protocol        uint32 `json:"protocol"`
		PaperWidthMm    uint32 `json:"paperWidthMm"`
		RasterWidthDots uint32 `json:"rasterWidthDots"`
		Language        string `json:"language"`
		Cutter          string `json:"cutter"`
		Encoding        string `json:"encoding"`
	}
	if json.Unmarshal(raw, &p) != nil {
		return false
	}
	return p.Protocol == 1 && p.PaperWidthMm >= 40 && p.PaperWidthMm <= 120 && p.RasterWidthDots >= 64 && p.RasterWidthDots <= 2048 && p.RasterWidthDots%8 == 0 && p.Language == "escposRaster" && (p.Cutter == "none" || p.Cutter == "full" || p.Cutter == "partial") && p.Encoding == "georgianViaRaster"
}

// ValidatePrimaryProfile is shared by inert logical queues. It validates only
// implemented primary capabilities; beep remains an optional tolerant field.
func ValidatePrimaryProfile(raw json.RawMessage) error {
	if len(raw) > 65536 {
		return ErrInvalid
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if uniqueJSON(d, 0) != nil {
		return ErrInvalid
	}
	if _, err := d.Token(); err != io.EOF || !validPrimaryProfile(raw) {
		return ErrInvalid
	}
	return nil
}

// Optional signal selection is deliberately tolerant. Unknown or malformed
// beep configuration never rejects valid primary bytes. Only the explicit
// Epson ESC ( A fn97 profile selects this documented fixed pattern command.
func optionalBeep(profile json.RawMessage) ([]byte, string) {
	var fields map[string]json.RawMessage
	var beep map[string]json.RawMessage
	if json.Unmarshal(profile, &fields) != nil || json.Unmarshal(fields["beep"], &beep) != nil || !exactKeys(beep, []string{"capability", "enabled"}) {
		return nil, "unknown"
	}
	var p struct {
		Language string `json:"language"`
		Beep     struct {
			Capability string `json:"capability"`
			Enabled    bool   `json:"enabled"`
		} `json:"beep"`
	}
	if json.Unmarshal(profile, &p) != nil {
		return nil, "unknown"
	}
	if !p.Beep.Enabled {
		return nil, "disabled"
	}
	if p.Language != "escposRaster" || p.Beep.Capability != "epsonEscA97Pattern" {
		return nil, "unsupported or unknown"
	}
	return []byte{0x1b, 0x28, 0x41, 0x03, 0x00, 0x61, 0x01, 0x01}, ""
}

type PrimaryState string

const (
	Queued    PrimaryState = "queued"
	Started   PrimaryState = "started"
	Submitted PrimaryState = "submitted"
	NotSent   PrimaryState = "notSent"
	Uncertain PrimaryState = "uncertain"
)

type BeepState string

const (
	BeepPending   BeepState = "pending"
	BeepSkipped   BeepState = "skipped"
	BeepReserved  BeepState = "reserved"
	BeepSubmitted BeepState = "submitted"
	BeepNotSent   BeepState = "notSent"
	BeepUncertain BeepState = "uncertain"
)

type Receipt struct {
	Version           uint32 `json:"version"`
	JobID             string `json:"jobId"`
	EffectID          string `json:"effectId"`
	PhysicalPrinterID string `json:"physicalPrinterId"`
	Sequence          uint64 `json:"sequence"`
	AdmissionSHA256   string `json:"admissionSha256"`
}

type Outcome struct {
	Receipt       Receipt                `json:"receipt"`
	Primary       PrimaryState           `json:"primary"`
	PrimaryResult *printtransport.Result `json:"primaryResult"`
	Beep          BeepState              `json:"beep"`
	BeepResult    *printtransport.Result `json:"beepResult"`
	Phase         string                 `json:"phase"`
}
