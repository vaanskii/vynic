---
name: vynic-task-router
description: Route focused Vynic engineering tasks to compact shared state and only the relevant subsystem code, tests, decisions, and governing rules.
---

# Vynic Task Router

Use this skill to reach implementation without reloading the whole project.

## Startup

1. Identify the subsystem named by the task.
2. Read `docs/agent-state/VYNIC_PROJECT_STATE.md`.
3. Read only the matching section(s) of
   `docs/agent-state/VYNIC_CODE_MAP.md`.
4. Open the task-specific implementation and nearby tests.
5. Read `docs/agent-state/VYNIC_DECISIONS.md` only if an architectural boundary
   is implicated.
6. Consult only relevant portions of
   `docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md` when governing detail is
   needed.

```text
state -> map -> targeted code -> tests
```

Do not rediscover completed phases without contradictory evidence. Do not read
unrelated application roots merely to be comprehensive. Expand scope only when
repository evidence proves a dependency. Prefer targeted `rg` from a mapped
entry point over broad recursive exploration.

## Task Routing

| Task words | Code-map sections |
| --- | --- |
| money, close, advance | Money / Closing; Sales / Reports |
| report, sales | Sales / Reports; Money / Closing if figures change |
| edge, command, transport | Edge Transport — Backend; Edge Transport — POS |
| device, enrollment | Device Enrollment; relevant Edge section |
| sync, audit | Audit Sync; POS / Operations Shell or Prisma as needed |
| manager | Manager App; relevant backend domain |
| reservation, booking | Reservations; Venue Website if public |
| website, host, domain | Venue Website; Platform Control Plane if managed |
| platform, admin | Platform Control Plane; Platform Admin UI |
| printing | Printing; Edge only for remote printing |
| schema, tenancy | Prisma / Database; implicated app; tenant decision |
| contract | Shared Contracts; producer and consumer only |

## Context Budget

For normal feature/fix work, do not automatically:

- read all docs or the full canonical protocol;
- read the full Prisma schema when the data model is untouched;
- inspect `venue-web` for a POS-only task or Platform Admin for an isolated
  Flutter change;
- inspect broad history, rerun established audits, or open every large file in
  a subsystem.

Broader inspection is allowed for an explicit architecture review, deep audit,
cross-product refactor, tenant/security audit, or modernization planning.

## Contradictions and Maintenance

If current code clearly contradicts project state, trust code, solve from the
implementation, and update `VYNIC_PROJECT_STATE.md` before finishing.

Update the state only for changed represented facts, the code map only for
moved/new/removed high-value entry points, and the decision index only for a
durable choice that prevents repeated debate. Never append session summaries.
