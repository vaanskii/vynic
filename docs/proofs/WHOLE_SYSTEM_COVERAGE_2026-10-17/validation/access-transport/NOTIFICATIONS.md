# Notification and claim recovery — 2026-10-18

Scope: validate the saved additive Manager notification paging contract and
stale credential claim handling. No Staff queue, enrollment, credentials,
permissions, application identity, printing or live restaurant state changed.

## Implemented

- A fresh inbox omits `since`, allowing Cloud to choose its 24-hour initial
  window. Subsequent catch-up uses the last completed server watermark with
  the existing one-minute replay overlap. A fast handset clock therefore
  cannot place the initial window in the future.
- Claim responses are discarded when their request credential has changed.
  This covers successful responses and rejections. Old commands remain
  unexecuted and unacknowledged; the next poll uses the current credential.
- Added inbox regression tests and a guarded disposable-PostgreSQL paging
  suite. Added old 401/403 retry tests and successful stale-claim execution
  regression coverage.

The saved paging implementation already fixes the drain watermark, orders by
notification timestamp and ID, scopes each page by authenticated Venue and
staff username, and advances the checkpoint only after the last page.

## Verified locally

| Check | Result |
| --- | --- |
| Flutter inbox, Edge client and Edge service tests | 37 passed |
| Focused Flutter analysis (six source/test files) | No issues |
| Disposable PostgreSQL notification paging spec | 4 passed |
| Backend full `tsc --noEmit --incremental false` | Passed after root's concurrent Staff test typing repair |
| Prettier check for new PostgreSQL spec | Passed |
| `git diff --check` for owned notification/transport paths | Passed |

Commands and raw output are in `flutter-notifications-transport.log`,
`flutter-analyze-notifications.log` and
`backend-typecheck-notifications.log` beside this file. Flutter also prints
existing CocoaPods migration guidance; no native dependency changes were made.

Flutter cases cover draining 125 rows, reopening the persisted checkpoint,
server time versus handset time, failed later page and safe replay, reset and
principal/origin changes while a page is in flight, inconsistent watermarks,
repeated cursors and malformed pages. The history panel intentionally retains
its newest 100 entries, separately from draining every fetched page.

## Database qualification

`src/mobile/services/notification-page.integration.spec.ts` uses
`TENANT_INTEGRATION_DATABASE_URL` and refuses non-disposable, non-loopback
databases. Its four cases passed in root's first disposable PostgreSQL run;
see `../postgres-recovery-20261018/core-tests.json`. They exercise
205 same-timestamp deliveries inserted in reverse order, Venue/staff scoping,
arrival during a fixed-watermark drain, server initial-window bounds and
malformed cursor/timestamp rejection. The run receipt confirms the owned
cluster stopped and was removed. Other core and website suites failed in that
aggregate run; this scoped notification pass is not aggregate recovery success.
Running the suite without its explicit
database variable skips it and is not evidence of database validation.

## Limits

This focused proof does not qualify live FCM, Socket.IO reconnection, handset
background delivery, normal app startup or physical devices. It does not
change the initial 24-hour catch-up policy or the 100-entry panel retention.
The separately deferred enrollment-security issue remains unchanged.
