import 'dart:developer' as developer;

import 'business_day_repository.dart';
import '../database_core.dart';

/// Persistent error log (admin panel's error section).
///
/// Never throws: logging must not break the operation being logged.
class ErrorLogRepository {
  ErrorLogRepository._();

  static Future<void> logError({
    required String title,
    required Object error,
    required StackTrace stackTrace,
    String? context,
    String? performedBy,
    Map<String, dynamic>? metadata,
  }) async {
    if (DatabaseCore.errorLogBox == null) {
      return;
    }

    final timestamp = BusinessDayRepository.getCurrentDateTime();
    final logKey = 'error_${timestamp.microsecondsSinceEpoch}';
    final log = <String, dynamic>{
      'title': title,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
      'context': context ?? '',
      'performedBy': performedBy ?? '',
      'metadata': metadata ?? <String, dynamic>{},
      'timestamp': timestamp.toIso8601String(),
      'date': timestamp.toIso8601String().split('T')[0],
    };

    await DatabaseCore.errorLogBox!.put(logKey, log);
    developer.log(
      'Error logged: $title',
      name: 'ErrorLog',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static List<Map<String, dynamic>> getErrorLogs({String? date}) {
    if (DatabaseCore.errorLogBox == null) {
      return [];
    }

    final logs = <Map<String, dynamic>>[];
    for (final key in DatabaseCore.errorLogBox!.keys) {
      final raw = DatabaseCore.errorLogBox!.get(key);
      if (raw is Map) {
        logs.add(Map<String, dynamic>.from(raw));
      }
    }

    var filtered = logs;
    if (date != null) {
      filtered = filtered
          .where((log) => (log['date'] as String?) == date)
          .toList();
    }

    filtered.sort(
      (a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String),
    );

    return filtered;
  }

  static Future<void> clearErrorLogs() async {
    await DatabaseCore.errorLogBox?.clear();
  }
}
