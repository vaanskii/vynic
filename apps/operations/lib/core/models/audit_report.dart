import 'package:collection/collection.dart';

enum AuditReportStatus { open, closed, cancelled }

enum AuditEventType { addItem, reduceQty, deleteItem, cancelTable, custom }

AuditReportStatus _statusFromString(String? raw) {
  switch (raw) {
    case 'OPEN':
      return AuditReportStatus.open;
    case 'CLOSED':
      return AuditReportStatus.closed;
    case 'CANCELLED':
      return AuditReportStatus.cancelled;
    default:
      return AuditReportStatus.open;
  }
}

AuditEventType auditEventTypeFromString(String? raw) {
  final normalized = raw?.trim().toUpperCase().replaceAll(' ', '_');
  switch (normalized) {
    case 'ADD_ITEM':
    case 'ADDITEM':
    case 'ADD':
      return AuditEventType.addItem;
    case 'REDUCE_QTY':
    case 'REDUCE_QUANTITY':
    case 'REDUCEQTY':
      return AuditEventType.reduceQty;
    case 'DELETE_ITEM':
    case 'DELETEITEM':
    case 'REMOVE_ITEM':
    case 'REMOVEITEM':
      return AuditEventType.deleteItem;
    case 'CANCEL_TABLE':
    case 'CANCELTABLE':
      return AuditEventType.cancelTable;
    default:
      break;
  }
  switch (raw?.trim().toLowerCase()) {
    case 'add_item':
      return AuditEventType.addItem;
    case 'reduce_quantity':
    case 'reduce_qty':
      return AuditEventType.reduceQty;
    case 'remove_item':
    case 'delete_item':
      return AuditEventType.deleteItem;
    case 'cancel_table':
      return AuditEventType.cancelTable;
    default:
      return AuditEventType.custom;
  }
}

/// When stored type is missing/legacy, infer from quantity delta (matches POS logic).
AuditEventType inferAuditEventType({
  required AuditEventType parsed,
  required int previousQty,
  required int newQty,
}) {
  if (parsed != AuditEventType.custom) return parsed;
  if (newQty <= 0 && previousQty > 0) return AuditEventType.deleteItem;
  if (newQty > 0 && newQty < previousQty) return AuditEventType.reduceQty;
  if (newQty > previousQty) return AuditEventType.addItem;
  return parsed;
}

String auditEventTypeToString(AuditEventType type) {
  switch (type) {
    case AuditEventType.addItem:
      return 'ADD_ITEM';
    case AuditEventType.reduceQty:
      return 'REDUCE_QTY';
    case AuditEventType.deleteItem:
      return 'DELETE_ITEM';
    case AuditEventType.cancelTable:
      return 'CANCEL_TABLE';
    case AuditEventType.custom:
      return 'CUSTOM';
  }
}

/// The time a record carries when it carries none.
///
/// Deserialization used to substitute `DateTime.now()` for a missing or
/// unparseable timestamp. That made the report's serialized content different
/// on every read, so its sync revision changed every time it was looked at and
/// the backend could never acknowledge it — a report in that state was pushed
/// again on every single sync, forever. A fixed value is a visibly unknown
/// time; a moving one is a silently wrong one.
final DateTime unknownAuditTimestamp = DateTime.fromMillisecondsSinceEpoch(
  0,
  isUtc: true,
);

/// Reads a stored timestamp, or null when there is nothing usable to read.
DateTime? parseAuditTimestamp(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}

class AuditEvent {
  const AuditEvent({
    required this.type,
    required this.itemName,
    required this.previousQty,
    required this.newQty,
    required this.waiterId,
    required this.waiterName,
    required this.timestamp,
    this.note,
  });

  final AuditEventType type;
  final String itemName;
  final int previousQty;
  final int newQty;
  final String waiterId;
  final String waiterName;
  final DateTime timestamp;
  final String? note;

  AuditEvent copyWith({
    AuditEventType? type,
    String? itemName,
    int? previousQty,
    int? newQty,
    String? waiterId,
    String? waiterName,
    DateTime? timestamp,
    String? note,
  }) {
    return AuditEvent(
      type: type ?? this.type,
      itemName: itemName ?? this.itemName,
      previousQty: previousQty ?? this.previousQty,
      newQty: newQty ?? this.newQty,
      waiterId: waiterId ?? this.waiterId,
      waiterName: waiterName ?? this.waiterName,
      timestamp: timestamp ?? this.timestamp,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': auditEventTypeToString(type),
      'itemName': itemName,
      'previousQty': previousQty,
      'newQty': newQty,
      'waiterId': waiterId,
      'waiterName': waiterName,
      'timestamp': timestamp.toIso8601String(),
      if (note != null && note!.isNotEmpty) 'note': note,
    };
  }

  /// [fallbackTimestamp] is used when the stored event has no usable time of
  /// its own. It must be a stable value derived from the record — never `now`,
  /// which would change the event's content on every read.
  static AuditEvent fromMap(
    Map<String, dynamic> map, {
    DateTime? fallbackTimestamp,
  }) {
    final previousQty = (map['previousQty'] as num?)?.toInt() ?? 0;
    final newQty = (map['newQty'] as num?)?.toInt() ?? 0;
    final type = inferAuditEventType(
      parsed: auditEventTypeFromString(map['type'] as String?),
      previousQty: previousQty,
      newQty: newQty,
    );
    final itemName = (map['itemName'] as String?) ?? '';
    final waiterId = (map['waiterId'] as String?) ?? '';
    final waiterName = (map['waiterName'] as String?) ?? waiterId;
    final timestamp =
        parseAuditTimestamp(map['timestamp']) ??
        fallbackTimestamp ??
        unknownAuditTimestamp;
    final note = (map['note'] as String?)?.trim();

    return AuditEvent(
      type: type,
      itemName: itemName,
      previousQty: previousQty,
      newQty: newQty,
      waiterId: waiterId,
      waiterName: waiterName,
      timestamp: timestamp,
      note: note?.isEmpty == true ? null : note,
    );
  }
}

