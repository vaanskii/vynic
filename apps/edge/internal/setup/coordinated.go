package setup

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"time"
	"vynic.local/edge/internal/updater"
)

type upgradeJournal struct {
	Phase            string          `json:"phase"`
	Previous         Receipt         `json:"previous"`
	Candidate        Receipt         `json:"candidate"`
	PreviousPOS      string          `json:"previousPOS"`
	PreviousPOSProof json.RawMessage `json:"previousPOSProof"`
	PreviousPOSHigh  uint64          `json:"previousPOSHigh"`
	CandidatePOS     string          `json:"candidatePOS"`
}

func (l Layout) upgradeDir() string { return filepath.Join(l.Root, "application-upgrade") }
func (l Layout) upgradeJournal() string {
	return filepath.Join(l.Root, "state", "application-upgrade.json")
}
func newerVersion(a, b string) bool {
	if !version.MatchString(a) || !version.MatchString(b) {
		return false
	}
	aa, bb := strings.Split(a, "."), strings.Split(b, ".")
	for n := range aa {
		x, e := strconv.ParseUint(aa[n], 10, 64)
		if e != nil {
			return false
		}
		y, e := strconv.ParseUint(bb[n], 10, 64)
		if e != nil {
			return false
		}
		if x != y {
			return x > y
		}
	}
	return false
}
func copyRegularTree(from, to string) error {
	return filepath.WalkDir(from, func(path string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if d.Type()&os.ModeSymlink != 0 {
			return errors.New("linked binary refused")
		}
		if e = checkReparse(path); e != nil {
			return e
		}
		rel, e := filepath.Rel(from, path)
		if e != nil {
			return e
		}
		target := filepath.Join(to, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0700)
		}
		info, e := d.Info()
		if e != nil {
			return e
		}
		if !info.Mode().IsRegular() {
			return errors.New("non-regular binary refused")
		}
		in, e := os.Open(path)
		if e != nil {
			return e
		}
		defer in.Close()
		out, e := os.OpenFile(target, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if e != nil {
			return e
		}
		_, e = io.Copy(out, in)
		return errors.Join(e, out.Sync(), out.Close())
	})
}
func (i *Installer) writeUpgrade(j upgradeJournal) error {
	raw, e := json.MarshalIndent(j, "", "  ")
	if e != nil {
		return e
	}
	if len(raw) > 256<<10 {
		return errors.New("application upgrade journal exceeds recovery limit")
	}
	return writeAtomic(i.Layout.upgradeJournal(), raw)
}

func (i *Installer) readUpgrade() (upgradeJournal, error) {
	var j upgradeJournal
	e := readJSON(i.Layout.upgradeJournal(), &j)
	if e != nil {
		return j, e
	}
	l := i.Layout
	if j.Previous.Schema != 1 || j.Candidate.Schema != 1 || j.Previous.Config.Listen != "127.0.0.1:7444" || len(j.Previous.Config.Token) != 64 || (j.Candidate.BootstrapRelease <= j.Previous.BootstrapRelease || (j.Phase != "restored" && j.Candidate.BootstrapRelease <= j.Previous.BootstrapHigh)) || (j.Phase != "prepared" && j.Phase != "probation" && j.Phase != "committed" && j.Phase != "restored") || !version.MatchString(j.Previous.EdgeVersion) || !version.MatchString(j.Candidate.EdgeVersion) || !version.MatchString(j.PreviousPOS) || !newerVersion(j.CandidatePOS, j.PreviousPOS) || j.Previous.Config.Root != l.POS() || j.Candidate.Config.Root != l.POS() || j.Previous.Config.Token != j.Candidate.Config.Token || j.Previous.Config.Listen != j.Candidate.Config.Listen || j.Previous.Status != "installed" || j.Candidate.Status != "installed" {
		return j, errors.New("invalid application upgrade journal; preserve files")
	}
	return j, nil
}

