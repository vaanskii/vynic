package updater

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/gofrs/flock"
	"github.com/google/uuid"
	_ "modernc.org/sqlite"
)

type Config struct {
	Root           string                `json:"root"`
	Feed           string                `json:"feed"`
	Channel        string                `json:"channel"`
	InitialVersion string                `json:"initialVersion"`
	InitialRelease uint64                `json:"initialRelease"`
	Token          string                `json:"token"`
	Listen         string                `json:"listen"`
	Keys           map[string]TrustedKey `json:"keys"`
}
type State struct {
	RepairPending   bool   `json:"repairPending,omitempty"`
	Layout          int    `json:"layout,omitempty"`
	Swap            string `json:"swap,omitempty"`
	CleanupPending  bool   `json:"cleanupPending,omitempty"`
	DiscardStaging  bool   `json:"discardStaging,omitempty"`
	DataPath        string `json:"dataPath,omitempty"`
	Status          string `json:"status"`
	LastOutcome     string `json:"lastOutcome,omitempty"`
	StartupVerified bool   `json:"startupVerified"`
	Version         string `json:"version"`
	Current         string `json:"current"`
	High            uint64 `json:"high"`
	Downloaded      int64  `json:"downloaded"`
	Total           int64  `json:"total"`
	Reason          string `json:"reason,omitempty"`
	Envelope        []byte `json:"envelope,omitempty"`
	Attempt         string `json:"attempt,omitempty"`
	Previous        string `json:"previous,omitempty"`
	Nonce           string `json:"nonce,omitempty"`
	PID             int    `json:"pid,omitempty"`
}

// Process operates on an exact managed POS path, never an image name or Edge.
type Process interface {
	Running(path string) (bool, error)
	Validate(pid int, path string) error
	Stop(path string) error
	Start(path string, env []string) (int, error)
}
type Service struct {
	lock             *flock.Flock
	mu               sync.Mutex
	state            State
	db               *sql.DB
	cfg              Config
	process          Process
	client           *http.Client
	busy             bool
	healthy          chan time.Time
	healthTimeout    time.Duration
	stabilization    time.Duration
	heartbeatTimeout time.Duration
}

