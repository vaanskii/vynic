import 'package:flutter/foundation.dart';

/// Provenance travels with the value; an HTTP response does not freshen the POS.
class ManagerReadStatus {
  final String key, location, source, completeness, query;
  final DateTime? sourceUpdatedAt, receivedAt, fetchedAt;
  final String? error;
  final bool apiAvailable;
  final int? httpStatus;
  bool get accessDenied => httpStatus == 401 || httpStatus == 403;
  const ManagerReadStatus({
    required this.key,
    this.location = 'unavailable',
    this.source = 'UNKNOWN',
    this.completeness = 'UNKNOWN',
    this.query = '',
    this.sourceUpdatedAt,
    this.receivedAt,
    this.fetchedAt,
    this.error,
    this.apiAvailable = false,
    this.httpStatus,
  });
  factory ManagerReadStatus.fromJson(String key, Map<String, dynamic> json) =>
      ManagerReadStatus(
        key: key,
        location: json['location'] as String? ?? 'unavailable',
        source: json['source'] as String? ?? 'UNKNOWN',
        completeness: json['completeness'] as String? ?? 'UNKNOWN',
        query: json['query'] as String? ?? '',
        sourceUpdatedAt: DateTime.tryParse(
          json['sourceUpdatedAt'] as String? ?? '',
        ),
        receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? ''),
        fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
        error: json['error'] as String?,
        apiAvailable: json['apiAvailable'] == true,
        httpStatus: (json['httpStatus'] as num?)?.toInt(),
      );
  Map<String, dynamic> toJson() => {
    'location': location,
    'source': source,
    'completeness': completeness,
    'query': query,
    'sourceUpdatedAt': sourceUpdatedAt?.toUtc().toIso8601String(),
    'receivedAt': receivedAt?.toUtc().toIso8601String(),
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
    'error': error,
    'apiAvailable': apiAvailable,
    'httpStatus': httpStatus,
  };
  ManagerReadStatus failed(
    String message, {
    String? location,
    int? httpStatus,
  }) => ManagerReadStatus(
    key: key,
    location: location ?? this.location,
    source: source,
    completeness: completeness,
    query: query,
    sourceUpdatedAt: sourceUpdatedAt,
    receivedAt: receivedAt,
    fetchedAt: fetchedAt,
    error: message,
    apiAvailable: false,
    httpStatus: httpStatus,
  );
  bool staleAt(DateTime now) {
    bool old(DateTime? time) =>
        time == null ||
        now.difference(time) > const Duration(minutes: 5) ||
        time.difference(now) > const Duration(minutes: 1);
    return location != 'api' ||
        !apiAvailable ||
        (source == 'POS' && (old(sourceUpdatedAt) || old(receivedAt))) ||
        source == 'UNKNOWN' ||
        old(fetchedAt);
  }

  bool limitedAt(DateTime now) => staleAt(now) || completeness != 'KNOWN';
}

class ManagerDataRead<T> {
  final T? data;
  final ManagerReadStatus status;
  const ManagerDataRead(this.data, this.status);
}

class ManagerReadFailure extends StateError {
  final ManagerReadStatus status;
  ManagerReadFailure(this.status)
    : super(status.error ?? 'მონაცემები მიუწვდომელია.');
}

/// All cached Manager reads share connectivity state without clearing another
/// block's error when one request (or the monitoring socket) succeeds.
class ManagerDataReads {
  static final statuses = ValueNotifier<Map<String, ManagerReadStatus>>(
    const {},
  );
  static String? _scope;
  static void activate(String scope) {
    if (_scope == scope) return;
    _scope = scope;
    statuses.value = const {};
  }

  static void publish(String scope, ManagerReadStatus status) {
    if (_scope != scope) return;
    statuses.value = {
      ...statuses.value,
      status.key: status,
      '${status.key}@${status.query}': status,
    };
  }

  static void clear() {
    _scope = null;
    statuses.value = const {};
  }

  /// A refreshed view no longer displays its old pages. Retire only those exact
  /// status objects; a newer response or another query keeps its own state.
  static void release(String scope, Iterable<ManagerReadStatus> reads) {
    if (_scope != scope) return;
    final retired = reads.toSet();
    statuses.value = {
      for (final entry in statuses.value.entries)
        if (!retired.contains(entry.value)) entry.key: entry.value,
    };
  }

  static bool get hasApiError =>
      statuses.value.values.any((s) => !s.apiAvailable);
}