// licensedRecovery verifies a publisher-signed capability for the exact baseline.
// Legacy or unproven baselines require a separately qualified migration; neither
// a version number nor a mutable local marker can authorize unrestricted fallback.
func licensedRecovery(r Receipt, current string, high uint64, proof []byte) (updater.Manifest, error) {
	b, _, e := Verify(r.Bootstrap, r.Distribution, time.Now())
	if e != nil || b.Release != r.BootstrapRelease || b.Edge.Version != r.EdgeVersion || b.Edge.SHA256 != r.EdgeHash {
		return updater.Manifest{}, errors.New("installed bootstrap trust/identity is not proven; preserve files")
	}
	p, e := updater.Verify(proof, r.Distribution.Keys, r.Distribution.Channel, "0.0.0", 0, time.Now())
	if e != nil || p.LicenseProtocol != 1 || p.Version != current || p.Release > high {
		return updater.Manifest{}, errors.New("licensing-capable current POS not proven by signed metadata; preserve installation/data and use a separately qualified migration or repair")
	}
	return p, nil
}

// Compare every regular file, not just the mutable version marker. The reference
// tree comes from a ZIP whose size/hash are bound by the signed current proof.
func sameBinaryTree(actual, verified string) error {
	fingerprints := func(root string) (map[string]string, error) {
		out := map[string]string{}
		err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.Type()&os.ModeSymlink != 0 {
				return errors.New("linked binary refused")
			}
			if err = checkReparse(path); err != nil {
				return err
			}
			if d.IsDir() {
				return nil
			}
			info, err := d.Info()
			if err != nil {
				return err
			}
			if !info.Mode().IsRegular() {
				return errors.New("non-regular binary refused")
			}
			f, err := os.Open(path)
			if err != nil {
				return err
			}
			h := sha256.New()
			_, err = io.Copy(h, f)
			err = errors.Join(err, f.Close())
			if err != nil {
				return err
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			out[rel] = fmt.Sprintf("%x", h.Sum(nil))
			return nil
		})
		return out, err
	}
	a, e := fingerprints(actual)
	if e != nil {
		return e
	}
	b, e := fingerprints(verified)
	if e != nil {
		return e
	}
	if !reflect.DeepEqual(a, b) {
		return errors.New("installed POS bytes differ from signed recovery artifact; preserve files")
	}
	return nil
}

