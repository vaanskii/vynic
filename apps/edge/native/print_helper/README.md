# Print helper boundary

The Go queue owns durable attempts and one worker per physical printer. Flutter
owns rendering, business decisions and UI. The helper reuses the existing
`windows_spooler.cpp` core and extracted `windows_spooler_native.cpp` adapter;
it does not render, retry, install drivers or confirm paper delivery.

`internal/printtransport.Sender.Send(ctx, Destination, []byte)` is synchronous.
The queue persists STARTED before the call and retains `PrinterGuard` across
primary acceptance persistence and the optional signal. A public wait deadline
does not cancel the worker. UNCERTAIN blocks that physical printer until explicit
reconciliation. The frozen `workerHostId` must match the configured Go host.
The host semaphore does not fence a different computer; fixed owner routing and
the durable queue supply that boundary. No timer authorizes ownership takeover.

Windows launch pins the helper's absolute canonical executable path, SHA-256,
and protocol version 1. A file handle denies write/delete while it is in use.
The helper has no command-line print arguments. `CreateProcessW` creates a
suspended process with a non-inherited kill-on-close Job Object assigned through
`PROC_THREAD_ATTRIBUTE_JOB_LIST`; only stdin, stdout and separate stderr pipe
handles are inherited. Unsupported creation attributes or job nesting fail
closed. Cancellation terminates and waits for the exact process. Killing the
helper does not retract bytes accepted by the Windows spooler.

The parent acquires the binary semaphore named
`Global\VynicPrint-<SHA256(physicalPrinterId)>`. The child opens the same object
and retains its handle, without releasing count. An unexpected successful child
probe is undone and refused. Parent death leaves count unavailable while the
child exists. Failed replacement acquisition closes its handle immediately;
after all old handles close, fresh acquisition can create a new semaphore.
Semaphore recovery does not authorize replay of a persisted STARTED attempt.

Each stdin/stdout frame is `uint32 little-endian length + body`, bounded to
16 MiB. Body starts with `uint32 0x31505456`, `uint16 version=1`, `uint8 tag`,
and `uint8 reserved=0`. Tags are inventory=1, submit=2, COMMIT=3, READY=64,
result=65 and inventory-result=66. Strings are a uint32 byte length plus exact
UTF-8. Additional fields, malformed UTF-8, control characters, incorrect
versions, reserved flags and oversize data are rejected.

Submit carries queue, driver, port, document and semaphore name strings followed
by uint32 payload length and payload. Queue/document are bounded to 255 UTF-16
units; driver/port to 1024, payload to 8 MiB+1024 bytes. The helper validates the
complete request, retains the parent semaphore and returns READY. It cannot
call SubmitRaw until a separate complete COMMIT frame arrives. Inventory and
COMMIT have no fields. Result contains state(0 notSent/1 submitted/2 uncertain),
attempted(0/1), uint16 reserved=0, uint32 bytesWritten/jobId/windowsError, then
stage/detail strings. Inventory result contains uint32 count and name/driver/
port triples, with at most 1024 descriptors.

Portable verification:

```sh
go test -race ./internal/printtransport
cmake -S native/print_helper -B <fresh-output>
cmake --build <fresh-output>
ctest --test-dir <fresh-output> --output-on-failure
```

`qualify_windows.ps1` uses a fresh source/output tree, an already cross-compiled
Go test executable, source/SDK hash manifests, and existing cached CMake/MSVC and
Flutter wrapper/engine paths. It rebuilds the helper, fake core/session tests and
the actual read-only legacy channel harness. Real helper requests are inventory,
missing/empty payloads, or incomplete framing only. Positive writes are fake.
The Go fixture executable verifies kill-on-parent-close, stdin EOF inheritance,
failed semaphore acquisition cleanup and parent-death-to-fresh-acquisition.
No product/service start, SCM changes, driver operations or physical print jobs
are part of this qualification. Service-account inventory and each physical
printer/profile still require separate qualification.

References: [process creation attributes](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute),
[Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects),
[semaphore lifetime](https://learn.microsoft.com/en-us/windows/win32/sync/semaphore-objects),
[StartDocPrinter](https://learn.microsoft.com/en-us/windows/win32/printdocs/startdocprinter),
[WritePrinter](https://learn.microsoft.com/en-us/windows/win32/printdocs/writeprinter),
[EnumPrinters](https://learn.microsoft.com/en-us/windows/win32/printdocs/enumprinters),
[GetPrinter](https://learn.microsoft.com/en-us/windows/win32/printdocs/getprinter).
