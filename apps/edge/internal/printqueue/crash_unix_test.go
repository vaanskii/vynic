//go:build !windows

package printqueue

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"testing"
	"time"

	"vynic.local/edge/internal/printtransport"
)

func durableTestFile(t *testing.T, path, text string, appendMode bool) {
	t.Helper()
	flags := os.O_WRONLY | os.O_CREATE | os.O_TRUNC
	if appendMode {
		flags = os.O_WRONLY | os.O_CREATE | os.O_APPEND
	}
	f, err := os.OpenFile(path, flags, 0600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.WriteString(text); err != nil {
		t.Fatal(err)
	}
	if err = f.Sync(); err != nil {
		t.Fatal(err)
	}
	if err = f.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestQueueSIGKILLHelper(t *testing.T) {
	path := os.Getenv("VYNIC_QUEUE_CRASH_DB")
	if path == "" {
		return
	}
	stage := os.Getenv("VYNIC_QUEUE_CRASH_STAGE")
	db := openDB(t, path, 6)
	store, err := NewProofStore(background, db, identity())
	if err != nil {
		t.Fatal(err)
	}
	pause := func(current string) {
		if current == stage {
			durableTestFile(t, path+".ready", current, false)
			select {}
		}
	}
	options := proofOptions()
	options.AfterPersist = func(boundary Boundary, _ FrozenJob) error {
		if stage == "notSentPrimaryFlushed" && boundary == PrimaryFlushed {
			pause(stage)
		}
		pause(string(boundary))
		return nil
	}
	sender := &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		kind := "primary"
		if bytes.Equal(p, []byte{0x1b, 0x28, 0x41, 3, 0, 0x61, 1, 1}) {
			kind = "beep"
		}
		durableTestFile(t, path+".sends", kind+"\n", true)
		if stage == "notSentPrimaryFlushed" {
			return printtransport.Result{State: printtransport.NotSent, Stage: "synthetic refusal"}
		}
		pause(kind + "NativeNoACK")
		return accepted(p)
	}}
	s, err := NewProofScheduler(background, store, sender, options)
	if err != nil {
		t.Fatal(err)
	}
	pause("admittedFlushed")
	if err = s.RunNext(uuid(21)); err != nil {
		t.Fatal(err)
	}
	t.Fatal("selected SIGKILL boundary not reached")
}

