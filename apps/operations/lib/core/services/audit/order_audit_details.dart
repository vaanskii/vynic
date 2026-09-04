import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';

/// The structured `details` every Order-level audit event carries.
///
/// One builder so the creation, transfer and closure events agree on the key
/// names a reader filters by: `orderId`, `orderKind`, `tableRefs`, `floor`,
/// `source`, `actorId`, `actorName`, `businessDate`. Event-specific keys are
/// layered on top by the caller.
abstract final class OrderAuditDetails {
  /// `WALK_IN`, `TAKEAWAY`, `PACKAGE` or `RESERVATION`.
  static const String walkIn = 'WALK_IN';
  static const String takeaway = 'TAKEAWAY';
  static const String package = 'PACKAGE';
  static const String reservation = 'RESERVATION';

  /// The `itemName` an Order-level event carries; it names no line.
  static const String orderItemName = 'ORDER';

  static Map<String, dynamic> base({
    required Order order,
    required String orderKind,
    required AuditSource source,
    required String actorId,
    String? actorName,
  }) {
    final name = (actorName == null || actorName.trim().isEmpty)
        ? actorId
        : actorName;
    return <String, dynamic>{
      'orderId': order.orderId,
      'orderKind': orderKind,
      'tableNumbers': List<String>.from(order.tableNumbers),
      'tableRefs': tableRefs(order),
      'floor': order.floor,
      AuditSource.detailsKey: source.wireValue,
      'actorId': actorId,
      'actorName': name,
      'businessDate': businessDate(),
    };
  }

  static List<String> tableRefs(Order order) => order.tableNumbers
      .map((tableNumber) => '${order.floor}/$tableNumber')
      .toList(growable: false);

  static String businessDate() =>
      BusinessDayRepository.getCurrentDate().toIso8601String().split('T')[0];

  /// A timestamp guaranteed to sort after [previous].
  ///
  /// Two writes inside one call can land on the same millisecond, and the
  /// report is ordered by timestamp. A package applied at the instant its
  /// Order was opened must still read as the second thing that happened.
  static DateTime strictlyAfter(DateTime previous, DateTime now) =>
      now.isAfter(previous)
      ? now
      : previous.add(const Duration(milliseconds: 1));
}
