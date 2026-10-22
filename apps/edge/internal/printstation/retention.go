package printstation

// DiagnosticRetentionMillis retains completed jobs, exact receipts, payloads,
// attempts and reconciliations for 30 days after the final event. Unresolved
// jobs have no expiry. Reprints and their originals are retained together until
// every dependent copy is eligible. This is a bounded replay guarantee.
const DiagnosticRetentionMillis int64 = 30 * 24 * 60 * 60 * 1000

// Compact is replicated with an explicit timestamp from the trusted runtime.
// It never observes a replica's clock. The admission floor refuses old exact
// retries after pruning instead of silently creating a fresh queue entry.
func (s *State) Compact(a Authority, now int64) ([]string, error) {
	if !a.Admin || a.VenueID != s.VenueID {
		return nil, ErrScope
	}
	if now <= DiagnosticRetentionMillis || now-DiagnosticRetentionMillis < s.RetiredBefore {
		return nil, ErrInvalid
	}
	cutoff := now - DiagnosticRetentionMillis
	eligible := map[string]bool{}
	for id, r := range s.Jobs {
		if r.State != Submitted && r.State != Reconciled {
			continue
		}
		last := r.Job.CreatedAt
		for _, x := range r.Attempts {
			if x.FinishedAt > last {
				last = x.FinishedAt
			}
		}
		if r.Resolution != nil && r.Resolution.At > last {
			last = r.Resolution.At
		}
		if last <= cutoff {
			eligible[id] = true
		}
	}
	// Retained copies pin originals, including chains of manual reprints.
	for changed := true; changed; {
		changed = false
		for id, r := range s.Jobs {
			if r.Job.Reprint != nil && !eligible[id] && eligible[r.Job.Reprint.OriginalID] {
				delete(eligible, r.Job.Reprint.OriginalID)
				changed = true
			}
		}
	}
	removed := make([]string, 0, len(eligible))
	for id := range eligible {
		delete(s.Jobs, id)
		removed = append(removed, id)
	}
	s.RetiredBefore = cutoff
	return removed, nil
}
func (s *State) pending() int {
	count := 0
	for _, r := range s.Jobs {
		if r == nil || (r.State != Submitted && r.State != Reconciled) {
			count++
		}
	}
	return count
}
