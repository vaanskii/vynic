package printcluster

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"testing"
	"time"

	"vynic.local/edge/internal/printstation"
	"vynic.local/edge/internal/printtransport"
)

// Opt-in bounded measurements; synthetic transport cannot measure printer speed.
func TestStationSoftwarePerformance(t *testing.T) {
	if os.Getenv("VYNIC_STATION_PERF") != "1" {
		t.Skip("opt-in software measurement")
	}
	for _, sources := range []int{1, 3, 10} {
		for _, size := range []int{4096, 512 * 1024} {
			t.Run(fmt.Sprintf("sources_%d_bytes_%d", sources, size), func(t *testing.T) {
				pin := stationPin(t, sources)
				cluster := startCluster(t, pin)
				n := cluster.leader()
				ctx := context.Background()
				c := stationCatalog(t, pin)
				admin := stationCaller(pin.Peers[0])
				if e := n.InstallStations(ctx, admin, c); e != nil {
					t.Fatal(e)
				}
				disk := func() int64 {
					var total int64
					for _, dir := range cluster.dirs {
						if e := filepath.Walk(dir, func(_ string, i os.FileInfo, e error) error {
							if e != nil {
								return e
							}
							if !i.IsDir() {
								total += i.Size()
							}
							return nil
						}); e != nil {
							t.Fatal(e)
						}
					}
					return total
				}
				runtime.GC()
				var before, after runtime.MemStats
				runtime.ReadMemStats(&before)
				diskBefore := disk()
				var submit, commit, dequeue []float64
				var jobs []printstation.Job
				// Every source submits to both stations; sources are concurrent within a
				// round, while each station still obtains a committed FIFO sequence.
				for station := 0; station < 2; station++ {
					type measured struct {
						j  printstation.Job
						ms float64
						e  error
					}
					results := make(chan measured, sources)
					for i, p := range pin.Peers {
						j := stationJob(c, p, i*2+station, size, station)
						if os.Getenv("VYNIC_STATION_UNIQUE") == "1" {
							binary.LittleEndian.PutUint64(j.Payload, uint64(i*2+station))
							j.PayloadDigest = sha(j.Payload)
						}
						go func() {
							start := time.Now()
							_, e := n.SubmitStation(ctx, stationCaller(p), testUUID(20000+i*2+station), j)
							results <- measured{j, float64(time.Since(start).Microseconds()) / 1000, e}
						}()
					}
					for range sources {
						r := <-results
						if r.e != nil {
							t.Fatal(r.e)
						}
						submit = append(submit, r.ms)
						jobs = append(jobs, r.j)
					}
				}
				// Dequeue each actual station head in committed order, with independent
				// station passes. Transport returns synthetic accepted bytes immediately.
				for station := 0; station < 2; station++ {
					var rows []printstation.Record
					for _, j := range jobs {
						if j.StationID == c.Stations[station].ID {
							r, e := n.ReadStation(ctx, j.ID)
							if e != nil {
								t.Fatal(e)
							}
							rows = append(rows, r)
						}
					}
					slices.SortFunc(rows, func(a, b printstation.Record) int {
						if a.Sequence < b.Sequence {
							return -1
						}
						return 1
					})
					controller := pin.Peers[0]
					if station == 1 {
						controller = pin.Peers[2%len(pin.Peers)]
					}
					for i, row := range rows {
						a := stationCaller(controller)
						start := time.Now()
						x, e := n.BeginStationAttempt(ctx, a, row.Job.ID, testUUID(22000+station*100+i), 2)
						if e != nil {
							t.Fatal(e)
						}
						dequeue = append(dequeue, float64(time.Since(start).Microseconds())/1000)
						start = time.Now()
						if e = n.FinishStationAttempt(ctx, a, row.Job.ID, x.ID, 3, printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: uint32(size)}); e != nil {
							t.Fatal(e)
						}
						commit = append(commit, float64(time.Since(start).Microseconds())/1000)
					}
				}
				runtime.GC()
				runtime.ReadMemStats(&after)
				growth := disk() - diskBefore
				duplicateStart := time.Now()
				first := jobs[0]
				var firstPeer Peer
				for _, p := range pin.Peers {
					if p.DeviceID == first.SourceDeviceID {
						firstPeer = p
					}
				}
				firstReceipt := stationReceipt(n.fsm.state.Stations.Jobs[first.ID])
				duplicate, e := n.SubmitStation(ctx, stationCaller(firstPeer), testUUID(29999), first)
				if e != nil || duplicate != firstReceipt {
					t.Fatal("duplicate changed receipt", e)
				}
				duplicateMs := float64(time.Since(duplicateStart).Microseconds()) / 1000
				n.fsm.mu.RLock()
				persistMs := float64(n.fsm.payloadPersistTime.Microseconds()) / 1000
				persistCount := n.fsm.payloadPersistCount
				n.fsm.mu.RUnlock()
				snap, e := n.fsm.Snapshot()
				if e != nil {
					t.Fatal(e)
				}
				snapshotBytes := len(snap.(*projectionSnapshot).raw)
				if e = n.Snapshot(ctx); e != nil {
					t.Fatal(e)
				}
				start := time.Now()
				for i, node := range cluster.nodes {
					if e := node.Close(); e != nil {
						t.Fatal(e)
					}
					cluster.nodes[i] = nil
				}
				for i, p := range pin.Peers {
					if p.Role != Voter {
						continue
					}
					node, e := OpenLoopbackProof(cluster.dirs[i], pin, p.ID)
					if e != nil {
						t.Fatal(e)
					}
					cluster.nodes[i] = node
				}
				n = cluster.leader()
				if _, e := n.ReadStation(ctx, jobs[0].ID); e != nil {
					t.Fatal(e)
				}
				recovery := time.Since(start)
				summary := func(v []float64) map[string]float64 {
					slices.Sort(v)
					return map[string]float64{"min": v[0], "p50": v[len(v)/2], "p95": v[(len(v)*95+99)/100-1], "max": v[len(v)-1]}
				}
				out := map[string]any{"uniquePayloads": os.Getenv("VYNIC_STATION_UNIQUE") == "1", "duplicateRetryMs": duplicateMs, "snapshotBytes": snapshotBytes, "leaderPayloadPersistTotalMs": persistMs, "leaderPayloadPersistTransactions": persistCount, "sources": sources, "voters": pin.Voters, "stations": 2, "payloadBytes": size, "jobs": len(jobs), "submissionIncludingMajorityFinalizeMs": summary(submit), "majorityResultCommitMs": summary(commit), "controllerBeginCommitMs": summary(dequeue), "allNodesReopenAndElectionMs": float64(recovery.Microseconds()) / 1000, "heapAllocDeltaBytes": int64(after.HeapAlloc) - int64(before.HeapAlloc), "allocatedBytes": after.TotalAlloc - before.TotalAlloc, "replicaDiskGrowthBytes": growth, "physicalThroughput": "NOT_MEASURED"}
				raw, e := json.Marshal(out)
				if e != nil {
					t.Fatal(e)
				}
				t.Log("STATION_PERF " + string(raw))
			})
		}
	}
}
