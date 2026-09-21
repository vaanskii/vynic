package setup

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"
	"vynic.local/edge/internal/updater"
)

func TestUpdateDownloadProgressUsesObservedBytes(t *testing.T) {
	for _, tc := range []struct {
		downloaded, total int64
		percent           int
	}{{0, 100, 0}, {42, 100, 42}, {100, 100, 100}, {101, 100, 100}, {-1, 100, 0}, {10, 0, 0}} {
		p := UpdateProgress{Downloaded: tc.downloaded, Total: tc.total}
		if p.Percent() != tc.percent {
			t.Fatal(p, p.Percent())
		}
	}
	p, _, done, e := updateOfferStatus(updater.State{Status: "DOWNLOADING", Version: "1.0.2", Downloaded: 12_500_000, Total: 25_000_000}, 4)
	if e != nil || done || !strings.Contains(p.Message, "50% — 12.5 / 25.0 MB") {
		t.Fatal(p, done, e)
	}
	p, _, done, e = updateOfferStatus(updater.State{Status: "DOWNLOADING", Downloaded: 25, Total: 25}, 4)
	if e != nil || done || !strings.Contains(p.Message, "Verifying SHA-256") {
		t.Fatal("100% bytes must not imply release verified", p, done, e)
	}
	p, _, _, _ = updateOfferStatus(updater.State{Status: "CHECKING", Version: "old"}, 4)
	if strings.Contains(p.Message, "Downloading") || p.Total != 0 {
		t.Fatal(p)
	}
	p, _, _, _ = updateOfferStatus(updater.State{Status: "DOWNLOADING", Downloaded: 10}, 4)
	if strings.Contains(p.Message, "%") {
		t.Fatal("unknown size given fake percentage")
	}
}

func TestOfferDownloadsWithoutLaunchingPOSAndLeavesConsentInPOS(t *testing.T) {
	states := []updater.State{
		{Status: "UP_TO_DATE", Current: "1.0.0"},
		{Status: "CHECKING"},
		{Status: "DOWNLOADING", Version: "1.0.1", Downloaded: 5, Total: 10},
		{Status: "DOWNLOADING", Version: "1.0.1", Downloaded: 10, Total: 10},
		{Status: "READY_TO_INSTALL", Version: "1.0.1"},
	}
	var calls []string
	var progress []UpdateProgress
	ops := updateOfferOps{
		startHost: func(context.Context) error { calls = append(calls, "host"); return nil },
		snapshot:  func(context.Context) (updater.State, error) { st := states[0]; states = states[1:]; return st, nil },
		check:     func(context.Context) error { calls = append(calls, "check"); return nil },
		launch:    func(context.Context, func(UpdateProgress)) error { t.Fatal("download launched POS"); return nil },
		interval:  time.Millisecond,
	}
	r, e := offerPOSUpdate(context.Background(), ops, func(p UpdateProgress) { progress = append(progress, p) })
	if e != nil || !r.Ready || !reflect.DeepEqual(calls, []string{"host", "check"}) {
		t.Fatal(r, e, calls)
	}
	found := false
	for _, p := range progress {
		if p.Total == 10 && p.Percent() == 50 {
			found = true
		}
	}
	if !found || !strings.Contains(r.Message, "Later") {
		t.Fatal("missing live progress/staged outcome", progress, r)
	}
}

func TestOfferExplainsRequiredRecoveryAndNeverClaimsUnresolvedSuccess(t *testing.T) {
	for _, stuck := range []bool{false, true} {
		var calls []string
		recovered := false
		ops := updateOfferOps{
			startHost: func(context.Context) error { return nil },
			snapshot: func(context.Context) (updater.State, error) {
				if !recovered || stuck {
					return updater.State{Status: "UP_TO_DATE", Swap: "repair_ready"}, nil
				}
				return updater.State{Status: "READY_TO_INSTALL", Version: "1.0.1", StartupVerified: true}, nil
			},
			launch: func(_ context.Context, report func(UpdateProgress)) error {
				calls = append(calls, "recovery")
				report(UpdateProgress{Message: "Checking startup health; elapsed 30s"})
				recovered = true
				return nil
			},
			check:    func(context.Context) error { t.Fatal("already staged update checked again"); return nil },
			interval: time.Millisecond,
		}
		var messages []string
		r, e := offerPOSUpdate(context.Background(), ops, func(p UpdateProgress) { messages = append(messages, p.Message) })
		if stuck && (e == nil || r.Ready) {
			t.Fatal("unresolved recovery treated as success")
		}
		if !stuck && (e != nil || !r.Ready) {
			t.Fatal(r, e)
		}
		if !reflect.DeepEqual(calls, []string{"recovery"}) || !strings.Contains(strings.Join(messages, " "), "previous installation") {
			t.Fatal(calls, messages)
		}
	}
}

func TestOfferFailureAndCancellationStayVisible(t *testing.T) {
	for _, status := range []string{"FAILED", "ROLLED_BACK", "UNKNOWN"} {
		_, r, done, e := updateOfferStatus(updater.State{Status: status, Reason: "network lost"}, 4)
		if e == nil || !done || r.Ready {
			t.Fatal(status, r, done, e)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	ops := updateOfferOps{
		startHost: func(context.Context) error { return nil },
		snapshot:  func(context.Context) (updater.State, error) { return updater.State{Status: "DOWNLOADING"}, nil },
		interval:  time.Millisecond,
	}
	r, e := offerPOSUpdate(ctx, ops, func(UpdateProgress) {})
	if !errors.Is(e, context.Canceled) || r.Ready {
		t.Fatal(r, e)
	}
}

func TestUnverifiedLaunchIsNotAnUpToDateCheck(t *testing.T) {
	st := updater.State{Status: "UP_TO_DATE", Nonce: "nonce", PID: 42}
	if !needsStartupRecovery(st) {
		t.Fatal("active health check ignored")
	}
	_, _, done, e := updateOfferStatus(st, 10)
	if done || e != nil {
		t.Fatal("unverified launch reported up to date", done, e)
	}
	st.StartupVerified = true
	if needsStartupRecovery(st) {
		t.Fatal("healthy ordinary launch requires recovery")
	}
}
