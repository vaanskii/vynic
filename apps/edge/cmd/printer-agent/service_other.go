//go:build !windows

package main

import (
	"errors"
	"io"

	"vynic.local/edge/internal/printerdaemon"
)

func runWindowsService(*printerdaemon.Daemon, printerdaemon.Principal, io.Writer) error {
	return errors.New("printer-agent service entry requires Windows; use foreground")
}
