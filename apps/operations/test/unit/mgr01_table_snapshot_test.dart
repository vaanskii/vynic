import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/database/repositories/table_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/sync/table_snapshot_projection.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import '../support/pos03_fixture.dart';

const mgr01Ids = [
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000003',
  'a1000000-0000-4000-8000-000000000004',
];
RestaurantTableLayout mgr01Layout() => RestaurantTableLayout(
  id: 'mgr01',
  zones: [
    for (final (i, f) in [
      'first',
      'terrace',
      'second',
      'ქართული სართული',
    ].indexed)
      RestaurantZone(
        id: 'z$i',
        name: ['Main hall', 'Terrace', 'VIP', 'ქართული დარბაზი'][i],
        legacyFloor: f,
        displayOrder: i,
        renderMode: TableLayoutRenderMode.buttonGrid,
      ),
  ],
  tables: [
    for (final (i, n) in ['10', '1', '11', 'Table Garden'].indexed)
      RestaurantTableDefinition(
        id: mgr01Ids[i],
        zoneId: 'z$i',
        legacyFloor: ['first', 'terrace', 'second', 'ქართული სართული'][i],
        legacyTableNumber: n,
        label: ['Main 10', 'Terrace 1', 'VIP 11', 'ბაღის მაგიდა'][i],
        capacity: 4,
        sortOrder: i,
      ),
  ],
);
Order mgr01Order({
  int id = 70,
  List<String> numbers = const ['10'],
  String floor = 'first',
  String status = 'confirmed',
}) => Order(
  orderId: id,
  tableNumbers: numbers,
  floor: floor,
  items: [],
  totalAmount: 45,
  createdAt: DateTime(2026, 10, 7),
  createdBy: 'synthetic',
  status: status,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = DateTime(2026, 10, 7);
  TableSnapshotProjection project({
    RestaurantTableLayout? layout,
    List<TableModel> tables = const [],
    List<Order> orders = const [],
  }) => TableSnapshotProjection.build(
    sourceTables: tables,
    orders: orders,
    businessDate: day,
    savedLayout: layout,
  );
  test(
    'saved layout includes first/10, terrace/1, second/11 and Georgian physical table labels',
    () {
      final p = project(layout: mgr01Layout());
      expect(p.tables.length, 4);
      expect(p.layout!['physicalTableIds'], mgr01Ids);
      expect(p.tables.map((t) => t['tableNumber']), [
        '10',
        '1',
        '11',
        'Table Garden',
      ]);
      expect(p.tables.last, containsPair('floorLabel', 'ქართული დარბაზი'));
      expect(p.tables.every((t) => t['tableKind'] == 'PHYSICAL'), isTrue);
    },
  );
  test(
    'merged occupancy shares one order bill and carrier rows are explicitly virtual',
    () {
      final p = project(
        layout: mgr01Layout(),
        tables: [
          TableModel(tableNumber: '1', floor: 'terrace', activeOrderId: 70),
          TableModel(
            tableNumber: 'carrier',
            floor: 'transport',
            activeOrderId: 99,
          ),
        ],
        orders: [
          mgr01Order(),
          mgr01Order(id: 99, numbers: ['carrier'], floor: 'transport'),
        ],
      );
      expect(p.tables.where((t) => t['activeOrderId'] == 70).length, 2);
      expect(
        p.tables
            .where((t) => t['activeOrderId'] == 70)
            .map((t) => t['currentBill']),
        [45.0, 45.0],
      );
      final carrier = p.tables.singleWhere(
        (t) => t['tableNumber'] == 'carrier',
      );
      expect(carrier['tableKind'], 'VIRTUAL');
      expect(carrier.containsKey('tableId'), isFalse);
    },
  );
  test(
    'exact configured aliases precede historical prefix and second-floor decoding',
    () {
      final layout = mgr01Layout();
      expect(
        TableSnapshotProjection.normalizeAlias('11', 'second', layout),
        '11',
      );
      expect(
        TableSnapshotProjection.normalizeAlias(
          'Table Garden',
          'ქართული სართული',
          layout,
        ),
        'Table Garden',
      );
      expect(
        TableSnapshotProjection.normalizeAlias('12', 'second', layout),
        '2',
      );
      expect(
        TableSnapshotProjection.normalizeAlias('Table 4', 'first', layout),
        '4',
      );
      final p = project(
        layout: layout,
        orders: [
          mgr01Order(numbers: ['11'], floor: 'second'),
          mgr01Order(
            id: 71,
            numbers: ['Table Garden'],
            floor: 'ქართული სართული',
          ),
        ],
      );
      expect(
        p.tables.singleWhere(
          (t) => t['tableId'] == mgr01Ids[2],
        )['activeOrderId'],
        70,
      );
      expect(
        p.tables.singleWhere(
          (t) => t['tableId'] == mgr01Ids[3],
        )['activeOrderId'],
        71,
      );
    },
  );
  test(
    'missing legacy layout omits classification and complete-layout claims',
    () {
      final p = project(
        tables: [TableModel(tableNumber: 'TA-1', floor: 'custom')],
      );
      expect(p.layout, isNull);
      expect(p.tables.single.containsKey('tableKind'), isFalse);
    },
  );
  for (final invalid in [
    'duplicate_id',
    'duplicate_alias',
    'missing_zone',
    'wrong_floor',
  ]) {
    test('invalid $invalid saved layout cannot classify rows', () {
      final data = mgr01Layout().toJson();
      final tables = data['tables'] as List;
      if (invalid == 'duplicate_id') tables[1]['id'] = tables[0]['id'];
      if (invalid == 'duplicate_alias') {
        tables[1]['legacyFloor'] = 'first';
        tables[1]['legacyTableNumber'] = '10';
        tables[1]['zoneId'] = 'z0';
      }
      if (invalid == 'missing_zone') tables[1]['zoneId'] = 'missing';
      if (invalid == 'wrong_floor') tables[1]['legacyFloor'] = 'first';
      expect(
        () => project(layout: RestaurantTableLayout.fromJson(data)),
        throwsFormatException,
      );
    });
  }
  test(
    'presentation JSON roundtrip preserves metadata without changing legacy/Hive representation',
    () {
      final legacy = (TableModel(
        tableNumber: '11',
        floor: 'second',
      )..currentBill = 0.0).toJson();
      expect(legacy.containsKey('tableKind'), isFalse);
      final json = {
        ...legacy,
        'tableKind': 'PHYSICAL',
        'tableLabel': 'VIP 11',
        'floorLabel': 'VIP',
        'floorSortOrder': 2,
        'tableSortOrder': 11,
      };
      expect(TableModel.fromJson(json).toJson(), json);
    },
  );
  group('strict saved-settings and operational alias compatibility', () {
    late Directory dir;
    late Pos03Fixture fixture;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vynic-mgr01-settings-');
      fixture = Pos03Fixture();
      await fixture.open(dir.path);
      await fixture.seed();
    });
    tearDown(() async {
      await fixture.close();
      await dir.delete(recursive: true);
    });
    test(
      'corrupt or incomplete layout cannot silently fall back for sync',
      () async {
        for (final raw in [
          '{',
          '{}',
          jsonEncode({'zones': []}),
          jsonEncode({
            'zones': [{}],
            'tables': [],
          }),
        ]) {
          await DatabaseCore.settingsBox!.put('activeTableLayoutJson', raw);
          expect(
            SettingsRepository.getActiveTableLayoutForSync,
            throwsA(anything),
          );
        }
      },
    );
    test(
      'actual Order wire aliases align with UUIDs for legacy prefixes and configured second/11',
      () async {
        await DatabaseCore.settingsBox!.put(
          'activeTableLayoutJson',
          jsonEncode(mgr01Layout().toJson()),
        );
        final payload = ManagerSyncService.buildOrdersSyncPayload(
          orders: [
            mgr01Order(numbers: ['Table 10']),
            mgr01Order(id: 71, numbers: ['21'], floor: 'second'),
            mgr01Order(id: 72, numbers: ['11'], floor: 'second'),
            mgr01Order(
              id: 73,
              numbers: ['Table Garden'],
              floor: 'ქართული სართული',
            ),
          ],
          businessDate: day,
        );
        expect(payload.map((p) => p['tableNumbers']), [
          ['10'],
          ['11'],
          ['11'],
          ['Table Garden'],
        ]);
        expect(payload.map((p) => p['tableIds']), [
          [mgr01Ids[0]],
          [mgr01Ids[2]],
          [mgr01Ids[2]],
          [mgr01Ids[3]],
        ]);
      },
    );
    test(
      'physical second/11 and Table Garden retain exact operational identity',
      () async {
        await DatabaseCore.settingsBox!.put(
          'activeTableLayoutJson',
          jsonEncode(mgr01Layout().toJson()),
        );
        expect(TableRepository.normalizeTableIdentifier('11', 'second'), '11');
        expect(
          TableRepository.normalizeTableIdentifier(
            'Table Garden',
            'ქართული სართული',
          ),
          'Table Garden',
        );
        expect(TableRepository.normalizeTableIdentifier('12', 'second'), '2');
      },
    );
  });
}
