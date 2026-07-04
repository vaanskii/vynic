import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';

class AuditEventService {
  static bool _isSyncing = false;
  static Timer? _syncTimer;

  /// Initialize the background sync service.
  static void initialize() {
    if (_syncTimer != null) return;
    
    // Periodic sync attempt every 2 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(syncEvents());
    });

    // Initial sync after startup
    Timer(const Duration(seconds: 10), () {
      unawaited(syncEvents());
    });
  }

  static void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Appends a new event to the local immutable queue.
  /// Every action in the app should call this.
  static Future<void> logEvent({
    required String action,
    required String userId,
    Map<String, dynamic> data = const {},
  }) async {
    final event = AuditEventLog(
      action: action,
      userId: userId,
      data: data,
      deviceType: kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.windows ? 'windows' : 'mobile'),
    );

    try {
      final box = DatabaseService.getAuditLogBox();
      await box.put(event.id, event.toMap());
      
      // Proactive debounced sync
      unawaited(syncEvents());
    } catch (e) {
      debugPrint('[AuditEventService] CRITICAL: Failed to write audit event: $e');
    }
  }

  /// Scans the local box for unsynced events and pushes them to backend in batches.
  static Future<void> syncEvents() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final box = DatabaseService.getAuditLogBox();
      final allEntries = box.toMap();
      
      // Filter for unsynced entries
      final unsynced = allEntries.entries
          .map((entry) {
            try {
              final map = Map<String, dynamic>.from(entry.value);
              return AuditEventLog.fromMap(map);
            } catch (_) {
              return null;
            }
          })
          .whereType<AuditEventLog>()
          .where((e) => !e.synced)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)); // Oldest first

      if (unsynced.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint('[AuditEventService] Found ${unsynced.length} unsynced events. Starting batch sync.');

      const batchSize = 30;
      for (var i = 0; i < unsynced.length; i += batchSize) {
        final end = (i + batchSize < unsynced.length) ? i + batchSize : unsynced.length;
        final batch = unsynced.sublist(i, end);

        final success = await _sendBatch(batch);
        if (success) {
          // Mark as synced locally
          for (final event in batch) {
            event.synced = true;
            await box.put(event.id, event.toMap());
          }
        } else {
          // Stop processing further batches if one fails (preserve order)
          debugPrint('[AuditEventService] Batch sync failed. Will retry later.');
          break;
        }
      }
    } catch (e) {
      debugPrint('[AuditEventService] Sync task failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static Future<bool> _sendBatch(List<AuditEventLog> batch) async {
    try {
      final payload = {
        'logs': batch.map((e) => e.toSyncMap()).toList(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/sync/audit-logs'),
        headers: ApiConfig.posSyncHeaders,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('[AuditEventService] Batch transmission error: $e');
      return false;
    }
  }
}
