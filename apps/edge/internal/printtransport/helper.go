package printtransport

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"sync/atomic"
)

type HelperConfig struct {
	Path            string
	SHA256          string
	ProtocolVersion uint16
}

func (h HelperConfig) validate() error {
	if !filepath.IsAbs(h.Path) || h.ProtocolVersion != HelperProtocolVersion || len(h.SHA256) != 64 {
		return errors.New("helper path, binary hash and exact protocol pin are required")
	}
	for _, c := range h.SHA256 {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return errors.New("helper SHA-256 must be lowercase hexadecimal")
		}
	}
	return nil
}

type helperProcess interface {
	Input() io.WriteCloser
	Output() io.ReadCloser
	Wait() error
	Terminate() error
	Close() error
}

type exchangeOutcome struct {
	result Result
	queues []QueueDescriptor
	err    error
}

func exchangeIO(process helperProcess, request []byte, expectedBytes int, submit bool, commitAttempted *atomic.Bool) exchangeOutcome {
	if err := writeFrame(process.Input(), request); err != nil {
		return exchangeOutcome{err: fmt.Errorf("helper request: %w", err)}
	}
	frame, err := readFrame(process.Output())
	if err != nil {
		return exchangeOutcome{err: fmt.Errorf("helper response: %w", err)}
	}
	if frame[6] == tagResult {
		if len(frame) >= 24 && (frame[9] == 1 || binary.LittleEndian.Uint32(frame[12:]) != 0 || binary.LittleEndian.Uint32(frame[16:]) != 0) {
			commitAttempted.Store(true)
		}
		result, err := decodeResult(frame, expectedBytes)
		if err == nil && result.State != NotSent {
			err = errors.New("helper claimed a write before COMMIT")
		}
		return exchangeOutcome{result: result, err: err}
	}
	if !submit {
		queues, err := decodeInventory(frame)
		return exchangeOutcome{queues: queues, err: err}
	}
	if frame[6] != tagReady || len(frame) != 8 {
		return exchangeOutcome{err: errors.New("invalid helper READY response")}
	}
	// From this boundary any lost ACK/result is uncertain. A partial COMMIT does
	// not make the helper print, but the parent must not infer delivery absence.
	commitAttempted.Store(true)
	if err = writeFrame(process.Input(), header(tagCommit)); err != nil {
		return exchangeOutcome{err: fmt.Errorf("helper COMMIT: %w", err)}
	}
	frame, err = readFrame(process.Output())
	if err != nil {
		return exchangeOutcome{err: fmt.Errorf("helper result: %w", err)}
	}
	result, err := decodeResult(frame, expectedBytes)
	return exchangeOutcome{result: result, err: err}
}

// A pipe timeout cannot release ownership while the original process lives.
// Terminate/wait cleanup keeps both the parent guard and executable pin alive
// until the exact child has terminated; a failed kill never creates takeover.
func exchangeProcess(ctx context.Context, process helperProcess, request []byte, expectedBytes int, submit bool) (outcome exchangeOutcome) {
	if err := ctx.Err(); err != nil {
		killErr := process.Terminate()
		_ = process.Input().Close()
		_ = process.Output().Close()
		waitErr := process.Wait()
		closeErr := process.Close()
		outcome.err = errors.Join(err, killErr, waitErr, closeErr)
		outcome.result = refused("admission", outcome.err)
		return outcome
	}
	var committed atomic.Bool
	done := make(chan exchangeOutcome, 1)
	waited := make(chan error, 1)
	exchangeSettled := false
	go func() { done <- exchangeIO(process, request, expectedBytes, submit, &committed) }()
	go func() { waited <- process.Wait() }()
	var waitErr, errorCause error
	select {
	case outcome = <-done:
		exchangeSettled = true
		errorCause = outcome.err
		if errorCause != nil {
			errorCause = errors.Join(errorCause, process.Terminate())
		}
	case <-ctx.Done():
		errorCause = errors.Join(ctx.Err(), process.Terminate())
	}
	_ = process.Input().Close()
	if errorCause != nil {
		_ = process.Output().Close()
	}
	select {
	case waitErr = <-waited:
	case <-ctx.Done():
		errorCause = errors.Join(errorCause, ctx.Err(), process.Terminate())
		_ = process.Output().Close()
		waitErr = <-waited // Retain the original lifetime even if termination fails.
	}
	// Ensure the exchange goroutine has also settled before releasing its pipes.
	if !exchangeSettled {
		_ = process.Output().Close()
		<-done
	}
	closeErr := process.Close()
	if errorCause != nil || waitErr != nil || closeErr != nil {
		err := errors.Join(errorCause, waitErr, closeErr)
		outcome.err = err
		outcome.result = refused("helper", err)
		if committed.Load() {
			outcome.result.State = Uncertain
			outcome.result.WriteAttempted = true
		}
	}
	return outcome
}

func (r *Router) sendNative(parent context.Context, d Destination, payload []byte, guard string) Result {
	if !nativeSupported() {
		return refused("platform", errors.New("Windows spooler helper requires Windows"))
	}
	if r.config.Helper == nil {
		return refused("config", errors.New("pinned Windows helper is not configured"))
	}
	ctx, cancel := context.WithTimeout(parent, r.config.HelperTimeout)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return refused("admission", err)
	}
	process, err := launchHelper(*r.config.Helper)
	if err != nil {
		return refused("launch", err)
	}
	outcome := exchangeProcess(ctx, process, submissionFrame(d, payload, guard), len(payload), true)
	return outcome.result
}

// ListQueues is read-only, running in the same account as the owning Go host.
// Inventory does not establish RAW/profile compatibility or physical delivery.
func (r *Router) ListQueues(parent context.Context) ([]QueueDescriptor, error) {
	if !nativeSupported() {
		return nil, errors.New("Windows spooler helper requires Windows")
	}
	if r.config.Helper == nil {
		return nil, errors.New("pinned Windows helper is not configured")
	}
	ctx, cancel := context.WithTimeout(parent, r.config.HelperTimeout)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	process, err := launchHelper(*r.config.Helper)
	if err != nil {
		return nil, err
	}
	outcome := exchangeProcess(ctx, process, header(tagInventory), 0, false)
	if outcome.err != nil {
		return nil, outcome.err
	}
	if outcome.result.State != "" {
		return nil, fmt.Errorf("%s: %s", outcome.result.Stage, strings.TrimSpace(outcome.result.Detail))
	}
	return outcome.queues, nil
}
