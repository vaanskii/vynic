package printcluster

import (
	"bufio"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"vynic.local/edge/internal/printstation"
)

func TestStationSpoolProcessChild(t *testing.T) {
	dir := os.Getenv("VYNIC_STATION_CHILD_DIR")
	if dir == "" {
		t.Skip("child fixture exercised by parent")
	}
	raw, e := os.ReadFile(filepath.Join(dir, "pin.json"))
	if e != nil {
		t.Fatal(e)
	}
	var pin ClusterConfig
	if e = json.Unmarshal(raw, &pin); e != nil {
		t.Fatal(e)
	}
	s, e := OpenLocalStationProof(filepath.Join(dir, "spool"), pin)
	if e != nil {
		t.Fatal(e)
	}
	c := stationCatalog(t, pin)
	a := stationCaller(pin.Peers[0])
	if e = s.Install(a, c); e != nil {
		t.Fatal(e)
	}
	j := stationJob(c, pin.Peers[0], 1, 4096, 0)
	if _, e = s.Submit(a, testUUID(27000), j); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Begin(context.Background(), a, j.ID, testUUID(27001), 2); e != nil {
		t.Fatal(e)
	}
	if _, e = os.Stdout.WriteString("STATION_STARTED_DURABLE\n"); e != nil {
		t.Fatal(e)
	}
	// Parent kills this exact fixture PID; no graceful spool closure occurs.
	time.Sleep(time.Minute)
	t.Fatal("parent did not terminate fixture")
}
func TestStationSpoolProcessKillAndIndependentRestart(t *testing.T) {
	dir := t.TempDir()
	_, base := golden(t, "local_tcp")
	pin := testPin(t, 1, Local, base, false, false)
	if e := os.WriteFile(filepath.Join(dir, "pin.json"), printstation.Encode(pin), 0600); e != nil {
		t.Fatal(e)
	}
	exe, e := os.Executable()
	if e != nil {
		t.Fatal(e)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, exe, "-test.run=^TestStationSpoolProcessChild$")
	cmd.Env = append(os.Environ(), "VYNIC_STATION_CHILD_DIR="+dir)
	pipe, e := cmd.StdoutPipe()
	if e != nil {
		t.Fatal(e)
	}
	cmd.Stderr = os.Stderr
	if e = cmd.Start(); e != nil {
		t.Fatal(e)
	}
	ready := false
	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		if scanner.Text() == "STATION_STARTED_DURABLE" {
			ready = true
			break
		}
	}
	if !ready {
		_ = cmd.Wait()
		t.Fatalf("child did not flush: %v", scanner.Err())
	}
	if e = cmd.Process.Kill(); e != nil {
		t.Fatal(e)
	}
	if e = cmd.Wait(); e == nil {
		t.Fatal("child exited without forced termination")
	}
	s, e := OpenLocalStationProof(filepath.Join(dir, "spool"), pin)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	c := stationCatalog(t, pin)
	j := stationJob(c, pin.Peers[0], 1, 4096, 0)
	r, e := s.Inspect(j.ID)
	if e != nil || r.State != printstation.Uncertain || len(r.Attempts) != 1 {
		t.Fatal(r, e)
	}
	a := stationCaller(pin.Peers[0])
	receipt, e := s.Submit(a, testUUID(27000), j)
	if e != nil || receipt.Sequence != 1 || receipt.CommitIndex != r.CommitIndex {
		t.Fatal(receipt, e)
	}
	if _, e = s.Begin(context.Background(), a, j.ID, testUUID(27002), 3); e == nil {
		t.Fatal("interrupted physical attempt replayed")
	}
}
