package printtransport

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"
	"testing"
	"time"
)

type fakeConnection struct {
	mu          sync.Mutex
	writes      int
	closed      int
	bytes       []byte
	deadlineErr error
	closeErr    error
	write       func([]byte) (int, error)
	deadline    func(time.Time)
}

func (c *fakeConnection) Read([]byte) (int, error) { return 0, io.EOF }
func (c *fakeConnection) Write(value []byte) (int, error) {
	c.mu.Lock()
	c.writes++
	c.bytes = append([]byte(nil), value...)
	c.mu.Unlock()
	if c.write != nil {
		return c.write(value)
	}
	return len(value), nil
}
func (c *fakeConnection) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.closed++
	return c.closeErr
}
func (c *fakeConnection) LocalAddr() net.Addr             { return nil }
func (c *fakeConnection) RemoteAddr() net.Addr            { return nil }
func (c *fakeConnection) SetDeadline(time.Time) error     { return nil }
func (c *fakeConnection) SetReadDeadline(time.Time) error { return nil }
func (c *fakeConnection) SetWriteDeadline(value time.Time) error {
	if c.deadline != nil {
		c.deadline(value)
	}
	return c.deadlineErr
}

func tcpDestination() Destination {
	return Destination{PhysicalPrinterID: "printer1", WorkerHostID: "host1", Transport: TCP, Host: "192.168.1.50", Port: 9100, DocumentName: "Test document"}
}
func windowsDestination() Destination {
	return Destination{PhysicalPrinterID: "printer1", WorkerHostID: "host1", Transport: WindowsSpooler, QueueName: "Printer", ExpectedDriverName: "Driver", ExpectedPortName: "Port", DocumentName: "Test document"}
}
func heldTestGuard(t *testing.T) (*physicalGuard, context.Context) {
	t.Helper()
	g := &physicalGuard{physicalID: "printer1", name: guardName("printer1"), release: func() error { return nil }}
	t.Cleanup(func() {
		if err := g.Close(); err != nil {
			t.Error(err)
		}
	})
	return g, g.Context(context.Background())
}
func routerFor(t *testing.T, dial func(context.Context, string, string) (net.Conn, error)) *Router {
	t.Helper()
	r, err := New(Config{WorkerHostID: "host1", DialContext: dial})
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestTCPFailureBoundariesAndOneWrite(t *testing.T) {
	for _, test := range []struct {
		name                                     string
		dialErr, deadlineErr, writeErr, closeErr error
		count                                    int
		state                                    State
		stage                                    string
		attempted                                bool
	}{
		{"dial", errors.New("refused"), nil, nil, nil, 0, NotSent, "dial", false},
		{"deadline", nil, errors.New("deadline failed"), nil, nil, 0, NotSent, "deadline", false},
		{"zero error", nil, nil, errors.New("lost connection"), nil, 0, Uncertain, "write", true},
		{"partial error", nil, nil, errors.New("lost connection"), nil, 1, Uncertain, "write", true},
		{"short write", nil, nil, nil, nil, 1, Uncertain, "write", true},
		{"close error", nil, nil, nil, errors.New("close failed"), 3, Uncertain, "close", true},
		{"accepted", nil, nil, nil, nil, 3, Submitted, "accepted", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, ctx := heldTestGuard(t)
			connection := &fakeConnection{deadlineErr: test.deadlineErr, closeErr: test.closeErr, write: func([]byte) (int, error) { return test.count, test.writeErr }}
			r := routerFor(t, func(_ context.Context, network, address string) (net.Conn, error) {
				if network != "tcp" || address != "192.168.1.50:9100" {
					t.Errorf("wrong endpoint %s %s", network, address)
				}
				if test.dialErr != nil {
					return nil, test.dialErr
				}
				return connection, nil
			})
			result := r.Send(ctx, tcpDestination(), []byte{27, 64, 10})
			if result.State != test.state || result.Stage != test.stage || result.WriteAttempted != test.attempted {
				t.Fatalf("unexpected %+v", result)
			}
			if connection.writes != map[bool]int{false: 0, true: 1}[test.attempted] {
				t.Fatalf("writes=%d", connection.writes)
			}
			if result.BytesWritten != uint32(test.count) {
				t.Fatalf("written=%d", result.BytesWritten)
			}
			if !r.Physical() {
				t.Fatal("production router must identify real I/O")
			}
		})
	}
}

