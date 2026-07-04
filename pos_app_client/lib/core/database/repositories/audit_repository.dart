import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order.dart';

import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'order_repository.dart';

/// Order audit reports and the admin action log.
class AuditRepository {
  AuditRepository._();

  static const String _auditReportKeyPrefix = 'audit_report_order_';
  static const String _auditLegacyPrefix = 'legacy_event_';

  /// Injected by ManagerSyncService so audit changes trigger a server push.
  static void Function()? _onAuditChanged;
  static void registerAuditChangedCallback(void Function() cb) {
    _onAuditChanged = cb;
  }

  static String buildAuditReportKey(int orderId) =>
      '$_auditReportKeyPrefix$orderId';

  static AuditReport? _parseAuditReport(dynamic raw) {
    if (raw is AuditReport) {
      return raw;
    }
    if (raw is Map) {
      final map = Map<dynamic, dynamic>.from(raw);
      final reportId = (map['reportId'] as String?)?.trim();
      if (reportId != null && reportId.isNotEmpty) {
        return AuditReport.fromMap(map);
      }
    }
    return null;
  }

  static Future<AuditReport> ensureAuditReport({
    required int orderId,
    Order? orderSnapshot,
  }) async {
    final existing = getAuditReport(orderId);
    if (existing != null) {
      return existing;
    }

    orderSnapshot ??= OrderRepository.getOrder(orderId);
    final now = DateTime.now();
    final tableNumbers = orderSnapshot?.tableNumbers ?? const <String>[];
    final floor = orderSnapshot?.floor ?? 'first';
    final openedBy = orderSnapshot?.createdBy ?? 'unknown';
    final openedAt = orderSnapshot?.createdAt ?? now;

    final report = AuditReport(
      reportId: buildAuditReportKey(orderId),
      orderId: orderId,
      tableNumbers: List<String>.from(tableNumbers),
      floor: floor,
      openedById: openedBy,
      openedByName: openedBy,
      openedAt: openedAt,
      status: AuditReportStatus.open,
      events: const [],
      updatedAt: now,
      locked: false,
    );

    await saveAuditReport(report);
    return report;
  }

  static Future<void> saveAuditReport(AuditReport report) async {
    if (DatabaseCore.auditLogBox == null) return;
    await DatabaseCore.auditLogBox!.put(report.reportId, report.toMap());
    _onAuditChanged?.call();
  }

  static AuditReport? getAuditReport(int orderId) {
    if (DatabaseCore.auditLogBox == null) {
      return null;
    }
    final raw = DatabaseCore.auditLogBox!.get(buildAuditReportKey(orderId));
    if (raw == null) {
      return null;
    }
    try {
      return _parseAuditReport(raw);
    } catch (e) {
      developer.log('Failed to parse audit report for order $orderId: $e');
      return null;
    }
  }

  static List<AuditReport> getAuditReports({AuditReportStatus? status}) {
    if (DatabaseCore.auditLogBox == null) {
      return const [];
    }

    final actualReports = <AuditReport>[];
    for (final key in DatabaseCore.auditLogBox!.keys) {
      final value = DatabaseCore.auditLogBox!.get(key);
      final report = _parseAuditReport(value);
      if (report == null) {
        continue;
      }
      actualReports.add(report);
    }

    final legacyReports = _buildLegacyAuditReports(
      actualReports.map((report) => report.orderId).toSet(),
    );

    final combined = <AuditReport>[...actualReports, ...legacyReports];
    if (status != null) {
      combined.removeWhere((report) => report.status != status);
    }

    combined.sort(
      (a, b) => _reportLastActivity(b).compareTo(_reportLastActivity(a)),
    );
    return combined;
  }

  static String _auditTableSetKey(List<String> tables) {
    final normalized =
        tables.map((t) => t.trim()).where((t) => t.isNotEmpty).toList()..sort();
    return normalized.join('|');
  }

