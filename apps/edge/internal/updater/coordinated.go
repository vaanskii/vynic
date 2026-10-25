package updater

import (
	"errors"
	"time"
)

// RegisterCoordinatedUpgrade is used only by Setup while POS and Edge are
// stopped and their locks are owned. Setup retains a separate binary recovery
// copy until authenticated POS startup health has passed. No data is copied.
func (s *Service) RegisterCoordinatedUpgrade(raw []byte) error {
	st := s.Snapshot()
	if st.Swap != "" || st.Status == "DOWNLOADING" || st.Status == "CHECKING" || st.Status == "READY_TO_INSTALL" || st.Status == "BLOCKED" || st.Status == "INSTALLING" || st.Status == "RESTARTING" {
		return errors.New("finish or cancel the existing POS update before upgrading the application")
	}
	m, e := Verify(raw, s.cfg.Keys, s.cfg.Channel, st.Current, st.High, time.Now())
	if e != nil {
		return e
	}
	if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != m.Version {
		return errors.New("coordinated candidate identity mismatch")
	}
	if e = s.ValidateDataSeparation(); e != nil {
		return e
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Current = m.Version
	s.state.High = max(s.state.High, m.Release)
	s.state.Previous = st.Current
	s.state.Version = ""
	s.state.Envelope = nil
	s.state.Attempt = ""
	s.state.Status = "UP_TO_DATE"
	s.state.Reason = ""
	s.state.StartupVerified = false
	s.state.Nonce = ""
	s.state.PID = 0
	s.state.Swap = "repair_ready"
	s.state.RepairPending = true
	s.state.DiscardStaging = false
	return s.saveLocked()
}

// RestoreCoordinatedVersion changes only the binary decision after Setup has
// restored its verified previous release. Release high-water, identity, Hive,
// consent history and the data path are never restored from a snapshot.
func (s *Service) RestoreCoordinatedVersion(previous, candidate string) error {
	st := s.Snapshot()
	if !versionRE.MatchString(previous) || !versionRE.MatchString(candidate) || (st.Current != previous && st.Current != candidate) {
		return errors.New("coordinated recovery identity mismatch")
	}
	if v, e := ReleaseVersion(CurrentDir(s.cfg.Root)); e != nil || v != previous {
		return errors.New("previous binary not restored")
	}
	if e := s.ValidateDataSeparation(); e != nil {
		return e
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Current = previous
	s.state.Previous = ""
	s.state.Version = ""
	s.state.Envelope = nil
	s.state.Attempt = ""
	s.state.Status = "ROLLED_BACK"
	s.state.LastOutcome = "ROLLED_BACK"
	s.state.Reason = "coordinated application upgrade restored previous binaries"
	s.state.StartupVerified = false
	s.state.Nonce = ""
	s.state.PID = 0
	s.state.Swap = ""
	s.state.RepairPending = false
	s.state.CleanupPending = false
	s.state.DiscardStaging = false
	return s.saveLocked()
}
