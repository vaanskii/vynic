import 'dart:convert';
import 'package:uuid/uuid.dart';

/// One venue-wide accountability row.
///
/// This is the generic half of the audit system: everything that is not the
/// lifecycle of a single Order. An Order has its own `AuditReport` with an
/// ordered timeline; a staff member, a menu item, an expense or a business day
/// has no such container, so what happened to it is recorded here.
///
/// [entityType] and [entityId] say *what* the row is about. They are additive
/// and nullable: every row written before they existed carries neither, and is
/// still read, displayed and synced exactly as it always was.
class AuditEventLog {
  final String id;
  final String action;
  final String userId;

  /// The canonical kind of thing this row is about — one of
  /// `GlobalAuditEntity` — or null for a row written before entity identity
  /// existed.
  final String? entityType;

  /// The identity of that thing inside this Venue: a staff username, a menu
  /// item id, an expense id, a business date. Null when the action names no
  /// single subject (a settings change that is its own subject, say).
  final String? entityId;

  final Map<String, dynamic> data;
  final String deviceType;
  final DateTime createdAt;
  bool synced;

  AuditEventLog({
    String? id,
    required this.action,
    required this.userId,
    this.entityType,
    this.entityId,
    this.data = const {},
    this.deviceType = 'mobile',
    DateTime? createdAt,
    this.synced = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'action': action,
      'userId': userId,
      if (entityType != null) 'entityType': entityType,
      if (entityId != null) 'entityId': entityId,
      'data': jsonEncode(data),
      'deviceType': deviceType,
      'createdAt': createdAt.toIso8601String(),
      'synced': synced ? 1 : 0,
    };
  }

  factory AuditEventLog.fromMap(Map<String, dynamic> map) {
    return AuditEventLog(
      id: map['id'],
      action: map['action'],
      userId: map['userId'],
      entityType: _nonEmpty(map['entityType']),
      entityId: _nonEmpty(map['entityId']),
      data: map['data'] is String
          ? jsonDecode(map['data'])
          : (map['data'] ?? {}),
      deviceType: map['deviceType'] ?? 'mobile',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : null,
      synced: map['synced'] == 1,
    );
  }

  Map<String, dynamic> toSyncMap() {
    return {
      'id': id,
      'action': action,
      'userId': userId,
      if (entityType != null) 'entityType': entityType,
      if (entityId != null) 'entityId': entityId,
      'data': data,
      'deviceType': deviceType,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// A stored string that actually says something, or null. An empty string is
  /// not an entity id, and sending one would make "has an entity" untrue.
  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