func Open(c Config, p Process) (*Service, error) {
	host, _, err := net.SplitHostPort(c.Listen)
	if err != nil || host != "127.0.0.1" || len(c.Token) < 64 || !filepath.IsAbs(c.Root) || !versionRE.MatchString(c.InitialVersion) || !strings.HasPrefix(c.Feed, "https://") || len(c.Keys) == 0 {
		return nil, errors.New("invalid updater configuration")
	}
	if err = os.MkdirAll(c.Root, 0700); err != nil {
		return nil, err
	}
	lock := flock.New(filepath.Join(c.Root, "updater.lock"))
	locked, err := lock.TryLock()
	if err != nil {
		return nil, err
	}
	if !locked {
		return nil, errors.New("updater root is already owned")
	}
	opened := false
	defer func() {
		if !opened {
			_ = lock.Unlock()
		}
	}()
	db, err := sql.Open("sqlite", filepath.Join(c.Root, "updater.sqlite"))
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err = db.Exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS updater_state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL CHECK(version=1), value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS install_requests (id TEXT PRIMARY KEY, version TEXT NOT NULL, pid INTEGER NOT NULL, data_path TEXT NOT NULL);`); err != nil {
		db.Close()
		return nil, err
	}
	var integrity string
	if err = db.QueryRow(`PRAGMA integrity_check`).Scan(&integrity); err != nil || integrity != "ok" {
		db.Close()
		return nil, errors.New("updater SQLite integrity failure")
	}
	s := &Service{lock: lock, db: db, cfg: c, process: p, healthTimeout: 90 * time.Second, stabilization: 30 * time.Second, heartbeatTimeout: 10 * time.Second, client: &http.Client{Timeout: 30 * time.Minute, CheckRedirect: func(r *http.Request, via []*http.Request) error {
		if len(via) > 5 || r.URL.Scheme != "https" {
			return errors.New("unsafe redirect")
		}
		return nil
	}}}
	var raw []byte
	var schema int
	err = db.QueryRow(`SELECT version, value FROM updater_state WHERE id=1`).Scan(&schema, &raw)
	if err == sql.ErrNoRows {
		s.state = State{Layout: binaryLayout, Status: "UP_TO_DATE", Current: c.InitialVersion, High: c.InitialRelease}
		if exists(filepath.Join(c.Root, "releases")) {
			s.state.Layout = 0
		}
		err = s.saveLocked()
	} else if err == nil {
		if schema != 1 {
			err = errors.New("incompatible updater schema")
		} else {
			err = decodeStrict(raw, &s.state)
		}
		if err == nil && (!versionRE.MatchString(s.state.Current) || s.state.Previous != "" && !versionRE.MatchString(s.state.Previous) || s.state.Version != "" && !versionRE.MatchString(s.state.Version)) {
			err = errors.New("corrupt updater release state")
		}
	}
	if err == nil {
		allowed := map[string]bool{"UP_TO_DATE": true, "CHECKING": true, "DOWNLOADING": true, "READY_TO_INSTALL": true, "BLOCKED": true, "INSTALLING": true, "RESTARTING": true, "SUCCESS": true, "FAILED": true, "ROLLED_BACK": true}
		swaps := map[string]bool{"": true, "prepared": true, "activating": true, "starting": true, "restoring": true, "cleanup": true, "repair_ready": true, "repair_starting": true}
		if (s.state.Layout != 0 && s.state.Layout != binaryLayout) || !swaps[s.state.Swap] || !allowed[s.state.Status] || ((s.state.Status == "INSTALLING" || s.state.Status == "RESTARTING") && (s.state.Previous == "" || (s.state.Swap != "restoring" && (s.state.Version == "" || s.state.Attempt == "")))) {
			err = errors.New("inconsistent updater state")
		}
	}
	if err == nil {
		err = validateBinaryJournal(s.state)
	}
	if err != nil {
		db.Close()
		return nil, err
	}
	if s.state.Status == "CHECKING" || s.state.Status == "DOWNLOADING" {
		s.state.Status = "FAILED"
		s.state.Reason = "interrupted download; retry check"
		err = s.saveLocked()
	}
	if err != nil {
		db.Close()
		return nil, err
	}
	opened = true
	return s, nil
}
func (s *Service) Close() error {
	for {
		s.mu.Lock()
		busy := s.busy
		s.mu.Unlock()
		if !busy {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	return errors.Join(s.db.Close(), s.lock.Unlock())
}
func (s *Service) saveLocked() error {
	b, e := json.Marshal(s.state)
	if e != nil {
		return e
	}
	_, e = s.db.Exec(`INSERT INTO updater_state VALUES(1,1,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value`, string(b))
	if e != nil {
		s.state.StartupVerified = false
		s.state.Status = "FAILED"
		s.state.Reason = "updater persistence failed"
	}
	return e
}
func (s *Service) Snapshot() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	v := s.state
	v.Envelope = nil
	v.Nonce = ""
	v.PID = 0
	return v
}
func (s *Service) set(status, reason string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Status = status
	if status == "SUCCESS" || status == "ROLLED_BACK" {
		s.state.StartupVerified = true
		s.state.LastOutcome = status
	}
	s.state.Reason = reason
	return s.saveLocked()
}
func (s *Service) path(version string) string {
	if s.state.Layout == 0 {
		return filepath.Join(s.cfg.Root, "releases", version, Executable)
	}
	return CurrentExecutable(s.cfg.Root)
}
func (s *Service) artifact() string {
	old := filepath.Join(s.cfg.Root, "staged.zip")
	if s.state.Layout == 0 && exists(old) {
		return old
	}
	return filepath.Join(StagingDir(s.cfg.Root), "candidate.zip")
}
func (s *Service) acquire() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.busy {
		return false
	}
	s.busy = true
	return true
}
func (s *Service) release() { s.mu.Lock(); s.busy = false; s.mu.Unlock() }
func (s *Service) fetch(ctx context.Context, url string, limit int64) ([]byte, error) {
	r, e := http.NewRequestWithContext(ctx, "GET", url, nil)
	if e != nil {
		return nil, e
	}
	resp, e := s.client.Do(r)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("release HTTP %d", resp.StatusCode)
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if int64(len(b)) > limit {
		return nil, errors.New("manifest too large")
	}
	return b, e
}
func (s *Service) Check(ctx context.Context) error {
	if !s.acquire() {
		return errors.New("updater busy")
	}
	defer s.release()
	st := s.Snapshot()
	if st.CleanupPending || st.Swap != "" {
		return nil
	}
	if st.Status == "READY_TO_INSTALL" || st.Status == "BLOCKED" || st.Status == "INSTALLING" || st.Status == "RESTARTING" {
		return nil
	}
	if e := s.set("CHECKING", ""); e != nil {
		return e
	}
	err := s.download(ctx)
	if err != nil {
		return errors.Join(err, s.set("FAILED", err.Error()))
	}
	return nil
}
func (s *Service) download(ctx context.Context) error {
	raw, e := s.fetch(ctx, s.cfg.Feed, 64<<10)
	if e != nil {
		return e
	}
	st := s.Snapshot()
	m, e := Verify(raw, s.cfg.Keys, s.cfg.Channel, st.Current, st.High, time.Now())
	if e != nil {
		// An authenticated current release is allowed to mean up-to-date. Never
		// reinterpret a bad signature/compatibility check as a successful check.
		same, se := Verify(raw, s.cfg.Keys, s.cfg.Channel, "0.0.0", 0, time.Now())
		if se == nil && same.Version == st.Current && same.Release == st.High {
			return s.set("UP_TO_DATE", "")
		}
		return e
	}
	s.mu.Lock()
	s.state.Status = "DOWNLOADING"
	s.state.Version = m.Version
	s.state.Total = m.Size
	s.state.Downloaded = 0
	s.state.Envelope = nil
	e = s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	req, e := http.NewRequestWithContext(ctx, "GET", m.URL, nil)
	if e != nil {
		return e
	}
	r, e := s.client.Do(req)
	if e != nil {
		return e
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return fmt.Errorf("artifact HTTP %d", r.StatusCode)
	}
	if e = safeDataPath(s.cfg.Root, st.DataPath); e != nil {
		return e
	}
	if e = safeTree(StagingDir(s.cfg.Root)); e != nil {
		return e
	}
	if e = os.MkdirAll(StagingDir(s.cfg.Root), 0700); e != nil {
		return e
	}
	part := s.artifact() + ".part"
	f, e := os.OpenFile(part, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer os.Remove(part)
	_, copyErr := io.Copy(f, io.TeeReader(io.LimitReader(r.Body, m.Size+1), progressWriter{s}))
	e = errors.Join(copyErr, f.Sync(), f.Close())
	if e != nil {
		return e
	}
	if e = verifyFile(part, m); e != nil {
		return e
	}
	// Remove only updater-owned stale artifact; never a restaurant data path.
	if e = os.Remove(s.artifact()); e != nil && !os.IsNotExist(e) {
		return e
	}
	if e = os.Rename(part, s.artifact()); e != nil {
		return e
	}
	if e = s.stageCandidate(m); e != nil {
		return e
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Envelope = raw
	s.state.Status = "READY_TO_INSTALL"
	s.state.Attempt = ""
	s.state.Reason = ""
	return s.saveLocked()
}

type progressWriter struct{ s *Service }

func (w progressWriter) Write(p []byte) (int, error) {
	w.s.mu.Lock()
	w.s.state.Downloaded += int64(len(p))
	w.s.mu.Unlock()
	return len(p), nil
}

// Install is reachable only from explicit local POS action after its exclusive
// readiness barrier. The request ID and decision persist before touching POS.
func (s *Service) Install(id, version, dataPath string, pid int, ready bool) error {
	parsed, pe := uuid.Parse(id)
	if pe != nil || parsed == uuid.Nil || parsed.String() != id || pid < 1 || !filepath.IsAbs(dataPath) {
		return errors.New("invalid install identity")
	}
	if e := safeDataPath(s.cfg.Root, dataPath); e != nil {
		return e
	}
	s.mu.Lock()
	var priorVersion, priorDataPath string
	var priorPID int
	err := s.db.QueryRow(`SELECT version,pid,data_path FROM install_requests WHERE id=?`, id).Scan(&priorVersion, &priorPID, &priorDataPath)
	if err == nil {
		s.mu.Unlock()
		if priorVersion != version || priorPID != pid || priorDataPath != dataPath {
			return errors.New("install request reused with changed inputs")
		}
		return nil
	}
	if err != sql.ErrNoRows {
		s.mu.Unlock()
		return err
	}
	if s.state.DataPath != "" && !strings.EqualFold(filepath.Clean(s.state.DataPath), filepath.Clean(dataPath)) {
		s.mu.Unlock()
		return errors.New("POS data directory changed")
	}
	if version != s.state.Version {
		s.mu.Unlock()
		return errors.New("staged release changed")
	}
	if s.busy || s.state.CleanupPending || s.state.Swap != "" || s.state.Status != "READY_TO_INSTALL" && s.state.Status != "BLOCKED" {
		s.mu.Unlock()
		return errors.New("update not staged or install busy")
	}
	if !ready {
		s.state.Status = "BLOCKED"
		s.state.Reason = "POS operation/recovery in progress"
		e := s.saveLocked()
		s.mu.Unlock()
		return e
	}
	if e := s.process.Validate(pid, s.path(s.state.Current)); e != nil {
		s.mu.Unlock()
		return e
	}
	m, e := Verify(s.state.Envelope, s.cfg.Keys, s.cfg.Channel, s.state.Current, s.state.High, time.Now())
	if e == nil {
		e = verifyFile(s.artifact(), m)
	}
	if e != nil {
		s.state.Status = "FAILED"
		s.state.Reason = e.Error()
		pe := s.saveLocked()
		s.mu.Unlock()
		return errors.Join(e, pe)
	}
	s.state.DataPath = dataPath
	s.state.StartupVerified = false
	s.state.Attempt = id
	s.state.Previous = s.state.Current
	s.state.Status = "INSTALLING"
	s.state.Swap = "prepared"
	s.state.RepairPending = false
	s.state.PID = pid
	s.state.Reason = ""
	s.busy = true
	// Consent and the idempotency record share a transaction.
	tx, te := s.db.Begin()
	e = te
	if e == nil {
		var b []byte
		b, e = json.Marshal(s.state)
		if e == nil {
			_, e = tx.Exec(`UPDATE updater_state SET value=? WHERE id=1`, string(b))
		}
		if e == nil {
			_, e = tx.Exec(`INSERT INTO install_requests VALUES(?,?,?,?)`, id, version, pid, dataPath)
		}
		if e == nil {
			e = tx.Commit()
		} else {
			_ = tx.Rollback()
		}
	}
	if e != nil {
		s.state.Status = "FAILED"
		s.state.Reason = "install consent persistence failed"
		s.busy = false
		s.mu.Unlock()
		return e
	}
	s.mu.Unlock()
	go func() {
		defer s.release()
		if err := s.install(m); err != nil {
			_ = s.set("FAILED", err.Error())
		}
	}()
	return nil
}
func (s *Service) stageCandidate(m Manifest) error {
	if e := s.removeBinary(CandidateDir(s.cfg.Root)); e != nil {
		return e
	}
	if e := extract(s.artifact(), CandidateDir(s.cfg.Root)); e != nil {
		return e
	}
	return MarkRelease(CandidateDir(s.cfg.Root), m.Version)
}
func (s *Service) install(m Manifest) (result error) {
	stopped := false
	defer func() {
		if result != nil && stopped && !s.Snapshot().CleanupPending {
			result = s.rollback(result)
		}
	}()
	// Rebuild from the freshly reverified signed ZIP; never trust a staged tree.
	if e := s.stageCandidate(m); e != nil {
		return e
	}
	st := s.Snapshot()
	if e := s.process.Stop(s.path(st.Previous)); e != nil {
		return e
	}
	stopped = true
	if e := s.MigrateClosedLayout(); e != nil {
		return e
	}
	if exists(RollbackDir(s.cfg.Root)) {
		return errors.New("unresolved rollback release")
	}
	if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != st.Previous {
		return errors.New("active release identity mismatch")
	}
	s.mu.Lock()
	s.state.Swap = "activating"
	e := s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	if e = moveBinary(CurrentDir(s.cfg.Root), RollbackDir(s.cfg.Root)); e != nil {
		return e
	}
	if e = moveBinary(CandidateDir(s.cfg.Root), CurrentDir(s.cfg.Root)); e != nil {
		return e
	}
	s.mu.Lock()
	s.state.Current = m.Version
	s.state.High = m.Release
	s.state.Status = "RESTARTING"
	s.state.Swap = "starting"
	e = s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	if e = s.startHealthy(m.Version); e != nil {
		return e
	}
	return s.finishStable("SUCCESS", "", true)
}
func (s *Service) startHealthy(version string) error {
	return s.startWithHealth(version, true)
}

// A verified current release needs fresh authenticated data readiness, but
// only newly installed/repaired/rolled-back binaries need a stability window.
func (s *Service) startWithHealth(version string, stabilize bool) error {
	if e := safeTree(CurrentDir(s.cfg.Root)); e != nil {
		return e
	}
	if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != version {
		return errors.New("startup release identity mismatch")
	}

	nonceBytes := make([]byte, 32)
	if _, e := rand.Read(nonceBytes); e != nil {
		return e
	}
	s.mu.Lock()
	s.state.StartupVerified = false
	s.state.Nonce = hex.EncodeToString(nonceBytes)
	s.healthy = make(chan time.Time, 1)
	nonce := s.state.Nonce
	e := s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	pid, e := s.process.Start(s.path(version), []string{"VYNIC_POS_UPDATE_NONCE=" + nonce, "VYNIC_POS_UPDATE_VERSION=" + version})
	if e != nil {
		return e
	}
	s.mu.Lock()
	s.state.PID = pid
	e = s.saveLocked()
	ch := s.healthy
	s.mu.Unlock()
	if e != nil {
		return e
	}
	var lastHealth time.Time
	select {
	case lastHealth = <-ch:
	case <-time.After(s.healthTimeout):
		return errors.New("POS startup health timeout")
	}
	if !stabilize {
		return s.process.Validate(pid, s.path(version))
	}
	// Require continued authenticated Hive-ready heartbeats AND the same live
	// process. POS remains in startup probation until this whole interval passes.
	stable := time.NewTimer(s.stabilization)
	defer stable.Stop()
	heartbeat := time.NewTimer(s.heartbeatTimeout)
	defer heartbeat.Stop()
	tick := time.NewTicker(min(time.Second, s.stabilization/4))
	defer tick.Stop()
	for {
		select {
		case <-stable.C:
			if time.Since(lastHealth) >= s.heartbeatTimeout {
				return errors.New("POS stabilization heartbeat timeout")
			}
			return s.process.Validate(pid, s.path(version))
		case <-heartbeat.C:
			return errors.New("POS stabilization heartbeat timeout")
		case <-tick.C:
			if e := s.process.Validate(pid, s.path(version)); e != nil {
				return e
			}
		case at := <-ch:
			if at.Sub(lastHealth) >= s.heartbeatTimeout || time.Since(at) >= s.heartbeatTimeout {
				return errors.New("POS stabilization heartbeat timeout")
			}
			lastHealth = at
			if !heartbeat.Stop() {
				select {
				case <-heartbeat.C:
				default:
				}
			}
			heartbeat.Reset(time.Until(lastHealth.Add(s.heartbeatTimeout)))
		}
	}
}
func (s *Service) rollback(cause error) error {
	st := s.Snapshot()
	if e := s.process.Stop(s.path(st.Current)); e != nil {
		return errors.Join(cause, e)
	}
	// Legacy interrupted activations still have immutable version directories.
	if st.Layout == 0 {
		if e := s.process.Stop(s.path(st.Previous)); e != nil {
			return e
		}
		s.mu.Lock()
		s.state.Current = st.Previous
		e := s.saveLocked()
		s.mu.Unlock()
		if e != nil {
			return e
		}
		if e = s.MigrateClosedLayout(); e != nil {
			return e
		}
	}
	s.mu.Lock()
	s.state.StartupVerified = false
	s.state.Swap = "restoring"
	e := s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	if e = s.restoreFiles(); e != nil {
		return e
	}
	s.mu.Lock()
	s.state.Current = st.Previous
	s.state.Status = "RESTARTING"
	e = s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	if e = s.startHealthy(st.Previous); e != nil {
		return errors.Join(cause, fmt.Errorf("rollback startup failed: %w", e))
	}
	status := "ROLLED_BACK"
	if st.RepairPending && len(st.Envelope) > 0 && st.Version != st.Previous && exists(s.artifact()) {
		status = "READY_TO_INSTALL"
		s.mu.Lock()
		s.state.LastOutcome = "ROLLED_BACK"
		s.mu.Unlock()
	}
	return s.finishStable(status, cause.Error(), !st.RepairPending)
}

// Interrupted consented activation restores the previous binary. Once stable
// success is durable, recovery ONLY retries deletion, never rolls data/binaries back.
func (s *Service) Recover() error {
	if !s.acquire() {
		return errors.New("busy")
	}
	defer s.release()
	st := s.Snapshot()
	if st.CleanupPending {
		s.retryCleanup()
		return nil
	}
	if st.Swap == "repair_ready" {
		return nil
	}
	if st.Swap == "repair_starting" && st.Previous == "" {
		if e := s.process.Stop(s.path(st.Current)); e != nil {
			return e
		}
		s.mu.Lock()
		s.state.Swap = "repair_ready"
		e := s.saveLocked()
		s.mu.Unlock()
		return e
	}
	if st.Swap != "" || st.Status == "INSTALLING" || st.Status == "RESTARTING" {
		return s.rollback(errors.New("interrupted installation"))
	}
	return s.migrateIfIdle()
}
func (s *Service) launch() error {
	st := s.Snapshot()
	if st.CleanupPending {
		s.retryCleanup()
		st = s.Snapshot()
	}
	if st.Swap != "" && st.Swap != "repair_ready" && st.Swap != "cleanup" {
		return errors.New("unresolved install requires recovery")
	}
	if st.Layout == 0 {
		if e := s.migrateIfIdle(); e != nil {
			return e
		}
		if s.Snapshot().Layout == 0 {
			return errors.New("legacy POS still running")
		}
	}
	if st.Swap == "repair_ready" {
		s.mu.Lock()
		s.state.Swap = "repair_starting"
		e := s.saveLocked()
		s.mu.Unlock()
		if e != nil {
			return e
		}
	}
	if e := s.startWithHealth(st.Current, !st.StartupVerified || st.DataPath == "" || st.Swap != "" || st.Previous != ""); e != nil {
		if st.Previous != "" && st.Swap == "repair_ready" {
			return s.rollback(e)
		}
		if st.Swap == "repair_ready" {
			s.mu.Lock()
			s.state.Swap = "repair_ready"
			pe := s.saveLocked()
			s.mu.Unlock()
			return errors.Join(e, pe)
		}
		return e
	}
	return s.finishStable(st.Status, st.Reason, st.DiscardStaging)
}

func (s *Service) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte("Bearer "+s.cfg.Token)) != 1 {
			http.Error(w, "unauthorized", 401)
			return
		}
		var err error
		switch {
		case r.Method == "GET" && r.URL.Path == "/v1/status":
		case r.Method == "POST" && r.URL.Path == "/v1/check":
			go func() { _ = s.Check(context.Background()) }()
		case r.Method == "POST" && r.URL.Path == "/v1/launch":
			if !s.acquire() {
				err = errors.New("updater busy")
			} else {
				go func() {
					defer s.release()
					if e := s.launch(); e != nil {
						_ = s.set("FAILED", e.Error())
					}
				}()
			}
		case r.Method == "POST" && r.URL.Path == "/v1/install":
			var q struct {
				RequestID string `json:"requestId"`
				PID       int    `json:"pid"`
				Ready     bool   `json:"ready"`
				Version   string `json:"version"`
				DataPath  string `json:"dataPath"`
			}
			b, e := io.ReadAll(io.LimitReader(r.Body, 4097))
			if e != nil || len(b) > 4096 {
				err = errors.New("bad request")
			} else if err = decodeStrict(b, &q); err == nil {
				err = s.Install(q.RequestID, q.Version, q.DataPath, q.PID, q.Ready)
			}
		case r.Method == "POST" && r.URL.Path == "/v1/health":
			var q struct {
				DataPath   string `json:"dataPath"`
				HiveSchema int    `json:"hiveSchema"`
				Nonce      string `json:"nonce"`
				Version    string `json:"version"`
				PID        int    `json:"pid"`
			}
			b, _ := io.ReadAll(io.LimitReader(r.Body, 4096))
			err = decodeStrict(b, &q)
			if err == nil {
				s.mu.Lock()
				if safeDataPath(s.cfg.Root, q.DataPath) != nil || q.HiveSchema != 9 || !filepath.IsAbs(q.DataPath) || s.state.DataPath != "" && !strings.EqualFold(filepath.Clean(q.DataPath), filepath.Clean(s.state.DataPath)) || s.healthy == nil || q.Nonce != s.state.Nonce || q.Version != s.state.Current || q.PID != s.state.PID {
					err = errors.New("stale startup health")
				} else if err = s.process.Validate(q.PID, s.path(q.Version)); err == nil {
					s.state.DataPath = q.DataPath
					err = s.saveLocked()
					if err != nil {
						s.mu.Unlock()
						http.Error(w, err.Error(), 500)
						return
					}
					select {
					case s.healthy <- time.Now():
					default:
					}
				}
				s.mu.Unlock()
			}
		default:
			http.NotFound(w, r)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 409)
			return
		}
		_ = json.NewEncoder(w).Encode(s.Snapshot())
	})
}
func (s *Service) Run(ctx context.Context) error {
	l, e := net.Listen("tcp", s.cfg.Listen)
	if e != nil {
		return e
	}
	server := &http.Server{Handler: s.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		c, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = server.Shutdown(c)
	}()
	go func() {
		if e := s.Recover(); e != nil {
			_ = s.set("FAILED", e.Error())
			return
		}
		if s.Snapshot().Status != "ROLLED_BACK" && s.Snapshot().Status != "FAILED" {
			_ = s.Check(ctx)
		}
		cleanup := time.NewTicker(30 * time.Second)
		defer cleanup.Stop()
		t := time.NewTicker(30 * time.Minute)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-cleanup.C:
				if s.acquire() {
					s.retryCleanup()
					s.release()
				}
			case <-t.C:
				_ = s.Check(ctx)
			}
		}
	}()
	e = server.Serve(l)
	if errors.Is(e, http.ErrServerClosed) {
		return nil
	}
	return e
}
