---
name: vynic-engineering
description: Use for non-trivial engineering work anywhere in the Vynic monorepo across Flutter, Hive, NestJS, Prisma, PostgreSQL, React, tenancy, authentication, Edge transport, contracts, migrations, or deployment. Skip isolated text-only or cosmetic changes that cannot affect architecture or runtime behavior.
---

# Vynic Engineering

Use this skill for non-trivial engineering work anywhere in the Vynic monorepo.

## Canonical Protocol

Before making changes, read:

`docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md`

That document is the authoritative cross-stack engineering protocol.

Do not duplicate its architecture here.

---

## When to Use This Skill

Use for tasks involving one or more of:

- Flutter / POS / Manager
- Hive persistence
- NestJS
- Prisma
- PostgreSQL
- React / Vite
- Platform Admin
- Venue website
- authentication / authorization
- Organization / Venue tenancy
- Plans / Features / entitlements
- Cloud ↔ Edge transport
- Device identity
- shared contracts
- migrations
- deployment
- production configuration
- multi-stack bug fixes or refactors

For trivial text-only or isolated cosmetic changes, the full protocol may not need to be re-read if it cannot affect architecture or runtime behaviour.

---

## Start-of-Task Checklist

Before editing:

1. Inspect Git state.
2. Read the canonical engineering protocol.
3. Read subsystem-specific docs.
4. Trace the actual current implementation.
5. Identify the authoritative data owner.
6. Identify the authenticated principal and tenant authority.
7. Identify all callers and consumers.
8. Check persistence and migration implications.
9. Check backward compatibility with existing POS installations.
10. Define the validation required for every touched stack.

---

## Vynic Safety Check

Before implementing, explicitly consider whether the change affects:

- offline-first POS operation;
- Device → Venue identity;
- Staff → Venue identity;
- Host → VenueDomain → Venue resolution;
- PlatformUser cross-tenant authority;
- entitlements;
- Cloud ↔ Edge delivery;
- Hive persistence;
- Prisma/PostgreSQL data;
- shared contracts;
- secrets;
- current deployed compatibility.

If none are affected, do not modify them unnecessarily.

---

## Scope Rule

Classify discoveries:

- `BLOCKER`
- `IN-SCOPE`
- `DEFERRED`

Only fix blockers and requested/in-scope work.

Do not convert a focused task into a broad cleanup.

---

## Implementation Rule

Prefer:

- authoritative existing services;
- explicit ownership;
- backward-compatible evolution;
- additive/data-safe migrations;
- generated shared contracts where justified;
- idempotent Edge behaviour;
- centralized API/auth clients;
- focused commits.

Avoid:

- duplicate authority logic;
- arbitrary client-controlled `venueId`;
- direct Cloud → private LAN dependencies;
- fake frontend authority;
- plaintext secret storage;
- premature distributed infrastructure;
- unrelated refactors.

---

## Completion Checklist

Before declaring the task complete:

1. Run validation for every changed stack.
2. Run `git diff --check`.
3. Inspect final `git status --short`.
4. Verify only intended files changed.
5. Report:
   - implementation;
   - architecture impact;
   - security/tenant impact;
   - environment changes;
   - migrations;
   - tests/builds actually run;
   - manual user actions;
   - deferred findings;
   - recommended next step.

Never claim more than the evidence proves.
