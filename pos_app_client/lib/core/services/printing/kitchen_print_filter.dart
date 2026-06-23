import 'dart:developer' as developer;

import '../database_service.dart';

/// Filters order item lines down to items that should be printed in kitchen.
class KitchenPrintFilter {
  const KitchenPrintFilter._();

  // Drink/bar category keywords that should NOT go to kitchen (bar items only)
  static List<String> get _barCategoryKeywords =>
      DatabaseService.kitchenExcludedCategoryKeywords;

  /// Filter out drinks from items list (kitchen only needs food)
  static List<String> filterItems(List<String> items) {
    return items.where((item) {
      // Extract item name from format "2x ItemName" or "ItemName"
      final namePart = item.contains('x ')
          ? item.substring(item.indexOf('x ') + 2)
          : item;
      return !_isDrinkItem(namePart);
    }).toList();
  }

  /// Check if an item is a drink/bar item (should not go to kitchen)
  static bool _isDrinkItem(String itemName) {
    try {
      final decision = _resolveKitchenRoutingFromMenu(itemName);
      if (decision != null) {
        return !decision;
      }
    } catch (e) {
      developer.log('Error checking if item is drink: $e');
    }

    // Fall back to keyword-based detection for items missing from the menu cache
    return _matchesDrinkKeyword(itemName);
  }

  // Uses the stored menu configuration to determine if the item should go to kitchen.
  static bool? _resolveKitchenRoutingFromMenu(String itemName) {
    final normalizedName = itemName.trim().toLowerCase();
    if (normalizedName.isEmpty) {
      return null;
    }

    final categories = DatabaseService.getAllMenuCategories();
    for (final category in categories) {
      final bool? directMatch = _matchItemsForRouting(
        category.items,
        normalizedName,
        category.sendToKitchen,
      );
      if (directMatch != null) {
        return directMatch;
      }

      if (category.subcategories != null) {
        for (final subcategory in category.subcategories!) {
          final bool? subMatch = _matchItemsForRouting(
            subcategory.items,
            normalizedName,
            category.sendToKitchen,
          );
          if (subMatch != null) {
            return subMatch;
          }
        }
      }
    }

    return null;
  }

  static bool? _matchItemsForRouting(
    List<dynamic>? items,
    String normalizedName,
    bool categorySendsToKitchen,
  ) {
    if (items == null || items.isEmpty) {
      return null;
    }

    for (final item in items) {
      final itemNameKa = item.getName('ka').trim().toLowerCase();
      final itemNameEn = item.getName('en').trim().toLowerCase();

      if (_nameMatches(normalizedName, itemNameKa) ||
          _nameMatches(normalizedName, itemNameEn)) {
        final bool itemSends = (item.sendToKitchen as bool?) ?? true;
        return categorySendsToKitchen && itemSends;
      }
    }

    return null;
  }

  static bool _nameMatches(String normalizedName, String candidate) {
    if (candidate.isEmpty) {
      return false;
    }
    return normalizedName == candidate ||
        normalizedName.startsWith('$candidate ') ||
        normalizedName.startsWith('$candidate-') ||
        normalizedName.startsWith('$candidate(');
  }

  static bool _matchesDrinkKeyword(String itemName) {
    final normalized = itemName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _barCategoryKeywords.any(
      (keyword) => normalized.contains(keyword.toLowerCase()),
    );
  }
}
