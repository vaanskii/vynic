package setup

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gofrs/flock"
	"vynic.local/edge/internal/store"
	"vynic.local/edge/internal/updater"
)

type Layout struct{ Root string }

func (l Layout) Config() string   { return filepath.Join(l.Root, "config", "pos-updater.json") }
func (l Layout) POS() string      { return filepath.Join(l.Root, "pos") }
func (l Layout) EdgeData() string { return filepath.Join(l.Root, "state", "edge") }
func (l Layout) Receipt() string  { return filepath.Join(l.Root, "config", "installation.json") }
func (l Layout) Setup() string    { return filepath.Join(l.Root, "bin", SetupExecutable) }
func (l Layout) Edge(v string) string {
	return filepath.Join(l.Root, "edge", "releases", v, EdgeExecutable)
}
func (l Layout) Maintenance() string { return filepath.Join(l.Root, "state", "maintenance") }
func (l Layout) StopFile() string    { return filepath.Join(l.Root, "state", "stop-host") }

type Receipt struct {
	Schema           int             `json:"schema"`
	Status           string          `json:"status"`
	Distribution     Distribution    `json:"distribution"`
	Bootstrap        json.RawMessage `json:"bootstrap"`
	EdgeVersion      string          `json:"edgeVersion"`
	EdgeHash         string          `json:"edgeHash"`
	BootstrapRelease uint64          `json:"bootstrapRelease"`
	RepairBase       string          `json:"repairBase"`
	POSReleaseBase   string          `json:"posReleaseBase"`
	Config           updater.Config  `json:"config"`
}

// Host performs only same-user, fixed-path Windows integration. Simulators never
// execute the downloaded fake Windows bundles.
type Host interface {
	Secure(Layout) error
	Quiesce(context.Context, Layout, Receipt) error
	Integrate(Layout) error
	RemoveIntegration(Layout) error
}
type Installer struct {
	Layout       Layout
	Distribution Distribution
	Client       *http.Client
	Host         Host
	SetupSource  string
	Report       func(string)
}

func (i *Installer) report(s string) {
	if i.Report != nil {
		i.Report(s)
	}
}
func readJSON(path string, v any) error {
	b, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	if len(b) > 256<<10 {
		return errors.New("local metadata too large")
	}
	return strict(b, v)
}
func writeJSON(path string, v any) error {
	b, e := json.MarshalIndent(v, "", "  ")
	if e != nil {
		return e
	}
	return writeAtomic(path, b)
}
func writeAtomic(path string, b []byte) error {
	if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return e
	}
	p := path + ".tmp"
	f, e := os.OpenFile(p, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	_, e = f.Write(b)
	e = errors.Join(e, f.Sync(), f.Close())
	if e != nil {
		return e
	}
	return replaceFile(p, path)
}
func Load(l Layout) (Receipt, error) {
	var r Receipt
	e := readJSON(l.Receipt(), &r)
	if e != nil {
		return r, e
	}
	if r.Schema != 1 || !version.MatchString(r.EdgeVersion) || r.Config.Root != l.POS() || r.Config.Listen != "127.0.0.1:7444" || len(r.Config.Token) != 64 || !version.MatchString(r.Config.InitialVersion) || (r.Status != "provisioning" && r.Status != "installed" && r.Status != "removed") || !https(r.RepairBase) || !https(r.POSReleaseBase) {
		return r, errors.New("invalid installation receipt; preserve state and contact support")
	}
	return r, nil
}

// PrepareRoot refuses linked trees before creating any logs or credentials.
func PrepareRoot(l Layout, h Host) error {
	if !filepath.IsAbs(l.Root) {
		return errors.New("absolute install root required")
	}
	if e := rejectLinks(l.Root); e != nil {
		return e
	}
	if e := os.MkdirAll(l.Root, 0700); e != nil {
		return e
	}
	return h.Secure(l)
}
func (i *Installer) lock() (func(), error) {
	l := i.Layout
	if !filepath.IsAbs(l.Root) || filepath.Base(l.Root) == "." {
		return nil, errors.New("absolute dedicated install root required")
	}
	if e := rejectLinks(l.Root); e != nil {
		return nil, e
	}
	if e := os.MkdirAll(l.Root, 0700); e != nil {
		return nil, e
	}
	if e := i.Host.Secure(l); e != nil {
		return nil, e
	}
	f := flock.New(filepath.Join(l.Root, "setup.lock"))
	ok, e := f.TryLock()
	if e != nil {
		return nil, e
	}
	if !ok {
		return nil, errors.New("another setup/repair is running")
	}
	return func() { _ = f.Unlock() }, nil
}

