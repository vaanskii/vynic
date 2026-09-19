package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"vynic.local/edge/internal/server"
	"vynic.local/edge/internal/store"
)

func run() (result error) {
	if len(os.Args) < 2 {
		return errors.New("usage: edge init|bind|ticket|revoke|inspect|serve --data DIR")
	}
	action := os.Args[1]
	flags := flag.NewFlagSet(action, flag.ContinueOnError)
	dir := flags.String("data", "", "required local data directory")
	listen := flags.String("listen", "127.0.0.1:7443", "gRPC TLS listen address")
	grant := flags.String("grant-file", "", "bootstrap grant file")
	cloudKey := flags.String("cloud-key", "", "trusted Cloud public PEM file")
	terminal := flags.String("terminal", "", "terminal UUID to revoke")
	if err := flags.Parse(os.Args[2:]); err != nil {
		return err
	}
	if *dir == "" {
		return errors.New("--data is required")
	}
	if action != "init" && action != "bind" && action != "ticket" && action != "revoke" && action != "inspect" && action != "serve" {
		return errors.New("unknown command")
	}
	s, err := store.Open(*dir, action == "init")
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, s.Close()) }()
	out := json.NewEncoder(os.Stdout)
	switch action {
	case "init":
		id, err := s.Init()
		if err != nil {
			return err
		}
		if err = os.WriteFile(filepath.Join(*dir, "edge-cert.pem"), id.Certificate, 0600); err != nil {
			return err
		}
		return out.Encode(id)
	case "bind":
		b, err := os.ReadFile(*grant)
		if err != nil {
			return err
		}
		key, err := os.ReadFile(*cloudKey)
		if err != nil {
			return err
		}
		if err = s.Bind(string(b), key); err != nil {
			return err
		}
		return out.Encode(map[string]string{"mode": "FOUNDATION_ONLY"})
	case "ticket":
		token, err := s.IssueTicket()
		if err != nil {
			return err
		}
		return out.Encode(map[string]string{"ticket": token})
	case "revoke":
		if err = s.Revoke(*terminal); err != nil {
			return err
		}
		return out.Encode(map[string]bool{"revoked": true})
	case "inspect":
		id, err := s.Identity()
		if err != nil {
			return err
		}
		return out.Encode(id)
	case "serve":
		srv, err := server.New(s)
		if err != nil {
			return err
		}
		l, err := net.Listen("tcp", *listen)
		if err != nil {
			return err
		}
		defer l.Close()
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer stop()
		if err = out.Encode(map[string]any{"listen": l.Addr().String(), "bootId": srv.BootID, "mode": "FOUNDATION_ONLY", "businessMutationsEnabled": false}); err != nil {
			return err
		}
		return srv.Serve(ctx, l)
	}
	return nil
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
