package updater

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const binaryLayout = 2
const releaseMarker = ".vynic-release.json"

func CurrentDir(root string) string        { return filepath.Join(root, "current") }
func StagingDir(root string) string        { return filepath.Join(root, "staging") }
func RollbackDir(root string) string       { return filepath.Join(root, "rollback") }
func CurrentExecutable(root string) string { return filepath.Join(CurrentDir(root), Executable) }
func CandidateDir(root string) string      { return filepath.Join(StagingDir(root), "release") }

type releaseIdentity struct {
	Version string `json:"version"`
}

func MarkRelease(dir, version string) error {
	if !versionRE.MatchString(version) {
		return errors.New("invalid release identity")
	}
	if e := safeTree(dir); e != nil {
		return e
	}
	b, e := json.Marshal(releaseIdentity{version})
	if e != nil {
		return e
	}
	path := filepath.Join(dir, releaseMarker)
	f, e := os.OpenFile(path+".tmp", os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	_, e = f.Write(b)
	e = errors.Join(e, f.Sync(), f.Close())
	if e != nil {
		return e
	}
	return moveBinary(path+".tmp", path)
}
func ReleaseVersion(dir string) (string, error) {
	b, e := os.ReadFile(filepath.Join(dir, releaseMarker))
	if e != nil {
		return "", e
	}
	var v releaseIdentity
	if e = decodeStrict(b, &v); e != nil {
		return "", e
	}
	if !versionRE.MatchString(v.Version) {
		return "", errors.New("invalid binary release marker")
	}
	return v.Version, nil
}
func exists(path string) bool { _, e := os.Lstat(path); return e == nil }
func overlap(a, b string) bool {
	a = strings.ToLower(filepath.Clean(a))
	b = strings.ToLower(filepath.Clean(b))
	sep := string(os.PathSeparator)
	return a == b || strings.HasPrefix(a, b+sep) || strings.HasPrefix(b, a+sep)
}
func safeDataPath(root, data string) error {
	if data == "" {
		return nil
	}
	for _, p := range []string{CurrentDir(root), StagingDir(root), RollbackDir(root), filepath.Join(root, "releases")} {
		if overlap(p, data) {
			return errors.New("restaurant data overlaps application binaries; preserve files and correct provisioning")
		}
	}
	return nil
}

// Never traverse links/junctions while moving or removing managed binaries.
func safeTree(path string) error {
	for p := path; ; p = filepath.Dir(p) {
		info, e := os.Lstat(p)
		if e != nil && !os.IsNotExist(e) {
			return e
		}
		if e == nil {
			if info.Mode()&os.ModeSymlink != 0 {
				return errors.New("linked binary path refused")
			}
			if e = checkBinaryReparse(p); e != nil {
				return e
			}
		}
		if filepath.Dir(p) == p {
			break
		}
	}
	if !exists(path) {
		return nil
	}
	return filepath.WalkDir(path, func(p string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if d.Type()&os.ModeSymlink != 0 {
			return errors.New("linked binary tree refused")
		}
		return checkBinaryReparse(p)
	})
}
func (s *Service) removeBinary(path string) error {
	allowed := false
	for _, slot := range []string{CurrentDir(s.cfg.Root), RollbackDir(s.cfg.Root), StagingDir(s.cfg.Root), filepath.Join(s.cfg.Root, "releases")} {
		if path == slot || strings.HasPrefix(path, slot+string(os.PathSeparator)) {
			allowed = true
		}
	}
	if path == filepath.Join(s.cfg.Root, "staged.zip") || path == filepath.Join(s.cfg.Root, "staged.zip.part") {
		allowed = true
	}
	if !allowed || filepath.Clean(path) != path {
		return errors.New("refusing deletion outside binary slots")
	}

	if e := safeDataPath(s.cfg.Root, s.Snapshot().DataPath); e != nil {
		return e
	}
	if e := safeTree(path); e != nil {
		return e
	}
	return os.RemoveAll(path)
}
func (s *Service) legacyDirs() ([]string, error) {
	root := filepath.Join(s.cfg.Root, "releases")
	if e := safeTree(root); e != nil {
		return nil, e
	}
	entries, e := os.ReadDir(root)
	if os.IsNotExist(e) {
		return nil, nil
	}
	if e != nil {
		return nil, e
	}
	dirs := []string{}
	for _, d := range entries {
		if !d.IsDir() || !versionRE.MatchString(d.Name()) {
			return nil, errors.New("unrecognized legacy release contents; preserve files for inspection")
		}
		dirs = append(dirs, filepath.Join(root, d.Name()))
	}
	return dirs, nil
}

// MigrateClosedLayout is used only after setup has proved POS is closed, or
// after Edge has checked/stopped the exact managed processes. It never deletes
// legacy history until a current-path startup has passed stabilization.
func (s *Service) MigrateClosedLayout() error {
	st := s.Snapshot()
	if st.Layout == binaryLayout {
		return nil
	}
	if e := safeDataPath(s.cfg.Root, st.DataPath); e != nil {
		return e
	}
	if _, e := s.legacyDirs(); e != nil {
		return e
	}
	old := filepath.Join(s.cfg.Root, "releases", st.Current)
	current := CurrentDir(s.cfg.Root)
	if e := safeTree(current); e != nil {
		return e
	}
	if exists(old) {
		if exists(current) {
			return errors.New("ambiguous old/current binary layout")
		}
		if e := MarkRelease(old, st.Current); e != nil {
			return e
		}
		if e := moveBinary(old, current); e != nil {
			return e
		}
	} else if v, e := ReleaseVersion(current); e != nil || v != st.Current {
		return errors.New("active legacy binary missing; repair required")
	}
	oldZip := filepath.Join(s.cfg.Root, "staged.zip")
	zip := filepath.Join(StagingDir(s.cfg.Root), "candidate.zip")
	if exists(oldZip) {
		if e := os.MkdirAll(StagingDir(s.cfg.Root), 0700); e != nil {
			return e
		}
		if exists(zip) {
			return errors.New("ambiguous staged ZIP during layout migration")
		}
		if e := moveBinary(oldZip, zip); e != nil {
			return e
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Layout = binaryLayout
	s.state.StartupVerified = false
	return s.saveLocked()
}
func (s *Service) migrateIfIdle() error {
	st := s.Snapshot()
	if st.Layout == binaryLayout {
		return nil
	}
	dirs, e := s.legacyDirs()
	if e != nil {
		return e
	}
	dirs = append(dirs, CurrentDir(s.cfg.Root))
	for _, d := range dirs {
		running, e := s.process.Running(filepath.Join(d, Executable))
		if e != nil {
			return e
		}
		if running {
			return nil
		}
	}
	return s.MigrateClosedLayout()
}
func (s *Service) cleanupBinaries() error {
	st := s.Snapshot()
	if !st.CleanupPending {
		return nil
	}
	if st.Layout != binaryLayout {
		return errors.New("cleanup requires current binary layout")
	}
	if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != st.Current {
		return errors.New("cleanup refused: current release identity mismatch")
	}
	if e := s.removeBinary(RollbackDir(s.cfg.Root)); e != nil {
		return e
	}
	dirs, e := s.legacyDirs()
	if e != nil {
		return e
	}
	for _, d := range dirs {
		running, e := s.process.Running(filepath.Join(d, Executable))
		if e != nil {
			return e
		}
		if running {
			return fmt.Errorf("cleanup deferred: legacy POS still running at %s", d)
		}
		if e = s.removeBinary(d); e != nil {
			return e
		}
	}
	legacy := filepath.Join(s.cfg.Root, "releases")
	if exists(legacy) {
		if e = os.Remove(legacy); e != nil {
			return e
		}
	}
	paths := []string{filepath.Join(s.cfg.Root, "staged.zip.part"), filepath.Join(s.cfg.Root, "staged.zip"), filepath.Join(StagingDir(s.cfg.Root), "setup.zip"), filepath.Join(StagingDir(s.cfg.Root), "setup-release")}
	if st.DiscardStaging {
		paths = append(paths, StagingDir(s.cfg.Root))
	}
	for _, p := range paths {
		if e = s.removeBinary(p); e != nil {
			return e
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.CleanupPending = false
	s.state.RepairPending = false
	s.state.DiscardStaging = false
	s.state.Previous = ""
	s.state.Swap = ""
	if strings.HasPrefix(s.state.Reason, "binary cleanup pending: ") {
		s.state.Reason = ""
	}
	return s.saveLocked()
}

// Stable success is durable before deletion. A failed cleanup is retried, never
// interpreted as startup failure (rollback may already be partially removed).
func (s *Service) finishStable(status, reason string, discard bool) error {
	s.mu.Lock()
	s.state.Status = status
	s.state.StartupVerified = true
	s.state.CleanupPending = true
	s.state.DiscardStaging = discard || ((status != "READY_TO_INSTALL" && status != "BLOCKED") || len(s.state.Envelope) == 0)
	s.state.Swap = "cleanup"
	s.state.Reason = reason
	if status == "SUCCESS" || status == "ROLLED_BACK" {
		s.state.LastOutcome = status
	}
	e := s.saveLocked()
	s.mu.Unlock()
	if e != nil {
		return e
	}
	s.retryCleanup()
	return nil
}
func (s *Service) retryCleanup() {
	if e := s.cleanupBinaries(); e != nil {
		s.mu.Lock()
		s.state.Reason = "binary cleanup pending: " + e.Error()
		_ = s.saveLocked()
		s.mu.Unlock()
	}
}

// PrepareRepair shares migration/rollback recovery with setup. Caller owns the
// setup lock and has quiesced POS/Edge. No signing or data policy is relaxed.
func (s *Service) PrepareRepair(removed bool) error {
	st := s.Snapshot()
	if e := safeDataPath(s.cfg.Root, st.DataPath); e != nil {
		return e
	}
	if st.Swap != "" && st.Swap != "repair_ready" && st.Swap != "cleanup" || st.Status == "INSTALLING" || st.Status == "RESTARTING" {
		return errors.New("unresolved update; recover before repair")
	}
	if st.CleanupPending && !removed {
		if e := s.cleanupBinaries(); e != nil {
			return e
		}
	}
	if removed {
		if exists(CurrentDir(s.cfg.Root)) || exists(RollbackDir(s.cfg.Root)) || exists(filepath.Join(s.cfg.Root, "releases")) {
			return errors.New("removed installation still has binaries; finish uninstall first")
		}
		s.mu.Lock()
		s.state.Layout = binaryLayout
		// Uninstall removed application staging; retained consent/high-water rows
		// must not advertise a nonexistent deferred candidate after reinstallation.
		s.state.Status = "UP_TO_DATE"
		s.state.Version = ""
		s.state.Envelope = nil
		s.state.Downloaded = 0
		s.state.Total = 0
		s.state.Attempt = ""
		s.state.Reason = ""
		s.state.CleanupPending = false
		s.state.DiscardStaging = false
		s.mu.Unlock()
	} else if e := s.MigrateClosedLayout(); e != nil {
		return e
	}
	if st.Swap == "repair_ready" && exists(RollbackDir(s.cfg.Root)) {
		if e := s.restoreFiles(); e != nil {
			return e
		}
	}
	if !removed && exists(CurrentDir(s.cfg.Root)) {
		if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != st.Current {
			return errors.New("repair rollback identity mismatch; preserve files for inspection")
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.RepairPending = false
	s.state.Swap = ""
	s.state.Previous = ""
	return s.saveLocked()
}

// RegisterRepair records a completed setup binary swap awaiting explicit Open.
// Merely starting Edge does not launch POS or discard the temporary rollback.
func (s *Service) RegisterRepair(hasPrevious bool) error {
	st := s.Snapshot()
	if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != st.Current {
		return errors.New("repair/current version mismatch")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Swap = "repair_ready"
	s.state.RepairPending = true
	if s.state.Status != "READY_TO_INSTALL" && s.state.Status != "BLOCKED" {
		s.state.Status = "UP_TO_DATE"
		s.state.Reason = ""
	}
	s.state.StartupVerified = false
	if hasPrevious {
		s.state.Previous = s.state.Current
	} else {
		s.state.Previous = ""
	}
	return s.saveLocked()
}
func (s *Service) restoreFiles() error {
	st := s.Snapshot()
	old := RollbackDir(s.cfg.Root)
	current := CurrentDir(s.cfg.Root)
	if st.Previous == "" {
		return errors.New("no previous POS release available")
	}
	if exists(old) {
		if v, e := ReleaseVersion(old); e != nil || v != st.Previous {
			return errors.New("rollback release identity mismatch")
		}
		if e := s.removeBinary(current); e != nil {
			return e
		}
		if e := moveBinary(old, current); e != nil {
			return e
		}
	} else if v, e := ReleaseVersion(current); e != nil || v != st.Previous {
		return errors.New("rollback release missing; preserve state for repair")
	}
	return nil
}

// ValidateDataSeparation is shared by setup before any application removal.
func (s *Service) ValidateDataSeparation() error {
	return safeDataPath(s.cfg.Root, s.Snapshot().DataPath)
}

func validateBinaryJournal(st State) error {
	invalid := st.CleanupPending != (st.Swap == "cleanup")
	if st.CleanupPending && (st.Layout != binaryLayout || st.Status == "INSTALLING" || st.Status == "RESTARTING") {
		invalid = true
	}
	switch st.Swap {
	case "prepared", "activating", "starting", "restoring":
		if st.Previous == "" {
			invalid = true
		}
	case "repair_ready", "repair_starting":
		if !st.RepairPending {
			invalid = true
		}
	}
	if st.RepairPending && (st.Layout != binaryLayout || st.Swap == "") {
		invalid = true
	}
	if invalid {
		return errors.New("inconsistent binary swap/cleanup journal")
	}
	return nil
}
