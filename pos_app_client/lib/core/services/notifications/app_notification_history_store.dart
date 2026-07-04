import 'package:flutter/foundation.dart';

/// Single notification row for manager (mobile) or POS (Windows) panels.
class AppNotificationEntry {
  AppNotificationEntry({
    required this.id,
    required this.at,
    required this.title,
    required this.message,
    this.source,
    this.meta,
    this.isRead = false,
  });

  final String id;
  final DateTime at;
  final String title;
  final String message;

  /// e.g. `mobile_pos`, `ws`, `system`
  final String? source;
  final Map<String, dynamic>? meta;
  final bool isRead;

  String get timeLabel {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  AppNotificationEntry copyWith({bool? isRead}) {
    return AppNotificationEntry(
      id: id,
      at: at,
      title: title,
      message: message,
      source: source,
      meta: meta,
      isRead: isRead ?? this.isRead,
    );
  }
}

/// In-memory history + unread badge for notification panels (mobile + Windows).
class AppNotificationHistoryStore {
  AppNotificationHistoryStore._();
  static final AppNotificationHistoryStore instance =
      AppNotificationHistoryStore._();

  static const int maxEntries = 100;

  final ValueNotifier<List<AppNotificationEntry>> entries =
      ValueNotifier<List<AppNotificationEntry>>([]);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Returns false if [dedupeId] was already present (FCM + socket hybrid dedupe).
  bool add({
    String? dedupeId,
    required String title,
    required String message,
    String? source,
    Map<String, dynamic>? meta,
  }) {
    final trimmedTitle = title.trim();
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) return false;

    final id = (dedupeId != null && dedupeId.trim().isNotEmpty)
        ? dedupeId.trim()
        : '${DateTime.now().microsecondsSinceEpoch}';
    if (entries.value.any((e) => e.id == id)) {
      return false;
    }
    final duplicateByContent = entries.value.any((e) {
      if (DateTime.now().difference(e.at).inSeconds > 30) return false;
      final sameTitle =
          e.title == (trimmedTitle.isEmpty ? 'შეტყობინება' : trimmedTitle);
      if (!sameTitle) return false;
      if (e.message == trimmedMessage) return true;
      // Service-fee toggles often differ only by duplicate summary lines.
      if (trimmedMessage.contains('სერვისის საფასური') &&
          e.message.contains('სერვისის საფასური')) {
        return _normalizeServiceFeeForDedupe(e.message) ==
            _normalizeServiceFeeForDedupe(trimmedMessage);
      }
      return false;
    });
    if (duplicateByContent) {
      return false;
    }

    final entry = AppNotificationEntry(
      id: id,
      at: DateTime.now(),
      title: trimmedTitle.isEmpty ? 'შეტყობინება' : trimmedTitle,
      message: trimmedMessage,
      source: source,
      meta: meta,
      isRead: false,
    );

    final next = List<AppNotificationEntry>.from(entries.value);
    next.insert(0, entry);
    if (next.length > maxEntries) {
      final removed = next.removeLast();
      if (!removed.isRead) {
        unreadCount.value = (unreadCount.value - 1).clamp(0, maxEntries);
      }
    }
    entries.value = next;
    unreadCount.value = unreadCount.value + 1;
    return true;
  }

  void markEntryRead(String id) {
    final index = entries.value.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final entry = entries.value[index];
    if (entry.isRead) return;
    final next = List<AppNotificationEntry>.from(entries.value);
    next[index] = entry.copyWith(isRead: true);
    entries.value = next;
    unreadCount.value = (unreadCount.value - 1).clamp(0, maxEntries);
  }

  static String _normalizeServiceFeeForDedupe(String message) {
    final lines = message
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return lines.join(' | ');
  }

  void markAllRead() {
    if (unreadCount.value == 0 && entries.value.every((e) => e.isRead)) {
      return;
    }
    entries.value = entries.value
        .map((e) => e.isRead ? e : e.copyWith(isRead: true))
        .toList();
    unreadCount.value = 0;
  }

  void clear() {
    entries.value = [];
    unreadCount.value = 0;
  }

  void remove(String id) {
    final index = entries.value.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final removed = entries.value[index];
    final next = List<AppNotificationEntry>.from(entries.value)
      ..removeAt(index);
    entries.value = next;
    if (!removed.isRead) {
      unreadCount.value = (unreadCount.value - 1).clamp(0, maxEntries);
    }
  }
}
