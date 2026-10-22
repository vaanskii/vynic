// Package printeligibility separates a quorum-backed logical assignment from
// permission to touch a shared physical printer. This is an isolated lease
// qualification seam, not a production authorization or fencing mechanism.
package printeligibility

import (
	"errors"
	"math"
	"regexp"
	"sync"
	"time"

	"vynic.local/edge/internal/printqueue"
)

var (
	ErrEvidence             = errors.New("invalid or stale logical printer evidence")
	ErrLease                = errors.New("logical printer lease unavailable")
	ErrPhysicalFencePending = errors.New("shared physical dispatch requires a qualified downstream fence")
)

// Assignment is an immutable committed claim. The elected executor is separate
// from job identity/configuration, so elections cannot retarget frozen bytes.
type Assignment struct {
	ClusterID, PhysicalPrinterID, JobID, AttemptID, ExecutorID string
	PayloadSHA256, JobSHA256, ConfigSHA256                     string
	Term, CommitIndex, MembershipGeneration, BindingGeneration uint64
}

func (a Assignment) valid() bool {
	for _, id := range []string{a.ClusterID, a.PhysicalPrinterID, a.JobID, a.AttemptID, a.ExecutorID} {
		if !printqueue.CanonicalUUID(id) {
			return false
		}
	}
	hash := regexp.MustCompile(`^[0-9a-f]{64}$`)
	return hash.MatchString(a.PayloadSHA256) && hash.MatchString(a.JobSHA256) && hash.MatchString(a.ConfigSHA256) &&
		a.Term > 0 && a.Term <= math.MaxInt64 && a.CommitIndex > 0 && a.CommitIndex <= math.MaxInt64 &&
		a.MembershipGeneration > 0 && a.MembershipGeneration <= math.MaxInt64 &&
		a.BindingGeneration > 0 && a.BindingGeneration <= math.MaxInt64
}

// Evidence is supplied only by the isolated consensus test adapter. It is not
// accepted from a Flutter request, deserialized lease or printer configuration.
// A production adapter would need authenticated current quorum evidence.
type Evidence struct {
	Assignment        Assignment
	BootID            string
	MajorityConfirmed bool
}

type lease struct {
	assignment                  Assignment
	granted, notBefore, expires time.Duration
}

// ProofGate keeps lease timing process-local and monotonic. No expiry is
// serializable/restorable. A new service process must obtain fresh evidence.
// Even a valid logical lease NEVER produces a physical permit in this package.
type ProofGate struct {
	mu                                               sync.Mutex
	bootID                                           string
	clock                                            func() time.Duration
	last                                             time.Duration
	broken                                           bool
	current                                          *lease
	highTerm, highIndex, highMembership, highBinding uint64
	lastAssignment                                   Assignment
	jobs                                             map[string]Assignment
}

func NewProofGate(bootID string, clock func() time.Duration) (*ProofGate, error) {
	if !printqueue.CanonicalUUID(bootID) {
		return nil, ErrEvidence
	}
	if clock == nil {
		start := time.Now()
		clock = func() time.Duration { return time.Since(start) }
	}
	return &ProofGate{bootID: bootID, clock: clock, jobs: make(map[string]Assignment)}, nil
}

func (g *ProofGate) now() (time.Duration, error) {
	now := g.clock()
	if g.broken || now < 0 || now < g.last {
		g.broken = true
		g.current = nil
		return 0, ErrEvidence
	}
	g.last = now
	return now, nil
}

// Refresh models quorum renewal and a previous-lease safety interval. These
// timing assumptions do not exclude an arbitrary pause after CheckLogical.
func (g *ProofGate) Refresh(e Evidence, lifetime, previousSafetyHold time.Duration) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	now, err := g.now()
	if err != nil {
		return err
	}
	if !e.MajorityConfirmed || e.BootID != g.bootID || !e.Assignment.valid() ||
		lifetime <= 0 || previousSafetyHold < 0 || previousSafetyHold >= lifetime ||
		now > time.Duration(1<<63-1)-lifetime {
		g.current = nil
		return ErrEvidence
	}
	if old := g.current; old != nil {
		if e.Assignment.ClusterID != old.assignment.ClusterID ||
			e.Assignment.PhysicalPrinterID != old.assignment.PhysicalPrinterID ||
			e.Assignment.ExecutorID != old.assignment.ExecutorID {
			g.current = nil
			return ErrEvidence
		}
	}
	// Losing quorum/expiry must not erase the observed generation high-water.
	// A later certificate or apparently fresh clock cannot revive stale claims.
	a := e.Assignment
	if g.highIndex != 0 && (a.ClusterID != g.lastAssignment.ClusterID ||
		a.PhysicalPrinterID != g.lastAssignment.PhysicalPrinterID ||
		a.ExecutorID != g.lastAssignment.ExecutorID || a.Term < g.highTerm ||
		a.CommitIndex < g.highIndex || a.MembershipGeneration < g.highMembership ||
		a.BindingGeneration < g.highBinding ||
		a.CommitIndex == g.highIndex && a != g.lastAssignment) {
		g.current = nil
		return ErrEvidence
	}
	if prior, ok := g.jobs[a.JobID]; ok {
		if prior.AttemptID != a.AttemptID || prior.PayloadSHA256 != a.PayloadSHA256 ||
			prior.JobSHA256 != a.JobSHA256 || prior.ConfigSHA256 != a.ConfigSHA256 ||
			prior.BindingGeneration != a.BindingGeneration {
			g.current = nil
			return ErrEvidence
		}
	} else if len(g.jobs) >= 4096 {
		// Bounded qualification memory. There is no silent eviction that could
		// make retained job identity appear fresh. A production FSM owns history.
		g.current = nil
		return ErrEvidence
	}
	g.jobs[a.JobID] = a
	g.highTerm, g.highIndex, g.highMembership, g.highBinding = a.Term, a.CommitIndex, a.MembershipGeneration, a.BindingGeneration
	g.lastAssignment = a
	g.current = &lease{assignment: e.Assignment, granted: now,
		notBefore: now + previousSafetyHold, expires: now + lifetime}
	return nil
}

func (g *ProofGate) LoseQuorum() {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.current = nil
}

func (g *ProofGate) CheckLogical(a Assignment) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	now, err := g.now()
	if err != nil {
		return err
	}
	l := g.current
	if l == nil || !a.valid() || l.assignment != a || now < l.granted || now < l.notBefore || now >= l.expires {
		return ErrLease
	}
	return nil
}

// CheckPhysical deliberately fails closed. A downstream contract must reject
// stale tokens at atomic job admission AND fence previously admitted workers.
// Generic RAW, an early epoch check and elapsed lease time supply no such fence.
func (g *ProofGate) CheckPhysical(a Assignment) error {
	if err := g.CheckLogical(a); err != nil {
		return err
	}
	return ErrPhysicalFencePending
}
