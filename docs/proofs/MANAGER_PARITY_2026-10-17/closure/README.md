# Manager approved-composition checklist — completed

This package records the final bounded presentation pass requested after design
approval. The production Manager widgets are rendered with explicitly synthetic
fixtures; the isolated approved preview remains unchanged. No commit, push,
deployment or live business mutation was performed.

Open [the screenshot gallery](index.html). The attachment manifest (local: `manifest.json`)
contains the exact 22 native Library file IDs, versions, local hashes and dimensions.
All 22 Library results were read back at their exact version and byte count.

## Completed composition changes

| Area | Final presentation | Existing capabilities retained |
| --- | --- | --- |
| Reports | Four-link directory for daily report, monthly sales, product results and staff results | Existing Report/Sales data, periods, filters and detail workspaces open in bounded dialogs |
| Audit | Connected activity feed, centered filters, event details and object history | Advanced Audit entitlement; operational daily Audit is available through the secondary menu, and remains the direct view without that entitlement |
| Team | Toolbar inside the connected list, compact name/role rows, responsive Add action | PIN/access details in the row detail; existing name, PIN, role and deletion actions |
| Obligations | Remaining/reserved summaries above the compact cards; help and Add action below; reserve/payment hierarchy | Actual cycle amounts, history, schedule, paid/coverage data and edit controls in secondary details; malformed amounts remain unavailable |
| Receiving | Approved two-step composition, supplier/date pairing, compact item fields, review summary and payment section | Source/document metadata, unit/price basis, conversion, invoice, notes, partial payment, due dates, draft/post/cancel/retry semantics |
| Receipt detail | Document metadata, connected lines and totals precede payment information | Actual payments, movements, supplier/document identity and cancellation state |
| Recipes | Connected ingredient rows, yield and current-cost summary, restrained Add action | Unit/conversion editors, product details, disable/save, direct-drink mode, ingredient creation and unknown-cost state |
| Order detail/editor | Connected detail panel, bounded 760-pixel editor, category-local menu filter, compact cart and fixed summary/action area | Service-fee details, actual totals and comments, categories/variants, quantity edits, print/receipt/cancel, retained guarded edit requests and recovery |

The editor/cart, operational Audit, retry/recovery states and several advanced
fields have no complete one-to-one state in the approved prototype. They use the
same shared composition while preserving the real workflow. This closes the
specified checklist; it does not claim whole-app pixel identity or invent
prototype-only business functions.

## Render and interaction evidence

- The broad actual-widget run passes all 28 cases: nine root viewport/theme/text
  configurations and 19 nested/navigation/state cases. The final order workspace
  is separately rendered and interacted with at 390, 780 and 1440 pixels (3 passes).
- Reference suite: 14 passes. Receiving's two reference cases were refreshed after
  clearing focus and scrolling to the top, so comparisons use the intended state.
- Changed workflow regression suite: 102 passes. The final order editor change
  additionally passes all 15 guarded navigation, service-fee and retained-draft
  checks. Five additional retained-workflow files pass 67 checks, making 169
  unique workflow checks across nine files. The 15 order checks overlap the 102
  and must not be added again.
- Final analysis reports no issues. The final macOS and Android debug builds and
  unsigned arm64 iOS Simulator build all succeed. Exact logs and all
  retained-workflow results are listed in validation summary (local: `validation/summary.json`).

Root sizes include phone 390×844, tablet 834×1112, narrow desktop 780×900,
desktop 1440×900, 1728×1117 and 1920×1080, plus phone/desktop dark mode and
320×900 at 130% text. Nested forms include simulated keyboard insets. These are
rendered Flutter widgets, not image-generation artwork, physical keyboard tests
or authenticated server end-to-end tests. The harness restricts HTTP to its own
loopback fixtures and uses temporary local storage.

The comparisons use matching viewport dimensions. Primary reference values are
matched where supported; the Activity pair explicitly identifies its different
actual supported event records. Operational fields, number formatting, dialog
frames and additional controls remain visible and are not hidden to manufacture
pixel equality. All exported images have a synthetic-data label.

## Final native boundary

The exact final Manager development bundle is running as PID 26303, launched
2026-10-17 at 04:24:10 local (+04:00), after the final build. Its remembered-venue
Georgian PIN screen was confirmed through native accessibility inspection, with
zero PIN digits entered. The preceding build's PIN screen was visually inspected.
The final process identity is recorded in native-launch.json (local: `validation/native-launch.json`).

Authenticated navigation in this final native process is **pending**, because
the user's PIN is required. It was not denied, no PIN was guessed, and no
credentials were read or changed. A timed-out quit of the preceding process was
resolved by checking that it had exited before launching the final bundle.
Native printing, physical-device installation and live financial/inventory writes
are not qualified by this package.

The macOS/Android stage links directly to repository `lib`. iOS uses the existing
isolated Manager checkout with the final scoped source refreshed and explicit
arm64, deployment-target and no-signing build arguments; repository iOS targets
were not changed. Source and artifact hashes are in build identity (local: `validation/build-identity.json`).
