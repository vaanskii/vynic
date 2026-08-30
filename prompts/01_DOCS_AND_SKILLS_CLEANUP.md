# Prompt — Phase 0: docs & skills cleanup

Use to maintain the guidance system (docs, AGENTS.md, skill, prompts). **No business
code.**

---

Task: tidy Vynic's guidance/documentation only. Do not edit Flutter or NestJS source.

1. Run `git status --short`.
2. Inspect: `AGENTS.md`, `docs/VYNIC_PROJECT_PLAN.md`,
   `.claude/skills/vynic-pos-modernization/SKILL.md`, `prompts/*.md`,
   `docs/UI_PLAN.md`, `apps/backend/CLAUDE.md`, `apps/operations/docs/**`,
   `apps/operations/docs/archive/**`.
3. Report a table before changing anything:

   | File | Action (keep/update/archive/create) | Reason | Risk |
   | ---- | ------ | ------ | ---- |

4. Rules:
   - Never delete secrets, `.env*`, migrations, source, or generated assets.
   - Archive (via `git mv` into `docs/archive/`), don't delete, when a doc is stale
     but historically useful.
   - Only delete docs that are outright misleading or exact duplicates already
     archived.
   - Keep skills compact — a skill should point to `docs/VYNIC_PROJECT_PLAN.md`, not
     restate it. If a skill grew large, trim it.
   - Keep long context in `docs/VYNIC_PROJECT_PLAN.md`, not in every skill/prompt.
5. After changes: `git status --short`, list what moved/created and why. Do not
   commit unless I say so.
