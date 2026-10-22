// Package printtransport sends already rendered, immutable printer bytes.
// Durable attempts, reconciliation, profiles and optional signals belong to
// printqueue; transport acceptance never confirms paper delivery.
package printtransport

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

const MaxTransmissionBytes = 8*1024*1024 + 1024

type Kind string

const (
	TCP            Kind = "tcp"
	WindowsSpooler Kind = "windowsSpooler"
)

// Destination is a frozen routing identity, not a source of tenant authority.
// All fields are serialized, including irrelevant fields at their zero value.
type Destination struct {
	PhysicalPrinterID  string `json:"physicalPrinterId"`
	WorkerHostID       string `json:"workerHostId"`
	Transport          Kind   `json:"transport"`
	Host               string `json:"host"`
	Port               uint16 `json:"port"`
	QueueName          string `json:"queueName"`
	ExpectedDriverName string `json:"expectedDriverName"`
	ExpectedPortName   string `json:"expectedPortName"`
	DocumentName       string `json:"documentName"`
}

type State string

const (
	NotSent   State = "notSent"
	Submitted State = "submitted"
	Uncertain State = "uncertain"
)

type Result struct {
	State          State  `json:"state"`
	Stage          string `json:"stage"`
	Detail         string `json:"detail"`
	BytesWritten   uint32 `json:"bytesWritten"`
	JobID          uint32 `json:"jobId"`
	WindowsError   uint32 `json:"windowsError"`
	WriteAttempted bool   `json:"writeAttempted"`
}

// Send is synchronous: its original call retains ownership until the actual
// connection/helper lifetime settles. A caller's public Wait timeout must not
// cancel or abandon this call. Physical lets an isolated proof reject real I/O.
type Sender interface {
	Send(context.Context, Destination, []byte) Result
	Physical() bool
}

// PrinterGuard spans primary acceptance persistence and optional signal work.
// A production guard refuses Close while a transport call still retains it.
type PrinterGuard interface {
	Context(context.Context) context.Context
	Close() error
}

type GuardFactory func(string) (PrinterGuard, error)

func ValidIdentity(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for _, c := range value {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == ':') {
			return false
		}
	}
	return true
}

func validText(value string, maxUnits int) bool {
	if value == "" || !utf8.ValidString(value) {
		return false
	}
	units, visible := 0, false
	for _, c := range value {
		if c < 32 || c == 127 {
			return false
		}
		units += utf16.RuneLen(c)
		visible = visible || c > ' '
	}
	return visible && units <= maxUnits
}

// ValidateDestination rejects ambiguous or mixed transport configurations.
// TCP uses a captured literal LAN address, without a DNS retargeting step.
func ValidateDestination(d Destination) error {
	if !ValidIdentity(d.PhysicalPrinterID) || !ValidIdentity(d.WorkerHostID) {
		return errors.New("invalid physical printer or worker host identity")
	}
	if !validText(d.DocumentName, 255) {
		return errors.New("invalid document name")
	}
	switch d.Transport {
	case TCP:
		ip := net.ParseIP(d.Host)
		if ip == nil || !(ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast()) || strings.TrimSpace(d.Host) != d.Host || d.Port == 0 {
			return errors.New("TCP destination requires a literal LAN address and port")
		}
		if d.QueueName != "" || d.ExpectedDriverName != "" || d.ExpectedPortName != "" {
			return errors.New("TCP destination contains spooler fields")
		}
	case WindowsSpooler:
		if d.Host != "" || d.Port != 0 || !validText(d.QueueName, 255) || !validText(d.ExpectedDriverName, 1024) || !validText(d.ExpectedPortName, 1024) {
			return errors.New("invalid exact Windows queue identity")
		}
	default:
		return fmt.Errorf("unsupported transport %q", d.Transport)
	}
	return nil
}

func refused(stage string, err error) Result {
	return Result{State: NotSent, Stage: stage, Detail: err.Error()}
}
