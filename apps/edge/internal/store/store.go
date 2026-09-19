// Package store owns the local file. No POS opens SQLite directly.
package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"embed"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofrs/flock"
	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrations embed.FS

const SchemaVersion = 1
const applicationID = 1448693321

type Store struct {
	DB   *sql.DB
	lock *flock.Flock
}

// Open never initializes missing state unless explicitly requested by init.
func Open(dir string, create bool) (*Store, error) {
	if create {
		if err := os.MkdirAll(dir, 0700); err != nil {
			return nil, err
		}
	}
	path := filepath.Join(dir, "edge.db")
	if !create {
		if _, err := os.Stat(path); err != nil {
			return nil, err
		}
	}
	lock := flock.New(filepath.Join(dir, "edge.lock"))
	ok, err := lock.TryLock()
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("Edge state is already in use; stop the service before administration")
	}
	fail := func(e error) (*Store, error) { _ = lock.Unlock(); return nil, e }
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0600)
	if err != nil {
		return fail(err)
	}
	if err = f.Close(); err != nil {
		return fail(err)
	}
	// One connection guarantees per-connection PRAGMAs apply to every statement.
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return fail(err)
	}
	db.SetMaxOpenConns(1)
	s := &Store{DB: db, lock: lock}
	if err = s.prepare(create); err != nil {
		_ = s.Close()
		return nil, fmt.Errorf("local store refused (preserve files; do not reset): %w", err)
	}
	return s, nil
}

func (s *Store) prepare(create bool) error {
	var check string
	if err := s.DB.QueryRow("PRAGMA integrity_check").Scan(&check); err != nil {
		return err
	}
	if check != "ok" {
		return errors.New("SQLite integrity check failed")
	}
	var app, version, tables int
	if err := s.DB.QueryRow("PRAGMA application_id").Scan(&app); err != nil {
		return err
	}
	if err := s.DB.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	if err := s.DB.QueryRow("SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").Scan(&tables); err != nil {
		return err
	}
	fresh := tables == 0 && app == 0 && version == 0
	if fresh && !create {
		return errors.New("uninitialized store")
	}
	if !fresh && (app != applicationID || version < 1 || version > SchemaVersion) {
		return errors.New("incompatible application/schema version")
	}
	for _, q := range []string{"PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL", "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000"} {
		if _, err := s.DB.Exec(q); err != nil {
			return err
		}
	}
	var journal string
	if err := s.DB.QueryRow("PRAGMA journal_mode").Scan(&journal); err != nil || journal != "wal" {
		return errors.New("WAL unavailable")
	}
	tx, err := s.DB.BeginTx(context.Background(), nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if fresh {
		if _, err = tx.Exec(migrationTable); err != nil {
			return err
		}
	}
	var count int
	if err = tx.QueryRow("SELECT count(*) FROM schema_migration").Scan(&count); err != nil {
		return err
	}
	if count != version {
		return errors.New("inconsistent migration ledger")
	}
	files, err := migrations.ReadDir("migrations")
	if err != nil {
		return err
	}
	for i, file := range files {
		n := i + 1
		if !strings.HasPrefix(file.Name(), fmt.Sprintf("%03d_", n)) {
			return errors.New("noncontiguous embedded migrations")
		}
		b, err := migrations.ReadFile("migrations/" + file.Name())
		if err != nil {
			return err
		}
		sum := sha256.Sum256(b)
		checksum := hex.EncodeToString(sum[:])
		if n <= version {
			var stored string
			if err = tx.QueryRow("SELECT checksum FROM schema_migration WHERE version=?", n).Scan(&stored); err != nil {
				return err
			}
			if stored != checksum {
				return errors.New("migration checksum mismatch")
			}
			continue
		}
		if _, err = tx.Exec(string(b)); err != nil {
			return err
		}
		if _, err = tx.Exec("INSERT INTO schema_migration VALUES (?,?)", n, checksum); err != nil {
			return err
		}
	}
	if len(files) != SchemaVersion {
		return errors.New("embedded schema version mismatch")
	}
	if err = verifySchema(tx); err != nil {
		return err
	}
	if _, err = tx.Exec("PRAGMA application_id=" + strconv.Itoa(applicationID)); err != nil {
		return err
	}
	if _, err = tx.Exec("PRAGMA user_version=" + strconv.Itoa(SchemaVersion)); err != nil {
		return err
	}
	// Detect missing/modified tables and columns even when user_version survived.
	for _, q := range []string{
		"SELECT singleton,id,public_key,private_key,venue_id,certificate,tls_key,binding_grant,created_at FROM installation LIMIT 0",
		"SELECT verifier,expires_at,request_id,terminal_id,request_digest FROM pairing_ticket LIMIT 0",
		"SELECT id,display_name,verifier,created_at,revoked_at FROM terminal LIMIT 0",
		"SELECT id,terminal_id,client_version,created_at,last_seen_at,last_boot_id FROM session LIMIT 0",
	} {
		rows, e := tx.Query(q)
		if e != nil {
			return e
		}
		if e = rows.Close(); e != nil {
			return e
		}
	}
	rows, err := tx.Query("PRAGMA foreign_key_check")
	if err != nil {
		return err
	}
	defer rows.Close()
	if rows.Next() {
		return errors.New("foreign key violation")
	}
	if err = rows.Err(); err != nil {
		return err
	}
	if err = rows.Close(); err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Store) Close() error { return errors.Join(s.DB.Close(), s.lock.Unlock()) }
