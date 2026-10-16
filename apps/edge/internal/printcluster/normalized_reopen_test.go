package printcluster

import (
	"context"
	"testing"
)

func TestNormalizedReopenRetainsStation(t *testing.T) {
	pin := stationPin(t, 1)
	c := startCluster(t, pin)
	n := c.leader()
	ctx := context.Background()
	cat := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	if e := n.InstallStations(ctx, a, cat); e != nil {
		t.Fatal(e)
	}
	if _, e := n.SubmitStation(ctx, a, testUUID(888), stationJob(cat, pin.Peers[0], 1, 4096, 0)); e != nil {
		t.Fatal(e)
	}
	if e := n.Close(); e != nil {
		t.Fatal(e)
	}
	c.nodes[0] = nil
	f, e := openProjection(c.dirs[0], pin)
	if e != nil {
		t.Fatal(e)
	}
	f.close()
}
