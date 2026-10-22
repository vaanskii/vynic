// Package printcluster is a replicated logical printer queue. The proof
// constructor only permits pinned loopback peers; OpenAuthenticated accepts the
// production peer transport. Neither exposes physical sending or activation.
package printcluster

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
)

const (
	Local            = "LOCAL"
	VenueShared      = "VENUE_SHARED"
	Voter            = "VOTER"
	Nonvoter         = "NONVOTER"
	Client           = "CLIENT"
	ChunkBytes       = 256 * 1024
	MaxEnvelopeBytes = 12 * 1024 * 1024
	MaxStateBytes    = 64 * 1024 * 1024
	MaxJobs          = 128
	MaxStagedJobs    = 16
	MaxStagedBytes   = 32 * 1024 * 1024
	DefaultVoters    = 3
)

var (
	ErrPayloadMissing = errors.New("referenced payload no longer retained; retry full payload")
	ErrInvalid        = errors.New("invalid cluster print data")
	ErrScope          = errors.New("cluster authority mismatch")
	ErrReuse          = errors.New("immutable cluster identity reused")
	ErrCapacity       = errors.New("cluster queue capacity exceeded")
	ErrConfig         = errors.New("committed printer configuration mismatch")
	ErrNoQuorum       = errors.New("cluster has no verified leader quorum")
	ErrCommitUnknown  = errors.New("cluster commit outcome unknown; retry exact identity")
	ErrBusy           = errors.New("printer has unresolved logical work")
	ErrAssignment     = errors.New("logical assignment no longer valid")
	ErrStorage        = errors.New("cluster durable storage unavailable")
	ErrMembership     = errors.New("pinned cluster membership mismatch")
	ErrPhysicalHeld   = errors.New("shared physical dispatch is held pending downstream fencing")
	ErrRenderer       = errors.New("primary renderer unavailable")
)

type Peer struct {
	ID             string `json:"id"`
	Address        string `json:"address"`
	Role           string `json:"role"`
	FullData       bool   `json:"fullData"`
	TerminalID     string `json:"terminalId"`
	InstallationID string `json:"installationId"`
	DeviceID       string `json:"deviceId"`
	Admin          bool   `json:"admin"`
}

// Caller is supplied by the trusted proof/transport adapter. Envelope tenant
// fields cannot create authority; production RPC derives it from mutual TLS.
type Caller struct {
	MemberID       string `json:"memberId"`
	TerminalID     string `json:"terminalId"`
	InstallationID string `json:"installationId"`
}

type ClusterConfig struct {
	Issuer    string `json:"issuer,omitempty"`
	Version   uint32 `json:"version"`
	Scope     string `json:"scope"`
	ClusterID string `json:"clusterId"`
	VenueID   string `json:"venueId"`
	Voters    int    `json:"voters"`
	Peers     []Peer `json:"peers"`
}

func (c ClusterConfig) validate() error {
	if c.Version == 2 {
		return c.validateProduction()
	}
	if c.Version != 1 || !uuid(c.ClusterID) || !uuid(c.VenueID) || (c.Scope != Local && c.Scope != VenueShared) || (c.Voters != 1 && c.Voters != 2 && c.Voters != 3 && c.Voters != 5) || (c.Scope == Local && c.Voters != 1) || len(c.Peers) < c.Voters || len(c.Peers) > 16 {
		return ErrMembership
	}
	ids, addresses, terminals := map[string]bool{}, map[string]bool{}, map[string]bool{}
	devices, installations := map[string]bool{}, map[string]bool{}
	voters := 0
	for _, p := range c.Peers {
		if !uuid(p.ID) || !uuid(p.TerminalID) || !uuid(p.InstallationID) || !uuid(p.DeviceID) || ids[p.ID] || terminals[p.TerminalID] || devices[p.DeviceID] || installations[p.InstallationID] {
			return ErrMembership
		}
		ids[p.ID], terminals[p.TerminalID] = true, true
		devices[p.DeviceID], installations[p.InstallationID] = true, true
		switch p.Role {
		case Voter, Nonvoter:
			if !p.FullData || !loopbackAddress(p.Address) || addresses[p.Address] {
				return ErrMembership
			}
			addresses[p.Address] = true
			if p.Role == Voter {
				voters++
			}
		case Client:
			if p.FullData || p.Address != "" {
				return ErrMembership
			}
		default:
			return ErrMembership
		}
	}
	if voters != c.Voters {
		return ErrMembership
	}
	return nil
}