  static Future<void> finalizeConflictingOpenAuditReports({
    required int currentOrderId,
    required String floor,
    required List<String> tableNumbers,
    required String closedBy,
  }) async {
    if (DatabaseCore.auditLogBox == null) {
      return;
    }

    final targetKey = _auditTableSetKey(tableNumbers);
    if (targetKey.isEmpty) {
      return;
    }

    final now = BusinessDayRepository.getCurrentDateTime();
    var changed = false;
    final openReports = getAuditReports(status: AuditReportStatus.open);

    for (final report in openReports) {
      if (report.orderId == currentOrderId) {
        continue;
      }
      if (report.floor != floor) {
        continue;
      }
      if (_auditTableSetKey(report.tableNumbers) != targetKey) {
        continue;
      }
      if (report.reportId.startsWith('legacy_report_order_')) {
        continue;
      }

      final updated = report.copyWith(
        status: AuditReportStatus.closed,
        locked: true,
        closedAt: now,
        closedById: closedBy,
        closedByName: closedBy,
        updatedAt: now,
      );
      await DatabaseCore.auditLogBox!.put(updated.reportId, updated.toMap());
      changed = true;
    }

    if (changed) {
      _onAuditChanged?.call();
    }
  }

  static Future<void> runAuditDuplicateOpenCleanupOnce() async {
    if (DatabaseCore.settingsBox == null || DatabaseCore.auditLogBox == null) {
      return;
    }

    const cleanupKey = 'auditOpenDuplicateCleanupV1';
    final alreadyDone = DatabaseCore.settingsBox!.get(cleanupKey) == true;
    if (alreadyDone) {
      return;
    }

    final openReports = getAuditReports(
      status: AuditReportStatus.open,
    ).where((r) => !r.reportId.startsWith('legacy_report_order_')).toList();

    if (openReports.isEmpty) {
      await DatabaseCore.settingsBox!.put(cleanupKey, true);
      return;
    }

    final grouped = <String, List<AuditReport>>{};
    for (final report in openReports) {
      final tableKey = _auditTableSetKey(report.tableNumbers);
      if (tableKey.isEmpty) {
        continue;
      }
      final key = '${report.floor}|$tableKey';
      grouped.putIfAbsent(key, () => <AuditReport>[]).add(report);
    }

    var changed = false;
    final now = BusinessDayRepository.getCurrentDateTime();

    for (final entry in grouped.entries) {
      final reports = entry.value;
      if (reports.length <= 1) {
        continue;
      }

      reports.sort(
        (a, b) => _reportLastActivity(b).compareTo(_reportLastActivity(a)),
      );
      final keeper = reports.first;
      final stale = reports.skip(1);

      for (final report in stale) {
        final closedBy = report.closedByName ?? report.openedByName;
        final closedId = report.closedById ?? report.openedById;
        final fixed = report.copyWith(
          status: AuditReportStatus.closed,
          locked: true,
          closedAt: now,
          closedById: closedId,
          closedByName: closedBy,
          updatedAt: now,
        );
        await DatabaseCore.auditLogBox!.put(fixed.reportId, fixed.toMap());
        changed = true;
      }

      debugPrint(
        '[AuditCleanup] ${reports.length - 1} stale OPEN reports closed for ${entry.key}, kept order #${keeper.orderId}.',
      );
    }

    await DatabaseCore.settingsBox!.put(cleanupKey, true);
    if (changed) {
      _onAuditChanged?.call();
    }
  }

  static DateTime _reportLastActivity(AuditReport report) {
    DateTime latestEventTs = report.openedAt;
    for (final event in report.events) {
      if (event.timestamp.isAfter(latestEventTs)) {
        latestEventTs = event.timestamp;
      }
    }
    return report.updatedAt.isAfter(latestEventTs)
        ? report.updatedAt
        : latestEventTs;
  }

