# Held printer agent executable and installation

The new `cmd/printer-agent` is a separate runnable process. Foreground mode is
nonprivileged; `service` joins an already SCM-launched Windows process. The
existing D022 POS/Edge installer, Hive directory and interactive launch remain
unchanged. Every physical call and both mutating RPC methods remain held. No
CLI/config flag can activate them.

The daemon requires a dedicated existing printer-state directory with
`printer-agent.state.json` (`PRINTER_AGENT_SOFTWARE_HELD`, schema 6, exact Pins)
and matching already provisioned installation/Venue in its SQLite file. It
refuses ordinary Edge roots, missing state, foreign markers, old schema, UNC,
device/reparse paths and remote Windows drives before opening a writer. It
never initializes/enrolls an identity, issues certificates or migrates a live
Edge/Hive root. Synthetic fixtures are prepared only by tests.

Foreground execution uses `printer-agent foreground --config <absolute-file>`.
An optional `--shutdown-file <state-directory>/printer-agent.stop` reads only
that explicit local empty marker and requests the same retained drain as a
foreground signal. It never creates/removes a marker; stale/malformed markers
are visible failures. This enables synthetic Windows process stop/restart
tests without SCM registration and is distinct from OS/service restart.

`LOCAL_HELD` runs an exclusive local retained queue. `VENUE_SHARED_HELD` reports
software infrastructure only: this daemon does not join Raft or claim a healthy
shared replica. Stable membership is explicit; no discovery or outage fallback
changes scope. STARTED recovery is UNCERTAIN, spent beep never replays, and the
scheduler never starts a physical claim in either profile.

The exact configuration schema is in `internal/printerdaemon/config.go`.
Three artifacts are mandatory: absolute running agent path/SHA256, absolute
helper path/SHA256/protocol 1, and exact capability-profile bytes/SHA256. Health
rechecks artifact hashes and trusted state pins; replacement latches a failure
and follows the retained drain. mTLS certificate/key/CA paths are read-only
inputs; neither config nor bundle embeds credential bytes. Config client pins
authorize observation only, not Device/origin/route authority. Flutter's exact
11-key client profile has a pinned current server leaf and no CA fallback.
Its explicit `currentDeviceInstallationId` is the POS enrollment context;
`pins.installationId` is the separate Go installation. They are never inferred
from or rewritten to each other, and this declaration grants no authority.

Use a verified existing Go SDK/cache to build each target, then review its exact
hash before supplying the provisioned config:

```text
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -mod=readonly -trimpath -o <agent.exe> ./cmd/printer-agent
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 go build -mod=readonly -trimpath -o <agent.exe> ./cmd/printer-agent
python3 packaging/windows/printer-agent/build-bundle.py --config <absolute-profile.json> --out <new-absolute-bundle-dir>
```

Bundle validation enforces matching real PE architectures, exact hashes/profile
and exactly three artifacts plus `manifest.json`; it never copies TLS keys.
AMD64 and ARM64 helpers are separate artifacts. Read-only inventory under an
interactive account is recorded separately from the selected future service
account, and neither establishes physical model/driver/cutter/beep eligibility.

The safe default is a reviewable plan:

```text
printer-agent plan --config <profile> --bundle-manifest <manifest.json> --client-profile <client-profile.json>
printer-agent apply --plan <reviewed-plan.json>
```

The second command defaults to `PlanOnly` and performs zero external SCM calls.
`planSha256` binds the exact configuration, bundle, client profile, principal,
service target and actions. A future separately approved registration is:

```text
printer-agent apply --plan <reviewed-plan.json> --apply --reviewed-plan-sha256 <exact-reviewed-hash>
```

The Apply source rechecks every referenced input, LOCAL held role, selected
account/SID qualification evidence, elevated Administrator membership and the
current service. Exact existing configurations are preserved; mismatch refuses
without reconfiguration/deletion. Fresh registration invokes only the exact
System32 `sc.exe` with separate argv to create a stopped manual own-process
service under an explicit preprovisioned gMSA or exact virtual service account.
There is no LocalSystem default, shell/eval, password, automatic elevation,
account/logon-right/ACL/firewall/trust/driver mutation, service start or cutover.
No Apply or service registration was executed by this task.

Before a later service start, the selected account must already be separately
qualified for state/artifact/key access and read-only queue inventory. The
runtime also checks its actual token SID against the selected principal. A
voluntary stop fences RPC/host admission, waits actual queue/RPC lifetimes, then
closes sockets/storage and owner. Timeouts never force a handler/native release;
unconfirmed cleanup retains the process and visible diagnostic. Forced Windows
kill/reboot and account-specific service lifecycle still need qualification.

Production dependencies remain explicit: authenticated server-owned
Device→Venue/current Device-installation binding, signed terminal/origin offline
authority and trusted route/profile provisioning; a complete business effect
bridge to local admission; Raft composition for shared agents; downstream RAW
fencing or a selected qualified gateway; real printer/model/driver and renderer
qualification; signed release/installer handover and original POS writer cutover.
Software availability, a certificate pin, epoch or quorum grants none of these.

The future SCM behavior follows the official
[CreateService contract](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew)
and [Go service APIs](https://pkg.go.dev/golang.org/x/sys/windows/svc).
