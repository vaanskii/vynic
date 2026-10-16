package printstation

import "encoding/json"

// PlanningCatalog is a read-only projection for Flutter business routing. The
// authenticated service must bind it to its current signed inventory before
// exposing it. A digest or this projection alone never grants admission rights.
type PlanningCatalog struct {
	Version        int               `json:"version"`
	VenueID        string            `json:"venueId"`
	SourceDeviceID string            `json:"sourceDeviceId"`
	Revision       uint64            `json:"revision"`
	CatalogDigest  string            `json:"catalogDigest"`
	Stations       []PlanningStation `json:"stations"`
	Rules          []Rule            `json:"rules"`
}

type PlanningStation struct {
	ID            string          `json:"id"`
	Name          string          `json:"name"`
	Scope         Scope           `json:"scope"`
	OwnerDeviceID string          `json:"ownerDeviceId"`
	Enabled       bool            `json:"enabled"`
	QueueDigest   string          `json:"queueDigest"`
	Profile       json.RawMessage `json:"profile"`
}

// Planning retains all business rules and stations, including foreign LOCAL
// stations. Filtering those before planning could silently select a fallback.
// Physical addresses and controller identities are not business destinations.
func (c Catalog) Planning(device string) (PlanningCatalog, error) {
	if err := c.Validate(); err != nil {
		return PlanningCatalog{}, err
	}
	if !id(device) {
		return PlanningCatalog{}, ErrScope
	}
	out := PlanningCatalog{Version: 1, VenueID: c.VenueID, SourceDeviceID: device,
		Revision: c.Revision, CatalogDigest: c.Digest(),
		Stations: []PlanningStation{}, Rules: append([]Rule{}, clone(c.Rules)...)}
	digests := map[string]string{}
	for _, station := range c.Stations {
		key := string(station.Scope) + "/" + station.OwnerDeviceID
		if _, ok := digests[key]; !ok {
			queue, err := c.ForQueue(station.Scope, station.OwnerDeviceID)
			if err != nil {
				return PlanningCatalog{}, err
			}
			digests[key] = queue.Digest()
		}
		printer, _ := c.Printer(station.Routes[0]) // validated, compatible backups
		out.Stations = append(out.Stations, PlanningStation{station.ID, station.Name,
			station.Scope, station.OwnerDeviceID, station.Enabled, digests[key],
			append(json.RawMessage(nil), printer.Profile...)})
	}
	return out, nil
}
