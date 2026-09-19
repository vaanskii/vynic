// terminal-sim has isolated, durable credentials; never imports Flutter/Hive.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/gofrs/flock"
	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/status"
	pb "vynic.local/contracts/go/vynic/edge/v1"
	"vynic.local/edge/internal/store"
)

type State struct{ TerminalID, Secret, RequestID, SessionID, Name, VenueID, InstallationID string }

func run() error {
	dir := flag.String("data", "", "isolated terminal directory")
	addr := flag.String("address", "127.0.0.1:7443", "Edge address")
	cert := flag.String("cert", "", "out-of-band trusted Edge certificate")
	venue := flag.String("venue", "", "expected Venue UUID")
	installation := flag.String("installation", "", "expected installation UUID")
	name := flag.String("name", "simulator", "terminal name")
	ticketFile := flag.String("ticket-file", "", "pairing ticket JSON file")
	watch := flag.Duration("watch", 0, "watch duration")
	major := flag.Uint("major", 1, "protocol major")
	bad := flag.Bool("invalid-credential", false, "negative authentication test")
	expected := flag.String("expect-code", "", "expected gRPC failure code")
	flag.Parse()
	if *dir == "" || *venue == "" || *installation == "" {
		return errors.New("--data, --venue and --installation required")
	}
	if err := os.MkdirAll(*dir, 0700); err != nil {
		return err
	}
	lock := flock.New(filepath.Join(*dir, "terminal.lock"))
	ok, err := lock.TryLock()
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("terminal state already in use")
	}
	defer lock.Unlock()
	path := filepath.Join(*dir, "terminal.json")
	b, err := os.ReadFile(path)
	var st State
	if errors.Is(err, os.ErrNotExist) {
		st = State{uuid.NewString(), store.Secret(), uuid.NewString(), uuid.NewString(), *name, *venue, *installation}
		b, err = json.Marshal(st)
		if err != nil {
			return err
		}
		// Persist the retry identity/secret before the first network request.
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return err
		}
		_, writeErr := f.Write(b)
		syncErr := f.Sync()
		closeErr := f.Close()
		if err = errors.Join(writeErr, syncErr, closeErr); err != nil {
			return err
		}
	} else if err != nil {
		return err
	} else if err = json.Unmarshal(b, &st); err != nil {
		return err
	}
	// Expected scope is supplied on every request to exercise wrong-Venue refusal.
	pem, err := os.ReadFile(*cert)
	if err != nil {
		return err
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(pem) {
		return errors.New("invalid trusted certificate")
	}
	conn, err := grpc.NewClient(*addr, grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{RootCAs: roots, ServerName: "vynic-edge.local", MinVersion: tls.VersionTLS13})))
	if err != nil {
		return err
	}
	defer conn.Close()
	client := pb.NewFoundationClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second+*watch)
	defer cancel()
	scope := &pb.Scope{VenueId: *venue, InstallationId: *installation, Protocol: &pb.Protocol{Major: uint32(*major)}}
	call := func() error {
		if *ticketFile != "" {
			b, err := os.ReadFile(*ticketFile)
			if err != nil {
				return err
			}
			var t struct{ Ticket string }
			if err = json.Unmarshal(b, &t); err != nil {
				return err
			}
			_, err = client.Pair(ctx, &pb.PairRequest{Scope: scope, Ticket: t.Ticket, RequestId: st.RequestID, TerminalId: st.TerminalID, TerminalSecret: st.Secret, DisplayName: st.Name})
			if err != nil {
				return err
			}
		}
		secret := st.Secret
		if *bad {
			secret = store.Secret()
		}
		auth := &pb.AuthenticatedRequest{Scope: scope, TerminalId: st.TerminalID, TerminalSecret: secret}
		res, err := client.Handshake(ctx, &pb.HandshakeRequest{Auth: auth, SessionId: st.SessionID, ClientVersion: "terminal-sim/1"})
		if err != nil {
			return err
		}
		if err = json.NewEncoder(os.Stdout).Encode(res); err != nil {
			return err
		}
		if *watch > 0 {
			wctx, stop := context.WithTimeout(ctx, *watch)
			defer stop()
			stream, err := client.WatchStatus(wctx, auth)
			if err != nil {
				return err
			}
			for {
				msg, err := stream.Recv()
				if err != nil {
					if status.Code(err) == codes.DeadlineExceeded || errors.Is(err, io.EOF) {
						return nil
					}
					return err
				}
				if err = json.NewEncoder(os.Stdout).Encode(msg); err != nil {
					return err
				}
			}
		}
		return nil
	}
	err = call()
	if *expected != "" {
		if status.Code(err).String() != *expected {
			return fmt.Errorf("expected %s, got %v", *expected, err)
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]string{"expectedRejection": *expected})
	}
	return err
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
