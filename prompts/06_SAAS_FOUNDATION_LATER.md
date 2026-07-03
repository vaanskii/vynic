# Prompt — Phases 7–8: SaaS foundation (LATER — do not start early)

Only after Phases 1–6 are done and stable. This begins multi-tenancy. Do NOT run this
prompt as a side effect of other work.

---

Lay Vynic's SaaS foundation. Read `docs/VYNIC_PROJECT_PLAN.md` §4 and §6 (Phases
7–8) first. Confirm with me that Phases 1–6 are complete before starting.

**Phase 7 — tenancy (server-first):**
1. Add a `Venue` (tenant) model in `pos_app_server/prisma/schema.prisma` via a proper
   Prisma migration. Do not hand-edit existing migrations.
2. Add `venueId` to every POS/website row that needs isolation. Fix globally-unique
   keys that break per-venue (e.g. `posOrderId` — scope it per venue).
3. Scope all queries, Socket.IO rooms, and notifications by `venueId`.
4. Per-venue sync credentials, replacing the single shared POS sync key.
5. Plan a data backfill for the existing single restaurant into one seed venue.

**Phase 8 — feature flags / entitlements:**
1. Server: a per-venue entitlements record (e.g. `VenueFeature { venueId, feature,
   enabled }`), synced to the client at login.
2. Client: a single gate — `Features.has(Feature.xReport)` etc. — replacing scattered
   role/feature checks. Gate the paid custom modules (calculator, X-report, kitchen
   check, takeaway, website reservations).

Hard rules:
- Migrations only via Prisma; never delete/edit applied migrations.
- Keep the existing single restaurant working throughout (it becomes venue #1).
- Small, reviewable steps; one concern per commit; verify server build/lint/test and
  client build after each. Do not commit unless I say so.
- Do NOT onboard a second venue until this is stable (that's Phase 9).
