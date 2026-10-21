# Computer Use permission clarification

This preserves the historical permission captions and original pause. The user
explicitly resumed the scoped builds and isolated QA on 2026-10-21; see the
[dated continuation evidence](validation/final-20261021/README.md). Initial
binding again timed out (`-10005: timeoutReached`), but a later supported fresh
CUA session recovered native control. The
[remaining native interactions passed](validation/final-20261021/native-recovery-1/README.md),
only the QA app was closed, and its fresh synthetic database was removed.
No denial or permission bypass was reported. This does not assert any permanent
Computer Use access grant.

The parent independently read the exact delivered approval captions below.
This identifies the requests; it supplies no new approval and does not reveal
which approval-button or persistence option the user selected.

| Approval ID | Exact caption | Recorded use and verified outcome |
| --- | --- | --- |
| `manager:042d2f607e1f446a99da91fe46719e20:1` | Allow Computer Use to use "Vynic Whole System QA"? | `cua.getApp` selected the separate QA executable by full path. It timed out after 737 seconds, but launch occurred: PID 69979, app inventory, native Dashboard capture and eight GET/200 requests confirm it. A subsequent binding lookup by QA bundle ID also timed out. No further UI retry occurred. |
| `manager:21cbbc12b74f4e20ae5fdeed970778b9:1` | Allow Computer Use to use "Vynic Manager Sync QA"? | Earlier `cua.getApp` opened the separate sync-QA executable. The first call took 871 seconds and its fixture expired; the failed attempt and resolved state were checked before retry. The successful session inspected Financials, scrolled Sale history, clicked the next page, reloaded reads after fixture shutdown, captured the cached-data warning and quit only that QA app. |
| `manager:f46746c2f5644d90982d999826ca9e16:1` | Allow Computer Use to use "Vynic Manager"? | Selected the existing normal Manager, read accessibility state/screenshots and tried to expand warning/source details using clicks, Tab and window Raise. Coordinate actions failed with no window available; exact source details remained unverified. A later read-only observation showed a separate entitlement-refresh error. No PIN, business form, normal-app quit or restart was issued. |

These are application-specific Computer Use access requests. The capability
can read screenshots/controls and click/type in the selected app; it is not
inherently read-only. The recorded actions remained constrained by the task.
These captions did not authorize GitHub publication, PIN entry or mutations to
real restaurant records. Execution establishes what ran, not which UI approval
option the user selected. No permanent-access grant is asserted.

## Targets and isolation

- Current QA: `/tmp/vynic-whole-system-native-qa-20261018/apps/operations/build/macos/Build/Products/Debug/Vynic Whole System QA.app`, bundle `ge.vynic.manager.wholesystemqa`.
- Earlier sync QA: `/tmp/vynic-manager-sync-native-qa-20261017/apps/operations/build/macos/Build/Products/Debug/Vynic Manager Sync QA.app`, bundle `ge.vynic.manager.syncqa`.
- Normal Manager: `ge.vynic.manager`.

QA used private temporary Hive storage, fixture-generated authentication and
an owned loopback proxy rejecting every non-GET app request. Its backend wrote
synthetic test records in a newly created disposable database. It did not use
real restaurant records or credentials. No real order, payment, reservation,
PIN entry or print job occurred. Source/test/proof changes belong to the
separately authorized integration task, not these app-window permission cards.
No signing, credential/security-setting change, deploy, commit or push occurred.

## Cleanup and pause

The latest fixture hold was released without escalation. Its original runner
completed its planned teardown: 47 HTTP/PostgreSQL cases passed, zero skipped,
and the owned cluster was stopped and removed. Exact receipt:
`validation/native-reporting/runtime-validation/receipt.json`.

The current QA window was left running at the last verified observation because
binding failed and further permission-dependent actions were paused. Its quit
is pending, not denied or silently retried. Earlier sync QA was closed and its
owned database removed; see the phase-one completion receipt.

No normal Manager/POS launch, quit or restart was issued. Normal POS PID 40211
and existing PostgreSQL PID 8148 were present at their last observation. Original
Manager PID 26303 was absent at a later check; its cause was not established.

Before another permission-dependent action, provide its specific app/target,
purpose, consequences and isolation in plain language. The parent's relay of
these captions was not treated as approval for another action.
