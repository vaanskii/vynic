// Package printstation separates business destinations from physical attempts.
// It supplies a deterministic queue domain; it issues no physical fencing permit.
package printstation

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"slices"
	"strings"
	"unicode/utf8"

	"vynic.local/edge/internal/printqueue"
	"vynic.local/edge/internal/printtransport"
)

type Scope string

const (
	Local  Scope = "LOCAL"
	Shared Scope = "VENUE_SHARED"
)

type FailoverMode string

const (
	NoFailover              FailoverMode = "NONE"
	FixedController         FailoverMode = "FIXED_CONTROLLER"
	QualifiedFencedFailover FailoverMode = "QUALIFIED_FENCED_FAILOVER"
)

type RouteState string

const (
	Available      RouteState = "AVAILABLE"
	Offline        RouteState = "OFFLINE"
	Unreachable    RouteState = "UNREACHABLE"
	Held           RouteState = "HELD"
	RouteUncertain RouteState = "UNCERTAIN"
	Disabled       RouteState = "DISABLED"
)

var (
	ErrInvalid  = errors.New("invalid station data")
	ErrScope    = errors.New("station authority mismatch")
	ErrReuse    = errors.New("immutable station identity reused")
	ErrHeld     = errors.New("station or physical printer held")
	ErrNoWork   = errors.New("station has no queued work")
	ErrConfig   = errors.New("station configuration changed or incompatible")
	ErrCapacity = errors.New("station proof capacity reached")
)

// Authority comes from a verified transport/provisioning adapter, never job JSON.
type Authority struct {
	VenueID      string
	DeviceID     string
	ControllerID string
	Admin        bool
}
type Controller struct {
	ID             string `json:"id"`
	InstallationID string `json:"installationId"`
	DeviceID       string `json:"deviceId"`
	Name           string `json:"name"`
}
type PhysicalPrinter struct {
	ID           string                     `json:"id"`
	Name         string                     `json:"name"`
	ControllerID string                     `json:"controllerId"`
	Destination  printtransport.Destination `json:"destination"`
	Profile      json.RawMessage            `json:"profile"`
	Enabled      bool                       `json:"enabled"`
	FailoverMode FailoverMode               `json:"failoverMode"`
}
type Station struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Role          string   `json:"role"` // descriptive, user-defined; never ownership authority
	Scope         Scope    `json:"scope"`
	OwnerDeviceID string   `json:"ownerDeviceId,omitempty"`
	Enabled       bool     `json:"enabled"`
	SortOrder     int      `json:"sortOrder"`
	Routes        []string `json:"routes"` // canonical physical IDs: primary, then backups
}
type Rule struct {
	Kind      string   `json:"kind"` // item, subcategory, category, default
	MatchID   string   `json:"matchId"`
	OrderType string   `json:"orderType,omitempty"`
	Stations  []string `json:"stations"`
}
type Catalog struct {
	Version     int               `json:"version"`
	VenueID     string            `json:"venueId"`
	Revision    uint64            `json:"revision"`
	Controllers []Controller      `json:"controllers"`
	Printers    []PhysicalPrinter `json:"printers"`
	Stations    []Station         `json:"stations"`
	Rules       []Rule            `json:"rules"`
}

func id(s string) bool { return printqueue.CanonicalUUID(s) }
func label(s string) bool {
	return utf8.ValidString(s) && len(s) > 0 && len(s) <= 160 && strings.TrimSpace(s) == s && !strings.ContainsAny(s, "\x00\r\n\t")
}
func Digest(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }

