# Windows POS fullscreen and clean Quit

Next POS publication: **version 1.0.5, signed manifest release 6**
(after the local lab's 1.0.4 / release 5). The Windows validation build uses
`--build-name=1.0.5 --build-number=6`; the signed release counter is separate
from Flutter’s build-number suffix. This change does not publish a feed or
change the shared Manager version. A newer feed published independently must
advance both POS version and release monotonically.

The prepared `vynic_pos` native target uses a borderless monitor-sized window
before the first Flutter frame. Manager keeps `WS_OVERLAPPEDWINDOW`.
Monitor coordinates remain physical; Flutter and `PosScaledSurface` retain
logical DPI and user display scaling. DPI/display changes refit monitor bounds.
The existing compact POS display setting does not restore a native title bar.

Settings contains **აპლიკაციიდან გასვლა**. It and Alt+F4 use one confirmation:
**ნამდვილად გსურთ Vynic POS-ის დახურვა?**, **გაუქმება / გასვლა**.
A confirmed Quit atomically freezes the existing `UpdateReadiness` admission
barrier, stops POS timers/transport clients, waits for outstanding local worker
callbacks, flushes Hive and coordination journals, closes owned coordination
channels and Hive, then allows Flutter to exit the POS process. No process-stop
or install request is sent to Edge; its background download service stays alive.

Active payment/close/cancel/restore/local writes, unresolved recovery/coordination
and an in-flight update refuse Quit with a reason. Windows enables tracking even
without an updater config. Persisted open Orders/Tables and durable Cloud outbox
rows do not block: the same pinned restaurant directory reopens next launch.
Cloud backlog is not drained as a condition of Quit. Existing worker callbacks
may finish before their local resources close.

During Go startup probation Quit refuses until the existing health check finishes;
this prevents normal user exit from being classified as candidate startup failure.
Updater-controlled process replacement continues to use its existing frozen,
flushed install path. A cleanup failure does not exit or reopen admission;
the dialog shows the error and allows retry. Worker shutdown is bounded at
45 seconds per attempt; local flushes must complete successfully.

## Focused validation

- Flutter tests: `test/unit/pos_quit_test.dart`,
  `test/widget/pos_quit_action_test.dart`, existing readiness/startup/update UI
  tests and affected transport/projection/runtime-config/consumption tests.
- Product/native selection: `python3 -m unittest windows_fullscreen_test product_test`
  from `apps/operations/tool`.
- Windows native geometry test: after preparing/building the product, copy
  `tool/windows-window-test.cmd` into that project's tool directory and run it
  from the VS x64 Native Tools prompt at the project root. It compiles/runs
  `windows/tests/fullscreen_smoke.cpp` in POS and Manager modes, checking native
  style/monitor bounds, DPI/display messages and preserved Manager chrome.
- Real Windows POS compilation is required; changing geometry must not disable
  the runner's per-monitor DPI manifest. Test physical touch/DPI combinations
  used at the restaurant before production rollout.

Validation completed on the development Windows 11 VM: release compilation
and both native geometry modes passed. The focused Flutter suites passed 65
tests; the exact staged commit also passed its 14 Quit/readiness tests independently
of unrelated workspace edits. Physical touchscreen/multi-monitor qualification
remains a production rollout check. No feed was published or app installed.

## Login and Windows notification area

The Windows POS login exposes the same confirmed **აპლიკაციიდან გასვლა** action
before PIN entry. Its native notification-area icon (Windows may place it under
Show hidden icons) offers Open and Quit. Quit foregrounds POS and sends its
normal WM_CLOSE request through Flutter's existing clean-exit observer. It
never directly terminates POS or signals Edge. The icon is removed when POS
exits and restored after Explorer recreates the taskbar. Manager's runner does
not compile the tray code.

Go remains available as an idle local service when POS is closed; POS-owned
operational workers and client connections stop through the existing Quit
path. Background release checks use the existing interval, not a busy loop.

## Ordinary launch versus release probation

Go now distinguishes a previously verified current release with a pinned data
path and no swap/rollback journal from an install/repair/rollback. An ordinary
launch generates a fresh nonce and still requires matching process ID, version,
Hive schema and the existing data directory. It can complete after the first
authenticated ready heartbeat; it does not repeat the 30-second release trial.
New/unverified releases, repair and rollback retain the full stability period.
A missing/wrong data path or unhealthy startup is never treated as ready.

This is a Go binary change. A POS-only release cannot deliver it to an existing
pinned Edge baseline. The user-approved local maintenance tool
`apps/edge/tool/lab-edge-upgrade` upgraded the Windows lab to Edge 1.0.1.0 /
bootstrap 3 after POS was cleanly closed. It verifies the signed bootstrap and
artifact, gracefully stops the old host, preserves data and identity, and retains
the old binary until fresh POS health is proven. It is restricted to the exact
development baseline and is neither shipped nor scheduled as an Edge updater.

The real Windows launch completed in 0.61 seconds. Its fresh PID 12984 sent
health at 22:23:56.713 UTC and received verification at 22:23:56.726 UTC on
2026-09-20, compared with 30-second waits in preceding launch logs. Restaurant
data, Edge installation identity and POS executable hashes matched across the
Edge-only maintenance. After verification, the temporary old Edge binary and
maintenance stage were removed. Production Edge self-update remains deferred.
The POS login/tray changes are built on Windows and published locally as POS
1.0.7 / signed release 8. Seven Flutter Quit tests and both Go updater/setup
suites pass. The tray interaction itself still requires Windows UI validation
after explicit installation; compilation does not prove Explorer interaction.
