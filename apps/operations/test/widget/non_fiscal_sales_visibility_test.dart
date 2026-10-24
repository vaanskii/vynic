import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_sales_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_audit_log_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_section.dart';
import 'package:vynic/apps/windows_pos/widgets/order/non_fiscal_closure_dialog.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/feature_keys.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import '../support/pos03_fixture.dart';
import '../support/pos_visual_capture.dart';
import '../support/menu01_fixture.dart' show menu01Venue;

void main() {
  late Directory directory;
  late Pos03Fixture fixture;
  setUpAll(loadPosVisualFonts);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic_entitlement_ui_');
    fixture = Pos03Fixture();
    await fixture.open(directory.path);
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-10-24T00:00:00.000',
    );
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await EdgeDeviceCredentialStore.saveEnrollment(
      rawCredential:
          'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-000000000000000000000000',
      venueId: menu01Venue,
      venueName: 'Synthetic venue',
    );
    final sale = <String, dynamic>{
      'date': '2026-10-24',
      'orderId': 1,
      'tableNumbers': ['1'],
      'floor': 'first',
      'createdBy': 'manager',
      'items': <Map<String, dynamic>>[],
      'createdAt': '2026-10-24T10:00:00.000',
      'closedAt': '2026-10-24T11:00:00.000',
      'grossSaleAmount': 1000.0,
      'totalAmount': 1000.0,
      'total': 1000.0,
      'advanceApplied': 100.0,
      'advanceAmount': 100.0,
      'collectedNow': 900.0,
      'isFiscal': true,
      'paymentMethod': 'cash',
      'paymentBreakdown': {'cash': 900.0, 'advance': 100.0},
    };
    await DatabaseCore.salesBox!.put('paid', sale);
    await DatabaseCore.salesBox!.put('internal', {
      ...sale,
      'orderId': 2,
      'isFiscal': false,
      'paymentMethod': 'non-fiscal',
      'paymentBreakdown': <String, double>{},
      'collectedNow': 0.0,
    });
    await DatabaseCore.salesBox!.put('advance', {
      ...sale,
      'orderId': 3,
      'recordType': 'advance_receipt',
      'isFiscal': false,
      'paymentMethod': 'advance',
      'grossSaleAmount': 100.0,
      'totalAmount': 100.0,
      'total': 100.0,
      'paymentBreakdown': {'advance': 100.0},
    });
  });
  tearDown(() async {
    await InventoryRepository.applyRuntimeFeatures([]);
    EdgeDeviceCredentialStore.resetForTest();
    await fixture.close();
    await directory.delete(recursive: true);
  });

  Future<void> host(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    Future<void> action(Map<String, dynamic> _) async {}
    await tester.pumpWidget(
      MaterialApp(
        theme: PosTheme.light,
        builder: (_, child) =>
            RepaintBoundary(key: posVisualKey, child: child!),
        home: Scaffold(
          body: AdminSalesSection(
            onReprintSaleReceipt: action,
            onReprintFullSaleReceipt: action,
            onConfirmCancelSale: action,
            onRestoreClosedSale: action,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final state in ['missing', 'disabled']) {
    testWidgets(
      '$state entitlement leaves no nonfiscal labels, including deposit receipts',
      (tester) async {
        if (state == 'disabled')
          await tester.runAsync(
            () => InventoryRepository.applyRuntimeFeatures([]),
          );
        await host(tester);
        expect(find.textContaining('არაფისკალურ'), findsNothing);
        expect(find.textContaining('Non-Fiscal'), findsNothing);
        expect(find.textContaining('1100.00'), findsNothing);
        expect(
          find.textContaining('დახურვისას მიღებული ₾900.00 + ავანსი ₾100.00'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        expect(DatabaseCore.salesBox!.length, 3);
        await capturePosVisual(tester, 'sales-$state');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('a real discount is not displayed as an applied advance', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await DatabaseCore.salesBox!.delete('advance');
      final paid = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get('paid') as Map,
      );
      await DatabaseCore.salesBox!.put('paid', {
        ...paid,
        'discountAmount': 100.0,
        'finalTransaction': {'discount': 100.0},
        'advanceApplied': 0.0,
        'advanceAmount': 0.0,
        'collectedNow': 1000.0,
        'paymentBreakdown': {'cash': 1000.0},
      });
    });
    await host(tester);
    expect(find.textContaining('სუფრების სრული თანხა (ავანსით)'), findsNothing);
    expect(find.textContaining('ავანსი: ₾100.00'), findsNothing);
    expect(find.textContaining('არაფისკალურ'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'explicit grant shows nonfiscal controls then removes them on revocation',
    (tester) async {
      await tester.runAsync(
        () => InventoryRepository.applyRuntimeFeatures([
          FeatureKeys.nonFiscalClose,
        ]),
      );
      await host(tester);
      expect(find.textContaining('არაფისკალურ'), findsWidgets);
      expect(find.text('ფისკალური'), findsNothing);
      expect(find.text('ფისკალური თანხა'), findsNothing);
      expect(find.textContaining('მოგება: ₾1000.00'), findsWidgets);
      expect(find.textContaining('მოგება: ₾2000.00'), findsNothing);
      await capturePosVisual(tester, 'sales-enabled');
      await tester.runAsync(() => InventoryRepository.applyRuntimeFeatures([]));
      await tester.pump();
      expect(find.textContaining('არაფისკალურ'), findsNothing);
      expect(find.textContaining('Non-Fiscal'), findsNothing);
      expect(find.textContaining('1100.00'), findsNothing);
      expect(
        find.textContaining('დახურვისას მიღებული ₾900.00 + ავანსი ₾100.00'),
        findsWidgets,
      );
      expect(DatabaseCore.salesBox!.length, 3);
      expect(tester.takeException(), isNull);
      await capturePosVisual(tester, 'sales-revoked');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'already-open confirmation removes its nonfiscal action and labels on revocation',
    (tester) async {
      await tester.runAsync(
        () => InventoryRepository.applyRuntimeFeatures([
          FeatureKeys.nonFiscalClose,
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => const NonFiscalClosureDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('არაფისკალური დახურვა'), findsOneWidget);
      await tester.runAsync(() => InventoryRepository.applyRuntimeFeatures([]));
      await tester.pump();
      expect(find.textContaining('არაფისკალურ'), findsNothing);
      expect(find.text('დახურვა და დაფიქსირება'), findsNothing);
      expect(find.text('ოპერაცია მიუწვდომელია'), findsOneWidget);
      expect(DatabaseCore.salesBox!.length, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('already-rendered X report removes internal rows on revocation', (
    tester,
  ) async {
    await tester.runAsync(
      () => InventoryRepository.applyRuntimeFeatures([
        FeatureKeys.nonFiscalClose,
      ]),
    );
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PosTheme.light,
        home: Scaffold(
          body: HomeXReportSection(
            dailySalesTotal: 1000,
            takeAwayCount: 0,
            activeWaitersCount: 1,
            waiterSummaries: const [],
            closedTables: [
              (
                orderId: 1,
                tables: 'Internal table',
                waiter: 'Synthetic manager',
                openedAt: null,
                closedAt: null,
                itemCount: 1,
                total: 1000,
                payment: 'Non-Fiscal',
                cancelled: false,
                fiscal: false,
              ),
            ],
            onPrintReport: () {},
            primaryColor: Colors.blue,
            secondaryColor: Colors.blue,
            textPrimary: Colors.black,
            mutedText: Colors.grey,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Non-Fiscal'), findsWidgets);
    await tester.runAsync(() => InventoryRepository.applyRuntimeFeatures([]));
    await tester.pump();
    expect(find.textContaining('Non-Fiscal'), findsNothing);
    expect(find.textContaining('არაფისკალურ'), findsNothing);
    expect(find.text('Internal table'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'open audit dialog removes nonfiscal labels while preserving stored evidence',
    (tester) async {
      await tester.runAsync(() async {
        await InventoryRepository.applyRuntimeFeatures([
          FeatureKeys.nonFiscalClose,
        ]);
        final time = DateTime(2026, 10, 24, 12);
        await AuditRepository.saveAuditReport(
          AuditReport(
            reportId: AuditRepository.buildAuditReportKey(1),
            orderId: 1,
            tableNumbers: ['1'],
            floor: 'first',
            openedById: 'manager',
            openedByName: 'Synthetic manager',
            openedAt: time,
            status: AuditReportStatus.closed,
            updatedAt: time,
            locked: true,
            events: [
              AuditEvent(
                type: AuditEventType.internalClose,
                itemName: 'ORDER',
                previousQty: 0,
                newQty: 0,
                waiterId: 'manager',
                waiterName: 'Synthetic manager',
                timestamp: time,
                note: 'Order closed (non-fiscal)',
                details: {
                  'isFiscal': false,
                  'paymentMethod': 'non-fiscal',
                  'grossAmount': 1000,
                  'advanceApplied': 100,
                  'collectedNow': 0,
                },
              ),
            ],
          ),
        );
      });
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: PosTheme.light,
          home: Scaffold(
            body: AdminAuditLogSection(
              selectedAuditYear: 2026,
              selectedAuditMonth: 10,
              onChangeAuditMonth: (_) {},
              onSetSelectedAuditMonth: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('დეტალურად ნახვა'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('არაფისკალურ'),
        ),
        findsWidgets,
      );
      await tester.runAsync(() => InventoryRepository.applyRuntimeFeatures([]));
      await tester.pump();
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('არაფისკალურ'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Non-fiscal'),
        ),
        findsNothing,
      );
      expect(
        AuditRepository.getAuditReport(1)!.events.single.details!['isFiscal'],
        false,
      );
      expect(
        AuditRepository.getAuditReport(1)!.events.single.note,
        contains('non-fiscal'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'monthly expenses on an internal-only day remain in profit when access is off',
    (tester) async {
      await tester.runAsync(() async {
        final paid = Map<String, dynamic>.from(
          DatabaseCore.salesBox!.get('paid') as Map,
        );
        await DatabaseCore.salesBox!.put('paid', {
          ...paid,
          'date': '2026-10-23',
        });
        await DatabaseCore.expenseBox!.put('synthetic-expense', {
          'date': '2026-10-24',
          'createdAt': '2026-10-24T12:00:00',
          'category': 'other',
          'amount': 100.0,
        });
        await InventoryRepository.applyRuntimeFeatures([
          FeatureKeys.nonFiscalClose,
        ]);
      });
      await host(tester);
      expect(find.textContaining('მოგება: ₾900.00'), findsWidgets);
      await tester.runAsync(() => InventoryRepository.applyRuntimeFeatures([]));
      await tester.pump();
      expect(find.textContaining('მოგება: ₾900.00'), findsWidgets);
      expect(find.textContaining('არაფისკალურ'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
