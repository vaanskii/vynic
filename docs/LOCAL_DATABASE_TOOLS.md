# Local Docker database tools

These tools operate exclusively on the Compose PostgreSQL service `postgres:5432`,
user `vynic`, database `vynic_local_prod`. They never read application `.env` files
or connect to `vankisi_database`. Use `scripts/docker.sh` from the repository.

## Commands and reset levels

```sh
./scripts/docker.sh start
./scripts/docker.sh studio
# Open http://127.0.0.1:5555
./scripts/docker.sh studio-stop

./scripts/docker.sh reset-customer-data --dry-run
./scripts/docker.sh reset-customer-data --confirm-local
# Choose onboarding in the UI OR explicit samples:
./scripts/docker.sh seed

# Retry an interrupted/failed post-commit media cleanup:
./scripts/docker.sh cleanup-customer-media --confirm-local

# Entire local DB, including Platform admins/config, rebuilt from migrations:
./scripts/docker.sh reset-local-db --confirm-local

# Nuclear option: delete BOTH local DB and website-media volumes:
./scripts/docker.sh --profile tools down -v
```

| Operation | Customer/business data | Platform admins, catalog, settings | Media volume |
| --- | --- | --- | --- |
| Dry run | Counts only; unchanged | Unchanged | Unchanged |
| Customer reset | All removed; no automatic seed | Preserved, including audit and migration history | Kept; only attributable customer files removed |
| Delete test Venue | Target Venue and its state | Preserved | Kept; target files only |
| Delete test Organization | Its Venues and state; unshared customer accounts | Preserved | Kept; target files only |
| Full DB reset | Entire database recreated by existing migrations | Lost/recreated by migrations; create admin again | Kept; previous files may remain |
| `down -v` | Entire database volume deleted | Entire database volume deleted | Deleted |

Full DB reset is deliberately separate and unchanged in purpose. Existing
migrations contain a legacy bootstrap restaurant; a freshly migrated DB therefore
is not an empty customer dataset. Customer reset removes that row too. Backend
startup skips legacy website bootstrap when that Venue is absent. Sample creation
is never a side effect of customer reset.

## Studio

`prisma-studio` exists only in `compose.local.yaml`, under profile `tools`.
It uses the same backend image, installed Prisma CLI and schema, and explicitly reuses the backend-generated query engine without downloading one at runtime.
Start the stack/build first; Studio uses that current image. Its entrypoint rejects
nonlocal connection configuration before spawning Prisma. Studio's query engine
uses `sslmode=disable` only after validating the exact isolated URL (the local
Postgres service does not enable TLS).

The only published binding is `127.0.0.1:5555:5555`. A dedicated `studio-access`
bridge enables that loopback publishing; Traefik is not on it. Studio also joins
the internal database network. There are no Studio Traefik routes, hostnames or
production service entries. Visit the IP URL directly; the normal Vynic/admin
web origins continue to serve their applications. Studio is a raw database editor,
so prefer the guarded cleanup actions for removing business data.

## Guards and transaction boundary

Both commands and scoped deletion require all of:

- `VYNIC_LOCAL_DOCKER=true` and Docker's `/.dockerenv` marker;
- exact `postgresql://vynic:<password>@postgres:5432/vynic_local_prod` URL;
- no caller-supplied query parameters, fragments, alternate port, host or user;
- connected `current_database() = vynic_local_prod`, `current_user = vynic`;
- expected Docker media mount `/var/lib/vynic/media`, not a symlink;
- complete audited Prisma model classification;
- explicit `--confirm-local` for CLI mutations (dry run requires `--dry-run`);
- exact typed `DELETE <current name>` for scoped API mutations.

The CLI validates before constructing a Prisma client. There is no full-reset API.
Scoped POST routes register only if the complete local environment guard passes,
then recheck it on each request. Existing Platform authentication/role checks apply;
restaurant/customer credentials cannot authorize this action, and SUPPORT_READONLY
cannot mutate. Capability discovery returns false outside local Docker; the UI
renders no danger-zone controls there. No frontend build flag grants access.

Counts, scope, membership decisions, row deletions and scoped audit insertion run
inside one transaction. Table write locks prevent concurrent local onboarding,
Studio edits and media changes from invalidating the snapshot. Ordinary reads can
continue; lock acquisition fails after five seconds and the transaction has a
60-second timeout. FK failure rolls back the whole database deletion. Restrictive
cross-Venue references fail closed; anomalous cross-Venue catalog cascades are
explicitly refused. No constraints are disabled and no tables are truncated.

## Account and audit semantics

Venue-only deletion keeps its Organization and all CustomerAccounts. Global
WebsiteUser identities remain; their target bookings are removed and a deleted
`adminVenueId` becomes null. Bookings on other Venues remain.

