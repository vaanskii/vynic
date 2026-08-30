# @vynic/contracts

Definitions that cross a language boundary, kept in one place.

## Why this exists

Some behaviour has to be identical in Dart and in TypeScript because both
sides read and write the same wire values. Before this package, the table
encoding was implemented twice by hand and kept in step by a comment — the
first line of `reservation-table-codes.ts` said it mirrored
`reservation_table_availability.dart`.

It didn't. By the time the pair was audited they had drifted:

| `encodeTableCode` input | Dart | TypeScript |
| --- | --- | --- |
| first floor, table 11 | throws | `11` — decodes back as *second floor table 1* |
| first floor, table 0 | throws | `0` |
| first floor, `"5abc"` | throws | `5` — parses a prefix, discards the rest |
| third floor, table 5 | throws | `5` — silently lands on the first floor |

Nothing failed, because no venue has a first floor with eleven tables. The
drift was invisible, and it was a table-misassignment bug waiting for a venue
with a bigger floor.

## What belongs here

Wire DTOs, enum and status vocabulary, stable identifiers, protocol-level
encoding rules, serialization contracts, and version metadata.

Nothing else. No Prisma queries, no Hive repositories, no availability or
booking rules, no payment or BOG logic, no UI state, no NestJS controllers,
no Flutter widgets, no entitlement rules. If a rule needs a database, a
request, or a screen to make sense, it is not a contract.

## Layout

```
packages/contracts/
├── schema/
│   ├── table-identity.contract.json   authoritative — edit this
│   └── table-identity.vectors.json    golden test vectors, shared by both suites
├── generated/
│   ├── dart/table_identity.dart       generated — never edit
│   └── typescript/table-identity.ts   generated — never edit
└── scripts/generate.mjs
```

**`schema/table-identity.contract.json` is the only file to edit.** Both
generated files carry a `GENERATED FILE — DO NOT EDIT` header; a hand edit is
overwritten on the next run and fails the check below in the meantime.

## Regenerating

```bash
node packages/contracts/scripts/generate.mjs
```

```bash
node packages/contracts/scripts/generate.mjs --check
```

`--check` regenerates in memory and exits non-zero if the committed output
differs — that is the CI gate, catching both a hand-edited output and a schema
change that was never regenerated. Generated output is committed so neither
app needs a build step, a network fetch, or a package manager to consume it.

The script uses only Node's standard library: no dependencies, no lockfile,
nothing to keep current.

### Why a script and not JSON Schema, OpenAPI, or Protobuf

Those describe the *shape* of a message. What is shared here is an
*algorithm* — `tableNumber + 10`, bounded by the first floor's maximum — and
no schema language emits that. What genuinely varies between versions is the
floor vocabulary, the offsets, and the bounds; those live in the schema, and
the templates read them. Adding a code generator toolchain to express a
30-line function would cost more than it explains. When a real message shape
needs sharing, JSON Schema is the thing to reach for, alongside this.

## Consumers

| Side | Consumes via |
| --- | --- |
| `pos_app_client` (Flutter) | `lib/core/contracts/table_identity.dart`, re-exported by `ReservationTableAvailability` and `TableRef` |
| `pos_app_server` (NestJS) | `src/website/reservation/reservation-table-codes.ts`, which re-exports the generated functions |

Both keep their existing public API, so call sites did not change when the
implementation moved here.

`restaurant-client` does not consume this package. It identifies tables by
`WebsiteTable.websiteTableNumber` strings (`table3`, `f2-table1`) and never
computes a legacy code; the server maps those to codes on its behalf.

## Contract versions

`contractVersion` in the schema is a single integer, currently `1`. It is
exposed to both languages — `tableIdentityContractVersion` in Dart,
`TABLE_IDENTITY_CONTRACT_VERSION` in TypeScript — and asserted by both golden
suites, so a bump cannot land without both sides acknowledging it.

Bump it when a change alters what an existing peer would compute or accept.
Adding a helper that no one calls yet does not need a bump.

The rule this exists to enable, for when the cloud is no longer on the same
machine as the POS: **the server should accept the current contract version
and the previous one**, so POS terminals can be upgraded on their own
schedule instead of in lockstep with a deployment. That is not implemented —
today both sides ship together and the constant is a foundation for it.

## Legacy table codes are transitional

The integer encoding here is not the long-term identity of a table. It cannot
represent a third floor, or a first floor with more than ten tables, and the
POS floor-plan editor can already create both — `canEncodeTableCode` returns
false for them and pickers hide them.

`encodeTableRef` / `tryDecodeTableRef` (`first/3`, `floor-3/7`) is the
lossless form and is already what `Reservation.tableRefs` stores in Hive. The
integer codes survive because they are still the reservation wire format
between POS and server, and because stored reservations carry them.

Both forms live here so the eventual migration is a change to this package and
its consumers, not another pair of hand-written implementations.
