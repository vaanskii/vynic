import 'package:flutter/foundation.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/order.dart';

/// Frozen in the same Hive value as the Sale: the Sale is also the durable
/// inventory outbox. Never called when decoding or restoring old history.
abstract final class SaleConsumptionSnapshot {
  static Map<String, dynamic> capture(List<OrderItem> items, bool isFiscal) {
    List<InventoryRecipe> recipes;
    String? catalogTime;
    try {
      recipes = InventoryRepository.getRecipes();
      catalogTime = InventoryRepository.lastRefreshedAt?.toIso8601String();
    } catch (error) {
      debugPrint('[Inventory] Cannot read close-time catalog: $error');
      recipes = const [];
    }
    return build(
      items,
      isFiscal: isFiscal,
      recipes: recipes,
      catalogTime: catalogTime,
    );
  }

  static Map<String, dynamic> build(
    List<OrderItem> items, {
    required bool isFiscal,
    required List<InventoryRecipe> recipes,
    String? catalogTime,
  }) => {
    'version': 1,
    'policy': isFiscal ? 'FISCAL_CLOSE' : 'INTERNAL_EXCLUDED',
    'catalogGeneratedAt': catalogTime,
    'lines': [
      for (var i = 0; i < items.length; i++)
        _line(items[i], i, isFiscal, recipes),
    ],
  };

  static Map<String, dynamic> _line(
    OrderItem item,
    int index,
    bool fiscal,
    List<InventoryRecipe> recipes,
  ) {
    final matches = recipes
        .where(
          (r) =>
              item.menuItemId != null &&
              r.posMenuItemId == item.menuItemId &&
              r.posMenuVariantId == item.variantId &&
              (item.variantId != null || r.variantId == null),
        )
        .toList();
    final recipe = matches.length == 1 ? matches.single : null;
    final line = <String, dynamic>{
      'lineSeq': index,
      'menuItemId': item.menuItemId,
      'variantId': item.variantId,
      'itemName': item.itemName,
      'soldQuantity': item.quantity,
      'status': fiscal ? 'UNMAPPED' : 'EXCLUDED',
      'reason': fiscal
          ? (item.menuItemId == null ? 'MANUAL_LINE' : 'NO_ACTIVE_RECIPE')
          : 'INTERNAL_POLICY',
      'components': <Map<String, dynamic>>[],
    };
    if (!fiscal || recipe == null) return line;
    try {
      if (recipe.components.isEmpty)
        throw const FormatException('Empty recipe');
      final components = [
        for (final c in recipe.components)
          {
            'stockItemId': c.stockItemId,
            'stockItemName': c.stockItemName,
            'baseUnit': c.baseUnit.wireValue,
            'baseQuantityPerUnit': c.baseQuantityPerUnit,
            'totalBaseQuantity': multiply(c.baseQuantityPerUnit, item.quantity),
          },
      ];
      return {
        ...line,
        'status': 'MAPPED',
        'reason': null,
        'recipeId': recipe.recipeId,
        'recipeRevision': recipe.revision,
        'variantName': recipe.variantLabel,
        'components': components,
      };
    } catch (error) {
      debugPrint('[Inventory] Invalid recipe ${recipe.recipeId}: $error');
      return {...line, 'reason': 'INVALID_LOCAL_RECIPE'};
    }
  }

  /// Six decimal fixed-point integers; no floating-point quantity arithmetic.
  static String multiply(String perUnit, int count) {
    if (!RegExp(r'^\d{1,12}\.\d{6}$').hasMatch(perUnit) || count < 1) {
      throw const FormatException('Invalid consumption quantity');
    }
    final value =
        BigInt.parse(perUnit.replaceAll('.', '')) * BigInt.from(count);
    if (value <= BigInt.zero || value.toString().length > 21)
      throw const FormatException('Quantity out of range');
    final digits = value.toString().padLeft(7, '0');
    return '${digits.substring(0, digits.length - 6)}.${digits.substring(digits.length - 6)}';
  }
}