  static List<AuditReport> _buildLegacyAuditReports(Set<int> existingOrderIds) {
    if (DatabaseCore.auditLogBox == null) {
      return const [];
    }

    final groupedLogs = <int, List<Map<String, dynamic>>>{};

    for (final key in DatabaseCore.auditLogBox!.keys) {
      if (key is! String || !key.startsWith(_auditLegacyPrefix)) {
        continue;
      }

      final raw = DatabaseCore.auditLogBox!.get(key);
      if (raw is! Map) {
        continue;
      }

      final log = Map<String, dynamic>.from(raw);
      final detailsRaw = log['details'];
      if (detailsRaw is! Map) {
        continue;
      }

      final orderId = (detailsRaw['orderId'] as num?)?.toInt();
      if (orderId == null || existingOrderIds.contains(orderId)) {
        continue;
      }

      groupedLogs
          .putIfAbsent(orderId, () => <Map<String, dynamic>>[])
          .add(Map<String, dynamic>.from(log));
    }

    if (groupedLogs.isEmpty) {
      return const [];
    }

    final legacyReports = <AuditReport>[];

    for (final entry in groupedLogs.entries) {
      final orderId = entry.key;
      final logs = entry.value;
      final events = <AuditEvent>[];

      for (final log in logs) {
        final actionType = log['actionType'] as String?;
        final eventType = _eventTypeFromLegacyAction(actionType);
        if (eventType == null) {
          continue;
        }

        final details = (log['details'] as Map?) ?? const {};
        final timestamp = _resolveLegacyTimestamp(
          log['timestamp'] as String?,
          log['date'] as String?,
        );

        final waiterName = (log['performedBy'] as String?)?.trim();
        final comment = (log['comment'] as String?)?.trim();

        events.add(
          AuditEvent(
            type: eventType,
            itemName: (details['itemName'] as String?)?.trim() ?? 'Item',
            previousQty: (details['previousQty'] as num?)?.toInt() ?? 0,
            newQty: (details['newQty'] as num?)?.toInt() ?? 0,
            waiterId: waiterName?.isNotEmpty == true ? waiterName! : 'unknown',
            waiterName: waiterName?.isNotEmpty == true
                ? waiterName!
                : 'Unknown',
            timestamp: timestamp,
            note: comment?.isNotEmpty == true ? comment : null,
          ),
        );
      }

      if (events.isEmpty) {
        continue;
      }

      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final firstEvent = events.first;
      final lastEvent = events.last;

      final referenceDetails = logs.lastWhere(
        (log) => log['details'] is Map,
        orElse: () => const {},
      );
      final referenceMap = (referenceDetails['details'] as Map?) ?? const {};

      final tableNumbers = _stringifyTableNumbers(referenceMap['tableNumbers']);
      final floorRaw = (referenceMap['floor']?.toString() ?? '').trim();
      final floor = floorRaw.isNotEmpty ? floorRaw : 'first';

      final isCancelled = events.last.type == AuditEventType.cancelTable;
      final status = isCancelled
          ? AuditReportStatus.cancelled
          : AuditReportStatus.open;

      legacyReports.add(
        AuditReport(
          reportId: 'legacy_report_order_$orderId',
          orderId: orderId,
          tableNumbers: tableNumbers,
          floor: floor,
          openedById: firstEvent.waiterId,
          openedByName: firstEvent.waiterName,
          openedAt: firstEvent.timestamp,
          status: status,
          events: List<AuditEvent>.unmodifiable(events),
          updatedAt: lastEvent.timestamp,
          closedAt: isCancelled ? lastEvent.timestamp : null,
          closedById: isCancelled ? lastEvent.waiterId : null,
          closedByName: isCancelled ? lastEvent.waiterName : null,
          locked: isCancelled,
        ),
      );
    }

    return legacyReports;
  }

  static AuditEventType? _eventTypeFromLegacyAction(String? action) {
    switch (action) {
      case 'add_item':
        return AuditEventType.addItem;
      case 'reduce_quantity':
        return AuditEventType.reduceQty;
      case 'remove_item':
        return AuditEventType.deleteItem;
      case 'cancel_table':
        return AuditEventType.cancelTable;
      case 'custom':
        return AuditEventType.custom;
    }
    return null;
  }

  static DateTime _resolveLegacyTimestamp(
    String? timestampIso,
    String? dateIso,
  ) {
    final parsedTimestamp = timestampIso != null
        ? DateTime.tryParse(timestampIso)
        : null;
    if (parsedTimestamp != null) {
      return parsedTimestamp;
    }

    if (dateIso != null && dateIso.isNotEmpty) {
      final parsedDate = DateTime.tryParse(dateIso);
      if (parsedDate != null) {
        return DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      }
    }

    return BusinessDayRepository.getCurrentDateTime();
  }

