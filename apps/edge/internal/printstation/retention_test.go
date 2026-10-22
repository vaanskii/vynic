package printstation

import (
	"testing"
	"vynic.local/edge/internal/printtransport"
)

func TestRetentionKeepsUnresolvedAndReprintDependencies(t *testing.T) {
	s, c, a, j := admitted(t)
	if _, e := s.Begin(a, j.ID, uid(400), 2); e != nil {
		t.Fatal(e)
	}
	if e := s.Finish(a, j.ID, uid(400), 3, printtransport.Result{State: printtransport.Submitted, WriteAttempted: true, BytesWritten: uint32(len(j.Payload))}); e != nil {
		t.Fatal(e)
	}
	copy := j
	copy.ID = uid(401)
	copy.CreatedAt = 4
	copy.Reprint = &Reprint{OriginalID: j.ID, ActorID: uid(500), Reason: "copy requested", At: 4}
	if _, e := s.Admit(a, copy, 2); e != nil {
		t.Fatal(e)
	}
	removed, e := s.Compact(a, DiagnosticRetentionMillis+100)
	if e != nil || len(removed) != 0 {
		t.Fatalf("pruned original pinned by queued copy: %v %v", removed, e)
	}
	if _, e = s.Begin(a, copy.ID, uid(402), 101); e != nil {
		t.Fatal(e)
	}
	if e = s.Finish(a, copy.ID, uid(402), 102, printtransport.Result{State: printtransport.Uncertain, WriteAttempted: true}); e != nil {
		t.Fatal(e)
	}
	removed, e = s.Compact(a, DiagnosticRetentionMillis+200)
	if e != nil || len(removed) != 0 {
		t.Fatal("uncertain reprint pruned", e)
	}
	if e = s.ReconcileProof(a, copy.ID, uid(500), "synthetic settled transport", 201); e != nil {
		t.Fatal(e)
	}
	removed, e = s.Compact(a, DiagnosticRetentionMillis+300)
	if e != nil || len(removed) != 2 {
		t.Fatalf("terminal chain retained beyond retention: %v %v", removed, e)
	}
	if _, e = s.Admit(a, j, 3); e == nil {
		t.Fatal("expired exact retry admitted as new job")
	}
	fresh := job(c, uid(50), 2)
	fresh.CreatedAt = 301
	r, e := s.Admit(a, fresh, 3)
	if e != nil || r.Sequence != 3 {
		t.Fatal("sequence reset after retention", e)
	}
	valid(t, s)
}
