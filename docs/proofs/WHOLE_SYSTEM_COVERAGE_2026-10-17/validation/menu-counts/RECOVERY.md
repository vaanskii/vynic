# Menu and counted-menu recovery

This is the menu/count slice of the whole-system recovery. It is not a whole-product readiness claim. Existing unrelated work and the original October 17 baseline were preserved.

## Implemented and verified

| Path | Defect and resulting behavior | Evidence |
| --- | --- | --- |
| Owner `CatalogEditor.tsx` | An accepted create followed by a failed catalog reload cleared its retry identity while keeping the form open. Clearing now happens after the reload succeeds, so retry sends the same entity ID and mutation ID. | `catalog-editor-recovery-before.log` reproduces differing IDs; `catalog-editor-recovery-after.log`: 7 passing tests. |
| Manager `mobile_calculator_screen.dart` | Categories containing both direct products and subcategories hid all direct products. The existing subcategory tab strip now includes the category's direct products first. | `flutter-recovery-before.log` reproduces zero direct-product rows; final widget suite verifies both branches are selectable. |
| Manager calculator and `mobile_menu_pin_sheet.dart` | Adding more of a different variant reused the first variant's quantity. The sheet and calculator now use the selected variant's own quantity. | `flutter-variant-before.log` reproduces the wrong displayed total; final widget suite verifies small 2 / large 4 becomes small 2 / large 5. |
| Manager calculator | Editing a legacy count skipped lines that no longer matched the live menu; ambiguous same-name/price matches also guessed a live identity. Unmatched and ambiguous lines now remain frozen manual lines. Saved names, prices, quantities and notes survive editing. A visible warning explains retained saved data. | `flutter-retained-count-before.log` reproduces the absent historical line; final widget suite verifies the complete two-line payload and notes. |
| Manager selections and count fee | The saved patches carry catalog/variant identities through newly selected reservation/takeaway lines, retain frozen/manual selections on reopen, and pass the selected service fee through save and edit reopen. | Five final calculator widget tests and focused analysis. |

## Current validation

- `flutter-recovery-after.log`: **5/5 widget tests pass**, using temporary private Hive boxes and a fully mocked HTTP client. The configured origin is loopback; the repository test harness rejects actual HTTP. Quantity-pad inputs are synthetic product quantities, not authentication PINs.
- `catalog-editor-recovery-after.log`: **7/7 owner editor tests pass**.
- `flutter-identity-regressions.log`: **82/82 existing tests pass** across `menu_line_identity_test`, `takeaway_order_source_test`, `order_item_transfer_test`, `order_item_transfer_apply_test`, and `reservation_audit_test`. Synthetic audit transmission attempts are rejected by the existing no-external-HTTP harness. These are regression proofs, not live sync evidence.
- `flutter-recovery-analyze.log`: **9 focused files, no issues** (calculator, counted menus, reservation/create-takeaway screens, takeaway controller/model/widgets, quantity sheet, new widget tests).
- Scoped `git diff --check` passes.
- Full Platform/backend builds, PostgreSQL execution of `counted-menu-write.integration.spec.ts`, and current native qualification are owned by the parent recovery and must be read from its final receipts. They were not run by this menu slice.

## Source audit/support matrix

| Surface | Audited source / implemented support | Boundary or remaining limit |
| --- | --- | --- |
| Canonical catalog | Owner mutation IDs and entity IDs; per-node revisions; POS local-first stable identities and existing canonical projection/queue architecture are preserved. | This slice does not repeat the full canonical-menu/restart rollout qualification. |
| Manager menu selection | Newly selected item/variant IDs remain distinct even when names and prices match. Reservation and takeaway reopen/request adapters retain keys, names, prices and IDs. | Legacy lines without trustworthy IDs remain manual snapshots; no guessed IDs or schema changes. |
| Cloud counted menus | `mobile-menu.service.ts` nested create and nested header/item replacement are atomic Prisma writes. Existing guarded HTTP/PG spec covers custom-rate persistence, failed second-line rollback, cross-Venue isolation, and missing update. | PG outcomes must come from the parent's disposable-database run. The legacy counted-menu schema still stores frozen names, quantities, prices and comments rather than Menu IDs. |
| Count edit/service fee | Selected custom rate travels in save/update payloads; saved include/rate settings reopen unchanged while the Venue supports the feature. Retained unknown lines and notes survive edits. | Explicit re-selection uses current catalog data. Existing feature availability remains authoritative. |
| POS estimates/packages | POS local Hive estimates/Packages use their existing local operation and synchronization boundaries. | They are not the Cloud counted-menu draft model; no new cross-product synchronization contract was invented. |
| Website menu variants/presentation | Covered by the website recovery owner. | This slice makes no website qualification claim. |

## Changed files in this recovery slice

- `apps/platform-web/src/customer/CatalogEditor.tsx`
- `apps/platform-web/src/test/catalog-editor.test.tsx`
- `apps/operations/lib/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart`
- `apps/operations/lib/apps/mobile_app/presentation/widgets/mobile_menu_pin_sheet.dart`
- `apps/operations/test/widget/manager_menu_selection_test.dart` (new)

The earlier saved propagation/atomicity patches were inspected rather than overwritten. No branding, printing, credentials, application IDs, permissions, data migrations, live data, commit, push, deployment, or ordinary app/service restart was changed.
