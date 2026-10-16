class InventoryHistoryPage {
  const InventoryHistoryPage({
    required this.items,
    this.nextCursor,
    this.window = const {},
    this.completeSource = true,
  });
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final Map<String, dynamic> window;
  final bool completeSource;

  factory InventoryHistoryPage.fromJson(Map<String, dynamic> json) {
    if (json['items'] is! List ||
        json['window'] is! Map ||
        (json['nextCursor'] != null && json['nextCursor'] is! String)) {
      throw const FormatException('Invalid Inventory history page');
    }
    return InventoryHistoryPage(
      items: (json['items'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      window: Map<String, dynamic>.from(json['window'] as Map),
    );
  }
}

typedef InventoryHistoryLoader =
    Future<InventoryHistoryPage> Function(String? cursor);
