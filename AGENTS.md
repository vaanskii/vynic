# AGENTS.md — Vynic

Root instructions for all AI agents (Claude / Fable / Codex). Keep this file short.

## What Vynic is

Restaurant POS system. Two parts:
- `pos_app_client/` — Flutter app (Windows POS is the operational source of truth;
  mobile manager app; shared `core/`). Local-first on Hive.
- `pos_app_server/` — NestJS + Prisma + PostgreSQL. Mirrors POS data for the
  manager app and the customer website. See `pos_app_server/CLAUDE.md`.

Currently single-restaurant. A modernization + SaaS effort is planned but **not
started**.

## Before you touch anything

1. Run `git status --short`. Know what was already dirty.
2. If the task is Vynic modernization (bug fix, refactor, SaaS, UI), **read
   `docs/VYNIC_PROJECT_PLAN.md` first** — it has the phases, constraints, and the
   known reservation/close-day bug. Do not re-derive it.
3. Confirm which phase your task belongs to. Do only that phase.

## Hard rules

- **One phase at a time.** No broad, unrelated refactors. If you notice other
  problems, note them — don't fix them in the same change.
- **Small changes, small commits.** Never a giant multi-concern commit.
- **Do not change app behavior** unless the task explicitly is a behavior change.
  Refactors (e.g. splitting `database_service.dart`) must be behavior-preserving.
- **Never hide errors behind `null` returns or empty `catch`.** Return a typed
  result or rethrow, and log the real error. This is the exact cause of the live
  reservation bug — do not reproduce the pattern.
- **Do not start the SaaS migration or the UI redesign now.** They are late
  phases. See the plan.
- Never delete or overwrite secrets, `.env*`, Prisma migrations, generated
  `*.g.dart`, or app assets. When unsure whether to remove a file, archive it
  under `docs/archive/` instead.

## After you finish

1. Run `git status --short` again and confirm only intended files changed.
2. Run the phase's verification (analyzer / build / tests — see the plan).
3. Do **not** commit unless the user explicitly says to.

## Detailed plans

- `docs/VYNIC_PROJECT_PLAN.md` — master plan, phases, constraints, the bug.
- `plan.md` — detailed UI/design system sub-plan (used by Phases 5–6 only).
- `.claude/skills/vynic-pos-modernization/SKILL.md` — compact per-task checklist.
- `prompts/` — ready-to-run, single-focus task prompts.
