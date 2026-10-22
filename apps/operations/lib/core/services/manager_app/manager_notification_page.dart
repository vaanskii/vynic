class ManagerNotificationPage {
  const ManagerNotificationPage({
    required this.items,
    required this.watermark,
    this.nextCursor,
  });

  final List<Map<String, dynamic>> items;
  final String watermark;
  final String? nextCursor;

  factory ManagerNotificationPage.fromJson(Object? value) {
    if (value is! Map ||
        value['items'] is! List ||
        value['watermark'] is! String ||
        DateTime.tryParse(value['watermark'] as String) == null ||
        (value['nextCursor'] != null &&
            (value['nextCursor'] is! String ||
                (value['nextCursor'] as String).isEmpty))) {
      throw const FormatException('Invalid notification page');
    }
    final items = value['items'] as List;
    if (items.any((row) => row is! Map))
      throw const FormatException('Invalid notification row');
    return ManagerNotificationPage(
      items: items.map((row) => Map<String, dynamic>.from(row as Map)).toList(),
      watermark: value['watermark'] as String,
      nextCursor: value['nextCursor'] as String?,
    );
  }
}
