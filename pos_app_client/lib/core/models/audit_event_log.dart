import 'dart:convert';
import 'package:uuid/uuid.dart';

class AuditEventLog {
  final String id;
  final String action;
  final String userId;
  final Map<String, dynamic> data;
  final String deviceType;
  final DateTime createdAt;
  bool synced;

  AuditEventLog({
    String? id,
    required this.action,
    required this.userId,
    this.data = const {},
    this.deviceType = 'mobile',
    DateTime? createdAt,
    this.synced = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'action': action,
      'userId': userId,
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
      data: map['data'] is String ? jsonDecode(map['data']) : (map['data'] ?? {}),
      deviceType: map['deviceType'] ?? 'mobile',
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : null,
      synced: map['synced'] == 1,
    );
  }

  Map<String, dynamic> toSyncMap() {
    return {
      'id': id,
      'action': action,
      'userId': userId,
      'data': data,
      'deviceType': deviceType,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
