# Vankisi pilot readiness

This is a read-only readiness assessment. Existing restaurant data, tenant
identities, accounts, live environments and the working POS were not changed.
The owner will handle historical-data loading; a restore is not a tenant merge.

| Area | Verified behavior | Gate before live use |
| --- | --- | --- |
| Website registration | `/request-access` creates an access request. Direct customer signup is disabled. Approval of a new request without an existing venue provisions a new organization and venue. | Identify the existing Vankisi venue/organization first. Do not approve a duplicate new venue based only on its name. Existing-organization owner invitations are supported. |
| Existing local data | POS checks local venue binding and restored/pending state against enrolled venue authority. Credential clearing does not detach the data. | Match the enrolled device to the same venue. Do not change venue IDs or clear data to bypass the guard. |
| Restore | Format-2 backup validates stores and schema, excludes device/updater credentials, and uses guarded replacement with recovery. Foundation import requires empty operational state. | Preserve the original backup and rehearse on a copy. Arbitrary old database merging and cross-venue restore are not supported. |
| Test isolation | Local compose has a separate local database. Beta/stable signed channels exist in updater contracts. | Remote staging database is not verified. This beta uses `api.vynic.ge`; `staging` in the build does not isolate customer data. |
| Beta distribution | POS 1.0.0 build 16 installer is published at `releases.vynic.ge`; signed bootstrap/repair metadata and Microsoft CRT DLLs are included. | Test-only download. Clean install/runtime and physical printing remain pending; automatic update feed stays inactive. See `WINDOWS_BETA_TEST_INSTALL.md`. |
| Updates | Check/download does not restart. Install is explicit, with payment/write/recovery readiness guards. Interrupted downloads retry; binary rollback retains restaurant data. | Exact clean install/runtime test is pending. Older lab `1.0.14` cannot ordinarily update to `1.0.0`; never reset monotonic counters. Channel/trust is pinned in the installation receipt; no supported channel-switch UI was found. |
| Cloud database | Render Free PostgreSQL expires after 30 days and has no managed backups. The workspace's exact database expiry is not verified here. | This is a live-use blocker until durable hosting and tested backups are chosen. No paid upgrade was authorized or performed. |
| Migrations | Production path uses serialized `prisma migrate deploy`; POS owns live offline operation. | Back up and rehearse restoration on a separate copy; verify old/new client compatibility before a rolling release. No production reset, seed or import. |
| Offline sync | Stable sale IDs and queued menu mutations provide retry/idempotency protections in their supported paths. | Test offline sale, reconnect and reconciliation with synthetic data on the same venue identity. Do not assume arbitrary legacy histories can be merged without duplicates. |
| POS and Manager | Enrollment uses existing device/venue authority. Existing Manager history is distinct from first-manager bootstrap. | Reuse the existing venue and correct enrollment path; do not create duplicate first-manager history or a second primary POS. |
| Printing | TCP ESC/POS and Windows RAW queues are supported. Paper diagnostics are removed; explicit copies retain a small `COPY` label and audit trail. | Physical print of this exact rebuilt candidate is pending. Existing user's printer test does not qualify these new bytes. |

Useful implementation entry points: `apps/backend/src/customer/onboarding-requests.ts`,
`owner-invitations.service.ts`, `apps/operations/lib/core/services/pos/update`,
`apps/edge/internal/setup`, and `apps/edge/internal/updater`. The separate domain
onboarding worktree is outside this task.

Render limitations were checked against https://render.com/docs/free on 2026-10-24.
