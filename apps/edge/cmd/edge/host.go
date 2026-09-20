package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/signal"
	"syscall"
	"time"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/updater"
)

// runLocalHost deliberately opens no LAN listener and requires no Venue binding.
// Enrollment and any future foundation binding remain separate operations.
func runLocalHost(dir, config, shutdown string) (result error) {
	s, e := store.Open(dir, false)
	if e != nil {
		return e
	}
	defer func() { result = errors.Join(result, s.Close()) }()
	if _, e = s.Identity(); e != nil {
		return e
	}
	raw, e := os.ReadFile(config)
	if e != nil {
		return e
	}
	var cfg updater.Config
	if e = json.Unmarshal(raw, &cfg); e != nil {
		return e
	}
	if e = os.Setenv("VYNIC_POS_UPDATER_CONFIG", config); e != nil {
		return e
	}
	u, e := updater.OpenExisting(cfg, updater.NativeProcess{})
	if e != nil {
		return e
	}
	defer func() { result = errors.Join(result, u.Close()) }()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if shutdown != "" {
		go func() {
			t := time.NewTicker(200 * time.Millisecond)
			defer t.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-t.C:
					if _, err := os.Stat(shutdown); err == nil {
						stop()
						return
					} else if !errors.Is(err, os.ErrNotExist) {
						stop()
						return
					}
				}
			}
		}()
	}
	return u.Run(ctx)
}
