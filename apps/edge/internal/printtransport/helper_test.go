package printtransport

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"sync/atomic"
	"testing"
	"time"
)

type fakeHelperProcess struct {
	input      *io.PipeWriter
	output     *io.PipeReader
	ended      chan struct{}
	waitGate   chan struct{}
	waited     atomic.Bool
	terminated atomic.Int32
	closed     atomic.Int32
}

func newFakeHelper(script func(io.Reader, io.Writer), holdWait bool) *fakeHelperProcess {
	childInput, input := io.Pipe()
	output, childOutput := io.Pipe()
	p := &fakeHelperProcess{input: input, output: output, ended: make(chan struct{})}
	if holdWait {
		p.waitGate = make(chan struct{})
	}
	go func() {
		defer close(p.ended)
		defer childInput.Close()
		defer childOutput.Close()
		script(childInput, childOutput)
	}()
	return p
}
func (p *fakeHelperProcess) Input() io.WriteCloser { return p.input }
func (p *fakeHelperProcess) Output() io.ReadCloser { return p.output }
func (p *fakeHelperProcess) Wait() error {
	<-p.ended
	if p.waitGate != nil {
		<-p.waitGate
	}
	p.waited.Store(true)
	return nil
}
func (p *fakeHelperProcess) Terminate() error { p.terminated.Add(1); return nil }
func (p *fakeHelperProcess) Close() error {
	if !p.waited.Load() {
		return errors.New("closed before exact child exit")
	}
	p.closed.Add(1)
	return nil
}

func resultFrame(state byte, attempted bool, count, job uint32, stage string) []byte {
	frame := header(tagResult)
	flag := byte(0)
	if attempted {
		flag = 1
	}
	frame = append(frame, state, flag, 0, 0)
	frame = binary.LittleEndian.AppendUint32(frame, count)
	frame = binary.LittleEndian.AppendUint32(frame, job)
	frame = binary.LittleEndian.AppendUint32(frame, 0)
	frame = appendText(frame, stage)
	return appendText(frame, "Synthetic result")
}

func TestHelperOutcomeAndNoCommitRetry(t *testing.T) {
	for _, test := range []struct {
		name      string
		ready     bool
		response  []byte
		state     State
		attempted bool
	}{
		{"prewrite refusal", false, resultFrame(0, false, 0, 0, "guard"), NotSent, false},
		{"accepted", true, resultFrame(1, true, 3, 77, "accepted"), Submitted, true},
		{"native prewrite", true, resultFrame(0, false, 0, 0, "selectQueue"), NotSent, false},
		{"partial uncertainty", true, resultFrame(2, true, 1, 77, "writePrinter"), Uncertain, true},
		{"ACK lost", true, nil, Uncertain, true},
		{"READY lost", false, nil, NotSent, false},
		{"contradictory early write", false, resultFrame(1, true, 3, 77, "accepted"), Uncertain, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			var commits atomic.Int32
			p := newFakeHelper(func(input io.Reader, output io.Writer) {
				if _, err := readFrame(input); err != nil {
					return
				}
				if test.ready {
					if writeFrame(output, header(tagReady)) != nil {
						return
					}
					frame, err := readFrame(input)
					if err != nil {
						return
					}
					if frame[6] != tagCommit || len(frame) != 8 {
						t.Error("invalid commit")
						return
					}
					commits.Add(1)
				}
				if test.response != nil {
					_ = writeFrame(output, test.response)
				}
			}, false)
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			outcome := exchangeProcess(ctx, p, submissionFrame(windowsDestination(), []byte{27, 64, 10}, guardName("printer1")), 3, true)
			if outcome.result.State != test.state || outcome.result.WriteAttempted != test.attempted {
				t.Fatalf("unexpected %+v error=%v", outcome.result, outcome.err)
			}
			wanted := int32(0)
			if test.ready {
				wanted = 1
			}
			if commits.Load() != wanted {
				t.Fatalf("COMMIT repeated %d", commits.Load())
			}
			if p.closed.Load() != 1 || !p.waited.Load() {
				t.Fatal("original child lifetime was not settled exactly once")
			}
		})
	}
}

