package printstation

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"testing"

	"vynic.local/edge/internal/printtransport"
)

func uid(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }
func fixture() (Catalog, Authority) {
	c := Catalog{Version: 1, VenueID: uid(1), Revision: 1}
	for i := 0; i < 3; i++ {
		c.Controllers = append(c.Controllers, Controller{uid(10 + i), uid(20 + i), uid(30 + i), fmt.Sprint("Host ", i+1)})
		p := PhysicalPrinter{ID: uid(40 + i), Name: fmt.Sprint("Printer ", i+1), ControllerID: uid(10 + i), Enabled: true, FailoverMode: FixedController, Profile: json.RawMessage(`{"protocol":1,"paperWidthMm":80,"rasterWidthDots":576,"language":"escposRaster","cutter":"partial","encoding":"georgianViaRaster"}`)}
		p.Destination = printtransport.Destination{PhysicalPrinterID: p.ID, WorkerHostID: p.ControllerID, Transport: printtransport.TCP, Host: fmt.Sprintf("192.168.1.%d", 50+i), Port: 9100, DocumentName: "Vynic"}
		c.Printers = append(c.Printers, p)
	}
	c.Stations = []Station{{ID: uid(50), Name: "Main Kitchen", Role: "KITCHEN", Scope: Shared, Enabled: true, Routes: []string{uid(40), uid(41)}}, {ID: uid(51), Name: "Upstairs Bar", Role: "BAR", Scope: Shared, Enabled: true, Routes: []string{uid(42)}}}
	c.Rules = []Rule{{Kind: "item", MatchID: "khinkali", Stations: []string{uid(50)}}, {Kind: "category", MatchID: "drinks", Stations: []string{uid(51)}}}
	return c, Authority{VenueID: c.VenueID, DeviceID: uid(30), ControllerID: uid(10), Admin: true}
}
func job(c Catalog, station string, n int) Job {
	effect := fmt.Sprint("confirm-order-", n)
	return Job{Version: 1, ID: OutputID(c.VenueID, effect, station, "production"), VenueID: c.VenueID, StationID: station, SourceDeviceID: uid(30), EffectID: effect, OutputKind: "production", BusinessRef: fmt.Sprint("Order ", n), ConfigDigest: c.Digest(), CreatedAt: 1, Payload: []byte("frozen ticket"), PayloadDigest: Digest([]byte("frozen ticket"))}
}
func admitted(t *testing.T) (*State, Catalog, Authority, Job) {
	t.Helper()
	c, a := fixture()
	s := New(c.VenueID)
	if e := s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	j := job(c, uid(50), 1)
	if _, e := s.Admit(a, j, 1); e != nil {
		t.Fatal(e)
	}
	return s, c, a, j
}
func valid(t *testing.T, s *State) {
	t.Helper()
	if e := s.Validate(); e != nil {
		t.Fatalf("invalid state: %v\n%s", e, Encode(s))
	}
}
func TestRoutingAllSourcesAndMultipleDestinations(t *testing.T) {
	c, a := fixture()
	lines := []Line{{ID: "line1", ItemID: "khinkali"}, {ID: "line2", ItemID: "beer", CategoryID: "drinks"}}
	want, e := c.Plan(a, "order-effect", "dineIn", "production", lines)
	if e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 10; i++ {
		a.DeviceID = uid(100 + i)
		got, e := c.Plan(a, "order-effect", "dineIn", "production", lines)
		if e != nil || !reflect.DeepEqual(got, want) {
			t.Fatalf("source %d: %v %v", i, got, e)
		}
	}
	lines[0].Stations = []string{uid(50), uid(51)}
	got, e := c.Plan(a, "order-effect", "takeaway", "production", lines)
	if e != nil || len(got) != 2 {
		t.Fatal(got, e)
	}
	lines[0].Stations = []string{uid(50), uid(50)}
	if _, e = c.Plan(a, "effect", "takeaway", "production", lines); e == nil {
		t.Fatal("duplicate station accepted")
	}
}
func TestTopologyMatrix(t *testing.T) {
	for _, n := range []int{1, 2, 3, 4, 6, 10, 100} {
		t.Run(fmt.Sprint(n), func(t *testing.T) {
			hosts := []string{}
			for i := 0; i < n; i++ {
				hosts = append(hosts, uid(100+i))
			}
			p, e := ProposeTopology(hosts, false, false)
			want := 1
			if n >= 3 {
				want = 3
			}
			if e != nil || len(p.Voters) != want || len(p.Clients) != n-want {
				t.Fatal(p, e)
			}
			local, e := ProposeTopology(hosts, true, false)
			if e != nil || len(local.Voters) != 0 || local.Majority != 0 {
				t.Fatal(local, e)
			}
		})
	}
}
func TestDefinitiveFallbackFIFOAndIndependentBar(t *testing.T) {
	s, c, a, j := admitted(t)
	j2 := job(c, uid(50), 2)
	bar := job(c, uid(51), 3)
	for i, j := range []Job{j2, bar} {
		if _, e := s.Admit(a, j, uint64(i+2)); e != nil {
			t.Fatal(e)
		}
	}
	if _, e := s.Begin(a, j2.ID, uid(99), 2); !errors.Is(e, ErrHeld) {
		t.Fatal(e)
	}
	x, e := s.Begin(a, j.ID, uid(100), 2)
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Finish(a, j.ID, x.ID, 3, printtransport.Result{State: printtransport.NotSent, Stage: "connect failed"}); e != nil {
		t.Fatal(e)
	}
	if s.Jobs[j.ID].NextRoute != 1 || s.Jobs[j.ID].State != Queued {
		t.Fatal(s.Jobs[j.ID])
	}
	backup := a
	backup.ControllerID = uid(11)
	x, e = s.Begin(backup, j.ID, uid(101), 4)
	if e != nil || x.PrinterID != uid(41) {
		t.Fatal(x, e)
	}
	barController := a
	barController.ControllerID = uid(12)
	if _, e = s.Begin(barController, bar.ID, uid(102), 4); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Begin(a, j2.ID, uid(103), 4); !errors.Is(e, ErrHeld) {
		t.Fatal("skipped head", e)
	}
	if e = s.Finish(backup, j.ID, x.ID, 5, printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: uint32(len(j.Payload))}); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Begin(a, j2.ID, uid(104), 6); e != nil {
		t.Fatal(e)
	}
	valid(t, s)
}
func TestUncertainNeverFallsBackOrRetries(t *testing.T) {
	for _, result := range []printtransport.Result{{State: printtransport.Uncertain}, {State: printtransport.NotSent, WriteAttempted: true}, {State: printtransport.NotSent, BytesWritten: 1}, {State: printtransport.NotSent, JobID: 42}, {State: printtransport.Submitted, WriteAttempted: true, BytesWritten: 1}, {}} {
		t.Run(fmt.Sprint(result), func(t *testing.T) {
			s, _, a, j := admitted(t)
			x, e := s.Begin(a, j.ID, uid(100), 2)
			if e != nil {
				t.Fatal(e)
			}
			if e = s.Finish(a, j.ID, x.ID, 3, result); e != nil {
				t.Fatal(e)
			}
			if s.Jobs[j.ID].State != Uncertain || s.Jobs[j.ID].NextRoute != 0 {
				t.Fatal(s.Jobs[j.ID])
			}
			a.ControllerID = uid(11)
			if _, e = s.Begin(a, j.ID, uid(101), 4); !errors.Is(e, ErrHeld) {
				t.Fatal(e)
			}
			valid(t, s)
		})
	}
}
func TestRestartAndLostACKRetainImmutableIdentity(t *testing.T) {
	s, _, a, j := admitted(t)
	first, _ := s.Admit(a, j, 2)
	again, e := s.Admit(a, j, 3)
	if e != nil || !reflect.DeepEqual(first, again) {
		t.Fatal(e)
	}
	j.Payload = []byte("changed")
	j.PayloadDigest = Digest(j.Payload)
	if _, e = s.Admit(a, j, 4); !errors.Is(e, ErrReuse) {
		t.Fatal(e)
	}
	j = s.Jobs[j.ID].Job
	if _, e = s.Begin(a, j.ID, uid(100), 2); e != nil {
		t.Fatal(e)
	}
	var restored State
	if e = json.Unmarshal(Encode(s), &restored); e != nil {
		t.Fatal(e)
	}
	restored.Interrupt()
	if restored.Jobs[j.ID].State != Uncertain {
		t.Fatal("replayed")
	}
	valid(t, &restored)
}
func TestConfigurationAndAuthorityFailClosed(t *testing.T) {
	s, c, a, j := admitted(t)
	wrong := a
	wrong.VenueID = uid(999)
	if _, e := s.Admit(wrong, j, 2); !errors.Is(e, ErrScope) {
		t.Fatal(e)
	}
	wrong = a
	wrong.ControllerID = uid(12)
	if _, e := s.Begin(wrong, j.ID, uid(100), 2); !errors.Is(e, ErrScope) {
		t.Fatal(e)
	}
	for _, change := range []func(*Catalog){func(c *Catalog) { c.Printers[0].FailoverMode = QualifiedFencedFailover }, func(c *Catalog) { c.Printers[1].Destination = c.Printers[0].Destination }, func(c *Catalog) { c.Controllers[0].ID = "" }} {
		v := clone(c)
		change(&v)
		if v.Validate() == nil {
			t.Fatal("invalid config accepted")
		}
	}
	c.Revision++
	c.Printers[0].ControllerID = uid(11)
	c.Printers[0].Destination.WorkerHostID = uid(11)
	if e := s.Install(a, c); !errors.Is(e, ErrHeld) {
		t.Fatal("controller moved", e)
	}
	c, _ = fixture()
	c.Revision++
	c.Stations[0].Routes = []string{uid(41)}
	if e := s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	x, e := s.Begin(a, j.ID, uid(100), 2)
	if e != nil || x.PrinterID != uid(40) {
		t.Fatal("retargeted queued job", x, e)
	}
	valid(t, s)
}
func TestLocalScopeAndAllLocal(t *testing.T) {
	c, a := fixture()
	for i := range c.Stations {
		c.Stations[i].Scope = Local
		c.Stations[i].OwnerDeviceID = uid(30)
		c.Stations[i].Routes = []string{uid(40)}
	}
	if e := c.Validate(); e != nil {
		t.Fatal(e)
	}
	s := New(c.VenueID)
	if e := s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	j := job(c, uid(50), 1)
	a.DeviceID = uid(31)
	j.SourceDeviceID = a.DeviceID
	if _, e := s.Admit(a, j, 1); !errors.Is(e, ErrScope) {
		t.Fatal(e)
	}
	a.DeviceID = uid(30)
	j.SourceDeviceID = a.DeviceID
	if _, e := s.Admit(a, j, 1); e != nil {
		t.Fatal(e)
	}
	valid(t, s)
}
func TestManualReprintAuditAndOriginalUnchanged(t *testing.T) {
	s, _, a, j := admitted(t)
	x, _ := s.Begin(a, j.ID, uid(100), 2)
	if e := s.Finish(a, j.ID, x.ID, 3, printtransport.Result{State: printtransport.Uncertain}); e != nil {
		t.Fatal(e)
	}
	copy := clone(j)
	copy.ID = uid(200)
	copy.Reprint = &Reprint{j.ID, uid(300), "Operator verified stopped controller", 4}
	if _, e := s.Admit(a, copy, 4); !errors.Is(e, ErrHeld) {
		t.Fatal(e)
	}
	if e := s.ReconcileProof(a, j.ID, uid(300), "synthetic drained controller", 5); e != nil {
		t.Fatal(e)
	}
	before := Encode(s.Jobs[j.ID])
	if _, e := s.Admit(a, copy, 5); e != nil {
		t.Fatal(e)
	}
	if !bytes.Equal(before, Encode(s.Jobs[j.ID])) {
		t.Fatal("original rewritten")
	}
	valid(t, s)
}
func TestDisabledPrimaryRecordsDefinitiveFailure(t *testing.T) {
	s, _, a, j := admitted(t)
	if e := s.SetRouteState(a, uid(40), Disabled); e != nil {
		t.Fatal(e)
	}
	x, e := s.Begin(a, j.ID, uid(100), 2)
	if e != nil || x.Outcome != NotSubmitted || s.Jobs[j.ID].NextRoute != 1 {
		t.Fatal(x, e)
	}
	valid(t, s)
}
func TestSharedPhysicalPrinterCannotOverlapStations(t *testing.T) {
	s, c, a, j := admitted(t)
	c.Revision++
	c.Stations[1].Routes = []string{uid(40)}
	if e := s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	bar := job(c, uid(51), 2)
	if _, e := s.Admit(a, bar, 2); e != nil {
		t.Fatal(e)
	}
	if _, e := s.Begin(a, j.ID, uid(100), 2); e != nil {
		t.Fatal(e)
	}
	if _, e := s.Begin(a, bar.ID, uid(101), 2); !errors.Is(e, ErrHeld) {
		t.Fatal(e)
	}
	s.Interrupt()
	if _, e := s.Begin(a, bar.ID, uid(102), 3); !errors.Is(e, ErrHeld) {
		t.Fatal(e)
	}
	valid(t, s)
}

