# Manager retained-item candidate — independent source review

Review date: 2026-10-06. **No P1/P2 findings in the reviewed detached scope.**
This is not production integration or full multi-terminal qualification.

The typed command permits quantity changes/removals of existing itemKey/lineUuid
pairs only. Prices and metadata come from the captured Order. New keys, changed
UUIDs, duplicate keys, POS origin, status/fee/ownership changes and no-op replacement
are rejected. The adapter repeats source/Staff authority checks and regenerates the
complete draft instead of accepting caller-supplied post-images.

Existing model arithmetic uses the frozen fee while preserving custom-rate
precedence and purchased package/advance state. Existing quantity-diff audit
semantics are retained: exact prefix and sequence, frozen new timestamps, no
invented GlobalAudit/MoneyAudit. The immutable AUDIT effect is evidence of the
already committed report events and must never replay-append them to that report.

The adapter validates canonical Order/Table/report/control links, full Order/Table
scan dependencies and referenced entities, then CAS-writes Order, report and
control with an exact caller result. Malformed historical UUIDs, unsupported
complex report-detail schemas, unresolved links and capacity/overflow fail closed.

## Inspected evidence

Captured selected regression: **143 tests passed**; targeted analysis: no issues.
Includes real local Hive Manager ORDER_UPDATE parity (only legacy regenerated line
UUIDs and new wall-clock fields explicitly normalized), pure calculation checks,
actual ready-client rejection without frame/transport changes, synthetic three
client contention and isolated Hive lost-ACK recovery. The reviewer inspected
source and logs; these are not a separate reviewer rerun of the Dart suite.

All ten existing files in the author's before-hash manifest remain byte-identical,
including ordinary planners, proof client/domain, Order model and fee seam. Only
the two new pure sources and new test comprise this candidate. No production
imports/startup/Cloud ingress or printer attachment were found.

## Remaining gates

Authenticated Manager-origin capture cannot be established by a caller source tag.
A trusted complete canonical planning view, remote ingress/ACK integration,
new-item catalog quotes, POS modification PRINT effects, status/fee writers and
all other required domains remain pending. Historical complex report shapes and
no-op replacements are explicitly outside this slice. Scripted tests do not prove
Go/RPC/LAN, real terminal bootstrap, physical printing, handover or rollback.
Full multi-terminal status remains **NOT_DONE**.

## Reviewed source SHA-256

- `apps/operations/lib/core/services/edge/operational_proof/manager_items_planner.dart`
  `86635d11eed2929e8a7fd454a2d0485fe99c7ef52cfe86c66037700c41e635fd`
- `apps/operations/lib/core/services/edge/operational_proof/manager_items_adapter.dart`
  `34f1a77a254d32832003094d156022a1f30764bb9b2f019322d48fea716a2ad2`
- `apps/operations/test/unit/operational_manager_items_test.dart`
  `3b4fee3bc637b053afecc07c37bfc5a29a87991b548a00effab15ffcc1f44a5d`

## Inspected log SHA-256

- `operational-manager-items-validation-test.log`
  `f33994b3e491f54adb7ddf5d6e0ab6ae0d09633ee4dfc21e92fd6c4dbea6b551`
- `operational-manager-items-validation-analyze.log`
  `3d1b8e5f21c3a232381c958c2022d476bb93f386ca5eb05448d071bf05ea33e7`
