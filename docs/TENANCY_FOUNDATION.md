# Organization and Venue foundation

Step 4A introduces the smallest persistent ownership hierarchy needed for the
Vynic control plane:

```text
Organization
    └── Venue
          └── Device
```

- **Organization** is the customer or business account.
- **Venue** is one physical restaurant or location owned by an Organization.
- **Device** remains one concrete POS installation. Its existing credential,
  status, revocation, and `lastSeenAt` behavior are unchanged.

All three entities use UUID primary identifiers. A Venue cannot exist without
an Organization, and a Device cannot exist without a Venue. Both foreign keys
use restrictive deletion semantics so deleting an owner cannot silently erase
or orphan live identities.

## Existing installation bootstrap

The additive PostgreSQL migration creates one deterministic hierarchy for the
single installation that predates tenancy:

| Entity | UUID | Name |
| --- | --- | --- |
| Organization | `00000000-0000-4000-8000-000000000001` | `Restaurant Vankisi` |
| Venue | `00000000-0000-4000-8000-000000000002` | `Restaurant Vankisi` |

The Venue uses `Asia/Tbilisi` and `GEL`, values already established by the
current booking, payment, reporting, and POS product behavior. Every Device row
that exists when the migration runs is attached to this Venue before
`Device.venueId` becomes required. The migration is deterministic and safe to
apply whether there are zero or many existing Device rows.

The POS-owned Hive `venueName` setting is not migrated or overwritten. It is
offline, user-editable presentation data and is not a reliable source for a
server migration.

## Authentication authority

For Device credentials, tenant context is resolved from persisted ownership:

```text
credential
  ↓
Device
  ↓
Venue
  ↓
Organization
```

`venueId` or `organizationId` supplied in a request body, query, or header is
not authoritative. The POS guard publishes the IDs resolved from the verified
Device record, and application services receive that typed context separately
from the sync payload.

The legacy `POS_SYNC_API_KEY` cannot identify an individual Device. During the
single-installation transition it resolves only to the deterministic bootstrap
Venue and Organization, with `deviceId: null`. This is compatibility behavior,
not the final multi-tenant security model, and must be removed after every
installation uses a Device credential.

## Existing concept inventory

| Concept | Location | Current meaning | Persistence | Reuse decision |
| --- | --- | --- | --- | --- |
| Device | `apps/backend/prisma/schema.prisma` | One authenticated POS installation | PostgreSQL `pos.Device` | Reuse and attach to Venue |
| Venue identity settings | `apps/operations/lib/core/database/repositories/settings_repository.dart` | Offline display name, address, phone, and logo for receipts/POS UI | Hive settings | Keep separate; not authoritative cloud ownership |
| Restaurant settings API | `apps/backend/src/mobile/services/mobile-devices.service.ts` | Service-fee settings for the current single restaurant | PostgreSQL `pos.Setting` | Operational data; tenant scope deferred to Step 4B |
| Venue web | `apps/venue-web/` | One compiled customer booking site | Static configuration plus backend website data | Host/domain tenancy deferred |
| Platform web | `apps/platform-web/` | Vynic marketing/product website | Static source content | Not a tenant model |
| Business date | POS and backend order/report code | Operational service-day boundary | Hive and PostgreSQL settings/rows | Not an Organization or Venue |

No existing persistent backend model represents a customer account or a
physical location, so `Organization` and `Venue` are new concepts rather than
duplicates.

## Deliberate boundary

Organization/Venue foundation exists after Step 4A, but operational models are
**not tenant-scoped yet**. Tables, orders, staff, menu, reservations, business
days, settings, outbox records, website records, and other operational data do
not receive `venueId` in this step. Full tenant isolation and tenant-aware
Prisma access arrive in Step 4B.
