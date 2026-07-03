# Prompt — Start a new Vynic session

Use this at the beginning of any Vynic work session to orient the agent safely.

---

You are working on **Vynic**, a restaurant POS (`pos_app_client/` Flutter +
`pos_app_server/` NestJS). Currently single-restaurant; a phased modernization is
planned but mostly not started.

Do this before proposing any change:

1. Run `git status --short` and tell me what is already dirty.
2. Read `AGENTS.md`, then `docs/VYNIC_PROJECT_PLAN.md`.
3. Tell me which **single phase** (0–9) my request belongs to, and confirm earlier
   phases it depends on are done.
4. If my request spans multiple phases or is a broad refactor, stop and propose how
   to split it. Do not start.

Hard rules for the whole session:
- One phase at a time; small changes; small commits.
- No behavior change unless the task explicitly is one.
- Never swallow errors behind `null` or empty `catch`.
- Do not start SaaS (Phases 7–8) or the UI redesign (Phases 5–6) unless I say so.
- Never touch secrets, `.env*`, Prisma migrations, `*.g.dart`, or assets.
- Do not commit unless I explicitly say "commit".

Wait for my confirmation of the phase before editing code.
