//go:build windows

package printhost

import (
	"errors"
	"time"

	"golang.org/x/sys/windows/svc"
)

// RunWindowsService joins only the current SCM-launched process. It registers
// no persistent service, starts no second writer, and changes no account/ACL.
// This source adapter has no executable entrypoint in the current installer.
func RunWindowsService(host *Host, diagnostic func(error)) error {
	if host == nil || diagnostic == nil {
		return ErrUnavailable
	}
	service, err := svc.IsWindowsService()
	if err != nil {
		return err
	}
	if !service {
		return errors.New("printer service adapter requires an SCM-launched process")
	}
	return svc.Run(ServiceName(host.pins.HostID), &windowsHandler{host: host, diagnostic: diagnostic})
}

type windowsHandler struct {
	host       *Host
	diagnostic func(error)
}

func (h *windowsHandler) Execute(args []string, requests <-chan svc.ChangeRequest, statuses chan<- svc.Status) (bool, uint32) {
	if len(args) != 1 || args[0] != ServiceName(h.host.pins.HostID) {
		h.diagnostic(errors.New("unexpected printer service arguments"))
		return true, 1
	}
	commands := make(chan ServiceCommand)
	finished := make(chan struct{})
	defer close(finished)
	go func() {
		defer close(commands)
		for {
			select {
			case <-finished:
				return
			case request, ok := <-requests:
				if !ok {
					return
				}
				var command ServiceCommand
				switch request.Cmd {
				case svc.Stop:
					command = ServiceStop
				case svc.Shutdown, svc.PreShutdown:
					command = ServiceShutdown
				case svc.Interrogate:
					command = ServiceInterrogate
				default:
					continue
				}
				select {
				case commands <- command:
				case <-finished:
					return
				}
			}
		}
	}()
	report := func(status ServiceStatus) {
		out := svc.Status{CheckPoint: status.Checkpoint}
		switch status.State {
		case ServiceStartPending:
			out.State, out.WaitHint = svc.StartPending, 5000
		case ServiceRunning:
			out.State = svc.Running
			out.Accepts = svc.AcceptStop | svc.AcceptShutdown | svc.AcceptPreShutdown
		case ServiceStopPending:
			out.State, out.WaitHint = svc.StopPending, 5000
		case ServiceStopped:
			out.State = svc.Stopped
		}
		statuses <- out
	}
	if err := ControlService(h.host, commands, report, h.diagnostic, 250*time.Millisecond); err != nil {
		h.diagnostic(err)
		return true, 1
	}
	return false, 0
}