// Reject symlinks and Windows reparse points before traversing any owned tree.
func rejectLinks(root string) error {
	for p := root; ; p = filepath.Dir(p) {
		info, e := os.Lstat(p)
		if e == nil && info.Mode()&os.ModeSymlink != 0 {
			return errors.New("linked install path refused")
		}
		if e != nil && !os.IsNotExist(e) {
			return e
		}
		if e == nil {
			if e = checkReparse(p); e != nil {
				return e
			}
		}
		if filepath.Dir(p) == p {
			break
		}
	}
	if _, e := os.Stat(root); os.IsNotExist(e) {
		return nil
	}
	return filepath.WalkDir(root, func(p string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if d.Type()&os.ModeSymlink != 0 {
			return errors.New("linked install tree refused")
		}
		return checkReparse(p)
	})
}
func (i *Installer) Install(ctx context.Context, repair bool) (err error) {
	unlock, e := i.lock()
	if e != nil {
		return e
	}
	defer unlock()
	l := i.Layout
	c := SecureClient(i.Client)
	r, e := Load(l)
	exists := e == nil
	if e != nil && !os.IsNotExist(e) {
		return e
	}
	if exists && r.Status == "installed" && !repair {
		return errors.New("already installed; use Open, Repair or Uninstall")
	}
	if repair && !exists {
		return errors.New("installation receipt missing; refusing to guess credentials/state")
	}
	if !exists {
		// A missing receipt must never turn retained state into a fresh database.
		for _, p := range []string{l.POS(), l.EdgeData()} {
			if _, e = os.Stat(p); e == nil {
				return errors.New("unregistered retained state: refusing fresh initialization")
			} else if !os.IsNotExist(e) {
				return e
			}
		}
	}
	// Recover an interrupted prior binary swap before any network dependency.
	// Failure to download a repair must not strand the previous working release.
	maintained := false
	if exists {
		if e = writeAtomic(l.Maintenance(), []byte("setup\n")); e != nil {
			return e
		}
		defer os.Remove(l.Maintenance())
		maintained = true
		if e = i.Host.Quiesce(ctx, l, r); e != nil {
			return e
		}
		if e = i.recoverSwaps(); e != nil {
			return e
		}
	}
	d := i.Distribution
	feed := d.BootstrapURL
	if exists {
		d = r.Distribution
		feed = strings.TrimRight(r.RepairBase, "/") + "/" + strconv.FormatUint(r.BootstrapRelease, 10) + ".json"
	}
	i.report("Checking signed installation metadata")
	raw, e := fetch(ctx, c, feed, 128<<10)
	if e != nil {
		return e
	}
	b, pos, e := Verify(raw, d, time.Now())
	if e != nil {
		return e
	}
	if exists && (b.Release != r.BootstrapRelease || b.Edge.Version != r.EdgeVersion || b.Edge.SHA256 != r.EdgeHash || pos.Version != r.Config.InitialVersion || pos.Release != r.Config.InitialRelease || b.POSFeed != r.Config.Feed || b.RepairBase != r.RepairBase || b.POSReleaseBase != r.POSReleaseBase) {
		return errors.New("repair metadata changes installed baseline; Edge self-update is not supported")
	}
	if !exists {
		secret := make([]byte, 32)
		if _, e = rand.Read(secret); e != nil {
			return e
		}
		r = Receipt{Schema: 1, Status: "provisioning", Distribution: d, Bootstrap: raw, EdgeVersion: b.Edge.Version, EdgeHash: b.Edge.SHA256, BootstrapRelease: b.Release, RepairBase: b.RepairBase, POSReleaseBase: b.POSReleaseBase, Config: updater.Config{Root: l.POS(), Feed: b.POSFeed, Channel: d.Channel, InitialVersion: pos.Version, InitialRelease: pos.Release, Listen: "127.0.0.1:7444", Token: hex.EncodeToString(secret), Keys: d.Keys}}
		if e = writeJSON(l.Receipt(), r); e != nil {
			return e
		}
	}
	// Prevent new shortcut/logon launches, then stop only the local host.
	if !maintained {
		if e = writeAtomic(l.Maintenance(), []byte("setup\n")); e != nil {
			return e
		}
		defer os.Remove(l.Maintenance())
		if e = i.Host.Quiesce(ctx, l, r); e != nil {
			return e
		}
		if e = i.recoverSwaps(); e != nil {
			return e
		}
	}
	posRaw := b.POS
	if exists && r.Status != "provisioning" {
		if _, e = os.Stat(filepath.Join(l.POS(), "updater.sqlite")); e != nil {
			return fmt.Errorf("retained updater state missing: %w", e)
		}
		u, e := updater.OpenExisting(r.Config, updater.NativeProcess{})
		if e != nil {
			return e
		}
		e = u.PrepareRepair(r.Status == "removed")
		st := u.Snapshot()
		e = errors.Join(e, u.Close())
		if e != nil {
			return e
		}
		if st.Status == "INSTALLING" || st.Status == "RESTARTING" {
			return errors.New("unresolved POS install: recover via existing Edge before repair")
		}
		if st.Current != pos.Version {
			pr, e := fetch(ctx, c, strings.TrimRight(r.POSReleaseBase, "/")+"/"+st.Current+".json", 64<<10)
			if e != nil {
				return e
			}
			posRaw = pr
			pos, e = updater.Verify(pr, d.Keys, d.Channel, "0.0.0", 0, time.Now())
			if e != nil {
				return e
			}
			if pos.Version != st.Current || pos.Release > st.High {
				return errors.New("repair release does not match active POS/high-water")
			}
		}
	}
	stage := filepath.Join(l.Root, "staging")
	if e = os.MkdirAll(stage, 0700); e != nil {
		return e
	}
	posStage := updater.StagingDir(l.POS())
	if e = os.MkdirAll(posStage, 0700); e != nil {
		return e
	}
	// Installer scratch and deferred updater candidates are separate names in the
	// same bounded staging slot. A repair must preserve a user's Later choice.
	posZip := filepath.Join(posStage, "setup.zip")
	defer func() {
		err = errors.Join(err, os.RemoveAll(stage), os.RemoveAll(posZip), os.RemoveAll(posZip+".part"))
	}()
	if e = download(ctx, c, b.Edge, filepath.Join(stage, "vynic-edge.zip"), i.report); e != nil {
		return e
	}
	if e = download(ctx, c, pos, posZip, i.report); e != nil {
		return e
	}
	// Expiry/trust is rechecked after potentially slow downloads.
	if _, _, e = Verify(raw, d, time.Now()); e != nil {
		return e
	}
	if _, e = updater.Verify(posRaw, d.Keys, d.Channel, "0.0.0", 0, time.Now()); e != nil {
		return e
	}
	// Verify all packages before modifying any working binary directory.
	edgeNew := filepath.Join(stage, "edge-new")
	posNew := filepath.Join(posStage, "setup-release")
	defer func() { err = errors.Join(err, os.RemoveAll(posNew)) }()
	for _, p := range []string{edgeNew, posNew} {
		if e = os.RemoveAll(p); e != nil {
			return e
		}
	}
	if e = updater.ExtractBundle(filepath.Join(stage, "vynic-edge.zip"), edgeNew, EdgeExecutable); e != nil {
		return e
	}
	if e = updater.ExtractBundle(posZip, posNew, updater.Executable); e != nil {
		return e
	}
	if e = updater.MarkRelease(posNew, pos.Version); e != nil {
		return e
	}
	// Full Flutter bundle, not a lone executable.
	for _, p := range []string{filepath.Join(posNew, "flutter_windows.dll"), filepath.Join(posNew, "data", "icudtl.dat"), filepath.Join(posNew, "data", "flutter_assets")} {
		if _, e = os.Stat(p); e != nil {
			return fmt.Errorf("incomplete Flutter bundle: %w", e)
		}
	}
	if e = i.Host.Secure(l); e != nil {
		return e
	}
	i.report("Provisioning local identity and updater")
	// Existing databases are opened/validated, never reset, migrated backwards or copied.
	s, e := store.Open(l.EdgeData(), r.Status == "provisioning")
	if e != nil {
		return e
	}
	var id store.Identity
	if r.Status == "provisioning" {
		id, e = s.Init()
	} else {
		id, e = s.Identity()
	}
	if e == nil {
		e = writeAtomic(filepath.Join(l.EdgeData(), "edge-cert.pem"), id.Certificate)
	}
	e = errors.Join(e, s.Close())
	if e != nil {
		return e
	}
	var u *updater.Service
	if r.Status == "provisioning" {
		u, e = updater.Open(r.Config, updater.NativeProcess{})
	} else {
		u, e = updater.OpenExisting(r.Config, updater.NativeProcess{})
	}
	if e != nil {
		return e
	}
	defer func() { err = errors.Join(err, u.Close()) }()
	if e = writeJSON(l.Config(), r.Config); e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(l.Setup()), 0700); e != nil {
		return e
	}
	swaps := []swap{{Target: filepath.Dir(l.Edge(r.EdgeVersion)), New: edgeNew}, {Target: updater.CurrentDir(l.POS()), New: posNew, Backup: updater.RollbackDir(l.POS())}}
	sourceInfo, e := os.Stat(i.SetupSource)
	if e != nil {
		return e
	}
	targetInfo, statErr := os.Stat(l.Setup())
	if statErr != nil && !os.IsNotExist(statErr) {
		return statErr
	}
	if statErr != nil || !os.SameFile(sourceInfo, targetInfo) {
		source, e := os.ReadFile(i.SetupSource)
		if e != nil {
			return e
		}
		setupNew := filepath.Join(stage, "setup-new.exe")
		if e = writeAtomic(setupNew, source); e != nil {
			return e
		}
		swaps = append(swaps, swap{Target: l.Setup(), New: setupNew})
	}
	for _, swap := range swaps {
		if swap.Target == updater.CurrentDir(l.POS()) {
			continue
		}
		if e = os.RemoveAll(swap.backup()); e != nil {
			return e
		}
	}
	if e = i.beginSwaps(swaps); e != nil {
		return e
	}
	defer func() {
		if err != nil {
			err = errors.Join(err, i.recoverSwaps())
		}
	}()
	if e = i.Host.Integrate(l); e != nil {
		return fmt.Errorf("startup/shortcut integration: %w", e)
	}
	r.Status = "installed"
	r.Bootstrap = raw
	if e = writeJSON(l.Receipt(), r); e != nil {
		return e
	}
	// Record the POS probation before committing setup's multi-binary journal.
	// A crash before journal deletion restores the original trees; a crash after
	// deletion leaves current+rollback for Edge's authenticated stabilization.
	if e = u.RegisterRepair(swaps[1].HadOld); e != nil {
		return e
	}
	// The journal's deletion is the commit point; old trees remain until then.
	if e = os.Remove(filepath.Join(l.Root, "state", "swap.json")); e != nil {
		return e
	}
	for _, s := range swaps {
		if s.Target == updater.CurrentDir(l.POS()) {
			continue
		}
		if e = os.RemoveAll(s.backup()); e != nil {
			return e
		}
	}
	i.report("Installation ready")
	return nil
}