class AuditReport {
  const AuditReport({
    required this.reportId,
    required this.orderId,
    required this.tableNumbers,
    required this.floor,
    required this.openedById,
    required this.openedByName,
    required this.openedAt,
    required this.status,
    required this.events,
    required this.updatedAt,
    this.closedAt,
    this.closedById,
    this.closedByName,
    this.locked = false,
  });

  final String reportId;
  final int orderId;
  final List<String> tableNumbers;
  final String floor;
  final String openedById;
  final String openedByName;
  final DateTime openedAt;
  final AuditReportStatus status;
  final List<AuditEvent> events;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final String? closedById;
  final String? closedByName;
  final bool locked;

  AuditReport copyWith({
    String? reportId,
    int? orderId,
    List<String>? tableNumbers,
    String? floor,
    String? openedById,
    String? openedByName,
    DateTime? openedAt,
    AuditReportStatus? status,
    List<AuditEvent>? events,
    DateTime? updatedAt,
    DateTime? closedAt,
    String? closedById,
    String? closedByName,
    bool? locked,
  }) {
    return AuditReport(
      reportId: reportId ?? this.reportId,
      orderId: orderId ?? this.orderId,
      tableNumbers: tableNumbers ?? this.tableNumbers,
      floor: floor ?? this.floor,
      openedById: openedById ?? this.openedById,
      openedByName: openedByName ?? this.openedByName,
      openedAt: openedAt ?? this.openedAt,
      status: status ?? this.status,
      events: events ?? this.events,
      updatedAt: updatedAt ?? this.updatedAt,
      closedAt: closedAt ?? this.closedAt,
      closedById: closedById ?? this.closedById,
      closedByName: closedByName ?? this.closedByName,
      locked: locked ?? this.locked,
    );
  }

  List<AuditEvent> get sortedEvents {
    return events.sorted((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Map<String, dynamic> toMap() {
    return {
      'reportId': reportId,
      'orderId': orderId,
      'tableNumbers': tableNumbers,
      'floor': floor,
      'openedById': openedById,
      'openedByName': openedByName,
      'openedAt': openedAt.toIso8601String(),
      'status': status.name.toUpperCase(),
      'events': events.map((event) => event.toMap()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
      'locked': locked,
      if (closedAt != null) 'closedAt': closedAt!.toIso8601String(),
      if (closedById != null && closedById!.isNotEmpty)
        'closedById': closedById,
      if (closedByName != null && closedByName!.isNotEmpty)
        'closedByName': closedByName,
    };
  }

  static AuditReport fromMap(Map<dynamic, dynamic> map) {
    final reportId = (map['reportId'] as String?) ?? '';
    final orderId = (map['orderId'] as num?)?.toInt() ?? 0;
    final tableNumbers = ((map['tableNumbers'] as List?) ?? const [])
        .map((entry) => entry.toString())
        .toList();
    final floor = (map['floor'] as String?) ?? 'first';
    final openedById = (map['openedById'] as String?) ?? '';
    final openedByName = (map['openedByName'] as String?) ?? openedById;
    final status = _statusFromString(map['status'] as String?);

    // Times are resolved from the record itself and nothing else. Every
    // fallback below is another field of this same report, so reading it twice
    // produces the same report — which is what lets its sync revision settle.
    final storedOpenedAt = parseAuditTimestamp(map['openedAt']);
    final storedUpdatedAt = parseAuditTimestamp(map['updatedAt']);
    final closedAt = parseAuditTimestamp(map['closedAt']);
    final rawEvents = ((map['events'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final eventTimes = rawEvents
        .map((entry) => parseAuditTimestamp(entry['timestamp']))
        .toList();
    DateTime? earliestEvent;
    for (final time in eventTimes) {
      if (time == null) continue;
      if (earliestEvent == null || time.isBefore(earliestEvent)) {
        earliestEvent = time;
      }
    }
    final anchor =
        storedOpenedAt ??
        earliestEvent ??
        storedUpdatedAt ??
        closedAt ??
        unknownAuditTimestamp;

    final events = <AuditEvent>[
      for (var i = 0; i < rawEvents.length; i++)
        AuditEvent.fromMap(
          rawEvents[i].cast<String, dynamic>(),
          fallbackTimestamp: anchor,
        ),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final openedAt = storedOpenedAt ?? anchor;
    final updatedAt =
        storedUpdatedAt ??
        (events.isNotEmpty ? events.last.timestamp : openedAt);
    final closedById = (map['closedById'] as String?)?.trim();
    final closedByName = (map['closedByName'] as String?)?.trim();
    final locked = map['locked'] == true;

    return AuditReport(
      reportId: reportId,
      orderId: orderId,
      tableNumbers: tableNumbers,
      floor: floor,
      openedById: openedById,
      openedByName: openedByName,
      openedAt: openedAt,
      status: status,
      events: events,
      updatedAt: updatedAt,
      closedAt: closedAt,
      closedById: closedById?.isNotEmpty == true ? closedById : null,
      closedByName: closedByName?.isNotEmpty == true ? closedByName : null,
      locked: locked,
    );
  }
}
