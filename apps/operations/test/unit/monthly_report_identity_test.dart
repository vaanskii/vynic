import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/pos/monthly_report_service.dart';

/// Money Integrity 1A: what the monthly report asserts, and about whom.
///
/// Two properties are under test here. First, the report names the venue whose
/// terminal produced it — the name and identification code used to be
/// constants naming the first customer, so any second venue's export carried
/// that restaurant's identity. Second, the report's transaction detail is the
/// sales the POS recorded and nothing else: the manual monthly adjustment that
/// used to be added to revenue, and the transaction rows that used to be
/// generated to match it, are gone.
void main() {
  late Directory tempDir;

  const year = 2026;
  const month = 5;

  Map<String, dynamic> sale({
    required int orderId,
    required String day,
    required double total,
  }) {
    return <String, dynamic>{
      'orderId': orderId,
      'tableNumbers': <String>['1'],
      'floor': 'first',
      'items': <Map<String, dynamic>>[],
      'totalAmount': total,
      'total': total,
      'paymentMethod': 'cash',
      'paymentBreakdown': <String, double>{'cash': total},
      'createdBy': 'waiter',
      'createdAt': '2026-05-${day}T12:00:00.000',
      'closedAt': '2026-05-${day}T13:00:00.000',
      'includeServiceFee': false,
      'date': '2026-05-$day',
      'isCancelled': false,
      'isFiscal': true,
      'restoredToOrder': false,
    };
  }

  /// Every string in the workbook, so an assertion can ask what the document
  /// says rather than where it says it.
  List<String> workbookText(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final out = <String>[];
    for (final table in excel.tables.values) {
      for (final row in table.rows) {
        for (final cell in row) {
          final value = cell?.value;
          if (value != null) out.add(value.toString());
        }
      }
    }
    return out;
  }

  int transactionRowCount(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables['Transactions']!;
    // Title row, header row, then one row per transaction.
    return sheet.rows
        .where(
          (row) => row.isNotEmpty && (row.first?.value?.toString() ?? '') != '',
        )
        .length;
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_report_identity');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('ri_settings');
    DatabaseCore.salesBox = await Hive.openBox('ri_sales');
    await DatabaseCore.settingsBox!.put('currentDate', '2026-05-31T00:00:00');
    await SettingsRepository.setMonthlyReportLeaseCost(1000.0);
    await SettingsRepository.setMonthlyReportStaffDailyCost(100.0);
    await SettingsRepository.setMonthlyReportFoodProfitRatio(0.5);
  });

  tearDown(() async {
    MonthlyReportService.venueNameResolver = () =>
        SettingsRepository.getVenueName();
    MonthlyReportService.venueLegalIdResolver = () =>
        SettingsRepository.getVenueLegalId();
    await Hive.deleteBoxFromDisk('ri_settings');
    await Hive.deleteBoxFromDisk('ri_sales');
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('report identity', () {
    test('names the venue that produced it, not the first customer', () async {
      MonthlyReportService.venueNameResolver = () => 'რესტორანი მეორე';
      MonthlyReportService.venueLegalIdResolver = () => '111222333';
      await DatabaseCore.salesBox!.add(
        sale(orderId: 1, day: '10', total: 200.0),
      );

      final text = workbookText(
        MonthlyReportService.buildExcelXlsxBytes(year: year, month: month),
      );

      expect(text, contains('რესტორანი მეორე'));
      expect(text, contains('111222333'));
      expect(text.join('\n'), isNot(contains('ვანკისი')));
      expect(text.join('\n'), isNot(contains('436687168')));
    });

    test(
      'an unconfigured venue says so instead of borrowing an identity',
      () async {
        MonthlyReportService.venueNameResolver = () => '';
        MonthlyReportService.venueLegalIdResolver = () => '';
        await DatabaseCore.salesBox!.add(
          sale(orderId: 1, day: '10', total: 200.0),
        );

        final text = workbookText(
          MonthlyReportService.buildExcelXlsxBytes(year: year, month: month),
        );

        expect(text.where((t) => t == 'არ არის კონფიგურირებული').length, 2);
        expect(text.join('\n'), isNot(contains('436687168')));
      },
    );

    test('the full report carries the same identity', () async {
      MonthlyReportService.venueNameResolver = () => 'Venue Two';
      MonthlyReportService.venueLegalIdResolver = () => '999888777';
      await DatabaseCore.salesBox!.add(
        sale(orderId: 1, day: '10', total: 200.0),
      );

      final text = workbookText(
        MonthlyReportService.buildFullReportXlsxBytes(
          months: [DateTime(year, month)],
          config: MonthlyReportService.getConfig(),
          leaseByMonth: const {},
          staffDailyByMonth: const {},
        ),
      );

      expect(text, contains('Venue Two'));
      expect(text, contains('999888777'));
      expect(text.join('\n'), isNot(contains('ვანკისი')));
    });
  });

  group('no synthesized transactions', () {
    test('the report totals only the sales the POS recorded', () async {
      await DatabaseCore.salesBox!.add(
        sale(orderId: 1, day: '10', total: 200.0),
      );
      await DatabaseCore.salesBox!.add(
        sale(orderId: 2, day: '11', total: 300.0),
      );

      final summary = MonthlyReportService.calculateSummary(
        year: year,
        month: month,
      );

      expect(summary.totalSales, 500.0);
      expect(summary.cashRevenue, 500.0);
      expect(summary.transactionCount, 2);
    });

    test('a stale manual-sales setting left on disk changes nothing', () async {
      await DatabaseCore.settingsBox!.put(
        SettingsRepository.removedMonthlyReportManualSalesByMonthSetting,
        <String, double>{'2026-05': 9000.0},
      );
      await DatabaseCore.salesBox!.add(
        sale(orderId: 1, day: '10', total: 200.0),
      );

      final summary = MonthlyReportService.calculateSummary(
        year: year,
        month: month,
      );

      expect(summary.totalSales, 200.0);
      expect(summary.cashRevenue, 200.0);
      expect(summary.transactionCount, 1);
    });

    test('the transaction sheet lists one row per real sale', () async {
      await DatabaseCore.salesBox!.add(
        sale(orderId: 1, day: '10', total: 200.0),
      );
      await DatabaseCore.salesBox!.add(
        sale(orderId: 2, day: '11', total: 300.0),
      );

      final bytes = MonthlyReportService.buildExcelXlsxBytes(
        year: year,
        month: month,
      );

      // Title + header + two sales, and no third invented row.
      expect(transactionRowCount(bytes), 4);
    });
  });

  group('v6 advance migration', () {
    test('moves a stored advance out of the discount field', () async {
      final orderBox = await Hive.openBox<Order>('ri_orders_v6');
      final order = Order(
        orderId: 1,
        tableNumbers: const ['1'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'ღვინო',
            itemName: 'ღვინო',
            unitPrice: 900,
            quantity: 1,
            total: 900,
          ),
        ],
        totalAmount: 850,
        createdAt: DateTime.parse('2026-05-10T12:00:00'),
        createdBy: 'waiter',
      );
      // How every advance was stored before v6.
      order.discountAmount = 50;
      await orderBox.put(1, order);

      final context = HiveMigrationContext(
        metaBox: await Hive.openBox('ri_meta_v6'),
        userBox: await Hive.openBox('ri_users_v6'),
        tableBox: await Hive.openBox('ri_tables_v6'),
        orderBox: orderBox,
        menuBox: await Hive.openBox('ri_menu_v6'),
        settingsBox: DatabaseCore.settingsBox!,
        salesBox: DatabaseCore.salesBox!,
        auditLogBox: await Hive.openBox('ri_audit_v6'),
        reservationBox: await Hive.openBox('ri_res_v6'),
      );

      await HiveMigrationService.migrateV5toV6(context);

      final migrated = orderBox.get(1)!;
      expect(migrated.advanceAmount, 50);
      expect(migrated.discountAmount, 0);
      expect(migrated.advanceCollectedOn, '2026-05-10');

      // The balance is unchanged — recalculateTotal subtracts both fields, so
      // moving the value between them cannot move the number.
      migrated.recalculateTotal(serviceFeeRate: 0);
      expect(migrated.totalAmount, 850);
      expect(migrated.grossAmount, 900);

      // Idempotent: a second run leaves it alone rather than zeroing it.
      await HiveMigrationService.migrateV5toV6(context);
      expect(orderBox.get(1)!.advanceAmount, 50);

      for (final name in const [
        'ri_orders_v6',
        'ri_meta_v6',
        'ri_users_v6',
        'ri_tables_v6',
        'ri_menu_v6',
        'ri_audit_v6',
        'ri_res_v6',
      ]) {
        await Hive.deleteBoxFromDisk(name);
      }
    });
  });

  group('removed setting', () {
    test('the v5 migration deletes it from an existing store', () async {
      final metaBox = await Hive.openBox('ri_meta');
      final context = HiveMigrationContext(
        metaBox: metaBox,
        userBox: await Hive.openBox('ri_users'),
        tableBox: await Hive.openBox('ri_tables'),
        orderBox: await Hive.openBox('ri_orders'),
        menuBox: await Hive.openBox('ri_menu'),
        settingsBox: DatabaseCore.settingsBox!,
        salesBox: DatabaseCore.salesBox!,
        auditLogBox: await Hive.openBox('ri_audit'),
        reservationBox: await Hive.openBox('ri_reservations'),
      );
      await DatabaseCore.settingsBox!.put(
        SettingsRepository.removedMonthlyReportManualSalesByMonthSetting,
        <String, double>{'2026-05': 9000.0},
      );

      await HiveMigrationService.migrateV4toV5(context);

      expect(
        DatabaseCore.settingsBox!.containsKey(
          SettingsRepository.removedMonthlyReportManualSalesByMonthSetting,
        ),
        isFalse,
      );

      // Rerunning on a store that never had the key is a no-op, not an error.
      await HiveMigrationService.migrateV4toV5(context);

      for (final name in const [
        'ri_meta',
        'ri_users',
        'ri_tables',
        'ri_orders',
        'ri_menu',
        'ri_audit',
        'ri_reservations',
      ]) {
        await Hive.deleteBoxFromDisk(name);
      }
    });
  });
}
