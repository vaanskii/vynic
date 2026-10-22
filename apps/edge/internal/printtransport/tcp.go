package printtransport

import (
	"context"
	"errors"
	"io"
	"net"
	"strconv"
	"time"
)

func (r *Router) sendTCP(parent context.Context, destination Destination, payload []byte) Result {
	ctx, cancel := context.WithTimeout(parent, r.config.TCPTimeout)
	defer cancel()
	connection, err := r.config.DialContext(ctx, "tcp", net.JoinHostPort(destination.Host, strconv.Itoa(int(destination.Port))))
	if err != nil {
		if connection != nil {
			err = errors.Join(err, connection.Close())
		}
		return refused("dial", err)
	}
	if connection == nil {
		return refused("dial", errors.New("dial returned no connection"))
	}
	closed := false
	defer func() {
		if !closed {
			_ = connection.Close()
		}
	}()
	if err = ctx.Err(); err != nil {
		return refused("admission", err)
	}
	deadline, _ := ctx.Deadline()
	if err = connection.SetWriteDeadline(deadline); err != nil {
		return refused("deadline", err)
	}
	stop := context.AfterFunc(ctx, func() { _ = connection.SetWriteDeadline(time.Now()) })
	defer stop()
	if err = ctx.Err(); err != nil {
		return refused("admission", err)
	}
	// One Write, no automatic retry, including a zero-byte write failure.
	count, writeErr := connection.Write(payload)
	result := Result{State: Uncertain, Stage: "write", WriteAttempted: true}
	if count >= 0 && count <= len(payload) {
		result.BytesWritten = uint32(count)
	}
	if writeErr != nil {
		result.Detail = writeErr.Error()
		return result
	}
	if count != len(payload) {
		result.Detail = io.ErrShortWrite.Error()
		return result
	}
	closed = true
	if err = connection.Close(); err != nil {
		result.Stage = "close"
		result.Detail = err.Error()
		return result
	}
	result.State = Submitted
	result.Stage = "accepted"
	result.Detail = "TCP accepted the complete payload; paper delivery is unconfirmed"
	return result
}