type swap struct {
	Target, New string
	Backup      string `json:",omitempty"`
	HadOld      bool
}

func (s swap) backup() string {
	if s.Backup != "" {
		return s.Backup
	}
	return s.Target + ".setup-old"
}

func (i *Installer) beginSwaps(ss []swap) error {
	for n := range ss {
		_, e := os.Stat(ss[n].Target)
		ss[n].HadOld = e == nil
		if e != nil && !os.IsNotExist(e) {
			return e
		}
		if _, e = os.Stat(ss[n].backup()); e == nil {
			return errors.New("uncommitted backup directory requires recovery")
		}
		if e = os.MkdirAll(filepath.Dir(ss[n].Target), 0700); e != nil {
			return e
		}
	}
	if e := writeJSON(filepath.Join(i.Layout.Root, "state", "swap.json"), ss); e != nil {
		return e
	}
	for _, s := range ss {
		if s.HadOld {
			if e := replaceFile(s.Target, s.backup()); e != nil {
				return errors.Join(e, i.recoverSwaps())
			}
		}
		if e := replaceFile(s.New, s.Target); e != nil {
			return errors.Join(e, i.recoverSwaps())
		}
	}
	return nil
}
func (i *Installer) recoverSwaps() error {
	p := filepath.Join(i.Layout.Root, "state", "swap.json")
	var ss []swap
	e := readJSON(p, &ss)
	if os.IsNotExist(e) {
		return nil
	}
	if e != nil {
		return e
	}
	for _, s := range ss {
		if s.Target == i.Layout.Setup() {
			exe, e := os.Executable()
			if e != nil {
				return e
			}
			running, e := os.Stat(exe)
			if e != nil {
				return e
			}
			target, e := os.Stat(s.Target)
			if e == nil && os.SameFile(running, target) {
				return errors.New("interrupted setup replacement: run the original downloaded VynicSetup to repair; the installed setup is currently locked")
			}
		}
	}
	for _, s := range ss {
		rel, e := filepath.Rel(i.Layout.Root, s.Target)
		validRelease := e == nil && !strings.HasPrefix(rel, "..") && (strings.HasPrefix(rel, filepath.Join("edge", "releases")+string(os.PathSeparator)) || strings.HasPrefix(rel, filepath.Join("pos", "releases")+string(os.PathSeparator))) && version.MatchString(filepath.Base(s.Target))
		if (!validRelease && s.Target != i.Layout.Setup() && s.Target != updater.CurrentDir(i.Layout.POS())) || (s.Backup != "" && (s.Target != updater.CurrentDir(i.Layout.POS()) || s.Backup != updater.RollbackDir(i.Layout.POS()))) {
			return errors.New("invalid recovery journal target")
		}
		if s.HadOld {
			if _, e = os.Stat(s.backup()); e == nil {
				if e = os.RemoveAll(s.Target); e != nil {
					return e
				}
				if e = replaceFile(s.backup(), s.Target); e != nil {
					return e
				}
			} else if !os.IsNotExist(e) {
				return e
			}
		} else {
			if e = os.RemoveAll(s.Target); e != nil {
				return e
			}
		}
	}
	return os.Remove(p)
}

