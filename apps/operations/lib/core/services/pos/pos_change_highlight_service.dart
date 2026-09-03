import 'package:vynic/core/models/order.dart';

/// Result of comparing saved order lines vs incoming manager-app lines.
class OrderItemChangeDiff {
  const OrderItemChangeDiff({
    required this.highlightKeys,
    required this.summaryLines,
  });

  final Set<String> highlightKeys;
  final List<String> summaryLines;

  bool get hasLineChanges => highlightKeys.isNotEmpty;
}

/// Pending UI highlights when opening an order after a system notification.
class PosChangeHighlightService {
  PosChangeHighlightService._();

  static final Map<int, Set<String>> _pendingByOrderId = {};

  static void setForOrder(int orderId, Iterable<String> itemKeysOrNames) {
    final keys = itemKeysOrNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (keys.isEmpty) return;
    _pendingByOrderId[orderId] = keys;
  }

  /// Consumed once when [OrderDetailScreen] opens.
  static Set<String>? takeForOrder(int orderId) {
    return _pendingByOrderId.remove(orderId);
  }

  static bool shouldHighlightItem(
    Set<String>? highlights,
    String itemKey,
    String itemName,
  ) {
    if (highlights == null || highlights.isEmpty) return false;
    return highlights.contains(itemKey) || highlights.contains(itemName);
  }

  static String _lineKey(OrderItem item) {
    final key = item.itemKey.trim();
    if (key.isNotEmpty) {
      return '$key|${item.unitPrice.toStringAsFixed(4)}';
    }
    return '${item.itemName.trim()}|${item.unitPrice.toStringAsFixed(4)}';
  }

  static void _registerChangedItem(OrderItem item, Set<String> highlightKeys) {
    final name = item.itemName.trim();
    final key = item.itemKey.trim();
    if (name.isNotEmpty) highlightKeys.add(name);
    if (key.isNotEmpty) highlightKeys.add(key);
  }

  /// Diff `before` (last saved on POS) vs `after` (incoming from manager app).
  static OrderItemChangeDiff computeOrderItemChanges({
    required List<OrderItem> before,
    required List<OrderItem> after,
  }) {
    final beforeMap = <String, OrderItem>{};
    for (final item in before) {
      beforeMap[_lineKey(item)] = item;
    }
    final afterMap = <String, OrderItem>{};
    for (final item in after) {
      afterMap[_lineKey(item)] = item;
    }

    final highlightKeys = <String>{};
    final summaryLines = <String>[];

    for (final entry in afterMap.entries) {
      final prev = beforeMap[entry.key];
      final item = entry.value;
      if (prev == null) {
        _registerChangedItem(item, highlightKeys);
        summaryLines.add('+ ${item.itemName} ×${item.quantity}');
      } else if (prev.quantity != item.quantity) {
        _registerChangedItem(item, highlightKeys);
        summaryLines.add(
          '${item.itemName}: ${prev.quantity} → ${item.quantity}',
        );
      } else if ((prev.unitPrice - item.unitPrice).abs() > 0.009) {
        _registerChangedItem(item, highlightKeys);
        summaryLines.add(
          '${item.itemName}: ფასი ${prev.unitPrice.toStringAsFixed(2)} → ${item.unitPrice.toStringAsFixed(2)}',
        );
      }
    }

    for (final entry in beforeMap.entries) {
      if (!afterMap.containsKey(entry.key)) {
        final item = entry.value;
        _registerChangedItem(item, highlightKeys);
        summaryLines.add('− ${item.itemName}');
      }
    }

    return OrderItemChangeDiff(
      highlightKeys: highlightKeys,
      summaryLines: summaryLines,
    );
  }
}