// Upgrade is an explicit whole-application maintenance action, not an unattended
// self-updater. The invoking Setup must be outside the installation. Existing
// pinned trust verifies both components; monotonic release counters are retained.
func (i *Installer) Upgrade(ctx context.Context) (err error) {
	unlock, e := i.lock()
	if e != nil {
		return e
	}
	defer unlock()
	l := i.Layout
	r, e := Load(l)
	if e != nil {
		return e
	}
	if r.Status != "installed" {
		return errors.New("install or repair the application before upgrading")
	}
	if _, e = os.Stat(l.upgradeJournal()); !os.IsNotExist(e) {
		return errors.New("previous application upgrade needs startup verification or recovery")
	}
	source, e := os.Stat(i.SetupSource)
	if e != nil {
		return e
	}
	target, e := os.Stat(l.Setup())
	if e != nil {
		return e
	}
	if os.SameFile(source, target) {
		return errors.New("open the newly downloaded installer to upgrade POS and Edge together")
	}
	c := SecureClient(i.Client)
	raw, e := fetch(ctx, c, r.Distribution.BootstrapURL, 128<<10)
	if e != nil {
		return e
	}
	b, pos, e := Verify(raw, r.Distribution, time.Now())
	if e != nil {
		return e
	}
	if b.Release <= max(r.BootstrapRelease, r.BootstrapHigh) || b.Edge.Release != b.Release || pos.Release != b.Release || b.Edge.Version == r.EdgeVersion || !newerVersion(b.Edge.Version, r.EdgeVersion) || b.POSFeed != r.Config.Feed || b.RepairBase != r.RepairBase || b.POSReleaseBase != r.POSReleaseBase {
		return errors.New("application upgrade must advance signed Edge/bootstrap versions and retain endpoints/trust")
	}
	if pos.LicenseProtocol != 1 {
		return errors.New("candidate lacks signed licensing capability")
	}
	stage := l.upgradeDir()
	if _, e = os.Stat(stage); !os.IsNotExist(e) {
		return errors.New("existing application upgrade files require inspection")
	}
	if e = os.MkdirAll(stage, 0700); e != nil {
		return e
	}
	journalWritten := false
	defer func() {
		if !journalWritten {
			err = errors.Join(err, os.RemoveAll(stage))
		}
	}()
	if e = download(ctx, c, b.Edge, filepath.Join(stage, "edge.zip"), i.report); e != nil {
		return e
	}
	if e = download(ctx, c, pos, filepath.Join(stage, "pos.zip"), i.report); e != nil {
		return e
	}
	edgeNew, posNew := filepath.Join(stage, "edge-new"), filepath.Join(stage, "pos-new")
	if e = updater.ExtractBundle(filepath.Join(stage, "edge.zip"), edgeNew, EdgeExecutable); e != nil {
		return e
	}
	if e = updater.ExtractBundle(filepath.Join(stage, "pos.zip"), posNew, updater.Executable); e != nil {
		return e
	}
	for _, p := range []string{"flutter_windows.dll", "data/icudtl.dat", "data/flutter_assets"} {
		if _, e = os.Stat(filepath.Join(posNew, p)); e != nil {
			return fmt.Errorf("incomplete Flutter bundle: %w", e)
		}
	}
	if e = updater.MarkRelease(posNew, pos.Version); e != nil {
		return e
	}
	if e = writeAtomic(l.Maintenance(), []byte("application upgrade\n")); e != nil {
		return e
	}
	defer os.Remove(l.Maintenance())
	if e = i.Host.Quiesce(ctx, l, r, false); e != nil {
		return e
	}
	u, e := updater.OpenExisting(r.Config, updater.NativeProcess{})
	if e != nil {
		return e
	}
	defer func() { err = errors.Join(err, u.Close()) }()
	st := u.Snapshot()
	if st.Swap != "" || !st.StartupVerified || st.Status == "READY_TO_INSTALL" || st.Status == "BLOCKED" || st.Status == "DOWNLOADING" || st.Status == "CHECKING" {
		return errors.New("finish startup verification and any pending POS update before application upgrade")
	}
	if _, e = updater.Verify(b.POS, r.Distribution.Keys, r.Distribution.Channel, st.Current, st.High, time.Now()); e != nil {
		return e
	}
	if _, _, e = Verify(raw, r.Distribution, time.Now()); e != nil {
		return e
	}
	if e = u.ValidateDataSeparation(); e != nil {
		return e
	}
	if v, e := updater.ReleaseVersion(updater.CurrentDir(l.POS())); e != nil || v != st.Current {
		return errors.New("current binary identity mismatch")
	}
	baseline, _, e := Verify(r.Bootstrap, r.Distribution, time.Now())
	if e != nil {
		return e
	}
	previousProof := baseline.POS
	baselinePOS, e := updater.Verify(previousProof, r.Distribution.Keys, r.Distribution.Channel, "0.0.0", 0, time.Now())
	if e != nil {
		return e
	}
	if baselinePOS.Version != st.Current {
		previousProof, e = fetch(ctx, c, strings.TrimRight(r.POSReleaseBase, "/")+"/"+st.Current+".json", 64<<10)
		if e != nil {
			return e
		}
	}
	previousPOS, e := licensedRecovery(r, st.Current, st.High, previousProof)
	if e != nil {
		return e
	}
	previousArchive := filepath.Join(stage, "previous-pos.zip")
	if e = download(ctx, c, previousPOS, previousArchive, i.report); e != nil {
		return e
	}
	previousTree := filepath.Join(stage, "previous-pos")
	if e = updater.ExtractBundle(previousArchive, previousTree, updater.Executable); e != nil {
		return e
	}
	if e = updater.MarkRelease(previousTree, st.Current); e != nil {
		return e
	}
	if e = sameBinaryTree(updater.CurrentDir(l.POS()), previousTree); e != nil {
		return e
	}
	if _, e = licensedRecovery(r, st.Current, st.High, previousProof); e != nil {
		return e
	}
	setupBytes, e := os.ReadFile(l.Setup())
	if e != nil {
		return e
	}
	if e = writeAtomic(filepath.Join(stage, "previous-setup.exe"), setupBytes); e != nil {
		return e
	}
	setupBytes, e = os.ReadFile(i.SetupSource)
	if e != nil {
		return e
	}
	if e = writeAtomic(filepath.Join(stage, "next-setup.exe"), setupBytes); e != nil {
		return e
	}
	if e = i.Host.Secure(l); e != nil {
		return e
	}
	next := r
	next.EdgeVersion = b.Edge.Version
	next.EdgeHash = b.Edge.SHA256
	next.BootstrapRelease = b.Release
	next.BootstrapHigh = b.Release
	next.Bootstrap = raw
	next.Config.InitialVersion = pos.Version
	next.Config.InitialRelease = pos.Release
	if _, e = os.Stat(filepath.Dir(l.Edge(next.EdgeVersion))); !os.IsNotExist(e) {
		return errors.New("candidate Edge directory already exists")
	}
	j := upgradeJournal{Phase: "prepared", Previous: r, Candidate: next, PreviousPOS: st.Current, PreviousPOSProof: previousProof, PreviousPOSHigh: st.High, CandidatePOS: pos.Version}
	if e = i.writeUpgrade(j); e != nil {
		return e
	}
	journalWritten = true
	// Every subsequent failure leaves the durable recovery record and old binaries.
	if e = os.MkdirAll(filepath.Dir(filepath.Dir(l.Edge(next.EdgeVersion))), 0700); e != nil {
		return e
	}
	if e = replaceFile(edgeNew, filepath.Dir(l.Edge(next.EdgeVersion))); e != nil {
		return e
	}
	if e = os.RemoveAll(updater.RollbackDir(l.POS())); e != nil {
		return e
	}
	if e = replaceFile(updater.CurrentDir(l.POS()), updater.RollbackDir(l.POS())); e != nil {
		return e
	}
	if e = replaceFile(posNew, updater.CurrentDir(l.POS())); e != nil {
		return e
	}
	if e = writeAtomic(l.Setup(), setupBytes); e != nil {
		return e
	}
	if e = u.RegisterCoordinatedUpgrade(b.POS); e != nil {
		return e
	}
	if e = writeJSON(l.Config(), next.Config); e != nil {
		return e
	}
	if e = writeJSON(l.Receipt(), next); e != nil {
		return e
	}
	j.Phase = "probation"
	if e = i.writeUpgrade(j); e != nil {
		return e
	}
	i.report("POS and Edge upgraded; previous binaries retained until authenticated POS startup health passes")
	return nil
}

