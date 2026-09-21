package store_test

import (
	"context"
	"database/sql"
	"github.com/google/uuid"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/testutil"
)

func TestStoreLockAndImmutableGrant(t *testing.T) {
	dir := t.TempDir()
	s, id := testutil.Bound(t, dir)
	defer s.Close()
	if other, e := store.Open(dir, false); e == nil {
		other.Close()
		t.Fatal("second process admitted")
	}
	for _, kind := range []string{"expired", "foreign-installation", "foreign-key", "foreign-venue", "tampered"} {
		t.Run(kind, func(t *testing.T) {
			copy := id
			issued, expires := time.Now().Unix(), time.Now().Unix()+600
			switch kind {
			case "expired":
				issued -= 700
				expires -= 700
			case "foreign-installation":
				copy.InstallationID = uuid.NewString()
			case "foreign-key":
				copy.PublicKey = store.Secret()
			case "foreign-venue":
				copy.VenueID = uuid.NewString()
			}
			g, key := testutil.Grant(t, copy, issued, expires)
			if kind == "tampered" {
				g = "x" + g
			}
			if e := s.Bind(g, key); e == nil {
				t.Fatal("invalid binding admitted")
			}
		})
	}
}
func TestIncompatibleAndCorruptStoreFailsClosed(t *testing.T) {
	for _, kind := range []string{"newer", "foreign-app", "checksum", "missing-table", "ledger", "altered-shape"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			s, _ := testutil.Bound(t, dir)
			switch kind {
			case "newer":
				s.DB.Exec("PRAGMA user_version=99")
			case "foreign-app":
				s.DB.Exec("PRAGMA application_id=1")
			case "checksum":
				s.DB.Exec("UPDATE schema_migration SET checksum='altered'")
			case "missing-table":
				s.DB.Exec("DROP TABLE session")
			case "altered-shape":
				s.DB.Exec("ALTER TABLE terminal ADD COLUMN unexpected TEXT")
			case "ledger":
				s.DB.Exec("DELETE FROM schema_migration")
			}
			s.Close()
			path := filepath.Join(dir, "edge.db")
			before, _ := os.ReadFile(path)
			other, e := store.Open(dir, false)
			if e == nil {
				other.Close()
				t.Fatal("incompatible store accepted")
			}
			after, _ := os.ReadFile(path)
			if string(before) != string(after) {
				t.Fatal("refusal rewrote database")
			}
		})
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "edge.db")
	os.WriteFile(path, []byte("corrupted sqlite data"), 0600)
	if s, e := store.Open(dir, false); e == nil {
		s.Close()
		t.Fatal("corruption accepted")
	}
	b, _ := os.ReadFile(path)
	if string(b) != "corrupted sqlite data" {
		t.Fatal("corruption reset")
	}
}
func TestAtomicPairAndRollback(t *testing.T) {
	s, _ := testutil.Bound(t, t.TempDir())
	defer s.Close()
	ticket, e := s.IssueTicket()
	if e != nil {
		t.Fatal(e)
	}
	// Force a failure between terminal INSERT and ticket consumption.
	if _, e = s.DB.Exec("CREATE TRIGGER refuse_consumption BEFORE UPDATE ON pairing_ticket BEGIN SELECT RAISE(ABORT,'test crash window'); END"); e != nil {
		t.Fatal(e)
	}
	terminal, request, secret := uuid.NewString(), uuid.NewString(), store.Secret()
	if e = s.Pair(context.Background(), ticket, request, terminal, secret, "A"); e == nil {
		t.Fatal("expected injected failure")
	}
	var count int
	s.DB.QueryRow("SELECT count(*) FROM terminal").Scan(&count)
	if count != 0 {
		t.Fatal("partial terminal commit")
	}
	if _, e = s.DB.Exec("DROP TRIGGER refuse_consumption"); e != nil {
		t.Fatal(e)
	}
	if e = s.Pair(context.Background(), ticket, request, terminal, secret, "A"); e != nil {
		t.Fatal(e)
	}
	var raw string
	var used sql.NullString
	if e = s.DB.QueryRow("SELECT verifier,request_id FROM pairing_ticket").Scan(&raw, &used); e != nil || raw == ticket || used.String != request {
		t.Fatal("bad ticket persistence", e)
	}
}

// The helper deliberately exits without Close/Rollback to simulate an interrupted
// process in the middle of a transaction, separate from graceful recovery tests.
func TestCrashWorker(t *testing.T) {
	dir := os.Getenv("VYNIC_TEST_CRASH_DIR")
	if dir == "" {
		t.Skip("subprocess only")
	}
	s, _ := testutil.Bound(t, dir)
	ticket, err := s.IssueTicket()
	if err != nil {
		t.Fatal(err)
	}
	terminal := uuid.NewString()
	if err = s.Pair(context.Background(), ticket, uuid.NewString(), terminal, store.Secret(), "committed"); err != nil {
		t.Fatal(err)
	}
	tx, err := s.DB.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec("UPDATE terminal SET display_name='uncommitted' WHERE id=?", terminal); err != nil {
		t.Fatal(err)
	}
	os.Exit(17)
}
func TestCrashRecoversCommittedWALAndRollsBackOpenTransaction(t *testing.T) {
	dir := t.TempDir()
	cmd := exec.Command(os.Args[0], "-test.run=^TestCrashWorker$")
	cmd.Env = append(os.Environ(), "VYNIC_TEST_CRASH_DIR="+dir)
	if out, err := cmd.CombinedOutput(); err == nil || !strings.Contains(err.Error(), "17") {
		t.Fatalf("worker did not crash as expected: %s %v", out, err)
	}
	info, err := os.Stat(filepath.Join(dir, "edge.db-wal"))
	if err != nil || info.Size() <= 32 {
		t.Fatalf("WAL absent: %v", err)
	}
	s, err := store.Open(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if _, err = s.Identity(); err != nil {
		t.Fatal(err)
	}
	var name string
	if err = s.DB.QueryRow("SELECT display_name FROM terminal").Scan(&name); err != nil || name != "committed" {
		t.Fatalf("crash recovery: %s %v", name, err)
	}
	var used int
	if err = s.DB.QueryRow("SELECT count(*) FROM pairing_ticket WHERE request_id IS NOT NULL").Scan(&used); err != nil || used != 1 {
		t.Fatalf("pairing commit lost %d %v", used, err)
	}
}