  static List<String> _stringifyTableNumbers(dynamic raw) {
    if (raw is List) {
      return raw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return const [];
      }
      return trimmed
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static Future<void> appendOrderAuditEvents({
    required int orderId,
    required List<AuditEvent> events,
    AuditReportStatus? statusOverride,
    bool lockReport = false,
    String? closedById,
    String? closedByName,
  }) async {
    if (events.isEmpty && !lockReport) {
      return;
    }

    final orderSnapshot = OrderRepository.getOrder(orderId);
    var report = await ensureAuditReport(
      orderId: orderId,
      orderSnapshot: orderSnapshot,
    );

    if (report.locked) {
      throw StateError('Audit report for order $orderId is locked');
    }

    final mergedEvents = <AuditEvent>[...report.events, ...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final updatedEvents = List<AuditEvent>.unmodifiable(mergedEvents);
    final updatedAt = BusinessDayRepository.getCurrentDateTime();

    final updatedReport = report.copyWith(
      events: updatedEvents,
      updatedAt: updatedAt,
      status: statusOverride ?? report.status,
      locked: lockReport ? true : report.locked,
      closedAt: lockReport ? updatedAt : report.closedAt,
      closedById: lockReport
          ? (closedById ??
                report.closedById ??
                (updatedEvents.isNotEmpty ? updatedEvents.last.waiterId : null))
          : (closedById ?? report.closedById),
      closedByName: lockReport
          ? (closedByName ??
                report.closedByName ??
                (updatedEvents.isNotEmpty
                    ? updatedEvents.last.waiterName
                    : null))
          : (closedByName ?? report.closedByName),
    );

    await DatabaseCore.auditLogBox!.put(
      updatedReport.reportId,
      updatedReport.toMap(),
    );
    _onAuditChanged?.call();
  }

  static String _legacyActionForEvent(AuditEventType type) {
    switch (type) {
      case AuditEventType.addItem:
        return 'add_item';
      case AuditEventType.reduceQty:
        return 'reduce_quantity';
      case AuditEventType.deleteItem:
        return 'remove_item';
      case AuditEventType.cancelTable:
        return 'cancel_table';
      case AuditEventType.custom:
        return 'custom';
    }
  }

  static Future<void> logAdminAction({
    required String actionType,
    required String performedBy,
    Map<String, dynamic>? details,
    String? comment,
    String? approvedBy,
  }) async {
    final normalizedType = actionType.toLowerCase();
    final orderId = (details?['orderId'] as num?)?.toInt();

    if (orderId != null &&
        (normalizedType == 'cancel_table' ||
            normalizedType == 'remove_item' ||
            normalizedType == 'reduce_quantity' ||
            normalizedType == 'add_item')) {
      final waiterName = performedBy.trim().isEmpty ? 'Unknown' : performedBy;
      final waiterId = waiterName;
      final timestamp = BusinessDayRepository.getCurrentDateTime();
      final events = <AuditEvent>[];

      final changes = (details?['changes'] as List?) ?? const [];

      if (normalizedType == 'cancel_table') {
        events.add(
          AuditEvent(
            type: AuditEventType.cancelTable,
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: waiterId,
            waiterName: waiterName,
            timestamp: timestamp,
            note: comment ?? details?['requestComment'] as String?,
          ),
        );

        await appendOrderAuditEvents(
          orderId: orderId,
          events: events,
          statusOverride: AuditReportStatus.cancelled,
          lockReport: true,
          closedById: waiterId,
          closedByName: waiterName,
        );
        return;
      }

      if (changes.isNotEmpty) {
        for (final entry in changes.whereType<Map>()) {
          final change = Map<String, dynamic>.from(entry);
          final itemName = (change['itemName'] as String?) ?? 'Item';
          final previousQty =
              (change['previousQuantity'] as num?)?.toInt() ?? 0;
          final newQty = (change['newQuantity'] as num?)?.toInt() ?? 0;

          AuditEventType type;
          if (newQty <= 0) {
            type = AuditEventType.deleteItem;
          } else if (newQty < previousQty) {
            type = AuditEventType.reduceQty;
          } else {
            type = AuditEventType.addItem;
          }

          events.add(
            AuditEvent(
              type: type,
              itemName: itemName,
              previousQty: previousQty,
              newQty: newQty,
              waiterId: waiterId,
              waiterName: waiterName,
              timestamp: timestamp,
              note: comment,
            ),
          );
        }
      } else if (details?['itemName'] is String) {
        final itemName = details?['itemName'] as String? ?? 'Item';
        final previousQty =
            (details?['previousQuantity'] as num?)?.toInt() ?? 0;
        final newQty = (details?['newQuantity'] as num?)?.toInt() ?? 0;

        AuditEventType type;
        if (normalizedType == 'remove_item' || newQty <= 0) {
          type = AuditEventType.deleteItem;
        } else if (newQty < previousQty) {
          type = AuditEventType.reduceQty;
        } else {
          type = AuditEventType.addItem;
        }

        events.add(
          AuditEvent(
            type: type,
            itemName: itemName,
            previousQty: previousQty,
            newQty: newQty,
            waiterId: waiterId,
            waiterName: waiterName,
            timestamp: timestamp,
            note: comment,
          ),
        );
      }

      if (events.isNotEmpty) {
        await appendOrderAuditEvents(orderId: orderId, events: events);
        return;
      }
    }

    final logKey =
        '$_auditLegacyPrefix${DateTime.now().microsecondsSinceEpoch}';
    final log = {
      'actionType': actionType,
      'performedBy': performedBy,
      if (approvedBy != null) 'approvedBy': approvedBy,
      'comment': comment ?? '',
      'details': details ?? <String, dynamic>{},
      'timestamp': BusinessDayRepository.getCurrentDateTime().toIso8601String(),
      'date': BusinessDayRepository.getCurrentDate().toIso8601String().split(
        'T',
      )[0],
    };

    await DatabaseCore.auditLogBox!.put(logKey, log);

    unawaited(
      AuditEventService.logEvent(
        action: actionType,
        userId: performedBy,
        data: {
          if (details != null) ...details,
          if (comment != null) 'comment': comment,
          if (approvedBy != null) 'approvedBy': approvedBy,
        },
      ),
    );
    _onAuditChanged?.call();
  }

  static List<Map<String, dynamic>> getAuditLogs({
    String? date,
    String? actionType,
  }) {
    final logs = <Map<String, dynamic>>[];

    for (final report in getAuditReports()) {
      for (final event in report.sortedEvents) {
        final action = _legacyActionForEvent(event.type);
        final timestampIso = event.timestamp.toIso8601String();
        final entryDate = timestampIso.split('T')[0];

        logs.add({
          'actionType': action,
          'performedBy': event.waiterName,
          'comment': event.note ?? '',
          'details': {
            'orderId': report.orderId,
            'tableNumbers': report.tableNumbers,
            'floor': report.floor,
            'previousQty': event.previousQty,
            'newQty': event.newQty,
            'itemName': event.itemName,
          },
          'timestamp': timestampIso,
          'date': entryDate,
        });
      }
    }

    if (DatabaseCore.auditLogBox != null) {
      for (final key in DatabaseCore.auditLogBox!.keys) {
        final value = DatabaseCore.auditLogBox!.get(key);
        if (value is! Map) continue;

        final map = Map<String, dynamic>.from(value);

        if (key is String && key.startsWith(_auditLegacyPrefix)) {
          logs.add(map);
        } else if (map.containsKey('action') && map.containsKey('userId')) {
          // New AuditEventLog format - map to legacy-compatible structure for UI
          final createdAt =
              map['createdAt'] as String? ?? DateTime.now().toIso8601String();
          final rawData = map['data'] is String
              ? jsonDecode(map['data'])
              : (map['data'] ?? {});

          final Map<String, dynamic> dataMap = rawData is Map
              ? Map<String, dynamic>.from(rawData)
              : {};

          // Extract details: handle both flat and nested (for transition period)
          final Map<String, dynamic> finalDetails =
              dataMap.containsKey('details') && dataMap['details'] is Map
              ? Map<String, dynamic>.from(dataMap['details'])
              : dataMap;

          logs.add({
            'actionType': map['action'],
            'performedBy': map['userId'],
            'comment': dataMap['comment'] ?? '',
            'details': finalDetails,
            'timestamp': createdAt,
            'date': createdAt.split('T')[0],
          });
        }
      }
    }

    var filtered = logs;
    if (date != null) {
      filtered = filtered
          .where((log) => (log['date'] as String?) == date)
          .toList();
    }
    if (actionType != null) {
      filtered = filtered
          .where((log) => (log['actionType'] as String?) == actionType)
          .toList();
    }

    filtered.sort(
      (a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String),
    );

    return filtered;
  }
}