func TestUnavailableControllerSkipRequiresNoDispatchReservation(t *testing.T) {
	s, _, a, j := admitted(t)
	if e := s.SkipUnavailable(a, j.ID, uid(100), "controller offline before reservation", 2); e != nil {
		t.Fatal(e)
	}
	if _, e := s.Begin(a, j.ID, uid(101), 3); !errors.Is(e, ErrScope) {
		t.Fatal("old controller claimed backup", e)
	}
	a.ControllerID = uid(11)
	if _, e := s.Begin(a, j.ID, uid(102), 3); e != nil {
		t.Fatal(e)
	}
	if e := s.SkipUnavailable(a, j.ID, uid(103), "controller timeout after reservation", 4); !errors.Is(e, ErrHeld) {
		t.Fatal(e)
	}
	valid(t, s)
}

func TestMixedSharedProductionAndIndependentLocalReceipts(t *testing.T) {
	c, _ := fixture()
	for i := 0; i < 3; i++ {
		p := clone(c.Printers[i])
		p.ID = uid(400 + i)
		p.Name = fmt.Sprint("Receipt ", i+1)
		p.Destination.PhysicalPrinterID = p.ID
		p.Destination.Host = fmt.Sprintf("192.168.1.%d", 80+i)
		c.Printers = append(c.Printers, p)
		c.Stations = append(c.Stations, Station{ID: uid(500 + i), Name: fmt.Sprint("Cashier ", i+1), Role: "RECEIPT", Scope: Local, OwnerDeviceID: uid(30 + i), Enabled: true, Routes: []string{p.ID}})
	}
	if e := c.Validate(); e != nil {
		t.Fatal(e)
	}
	shared, e := c.ForQueue(Shared, "")
	if e != nil || len(shared.Stations) != 2 || len(shared.Printers) != 3 || len(shared.Rules) != 0 {
		t.Fatal(shared, e)
	}
	for i := 0; i < 3; i++ {
		local, e := c.ForQueue(Local, uid(30+i))
		if e != nil || len(local.Stations) != 1 || len(local.Printers) != 1 || local.Stations[0].OwnerDeviceID != uid(30+i) {
			t.Fatal(local, e)
		}
	}
}