// Encode serializes an already validated domain value. Unsupported values are a
// programming error; never substitute empty bytes or a false digest on failure.
func Encode(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Errorf("encode validated station value: %w", err))
	}
	return b
}
func (c Catalog) Digest() string { return Digest(Encode(c)) }
func (c Catalog) Station(stationID string) (Station, bool) {
	for _, s := range c.Stations {
		if s.ID == stationID {
			return s, true
		}
	}
	return Station{}, false
}
func (c Catalog) Printer(printerID string) (PhysicalPrinter, bool) {
	for _, p := range c.Printers {
		if p.ID == printerID {
			return p, true
		}
	}
	return PhysicalPrinter{}, false
}
func (c Catalog) Controller(controllerID string) (Controller, bool) {
	for _, p := range c.Controllers {
		if p.ID == controllerID {
			return p, true
		}
	}
	return Controller{}, false
}
func endpoint(p PhysicalPrinter) string {
	d := p.Destination
	if d.Transport == printtransport.TCP {
		return net.JoinHostPort(net.ParseIP(d.Host).String(), fmt.Sprint(d.Port))
	}
	return p.ControllerID + "/" + strings.ToLower(d.QueueName)
}
func (c Catalog) Validate() error {
	if c.Version != 1 || !id(c.VenueID) || c.Revision == 0 || c.Revision > 1<<53-1 || len(c.Controllers) == 0 || len(c.Controllers) > 256 || len(c.Printers) == 0 || len(c.Printers) > 64 || len(c.Stations) == 0 || len(c.Stations) > 64 || len(c.Rules) > 2048 {
		return ErrInvalid
	}
	controllers, installations, printers, stations, endpoints := map[string]bool{}, map[string]bool{}, map[string]bool{}, map[string]bool{}, map[string]bool{}
	for _, p := range c.Controllers {
		if !id(p.ID) || !id(p.InstallationID) || !id(p.DeviceID) || !label(p.Name) || controllers[p.ID] || installations[p.InstallationID] {
			return ErrInvalid
		}
		controllers[p.ID] = true
		installations[p.InstallationID] = true
	}
	for _, p := range c.Printers {
		if !id(p.ID) || !label(p.Name) || printers[p.ID] || !controllers[p.ControllerID] || p.Destination.PhysicalPrinterID != p.ID || p.Destination.WorkerHostID != p.ControllerID || printtransport.ValidateDestination(p.Destination) != nil || printqueue.ValidatePrimaryProfile(p.Profile) != nil {
			return ErrInvalid
		}
		// Reserved fenced modes have no implemented downstream enforcement.
		if p.FailoverMode != FixedController && p.FailoverMode != NoFailover {
			return ErrHeld
		}
		if endpoints[endpoint(p)] {
			return ErrConfig
		}
		endpoints[endpoint(p)] = true
		printers[p.ID] = true
	}
	for _, s := range c.Stations {
		if !id(s.ID) || !label(s.Name) || !label(s.Role) || stations[s.ID] || len(s.Routes) == 0 || len(s.Routes) > 8 || (s.Scope != Local && s.Scope != Shared) || (s.Scope == Local && !id(s.OwnerDeviceID)) || (s.Scope == Shared && s.OwnerDeviceID != "") {
			return ErrInvalid
		}
		seen := map[string]bool{}
		var profile []byte
		for _, r := range s.Routes {
			p, ok := c.Printer(r)
			if !ok || seen[r] {
				return ErrConfig
			}
			seen[r] = true
			controller, _ := c.Controller(p.ControllerID)
			if s.Scope == Local && controller.DeviceID != s.OwnerDeviceID {
				return ErrScope
			}
			var v any
			if json.Unmarshal(p.Profile, &v) != nil {
				return ErrInvalid
			}
			canonical := Encode(v)
			if profile != nil && !bytes.Equal(profile, canonical) {
				return ErrConfig
			}
			profile = canonical
		}
		stations[s.ID] = true
	}
	keys := map[string]bool{}
	for _, r := range c.Rules {
		key := string(Encode([]string{r.Kind, r.MatchID, r.OrderType}))
		if keys[key] || !slices.Contains([]string{"item", "subcategory", "category", "default"}, r.Kind) || (r.Kind == "default" && r.MatchID != "") || (r.Kind != "default" && !label(r.MatchID)) || (r.OrderType != "" && !label(r.OrderType)) || len(r.Stations) == 0 || len(r.Stations) > 64 {
			return ErrInvalid
		}
		keys[key] = true
		seen := map[string]bool{}
		for _, s := range r.Stations {
			if !stations[s] || seen[s] {
				return ErrConfig
			}
			seen[s] = true
		}
	}
	return nil
}

type Line struct {
	ID            string
	ItemID        string
	SubcategoryID string
	CategoryID    string
	Stations      []string // optional explicit station override
}
type Output struct {
	JobID     string
	StationID string
	LineIDs   []string
}

