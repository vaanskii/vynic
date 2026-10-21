# Native QA recovery — 2026-10-21

**PASS: the remaining requested native interactions are complete. No user action
is needed.** The same already-built `Vynic Whole System QA` executable was used;
no successful build was repeated. No production source or normal app was changed.

## Supported recovery

1. Reset the persistent Computer Use JavaScript session with `js_reset` and
   initialize a fresh app inventory with `cua.getState()`.
2. Display-name selection returned `Invalid app: Vynic Whole System QA` without
   launching it. Selecting the existing exact app path in the fresh session then
   succeeded and returned its native window and accessibility tree.
3. Accessibility button actions worked. Pointer scrolling still returned
   `-10005: noWindowsAvailable`. Raising the QA window and using supported CUA
   keyboard Tab and Next/Page Down navigation reached the sales list. The native
   next-page button was then operated through its current accessibility index.

No permission denial was reported. No unsupported UI automation, permission
reset, permission expansion or security bypass was used. The earlier timeout
was an actual failed binding attempt, not a denial and not a product failure.

Target:
`/private/tmp/vynic-whole-system-native-qa-20261018/apps/operations/build/macos-final-20261021/Build/Products/Debug/Vynic Whole System QA.app`,
bundle `ge.vynic.manager.wholesystemqa`.

## Native verification

| Check | Native observation | Evidence |
| --- | --- | --- |
| Creator-report navigation | `QA creator`, 31 orders and 372.00 GEL; partial detail coverage and recorded creator-name attribution notices remain visible | Creator report (local: `screenshots/creator-report-1.png`) |
| History navigation | 372.00 GEL for available history, 2026-10-20 explicitly unavailable, total labeled as including available days only | History (local: `screenshots/history-3.png`) |
| Financials pagination | First page showed “მეტის ნახვა”; clicking it issued a cursor GET/200, appended sale `#10005` for 12.00 GEL, and removed the button after all 31 fixture sales | Before (local: `screenshots/financials-5.png`), after (local: `screenshots/financials-6.png`), `native-reads.jsonl` |
| Offline reload | After the owned proxy/database were removed, “Reload reads” rebuilt Financials; 372.00 GEL remained with “განახლება ვერ მოხერხდა · მონაცემები შეზღუდულია” | Offline Financials (local: `screenshots/financials-8.png`) |
| Offline provenance | Expanded details identify cached POS source, API/source timestamps and ages, partial completeness, API unavailability, and the limitation on confirming current POS state | Offline source details (local: `screenshots/financials-9.png`), `native-interaction-receipt.json` |
| QA closure | CUA `super+q` quit the bound QA app; subsequent AX lookup returned `procNotFound` and fresh app inventory showed QA absent | `native-interaction-receipt.json`, `final-processes.txt` |

These are observations and actions in the actual macOS QA window. No automated
equivalent was substituted for native evidence. The separate app startup shim
still limits qualification: normal production login/full startup, live data,
physical devices, Windows and printers were not exercised.

## Fixture and cleanup

The fresh fixture used the same GET-only loopback proxy at `127.0.0.1:55381`,
new private temporary Hive storage and a newly created disposable PostgreSQL
cluster. It prepared only synthetic records: 31 sales at 12.00 GEL, distinct
creator/closer values and an unavailable historical day. The app's 26 recorded
mobile API GET requests were all HTTP 200, including the real next-page cursor
request. No non-GET app request is present in `native-reads.jsonl`.

The fixture was deliberately shut down before the offline check via its owned
`STOP` marker. Its runner passed the same 47 reporting/ledger fixture cases,
zero failed/skipped, and stopped/removed only its new cluster; see
`runtime-validation/receipt.json`. This is a repeated overlapping fixture run,
not 47 additional independent cases. Existing PostgreSQL PID 8148 remained
running. The QA app was then closed through CUA. No normal Manager/POS launch,
quit or restart was issued.

Accepted app-generated captures were copied from the separate QA container and
visually checked. Raw timer/transition images are identified separately in
`screenshots/README.md`; they are not extra acceptance results.

No remaining blocker exists for this requested local build and isolated native
QA scope. This does not expand the earlier evidence into whole-product or
production-readiness certification.
