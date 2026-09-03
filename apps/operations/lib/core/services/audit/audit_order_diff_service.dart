import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order.dart';

/// Builds audit line events from an order item diff (POS menu + mobile ingest).
class AuditOrderDiffService {
  AuditOrderDiffService._();

  static List<AuditEvent> buildEvents({
    required List<OrderItem> previousItems,
    required List<OrderItem> updatedItems,
    required String performerId,
    required String performerName,
    required DateTime timestamp,
  }) {
    final previous = <String, OrderItem>{
      for (final item in previousItems) item.itemKey: item,
    };
    final next = <String, OrderItem>{
      for (final item in updatedItems) item.itemKey: item,
    };
    final keys = {...previous.keys, ...next.keys};
    final events = <AuditEvent>[];

    for (final key in keys) {
      final prevItem = previous[key];
      final nextItem = next[key];
      final prevQty = prevItem?.quantity ?? 0;
      final newQty = nextItem?.quantity ?? 0;
      if (prevQty == newQty) continue;

      final itemName = nextItem?.itemName ?? prevItem?.itemName ?? 'Item';
      final eventType = newQty <= 0
          ? AuditEventType.deleteItem
          : (prevQty == 0 || newQty > prevQty)
          ? AuditEventType.addItem
          : AuditEventType.reduceQty;

      final noteSegments = <String>[];
      final prevComment = prevItem?.comment?.trim();
      final nextComment = nextItem?.comment?.trim();
      if (prevComment != null &&
          prevComment.isNotEmpty &&
          prevComment != nextComment) {
        noteSegments.add('Prev note: $prevComment');
      }
      if (nextComment != null &&
          nextComment.isNotEmpty &&
          nextComment != prevComment) {
        noteSegments.add('Note: $nextComment');
      }

      events.add(
        AuditEvent(
          type: eventType,
          itemName: itemName,
          previousQty: prevQty,
          newQty: newQty,
          waiterId: performerId,
          waiterName: performerName,
          timestamp: timestamp,
          note: noteSegments.isEmpty ? null : noteSegments.join(' • '),
        ),
      );
    }

    return events;
  }
}
