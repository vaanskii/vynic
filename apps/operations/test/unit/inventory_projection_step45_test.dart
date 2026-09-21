import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/inventory.dart';

void main() {
  test(
    'classification, supplier links and item-specific keg survive Hive restart/backup',
    () async {
      final directory = await Directory.systemTemp.createTemp('step45-catalog');
      Hive.init(directory.path);
      try {
        DatabaseCore.inventoryBox = await Hive.openBox('step45');
        final catalog = {
          'version': 4,
          'generatedAt': '2026-09-06T12:00:00Z',
          'stockItems': [
            {
              'id': 'food',
              'name': 'Beef',
              'baseUnit': 'kg',
              'classification': 'FOOD',
            },
            {
              'id': 'drink',
              'name': 'Draft beer',
              'baseUnit': 'L',
              'classification': 'BEVERAGE',
              'supplierIds': ['supplier'],
              'purchaseUnits': [
                {
                  'id': 'keg-unit',
                  'unit': 'keg',
                  'baseUnitMultiplier': '30.000000',
                },
              ],
            },
          ],
          'suppliers': [
            {
              'id': 'supplier',
              'name': 'Market',
              'stockItemIds': ['drink'],
            },
          ],
        };
        await InventoryRepository.replaceCatalog(catalog);
        await DatabaseCore.inventoryBox!.close();
        DatabaseCore.inventoryBox = await Hive.openBox('step45');
        final items = InventoryRepository.getStockItems();
        expect(items.first.classification, StockItemClassification.food);
        expect(items.last.classification, StockItemClassification.beverage);
        expect(items.last.supplierIds, ['supplier']);
        expect(items.last.purchaseUnits.single.unit, InventoryUnit.keg);
        expect(InventoryRepository.getSuppliers().single.email, isNull);
        await InventoryRepository.restoreCatalog(catalog);
        expect(
          InventoryRepository.getStockItems().last.classification,
          StockItemClassification.beverage,
        );
        expect(InventoryRepository.getSuppliers().single.stockItemIds, [
          'drink',
        ]);
      } finally {
        await Hive.close();
        DatabaseCore.inventoryBox = null;
        await directory.delete(recursive: true);
      }
    },
  );
}
