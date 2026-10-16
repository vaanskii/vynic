package printerprovisioning

import (
	"context"
	"errors"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"vynic.local/edge/internal/printhost"
	"vynic.local/edge/internal/store"
)

func pins(f *fixture) printhost.Pins {
	j := f.job
	p := printhost.Pins{Scope: printhost.Scope(f.state.Scope), OwnershipPolicy: printhost.LocalHost, Role: printhost.POSAgent, VenueID: j.VenueID, InstallationID: j.InstallationID, DeviceID: j.DeviceID, HostID: j.Destination.WorkerHostID, GatewayHostID: j.Destination.WorkerHostID, AuthorityEpoch: j.AuthorityEpoch, ProtocolVersion: 1, HelperProtocolVersion: 1, DatabaseSchemaVersion: store.SchemaVersion, MinimumReaderVersion: printhost.ReaderVersion, RouteRevision: j.RouteRevision, ConfigRevision: j.ConfigRevision, RegistryRevision: j.RegistryRevision, BindingRevision: j.BindingRevision, CapabilityRevision: 1, CapabilityProfileSHA256: SHA256(j.CapabilityProfile), HostBinarySHA256: strings.Repeat("b", 64), HelperBinarySHA256: strings.Repeat("c", 64)}
	if f.state.Scope == VenueShared {
		p.OwnershipPolicy = printhost.ClusterLogicalOnly
		p.GatewayHostID = ""
		p.ClusterID = f.state.ClusterID
		p.MembershipSHA256 = f.state.MembershipSHA256
	}
	return p
}

func TestOptionalServerAdapterReadsCurrentStateEveryAttempt(t *testing.T) {
	f := fresh(t, "tcp", Local)
	reads := 0
	v, e := NewValidator(f.grant, func(context.Context) (TrustedState, error) { reads++; return f.state, nil })
	if e != nil {
		t.Fatal(e)
	}
	if reads != 0 {
		t.Fatal("constructor read current state")
	}
	p := pins(f)
	if e = v.Validate(context.Background(), f.peer, p, f.job); e != nil {
		t.Fatal(e)
	}
	f.state.RevokedThroughGeneration = f.state.HighWaterGeneration
	if e = v.Validate(context.Background(), f.peer, p, f.job); !errors.Is(e, ErrRevoked) {
		t.Fatal("cached validation ignored revocation", e)
	}
	f.state.RevokedThroughGeneration = 0
	f.state.HighWaterGeneration++
	f.state.Authorization.Generation++
	if e = v.Validate(context.Background(), f.peer, p, f.job); !errors.Is(e, ErrStale) {
		t.Fatal("cached validation ignored new generation", e)
	}
	if reads != 3 {
		t.Fatal("fresh state not read on every call", reads)
	}
}

func TestAdapterConstructorFreezeAndFailurePropagation(t *testing.T) {
	f := fresh(t, "tcp", Local)
	if _, e := NewValidator(f.grant, nil); !errors.Is(e, ErrState) {
		t.Fatal(e)
	}
	if _, e := NewValidator([]byte(`{}`), func(context.Context) (TrustedState, error) {
		t.Fatal("constructor queried state")
		return TrustedState{}, nil
	}); !errors.Is(e, ErrInvalid) {
		t.Fatal(e)
	}
	reads := 0
	v, e := NewValidator(f.grant, func(context.Context) (TrustedState, error) { reads++; return f.state, nil })
	if e != nil {
		t.Fatal(e)
	}
	f.grant[0] ^= 1
	if e = v.Validate(context.Background(), f.peer, pins(f), f.job); e != nil {
		t.Fatal("constructor retained caller's grant buffer", e)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if e = v.Validate(ctx, f.peer, pins(f), f.job); !errors.Is(e, context.Canceled) || reads != 1 {
		t.Fatal("canceled call read state", e, reads)
	}
	boom := errors.New("durable high-water store unavailable")
	v, e = NewValidator(f.signRaw(t, encode(t, f.body)), func(context.Context) (TrustedState, error) { return TrustedState{}, boom })
	if e != nil {
		t.Fatal(e)
	}
	if e = v.Validate(context.Background(), f.peer, pins(f), f.job); !errors.Is(e, ErrState) || !errors.Is(e, boom) {
		t.Fatal("storage failure hidden", e)
	}
	var nilValidator *Validator
	if e = nilValidator.Validate(context.Background(), f.peer, pins(f), f.job); !errors.Is(e, ErrState) {
		t.Fatal(e)
	}
}

func TestAdapterRejectsChangedPinsAndExportedJobMutation(t *testing.T) {
	for _, field := range []string{"scope", "cluster", "profile", "host", "revision"} {
		t.Run(field, func(t *testing.T) {
			f := fresh(t, "tcp", Local)
			v, e := NewValidator(f.grant, func(context.Context) (TrustedState, error) { return f.state, nil })
			if e != nil {
				t.Fatal(e)
			}
			p := pins(f)
			switch field {
			case "scope":
				p.Scope = printhost.VenueShared
			case "cluster":
				p.ClusterID = uuid(14)
			case "profile":
				p.CapabilityProfileSHA256 = strings.Repeat("a", 64)
			case "host":
				p.HostID = uuid(11)
			case "revision":
				p.RouteRevision++
			}
			if e = v.Validate(context.Background(), f.peer, p, f.job); !errors.Is(e, ErrBinding) {
				t.Fatal(e)
			}
		})
	}
	f := fresh(t, "tcp", Local)
	v, e := NewValidator(f.grant, func(context.Context) (TrustedState, error) { return f.state, nil })
	if e != nil {
		t.Fatal(e)
	}
	p := pins(f)
	f.job.PrimaryBytes[0] ^= 1
	if e = v.Validate(context.Background(), f.peer, p, f.job); !errors.Is(e, ErrInvalid) {
		t.Fatal("mutated exported job used retained raw", e)
	}
}

func TestConcurrentValidationRetainsImmutableGrantAndJob(t *testing.T) {
	f := fresh(t, "tcp", VenueShared)
	var reads atomic.Int32
	v, e := NewValidator(f.grant, func(context.Context) (TrustedState, error) { reads.Add(1); return f.state, nil })
	if e != nil {
		t.Fatal(e)
	}
	p := pins(f)
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if e := v.Validate(context.Background(), f.peer, p, f.job); e != nil {
				t.Error(e)
			}
		}()
	}
	wg.Wait()
	if reads.Load() != 16 {
		t.Fatal("read count", reads.Load())
	}
}
