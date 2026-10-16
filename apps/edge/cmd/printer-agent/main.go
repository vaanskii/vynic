package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"vynic.local/edge/internal/printerdaemon"
)

func run(args []string, out, diagnostic io.Writer) error {
	mode := "foreground"
	if len(args) > 0 && args[0] == "" {
		return errors.New("empty printer-agent mode refused")
	}
	if len(args) > 0 && len(args[0]) > 0 && args[0][0] != '-' {
		mode, args = args[0], args[1:]
	}
	if mode == "plan" || mode == "bundle" || mode == "apply" {
		return runPackaging(mode, args, out, diagnostic)
	}
	flags := flag.NewFlagSet("printer-agent "+mode, flag.ContinueOnError)
	flags.SetOutput(diagnostic)
	configPath := flags.String("config", "", "explicit provisioned held profile; no default state or credentials")
	shutdownFile := flags.String("shutdown-file", "", "optional empty stop marker in the dedicated state directory; foreground only")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 || *configPath == "" {
		return errors.New("usage: printer-agent foreground|service|validate --config ABSOLUTE_FILE")
	}
	if mode != "foreground" && mode != "service" && mode != "validate" {
		return errors.New("unsupported printer-agent mode")
	}
	if *shutdownFile != "" && mode != "foreground" {
		return errors.New("shutdown-file is supported only for foreground mode")
	}
	config, err := printerdaemon.LoadConfig(*configPath)
	if err != nil {
		return err
	}
	if *shutdownFile != "" {
		if *shutdownFile != filepath.Join(config.StateDirectory, "printer-agent.stop") {
			return errors.New("shutdown-file must be the dedicated state's printer-agent.stop marker")
		}
		if _, err := os.Lstat(*shutdownFile); !errors.Is(err, os.ErrNotExist) {
			return errors.New("shutdown-file already exists or cannot be inspected; explicit cleanup required")
		}
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	executable, err = filepath.EvalSymlinks(executable)
	if err != nil {
		return err
	}
	daemon, err := printerdaemon.New(config, executable)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(out)
	if mode == "validate" {
		return encoder.Encode(map[string]any{"valid": true, "profile": config.Profile, "physicalEligible": false, "admission": printerdaemon.ProvisioningHeld})
	}
	if mode == "service" {
		return runWindowsService(daemon, config.ServicePrincipal, diagnostic)
	}
	signalCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithCancel(signalCtx)
	defer cancel()
	watchFailure := make(chan error, 1)
	if *shutdownFile != "" {
		go watchShutdown(ctx, cancel, *shutdownFile, watchFailure)
	}
	err = runForeground(ctx, daemon, func() error {
		return encoder.Encode(map[string]any{"agent": "vynic-printer-agent.v1", "listen": daemon.Address(), "profile": config.Profile, "pins": config.Pins, "softwareReady": true, "physicalEligible": false, "holdReason": printerdaemon.PhysicalHoldReason, "admission": printerdaemon.ProvisioningHeld, "inventoryQualification": "HELD_FOR_SELECTED_SERVICE_PRINCIPAL"})
	}, diagnostic)
	select {
	case failure := <-watchFailure:
		return errors.Join(err, failure)
	default:
		return err
	}
}

// The optional local marker only requests the same retained lifecycle drain as
// a foreground signal. It grants no remote/SCM control and is never removed or
// created by the agent. A stale or malformed marker requires explicit review.
func watchShutdown(ctx context.Context, cancel context.CancelFunc, path string, failures chan<- error) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			info, err := os.Lstat(path)
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil || !info.Mode().IsRegular() || info.Size() != 0 {
				failures <- errors.New("foreground shutdown marker invalid; retained drain requested")
			}
			cancel()
			return
		}
	}
}

type foregroundAgent interface {
	Start(context.Context) error
	Wait(context.Context) error
	Stop(context.Context) error
}

func runForeground(ctx context.Context, daemon foregroundAgent, announce func() error, diagnostic io.Writer) error {
	if err := daemon.Start(ctx); err != nil {
		return finishDaemon(daemon, err, diagnostic)
	}
	if err := announce(); err != nil {
		return finishDaemon(daemon, err, diagnostic)
	}
	return finishDaemon(daemon, daemon.Wait(ctx), diagnostic)
}

// Every post-Start exit uses the same original drain and retained-failure path,
// including startup and initial output failures. No failed cleanup reaches main
// and releases the process owner by voluntary exit.
func finishDaemon(daemon foregroundAgent, original error, diagnostic io.Writer) error {
	if err := daemon.Stop(context.Background()); err != nil {
		// A failed close retains the host guard. Voluntary process exit must
		// not turn that failure into a replacement writer's admission.
		fmt.Fprintln(diagnostic, "printer agent remains held; ownership retained:", errors.Join(original, err))
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for {
			<-ticker.C
			fmt.Fprintln(diagnostic, "printer agent remains held; explicit recovery required")
		}
	}
	return original
}

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
