package printtransport

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"sync"
)

const nativeGuardPrefix = `Global\VynicPrint-`

type guardContextKey struct{}

type physicalGuard struct {
	mu         sync.Mutex
	physicalID string
	name       string
	closed     bool
	active     int
	release    func() error
}

func guardName(physicalID string) string {
	sum := sha256.Sum256([]byte(physicalID))
	return fmt.Sprintf("%s%x", nativeGuardPrefix, sum)
}

// AcquirePrinterGuard is nonblocking. A failed acquisition closes its OS
// handle immediately: a replacement must not keep an orphan semaphore alive.
// This host barrier never authorizes replay of a durable STARTED attempt.
func AcquirePrinterGuard(physicalID string) (PrinterGuard, error) {
	if !ValidIdentity(physicalID) {
		return nil, errors.New("invalid physical printer identity")
	}
	name := guardName(physicalID)
	release, err := acquireOSGuard(name)
	if err != nil {
		return nil, err
	}
	return &physicalGuard{physicalID: physicalID, name: name, release: release}, nil
}

func (g *physicalGuard) Context(ctx context.Context) context.Context {
	return context.WithValue(ctx, guardContextKey{}, g)
}

func (g *physicalGuard) Close() error {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.closed {
		return nil
	}
	if g.active != 0 {
		return errors.New("printer guard still owns an original transport call")
	}
	g.closed = true
	return g.release()
}

func (g *physicalGuard) retain(physicalID string) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.closed || g.physicalID != physicalID {
		return errors.New("printer guard is closed or belongs to another printer")
	}
	if g.active != 0 {
		return errors.New("printer guard already owns a transport call")
	}
	g.active++
	return nil
}

func retainGuard(ctx context.Context, physicalID string) (*physicalGuard, func() error, error) {
	g, supplied := ctx.Value(guardContextKey{}).(*physicalGuard)
	if !supplied {
		guard, err := AcquirePrinterGuard(physicalID)
		if err != nil {
			return nil, nil, err
		}
		g = guard.(*physicalGuard)
	}
	if err := g.retain(physicalID); err != nil {
		if !supplied {
			_ = g.Close()
		}
		return nil, nil, err
	}
	finish := func() error {
		g.mu.Lock()
		g.active--
		g.mu.Unlock()
		if supplied {
			return nil
		}
		return g.Close()
	}
	return g, finish, nil
}
