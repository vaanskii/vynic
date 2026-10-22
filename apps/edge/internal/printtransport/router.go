package printtransport

import (
	"context"
	"errors"
	"fmt"
	"net"
	"time"
)

type Config struct {
	WorkerHostID  string
	TCPTimeout    time.Duration
	HelperTimeout time.Duration
	Helper        *HelperConfig
	DialContext   func(context.Context, string, string) (net.Conn, error)
}

type Router struct{ config Config }

func New(config Config) (*Router, error) {
	if !ValidIdentity(config.WorkerHostID) {
		return nil, errors.New("worker host identity is required")
	}
	if config.TCPTimeout == 0 {
		config.TCPTimeout = 15 * time.Second
	}
	if config.HelperTimeout == 0 {
		config.HelperTimeout = 30 * time.Second
	}
	if config.TCPTimeout < time.Millisecond || config.TCPTimeout > 30*time.Second || config.HelperTimeout < time.Millisecond || config.HelperTimeout > 30*time.Second {
		return nil, errors.New("transport timeout exceeds bounds")
	}
	if config.Helper != nil {
		copy := *config.Helper
		if err := copy.validate(); err != nil {
			return nil, err
		}
		config.Helper = &copy
	}
	if config.DialContext == nil {
		config.DialContext = (&net.Dialer{}).DialContext
	}
	return &Router{config: config}, nil
}

func (*Router) Physical() bool { return true }

func (r *Router) Send(ctx context.Context, destination Destination, payload []byte) (result Result) {
	if err := ValidateDestination(destination); err != nil {
		return refused("validate", err)
	}
	if destination.WorkerHostID != r.config.WorkerHostID {
		return refused("owner", errors.New("frozen worker host does not own this transport"))
	}
	if len(payload) == 0 || len(payload) > MaxTransmissionBytes {
		return refused("validate", errors.New("payload is empty or exceeds bounds"))
	}
	if err := ctx.Err(); err != nil {
		return refused("admission", err)
	}
	if destination.Transport == WindowsSpooler {
		if !nativeSupported() {
			return refused("platform", errors.New("Windows spooler helper requires Windows"))
		}
		if r.config.Helper == nil {
			return refused("config", errors.New("pinned Windows helper is not configured"))
		}
	}
	bytes := append([]byte(nil), payload...)
	guard, finish, err := retainGuard(ctx, destination.PhysicalPrinterID)
	if err != nil {
		return refused("guard", err)
	}
	defer func() {
		if err := finish(); err != nil {
			result.Detail = fmt.Sprintf("%s; printer guard cleanup: %v", result.Detail, err)
			result.Stage = "guardClose"
			if result.WriteAttempted {
				result.State = Uncertain
			}
		}
	}()
	if destination.Transport == TCP {
		return r.sendTCP(ctx, destination, bytes)
	}
	return r.sendNative(ctx, destination, bytes, guard.name)
}
