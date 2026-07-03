# Prompt — Phase 3: data-driven tables & zones

Only after Phases 1–2. Removes hardcoded floor-plan logic. Behavior-preserving for
the current restaurant.

---

Replace Vynic's hardcoded table/floor logic with a data-driven model. Read
`docs/VYNIC_PROJECT_PLAN.md` §3 and §6 (Phase 3) first.

Today the floor plan is compiled in: `'first'`/`'second'`, `Table N` vs
`VIP Zone N`, and the `tableNumber > 10 => second/VIP` arithmetic, duplicated across
~11 files.

Task:
1. Introduce a data model: `Zone { id, name }` and
   `Table { id, zoneId, label, capacity }`. Seed it from the current restaurant's
   real layout so behavior is unchanged for this venue.
2. Centralize any remaining table-code encode/decode into ONE utility (there's
   duplication today). Prefer removing the `> 10` arithmetic entirely; keep a single
   compatibility shim only if Hive-stored data requires it, and document why.
3. Update call sites to use the model instead of magic numbers/strings, one area at a
   time (tables → reservations → orders → dashboards).
4. Do not add tenancy/`venueId` here — that's Phase 7. Single-venue only.

Verify: `flutter analyze`, build, tests; confirm the current floor plan renders and
behaves exactly as before (same tables, same VIP grouping). `git status --short`
before/after. Do not commit unless I say so.
