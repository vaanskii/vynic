import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/inventory.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vynic_inventory');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('inventory_test');
    DatabaseCore.inventoryBox = await Hive.openBox('inventory_test');
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.inventoryBox = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('mass and volume conversions are canonical', () {
    expect(
      convertInventoryQuantity(1, from: InventoryUnit.kg, to: InventoryUnit.g),
      1000,
    );
    expect(
      convertInventoryQuantity(
        1250,
        from: InventoryUnit.g,
        to: InventoryUnit.kg,
      ),
      1.25,
    );
    expect(
      convertInventoryQuantity(
        1,
        from: InventoryUnit.liter,
        to: InventoryUnit.ml,
      ),
      1000,
    );
    expect(
      convertInventoryQuantity(
        750,
        from: InventoryUnit.ml,
        to: InventoryUnit.liter,
      ),
      0.75,
    );
  });

  test('incompatible and count-unit conversions are protected', () {
    expect(
      () => convertInventoryQuantity(
        1,
        from: InventoryUnit.kg,
        to: InventoryUnit.liter,
      ),
      throwsArgumentError,
    );
    expect(
      () => convertInventoryQuantity(
        1,
        from: InventoryUnit.box,
        to: InventoryUnit.piece,
      ),
      throwsArgumentError,
    );
  });

  test(
    'legacy-compatible decoding defaults active and preserves stable id',
    () {
      final item = StockItem.fromJson({
        'id': 'stock-immutable-1',
        'name': 'Beef',
        'baseUnit': 'kg',
        'minimumStock': '2.500',
        'createdAt': '2026-09-05T10:00:00Z',
        'updatedAt': '2026-09-05T10:00:00Z',
      });
      final roundTrip = StockItem.fromJson(item.toJson());

      expect(item.isActive, isTrue);
      // A payload with no balance reads as an honest zero and no threshold
      // verdict, never as a fabricated number.
      expect(item.currentStock, '0.000');
      expect(item.currentStockValue, 0);
      expect(item.stockStatus, 'NO_MINIMUM');
      expect(item.isLowStock, isFalse);
      expect(roundTrip.id, 'stock-immutable-1');
      expect(roundTrip.minimumStock, 2.5);
    },
  );

  test(
    'one atomic catalog value supports same-name items and offline reads',
    () async {
      await InventoryRepository.replaceCatalog({
        'version': 1,
        'generatedAt': '2026-09-05T10:00:00Z',
        'stockItems': [
          _stock('stock-1', 'Beef', 'kg'),
          _stock('stock-2', 'Beef', 'g'),
        ],
        'suppliers': [_supplier('supplier-1', 'Farm')],
      });

      expect(DatabaseCore.inventoryBox!.keys, [InventoryRepository.catalogKey]);
      expect(InventoryRepository.getStockItems().map((item) => item.id), [
        'stock-1',
        'stock-2',
      ]);
      expect(InventoryRepository.getSuppliers().single.id, 'supplier-1');
      expect(
        InventoryRepository.lastRefreshedAt,
        DateTime.parse('2026-09-05T10:00:00Z'),
      );
    },
  );
}

Map<String, dynamic> _stock(String id, String name, String unit) => {
  'id': id,
  'name': name,
  'baseUnit': unit,
  'isActive': true,
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
};

Map<String, dynamic> _supplier(String id, String name) => {
  'id': id,
  'name': name,
  'isActive': true,
  'createdAt': '2026-09-05T10:00:00Z',
  'updatedAt': '2026-09-05T10:00:00Z',
};
