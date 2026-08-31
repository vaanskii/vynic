# CLAUDE.md — Vynic

Instructions for Claude Code when working in the Vynic repository.

## Required Engineering Protocol

Before any non-trivial Vynic engineering task, read and follow:

`docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md`

This is the canonical repository-wide engineering policy for Vynic.

Do not duplicate or reinterpret its architecture rules here.

Repository code, current Prisma schema, migrations, tests, generated contracts, and current architecture documentation are the source of truth.

---

## Before Editing

Run:

```bash
git status --short
git stash list
git log --oneline --decorate -50
```

Do not manipulate any pre-existing stash.

Inspect the actual implementation relevant to the task before editing.

For substantial work, establish:

- current state;
- target state;
- affected applications/layers;
- authentication and tenant authority;
- persistence/migration impact;
- compatibility requirements;
- validation plan;
- explicit non-goals.

---

## Scope Discipline

Work on one requested task or migration phase at a time.

Classify discoveries as:

- `BLOCKER`
- `IN-SCOPE`
- `DEFERRED`

Do not opportunistically fix unrelated findings.

If a prompt conflicts with repository reality, investigate the repository and report the conflict rather than blindly implementing the prompt.

---

## Task-Specific Documentation

Read the relevant documents under `docs/` for the subsystem being changed.

Examples:

- Cloud / Edge → `docs/CLOUD_EDGE_TRANSPORT.md`
- Platform Control Plane → `docs/PLATFORM_CONTROL_PLANE.md`
- Platform API → `docs/PLATFORM_CONTROL_PLANE_API.md`
- Product / entitlements → `docs/PRODUCT_ENTITLEMENTS.md`
- tenancy → relevant tenancy documents under `docs/`
- payment integrations → `docs/PAYMENT_INTEGRATIONS.md`
- Vynic roadmap → `docs/VYNIC_ROADMAP.md`

Do not assume every older document is current. Verify important claims against code, migrations, and tests.

---

## Git

Use focused commits when the task requests or benefits from checkpointed work.

Do not amend unrelated history.

Do not push unless explicitly requested.

Never overwrite the user's `.env`, secrets, unrelated work, or pre-existing migrations.

---

## Validation

Run the validation required by every stack actually touched.

Do not claim a platform, integration, migration, or deployment was verified unless it actually was.

At completion run:

```bash
git status --short
git diff --check
```

and report any manual actions or environment changes the user still needs to perform.
