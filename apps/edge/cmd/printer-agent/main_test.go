package main

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCLIRejectsEmptyUnknownAndActivationArguments(t *testing.T) {
	for _, args := range [][]string{{""}, {"--enable-physical"}, {"foreground", "--physical"}, {"service", "--config", "missing", "--shutdown-file", "other"}, {"unknown", "--config", "missing"}} {
		if err := run(args, io.Discard, io.Discard); err == nil {
			t.Fatal("unsupported argv accepted:", args)
		}
	}
}

type fakeForeground struct {
	start, wait, close error
	stops              int
}

func (d *fakeForeground) Start(context.Context) error { return d.start }
func (d *fakeForeground) Wait(context.Context) error  { return d.wait }
func (d *fakeForeground) Stop(context.Context) error  { d.stops++; return d.close }
func TestEveryForegroundExitDrainsAndPreservesOriginalFailure(t *testing.T) {
	for _, path := range []string{"startup", "announce", "wait"} {
		t.Run(path, func(t *testing.T) {
			original := errors.New("original " + path)
			d := &fakeForeground{}
			announce := func() error { return nil }
			switch path {
			case "startup":
				d.start = original
			case "announce":
				announce = func() error { return original }
			case "wait":
				d.wait = original
			}
			if err := runForeground(context.Background(), d, announce, io.Discard); !errors.Is(err, original) || d.stops != 1 {
				t.Fatal("original failure/drain absent", err, d.stops)
			}
		})
	}
}
func TestForegroundHeldChild(t *testing.T) {
	path := os.Getenv("VYNIC_TEST_FOREGROUND_CLOSE_FAILURE")
	if path == "" {
		return
	}
	d := &fakeForeground{close: errors.New("injected close remains unresolved")}
	original := errors.New("original " + path)
	announce := func() error { return nil }
	switch path {
	case "startup":
		d.start = original
	case "announce":
		announce = func() error { return original }
	case "wait":
		d.wait = original
	default:
		t.Fatal("invalid child fixture")
	}
	_ = runForeground(context.Background(), d, announce, os.Stderr)
	t.Fatal("unresolved close returned and could exit")
}
func TestEveryForegroundExitRetainsProcessOnUnresolvedClose(t *testing.T) {
	for _, path := range []string{"startup", "announce", "wait"} {
		t.Run(path, func(t *testing.T) {
			cmd := exec.Command(os.Args[0], "-test.run=^TestForegroundHeldChild$")
			cmd.Env = append(os.Environ(), "VYNIC_TEST_FOREGROUND_CLOSE_FAILURE="+path)
			stderr, err := cmd.StderrPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err = cmd.Start(); err != nil {
				t.Fatal(err)
			}
			done := make(chan error, 1)
			go func() { done <- cmd.Wait() }()
			t.Cleanup(func() { _ = cmd.Process.Kill() })
			line := make(chan string, 1)
			go func() {
				reader := bufio.NewReader(stderr)
				first, _ := reader.ReadString('\n')
				second, _ := reader.ReadString('\n')
				line <- first + second
			}()
			select {
			case diagnostic := <-line:
				if !strings.Contains(diagnostic, "ownership retained") || !strings.Contains(diagnostic, "original "+path) || !strings.Contains(diagnostic, "unresolved") {
					t.Fatal("failure diagnostic hidden", diagnostic)
				}
			case <-time.After(5 * time.Second):
				cmd.Process.Kill()
				t.Fatal("retained diagnostic missing")
			}
			select {
			case err := <-done:
				t.Fatal("failed close exited and released process", err)
			case <-time.After(50 * time.Millisecond):
			}
			// Kill only this otherwise intentionally retained disposable test child.
			if err = cmd.Process.Kill(); err != nil {
				t.Fatal(err)
			}
			select {
			case <-done:
			case <-time.After(5 * time.Second):
				t.Fatal("fixture kill did not settle")
			}
		})
	}
}
func TestForegroundLocalShutdownMarkerUsesNormalContextDrain(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "printer-agent.stop")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	failures := make(chan error, 1)
	go watchShutdown(ctx, cancel, path, failures)
	if err := os.WriteFile(path, nil, 0600); err != nil {
		t.Fatal(err)
	}
	select {
	case <-ctx.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("explicit marker did not request stop")
	}
	select {
	case err := <-failures:
		t.Fatal("valid empty marker failed", err)
	default:
	}
	d := &fakeForeground{}
	if err := runForeground(ctx, d, func() error { return nil }, io.Discard); err != nil || d.stops != 1 {
		t.Fatal("marker bypassed normal drain", err, d.stops)
	}
}
func TestMalformedShutdownMarkerReportsFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "printer-agent.stop")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	failures := make(chan error, 1)
	go watchShutdown(ctx, cancel, path, failures)
	if err := os.WriteFile(path, []byte("unexpected payload"), 0600); err != nil {
		t.Fatal(err)
	}
	select {
	case <-ctx.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("malformed marker did not fence")
	}
	select {
	case err := <-failures:
		if err == nil {
			t.Fatal("marker error absent")
		}
	default:
		t.Fatal("malformed marker silently stopped")
	}
}
func TestCLIPlanOnlyDoesNotInvokeUnsupportedPlatformBackend(t *testing.T) {
	// A wrong hash is visible even when no external service backend runs.
	var out bytes.Buffer
	if err := run([]string{"apply", "--plan", filepath.Join(t.TempDir(), "missing.json")}, &out, io.Discard); err == nil {
		t.Fatal("missing plan hidden")
	}
}
