import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';

const Color _kAccent = Color(0xFF6366F1);
const Color _kCardBorder = Color(0x14FFFFFF);

/// Full-screen, dark "glass" notifications view.
///
/// Pushed as a route that slides in from the right (Instagram style).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.onEntryTap,
    required this.onClear,
  });

  final void Function(AppNotificationEntry entry) onEntryTap;
  final VoidCallback onClear;

  /// Build the right-to-left slide route.
  static Route<void> route({
    required void Function(AppNotificationEntry entry) onEntryTap,
    required VoidCallback onClear,
  }) {
    return PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) =>
          NotificationsScreen(onEntryTap: onEntryTap, onClear: onClear),
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
    final dateFmt = DateFormat('d MMM');
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      body: Stack(
        children: [
          const Positioned(
            top: -90,
            right: -60,
            child: _GlowOrb(color: Color(0xFF6366F1), size: 280),
          ),
          const Positioned(
            bottom: 120,
            left: -100,
            child: _GlowOrb(color: Color(0xFF8B5CF6), size: 240),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                Expanded(
                  child: ValueListenableBuilder<List<AppNotificationEntry>>(
                    valueListenable:
                        AppNotificationHistoryStore.instance.entries,
                    builder: (_, entries, __) {
                      if (entries.isEmpty) return _buildEmpty();
                      return ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _NotificationCard(
                          entry: entries[index],
                          dateFmt: dateFmt,
                          onTap: () => onEntryTap(entries[index]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 16),
      child: Row(
        children: [
          _GlassCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'შეტყობინებები',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          ValueListenableBuilder<List<AppNotificationEntry>>(
            valueListenable: AppNotificationHistoryStore.instance.entries,
            builder: (_, entries, __) {
              if (entries.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFC7D2FE),
                ),
                child: const Text(
                  'გასუფთავება',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 64,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 16),
          Text(
            'ჯერ არაფერია',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'რეალტაიმ მოვლენები აქ გამოჩნდება',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.entry,
    required this.dateFmt,
    required this.onTap,
  });

  final AppNotificationEntry entry;
  final DateFormat dateFmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool unread = !entry.isRead;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: unread
                  ? _kAccent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unread
                    ? _kAccent.withValues(alpha: 0.45)
                    : _kCardBorder,
                width: unread ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5, right: 12),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread ? _kAccent : Colors.transparent,
                    boxShadow: unread
                        ? [
                            BoxShadow(
                              color: _kAccent.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                    border: unread
                        ? null
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.2)),
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
                              entry.title,
                              style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: unread ? 1 : 0.7),
                                fontSize: 15,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${dateFmt.format(entry.at)} ${entry.timeLabel}',
                            style: TextStyle(
                              color: unread
                                  ? const Color(0xFFC7D2FE)
                                  : Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.message,
                        style: TextStyle(
                          color: Colors.white
                              .withValues(alpha: unread ? 0.85 : 0.5),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: _kCardBorder),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
