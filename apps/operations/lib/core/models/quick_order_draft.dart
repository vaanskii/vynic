import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:hive/hive.dart';

import 'order.dart';

part 'quick_order_draft.g.dart';

@HiveType(typeId: 14)
class QuickOrderDraft extends HiveObject with UpdateTrackedHiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  List<OrderItem> items;

  @HiveField(2)
  double subtotal;

  @HiveField(3)
  double serviceFeeAmount;

  @HiveField(4)
  double total;

  @HiveField(5)
  bool includeServiceFee;

  @HiveField(6)
  double serviceFeeRate;

  @HiveField(7)
  DateTime createdAt;

  @HiveField(8)
  String createdBy;

  @HiveField(9)
  String? displayName;

  @HiveField(10)
  String? customerName;

  @HiveField(11)
  String? customerPhone;

  QuickOrderDraft({
    required this.id,
    required this.items,
    required this.subtotal,
    required this.serviceFeeAmount,
    required this.total,
    required this.includeServiceFee,
    required this.serviceFeeRate,
    required this.createdAt,
    required this.createdBy,
    this.displayName,
    this.customerName,
    this.customerPhone,
  });

  /// Search actual saved contact information and the payable estimate amount.
  bool matchesSearch(String input) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return true;
    final amount = double.tryParse(query.replaceAll(',', '.'));
    if (amount != null && (total - amount).abs() < 0.005) return true;
    final phone = query.replaceAll(RegExp(r'[^0-9]'), '');
    return (customerName ?? '').toLowerCase().contains(query) ||
        (displayName ?? '').toLowerCase().contains(query) ||
        (RegExp(r'^[+0-9\s()-]+$').hasMatch(query) &&
            phone.isNotEmpty &&
            (customerPhone ?? '')
                .replaceAll(RegExp(r'[^0-9]'), '')
                .contains(phone)) ||
        createdBy.toLowerCase().contains(query) ||
        items.any((item) => item.itemName.toLowerCase().contains(query));
  }
}
