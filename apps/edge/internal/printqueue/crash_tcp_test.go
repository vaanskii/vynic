//go:build !windows

package printqueue

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"testing"
	"time"

	"vynic.local/edge/internal/printtransport"
)

// observedTCP records entry and return around one actual kernel TCP Write. It
// changes no transport result, byte, retry or persistence policy.
type observedTCP struct {
	*net.TCPConn
	t    *testing.T
	path string
}

func (c *observedTCP) Write(payload []byte) (int, error) {
	durableTestFile(c.t, c.path+".write-entered", "entered", false)
	n, err := c.TCPConn.Write(payload)
	durableTestFile(c.t, c.path+".write-returned", strconv.Itoa(n), false)
	return n, err
}

func TestQueueTCPKillChild(t *testing.T) {
	path := os.Getenv("VYNIC_QUEUE_TCP_KILL_DB")
	if path == "" {
		t.Skip("child fixture exercised by TestActualTCPWriteSIGKILLNoReplay")
	}
	address := os.Getenv("VYNIC_QUEUE_TCP_KILL_ADDRESS")
	stage := os.Getenv("VYNIC_QUEUE_TCP_KILL_STAGE")
	host, _, err := net.SplitHostPort(address)
	if err != nil || host != "127.0.0.1" || stage != "duringWrite" && stage != "afterWriteBeforeDisposition" {
		t.Fatal("explicit loopback-only fixture required")
	}
	db := openDB(t, path, 6)
	store, err := NewProofStore(background, db, identity())
	if err != nil {
		t.Fatal(err)
	}
	router, err := printtransport.New(printtransport.Config{
		WorkerHostID: identity().WorkerHostID, TCPTimeout: 30 * time.Second,
		DialContext: func(ctx context.Context, network, target string) (net.Conn, error) {
			if network != "tcp" || target != address {
				return nil, errors.New("fixture refuses every nonselected loopback endpoint")
			}
			connection, err := (&net.Dialer{}).DialContext(ctx, network, target)
			if err != nil {
				return nil, err
			}
			tcp := connection.(*net.TCPConn)
			if err = tcp.SetWriteBuffer(4096); err != nil {
				return nil, errors.Join(err, tcp.Close())
			}
			return &observedTCP{TCPConn: tcp, t: t, path: path}, nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	// This test-only proof sender delegates solely to the literal selected
	// loopback receiver. Production NewProofScheduler still refuses Router.
	sender := &fakeSender{call: func(ctx context.Context, destination printtransport.Destination, payload []byte) printtransport.Result {
		result := router.Send(ctx, destination, payload)
		if stage == "afterWriteBeforeDisposition" {
			if result.State != printtransport.Submitted || !result.WriteAttempted || int(result.BytesWritten) != len(payload) {
				t.Fatalf("actual complete Write was not accepted: %+v", result)
			}
			durableTestFile(t, path+".send-returned", "submitted", false)
			select {} // before Scheduler can persist settlePrimary
		}
		return result
	}}
	s, err := NewProofScheduler(background, store, sender, proofOptions())
	if err != nil {
		t.Fatal(err)
	}
	if err = s.RunNext(uuid(21)); err != nil {
		t.Fatal(err)
	}
	t.Fatal("selected TCP process-kill boundary not reached")
}

func TestActualTCPWriteSIGKILLNoReplay(t *testing.T) {
	for _, stage := range []string{"duringWrite", "afterWriteBeforeDisposition"} {
		t.Run(stage, func(t *testing.T) {
			listener, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.ParseIP("127.0.0.1")})
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = listener.Close() })
			if err = listener.SetDeadline(time.Now().Add(15 * time.Second)); err != nil {
				t.Fatal(err)
			}
			f := newFixture(t)
			r := registry(21)
			r.Destination.Port = uint16(listener.Addr().(*net.TCPAddr).Port)
			if err = f.store.Register(background, r); err != nil {
				t.Fatal(err)
			}
			j := modify(t, job(t, 10, 21, 1, false), func(j *FrozenJob) {
				j.Destination.Port = r.Destination.Port
				if stage == "duringWrite" {
					j.PrimaryBytes = bytes.Repeat([]byte{'T'}, 2*1024*1024-3)
					j.PrimaryBytes = append(j.PrimaryBytes, 0x1d, 0x56, 0x01)
					h := sha256.Sum256(j.PrimaryBytes)
					j.PrimarySHA256 = hex.EncodeToString(h[:])
				}
			})
			first := admitJob(t, f, j)
			if err = f.db.Close(); err != nil {
				t.Fatal(err)
			}
			executable, err := os.Executable()
			if err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command(executable, "-test.run=^TestQueueTCPKillChild$", "-test.timeout=45s")
			cmd.Env = append(os.Environ(), "VYNIC_QUEUE_TCP_KILL_DB="+f.path, "VYNIC_QUEUE_TCP_KILL_ADDRESS="+listener.Addr().String(), "VYNIC_QUEUE_TCP_KILL_STAGE="+stage)
			var childLog bytes.Buffer
			cmd.Stdout, cmd.Stderr = &childLog, &childLog
			if err = cmd.Start(); err != nil {
				t.Fatal(err)
			}
			waited := false
			defer func() {
				if !waited {
					_ = cmd.Process.Kill()
					_ = cmd.Wait()
				}
			}()
			receiver, err := listener.AcceptTCP()
			if err != nil {
				t.Fatal("child did not reach real loopback receiver", err)
			}
			t.Cleanup(func() { _ = receiver.Close() })
			if err = receiver.SetReadBuffer(4096); err != nil {
				t.Fatal(err)
			}
			if err = receiver.SetReadDeadline(time.Now().Add(15 * time.Second)); err != nil {
				t.Fatal(err)
			}
			var received []byte
			if stage == "duringWrite" {
				received = make([]byte, 1)
				if _, err = io.ReadFull(receiver, received); err != nil {
					t.Fatal("no actual byte reached receiver", err)
				}
				// Receiver deliberately leaves the remainder unread. With small
				// TCP buffers the 2 MiB Write cannot complete before this kill.
				if _, err = os.Stat(f.path + ".write-entered"); err != nil {
					t.Fatal("actual Write entry missing", err)
				}
				if _, err = os.Stat(f.path + ".write-returned"); !os.IsNotExist(err) {
					t.Fatal("Write already returned; not a mid-Write kill", err)
				}
			} else {
				received, err = io.ReadAll(receiver)
				if err != nil || !bytes.Equal(received, j.PrimaryBytes) {
					t.Fatalf("complete immutable bytes/cut not received: %d/%d %v", len(received), len(j.PrimaryBytes), err)
				}
				deadline := time.Now().Add(5 * time.Second)
				for {
					if _, err = os.Stat(f.path + ".send-returned"); err == nil {
						break
					}
					if !os.IsNotExist(err) || time.Now().After(deadline) {
						t.Fatal("complete transport return boundary missing", err)
					}
					time.Sleep(5 * time.Millisecond)
				}
			}
			if err = cmd.Process.Signal(syscall.SIGKILL); err != nil {
				t.Fatal(err)
			}
			err = cmd.Wait()
			waited = true
			status, ok := cmd.ProcessState.Sys().(syscall.WaitStatus)
			if err == nil || !ok || !status.Signaled() || status.Signal() != syscall.SIGKILL {
				t.Fatalf("not actual SIGKILL: %v %v %s", err, status, childLog.String())
			}
			if stage == "duringWrite" {
				remaining, err := io.ReadAll(receiver)
				if err != nil {
					t.Fatal("killed TCP connection did not settle", err)
				}
				received = append(received, remaining...)
				if len(received) == 0 || len(received) >= len(j.PrimaryBytes) || !bytes.Equal(received, j.PrimaryBytes[:len(received)]) {
					t.Fatalf("expected actual partial immutable kernel write: %d/%d", len(received), len(j.PrimaryBytes))
				}
				if _, err = os.Stat(f.path + ".write-returned"); !os.IsNotExist(err) {
					t.Fatal("killed Write unexpectedly returned", err)
				}
			}
			db := openDB(t, f.path, 6)
			fresh, err := NewProofStore(background, db, identity())
			if err != nil {
				t.Fatal(err)
			}
			f.db, f.store = db, fresh
			recoveryCalls := 0
			s := scheduler(t, f, &fakeSender{call: func(_ context.Context, _ printtransport.Destination, payload []byte) printtransport.Result {
				recoveryCalls++
				return accepted(payload)
			}}, proofOptions())
			outcome, err := fresh.Outcome(background, j.JobID)
			if err != nil || outcome.Primary != Uncertain || outcome.Phase != "hold" {
				t.Fatalf("interrupted actual TCP attempt lost uncertainty: %+v %v", outcome, err)
			}
			if err = s.RunNext(j.PhysicalPrinterID); !errors.Is(err, ErrBusy) || recoveryCalls != 0 {
				t.Fatalf("actual TCP attempt automatically replayed: %v calls=%d", err, recoveryCalls)
			}
			retry, err := fresh.Accept(background, authority(j), j)
			if err != nil || retry != first || count(t, db, "pq_job") != 1 || count(t, db, "pq_attempt") != 1 {
				t.Fatalf("immutable receipt/attempt changed after crash: %+v %v", retry, err)
			}
			var integrity string
			if err = db.QueryRow("PRAGMA integrity_check").Scan(&integrity); err != nil || integrity != "ok" {
				t.Fatal("crash database integrity", integrity, err)
			}
			t.Logf("actual SIGKILL %s; receiver bytes=%d/%d; UNCERTAIN; recovery calls=0; receipt sequence=%d; paper delivery unobserved", stage, len(received), len(j.PrimaryBytes), retry.Sequence)
		})
	}
}
