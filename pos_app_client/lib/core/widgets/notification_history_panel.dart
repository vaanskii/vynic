import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/core/widgets/notification_entry_style.dart';

/// Scrollable list of notifications + optional clear action (Windows POS).
class NotificationHistoryPanel extends StatelessWidget {
  const NotificationHistoryPanel({
    super.key,
    required this.entries,
    this.onClear,
    this.onEntryTap,
    this.emptyLabel = 'შეტყობინებები არ არის',
    this.dense = false,
  });

  final List<AppNotificationEntry> entries;
  final VoidCallback? onClear;
  final void Function(AppNotificationEntry entry)? onEntryTap;
  final String emptyLabel;
  final bool dense;

  static const Color _readBg = Colors.white;
  static const Color _readBorder = Color(0xFFE2E8F0);
  static const Color _readTitle = Color(0xFF64748B);
  static const Color _readMessage = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM');
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: dense ? 13 : 14,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onClear != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClear,
                child: const Text('გასუფთავება'),
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(12, onClear != null ? 0 : 12, 12, 12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final e = entries[index];
              final unread = !e.isRead;
              final style = resolveNotificationEntryStyle(e);
              final accent = style.accent;
              final borderColor = unread ? accent : _readBorder;
              final bg = unread ? accent.withValues(alpha: 0.08) : _readBg;

              return Material(
                color: bg,
                elevation: unread ? 1 : 0,
                shadowColor: unread ? accent.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onEntryTap != null ? () => onEntryTap!(e) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: unread ? 1.5 : 1,
                      ),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: dense ? 10 : 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: dense ? 34 : 40,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.title,
                                      style: TextStyle(
                                        fontWeight: unread
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        fontSize: dense ? 13 : 14,
                                        color: unread
                                            ? Color.alphaBlend(
                                                accent.withValues(alpha: 0.85),
                                                const Color(0xFF0F172A),
                                              )
                                            : _readTitle,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${dateFmt.format(e.at)} ${e.timeLabel}',
                                    style: TextStyle(
                                      fontSize: dense ? 10 : 11,
                                      fontWeight: unread
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: unread
                                          ? accent
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                e.message,
                                style: TextStyle(
                                  fontSize: dense ? 12 : 13,
                                  height: 1.35,
                                  fontWeight: unread
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                  color: _messageColor(style, unread),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _messageColor(NotificationEntryStyle style, bool unread) {
    if (!unread) return _readMessage;
    switch (style.kind) {
      case NotificationEntryKind.decrease:
      case NotificationEntryKind.cancel:
        return style.accent;
      default:
        return Color.alphaBlend(
          style.accent.withValues(alpha: 0.75),
          const Color(0xFF334155),
        );
    }
  }
}
