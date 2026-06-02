import 'package:flutter/material.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';
import 'package:vynic/core/widgets/notification_entry_style.dart';

/// Shared notification row: colored accent bar, no category icons.
class NotificationEntryTile extends StatelessWidget {
  const NotificationEntryTile({
    super.key,
    required this.entry,
    required this.timeLabel,
    this.onTap,
    this.trailing,
    this.compact = false,
    this.light = false,
  });

  final AppNotificationEntry entry;
  final String timeLabel;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;

  /// Light dashboard / notifications screen (dark text on pale cards).
  final bool light;

  @override
  Widget build(BuildContext context) {
    final unread = !entry.isRead;
    final style = resolveNotificationEntryStyle(entry);
    final titleColor = light
        ? const Color(0xFF0F172A).withValues(alpha: unread ? 1 : 0.72)
        : Colors.white.withValues(alpha: unread ? 0.95 : 0.72);
    final timeColor = light
        ? const Color(0xFF64748B)
        : Colors.white.withValues(alpha: 0.38);

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NotificationEntryAccentBar(
            entry: entry,
            height: compact ? 36 : 40,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeLabel,
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  entry.message,
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _messageColor(style, unread),
                    fontSize: compact ? 12 : 13,
                    height: 1.35,
                    fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: light
                ? (unread
                    ? style.accent.withValues(alpha: 0.06)
                    : const Color(0xFFF8FAFC))
                : style.backgroundTint(unread: unread),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: light
                  ? (unread
                      ? style.accent.withValues(alpha: 0.22)
                      : const Color(0xFFE2E8F0))
                  : style.borderTint(unread: unread),
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  Color _messageColor(NotificationEntryStyle style, bool unread) {
    final vivid = unread ? 0.88 : 0.62;
    final muted = unread ? 0.55 : 0.42;
    if (light) {
      switch (style.kind) {
        case NotificationEntryKind.decrease:
        case NotificationEntryKind.cancel:
          return style.accent.withValues(alpha: vivid);
        default:
          return const Color(0xFF64748B);
      }
    }
    switch (style.kind) {
      case NotificationEntryKind.decrease:
      case NotificationEntryKind.cancel:
        return style.accent.withValues(alpha: vivid);
      case NotificationEntryKind.reservation:
      case NotificationEntryKind.table:
      case NotificationEntryKind.takeaway:
      case NotificationEntryKind.payment:
        return style.accent.withValues(alpha: muted);
      case NotificationEntryKind.order:
      case NotificationEntryKind.sync:
      case NotificationEntryKind.general:
        return Colors.white.withValues(alpha: muted);
    }
  }
}
