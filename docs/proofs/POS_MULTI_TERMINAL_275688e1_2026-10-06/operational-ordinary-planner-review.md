# Detached operational planner — independent final review

Review date: 2026-10-06. Scope: isolated candidate only.

**No remaining P1/P2 findings in the reviewed bounded implementation.** This is
not production integration or a full multi-terminal readiness approval.

## Findings closed

- Cancellation approval is enforced independently by the adapter against policy
  and enabled, authorized Staff, with the exact Staff revision retained as a read.
- Table `activeOrderId` and `reservedBy` resolve to canonical Order/Staff identities.
  Other supported business references are explicitly resolved, and missing mappings
  fail before preparation. Virtual takeaway labels bind to Order, not physical Table.
- Takeaway creation preserves no service fee and null `openedByUserId`; ordinary
  creation recomputes totals using the frozen policy and rejects added financial state.
- Adapter provenance binds the original view/control/day/policy/actor revisions,
  menu revision/fingerprint and time. Direct calls cannot bypass these checks.
- Duplicate line UUIDs, changed lifecycle/audit time, unsupported effects/settings
  and omitted required booking effects are rejected before client preparation.
- Cancellation retains the unique existing cancelled Sale image/identity and refuses
  legacy-prefix recovery; it does not create replacement financial history.
- Final follow-up: all genuine linked bookings are counted for ambiguity before
  already-cancelled rows are excluded from the changed subset. The direct-adapter
  regression passes legacy journal validation but is rejected for ambiguous links.
- Every accepted create/move/cancel includes control CAS and complete mapped
  post-images/audit effects; capacity rejection occurs before preparation.

The optional repository seam only threads nullable `serviceFeeRate` through
`decode`/`validatePlan`/`validateCancellation`/`cancellationSaleImage` to the existing
model calculation. Callers omitting it retain existing resolver behavior. Its diff
was independently compared with the original checkout; no production call site or
startup attachment was introduced by this candidate.

## Evidence and limits

Inspected corrected sources and captured logs: **92 tests passed** (20 planner,
46 isolated client, four legacy suites), and targeted analysis reported no issues.
The reviewer inspected these logs, rather than rerunning the Dart suites. Root's
independent full regression run and sealed source verification are separate evidence.

PlanningView still requires a trusted complete canonical projection supplied at
one verified cursor; production capture/admission and all remaining writer families
remain required work. Synthetic CAS and real isolated Hive lost-ACK tests do not
qualify Go, generated RPC, LAN operation, actual terminal bootstrap, physical print,
production authority, handover or rollback. Full multi-terminal status is **NOT_DONE**.

## Reviewed source SHA-256

- `apps/operations/lib/core/services/edge/operational_proof/planning_view.dart`
  `38973bfff6f373abfa575be72c0d1af962ef8c6040c6d5134f92c9052872fe17`
- `apps/operations/lib/core/services/edge/operational_proof/intent_adapter.dart`
  `143e73f8606289f399431682f338ee898eb0f6f1afaf941a9310c4cf012f76e5`
- `apps/operations/lib/core/services/edge/operational_proof/ordinary_planner.dart`
  `2b63ba76ff9864e1c92099e7e62a863a7426552d3d4b3d8019e81f5cadd1875f`
- `apps/operations/lib/core/database/repositories/order_table_mutation_repository.dart`
  `9939c54d5b6b9fc927f35ddac94548925d90fab47dea7e0446700b72ecd87a17`
- `apps/operations/test/unit/operational_ordinary_planner_test.dart`
  `bed0e69dc31b0ea4070c66c7de9f37a7ead2fc1bd716776f8b0d702f28fa172b`

## Inspected log SHA-256

- `operational-ordinary-planner-validation-test.log`
  `60a8d0de8f4033983d10a1759ae0dd92d9eb1ffe3cd956f02d0152ce5edd2b10`
- `operational-ordinary-planner-validation-analyze.log`
  `fb9dc49e62962e94398574ee31c54195c2c8f79a1f3238dc022d5934b6ecdd4c`