func TestHelperTimeoutRetainsOriginalLifetimeAndGuard(t *testing.T) {
	committed := make(chan struct{})
	p := newFakeHelper(func(input io.Reader, output io.Writer) {
		_, _ = readFrame(input)
		_ = writeFrame(output, header(tagReady))
		_, _ = readFrame(input)
		close(committed)
		_, _ = io.Copy(io.Discard, input)
	}, true)
	g, base := heldTestGuard(t)
	if err := g.retain("printer1"); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(base)
	done := make(chan exchangeOutcome, 1)
	go func() {
		done <- exchangeProcess(ctx, p, submissionFrame(windowsDestination(), []byte{1, 2, 3}, g.name), 3, true)
	}()
	<-committed
	cancel()
	deadline := time.After(time.Second)
	for p.terminated.Load() == 0 {
		select {
		case <-deadline:
			t.Fatal("timeout did not request child termination")
		default:
			time.Sleep(time.Millisecond)
		}
	}
	if err := g.Close(); err == nil {
		t.Fatal("guard released while original child termination is pending")
	}
	select {
	case <-done:
		t.Fatal("timeout abandoned the original child")
	default:
	}
	close(p.waitGate)
	outcome := <-done
	if outcome.result.State != Uncertain || !outcome.result.WriteAttempted || !p.waited.Load() {
		t.Fatalf("%+v", outcome)
	}
	g.mu.Lock()
	g.active--
	g.mu.Unlock()
	if err := g.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestHelperFrameAndResultBounds(t *testing.T) {
	for _, frame := range [][]byte{{1, 2, 3}, binary.LittleEndian.AppendUint32(nil, maxFrameBytes+1), binary.LittleEndian.AppendUint32(nil, 7)} {
		if _, err := readFrame(bytes.NewReader(frame)); err == nil {
			t.Fatal("invalid frame accepted")
		}
	}
	version := header(tagReady)
	version[4] = 2
	var framed bytes.Buffer
	_ = writeFrame(&framed, version)
	if _, err := readFrame(&framed); err == nil {
		t.Fatal("different protocol pin accepted")
	}
	for _, frame := range [][]byte{
		append(resultFrame(1, true, 3, 77, "accepted"), 0),
		resultFrame(0, true, 0, 0, "validate"),
		resultFrame(1, true, 2, 77, "accepted"),
		resultFrame(2, false, 0, 0, "write"),
	} {
		if _, err := decodeResult(frame, 3); err == nil {
			t.Fatal("contradictory/extra result accepted")
		}
	}
	frame := header(tagInventoryResult)
	frame = binary.LittleEndian.AppendUint32(frame, 1025)
	if _, err := decodeInventory(frame); err == nil {
		t.Fatal("oversized inventory accepted")
	}
}

func TestGuardIdentityActiveCallAndIdempotentClose(t *testing.T) {
	var releases atomic.Int32
	g := &physicalGuard{physicalID: "printer1", name: guardName("printer1"), release: func() error { releases.Add(1); return nil }}
	if err := g.retain("printer2"); err == nil {
		t.Fatal("guard retargeted")
	}
	ctx := g.Context(context.Background())
	_, finish, err := retainGuard(ctx, "printer1")
	if err != nil {
		t.Fatal(err)
	}
	if err = g.Close(); err == nil {
		t.Fatal("active call released host barrier")
	}
	if _, _, err = retainGuard(ctx, "printer1"); err == nil {
		t.Fatal("concurrent call admitted")
	}
	if err = finish(); err != nil {
		t.Fatal(err)
	}
	if err = g.Close(); err != nil {
		t.Fatal(err)
	}
	if err = g.Close(); err != nil {
		t.Fatal(err)
	}
	if releases.Load() != 1 {
		t.Fatal("host barrier released twice")
	}
	if _, _, err = retainGuard(ctx, "printer1"); err == nil {
		t.Fatal("closed guard reused")
	}
}
