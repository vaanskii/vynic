# MGR-01 generic Manager table layout

The POS saved restaurant layout owns physical-table membership, aliases, floor/table
labels and display ordering. Manager reads every physical table for its authenticated
Venue, including first/10, terrace/1, second/11 and custom Georgian floors.

POS full and realtime snapshots add nullable presentation fields to each Table and
an optional `tableLayout: {version: 1, physicalTableIds: [...]}` completeness claim.
Only a strictly decoded and validated saved layout can issue this claim. Duplicate
identities/aliases, missing zones and invalid metadata stop sync visibly. An absent
legacy setting emits no classification or completeness claim. Existing Hive v9 and
its Table adapter are unchanged; Manager metadata lives only in JSON/cache.

Cloud validates the whole modern projection and exact membership before its first
table write. Existing Device/Venue primary authorization and the Venue transaction
own ingestion. A complete applied layout explicitly marks non-member rows VIRTUAL,
including stale removed tables and order-derived carriers; no operational row is
deleted and its occupancy remains retained. Cold full all-free snapshots, including
empty complete layouts, preserve occupied Cloud state/classification. Explicit
realtime empty membership can retire the complete layout. Legacy partial snapshots
and Order linking omit presentation fields, preserving modern classification.

Manager excludes only explicit VIRTUAL rows. Unclassified historical rows remain
visible until a modern complete POS sync supplies membership; floor names and table
number ranges never infer physical/virtual type. The additive migration leaves
existing identities, occupancy and null legacy metadata intact. Deploy the migration
with the backend before the POS/Manager changes. A downlevel client can still send
its old optional wire shape, though its old UI cannot display the new layout fully.

Configured aliases resolve before historical display prefixes/second-floor numeric
encoding. UUID-linked retained Orders resolve the current table alias and floor;
linking cannot rename a physical table after its layout snapshot. Dashboard and
LiveStatus count each occupied/reserved/free physical row identically. Open current-
business-day payable contributes once per linked Order (maximum authoritative bill
across merged rows); unknown or terminal Orders contribute no open payable.

LiveStatus renders configured labels/order, combined same-floor cards, compact and
desktop grids. Its real route navigation and scoped cache retain metadata; disposal
removes timers/socket listeners. Button labels wrap within compact available width.

## Synthetic verification

Use a clean Git export and existing installed dependencies/toolchains. Generate
Prisma in a private dependency copy, never the repository's installed client:

```sh
DATABASE_URL=postgresql://synthetic@127.0.0.1:1/disposable_codegen node node_modules/prisma/build/index.js generate
python3 apps/backend/tool/prove_mgr01_postgres.py --postgres-bin /path/to/postgresql/bin --output /tmp/mgr01/pg.json
```

The PostgreSQL tool creates/stops/removes its own loopback-only synthetic cluster.
It runs real authenticated HTTP, migration compatibility, merged payable, tenant/
primary isolation, legacy partial/UUID aliases, retirement, cold full/empty guards
and malformed projection rollback; completed MGR-02 repair runs as a regression.
The actual HTTP response can feed the Manager test with `MGR01_HTTP_FIXTURE`:

```sh
flutter test --no-pub test/unit/mgr01_table_snapshot_test.dart test/widget/mgr01_manager_table_navigation_test.dart
```

The widget fixture permits only its own fresh loopback port and rejects external
HTTP. It checks real LiveStatus/OrderDetail routes, combined cards, Georgian strings,
three visits per 320/1024 window, one socket/timer refresh and disposal/cache behavior.
Optional `MGR01_SCREENSHOT_DIR` exports Flutter-test layout images (Ahem glyphs), not
manual packaged-font/platform qualification. Windows VM/device/printer release
acceptance remains separately held/pending; no live restaurant is used.
