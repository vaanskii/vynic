//go:build windows

package main

import (
	"fmt"
	"io"

	"golang.org/x/sys/windows"
	"vynic.local/edge/internal/printerdaemon"
	"vynic.local/edge/internal/printhost"
)

func runWindowsService(daemon *printerdaemon.Daemon, principal printerdaemon.Principal, diagnostic io.Writer) error {
	if err := printerdaemon.ValidatePrincipal(principal, daemon.Pins()); err != nil {
		return err
	}
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return err
	}
	if user.User.Sid.String() != principal.SID {
		return fmt.Errorf("printer-agent SCM principal mismatch; selected account was not used")
	}
	return printhost.RunWindowsService(daemon.Host(), func(err error) { fmt.Fprintln(diagnostic, err) })
}
