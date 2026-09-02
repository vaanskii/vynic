# Venue Policy — implementation plan

**Status:** analysis only. Nothing here is built.

The owner's requirement: Vankisi-specific and advanced operational
capabilities must not sit in ordinary POS settings as enable/disable toggles.
They should be controlled per Venue from the Vynic Platform Admin, cached by
the POS so the restaurant keeps working offline.

Related: [MONEY_INTEGRITY.md](./MONEY_INTEGRITY.md),
[PRODUCT_ENTITLEMENTS.md](./PRODUCT_ENTITLEMENTS.md),
[PLATFORM_CONTROL_PLANE.md](./PLATFORM_CONTROL_PLANE.md)

---

## 1. Why this is not the entitlement resolver

`VenueEntitlementsService.effectiveFeatures` answers *may this Venue use this
product surface* — `POS`, `WEBSITE`, `MANAGER_APP`. It is commercial packaging.

Operational policy answers a different question: *may this Venue's staff do
this thing, and how does this Venue's paperwork read*. Overloading `Feature`
keys with it would mean a commercial plan change silently altering how a
receipt prints. Expect a separate `VenuePolicy` record with its own resolver,
following the authority shape the engineering protocol already states:

```text
Cloud administrative authority
        ↓
complete POS local/offline cache
```

## 2. Two rules the model must keep

1. **No policy may switch off an audit record.** A capability can be disabled;
   its use can never be made invisible.
2. **No policy may change what a report or a receipt *asserts*.** A policy may
   change what a document *shows*. It may not make the document claim
   something that did not happen, and the stored accounting must never depend
   on it.

## 3. The inventory

Every row is a capability that is today either always-on or a local POS
setting.

### 3.1 `close.internalClosureEnabled`

| | |
| --- | --- |
| Current call site | `CloseTableTransaction.run(isFiscal: false)` via `_startNonFiscalClosureFlow`; visibility gated only by `user.canCloseTablesNonFiscal` |
| Current default | Always available to managers |
| Local-only? | Yes — no setting at all, it is unconditional code |
| Proposed key | `close.internalClosureEnabled` (bool), plus `close.internalClosureReasons` (enumerated list) |
| Owner | **Platform Admin.** Whether a venue may close a table outside revenue is a product/commercial decision, not a floor-manager one |
| POS must cache | The flag and the reason list, so the button and its reason picker work offline |

Follow-up beyond the flag: replace the single unnamed bucket with enumerated,
approver-attributed closure reasons reported as their own line.

### 3.2 `receipt.serviceFeeLine`

| | |
| --- | --- |
| Current call site | `receiptShowServiceFeeLine` in the POS settings box → `PrinterService._shouldShowServiceFeeLine`, `ReceiptPdfGenerator` |
| Current default | Visible |
| Local-only? | Yes, a POS admin switch. Changes are audited since Phase 1A (`RECEIPT_SERVICE_FEE_POLICY_CHANGED`) |
| Proposed key | `receipt.serviceFeeLine` = `SHOW` \| `HIDE` |
| Owner | **Platform Admin** |
| POS must cache | The enum; printing must never wait on Cloud |

### 3.3 `receipt.closeCheckServiceFeeLine`

| | |
| --- | --- |
| Current call site | `closeReceiptShowServiceFeeLine` → `PrinterService._shouldShowCloseReceiptServiceFeeLine` |
| Current default | Hidden — how the closing check has always printed |
| Local-only? | Yes |
| Proposed key | `receipt.closeCheckServiceFeeLine` = `SHOW` \| `HIDE` |
| Owner | **Platform Admin** |
| POS must cache | The enum |

### 3.4 `receipt.advanceDisplay` — requested during Phase 1B

| | |
| --- | --- |
| Current call site | `_buildFinalReceiptLines` / `PrinterService.printReceiptInBackground` in the close path; the in-service receipt passes the advance as `discountAmount` |
| Current default | The closing check prints the amount collected at the table |
| Local-only? | Yes — it is not a setting at all today, it is hardcoded behaviour |
| Proposed key | `receipt.advanceDisplay` = `FULL_BREAKDOWN` \| `BALANCE_ONLY` |
| Owner | **Platform Admin** |
| POS must cache | The enum, so the printer never waits on Cloud |

Semantics:

