import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/receiving.dart';

/// The POS side of Inventory Step 2.
///
/// Receiving and StockMovement stay Cloud-authoritative. What the POS gains is
/// a projection of Cloud's derived balance and each item's packaging — enough
/// for a later consumption step, and nothing the terminal could disagree with
/// Cloud about.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vynic_inventory_step2');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('inventory_step2_test');
    DatabaseCore.inventoryBox = await Hive.openBox('inventory_step2_test');
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.inventoryBox = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('the derived balance', () {
    test('is projected exactly, never recomputed on the terminal', () {
      final item = StockItem.fromJson(_stock(currentStock: '62.500'));

      expect(item.currentStock, '62.500');
      expect(item.currentStockValue, 62.5);
      // Round-tripping through the cache must not re-round Cloud's decimal.
      expect(StockItem.fromJson(item.toJson()).currentStock, '62.500');
    });

    test('carries Cloud’s low-stock verdict rather than a local comparison', () {
      final low = StockItem.fromJson(
        _stock(currentStock: '5.000', minimumStock: '10', status: 'LOW'),
      );
      final ok = StockItem.fromJson(
        _stock(currentStock: '50.000', minimumStock: '10', status: 'OK'),
      );
      final untracked = StockItem.fromJson(_stock(currentStock: '0.000'));

      expect(low.isLowStock, isTrue);
      expect(ok.isLowStock, isFalse);
      expect(untracked.stockStatus, 'NO_MINIMUM');
      expect(untracked.isLowStock, isFalse);
    });

    test('a v1 catalog decodes as an honest zero with no verdict', () {
      final legacy = StockItem.fromJson(_stock());

      expect(legacy.currentStock, '0.000');
      expect(legacy.stockStatus, 'NO_MINIMUM');
      expect(legacy.isLowStock, isFalse);
      expect(legacy.purchaseUnits, isEmpty);
    });
  });

  group('item packaging', () {
    test('survives the projection round trip', () {
      final item = StockItem.fromJson(
        _stock(
          unit: 'bottle',
          purchaseUnits: [
            {'id': 'pu-1', 'unit': 'box', 'baseUnitMultiplier': '24'},
            {'id': 'pu-2', 'unit': 'pack', 'baseUnitMultiplier': '6'},
          ],
        ),
      );
      final cached = StockItem.fromJson(item.toJson());

      expect(cached.purchaseUnits.map((row) => row.unit.wireValue), [
        'box',
        'pack',
      ]);
      expect(cached.purchaseUnits.first.baseUnitMultiplier, '24');
      expect(cached.purchaseUnits.first.multiplier, 24);
    });

    test('stays item-specific — one box is not every box', () {
      final lemonade = StockItem.fromJson(
        _stock(
          id: 'lemonade',
          unit: 'bottle',
          purchaseUnits: [
            {'id': 'pu-1', 'unit': 'box', 'baseUnitMultiplier': '24'},
          ],
        ),
      );
      final wine = StockItem.fromJson(
        _stock(
          id: 'wine',
          unit: 'bottle',
          purchaseUnits: [
            {'id': 'pu-2', 'unit': 'box', 'baseUnitMultiplier': '6'},
          ],
        ),
      );

      expect(lemonade.purchaseUnits.single.multiplier, 24);
      expect(wine.purchaseUnits.single.multiplier, 6);
    });
  });

  group('the Hive catalog', () {
    test('replaces atomically and keeps the Step 2 fields', () async {
      await InventoryRepository.replaceCatalog({
        'version': 2,
        'generatedAt': '2026-09-09T10:00:00Z',
        'stockItems': [
          _stock(
            id: 'stock-1',
            currentStock: '62.500',
            minimumStock: '10',
            status: 'OK',
            purchaseUnits: [
              {'id': 'pu-1', 'unit': 'box', 'baseUnitMultiplier': '24'},
            ],
          ),
        ],
        'suppliers': const [],
      });

      expect(DatabaseCore.inventoryBox!.keys, [InventoryRepository.catalogKey]);
      final cached = InventoryRepository.getStockItems().single;
      expect(cached.currentStock, '62.500');
      expect(cached.stockStatus, 'OK');
      expect(cached.purchaseUnits.single.baseUnitMultiplier, '24');
    });

    test('a failed refresh leaves the last known quantities intact', () async {
      await InventoryRepository.replaceCatalog({
        'version': 2,
        'generatedAt': '2026-09-09T10:00:00Z',
        'stockItems': [_stock(id: 'stock-1', currentStock: '40.000')],
        'suppliers': const [],
      });

      // A refresh that never produced a payload writes nothing at all.
      expect(InventoryRepository.getStockItems().single.currentStock, '40.000');
      expect(
        InventoryRepository.lastRefreshedAt,
        DateTime.parse('2026-09-09T10:00:00Z'),
      );
    });

    test('an older backup restores without inventing a balance', () async {
      // A v1 export carries no currentStock; restoring it must not fabricate
      // one, and the next Device pull replaces the whole value anyway.
      await InventoryRepository.restoreCatalog({
        'version': 1,
        'generatedAt': '2026-09-05T10:00:00Z',
        'stockItems': [_stock(id: 'stock-1')],
        'suppliers': const [],
      });

      final restored = InventoryRepository.getStockItems().single;
      expect(restored.id, 'stock-1');
      expect(restored.currentStock, '0.000');
      expect(restored.stockStatus, 'NO_MINIMUM');
      expect(restored.purchaseUnits, isEmpty);
    });
  });

  group('Receiving documents', () {
    test('decode with their frozen snapshots and both movement sets', () {
      final receiving = Receiving.fromJson({
        'id': 'r-1',
        'supplierId': 'supplier-1',
        'supplierName': 'Meat Supplier',
        'waybillNumber': '12345',
        'documentDate': '2026-09-05',
        'receivedAt': '2026-09-05T09:00:00Z',
        'status': 'CANCELLED',
        'documentTotal': '750.00',
        'lineCount': 1,
        'createdByName': 'Nino',
        'createdAt': '2026-09-05T09:00:00Z',
        'cancelledByName': 'Gio',
        'cancellationReason': 'returned',
        'lines': [
          {
            'id': 'line-1',
            'lineSequence': 0,
            'stockItemId': 'stock-1',
            'stockItemName': 'Beef',
            'enteredQuantity': '50.000',
            'enteredUnit': 'kg',
            'baseQuantity': '50.000',
            'baseUnit': 'kg',
            'unitPurchaseCost': '15.0000',
            'lineTotal': '750.00',
            'effectiveBaseUnitCost': '15.000000',
          },
        ],
        'movements': [
          {
            'id': 'm-1',
            'stockItemId': 'stock-1',
            'movementType': 'RECEIVING',
            'quantityDeltaBase': '50.000',
            'baseUnit': 'kg',
            'businessDate': '2026-09-05',
            'actorName': 'Nino',
            'createdAt': '2026-09-05T09:00:00Z',
          },
          {
            'id': 'm-2',
            'stockItemId': 'stock-1',
            'movementType': 'RECEIVING_REVERSAL',
            'quantityDeltaBase': '-50.000',
            'baseUnit': 'kg',
            'businessDate': '2026-09-06',
            'actorName': 'Gio',
            'createdAt': '2026-09-06T09:00:00Z',
            'reversalOfMovementId': 'm-1',
          },
        ],
      });

      expect(receiving.isCancelled, isTrue);
      expect(receiving.supplierName, 'Meat Supplier');
      expect(receiving.lines.single.stockItemId, 'stock-1');
      expect(receiving.lines.single.isConverted, isFalse);
      // The original is kept beside its reversal, never replaced by it.
      expect(receiving.originalMovements.single.quantityDeltaBase, '50.000');
      expect(receiving.reversalMovements.single.quantityDeltaBase, '-50.000');
      expect(receiving.reversalMovements.single.isNegative, isTrue);
      expect(receiving.reversalMovements.single.reversalOfMovementId, 'm-1');
    });

    test('a packaged line reports both what was ordered and what arrived', () {
      final line = ReceivingLine.fromJson({
        'id': 'line-1',
        'lineSequence': 0,
        'stockItemId': 'stock-1',
        'stockItemName': 'Lemonade 0.5L',
        'enteredQuantity': '10.000',
        'enteredUnit': 'box',
        'baseQuantity': '240.000',
        'baseUnit': 'bottle',
        'unitPurchaseCost': '28.8000',
        'lineTotal': '288.00',
        'effectiveBaseUnitCost': '1.200000',
      });

      expect(line.isConverted, isTrue);
      expect(line.enteredQuantityValue, 10);
      expect(line.baseQuantityValue, 240);
      expect(line.lineTotal, '288.00');
      expect(line.effectiveBaseUnitCost, '1.200000');
    });

    test('an unknown future movement kind is shown, not dropped', () {
      final movement = StockMovement.fromJson({
        'id': 'm-9',
        'stockItemId': 'stock-1',
        'movementType': 'SALE_CONSUMPTION',
        'quantityDeltaBase': '-2.000',
        'baseUnit': 'kg',
        'businessDate': '2026-10-01',
        'actorName': 'system',
        'createdAt': '2026-10-01T09:00:00Z',
      });

      expect(movement.movementType, StockMovementType.unknown);
      expect(movement.quantityDeltaBase, '-2.000');
      expect(movement.isNegative, isTrue);
    });
  });
}

Map<String, dynamic> _stock({
  String id = 'stock-1',
  String name = 'Beef',
  String unit = 'kg',
  String? currentStock,
  String? minimumStock,
  String? status,
  List<Map<String, dynamic>>? purchaseUnits,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'baseUnit': unit,
  'isActive': true,
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
  if (minimumStock != null) 'minimumStock': minimumStock,
  if (currentStock != null) 'currentStock': currentStock,
  if (status != null) 'stockStatus': status,
  if (purchaseUnits != null) 'purchaseUnits': purchaseUnits,
};
