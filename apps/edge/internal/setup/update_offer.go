package setup

import (
	"context"
	"errors"
	"fmt"
	"time"
	"vynic.local/edge/internal/updater"
)

// UpdateProgress describes observed work, never simulated completion.
type UpdateProgress struct {
	Message           string
	Downloaded, Total int64
}

func (p UpdateProgress) Percent() int {
	if p.Total <= 0 {
		return 0
	}
	return int(min(100, max(0, float64(p.Downloaded)*100/float64(p.Total))))
}

type UpdateOfferResult struct {
	Message string
	Ready   bool
}
type updateOfferOps struct {
	startHost func(context.Context) error
	snapshot  func(context.Context) (updater.State, error)
	check     func(context.Context) error
	launch    func(context.Context, func(UpdateProgress)) error
	interval  time.Duration
}

func needsStartupRecovery(st updater.State) bool {
	unverifiedLaunch := st.Nonce != "" && st.PID > 0 && !st.StartupVerified && st.Status != "FAILED" && st.Status != "ROLLED_BACK"
	return st.Swap != "" && st.Swap != "cleanup" || st.Status == "INSTALLING" || st.Status == "RESTARTING" || unverifiedLaunch
}

// Download first unless the installed Edge explicitly requires startup recovery.
// Installation remains a separate, consented POS operation behind its readiness gate.
func offerPOSUpdate(ctx context.Context, ops updateOfferOps, report func(UpdateProgress)) (UpdateOfferResult, error) {
	report(UpdateProgress{Message: "Connecting to the local update service…"})
	if e := ops.startHost(ctx); e != nil {
		return UpdateOfferResult{}, e
	}
	st, e := ops.snapshot(ctx)
	if e != nil {
		return UpdateOfferResult{}, e
	}
	if needsStartupRecovery(st) {
		report(UpdateProgress{Message: "The previous installation needs startup verification before Edge can check for updates."})
		if e = ops.launch(ctx, report); e != nil {
			return UpdateOfferResult{}, e
		}
		st, e = ops.snapshot(ctx)
		if e != nil {
			return UpdateOfferResult{}, e
		}
		if needsStartupRecovery(st) {
			return UpdateOfferResult{}, errors.New("startup recovery is still pending; inspect logs/edge.log")
		}
	}
	// The pinned Edge refuses checks during cleanup; do not misreport its old
	// SUCCESS snapshot as a completed check of the current release feed.
	if st.CleanupPending {
		return UpdateOfferResult{}, fmt.Errorf("previous release cleanup is pending: %s; retry Update POS after cleanup completes", st.Reason)
	}
	if st.Status != "DOWNLOADING" && st.Status != "CHECKING" && st.Status != "READY_TO_INSTALL" && st.Status != "BLOCKED" {
		report(UpdateProgress{Message: "Checking the signed release manifest…"})
		if e = ops.check(ctx); e != nil {
			return UpdateOfferResult{}, e
		}
	}
	ticker := time.NewTicker(ops.interval)
	defer ticker.Stop()
	started := time.Now()
	for polls := 0; ; polls++ {
		select {
		case <-ctx.Done():
			return UpdateOfferResult{}, fmt.Errorf("update monitoring stopped: %w; Edge may continue downloading in the background", ctx.Err())
		case <-ticker.C:
		}
		st, e = ops.snapshot(ctx)
		if e != nil {
			return UpdateOfferResult{}, e
		}
		progress, result, done, e := updateOfferStatus(st, polls)
		if progress.Message != "" {
			if !done {
				progress.Message += fmt.Sprintf("\nElapsed: %ds", int(time.Since(started).Seconds()))
			}
			report(progress)
		}
		if e != nil {
			return UpdateOfferResult{}, e
		}
		if done {
			return result, nil
		}
	}
}

func updateOfferStatus(st updater.State, polls int) (UpdateProgress, UpdateOfferResult, bool, error) {
	p := UpdateProgress{}
	r := UpdateOfferResult{}
	switch st.Status {
	case "CHECKING":
		p.Message = "Checking the signed release manifest and compatibility…"
	case "DOWNLOADING":
		p.Downloaded, p.Total = st.Downloaded, st.Total
		if st.Total > 0 {
			p.Message = fmt.Sprintf("Downloading POS %s\n%d%% — %.1f / %.1f MB", st.Version, p.Percent(), float64(max(0, st.Downloaded))/1e6, float64(st.Total)/1e6)
			if st.Downloaded >= st.Total {
				p.Message += "\nDownload received. Verifying SHA-256 and preparing the release…"
			}
		} else {
			p.Message = fmt.Sprintf("Downloading POS %s\n%.1f MB received; total size unavailable", st.Version, float64(max(0, st.Downloaded))/1e6)
		}
	case "READY_TO_INSTALL", "BLOCKED":
		r = UpdateOfferResult{Message: "POS " + st.Version + " is downloaded and verified.\nOpen POS and choose Update Now to install, or choose Later to keep it staged.", Ready: true}
		if st.Status == "BLOCKED" {
			r.Message += "\nInstallation is currently blocked: " + st.Reason
		}
		p.Message = r.Message
		return p, r, true, nil
	case "INSTALLING", "RESTARTING":
		p.Message = "The update was confirmed in POS. Waiting for installation and startup health checks…"
	case "SUCCESS", "UP_TO_DATE":
		if polls >= 2 && !needsStartupRecovery(st) {
			r.Message = "Vynic POS " + st.Current + " is up to date."
			p.Message = r.Message
			return p, r, true, nil
		}
	case "FAILED", "ROLLED_BACK":
		return p, r, true, fmt.Errorf("POS update %s: %s", st.Status, st.Reason)
	default:
		return p, r, true, fmt.Errorf("unrecognized updater status %q", st.Status)
	}
	return p, r, false, nil
}
