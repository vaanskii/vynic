# Manager approved preview — actual implementation evidence

Generated captures, logs and machine receipts referenced below are local-only; see the [proof output policy](../README.md).

The approved Manager presentation is implemented in the actual app. The final
bounded checklist is complete: Reports directory, Audit activity composition,
Team toolbar, obligation summaries/actions, receiving/recipe forms, and connected
order detail/editor/cart. The isolated approved reference in
`experiments/manager-design-preview/` remains unchanged. Existing business services,
permissions and recovery paths remain in place. No commit, push, deployment or
live business mutation was performed. Concurrent POS/environment work was preserved.

Start with [the current gallery](index.html), the [completed checklist](closure/README.md)
and the 22 verified Library attachments (local: `closure/manifest.json`). The closure
package supersedes earlier screenshots for those changed surfaces.

## Actual route inventory

“Verified” means production widgets rendered/interacted with in the isolated
Flutter harness unless explicitly described as native. It does not imply live
server, physical-device or printer qualification.

| Route / surface | Current composition and retained capabilities | Evidence |
| --- | --- | --- |
| Dashboard | Approved four-metric revenue panel, exact preview revenue/occupancy geometry, connected operation/reservation/planning panels; real API values, freshness and attention controls | Nine viewport/theme/text configurations; matched chart and whole-dashboard comparisons; scroll-state crash regression |
| Tables / takeaways | Compact numbered cards, real zone tabs, Tables/Takeaways segments and wide order inspector; real identities and custom names | Root renders and table/merged-order/listener regressions; repair/recovery handlers retained |
| Order detail / editor / cart | Connected detail panel and totals, service-fee disclosure; centered bounded editor, category-local filter, connected cart and fixed summary/actions | Final 390/780/1440 render/interactions; 15 guarded-edit/navigation/service-fee/draft checks |
| Reservations / details / create | Connected desktop columns and phone time/name rows; real Day/All/date, New/Walk-in, guest/preorder/table/confirmation flows | Root renders, nested detail/create/table-picker and simulated keyboard checks; existing cancel/print handlers |
| Financials | Approved balance composition, provider/expense columns and connected sale rows; actual advances, payments and ledger distinctions | Root renders, ledger/negative-balance/history/planning checks |
| Payroll / obligations / histories | Centered frames, connected staff rows; remaining/reserved obligation summaries, compact cards, bottom help/Add action and secondary actual details | Phone/desktop comparison pairs; six-width nested layouts and finance workflow regressions |
| Inventory overview | Daily overview, low-stock panel and connected receipt rows; real posted/draft/payable states | Root renders and daily navigation/journey regressions |
| Stock / suppliers | Connected rows, action menus, details and editors; units, thresholds, archive/restore, supplier products and histories | Six-width pages/dialogs; supplier payment/reversal and inset coverage |
| Receiving / receipt detail | Two-step primary form matching approved composition; advanced source/document/unit fields in secondary disclosures; connected lines/totals before payment details | Matched phone/desktop reference forms/details; draft/post/cancel/payment/retry tests |
| Recipes / composition | Connected ingredient rows, yield and cost summary; category selection, conversion, product details, ingredient creation and unknown-cost states retained | Matched phone/desktop recipe editor; recipe/catalog-cost tests |
| Movement / consumption / Payments | Bounded lists/details with actual movement, consumption and payable semantics; sixth Inventory destination retained | Six-width history/details and existing workflow tests |
| Reports | Four-link directory: daily report, monthly sales, product results, staff results; existing reports and Sales open in focused bounded workspaces | Nine root cases exercise directory destinations; matched phone/desktop comparisons |
| Audit / Activity | Connected entitled Activity feed, centered filters, event details and object history; operational Audit available through secondary menu or directly without entitlement | Nine root cases exercise feed/details/filter and operational access; narrow text-scale checks; matched composition pairs with event-data distinction labeled |
| Team / Settings | Toolbar inside connected staff list; row details retain PIN/access and existing action menus. Settings is a connected directory with actual operational/session/service controls | Nine root/form cases; phone/desktop comparisons. Production developer controls remain hidden |
| Count / Saved | One Count destination with New/Saved tabs; draft selection survives switching; save refreshes Saved | Android/iOS/macOS platform journeys and existing edit/confirm/print/delete tests |
| Login / linking | Bounded Georgian remembered-venue/PIN surface with actual enrollment/session behavior | Actual-widget renders; final native bundle confirmed at PIN boundary |
| Notifications / freshness / retained operations | Shared presentation with cached/unavailable/pending/error states visible | Render and focused data-state tests; native notification delivery not claimed |