Organization deletion considers accounts linked through membership, legacy
provenance or accepted invitations. It deletes an account only if all its
memberships, provenance, accepted invitations and enrollment references are within
the removed Organization. References elsewhere preserve the account. Legacy
`organizationId` provenance pointing at the deleted Organization becomes null;
remaining memberships stay intact. This is intentionally conservative.

Full customer reset deletes all CustomerAccounts and WebsiteUsers in the isolated
DB, including restaurant website administrators. PlatformUser is a distinct model
and is always preserved. There is no Platform-user, plan or catalog delete path.

PlatformAuditEvent has no FK to its target and survives deletion. Scoped actions
append `LOCAL_TEST_DATA_DELETED` with actor, target and model counts in the same
transaction. Full reset prints counts without inventing an audit event. Customer audit rows are removed only for deleted accounts (all for full reset).
Surviving customers retain their historical audit entries, whose target IDs have
no foreign keys. Restaurant operational audit follows the deleted Venue. Platform audit history remains even for deleted targets.

## Media

The reset captures owned `WebsiteMediaAsset.storageKey` values plus legacy local
references in website draft/published content, menu presentation and public-profile
gallery. Only UUID `.webp` filenames are accepted; an unsafe key aborts before any
DB deletion. Other files, external URLs and the volume itself are not swept.

Before committing, a private manifest is written into the media volume at
`.local-customer-cleanup/<uuid>.json`. File cleanup runs after commit and checks that
all target Venues are absent and no remaining asset record or Venue content
references the file. Shared references are retained. `unlink` removes only the
listed leaf entry; it never traverses a storage-key path or follows a leaf symlink.
Missing files count as already cleaned.

Failures return an explicit **database committed / media incomplete** result;
the CLI exits nonzero and the UI displays recovery instructions. The manifest
remains for `cleanup-customer-media --confirm-local`. A rolled-back transaction's
manifest cannot remove files while any target Venue still exists. If a target was
reseeded using the same ID, recovery conservatively retains its files and reports
that condition; it does not guess which incarnation owns them.

## Deletion matrix

All Prisma models are classified below. `V` means target Venue IDs for a scoped
action, every row for full reset; Organization deletion uses all of its Venue IDs.
Inherited scope follows the named parent relation, including nullable legacy audit
Venue IDs. Rows are deleted child-first; counts are measured before any cascades.

| Model | Deletion scope / preserved behavior |
| --- | --- |
| `StockMovement` | V by `venueId` |
| `SaleConsumptionComponent` | V by `venueId` |
| `SaleConsumptionLine` | V by `venueId` |
| `SaleConsumption` | V by `venueId` |
| `MenuConsumptionComponent` | V by `venueId` |
| `MenuConsumptionRecipe` | V by `venueId` |
| `SupplierPayment` | V by `venueId` |
| `ReceivingLine` | V through `receiving` |
| `Receiving` | V by `venueId` |
| `StockLocation` | V by `venueId`, after movements and Receivings; shared Venue defaults/history are not reassigned. |
| `SupplierProduct` | V by `venueId` |
| `StockItemPurchaseUnit` | V by `venueId` |
| `StockItem` | V by `venueId` |
| `Supplier` | V by `venueId` |
| `PayrollAccrual` | V by `venueId` |
| `PayrollPayment` | V by `venueId` |
| `PayrollPeriod` | V by `venueId` |
| `StaffCompensation` | V by `venueId` |
| `ManagerActivation` | V by `venueId`; initial registration grant removed with the Venue. |
| `Staff` | V by `venueId` |
| `ObligationPayment` | V by `venueId` |
| `ObligationReserveEntry` | V by `venueId` |
| `ObligationCycle` | V by `venueId` |
| `FinancialObligation` | V by `venueId` |
| `WebsiteReservationTable` | V through `reservation` |
| `WebsiteReservation` | V by `venueId` |
| `WebsiteTable` | V by `venueId` |
| `PaymentIntegration` | V by `venueId` |
| `OrderItem` | V through `order` |
| `Order` | V by `venueId` |
| `Table` | V by `venueId` |
| `SaleLine` | V through `sale` |
| `SalePayment` | V through `sale` |
| `CloudSale` | V by `venueId` |
| `SaleLedgerDay` | V by `venueId` |
| `MenuItemWebsitePresentation` | V by `venueId` |
| `MenuCatalogMutation`, `MenuCatalogTombstone` | V by `venueId` (canonical Menu ledger/tombstones; also cascade with the Venue) |
| `MenuItemVariant` | V through `menuItem` |
| `MenuItem` | V by `venueId` |
| `MenuSubcategory` | V through `category` |
| `MenuCategory` | V by `venueId` |
| `AuditEvent` | V through `report` |
| `AuditReport` | V by `venueId` |
| `AuditEventLog` | V by `venueId` |
| `QuickOrderDraftItem` | V through `draft` |
| `QuickOrderDraft` | V by `venueId` |
| `ManagerNotificationDelivery` | V through `notification` |
| `ManagerNotification` | V by `venueId` |
| `Expense` | V by `venueId` |
| `PosReservation` | V by `venueId` |
| `DailySnapshot` | V by `venueId` |
| `Setting` | V by `venueId` |
| `PushDevice` | V by `venueId` |
| `PosCallbackOutbox` | V by `venueId` |
| `EdgeCommand` | V by `venueId` |
| `DevicePrinterRuntimeRequest` | V by `venueId`; child-first before Device. |
| `DeviceEnrollment` | V by `venueId` |
| `Device` | V by `venueId` |
| `EdgeFoundationInstallation` | V by `venueId` |
| `SubscriptionBillingEvent` | V through `operation` |
| `SubscriptionBillingOperation` | V by `venueId` |
| `VenueSubscription` | V by `venueId` |
| `VenuePlanAssignment` | V by `venueId` |
| `VenueFeatureOverride` | V by `venueId` |
| `WebsiteHostnameRequest` | V by `venueId` |
| `CustomWebsiteBinding` | V by `venueId` |
| `VenueWebsiteCapability` | V by `venueId` |
| `VenueWebsiteConfig` | V by `venueId` |
| `VenuePublicProfile` | V by `venueId` |
| `VenuePublicInfoReview` | V by `venueId` (WEB-02 private evidence) |
| `VenueDomain` | V by `venueId` |
| `WebsiteMediaAsset` | V by `venueId` |
| `Venue` | Selected roots; all for full reset. Operational-primary FK cleared first. |
| `Organization` | Organization target only; all for full reset. Venue deletion preserves it. |
| `OrganizationMembership` | Deleted Organizations; all for full reset. |
| `OwnerInvitation` | Deleted Organizations; all for full reset. |
| `CustomerAccount` | Organization candidates only when no surviving relationships; all for full reset; never Venue-only. |
| `CustomerAuditEvent` | Deleted accounts only; surviving accounts retain historical target IDs. All for full reset. |
| `OnboardingRequest` | Requests whose requested/approved Venue or deleted account is in scope; all access/trial requests for full reset. |
| `WebsiteUser` | Preserved for scoped deletion; all removed for full reset. |
| `PlatformUser` | Always preserved, including passwords, status and role. |
| `PlatformAuditEvent` | Always preserved; scoped action appends one event. |
| `Plan` | Always preserved, including pricing and quotas. |
| `Feature` | Always preserved. |
| `PlanFeature` | Always preserved. |
| `OnboardingPolicy` | Always preserved, including release/distribution links. |

