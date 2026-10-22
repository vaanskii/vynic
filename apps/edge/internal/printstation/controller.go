package printstation

import (
	"context"
	"fmt"
	"time"

	"vynic.local/edge/internal/printtransport"
)

type Work struct {
	Record  Record
	Printer PhysicalPrinter
}

// ControllerQueue must return only committed state and persist Begin before it
// returns. Implementations bind the controller's verified identity out of band.
type ControllerQueue interface {
	Load(context.Context, string) (Work, error)
	Begin(context.Context, string, string, int64) (Attempt, error)
	Finish(context.Context, string, string, int64, printtransport.Result) error
}
type ProofController struct {
	queue  ControllerQueue
	sender printtransport.Sender
}

// NewProofController cannot attach hardware. Production attachment additionally
// needs fixed-owner enrollment, retained local dispatch receipts and host drain.
func NewProofController(queue ControllerQueue, sender printtransport.Sender) (*ProofController, error) {
	if queue == nil || sender == nil || sender.Physical() {
		return nil, ErrHeld
	}
	return &ProofController{queue, sender}, nil
}

// Run owns one synchronous attempt. A missing commit response causes no Send;
// a missing completion response leaves the durable attempt unresolved. It never
// retries an attempt or derives a new ID. Call again with a fresh attempt only
// if the station state committed definitive NOT_SUBMITTED for the previous one.
func (c *ProofController) Run(jobID, attemptID string) error {
	ctx := context.Background()
	work, e := c.queue.Load(ctx, jobID)
	if e != nil {
		return e
	}
	x, e := c.queue.Begin(ctx, jobID, attemptID, time.Now().UnixMilli())
	if e != nil {
		return e
	}
	if x.Outcome == NotSubmitted {
		return nil
	}
	if x.Outcome != "" || x.PrinterID != work.Printer.ID || x.ControllerID != work.Printer.ControllerID {
		return ErrHeld
	}
	result := c.send(ctx, work.Printer.Destination, work.Record.Job.Payload)
	return c.queue.Finish(ctx, jobID, attemptID, time.Now().UnixMilli(), result)
}
func (c *ProofController) send(ctx context.Context, d printtransport.Destination, payload []byte) (r printtransport.Result) {
	defer func() {
		if v := recover(); v != nil {
			r = printtransport.Result{State: printtransport.Uncertain, Stage: "sender panic", Detail: fmt.Sprint(v), WriteAttempted: true}
		}
	}()
	return c.sender.Send(ctx, d, append([]byte(nil), payload...))
}
func (s *State) Work(jobID string) (Work, error) {
	r, ok := s.Jobs[jobID]
	if !ok {
		return Work{}, ErrNoWork
	}
	p, e := s.route(r)
	if e != nil {
		return Work{}, e
	}
	return Work{Record: *clone(r), Printer: clone(p)}, nil
}