Unsupported preview choices were not converted into new business functions.
Dashboard takeaway count/forecast remains unavailable where the API has no field;
actual Takeaways still provides its own list. Real reservation dates, zones,
settings options, inventory Payments, permissions and advanced operational fields
remain. Order/cart, repair/recovery and some advanced form states have no complete
one-to-one reference; they use shared components. Whole-app pixel identity is not
claimed, and no requested composition gap is left as a theme-only substitute.

## Data and crash fixes

Dashboard outflows/balance read the existing financial response only when its
business date matches. Missing, malformed and mismatched data remains unavailable;
production code contains no fixture totals or forecast. Obligation summaries use
exact decimal aggregation of actual server cycle values; malformed amounts do not
silently become zero.

The supplied Manager `double` to `bool` crash was reproduced as a PageStorage
collision between scrolling and expansion state. Distinct keys and isolated
expansion storage fix it, including the deeper recipe/receiving editors. Original
failure evidence remains in `validation/dashboard-crash-before.log` and passing
reproduction in `validation/manager-dashboard-fixed-final.log`.

Manager connection feedback now waits for an active authenticated monitoring
session, preventing a false outage at the remembered-venue PIN screen. Active
session loss still warns; POS feedback is unchanged. The original read-only health
check succeeded without restarting services or changing configuration.

## Final verification

Current logs are in closure/validation (local: `closure/validation/summary.json`):

- Broad actual-widget render/navigation suite: 28 passes; final order detail/editor/
  cart at three sizes: 3 passes.
- Changed workflow regressions: 102 passes. Final editor guarded-flow rerun:
  15 passes, overlapping the 102. Five retained-workflow files pass 67 additional
  checks: 169 unique workflow checks across nine files.
- Reference suite: 14 passes; receiving reference refresh: 2 overlapping passes.
- Analysis: no issues. Final macOS/Android debug and unsigned arm64 iOS Simulator
  builds: successful.

Sizes cover 390-pixel phone, 834-pixel tablet, 780-pixel narrow desktop,
1440/1728/1920 desktops, phone/desktop dark mode, and 320 pixels at 130% text.
The harness uses production widgets, a loopback fixture server and temporary
storage. It labels synthetic data and simulates keyboard insets. No screenshot is
image-generation artwork or proof of a physical keyboard/live business mutation.

## Native launch boundary

The final Manager bundle at
`apps/operations/.dart_tool/vynic-dev/manager/apps/operations/build/macos/Build/Products/Debug/Vynic Manager.app`
is running as PID 26303, started 2026-10-17 04:24:10 local (+04:00), after the final
build. Accessibility inspection confirmed the remembered-venue PIN screen with
zero digits entered. The preceding process's PIN screen was visually checked.
Final identity/hashes are recorded in `closure/validation/`.

Authenticated navigation in that final process is **pending the user's PIN**.
No PIN was guessed and no credentials were read or changed. The preceding quit's
timeout was resolved by confirming that process had exited; the final launch is
confirmed. Earlier authenticated observations belong to a superseded process and
are not used to qualify the final build. Windows Manager, physical device/signing,
native printing and live financial/inventory writes remain unverified.

iOS used the existing isolated checkout with scoped Manager sources refreshed and
explicit arm64/deployment-target/no-signing arguments. Repository iOS targets were
not changed. macOS/Android use the actual development stage linked to repo `lib`.

## Evidence locations

- `closure/`: current checklist, 22 labeled PNGs, verified native Library IDs,
  comparisons, logs, source/build hashes and gallery.
- `library-followup-index.json`: consolidated attachment index; updated identities
  retain their Library history, and earlier unchanged screenshots remain listed.
- `comparison/`: chart and Dashboard comparisons; `nested-comparison/`, `followup/`
  and `final/`: preceding passes. These are historical where closure replaces them.
- `before/`: actual previous Manager implementation, not a fabricated mockup.
- `closure/validation/preceding-pass-readme.md`: preserved earlier findings and
  limitations, superseded by this completed checklist.
- `experiments/manager-design-preview/`: original research, feature inventory,
  navigable isolated prototype and skill-source recommendations.
