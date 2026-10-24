import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_sales_section.dart';
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
}