// Uninstall deliberately offers no data-deletion path. Retained identity, Hive,
// updater history/config and diagnostics allow a later explicit Repair.
func (i *Installer) Uninstall(ctx context.Context) error {
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
	if e = writeAtomic(l.Maintenance(), []byte("uninstall\n")); e != nil {
		return e
	}
	defer os.Remove(l.Maintenance())
	if e = i.Host.Quiesce(ctx, l, r); e != nil {
		return e
	}
	if e = i.recoverSwaps(); e != nil {
		return e
	}
	if r.Status != "provisioning" {
		if _, e = os.Stat(filepath.Join(l.POS(), "updater.sqlite")); e != nil {
			return fmt.Errorf("retained updater state unavailable: %w", e)
		}
		u, e := updater.OpenExisting(r.Config, updater.NativeProcess{})
		if e != nil {
			return e
		}
		st := u.Snapshot()
		e = errors.Join(u.ValidateDataSeparation(), u.Close())
		if e != nil {
			return e
		}
		if st.Status == "INSTALLING" || st.Status == "RESTARTING" || (st.Swap != "" && st.Swap != "repair_ready" && st.Swap != "cleanup") {
			return errors.New("unresolved POS install; recover before uninstall")
		}
	}
	if e = i.Host.RemoveIntegration(l); e != nil {
		return e
	}
	// Persist removal before deleting binaries so interruption cannot autolaunch.
	r.Status = "removed"
	if e = writeJSON(l.Receipt(), r); e != nil {
		return e
	}
	for _, p := range []string{filepath.Join(l.Root, "edge", "releases"), filepath.Join(l.POS(), "releases"), updater.CurrentDir(l.POS()), updater.RollbackDir(l.POS()), updater.StagingDir(l.POS()), filepath.Join(l.POS(), "staged.zip"), filepath.Join(l.POS(), "staged.zip.part"), filepath.Join(l.Root, "staging")} {
		if e = os.RemoveAll(p); e != nil {
			return e
		}
	}
	return nil
}
