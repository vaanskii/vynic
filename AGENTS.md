# AGENTS.md — Vynic

Codex entry point for the Vynic monorepo. Keep startup context targeted.

## Normal Startup

1. Run `git status --short`; treat existing changes and stashes as user-owned.
2. Read `docs/agent-state/VYNIC_PROJECT_STATE.md`.
3. Read only the task's section(s) in
   `docs/agent-state/VYNIC_CODE_MAP.md`.
4. Inspect the task-specific implementation and nearby tests.
5. Read `docs/agent-state/VYNIC_DECISIONS.md` only when an architectural
   boundary is implicated.
6. Consult only the relevant section of
   `docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md` when governing detail is
   needed.

Use this sequence by default:

```text
state -> map -> targeted code -> tests
```

Do not re-audit completed architecture unless current code contradicts project
state, the task explicitly requests an audit, or correctness requires it.
Repository code, schema, migrations, contracts, and tests are authoritative.

## Skills Routing

Project skills live once in `.agents/skills/`; Claude Code sees them through
`.claude/skills/` symlinks. Claude Code and Codex follow the same policy in
`docs/agent-state/VYNIC_SKILL_ROUTING.md`. Read it before loading a design or
Flutter skill.

- Skills are advisory. Repository code, project state and `VYNIC_DECISIONS.md`
  win; never rewrite working architecture, switch packages, or restyle an
  incremental edit because a skill suggests it.
- Web: `frontend-design` for new pages/components or a real redesign;
  `design-taste-frontend` when premium polish matters; `image-to-code` when
  matching a screenshot/mockup; `web-design-guidelines` for UI/a11y review and
  final QA. Do not run them all on every frontend edit.
- Flutter: `flutter-build-responsive-layout` for layout,
  `flutter-fix-layout-issues` for layout errors, `flutter-add-widget-preview`,
  `flutter-add-widget-test` and `flutter-add-integration-test` after meaningful
  UI changes. Architecture, routing, HTTP, JSON and localization skills apply
  only when that layer is actually being built or changed.

## Context Budget

For a normal focused task, do not automatically read all docs, the full Prisma
schema, unrelated app roots, broad git history, every large file in a subsystem,
or the complete canonical engineering protocol. Do not regenerate an
architecture inventory or repeat an established audit.

Broader inspection is appropriate for an explicit architecture review,
cross-product refactor, tenant/security audit, modernization plan, or when
targeted evidence proves a dependency.

## Critical Invariants

- POS operation remains offline-first; Hive and the POS own live restaurant
  operation.
- Tenant authority is Device -> Venue, Staff -> Venue, Host -> VenueDomain ->
  Venue, or server-owned payment identity -> Venue. Never trust a client tenant
  ID as authority.
- `PlatformUser` is separate from restaurant Staff.
- Cloud-originated POS work is pulled by Edge. Do not add Cloud -> LAN calls or
  new operations to the frozen legacy callback fallback.
- Never hide errors behind ambiguous `null`, false success, or an empty catch.

## Scope and Safety

- Keep one requested phase/task and classify adjacent findings as blocker,
  in-scope, or deferred.
- Do not change behavior in a refactor unless explicitly requested.
- Do not manipulate an existing stash, overwrite `.env*` or secrets, rewrite
  migrations, hand-edit generated contract/model output, or push unless asked.
- Do not commit unless the user explicitly requests it.

## Finish and Maintenance

- Run validation proportional to the files changed, then `git diff --check` and
  `git status --short`.
- Update `VYNIC_PROJECT_STATE.md` only when a represented fact changed; replace
  obsolete state rather than appending a session log.
- Update `VYNIC_CODE_MAP.md` only when a high-value entry point moves, appears,
  or disappears.
- Add a decision only when it prevents repeated architectural debate.
