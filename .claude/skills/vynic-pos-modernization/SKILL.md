---
name: vynic-pos-modernization
description: Use only when a task explicitly targets the legacy phased POS modernization plan, such as reservation/close-day fixes, database-service splitting, table/status migrations, localization, theme, or responsive UI.
---

# Vynic POS Modernization Adapter

This is a narrow adapter for tasks that explicitly belong to
`docs/VYNIC_PROJECT_PLAN.md`. It is not the default router for all Vynic work.

## Route

1. Follow root `CLAUDE.md` and read
   `docs/agent-state/VYNIC_PROJECT_STATE.md` first.
2. Use the relevant POS/Manager section of
   `docs/agent-state/VYNIC_CODE_MAP.md`.
3. Read only the task's phase in `docs/VYNIC_PROJECT_PLAN.md`, plus its shared
   constraints if needed. Do not assume old phase status is current when code or
   project state says otherwise.
4. Read `docs/UI_PLAN.md` only for a UI phase.
5. Inspect the task-specific implementation and tests before editing.

## Constraints

- Work on one requested phase only; report adjacent discoveries as deferred.
- Preserve behavior in refactors unless the phase explicitly changes behavior.
- Never hide errors behind `null`, false success, or empty catches.
- Preserve secrets, `.env*`, migrations, generated `*.g.dart`, and assets.
- Verify the Flutter role actually changed. Desktop POS work uses
  `--dart-define=APP_ROLE=pos`; the remote desktop Manager client uses
  `APP_ROLE=client`.

Use the canonical engineering protocol only for relevant governing rules; do not
load it in full merely because the task is called modernization.
