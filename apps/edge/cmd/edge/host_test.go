package main

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/updater"
)

func TestUnboundLocalHostAndCleanRestart(t *testing.T) {
	root := t.TempDir()
	data := filepath.Join(root, "edge")
	s, e := store.Open(data, true)
	if e != nil {
		t.Fatal(e)
	}
	id, e := s.Init()
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	if id.VenueID != "" {
		t.Fatal("expected unbound foundation")
	}
	l, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	addr := l.Addr().String()
	l.Close()
	cfg := updater.Config{Root: filepath.Join(root, "pos"), Listen: addr, Token: strings.Repeat("a", 64), Feed: "https://127.0.0.1:1/unavailable", Channel: "fixture", InitialVersion: "1.8.0", InitialRelease: 1, Keys: map[string]updater.TrustedKey{"fixture": {Public: "unused", Expires: time.Now().Add(time.Hour)}}}
	u, e := updater.Open(cfg, updater.NativeProcess{})
	if e != nil {
		t.Fatal(e)
	}
	if e = u.Close(); e != nil {
		t.Fatal(e)
	}
	raw, _ := json.Marshal(cfg)
	file := filepath.Join(root, "updater.json")
	if e = os.WriteFile(file, raw, 0600); e != nil {
		t.Fatal(e)
	}
	stop := filepath.Join(root, "stop")
	for n := 0; n < 2; n++ {
		done := make(chan error, 1)
		go func() { done <- runLocalHost(data, file, stop) }()
		deadline := time.Now().Add(5 * time.Second)
		for {
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			r, _ := http.NewRequestWithContext(ctx, "GET", "http://"+addr+"/v1/status", nil)
			r.Header.Set("Authorization", "Bearer "+cfg.Token)
			resp, e := http.DefaultClient.Do(r)
			cancel()
			if e == nil {
				resp.Body.Close()
				if resp.StatusCode != 200 {
					t.Fatal(resp.Status)
				}
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("local updater not reachable", e)
			}
			time.Sleep(10 * time.Millisecond)
		}
		if e = os.WriteFile(stop, []byte("stop"), 0600); e != nil {
			t.Fatal(e)
		}
		select {
		case e := <-done:
			if e != nil {
				t.Fatal(e)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("host did not stop")
		}
		if e = os.Remove(stop); e != nil {
			t.Fatal(e)
		}
	}
	s, e = store.Open(data, false)
	if e != nil {
		t.Fatal(e)
	}
	after, e := s.Identity()
	if e != nil {
		t.Fatal(e)
	}
	s.Close()
	if after.InstallationID != id.InstallationID || after.VenueID != "" {
		t.Fatal("host changed foundation identity/authority")
	}
}
