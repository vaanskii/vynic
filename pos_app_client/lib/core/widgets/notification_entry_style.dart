import 'package:flutter/material.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';

/// Semantic category for notification accent color (no per-row icons).
enum NotificationEntryKind {
  decrease,
  cancel,
  reservation,
  table,
  takeaway,
  payment,
  order,
  sync,
  general,
}

class NotificationEntryStyle {
  const NotificationEntryStyle({
    required this.kind,
    required this.accent,
  });

  final NotificationEntryKind kind;
  final Color accent;

  Color backgroundTint({bool unread = true}) =>
      accent.withValues(alpha: unread ? 0.12 : 0.06);

  Color borderTint({bool unread = true}) =>
      accent.withValues(alpha: unread ? 0.35 : 0.14);
}

NotificationEntryStyle resolveNotificationEntryStyle(AppNotificationEntry entry) {
  final kind = _resolveKind(entry);
  return NotificationEntryStyle(kind: kind, accent: _accentFor(kind));
}

bool notificationMessageIsDecrease(String text) {
  final match = RegExp(r'(\d+)\s*→\s*(\d+)').firstMatch(text);
  if (match == null) return false;
  final prev = int.tryParse(match.group(1) ?? '');
  final next = int.tryParse(match.group(2) ?? '');
  if (prev == null || next == null) return false;
  return next < prev;
}

NotificationEntryKind _resolveKind(AppNotificationEntry entry) {
  final title = entry.title.toLowerCase();
  final message = entry.message.toLowerCase();
  final combined = '$title $message';
  final meta = entry.meta;

  if (meta?['reservationId'] != null &&
      meta!['reservationId'].toString().trim().isNotEmpty) {
    return NotificationEntryKind.reservation;
  }

  if (notificationMessageIsDecrease(combined) ||
      combined.contains('შემცირ') ||
      combined.contains('დაკლებ')) {
    return NotificationEntryKind.decrease;
  }

  if (combined.contains('გაუქმ') ||
      combined.contains('წაიშალ') ||
      combined.contains('cancel') ||
      combined.contains('deleted')) {
    return NotificationEntryKind.cancel;
  }

  if (title.contains('რეზერ') || combined.contains('reservation')) {
    return NotificationEntryKind.reservation;
  }

  if (title.contains('გატან') || combined.contains('takeaway')) {
    return NotificationEntryKind.takeaway;
  }

  if (title.contains('მაგიდ') ||
      combined.contains('walk-in') ||
      combined.contains('table ')) {
    return NotificationEntryKind.table;
  }

  if (combined.contains('შეიქმნა') &&
      (title.contains('შეკვეთ') || combined.contains('ახალი'))) {
    return NotificationEntryKind.table;
  }

  if (combined.contains('გადახ') ||
      combined.contains('paid') ||
      combined.contains('ჩაიხურ') ||
      combined.contains('დახურვ') ||
      title.contains('დღის')) {
    return NotificationEntryKind.payment;
  }

  if (combined.contains('სინქ') ||
      combined.contains('sync') ||
      combined.contains('audit') ||
      combined.contains('მონაცემები განახლდა')) {
    return NotificationEntryKind.sync;
  }

  if (title.contains('შეკვეთ') ||
      title.contains('სალარ') ||
      title.contains('მენეჯერ')) {
    return NotificationEntryKind.order;
  }

  return NotificationEntryKind.general;
}

Color _accentFor(NotificationEntryKind kind) {
  switch (kind) {
    case NotificationEntryKind.decrease:
    case NotificationEntryKind.cancel:
      return const Color(0xFFEF4444);
    case NotificationEntryKind.reservation:
      return const Color(0xFF3B82F6);
    case NotificationEntryKind.table:
      return const Color(0xFFF59E0B);
    case NotificationEntryKind.takeaway:
      return const Color(0xFF06B6D4);
    case NotificationEntryKind.payment:
      return const Color(0xFF22C55E);
    case NotificationEntryKind.order:
      return const Color(0xFF8B5CF6);
    case NotificationEntryKind.sync:
      return const Color(0xFF64748B);
    case NotificationEntryKind.general:
      return const Color(0xFF94A3B8);
  }
}

/// Thin colored stripe used on notification rows (replaces icon badges).
class NotificationEntryAccentBar extends StatelessWidget {
  const NotificationEntryAccentBar({
    super.key,
    required this.entry,
    this.height = 40,
  });

  final AppNotificationEntry entry;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = resolveNotificationEntryStyle(entry);
    return Container(
      width: 3,
      height: height,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: style.accent,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: style.accent.withValues(alpha: 0.35),
            blurRadius: 6,
            spreadRadius: -1,
          ),
        ],
      ),
    );
  }
}
