# CLAUDE.md — Vynic

Claude Code entry point. Use the shared current-state system rather than
rediscovering the monorepo.

## Route Every Normal Task

1. Inspect `git status --short`; do not touch existing changes or stashes.
2. Read `docs/agent-state/VYNIC_PROJECT_STATE.md`.
3. Use only the relevant section of
   `docs/agent-state/VYNIC_CODE_MAP.md`.
4. Open the task-specific code and nearby tests.
5. Consult `docs/agent-state/VYNIC_DECISIONS.md` only for an implicated boundary.
6. Read only the relevant governing section of
   `docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md` when needed.

The lightweight reusable version of this flow is
`.claude/skills/vynic-task-router/SKILL.md`.

```text
PROJECT_STATE -> relevant CODE_MAP -> targeted code/tests
              -> implicated DECISION -> relevant canonical rule
```

Do not automatically read all documentation, all application roots, the full
Prisma schema, broad history, or the entire canonical protocol. Broaden scope
only for an explicit audit/architecture task or when repository evidence proves
a dependency. If state conflicts with code, trust code and update state before
finishing.

## Safety

- Preserve offline-first POS/Hive operation and server-owned tenant authority.
- Keep `PlatformUser`, Staff, WebsiteUser, and Device principals separate.
- Do not add Cloud-to-LAN dependencies or new legacy callback operations.
- Keep work to the requested task; report unrelated findings instead of fixing
  them opportunistically.
- Do not manipulate stashes, secrets, `.env*`, migrations, generated files, or
  unrelated changes. Do not push or commit unless requested.
- Run focused validation, `git diff --check`, and final `git status --short`.

Maintain shared state as current facts, not history. Keep the code map
navigational and the decision index limited to durable architectural choices.
