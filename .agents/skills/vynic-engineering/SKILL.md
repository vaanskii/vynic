---
name: vynic-engineering
description: Route non-trivial Vynic engineering work across Flutter, Hive, NestJS, Prisma, React, tenancy, Edge transport, contracts, migrations, or deployment without rediscovering unrelated architecture.
---

# Vynic Engineering Router

Follow root `AGENTS.md`. Start with current shared state, not the full canonical
protocol.

## Focused Startup

1. Read `docs/agent-state/VYNIC_PROJECT_STATE.md`.
2. Read only the relevant section(s) of
   `docs/agent-state/VYNIC_CODE_MAP.md`.
3. Inspect the mapped implementation and nearby tests.
4. Consult `docs/agent-state/VYNIC_DECISIONS.md` if the task crosses an
   architectural boundary.
5. Read only relevant sections of
   `docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md` when detailed governing
   rules are needed.

Do not load every document, application root, schema section, or historical
phase for completeness. Broaden inspection only when the task is an explicit
audit/architecture exercise or targeted code proves a dependency.

## Boundaries to Check

Consider only those affected by the task:

- offline-first POS/Hive operation;
- principal and server-owned tenant authority;
- persistence and migration compatibility;
- Cloud/Edge delivery and deployed-client compatibility;
- shared contracts, secrets, configuration, and touched-stack validation.

No impact is a valid answer and is not a reason to edit an unrelated layer.

## Scope and Finish

Classify discoveries as blocker, in-scope, or deferred. Do not widen a focused
task into cleanup.

If code contradicts shared state, code wins; update the state fact before
finishing. Run validation proportional to the changed stack plus
`git diff --check` and final `git status --short`. Report only properties the
evidence proves.
