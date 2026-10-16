package printstation

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func planningFixture() Catalog {
	c, _ := fixture()
	// Local station is independent of the shared catalog; all rules survive.
	c.Stations = append(c.Stations,
		Station{ID: uid(52), Name: "Receipt", Role: "CASHIER", Scope: Local,
			OwnerDeviceID: uid(30), Enabled: true, Routes: []string{uid(40)}},
		Station{ID: uid(53), Name: "Other receipt", Role: "CASHIER", Scope: Local,
			OwnerDeviceID: uid(31), Enabled: true, Routes: []string{uid(41)}})
	c.Rules = append(c.Rules,
		Rule{Kind: "subcategory", MatchID: "cold", Stations: []string{uid(51)}},
		Rule{Kind: "item", MatchID: "khinkali", OrderType: "takeaway", Stations: []string{uid(51)}},
		Rule{Kind: "default", Stations: []string{uid(50)}})
	return c
}

func TestPlanningProjectionRetainsRulesAndQueueDigests(t *testing.T) {
	c := planningFixture()
	m, err := c.Planning(uid(30))
	if err != nil || m.CatalogDigest != c.Digest() || !reflect.DeepEqual(m.Rules, c.Rules) || len(m.Stations) != len(c.Stations) {
		t.Fatal(m, err)
	}
	for _, s := range m.Stations {
		q, err := c.ForQueue(s.Scope, s.OwnerDeviceID)
		if err != nil || s.QueueDigest != q.Digest() {
			t.Fatal(s, err)
		}
	}
	// Projection cannot mutate its source or expose a physical address.
	raw := Encode(m)
	m.Rules[0].Stations[0] = uid(99)
	m.Stations[0].Profile[0] = '!'
	if c.Validate() != nil || c.Rules[0].Stations[0] != uid(50) {
		t.Fatal("projection mutated source")
	}
	if bytes.Contains(raw, []byte("192.168.")) || bytes.Contains(raw, []byte("controllerId")) {
		t.Fatal("physical destination leaked into planning view")
	}
}

func TestPlanningRejectsInvalidSourceAndIncompatibleBackups(t *testing.T) {
	c := planningFixture()
	if _, err := c.Planning("untrusted-device"); err == nil {
		t.Fatal("invalid source accepted")
	}
	c.Printers[1].Profile = bytes.Replace(c.Printers[1].Profile, []byte("576"), []byte("384"), 1)
	if _, err := c.Planning(uid(30)); err == nil {
		t.Fatal("incompatible backup accepted")
	}
}

// Executed explicitly with VYNIC_STATION_DART set to a cached Dart executable.
// Calls the real Dart planner, then independently validates every job and
// admits it through the Go station domain. No listener or printer is started.
func TestDartStationPlanningInterop(t *testing.T) {
	dart := os.Getenv("VYNIC_STATION_DART")
	if dart == "" {
		t.Skip("set VYNIC_STATION_DART for actual cross-language qualification")
	}
	type scenario struct {
		Effect string `json:"effect"`
		Order  string `json:"orderType"`
		Kind   string `json:"kind"`
		Lines  []Line `json:"lines"`
	}
	c := planningFixture()
	manifest, err := c.Planning(uid(30))
	if err != nil {
		t.Fatal(err)
	}
	cases := []scenario{
		{"confirm-1", "dineIn", "production", []Line{{ID: "one", ItemID: "khinkali"}, {ID: "two", CategoryID: "drinks"}}},
		{"შეკვეთა <1> & \u2028\u2029", "dineIn", "production", []Line{{ID: "ქართული", Stations: []string{uid(51), uid(50)}}}},
		{"specific", "takeaway", "production", []Line{{ID: "one", ItemID: "khinkali", CategoryID: "drinks"}}},
		{"subcategory", "dineIn", "production", []Line{{ID: "one", SubcategoryID: "cold"}}},
		{"default", "dineIn", "production", []Line{{ID: "one"}}},
		{"mixed", "dineIn", "production", []Line{{ID: "one", Stations: []string{uid(50), uid(52)}}}},
		{"foreign", "dineIn", "production", []Line{{ID: "one", Stations: []string{uid(53)}}}},
		{"missing", "dineIn", "production", []Line{{ID: "one", Stations: []string{uid(99)}}}},
		{"duplicate", "dineIn", "production", []Line{{ID: "one", Stations: []string{uid(50), uid(50)}}}},
	}
	dir := t.TempDir()
	input, output := filepath.Join(dir, "input.json"), filepath.Join(dir, "output.json")
	if err := os.WriteFile(input, Encode(map[string]any{"catalog": manifest, "scenarios": cases}), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, dart, "run", "tool/station_print_fixture.dart", input, output)
	cmd.Dir = filepath.Join("..", "..", "..", "operations")
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("Dart planner: %v\n%s", err, b)
	}
	var results []struct {
		Outputs []Output `json:"outputs"`
		Jobs    []string `json:"jobs"`
		Digests []string `json:"digests"`
		Error   string   `json:"error"`
	}
	raw, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, &results); err != nil {
		t.Fatal(err)
	}
	if len(results) != len(cases) {
		t.Fatal("missing Dart scenarios")
	}
	for i, test := range cases {
		t.Run(test.Effect, func(t *testing.T) {
			a := Authority{VenueID: c.VenueID, DeviceID: uid(30), Admin: true}
			want, err := c.Plan(a, test.Effect, test.Order, test.Kind, test.Lines)
			got := results[i]
			if err != nil {
				if got.Error == "" {
					t.Fatal("Dart admitted a Go-refused plan")
				}
				return
			}
			if got.Error != "" || !reflect.DeepEqual(want, got.Outputs) || len(got.Jobs) != len(want) || len(got.Digests) != len(want) {
				t.Fatalf("Go/Dart plan mismatch: want=%+v got=%+v", want, got)
			}
			for j, raw := range got.Jobs {
				var job Job
				if err := json.Unmarshal([]byte(raw), &job); err != nil || job.Validate() != nil {
					t.Fatal("Dart job rejected", err)
				}
				if !bytes.Equal(Encode(job), []byte(raw)) || Digest([]byte(raw)) != got.Digests[j] {
					t.Fatal("exact job bytes/digest differ")
				}
				station, _ := c.Station(job.StationID)
				q, err := c.ForQueue(station.Scope, station.OwnerDeviceID)
				if err != nil || q.Digest() != job.ConfigDigest {
					t.Fatal("queue digest differs", err)
				}
				s := New(c.VenueID)
				if err := s.Install(a, q); err != nil {
					t.Fatal(err)
				}
				first, err := s.Admit(a, job, 1)
				if err != nil {
					t.Fatal(err)
				}
				retry, err := s.Admit(a, job, 2)
				if err != nil || retry.Sequence != first.Sequence || len(s.Jobs) != 1 {
					t.Fatal("exact retry duplicated job", err)
				}
			}
		})
	}
}