func (c ClusterConfig) peer(id string) (Peer, bool) {
	for _, p := range c.Peers {
		if p.ID == id {
			return p, true
		}
	}
	return Peer{}, false
}
func (c ClusterConfig) authorize(a Caller, admin bool) bool {
	p, ok := c.peer(a.MemberID)
	return ok && p.TerminalID == a.TerminalID && p.InstallationID == a.InstallationID && (!admin || p.Admin)
}
func loopbackAddress(address string) bool {
	host, port, err := net.SplitHostPort(address)
	n, e := strconv.Atoi(port)
	if err != nil || e != nil || n < 1 || n > 65535 {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

type Ownership struct {
	Generation uint64 `json:"generation"`
	Kind       string `json:"kind"`
	OwnerID    string `json:"ownerId"`
}

// ConfigSnapshot freezes the routing destination independently of the current
// leader. A job references its exact committed bytes by SHA256; later endpoint
// edits create another immutable revision, never retarget an accepted job.
type ConfigSnapshot struct {
	Version           uint32          `json:"version"`
	Scope             string          `json:"scope"`
	ClusterID         string          `json:"clusterId"`
	VenueID           string          `json:"venueId"`
	PhysicalPrinterID string          `json:"physicalPrinterId"`
	RouteID           string          `json:"routeId"`
	Role              string          `json:"role"`
	RouteRevision     uint64          `json:"routeRevision"`
	ConfigRevision    uint64          `json:"configRevision"`
	Ownership         Ownership       `json:"ownership"`
	Destination       json.RawMessage `json:"destination"`
	CapabilityProfile json.RawMessage `json:"capabilityProfile"`
	raw               []byte
	digest            string
}

type Job struct {
	Version              uint32          `json:"version"`
	Scope                string          `json:"scope"`
	ClusterID            string          `json:"clusterId"`
	VenueID              string          `json:"venueId"`
	JobID                string          `json:"jobId"`
	EffectID             string          `json:"effectId"`
	RequestID            string          `json:"requestId"`
	OriginTerminalID     string          `json:"originTerminalId"`
	OriginInstallationID string          `json:"originInstallationId"`
	PhysicalPrinterID    string          `json:"physicalPrinterId"`
	RouteID              string          `json:"routeId"`
	Role                 string          `json:"role"`
	RouteRevision        uint64          `json:"routeRevision"`
	ConfigRevision       uint64          `json:"configRevision"`
	ConfigSHA256         string          `json:"configSha256"`
	CapabilityProfile    json.RawMessage `json:"capabilityProfile"`
	PrimaryBytes         []byte          `json:"primaryBytes"`
	PrimarySHA256        string          `json:"primarySha256"`
	ReprintOf            *string         `json:"reprintOf"`
	raw                  []byte
	digest               string
}

func (j Job) Raw() []byte               { return bytes.Clone(j.raw) }
func (j Job) Digest() string            { return j.digest }
func (c ConfigSnapshot) Raw() []byte    { return bytes.Clone(c.raw) }
func (c ConfigSnapshot) Digest() string { return c.digest }

// Public structs are convenient for inspection, but cannot authorize mutation
// of an envelope already decoded. Always submit the original retained bytes.
func (j Job) fresh() (Job, error) {
	f, err := DecodeJob(j.raw)
	if err != nil || f.digest != j.digest {
		return Job{}, ErrInvalid
	}
	a, e := json.Marshal(j)
	b, _ := json.Marshal(f)
	if e != nil || !bytes.Equal(a, b) {
		return Job{}, ErrInvalid
	}
	return f, nil
}
func (c ConfigSnapshot) fresh() (ConfigSnapshot, error) {
	f, err := DecodeConfig(c.raw)
	if err != nil || f.digest != c.digest {
		return ConfigSnapshot{}, ErrInvalid
	}
	a, e := json.Marshal(c)
	b, _ := json.Marshal(f)
	if e != nil || !bytes.Equal(a, b) {
		return ConfigSnapshot{}, ErrInvalid
	}
	return f, nil
}

func DecodeJob(raw []byte) (Job, error) {
	var j Job
	if strict(raw, MaxEnvelopeBytes, &j) != nil || !keys(raw, []string{"version", "scope", "clusterId", "venueId", "jobId", "effectId", "requestId", "originTerminalId", "originInstallationId", "physicalPrinterId", "routeId", "role", "routeRevision", "configRevision", "configSha256", "capabilityProfile", "primaryBytes", "primarySha256", "reprintOf"}) {
		return j, ErrInvalid
	}
	if j.Version != 2 || (j.Scope != Local && j.Scope != VenueShared) || !uuid(j.ClusterID) || !uuid(j.VenueID) || !uuid(j.JobID) || !uuid(j.EffectID) || !uuid(j.RequestID) || !uuid(j.OriginTerminalID) || !uuid(j.OriginInstallationID) || !uuid(j.PhysicalPrinterID) || !uuid(j.RouteID) || !role(j.Role) || !revision(j.RouteRevision) || !revision(j.ConfigRevision) || !hash(j.ConfigSHA256) || !hash(j.PrimarySHA256) || len(j.PrimaryBytes) < 1 || len(j.PrimaryBytes) > printtransport.MaxTransmissionBytes || sha(j.PrimaryBytes) != j.PrimarySHA256 || (j.ReprintOf != nil && (!uuid(*j.ReprintOf) || *j.ReprintOf == j.JobID)) {
		return j, ErrInvalid
	}
	if _, err := canonicalProfile(j.CapabilityProfile); err != nil {
		return j, ErrRenderer
	}
	j.raw, j.digest = bytes.Clone(raw), sha(raw)
	return j, nil
}

func DecodeConfig(raw []byte) (ConfigSnapshot, error) {
	var c ConfigSnapshot
	if strict(raw, 256*1024, &c) != nil || !keys(raw, []string{"version", "scope", "clusterId", "venueId", "physicalPrinterId", "routeId", "role", "routeRevision", "configRevision", "ownership", "destination", "capabilityProfile"}) {
		return c, ErrInvalid
	}
	if c.Version != 1 || (c.Scope != Local && c.Scope != VenueShared) || !uuid(c.ClusterID) || !uuid(c.VenueID) || !uuid(c.PhysicalPrinterID) || !uuid(c.RouteID) || !role(c.Role) || !revision(c.RouteRevision) || !revision(c.ConfigRevision) || !revision(c.Ownership.Generation) || !uuid(c.Ownership.OwnerID) || !keys(c.rawField(raw, "ownership"), []string{"generation", "kind", "ownerId"}) {
		return c, ErrInvalid
	}
	if _, err := canonicalProfile(c.CapabilityProfile); err != nil {
		return c, ErrRenderer
	}
	var d struct {
		Kind          string `json:"kind"`
		Host          string `json:"host"`
		Port          uint16 `json:"port"`
		OwnerDeviceID string `json:"ownerDeviceId"`
		QueueName     string `json:"queueName"`
		DriverName    string `json:"driverName"`
		PortName      string `json:"portName"`
	}
	if json.Unmarshal(c.Destination, &d) != nil {
		return c, ErrInvalid
	}
	if d.Kind == "tcp" {
		if !keys(c.Destination, []string{"kind", "host", "port"}) || !text(d.Host, 255) || d.Port == 0 {
			return c, ErrInvalid
		}
		if c.Scope == VenueShared && (c.Ownership.Kind != "cluster" || c.Ownership.OwnerID != c.ClusterID) {
			return c, ErrInvalid
		}
		if c.Scope == Local && c.Ownership.Kind != "device" {
			return c, ErrInvalid
		}
	} else if d.Kind == "windowsSpooler" {
		if !keys(c.Destination, []string{"kind", "ownerDeviceId", "queueName", "driverName", "portName"}) || !uuid(d.OwnerDeviceID) || !text(d.QueueName, 255) || !text(d.DriverName, 1024) || !text(d.PortName, 1024) || c.Ownership.Kind != "device" || c.Ownership.OwnerID != d.OwnerDeviceID {
			return c, ErrInvalid
		}
	} else {
		return c, ErrInvalid
	}
	c.raw, c.digest = bytes.Clone(raw), sha(raw)
	return c, nil
}
func (c ConfigSnapshot) rawField(raw []byte, field string) []byte {
	var m map[string]json.RawMessage
	_ = json.Unmarshal(raw, &m)
	return m[field]
}

func (j Job) bound(c ClusterConfig, a Caller) bool {
	return c.authorize(a, false) && j.ClusterID == c.ClusterID && j.VenueID == c.VenueID && j.Scope == c.Scope && j.OriginTerminalID == a.TerminalID && j.OriginInstallationID == a.InstallationID
}
func (c ConfigSnapshot) bound(cluster ClusterConfig) bool {
	return c.ClusterID == cluster.ClusterID && c.VenueID == cluster.VenueID && c.Scope == cluster.Scope
}
func (j Job) matches(c ConfigSnapshot) bool {
	a, ae := canonicalProfile(j.CapabilityProfile)
	b, be := canonicalProfile(c.CapabilityProfile)
	return ae == nil && be == nil && j.ConfigSHA256 == c.digest && j.PhysicalPrinterID == c.PhysicalPrinterID && j.RouteID == c.RouteID && j.Role == c.Role && j.ConfigRevision == c.ConfigRevision && j.RouteRevision == c.RouteRevision && bytes.Equal(a, b)
}
func canonicalProfile(raw []byte) ([]byte, error) {
	if printqueue.ValidatePrimaryProfile(raw) != nil {
		return nil, ErrRenderer
	}
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return nil, ErrInvalid
	}
	core := []string{"protocol", "paperWidthMm", "rasterWidthDots", "language", "cutter", "encoding"}
	if len(m) != 6 && len(m) != 7 {
		return nil, ErrInvalid
	}
	for _, k := range core {
		if _, ok := m[k]; !ok {
			return nil, ErrInvalid
		}
	}
	for k := range m {
		known := k == "beep"
		for _, c := range core {
			known = known || k == c
		}
		if !known {
			return nil, ErrInvalid
		}
	}
	capability, enabled := "unknown", false
	var fields map[string]json.RawMessage
	if json.Unmarshal(m["beep"], &fields) == nil && keys(m["beep"], []string{"capability", "enabled"}) {
		var c string
		var e bool
		if json.Unmarshal(fields["capability"], &c) == nil && (bytes.Equal(fields["enabled"], []byte("true")) || bytes.Equal(fields["enabled"], []byte("false"))) && json.Unmarshal(fields["enabled"], &e) == nil {
			switch c {
			case "unknown", "unsupported":
				capability = c
			case "epsonEscA97Pattern":
				capability = c
				enabled = e
			}
		}
	}
	m["beep"], _ = json.Marshal(struct {
		Capability string `json:"capability"`
		Enabled    bool   `json:"enabled"`
	}{capability, enabled})
	return json.Marshal(m)
}
func equalJSON(a, b []byte) bool {
	var x, y any
	if json.Unmarshal(a, &x) != nil || json.Unmarshal(b, &y) != nil {
		return false
	}
	aa, _ := json.Marshal(x)
	bb, _ := json.Marshal(y)
	return bytes.Equal(aa, bb)
}
func sha(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func hash(s string) bool {
	if len(s) != 64 {
		return false
	}
	_, err := hex.DecodeString(s)
	return err == nil && s == strings.ToLower(s)
}
func uuid(s string) bool     { return printqueue.CanonicalUUID(s) }
func revision(v uint64) bool { return v > 0 && v <= math.MaxInt64 }
func role(s string) bool     { return s == "kitchen" || s == "bar" || s == "receipt" || s == "additional" }
func text(s string, max int) bool {
	if !utf8.ValidString(s) || len(s) < 1 || strings.TrimFunc(s, func(r rune) bool { return unicode.IsSpace(r) || r == '\ufeff' }) != s {
		return false
	}
	units := 0
	for _, c := range s {
		units += utf16.RuneLen(c)
		if c < 32 || c == 127 {
			return false
		}
	}
	return units <= max
}
func keys(raw []byte, expected []string) bool {
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil || len(m) != len(expected) {
		return false
	}
	for _, k := range expected {
		if _, ok := m[k]; !ok {
			return false
		}
	}
	return true
}
func strict(raw []byte, max int, target any) error {
	if len(raw) < 1 || len(raw) > max || !utf8.Valid(raw) {
		return ErrInvalid
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if unique(d, 0) != nil {
		return ErrInvalid
	}
	if _, err := d.Token(); err != io.EOF {
		return ErrInvalid
	}
	d = json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(target) != nil {
		return ErrInvalid
	}
	return nil
}
func unique(d *json.Decoder, depth int) error {
	if depth > 32 {
		return ErrInvalid
	}
	t, err := d.Token()
	if err != nil {
		return err
	}
	if delim, ok := t.(json.Delim); ok {
		switch delim {
		case '{':
			seen := map[string]bool{}
			for d.More() {
				k, e := d.Token()
				if e != nil {
					return e
				}
				key, ok := k.(string)
				if !ok || seen[key] {
					return ErrInvalid
				}
				seen[key] = true
				if err := unique(d, depth+1); err != nil {
					return err
				}
			}
		case '[':
			for d.More() {
				if err := unique(d, depth+1); err != nil {
					return err
				}
			}
		default:
			return ErrInvalid
		}
		_, err = d.Token()
		return err
	}
	return nil
}

type Receipt struct {
	Status      string `json:"status"`
	JobID       string `json:"jobId"`
	InputSHA256 string `json:"inputSha256"`
	Sequence    uint64 `json:"sequence"`
	CommitIndex uint64 `json:"commitIndex"`
}
type Assignment struct {
	ClusterID            string `json:"clusterId"`
	Scope                string `json:"scope"`
	JobID                string `json:"jobId"`
	PhysicalPrinterID    string `json:"physicalPrinterId"`
	AttemptID            string `json:"attemptId"`
	ExecutorMemberID     string `json:"executorMemberId"`
	LeaderTerm           uint64 `json:"leaderTerm"`
	MembershipGeneration uint64 `json:"membershipGeneration"`
	ConfigSHA256         string `json:"configSha256"`
	PrimarySHA256        string `json:"primarySha256"`
	CommitIndex          uint64 `json:"commitIndex"`
}
type JobView struct {
	Job          Job         `json:"job"`
	Receipt      Receipt     `json:"receipt"`
	State        string      `json:"state"`
	PrimaryState string      `json:"primaryState"`
	BeepState    string      `json:"beepState"`
	Assignment   *Assignment `json:"assignment"`
}
