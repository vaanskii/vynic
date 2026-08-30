import 'package:hive/hive.dart';

import 'order.dart';

part 'quick_order_draft.g.dart';

@HiveType(typeId: 14)
class QuickOrderDraft extends HiveObject {
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
  });
}
