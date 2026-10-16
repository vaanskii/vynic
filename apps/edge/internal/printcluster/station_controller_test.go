package printcluster

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

type stationSender struct {
	mu      sync.Mutex
	calls   []string
	primary string
	blocked chan struct{}
	entered chan struct{}
	result  printtransport.State
}

func (s *stationSender) Physical() bool { return false }
func (s *stationSender) Send(_ context.Context, d printtransport.Destination, payload []byte) printtransport.Result {
	s.mu.Lock()
	s.calls = append(s.calls, d.PhysicalPrinterID+"/"+string(payload))
	s.mu.Unlock()
	if d.PhysicalPrinterID == s.primary {
		if s.entered != nil {
			close(s.entered)
		}
		if s.blocked != nil {
			<-s.blocked
		}
		if s.result == printtransport.NotSent {
			return printtransport.Result{State: printtransport.NotSent, Stage: "synthetic connect refusal"}
		}
		if s.result == printtransport.Uncertain {
			return printtransport.Result{State: printtransport.Uncertain, WriteAttempted: true}
		}
	}
	return printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: uint32(len(payload))}
}
func TestStationControllersDispatchFallbackInFIFOOrder(t *testing.T) {
	pin := stationPin(t, 3)
	cluster := startCluster(t, pin)
	n := cluster.leader()
	ctx := context.Background()
	catalog := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	if e := n.InstallStations(ctx, a, catalog); e != nil {
		t.Fatal(e)
	}
	sender := &stationSender{primary: catalog.Printers[0].ID, result: printtransport.NotSent}
	controllers := make([]*printstation.ProofController, 2)
	for i := range controllers {
		var e error
		controllers[i], e = printstation.NewProofController(StationControllerQueue{Leader: func() *Node { return n }, Caller: stationCaller(pin.Peers[i])}, sender)
		if e != nil {
			t.Fatal(e)
		}
	}
	var ids []string
	for i := 0; i < 3; i++ {
		j := stationJob(catalog, pin.Peers[2], i, 4, 0)
		j.Payload = []byte(fmt.Sprintf("K%d", 101+i))
		j.PayloadDigest = sha(j.Payload)
		if _, e := n.SubmitStation(ctx, stationCaller(pin.Peers[2]), testUUID(25000+i), j); e != nil {
			t.Fatal(e)
		}
		ids = append(ids, j.ID)
	}
	for i, id := range ids {
		if e := controllers[0].Run(id, testUUID(25100+i*2)); e != nil {
			t.Fatal(e)
		}
		if e := controllers[1].Run(id, testUUID(25101+i*2)); e != nil {
			t.Fatal(e)
		}
	}
	for i, call := range sender.calls {
		want := fmt.Sprintf("%s/K%d", catalog.Printers[i%2].ID, 101+i/2)
		if call != want {
			t.Fatal(sender.calls)
		}
	}
}
func TestStationBlockedKitchenControllerDoesNotBlockBar(t *testing.T) {
	pin := stationPin(t, 3)
	cluster := startCluster(t, pin)
	n := cluster.leader()
	ctx := context.Background()
	catalog := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	if e := n.InstallStations(ctx, a, catalog); e != nil {
		t.Fatal(e)
	}
	sender := &stationSender{primary: catalog.Printers[0].ID, result: printtransport.Uncertain, entered: make(chan struct{}), blocked: make(chan struct{})}
	var once sync.Once
	release := func() { once.Do(func() { close(sender.blocked) }) }
	defer release()
	k := stationJob(catalog, pin.Peers[0], 1, 4, 0)
	b := stationJob(catalog, pin.Peers[0], 2, 4, 1)
	for i, j := range []printstation.Job{k, b} {
		if _, e := n.SubmitStation(ctx, a, testUUID(26000+i), j); e != nil {
			t.Fatal(e)
		}
	}
	kitchen, e := printstation.NewProofController(StationControllerQueue{func() *Node { return n }, a}, sender)
	if e != nil {
		t.Fatal(e)
	}
	bar, e := printstation.NewProofController(StationControllerQueue{func() *Node { return n }, stationCaller(pin.Peers[2])}, sender)
	if e != nil {
		t.Fatal(e)
	}
	done := make(chan error, 1)
	go func() { done <- kitchen.Run(k.ID, testUUID(26100)) }()
	select {
	case <-sender.entered:
	case <-time.After(10 * time.Second):
		t.Fatal("controller did not start")
	}
	if e = bar.Run(b.ID, testUUID(26101)); e != nil {
		t.Fatal(e)
	}
	row, e := n.ReadStation(ctx, b.ID)
	if e != nil || row.State != printstation.Submitted {
		t.Fatal(row, e)
	}
	release()
	if e = <-done; e != nil {
		t.Fatal(e)
	}
	backup, e := printstation.NewProofController(StationControllerQueue{func() *Node { return n }, stationCaller(pin.Peers[1])}, sender)
	if e != nil {
		t.Fatal(e)
	}
	if e = backup.Run(k.ID, testUUID(26102)); e == nil {
		t.Fatal("uncertain head sent to backup")
	}
	sender.mu.Lock()
	defer sender.mu.Unlock()
	if len(sender.calls) != 2 {
		t.Fatal(sender.calls)
	}
}
func TestStationProofControllerRefusesPhysicalTransport(t *testing.T) {
	router, e := printtransport.New(printtransport.Config{WorkerHostID: testUUID(1)})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = printstation.NewProofController(StationControllerQueue{}, router); e == nil {
		t.Fatal("physical router enabled")
	}
}
