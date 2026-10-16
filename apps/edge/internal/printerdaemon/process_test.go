package printerdaemon

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/printhost"
)

type lockedBuffer struct {
	mu   sync.Mutex
	data bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.data.Write(p)
}
func (b *lockedBuffer) String() string { b.mu.Lock(); defer b.mu.Unlock(); return b.data.String() }

type runningFixture struct {
	cmd        *exec.Cmd
	done       chan error
	diagnostic *lockedBuffer
	address    string
}

func actualCLI(t *testing.T) string {
	t.Helper()
	if path := os.Getenv("VYNIC_PRINTER_AGENT_BINARY"); path != "" {
		canonical, err := filepath.EvalSymlinks(path)
		if err != nil {
			t.Fatal(err)
		}
		if err = noReparse(canonical); err != nil {
			t.Fatal(err)
		}
		t.Log("actual supplied foreground executable:", canonical)
		return canonical
	}
	if runtime.GOOS == "windows" {
		t.Fatal("actual foreground executable requires VYNIC_PRINTER_AGENT_BINARY; qualification must not skip this fixture")
	}
	path := filepath.Join(canonicalTemp(t), "printer-agent")
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("source path unavailable")
	}
	module, err := filepath.EvalSymlinks(filepath.Join(filepath.Dir(file), "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("go", "build", "-mod=readonly", "-o", path, "./cmd/printer-agent")
	cmd.Dir = module
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("actual CLI build: %v\n%s", err, out)
	}
	t.Log("actual compiled foreground executable:", path)
	return path
}
func startProcess(t *testing.T, f softwareFixture, binary string) *runningFixture {
	t.Helper()
	marker := filepath.Join(f.config.StateDirectory, "printer-agent.stop")
	cmd := exec.Command(binary, "foreground", "--config", f.configPath, "--shutdown-file", marker)
	stderr := &lockedBuffer{}
	cmd.Stderr = stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	proc := &runningFixture{cmd: cmd, done: make(chan error, 1), diagnostic: stderr}
	ready := make(chan error, 1)
	go func() {
		var announcement struct {
			Listen           string
			SoftwareReady    bool
			PhysicalEligible bool
			Admission        string
			Pins             printhost.Pins
		}
		err := json.NewDecoder(stdout).Decode(&announcement)
		if err == nil && (!announcement.SoftwareReady || announcement.PhysicalEligible || announcement.Admission != ProvisioningHeld || announcement.Pins != f.config.Pins) {
			err = errors.New("startup readiness/binding/held profile differs")
		}
		proc.address = announcement.Listen
		ready <- err
	}()
	go func() { proc.done <- cmd.Wait() }()
	t.Cleanup(func() {
		select {
		case <-proc.done:
			return
		default:
		}
		_ = cmd.Process.Kill() // only this disposable synthetic child on test failure
		select {
		case <-proc.done:
		case <-time.After(5 * time.Second):
			t.Error("synthetic child did not terminate")
		}
	})
	select {
	case err = <-ready:
		if err != nil {
			t.Fatalf("foreground announce failed: %v %s", err, stderr.String())
		}
	case <-time.After(15 * time.Second):
		t.Fatalf("foreground startup timeout: %s", stderr.String())
	}
	if proc.address == "" {
		t.Fatal("actual foreground listener missing")
	}
	return proc
}
func stopProcess(t *testing.T, f softwareFixture, proc *runningFixture, wantError bool) {
	t.Helper()
	marker := filepath.Join(f.config.StateDirectory, "printer-agent.stop")
	if !wantError {
		writeBytes(t, marker, nil)
	}
	select {
	case err := <-proc.done:
		if (err != nil) != wantError {
			t.Fatalf("foreground exit: %v (expected failure=%v)\n%s", err, wantError, proc.diagnostic.String())
		}
	case <-time.After(10 * time.Second):
		t.Fatalf("foreground drain timeout: %s", proc.diagnostic.String())
	}
	// Record completion so cleanup never signals a PID already reaped.
	proc.done <- nil
	if !wantError {
		if err := os.Remove(marker); err != nil {
			t.Fatal(err)
		}
	}
}
func TestActualForegroundExecutableHealthExclusiveStopRestartAndRetention(t *testing.T) {
	binary := actualCLI(t)
	f := fixture(t, binary)
	j1, j2 := seedRetainedQueue(t, f)
	for iteration := 0; iteration < 2; iteration++ {
		proc := startProcess(t, f, binary)
		client, _ := connectFixture(t, f, proc.address)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		health, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: healthAuth(f)})
		cancel()
		if err != nil || !health.GetSoftwareReady() || len(health.GetPrinterHolds()) != 1 || health.GetPhysicalState() != pb.PrinterAgentPhysicalState_PRINTER_AGENT_PHYSICAL_HELD {
			t.Fatalf("actual process held health: %v %v", health, err)
		}
		secondCtx, secondCancel := context.WithTimeout(context.Background(), 10*time.Second)
		second := exec.CommandContext(secondCtx, binary, "foreground", "--config", f.configPath, "--shutdown-file", filepath.Join(f.config.StateDirectory, "printer-agent.stop"))
		out, err := second.CombinedOutput()
		secondCancel()
		if err == nil || !strings.Contains(string(out), "host owner") {
			t.Fatalf("actual second process admitted or wrong refusal: %v %s", err, out)
		}
		// Rejection of the second process does not disturb the first RPC owner.
		ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
		if _, err = client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: healthAuth(f)}); err != nil {
			t.Fatal(err)
		}
		cancel()
		stopProcess(t, f, proc, false)
		assertRetainedQueue(t, f, j1, j2)
	}
}
func TestActualForegroundExecutableRejectsWrongPinsRootRoleWithoutReset(t *testing.T) {
	binary := actualCLI(t)
	f := fixture(t, binary)
	original := f.config
	for _, name := range []string{"pins", "root", "role", "old-reader", "outside-stop-marker"} {
		t.Run(name, func(t *testing.T) {
			config := original
			marker := filepath.Join(config.StateDirectory, "printer-agent.stop")
			switch name {
			case "pins":
				config.Pins.ConfigRevision++
			case "root":
				config.StateDirectory = f.root
			case "role":
				config.Pins.Role = "unknown"
			case "old-reader":
				config.Pins.MinimumReaderVersion = 1
			case "outside-stop-marker":
				marker = filepath.Join(f.root, "printer-agent.stop")
			}
			writeJSON(t, f.configPath, config)
			before, _ := os.ReadFile(filepath.Join(original.StateDirectory, "edge.db"))
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, binary, "foreground", "--config", f.configPath, "--shutdown-file", marker)
			if out, err := cmd.CombinedOutput(); err == nil {
				t.Fatalf("wrong profile ran: %s", out)
			}
			after, _ := os.ReadFile(filepath.Join(original.StateDirectory, "edge.db"))
			if !bytes.Equal(before, after) {
				t.Fatal("failed foreground preflight rewrote state")
			}
		})
	}
}
func TestActualForegroundExecutableTrustedStorageAndArtifactFailuresDrain(t *testing.T) {
	binary := actualCLI(t)
	for _, name := range []string{"helper", "marker", "queue-table"} {
		t.Run(name, func(t *testing.T) {
			f := fixture(t, binary)
			proc := startProcess(t, f, binary)
			path := f.config.Helper.Path
			if name == "marker" {
				path = filepath.Join(f.config.StateDirectory, StateMarkerFilename)
			}
			if name == "queue-table" {
				// Deliberate isolated storage fault; this bypasses the normal
				// lock only inside a synthetic test, never in the executable.
				db, err := sql.Open("sqlite", filepath.Join(f.config.StateDirectory, "edge.db"))
				if err != nil {
					t.Fatal(err)
				}
				if _, err = db.Exec("DROP TABLE pq_claim"); err != nil {
					db.Close()
					t.Fatal(err)
				}
				if err = db.Close(); err != nil {
					t.Fatal(err)
				}
			} else {
				writeBytes(t, path, []byte("trusted input replaced"))
			}
			client, _ := connectFixture(t, f, proc.address)
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			health, err := client.Health(ctx, &pb.PrinterAgentHealthRequest{Auth: healthAuth(f)})
			cancel()
			if err == nil && health.GetSoftwareReady() {
				t.Fatal("changed input remained ready")
			}
			stopProcess(t, f, proc, true)
			if proc.diagnostic.String() == "" {
				t.Fatal("foreground trusted failure diagnostic hidden")
			}
		})
	}
}
