import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/services/pos/sale_consumption_snapshot.dart';
import 'package:vynic/core/services/edge/sale_consumption_sync_service.dart';

void main() {
  InventoryRecipe recipe({
    String variant = 'half',
    String quantity = '0.500000',
    int revision = 1,
  }) => InventoryRecipe(
    recipeId: 'recipe-$variant',
    revision: revision,
    menuItemId: 'cloud-menu',
    posMenuItemId: 'menu',
    variantId: 'cloud-$variant',
    posMenuVariantId: variant,
    components: [
      InventoryRecipeComponent(
        stockItemId: 'beer',
        stockItemName: 'Beer',
        baseQuantityPerUnit: quantity,
        baseUnit: InventoryUnit.liter,
      ),
    ],
  );
  OrderItem item(
    int count, {
    String? menu = 'menu',
    String? variant = 'half',
  }) => OrderItem(
    itemKey: 'beer',
    total: count * 10.0,
    itemName: 'Beer',
    quantity: count,
    unitPrice: 10,
    menuItemId: menu,
    variantId: variant,
  );
  test('exact draft, ingredient and small quantities use fixed point', () {
    expect(SaleConsumptionSnapshot.multiply('0.035000', 10), '0.350000');
    expect(SaleConsumptionSnapshot.multiply('0.500000', 4), '2.000000');
    expect(SaleConsumptionSnapshot.multiply('0.300000', 3), '0.900000');
    expect(SaleConsumptionSnapshot.multiply('0.000010', 3), '0.000030');
    expect(SaleConsumptionSnapshot.multiply('1.000000', 8), '8.000000');
  });
  test(
    'exact variant match and frozen revision; no name or default variant fallback',
    () {
      final a = SaleConsumptionSnapshot.build(
        [item(4), item(3, variant: 'third'), item(1, variant: 'unknown')],
        isFiscal: true,
        recipes: [
          recipe(),
          recipe(variant: 'third', quantity: '0.300000'),
        ],
      );
      final lines = a['lines'] as List;
      expect(lines[0]['components'][0]['totalBaseQuantity'], '2.000000');
      expect(lines[1]['components'][0]['totalBaseQuantity'], '0.900000');
      expect(lines[2]['status'], 'UNMAPPED');
      final b = SaleConsumptionSnapshot.build(
        [item(1)],
        isFiscal: true,
        recipes: [recipe(quantity: '0.600000', revision: 2)],
      );
      expect(lines[0]['recipeRevision'], 1);
      expect(b['lines'][0]['recipeRevision'], 2);
      expect(lines[0]['components'][0]['baseQuantityPerUnit'], '0.500000');
    },
  );
  test(
    'manual, disabled/absent, invalid and internal definitions never fabricate stock',
    () {
      final manual = SaleConsumptionSnapshot.build(
        [item(1, menu: null)],
        isFiscal: true,
        recipes: [recipe()],
      );
      expect(manual['lines'][0]['reason'], 'MANUAL_LINE');
      final disabled = SaleConsumptionSnapshot.build(
        [item(1)],
        isFiscal: true,
        recipes: [],
      );
      expect(disabled['lines'][0]['status'], 'UNMAPPED');
      final invalid = SaleConsumptionSnapshot.build(
        [item(1)],
        isFiscal: true,
        recipes: [recipe(quantity: 'NaN')],
      );
      expect(invalid['lines'][0]['reason'], 'INVALID_LOCAL_RECIPE');
      final internal = SaleConsumptionSnapshot.build(
        [item(1)],
        isFiscal: false,
        recipes: [recipe()],
      );
      expect(internal['policy'], 'INTERNAL_EXCLUDED');
      expect(internal['lines'][0]['components'], isEmpty);
    },
  );
  group('durable independent retry', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('consumption_outbox');
      Hive.init(dir.path);
      DatabaseCore.salesBox = await Hive.openBox('sales');
    });
    tearDown(() async {
      await Hive.close();
      DatabaseCore.salesBox = null;
      await dir.delete(recursive: true);
    });
    Map<String, dynamic> sale(String id) => {
      'posSaleId': id,
      'closureId': 'close-$id',
      'orderId': 1,
      'date': '2026-09-05',
      'closedAt': '2026-09-05T10:00:00Z',
      'inventoryConsumption': SaleConsumptionSnapshot.build(
        [item(4)],
        isFiscal: true,
        recipes: [recipe()],
      ),
    };
    SaleConsumptionSyncService client(
      Future<http.Response> Function(http.Request) handler,
    ) => SaleConsumptionSyncService(
      client: MockClient(handler),
      baseUrl: () => 'http://isolated.test',
      credential: () => 'test-device',
    );
    test(
      'offline, restart, lost response replay and acknowledgement leave Sale intact',
      () async {
        await DatabaseCore.salesBox!.put('a', sale('a'));
        final offline = client(
          (_) async => throw const SocketException('offline'),
        );
        await offline.syncOnce();
        expect(SaleConsumptionSyncService.pending(), hasLength(1));
        await Hive.close();
        DatabaseCore.salesBox = await Hive.openBox('sales');
        final serverEffects = <String>{};
        var loseResponse = true;
        final online = client((request) async {
          final body = jsonDecode(request.body);
          serverEffects.add(body['posSaleId'] as String);
          if (loseResponse) {
            loseResponse = false;
            throw const SocketException('lost ACK');
          }
          return http.Response(
            jsonEncode({'posSaleId': body['posSaleId'], 'revision': 1}),
            201,
          );
        });
        await online.syncOnce();
        await online.syncOnce();
        await online.syncOnce();
        expect(serverEffects, {'a'});
        expect(SaleConsumptionSyncService.pending(), isEmpty);
        expect(
          DatabaseCore.salesBox!.get('a')['inventoryConsumption'],
          sale('a')['inventoryConsumption'],
        );
      },
    );
    test(
      'one rejected effect does not prevent another; restore concurrent with ACK remains pending',
      () async {
        await DatabaseCore.salesBox!.put('a', sale('a'));
        await DatabaseCore.salesBox!.put('b', sale('b'));
        final online = client((request) async {
          final body = jsonDecode(request.body);
          if (body['posSaleId'] == 'a') return http.Response('bad', 400);
          await DatabaseCore.salesBox!.put('b', {
            ...DatabaseCore.salesBox!.get('b') as Map,
            'restoredToOrder': true,
            'restoredAt': '2026-09-05T12:00:00Z',
          });
          return http.Response('{"posSaleId":"b","revision":1}', 201);
        });
        await online.syncOnce();
        expect(DatabaseCore.salesBox!.get('b')['restoredToOrder'], true);
        expect(SaleConsumptionSyncService.pending(), hasLength(2));
        final reverse = client(
          (request) async => http.Response(
            jsonEncode({
              'posSaleId': jsonDecode(request.body)['posSaleId'],
              'revision': jsonDecode(request.body)['reversedAt'] == null
                  ? 1
                  : 2,
            }),
            201,
          ),
        );
        await reverse.syncOnce();
        expect(SaleConsumptionSyncService.pending(), isEmpty);
      },
    );
    test(
      'historical Sales and cancellation sentinels without new intent are never backfilled',
      () async {
        await DatabaseCore.salesBox!.add({
          'posSaleId': 'legacy',
          'isFiscal': true,
        });
        await DatabaseCore.salesBox!.add({
          'posSaleId': 'cancelled',
          'isCancelled': true,
        });
        expect(SaleConsumptionSyncService.pending(), isEmpty);
      },
    );
  });
}