// OutputID omits source Device and all physical routing. One business output
// cannot duplicate merely because another authorized POS retries its admission.
func OutputID(venue, effect, station, kind string) string {
	h := sha256.Sum256(Encode([]string{venue, effect, station, kind}))
	h[6] = (h[6] & 15) | 0x50
	h[8] = (h[8] & 63) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", h[:4], h[4:6], h[6:8], h[8:10], h[10:16])
}
func (c Catalog) Plan(a Authority, effect, orderType, kind string, lines []Line) ([]Output, error) {
	if c.Validate() != nil || a.VenueID != c.VenueID || !id(a.DeviceID) || !label(effect) || !label(kind) || !label(orderType) || len(lines) == 0 || len(lines) > 1000 {
		return nil, ErrInvalid
	}
	grouped := map[string][]string{}
	seenLines := map[string]bool{}
	for _, line := range lines {
		if !label(line.ID) || seenLines[line.ID] {
			return nil, ErrInvalid
		}
		seenLines[line.ID] = true
		targets := line.Stations
		if len(targets) == 0 {
			for _, match := range []struct{ kind, value string }{{"item", line.ItemID}, {"subcategory", line.SubcategoryID}, {"category", line.CategoryID}, {"default", ""}} {
				// An order-specific mapping takes precedence over the generic rule.
				for _, order := range []string{orderType, ""} {
					for _, r := range c.Rules {
						if r.Kind == match.kind && r.MatchID == match.value && r.OrderType == order {
							targets = r.Stations
							break
						}
					}
					if len(targets) > 0 {
						break
					}
				}
				if len(targets) > 0 {
					break
				}
			}
		}
		if len(targets) == 0 {
			return nil, ErrConfig
		}
		seen := map[string]bool{}
		for _, target := range targets {
			s, ok := c.Station(target)
			if !ok || !s.Enabled || seen[target] {
				return nil, ErrConfig
			}
			if s.Scope == Local && s.OwnerDeviceID != a.DeviceID {
				return nil, ErrScope
			}
			seen[target] = true
			grouped[target] = append(grouped[target], line.ID)
		}
	}
	ids := make([]string, 0, len(grouped))
	for k := range grouped {
		ids = append(ids, k)
	}
	slices.Sort(ids)
	outputs := make([]Output, 0, len(ids))
	for _, s := range ids {
		outputs = append(outputs, Output{OutputID(c.VenueID, effect, s, kind), s, grouped[s]})
	}
	return outputs, nil
}

type Topology struct {
	Voters                []string
	Clients               []string
	Majority              int
	QueueFailureTolerance int
}

// ForQueue projects a validated Venue catalog into one shared queue or one
// Device's LOCAL spool. Business planning uses the complete catalog first;
// queue projections carry no routing rules, so a filtered rule cannot silently
// turn into a different fallback. Projection is not a signature or authority.
func (c Catalog) ForQueue(scope Scope, ownerDevice string) (Catalog, error) {
	if err := c.Validate(); err != nil {
		return Catalog{}, err
	}
	if (scope != Local && scope != Shared) || (scope == Local && !id(ownerDevice)) || (scope == Shared && ownerDevice != "") {
		return Catalog{}, ErrScope
	}
	projected := Catalog{Version: c.Version, VenueID: c.VenueID, Revision: c.Revision}
	physical := map[string]bool{}
	controllers := map[string]bool{}
	for _, s := range c.Stations {
		if s.Scope != scope || (scope == Local && s.OwnerDeviceID != ownerDevice) {
			continue
		}
		projected.Stations = append(projected.Stations, clone(s))
		for _, p := range s.Routes {
			physical[p] = true
		}
	}
	for _, p := range c.Printers {
		if physical[p.ID] {
			projected.Printers = append(projected.Printers, clone(p))
			controllers[p.ControllerID] = true
		}
	}
	for _, p := range c.Controllers {
		if controllers[p.ID] {
			projected.Controllers = append(projected.Controllers, p)
		}
	}
	if err := projected.Validate(); err != nil {
		return Catalog{}, err
	}
	return projected, nil
}

// ProposeTopology is deterministic from the persisted preferred host order.
// Two hosts default to standalone + client, never two-voter HA. localOnly uses
// no shared members. The caller must persist/authorize the proposal explicitly.
func ProposeTopology(hosts []string, localOnly, higherTolerance bool) (Topology, error) {
	if len(hosts) == 0 || len(hosts) > 256 {
		return Topology{}, ErrInvalid
	}
	seen := map[string]bool{}
	for _, h := range hosts {
		if !id(h) || seen[h] {
			return Topology{}, ErrInvalid
		}
		seen[h] = true
	}
	if localOnly {
		return Topology{Clients: slices.Clone(hosts)}, nil
	}
	n := 1
	if len(hosts) >= 3 {
		n = 3
	}
	if higherTolerance {
		if len(hosts) < 5 {
			return Topology{}, ErrConfig
		}
		n = 5
	}
	return Topology{slices.Clone(hosts[:n]), slices.Clone(hosts[n:]), n/2 + 1, (n - 1) / 2}, nil
}
