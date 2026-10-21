# Approved publication qualification — 2026-10-21

The user approved publishing the completed repairs together with their earlier
Manager redesign/shared-reporting dependencies. The candidate uses branch
`codex/docker-deployment-foundation`, tracking the same branch at
`git@github.com:vaanskii/vynic.git`, starting from
`e99d2ca36168b0d85f51b7812eb1dde42464846c`. No scope decision is pending.

## Included source

- Manager light/dark presentation, adaptive navigation, Count/New/Saved flow,
  forms and connected reporting/inventory surfaces, with regression tests.
- Shared ledger reporting, recorded creator/closer attribution, explicit missing
  history/provenance and retained-row recovery.
- Transactional Staff/expense delivery intent, pending-command snapshot
  protection, whole-day reservation admission, stock-unit/recipe concurrency
  guards, atomic counted-menu writes and paged notification catch-up.
- Owner catalog retry identity, Manager linking guidance and Vankisi booking
  snapshot/variant/guest-count/payment-return corrections with focused tests.
- A publication fix makes chart/nested-form parity tests self-contained: four
  unchanged approved preview Dart files are now test fixtures instead of imports
  into a local design-preview directory. Only the test import paths changed.

The local, ignored `source-manifest.json` records the 168 validated candidate
source/test/state paths and SHA-256 values. Project-state and code-map documents are staged partially:
unrelated POS/printer paragraphs remain only in the user's working files.

## Fresh exact-candidate checks

| Check | Result |
| --- | --- |
| Backend TypeScript and Nest build | PASS |
| Backend unit selections | 304 passed, 0 failed/skipped |
| Seven disposable PostgreSQL groups | 212 passed, 0 failed/skipped; owned cluster stopped/removed |
| Flutter analysis | PASS; no issues |
| 31 Flutter unit/widget files, including portable parity references | 379 passed, 0 failed/skipped |
| Full platform-web test run | 262 passed, 0 failed/skipped |
| Platform-web and Vankisi production builds | PASS; existing chunk warnings only |
| Candidate Manager Android debug, macOS arm64 debug and unsigned arm64 iOS Simulator builds | PASS; no product installed or launched |
| Three new backend test files lint | PASS; zero errors/warnings |
| Changed platform-web files lint | Zero errors; one hook warning also present at HEAD |
| Changed Vankisi files lint | Not clean: four pre-existing no-explicit-any errors in Checkout, identical at HEAD; other selected files clean |
| Formatting of two repaired parity tests | PASS; zero changes required |

Machine-readable results and command receipts: `candidate-validation.json`.
Unchanged Vankisi lint debt is compared per file in
the local, ignored `vankisi-lint-comparison.json`. Full backend lint was not rerun; its documented
existing debt is not claimed resolved. The initial 71-path-only candidate failed
because it omitted the subsequently approved dependencies. Those scope-isolation
failures are superseded by these successful complete-candidate checks, and were
not regressions in the qualified working tree.

The candidate excludes an unrelated printer-service change reachable through
Manager imports, so all three artifacts were rebuilt against candidate source.
Earlier isolated native Creator-report, History, pagination and offline/source
observations remain separately recorded in
`../validation/final-20261021/native-recovery-1/README.md`. Publication did not
launch normal Manager/POS apps or perform live business writes.

Apple qualification retains the prepared pinned dependency graph and documented
temporary package-path/CocoaPods preparation fixes from the build phase. These
are development compiles, not signed mobile release, clean-machine packaging,
Windows, physical-device or printer certification. Existing mobile package IDs
remain unchanged.

## Exclusions and publication boundary

The local `exclusions.json` accounts for unrelated tracked work left unstaged. Environment
changes, local settings, POS UI followups and printer work remain untouched.
Binaries, archives, PNG captures, raw logs, generated caches, fixture rows and
runtime sessions are not published. Prose may reference those retained local
proof files; their omission from Git is intentional.

Actual staged contents are compared with the validated candidate and checked
for whitespace, binary content and credential patterns before commit. No force
push, merge, deployment, credential change or normal-service restart is included.
GitHub's read-only API reports zero configured Actions workflows; checks and
statuses for the exact pushed commit are inspected after publication. No CI pass
is implied by local checks or by the absence of workflows.
