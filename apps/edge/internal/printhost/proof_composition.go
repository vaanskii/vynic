package printhost

import (
	"context"
	"fmt"

	"vynic.local/edge/internal/printqueue"
)

var _ AdmissionFence = (*printqueue.Store)(nil)
var _ DrainWorker = (*printqueue.Scheduler)(nil)

// ComposeProofGateway wires the actual isolated queue lifecycle, not a physical
// deployment. NewProofScheduler has already rejected physical senders and owns
// recovery/exclusive proof-worker locking. The resource owner supplies Close;
// the probe must read trusted configuration/account/helper evidence separately.
func ComposeProofGateway(queue *printqueue.Store, scheduler *printqueue.Scheduler, physicalIDs []string, probe HealthProbe, closeResources func() error) (Components, error) {
	if queue == nil || scheduler == nil || probe == nil || closeResources == nil || len(physicalIDs) == 0 || len(physicalIDs) > 64 {
		return Components{}, ErrUnavailable
	}
	ids, seen := append([]string(nil), physicalIDs...), make(map[string]bool)
	for _, id := range ids {
		if !printqueue.CanonicalUUID(id) || seen[id] {
			return Components{}, fmt.Errorf("%w: invalid proof printer identities", ErrBindingMismatch)
		}
		seen[id] = true
	}
	return Components{Queue: queue, Worker: scheduler, Probe: probe, Start: func() error { return scheduler.Start(ids) }, Close: closeResources, HasPrinterWriter: true}, nil
}

// QueueProbe retains configured pins by value and reads actual durable holds.
// The composition must attest account/helper/configuration evidence before
// constructing it; this snapshot is not a signature or fleet activation check.
func QueueProbe(queue *printqueue.Store, pins Pins, physicalIDs []string) (HealthProbe, error) {
	if queue == nil || pins.Validate() != nil || len(physicalIDs) == 0 || len(physicalIDs) > 64 {
		return nil, ErrBindingMismatch
	}
	ids, seen := append([]string(nil), physicalIDs...), make(map[string]bool)
	for _, id := range ids {
		if !printqueue.CanonicalUUID(id) || seen[id] {
			return nil, ErrBindingMismatch
		}
		seen[id] = true
	}
	return ProbeFunc(func(ctx context.Context) (Evidence, error) {
		reason, err := queue.BlockedReason(ctx)
		evidence := Evidence{Pins: pins, RecoveryComplete: true, BlockedReason: reason}
		if err != nil {
			return evidence, err
		}
		for _, id := range ids {
			hold, err := queue.PrinterBlockedReason(ctx, id)
			if err != nil {
				return evidence, err
			}
			if hold != "" {
				evidence.PrinterHolds = append(evidence.PrinterHolds, PrinterHold{PhysicalPrinterID: id, Reason: hold})
			}
		}
		return evidence, nil
	}), nil
}