func TestActualSIGKILLDurabilityAndNoReplay(t *testing.T) {
	for _, stage := range []string{"admittedFlushed", string(StartedFlushed), "primaryNativeNoACK", string(PrimaryFlushed), "notSentPrimaryFlushed", string(BeepReservedFlushed), "beepNativeNoACK", string(BeepFlushed), string(CompletedFlushed)} {
		t.Run(stage, func(t *testing.T) {
			f := newFixture(t)
			if err := f.store.Register(background, registry(21)); err != nil {
				t.Fatal(err)
			}
			j := job(t, 10, 21, 1, true)
			first := admitJob(t, f, j)
			if err := f.db.Close(); err != nil {
				t.Fatal(err)
			}
			executable, err := os.Executable()
			if err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command(executable, "-test.run=^TestQueueSIGKILLHelper$", "-test.timeout=20s")
			cmd.Env = append(os.Environ(), "VYNIC_QUEUE_CRASH_DB="+f.path, "VYNIC_QUEUE_CRASH_STAGE="+stage)
			var log bytes.Buffer
			cmd.Stdout = &log
			cmd.Stderr = &log
			if err = cmd.Start(); err != nil {
				t.Fatal(err)
			}
			killed := false
			defer func() {
				if !killed {
					_ = cmd.Process.Kill()
					_ = cmd.Wait()
				}
			}()
			deadline := time.Now().Add(5 * time.Second)
			for {
				if _, err = os.Stat(f.path + ".ready"); err == nil {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("helper failed to flush selected boundary")
				}
				time.Sleep(5 * time.Millisecond)
			}
			if err = cmd.Process.Signal(syscall.SIGKILL); err != nil {
				t.Fatal(err)
			}
			err = cmd.Wait()
			killed = true
			status, ok := cmd.ProcessState.Sys().(syscall.WaitStatus)
			if err == nil || !ok || !status.Signaled() || status.Signal() != syscall.SIGKILL {
				t.Fatalf("not actual SIGKILL: %v %v %s", err, status, log.String())
			}
			db := openDB(t, f.path, 6)
			fresh, err := NewProofStore(background, db, identity())
			if err != nil {
				t.Fatal(err)
			}
			f.db = db
			f.store = fresh
			var sends []string
			if raw, err := os.ReadFile(f.path + ".sends"); err == nil {
				sends = strings.Fields(string(raw))
			} else if !os.IsNotExist(err) {
				t.Fatal(err)
			}
			newCalls := 0
			s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
				newCalls++
				return accepted(p)
			}}, proofOptions())
			o, err := f.store.Outcome(background, j.JobID)
			if err != nil {
				t.Fatal(err)
			}
			switch stage {
			case "admittedFlushed":
				if o.Primary != Queued || len(sends) != 0 {
					t.Fatalf("queued recovery: %+v %v", o, sends)
				}
				if err = s.RunNext(uuid(21)); err != nil || newCalls != 2 {
					t.Fatalf("never-started job not dispatched once: %v calls=%d", err, newCalls)
				}
			case string(StartedFlushed), "primaryNativeNoACK":
				if o.Primary != Uncertain || o.Phase != "hold" {
					t.Fatalf("interrupted primary replayed: %+v", o)
				}
				if err = s.RunNext(uuid(21)); !errors.Is(err, ErrBusy) || newCalls != 0 {
					t.Fatalf("uncertain barrier: %v calls=%d", err, newCalls)
				}
			case "notSentPrimaryFlushed":
				if o.Primary != NotSent || o.Phase != "complete" || count(t, db, "pq_claim") != 0 {
					t.Fatalf("stale complete claim: %+v", o)
				}
				admitJob(t, f, job(t, 11, 21, 2, false))
				if err = s.RunNext(uuid(21)); err != nil || newCalls != 1 {
					t.Fatalf("refusal blocked later job: %v calls=%d", err, newCalls)
				}
			default:
				if o.Primary != Submitted || o.Phase != "complete" {
					t.Fatalf("accepted primary lost: %+v", o)
				}
				if stage == string(PrimaryFlushed) && o.Beep != BeepSkipped {
					t.Fatal("unreserved beep replay policy")
				}
				if (stage == string(BeepReservedFlushed) || stage == "beepNativeNoACK") && o.Beep != BeepUncertain {
					t.Fatal("spent beep replay policy")
				}
				if err = s.RunNext(uuid(21)); !errors.Is(err, ErrNoWork) || newCalls != 0 {
					t.Fatalf("accepted primary replayed: %v calls=%d", err, newCalls)
				}
			}
			if len(sends) > 2 || len(sends) > 0 && sends[0] != "primary" || len(sends) == 2 && sends[1] != "beep" {
				t.Fatal("unexpected send sequence", sends)
			}
			var integrity string
			if err = db.QueryRow("PRAGMA integrity_check").Scan(&integrity); err != nil || integrity != "ok" {
				t.Fatal("corrupt crash database", integrity, err)
			}
			retry, err := f.store.Accept(background, authority(j), j)
			jobsExpected := 1
			if stage == "notSentPrimaryFlushed" {
				jobsExpected = 2
			}
			if err != nil || retry != first || count(t, db, "pq_job") != jobsExpected {
				t.Fatalf("SIGKILL exact receipt: %+v %v", retry, err)
			}
			t.Logf("actual SIGKILL at %s; original sends=%v; recovery calls=%d; immutable receipt sequence=%d", stage, sends, newCalls, retry.Sequence)
		})
	}
}

func TestCompetingProcessCannotRecoverOrSubmit(t *testing.T) {
	f := newFixture(t)
	if err := f.store.Register(background, registry(21)); err != nil {
		t.Fatal(err)
	}
	admitJob(t, f, job(t, 10, 21, 1, true))
	owner := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, p []byte) printtransport.Result {
		return accepted(p)
	}}, proofOptions())
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(executable, "-test.run=^TestQueueSIGKILLHelper$", "-test.timeout=5s")
	cmd.Env = append(os.Environ(), "VYNIC_QUEUE_CRASH_DB="+f.path, "VYNIC_QUEUE_CRASH_STAGE=admittedFlushed")
	raw, err := cmd.CombinedOutput()
	if err == nil || !bytes.Contains(raw, []byte(ErrBusy.Error())) {
		t.Fatalf("second process obtained worker: %v %s", err, raw)
	}
	if count(t, f.db, "pq_attempt") != 0 {
		t.Fatal("competing process created an attempt")
	}
	if err = owner.RunNext(uuid(21)); err != nil {
		t.Fatal(err)
	}
	t.Log(fmt.Sprintf("exclusive live worker refused a separate process, then submitted once"))
}
