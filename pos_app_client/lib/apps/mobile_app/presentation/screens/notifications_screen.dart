import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_theme.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/core/widgets/notification_entry_tile.dart';

/// Full-screen notifications list (swipe left to delete).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.onEntryTap,
    required this.onClear,
  });

  final void Function(AppNotificationEntry entry) onEntryTap;
  final VoidCallback onClear;

  static Route<void> route({
    required void Function(AppNotificationEntry entry) onEntryTap,
    required VoidCallback onClear,
  }) {
    return PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => ManagerThemeListener(
        child: NotificationsScreen(onEntryTap: onEntryTap, onClear: onClear),
      ),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = managerThemeOf(context);
    final dateFmt = DateFormat('d MMM');
    return Scaffold(
      backgroundColor: theme.scaffoldBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, theme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'მარცხნივ გადასმა — წაშლა',
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              child: ValueListenableBuilder<List<AppNotificationEntry>>(
                valueListenable: AppNotificationHistoryStore.instance.entries,
                builder: (_, entries, __) {
                  if (entries.isEmpty) return _buildEmpty(theme);
                  return ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Dismissible(
                        key: ValueKey(entry.id),
                        direction: DismissDirection.endToStart,
                        movementDuration: const Duration(milliseconds: 220),
                        onDismissed: (_) {
                          AppNotificationHistoryStore.instance.remove(entry.id);
                        },
                        background: const _SwipeDeleteBackground(),
                        child: NotificationEntryTile(
                          entry: entry,
                          timeLabel:
                              '${dateFmt.format(entry.at)} ${entry.timeLabel}',
                          onTap: () => onEntryTap(entry),
                          light: theme.notificationTileLight,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DashboardThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: theme.textSecondary,
          ),
          Expanded(
            child: Text(
              'შეტყობინებები',
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          ValueListenableBuilder<List<AppNotificationEntry>>(
            valueListenable: AppNotificationHistoryStore.instance.entries,
            builder: (_, entries, __) {
              if (entries.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: onClear,
                child: Text(
                  'გასუფთავება',
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(DashboardThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 52,
            color: theme.textSecondary.withValues(alpha: 0.35),
          ),
          SizedBox(height: 14),
          Text(
            'ჯერ არაფერია',
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Revealed behind the row when swiping left (delete).
class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: MobileGlassTheme.bad,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
          SizedBox(width: 8),
          Text(
            'წაშლა',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