func TestRejectBeforeDialAndFreezeBytes(t *testing.T) {
	for _, test := range []struct {
		name        string
		destination Destination
		payload     []byte
	}{
		{"empty", tcpDestination(), nil},
		{"large", tcpDestination(), make([]byte, MaxTransmissionBytes+1)},
		{"worker pin", func() Destination { d := tcpDestination(); d.WorkerHostID = "host2"; return d }(), []byte{1}},
		{"mixed transport", func() Destination { d := tcpDestination(); d.QueueName = "Printer"; return d }(), []byte{1}},
		{"DNS", func() Destination { d := tcpDestination(); d.Host = "printer.example"; return d }(), []byte{1}},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, ctx := heldTestGuard(t)
			calls := 0
			r := routerFor(t, func(context.Context, string, string) (net.Conn, error) {
				calls++
				return nil, errors.New("unexpected dial")
			})
			if got := r.Send(ctx, test.destination, test.payload); got.State != NotSent || got.WriteAttempted {
				t.Fatalf("%+v", got)
			}
			if calls != 0 {
				t.Fatal("invalid admission dialed")
			}
		})
	}
	t.Run("frozen after admission", func(t *testing.T) {
		_, ctx := heldTestGuard(t)
		entered, release := make(chan struct{}), make(chan struct{})
		connection := &fakeConnection{}
		r := routerFor(t, func(context.Context, string, string) (net.Conn, error) {
			close(entered)
			<-release
			return connection, nil
		})
		payload := []byte{27, 64, 10}
		done := make(chan Result, 1)
		go func() { done <- r.Send(ctx, tcpDestination(), payload) }()
		<-entered
		payload[0] = 0
		close(release)
		if result := <-done; result.State != Submitted {
			t.Fatalf("%+v", result)
		}
		if connection.bytes[0] != 27 {
			t.Fatal("caller mutation changed admitted bytes")
		}
	})
}

func TestCancelWriteRemainsUncertainAndGuardBusy(t *testing.T) {
	g, base := heldTestGuard(t)
	ctx, cancel := context.WithCancel(base)
	defer cancel()
	started, unblock := make(chan struct{}), make(chan struct{})
	var once sync.Once
	connection := &fakeConnection{write: func([]byte) (int, error) { close(started); <-unblock; return 1, context.DeadlineExceeded }, deadline: func(deadline time.Time) {
		if !deadline.After(time.Now()) {
			once.Do(func() { close(unblock) })
		}
	}}
	r := routerFor(t, func(context.Context, string, string) (net.Conn, error) { return connection, nil })
	done := make(chan Result, 1)
	go func() { done <- r.Send(ctx, tcpDestination(), []byte{1, 2, 3}) }()
	<-started
	if err := g.Close(); err == nil {
		t.Fatal("original write must retain its guard")
	}
	if result := r.Send(base, tcpDestination(), []byte{4}); result.State != NotSent || result.Stage != "guard" {
		t.Fatalf("concurrent call %+v", result)
	}
	cancel()
	if result := <-done; result.State != Uncertain || result.BytesWritten != 1 || !result.WriteAttempted {
		t.Fatalf("%+v", result)
	}
	if err := g.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestDestinationAndHelperPins(t *testing.T) {
	if err := ValidateDestination(windowsDestination()); err != nil {
		t.Fatal(err)
	}
	d := windowsDestination()
	d.ExpectedPortName = ""
	if ValidateDestination(d) == nil {
		t.Fatal("exact port is required")
	}
	d = windowsDestination()
	d.QueueName = "bad\x00name"
	if ValidateDestination(d) == nil {
		t.Fatal("NUL queue accepted")
	}
	for _, config := range []Config{{}, {WorkerHostID: "host1", TCPTimeout: time.Minute}, {WorkerHostID: "host1", Helper: &HelperConfig{Path: "relative.exe", ProtocolVersion: 1}}} {
		if _, err := New(config); err == nil {
			t.Fatal("invalid pin/config accepted")
		}
	}
}
