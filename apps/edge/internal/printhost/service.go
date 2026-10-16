package printhost

import (
	"context"
	"errors"
	"time"
)

type ServiceCommand uint8

const (
	ServiceInterrogate ServiceCommand = iota + 1
	ServiceStop
	ServiceShutdown
)

type ServiceState uint8

const (
	ServiceStartPending ServiceState = iota + 1
	ServiceRunning
	ServiceStopPending
	ServiceStopped
)

type ServiceStatus struct {
	State      ServiceState
	Checkpoint uint32
}

func ServiceName(hostID string) string { return "VynicPrinterHost-" + hostID }

// ControlService is the portable control loop behind the Windows adapter. Only
// lifecycle events are accepted: there is no install/start-other-service API.
// StopPending continues through caller deadlines and failed resource closure;
// voluntary exit waits original ownership. Forced OS shutdown/process kill is
// outside this loop and still requires durable recovery and hardware fencing.
func ControlService(host *Host, commands <-chan ServiceCommand, report func(ServiceStatus), diagnostic func(error), interval time.Duration) error {
	if host == nil || report == nil || diagnostic == nil || interval < time.Millisecond || interval > time.Second {
		return ErrUnavailable
	}
	status := ServiceStatus{State: ServiceStartPending, Checkpoint: 1}
	report(status)
	started := make(chan error, 1)
	go func() { started <- host.Start(context.Background()) }()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	var startupErr error
	var stopped <-chan struct{}
	var hostStopping <-chan struct{} = host.stopStarted
	stopping := false
	stop := func() {
		if stopping {
			return
		}
		stopping = true
		host.beginStop()
		hostStopping = nil
		stopped = host.stopDone
		status = ServiceStatus{State: ServiceStopPending, Checkpoint: 1}
		report(status)
	}
	for {
		select {
		case err := <-started:
			started = nil
			startupErr = err
			if err != nil {
				diagnostic(err)
				stop()
			} else if stopped == nil {
				select {
				case <-host.stopStarted:
					stop()
				default:
					status = ServiceStatus{State: ServiceRunning}
					report(status)
				}
			}
		case <-hostStopping:
			// Trusted runtime evidence can stop the host independently of SCM.
			// Observe that same retained drain instead of reporting Running.
			stop()
		case command, ok := <-commands:
			if !ok {
				commands = nil
				stop()
				continue
			}
			switch command {
			case ServiceStop, ServiceShutdown:
				stop()
			case ServiceInterrogate:
				report(status)
			}
		case <-stopped:
			if started != nil {
				startupErr = <-started
				started = nil
				if startupErr != nil {
					diagnostic(startupErr)
				}
			}
			host.mu.Lock()
			err, held := host.stopErr, host.held
			host.mu.Unlock()
			failure := errors.Join(startupErr, held, err)
			if failure != nil {
				diagnostic(failure)
			}
			if err != nil {
				// A close failure does not release the host owner. Keep the
				// service visibly pending for explicit operator recovery.
				stopped = nil
				continue
			}
			report(ServiceStatus{State: ServiceStopped})
			return failure
		case <-ticker.C:
			if status.State == ServiceStartPending || status.State == ServiceStopPending {
				// This is a liveness report, not evidence of physical drain.
				report(status)
			}
		}
	}
}