Prisma migration history, database schema, Docker configuration and secrets are outside the deletion matrix and are never changed. Venue policy/profile fields embedded on Venue are removed with it; there is no separate global policy table to infer. Billing quotes/receipts are customer-owned despite denormalized Venue IDs without foreign keys.

## Validation and proof boundary

Validation for this implementation:

- Backend and Platform production builds, 25 targeted backend tests and 153
  Platform tests passed. Guards reject production mode, remote hosts, query-string
  overrides, alternate ports/users and the forbidden database name before connecting.
- Production Compose configuration lists no Studio service even with `tools` enabled.
  Studio binds `127.0.0.1:5555`; health checks execute a real Venue count query.
- Real PostgreSQL proof inside an **unconditionally rolled-back** outer transaction
  passed Venue-only isolation, preservation of shared WebsiteUser and customer
  identities, Organization account cleanup, payroll day adjustments, supplier
  payment reversals, audit retention and full customer/control-plane separation.
  Original local Venue/Organization/Admin counts remained unchanged afterward.
- Real media proof creates only uniquely named test files: manifest cleanup removes
  its file, preserves unrelated files, retains a failed cleanup manifest and succeeds
  on retry. It changes no database rows.
- Browser inspection verified the local danger zone and that the button enables
  only after typing the exact name. The dialog was cancelled without deleting data;
  the existing Platform Admin session remained usable.

The committed customer reset/reseed cycle and temporary-admin fresh-login proof
were **not executed**: automatic approval review required additional explicit
approval for deletion of existing local data and a temporary privileged account.
Full `reset-local-db` was not executed against the existing volume, because it
would also remove the existing Platform Admin. It remains the separate original
implementation; command wiring and syntax are checked. These limitations must not
be reported as completed destructive acceptance tests.

Reproducible proof entrypoints (from repository root):

```sh
# No persistent DB writes; refuses if existing media needs cleanup:
./scripts/docker.sh exec -T backend node < apps/backend/scripts/prove-docker-cleanup-rollback.cjs
# Only task-owned temporary files; no DB writes:
./scripts/docker.sh exec -T backend node < apps/backend/scripts/prove-docker-media-cleanup.cjs
# DESTRUCTIVE: all local customer data removed, samples reseeded;
# temporary proof admin created then removed, existing admins preserved:
./scripts/docker.sh exec -T backend node - --confirm-local < apps/backend/scripts/prove-docker-cleanup.cjs
```
