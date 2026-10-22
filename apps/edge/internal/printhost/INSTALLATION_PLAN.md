# Printer host installation qualification

This is a reviewable future plan. No executable currently calls
`RunWindowsService`; no service is registered, started, stopped, deleted or
reconfigured by this package. D022's existing per-user Edge/POS installer and
interactive launcher remain unchanged.

The generic model separates scope, role and transport. `LOCAL` uses an exclusive
local host queue; it may run inside a POS machine. `VENUE_SHARED` pins a stable
cluster ID and an explicit membership digest. Its `clusterLogicalOnly` or
`qualifiedGateway` policy does not establish a downstream RAW-printer fence.
Shared physical senders remain refused in this candidate. An independent gateway
outside the configured POS hosts is only the explicit `independentGateway`
availability profile. No lease expiry, epoch, health timeout or discovery selects
a replacement physical owner. Cluster membership/election/authentication and
physical fencing remain separate qualification work.

Before any future installation, record these exact selected values for review:

| Value | Required evidence |
| --- | --- |
| Role and scope | `posAgent` or `printGateway`; `LOCAL` or `VENUE_SHARED`; explicit ownership policy |
| Service name | `VynicPrinterHost-<canonical host UUID>`; one role/configuration per stable host |
| Installation state | Absolute existing state root and its Venue/installation/Device/host identities; preserve `edge.db`, WAL and migration receipts |
| Host artifact | Absolute executable path, signed release identity and exact SHA-256; reject links/reparse substitution during qualification |
| Helper artifact | Absolute helper path, exact SHA-256 and helper protocol 1; no guessed executable or driver |
| Principal | Exact approved service account/SID; intended local/network rights and session scope, without inventing credentials |
| Queue binding | Under that account, enumerate and match exact queue, driver and port; machine-local and per-user connections require separate qualification |
| Capability/configuration | Explicit qualified command language, paper/raster/cutter/beep profile digest and all captured revisions |
| Shared scope | Server-authorized cluster/explicit voter-client membership and configuration digest; a separate qualified downstream physical fence |

Future actions, in order, after exact values and authority are approved:

1. Verify artifact signatures/hashes, account-specific read-only enumeration,
   storage access and supported reader/schema/helper floors. Inventory success
   alone does not qualify a printer model or prove paper delivery.
2. Inspect existing installed services/processes and the current POS writer.
   Refuse a second writer. Do not use a service-name change or copied state root
   to evade ownership. Explicitly stop/drain the current owner and reconcile
   retained uncertainty before a physical cutover.
3. Prepare the one own-process service definition with the selected executable,
   fixed role/configuration and approved principal. Register/start it only under
   the separately approved installer flow; this package supplies no SCM manager
   API, account provisioning, ACL, firewall, driver or credential mutation.
4. Keep Flutter's client read-only health check bound to the authenticated host
   and exact pins. Missing/foreign/stale health reports unavailable or version
   mismatch. Flutter must never launch a replacement writer or perform SCM work.
5. Qualify voluntary stop: close transaction admission; fence new queue claims;
   wait actual primary persistence and optional beep; flush/close resources;
   only then release ownership. A timeout only stops waiting. Windows service
   StopPending is a status report, not proof against forced OS termination.
6. Qualify forced shutdown/kill and old-host return separately. Retained STARTED
   becomes UNCERTAIN, an uncertain FIFO head never automatically replays or
   skips, and old readers cannot reopen a newer database. Exact downstream
   transport/JobObject/hardware behavior remains necessary before shared RAW.
7. Upgrade only through a separately qualified ownership-preserving transaction:
   verify no active admission/native call or unresolved compatibility hold;
   maintain the freeze through signed binary/helper replacement and health
   attestation. Preserve the database and all journals. Reject old-reader/schema
   or changed helper/artifact binding rollback; never restore data with binaries.

The source currently wires only the proof queue's `FenceAdmission`, `Stop`,
durable hold inspection and explicit resource closure. The Windows adapter
compiles against `golang.org/x/sys/windows/svc` and joins an already
SCM-launched process. There is no production listener, physical activation,
fleet cutover, installer integration or persistent service change.

Windows account/queue behavior must be qualified on the selected machine:
[EnumPrinters](https://learn.microsoft.com/en-us/windows/win32/printdocs/enumprinters),
[service accounts](https://learn.microsoft.com/en-us/windows/win32/services/service-user-accounts),
[service control handling](https://learn.microsoft.com/en-us/windows/win32/services/service-control-handler-function).