- `FULL_BREAKDOWN` — gross order total, the advance deducted, and the remaining
  amount paid now.
- `BALANCE_ONLY` — only the remaining amount due/paid at close.

**The accounting must never depend on this.** Phase 1B already guarantees that:
`ClosureMoney` stores gross, advance applied and collected-now as three
separate persisted fields, and the sale's payment breakdown carries the
`advance` line whichever way the receipt is printed. The policy chooses which
of those stored values a printed document shows; it cannot change any of them.
A test asserting that both settings produce identical sale records should land
with the implementation.

No legal or fiscal claim is made here about when either presentation is
appropriate. That is the operator's and their accountant's call.

### 3.5 `order.manualAdjustmentEnabled`

| | |
| --- | --- |
| Current call site | `Order.setManualAdjustment` via `_showManualAdjustmentDialog`, gated only by `PosPermission.applyDiscount` |
| Current default | Available to managers and supervisors |
| Local-only? | Yes — no setting, only the permission |
| Proposed key | `order.manualAdjustmentEnabled` (bool) plus `order.manualAdjustmentMaxAbs` (amount) |
| Owner | **Platform Admin** for the capability; a per-shift limit could later be Restaurant Backoffice |
| POS must cache | Both, and enforce the bound locally |

### 3.6 `order.advanceEnabled`

| | |
| --- | --- |
| Current call site | `Order.setAdvance` + `SalesRepository.recordAdvanceReceipt` via the ავანსი dialog |
| Current default | Available to managers and supervisors |
| Local-only? | Yes |
| Proposed key | `order.advanceEnabled` (bool) |
| Owner | **Platform Admin** |
| POS must cache | The flag |

### 3.7 `repair.salesRepairEnabled` and `repair.backdateEnabled`

| | |
| --- | --- |
| Current call site | `cancelSaleRecord(allowHistorical:)` and `setCurrentDate(allowBackdate:)`, gated on `DeveloperScope.salesRepair` / `DeveloperScope.backdate` |
| Current default | Off — the support token must carry the scope |
| Local-only? | The scope is offline-verified from a signed token, which is the right shape already |
| Proposed key | Possibly none. The developer-scope model is a better fit than a Venue policy |
| Owner | **Neither.** Support access, not venue configuration |
| POS must cache | Nothing new |

Recorded here for completeness. The Venue Policy phase should decide whether
either is ever venue-grantable; the default answer should be no.

### 3.8 `report.costAssumptionsEnabled`

| | |
| --- | --- |
| Current call site | `monthlyReportLeaseCost`, `monthlyReportStaffDailyCost`, `monthlyReportFoodProfitRatio` and the per-month override maps in the POS settings box |
| Current default | Enabled, with seeded values |
| Local-only? | Yes. Changes are audited since Phase 1A |
| Proposed key | `report.costAssumptionsEnabled` (bool) |
| Owner | **Restaurant Backoffice** for the values; **Platform Admin** for whether an operator-entered cost basis may appear in an "official" report at all |
| POS must cache | The flag and the current values |

### 3.9 Venue report identity

| | |
| --- | --- |
| Current call site | `venueName`, `venueLegalId` in the POS settings box, edited in the venue identity panel |
| Current default | Empty on a fresh install; the report says so rather than substituting a value |
| Local-only? | Yes |
| Proposed key | Not a policy — Venue configuration proper |
| Owner | **Platform Admin**, with the POS caching it, like the rest of administrative configuration |
| POS must cache | Name and legal id; reports must render offline |

## 4. Shape of the work

1. `VenuePolicy` model (Venue-owned, one row per Venue, JSON or typed columns),
   plus a resolver alongside `VenueEntitlementsService` and separate from it.
2. Platform Admin UI per Venue, with every change written to
   `PlatformAuditEvent`.
3. POS: a policy cache in the settings box, refreshed on sync, read through one
   `VenuePolicy.of()`-style accessor. Never a network read on a hot path.
4. Migration: seed each Venue's policy from what its POS currently has, so no
   behaviour changes on the day the system ships.
5. Remove the corresponding POS admin toggles in the same release that adds the
   Platform Admin control — not before, or a venue loses the ability to
   configure itself.

**Never** `if (venue == Vankisi)`. Nothing in Phase 1A or 1B introduced such a
branch, and the policy model exists specifically so none is needed.
