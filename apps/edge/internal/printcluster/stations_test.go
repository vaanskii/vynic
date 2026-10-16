package printcluster

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

func stationCatalog(t *testing.T, pin ClusterConfig) printstation.Catalog {
	t.Helper()
	old, _ := golden(t, "shared_tcp")
	c := printstation.Catalog{Version: 1, VenueID: pin.VenueID, Revision: 1}
	for _, p := range pin.Peers {
		c.Controllers = append(c.Controllers, printstation.Controller{ID: p.ID, InstallationID: p.InstallationID, DeviceID: p.DeviceID, Name: p.ID})
	}
	for i := 0; i < 3; i++ {
		controller := pin.Peers[i%len(pin.Peers)]
		physical := testUUID(8000 + i)
		c.Printers = append(c.Printers, printstation.PhysicalPrinter{ID: physical, Name: fmt.Sprint("Printer ", i), ControllerID: controller.ID, Destination: printtransport.Destination{PhysicalPrinterID: physical, WorkerHostID: controller.ID, Transport: printtransport.TCP, Host: fmt.Sprintf("192.168.50.%d", 10+i), Port: 9100, DocumentName: "Synthetic ticket"}, Profile: old.CapabilityProfile, Enabled: true, FailoverMode: printstation.FixedController})
	}
	c.Stations = []printstation.Station{{ID: testUUID(8100), Name: "Main Kitchen", Role: "KITCHEN", Scope: printstation.Scope(pin.Scope), Enabled: true, Routes: []string{c.Printers[0].ID, c.Printers[1].ID}}, {ID: testUUID(8101), Name: "Bar", Role: "BAR", Scope: printstation.Scope(pin.Scope), Enabled: true, Routes: []string{c.Printers[2].ID}}}
	if pin.Scope == Local {
		for i := range c.Stations {
			c.Stations[i].OwnerDeviceID = pin.Peers[0].DeviceID
		}
	}
	return c
}
func stationJob(c printstation.Catalog, p Peer, n, size int, station int) printstation.Job {
	effect := fmt.Sprintf("order-confirm-%d", n)
	payload := bytes.Repeat([]byte{'x'}, size)
	sid := c.Stations[station].ID
	return printstation.Job{Version: 1, ID: printstation.OutputID(c.VenueID, effect, sid, "production"), VenueID: c.VenueID, StationID: sid, SourceDeviceID: p.DeviceID, EffectID: effect, OutputKind: "production", BusinessRef: fmt.Sprint("Order ", n), ConfigDigest: c.Digest(), CreatedAt: 1, Payload: payload, PayloadDigest: sha(payload)}
}
func stationCaller(p Peer) Caller { return Caller{p.ID, p.TerminalID, p.InstallationID} }
func stationPin(t *testing.T, sources int) ClusterConfig {
	_, base := golden(t, "shared_tcp")
	voters := 1
	if sources >= 3 {
		voters = 3
	}
	pin := testPin(t, voters, VenueShared, base, false, false)
	for i := voters; i < sources; i++ {
		pin.Peers = append(pin.Peers, Peer{ID: testUUID(1100 + i), TerminalID: testUUID(1200 + i), InstallationID: testUUID(1300 + i), DeviceID: testUUID(1400 + i), Role: Client})
	}
	return pin
}
func TestStationReplicatedTopologyMatrix(t *testing.T) {
	for _, sources := range []int{1, 2, 3, 4, 6, 10} {
		t.Run(fmt.Sprint(sources), func(t *testing.T) {
			pin := stationPin(t, sources)
			cluster := startCluster(t, pin)
			leader := cluster.leader()
			ctx := context.Background()
			c := stationCatalog(t, pin)
			admin := stationCaller(pin.Peers[0])
			if e := leader.InstallStations(ctx, admin, c); e != nil {
				t.Fatal(e)
			}
			for i, p := range pin.Peers {
				for station := 0; station < 2; station++ {
					j := stationJob(c, p, i*2+station, 4096, station)
					req := testUUID(9000 + i*2 + station)
					r, e := leader.SubmitStation(ctx, stationCaller(p), req, j)
					if e != nil {
						t.Fatal(e)
					}
					again, e := leader.SubmitStation(ctx, stationCaller(p), req, j)
					if e != nil || again != r {
						t.Fatal("lost ACK", again, e)
					}
					if r.Sequence != uint64(i+1) {
						t.Fatal("station sequence", r)
					}
					got, e := leader.ReadStation(ctx, j.ID)
					if e != nil || !reflect.DeepEqual(got.Job, j) {
						t.Fatal(got, e)
					}
				}
			}
			if leader.PhysicalDispatchStatus() != ErrPhysicalHeld {
				t.Fatal("physical activation escaped")
			}
			if e := leader.Snapshot(ctx); e != nil {
				t.Fatal(e)
			}
		})
	}
}
func TestStationControllerIsIndependentOfLeaderAndFallback(t *testing.T) {
	pin := stationPin(t, 3)
	cluster := startCluster(t, pin)
	n := cluster.leader()
	ctx := context.Background()
	c := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	if e := n.InstallStations(ctx, a, c); e != nil {
		t.Fatal(e)
	}
	kitchen := stationJob(c, pin.Peers[2], 1, 32, 0)
	bar := stationJob(c, pin.Peers[1], 2, 32, 1)
	for i, j := range []printstation.Job{kitchen, bar} {
		p := pin.Peers[2-i]
		if _, e := n.SubmitStation(ctx, stationCaller(p), testUUID(9000+i), j); e != nil {
			t.Fatal(e)
		}
	}
	x, e := n.BeginStationAttempt(ctx, a, kitchen.ID, testUUID(9200), 2)
	if e != nil || x.ControllerID != pin.Peers[0].ID {
		t.Fatal(x, e)
	}
	if e = n.FinishStationAttempt(ctx, a, kitchen.ID, x.ID, 3, printtransport.Result{State: printtransport.NotSent, Stage: "connect", Detail: "zero bytes"}); e != nil {
		t.Fatal(e)
	}
	b := stationCaller(pin.Peers[1])
	x, e = n.BeginStationAttempt(ctx, b, kitchen.ID, testUUID(9201), 4)
	if e != nil || x.PrinterID != c.Printers[1].ID {
		t.Fatal(x, e)
	}
	if e = n.FinishStationAttempt(ctx, b, kitchen.ID, x.ID, 5, printtransport.Result{State: printtransport.Uncertain, WriteAttempted: true}); e != nil {
		t.Fatal(e)
	}
	if _, e = n.BeginStationAttempt(ctx, b, kitchen.ID, testUUID(9202), 6); !errors.Is(e, ErrBusy) {
		t.Fatal(e)
	}
	barController := stationCaller(pin.Peers[2])
	bx, e := n.BeginStationAttempt(ctx, barController, bar.ID, testUUID(9203), 6)
	if e != nil {
		t.Fatal(e)
	}
	if e = n.FinishStationAttempt(ctx, barController, bar.ID, bx.ID, 7, printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: 32}); e != nil {
		t.Fatal(e)
	}
	got, e := n.ReadStation(ctx, kitchen.ID)
	if e != nil || got.State != printstation.Uncertain || len(got.Attempts) != 2 {
		t.Fatal(got, e)
	}
	if e = n.ReconcileStationProof(ctx, a, kitchen.ID, testUUID(9999), "synthetic controller drained", 8); e != nil {
		t.Fatal(e)
	}
	copy := kitchen
	copy.ID = testUUID(9300)
	copy.SourceDeviceID = pin.Peers[0].DeviceID
	copy.Reprint = &printstation.Reprint{OriginalID: kitchen.ID, ActorID: testUUID(9999), Reason: "operator copy", At: 9}
	if _, e = n.SubmitStation(ctx, a, testUUID(9301), copy); e != nil {
		t.Fatal(e)
	}
}
func TestStationReplicaLossLeaderLossRejoinAndMinority(t *testing.T) {
	pin := stationPin(t, 3)
	cluster := startCluster(t, pin)
	n := cluster.leader()
	ctx := context.Background()
	c := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	if e := n.InstallStations(ctx, a, c); e != nil {
		t.Fatal(e)
	}
	j := stationJob(c, pin.Peers[0], 1, 700*1024, 0)
	receipt, e := n.SubmitStation(ctx, a, testUUID(9400), j)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = n.BeginStationAttempt(ctx, a, j.ID, testUUID(9401), 2); e != nil {
		t.Fatal(e)
	}
	lost := -1
	for i, node := range cluster.nodes {
		if node == n {
			lost = i
			if e = node.Close(); e != nil {
				t.Fatal(e)
			}
			cluster.nodes[i] = nil
			break
		}
	}
	n = cluster.leader()
	got, e := n.ReadStation(ctx, j.ID)
	if e != nil || got.State != printstation.Uncertain || !bytes.Equal(got.Job.Payload, j.Payload) {
		t.Fatal(got.State, e)
	}
	again, e := n.SubmitStation(ctx, a, testUUID(9400), j)
	if e != nil || again != receipt {
		t.Fatal("lost ACK after election", e)
	}
	rejoined, e := OpenLoopbackProof(cluster.dirs[lost], pin, pin.Peers[lost].ID)
	if e != nil {
		t.Fatal(e)
	}
	cluster.nodes[lost] = rejoined
	deadline := time.Now().Add(15 * time.Second)
	for {
		got, e = rejoined.InspectStationReplica(j.ID)
		if e == nil && got.State == printstation.Uncertain {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("rejoin", e)
		}
		time.Sleep(20 * time.Millisecond)
	}
	for i, node := range cluster.nodes {
		if node != n {
			if e = node.Close(); e != nil {
				t.Fatal(e)
			}
			cluster.nodes[i] = nil
		}
	}
	short, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	j2 := stationJob(c, pin.Peers[0], 2, 16, 0)
	if _, e = n.SubmitStation(short, a, testUUID(9402), j2); e == nil {
		t.Fatal("minority admitted")
	}
}
func TestLocalStationSpoolReopensWithoutRaft(t *testing.T) {
	_, base := golden(t, "local_tcp")
	pin := testPin(t, 1, Local, base, false, false)
	c := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	dir := filepath.Join(t.TempDir(), "spool")
	if e := os.MkdirAll(dir, 0700); e != nil {
		t.Fatal(e)
	}
	s, e := OpenLocalStationProof(dir, pin)
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	j := stationJob(c, pin.Peers[0], 1, 4096, 0)
	receipt, e := s.Submit(a, testUUID(9500), j)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = OpenLocalStationProof(dir, pin); e == nil {
		t.Fatal("duplicate local writer")
	}
	if _, e = s.Begin(context.Background(), a, j.ID, testUUID(9501), 2); e != nil {
		t.Fatal(e)
	}
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e = OpenLocalStationProof(dir, pin)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	got, e := s.Inspect(j.ID)
	if e != nil || got.State != printstation.Uncertain {
		t.Fatal(got, e)
	}
	again, e := s.Submit(a, testUUID(9500), j)
	if e != nil || again != receipt {
		t.Fatal(e)
	}
	if _, e = os.Stat(filepath.Join(dir, "raft.bolt")); !os.IsNotExist(e) {
		t.Fatal("local spool started Raft")
	}
}
func TestStationMalformedOversizedAndWrongVenue(t *testing.T) {
	pin := stationPin(t, 1)
	cluster := startCluster(t, pin)
	n := cluster.leader()
	c := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	ctx := context.Background()
	if e := n.InstallStations(ctx, a, c); e != nil {
		t.Fatal(e)
	}
	j := stationJob(c, pin.Peers[0], 1, 16, 0)
	j.VenueID = testUUID(999)
	j.ID = printstation.OutputID(j.VenueID, j.EffectID, j.StationID, j.OutputKind)
	if _, e := n.SubmitStation(ctx, a, testUUID(9600), j); !errors.Is(e, ErrScope) {
		t.Fatal(e)
	}
	j = stationJob(c, pin.Peers[0], 1, printtransport.MaxTransmissionBytes+1, 0)
	if _, e := n.SubmitStation(ctx, a, testUUID(9601), j); e == nil {
		t.Fatal("oversized accepted")
	}
	j = stationJob(c, pin.Peers[0], 1, 16, 0)
	j.PayloadDigest = "bad"
	if _, e := n.SubmitStation(ctx, a, testUUID(9602), j); e == nil {
		t.Fatal("malformed accepted")
	}
	if _, e := n.SubmitStation(ctx, Caller{}, testUUID(9603), stationJob(c, pin.Peers[0], 1, 16, 0)); e == nil {
		t.Fatal("unknown caller accepted")
	}
}
func TestStationSnapshotRejectsCorruption(t *testing.T) {
	pin := stationPin(t, 1)
	c := stationCatalog(t, pin)
	s := printstation.New(pin.VenueID)
	a := printstation.Authority{VenueID: pin.VenueID, DeviceID: pin.Peers[0].DeviceID, ControllerID: pin.Peers[0].ID, Admin: true}
	if e := s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	j := stationJob(c, pin.Peers[0], 1, 32, 0)
	if _, e := s.Admit(a, j, 1); e != nil {
		t.Fatal(e)
	}
	raw := printstation.Encode(s)
	var copy printstation.State
	if e := json.Unmarshal(raw, &copy); e != nil {
		t.Fatal(e)
	}
	copy.Jobs[j.ID].Job.Payload[0] = 'z'
	if copy.Validate() == nil {
		t.Fatal("corrupted payload accepted")
	}
}

func TestLocalStationRootAliasCannotDuplicateOwner(t *testing.T) {
	_, base := golden(t, "local_tcp")
	pin := testPin(t, 1, Local, base, false, false)
	root := t.TempDir()
	dir := filepath.Join(root, "spool")
	s, e := OpenLocalStationProof(dir, pin)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	alias := filepath.Join(root, "alias")
	if e = os.Symlink(dir, alias); e != nil {
		t.Skipf("directory symlink unavailable: %v", e)
	}
	other, e := OpenLocalStationProof(alias, pin)
	if e == nil {
		_ = other.Close()
		t.Fatal("alias acquired duplicate spool ownership")
	}
}