// RecoverUpgrade requires stopped managed processes. It is also used after a
// failed startup. It never restores a database, credentials, or release counter.
func (i *Installer) RecoverUpgrade(ctx context.Context) (err error) {
	unlock, e := i.lock()
	if e != nil {
		return e
	}
	defer unlock()
	j, e := i.readUpgrade()
	if os.IsNotExist(e) {
		return nil
	}
	if e != nil {
		return e
	}
	l := i.Layout
	if j.Phase != "committed" {
		installed, loadErr := Load(l)
		if loadErr != nil {
			return loadErr
		}
		if !reflect.DeepEqual(installed.Distribution, j.Previous.Distribution) || !reflect.DeepEqual(j.Candidate.Distribution, j.Previous.Distribution) {
			return errors.New("recovery trust differs from installed distribution; preserve files")
		}
		if _, e = licensedRecovery(j.Previous, j.PreviousPOS, j.PreviousPOSHigh, j.PreviousPOSProof); e != nil {
			return e
		}
	}
	if j.Phase == "committed" || j.Phase == "restored" {
		return i.cleanupUpgrade(j)
	}
	if e = writeAtomic(l.Maintenance(), []byte("application recovery\n")); e != nil {
		return e
	}
	defer os.Remove(l.Maintenance())
	if e = i.Host.Quiesce(ctx, l, j.Previous, true); e != nil {
		return e
	}
	u, e := updater.OpenExisting(j.Previous.Config, updater.NativeProcess{})
	if e != nil {
		return e
	}
	defer func() { err = errors.Join(err, u.Close()) }()
	if e = u.ValidateDataSeparation(); e != nil {
		return e
	}
	previousPOS, e := licensedRecovery(j.Previous, j.PreviousPOS, j.PreviousPOSHigh, j.PreviousPOSProof)
	if e != nil {
		return e
	}
	previousArchive := filepath.Join(l.upgradeDir(), "previous-pos.zip")
	if e = updater.VerifyArtifact(previousArchive, previousPOS); e != nil {
		return e
	}
	restore := filepath.Join(l.upgradeDir(), "restore-pos")
	if e = os.RemoveAll(restore); e != nil {
		return e
	}
	if e = updater.ExtractBundle(previousArchive, restore, updater.Executable); e != nil {
		return e
	}
	if e = updater.MarkRelease(restore, j.PreviousPOS); e != nil {
		return e
	}
	if e = os.RemoveAll(updater.CurrentDir(l.POS())); e != nil {
		return e
	}
	if e = replaceFile(restore, updater.CurrentDir(l.POS())); e != nil {
		return e
	}
	// Keep the new coordinator on binary rollback: old Setup cannot parse the
	// additive high-water receipt. POS and Edge roll back; Setup never downgrades.
	running, e := os.Executable()
	if e != nil {
		return e
	}
	ri, e := os.Stat(running)
	if e != nil {
		return e
	}
	si, e := os.Stat(l.Setup())
	if e != nil && !os.IsNotExist(e) {
		return e
	}
	if si == nil || !os.SameFile(ri, si) {
		next, e := os.ReadFile(filepath.Join(l.upgradeDir(), "next-setup.exe"))
		if e != nil {
			return e
		}
		if e = writeAtomic(l.Setup(), next); e != nil {
			return e
		}
	}
	if e = u.RestoreCoordinatedVersion(j.PreviousPOS, j.CandidatePOS); e != nil {
		return e
	}
	j.Previous.BootstrapHigh = max(j.Previous.BootstrapHigh, j.Candidate.BootstrapRelease)
	if e = writeJSON(l.Config(), j.Previous.Config); e != nil {
		return e
	}
	if e = writeJSON(l.Receipt(), j.Previous); e != nil {
		return e
	}
	if e = os.RemoveAll(updater.RollbackDir(l.POS())); e != nil {
		return e
	}
	j.Phase = "restored"
	if e = i.writeUpgrade(j); e != nil {
		return e
	}
	return i.cleanupUpgrade(j)
}
func (i *Installer) cleanupUpgrade(j upgradeJournal) error {
	obsolete := j.Previous.EdgeVersion
	if j.Phase == "restored" {
		obsolete = j.Candidate.EdgeVersion
	}
	if obsolete != j.Previous.EdgeVersion && obsolete != j.Candidate.EdgeVersion {
		return errors.New("invalid obsolete Edge version")
	}
	if e := os.RemoveAll(filepath.Dir(i.Layout.Edge(obsolete))); e != nil {
		return e
	}
	if e := os.RemoveAll(i.Layout.upgradeDir()); e != nil {
		return e
	}
	return os.Remove(i.Layout.upgradeJournal())
}

// CompleteUpgrade is called only after existing authenticated startup health
// reports the exact candidate stable. Durable commit precedes backup cleanup.
func (i *Installer) CompleteUpgrade(st updater.State) error {
	unlock, e := i.lock()
	if e != nil {
		return e
	}
	defer unlock()
	j, e := i.readUpgrade()
	if os.IsNotExist(e) {
		return nil
	}
	if e != nil {
		return e
	}
	if j.Phase == "committed" || j.Phase == "restored" {
		return i.cleanupUpgrade(j)
	}
	if j.Phase != "probation" || !st.StartupVerified || st.Current != j.CandidatePOS {
		return errors.New("application upgrade has not passed candidate startup health")
	}
	j.Phase = "committed"
	if e = i.writeUpgrade(j); e != nil {
		return e
	}
	return i.cleanupUpgrade(j)
}
