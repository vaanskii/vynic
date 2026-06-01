import 'dart:async';
import 'dart:ui';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/apps/windows_pos/screens/order_detail_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';

class HomeTakeAwaySection extends StatefulWidget {
  const HomeTakeAwaySection({
    super.key,
    required this.user,
    required this.takeAwayReservations,
    required this.onRefreshRequested,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final User user;
  final List<Reservation> takeAwayReservations;
  final Future<void> Function() onRefreshRequested;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  @override
  State<HomeTakeAwaySection> createState() => _HomeTakeAwaySectionState();
}

class _HomeTakeAwaySectionState extends State<HomeTakeAwaySection> {
  @override
  Widget build(BuildContext context) {
    final orderedTakeaways = [...widget.takeAwayReservations]
      ..sort((a, b) {
        final orderIdComparison = (b.linkedOrderId ?? 0).compareTo(
          a.linkedOrderId ?? 0,
        );
        if (orderIdComparison != 0) {
          return orderIdComparison;
        }

        final createdAtComparison = b.createdAt.compareTo(a.createdAt);
        if (createdAtComparison != 0) {
          return createdAtComparison;
        }

        return b.id.compareTo(a.id);
      });
    final pendingCount = widget.takeAwayReservations
        .where((reservation) => reservation.status != 'completed')
        .length;
    final completedCount = widget.takeAwayReservations
        .where((reservation) => reservation.status == 'completed')
        .length;
    final totalAmount = widget.takeAwayReservations.fold<double>(
      0,
      (sum, reservation) => sum + _calculateTakeAwayTotal(reservation),
    );

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 16 : 24,
        isMobile ? 16 : 24,
        96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.list_alt_outlined,
            title: 'დღევანდელი გატანები',
            subtitle:
                'Დაკვირდით აქტიურ შეკვეთებს, სტატუსებს და საჭიროების შემთხვევაში დაბრუნდით შეკვეთაზე.',
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 16 : 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildMetricTile(
                icon: Icons.pending_actions_outlined,
                label: 'აქტიური',
                value: '$pendingCount',
                backgroundColor: const Color(0xFFEFF6FF),
                iconColor: widget.primaryColor,
                isMobile: isMobile,
              ),
              _buildMetricTile(
                icon: Icons.task_alt_outlined,
                label: 'დასრულებული',
                value: '$completedCount',
                backgroundColor: const Color(0xFFECFDF5),
                iconColor: const Color(0xFF047857),
                isMobile: isMobile,
              ),
              _buildMetricTile(
                icon: Icons.attach_money,
                label: 'ჯამური ღირებულება',
                value: '₾${totalAmount.toStringAsFixed(2)}',
                backgroundColor: const Color(0xFFF8FAFC),
                iconColor: widget.secondaryColor,
                isMobile: isMobile,
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 24),
          _buildActionCard(
            icon: Icons.add_circle_outline,
            title: 'ახალი გატანის შეკვეთა',
            description:
                'დაიწყე გატანის შეკვეთა პირდაპირ ამ ეკრანიდან — სიაში მაშინვე გამოჩნდება.',
            isMobile: isMobile,
            actions: [
              ElevatedButton.icon(
                onPressed: _startTakeAwayFlow,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('დაწყება'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (orderedTakeaways.isEmpty)
            _buildTakeAwayEmptyState()
          else
            Column(
              children: orderedTakeaways
                  .map(
                    (reservation) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _buildTakeAwayListCard(reservation, isMobile),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _showTakeAwayDetailsDialog() async {
    return showGeneralDialog<Map<String, String>>(
      context: context,
      barrierLabel: 'გატანის შეკვეთა',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final mediaQuery = MediaQuery.of(dialogContext);
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: mediaQuery.size.width > 560
                      ? 480
                      : mediaQuery.size.width - 48,
                  maxHeight: mediaQuery.size.height > 720
                      ? 620
                      : mediaQuery.size.height * 0.9,
                ),
                child: _TakeAwayDetailsSheet(
                  initialTime: TimeOfDay.now(),
                  onEditNumber: (controller) => _openNameKeyboardSheet(
                    controller: controller,
                    title: 'ნომრის შეყვანა',
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _startTakeAwayFlow() async {
    final details = await _showTakeAwayDetailsDialog();
    if (details == null) {
      return;
    }

    final numberValue = details['number']?.trim() ?? '';
    final waitHere = details['waitHere'] == 'true';
    final label = _buildTakeAwayLabel(waitHere ? null : numberValue);
    final takeAwayDisplayName = waitHere
        ? 'აქ დაელოდება'
        : (numberValue.isNotEmpty ? numberValue : 'გატანის სტუმარი');
    final takeAwayNotes = waitHere ? 'აქ დაელოდება' : numberValue;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MenuScreen(
          user: widget.user,
          selectedTables: [label],
          isTakeAwayMode: true,
          takeAwayCustomerName: takeAwayDisplayName,
          takeAwayCustomerPhone: null,
          takeAwayPickupTime: details['pickupTime'],
          takeAwayNotes: takeAwayNotes,
        ),
      ),
    );

    await widget.onRefreshRequested();
    if (mounted) {
      setState(() {});
    }
  }

  String _buildTakeAwayLabel(String? rawNotes) {
    if (rawNotes == null || rawNotes.trim().isEmpty) {
      return 'გატანა';
    }
    final trimmed = rawNotes.trim();
    final preview = trimmed.length > 24
        ? '${trimmed.substring(0, 24)}…'
        : trimmed;
    return 'გატანა - $preview';
  }

  void _openTakeAwayOrder(int orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrderDetailScreen(user: widget.user, orderId: orderId),
      ),
    ).then((_) async {
      await widget.onRefreshRequested();
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _openNameKeyboardSheet({
    required TextEditingController controller,
    String title = 'ტექსტის შეყვანა',
  }) async {
    final textLength = controller.text.length;
    final currentSelection = controller.selection;
    if (currentSelection.start < 0 ||
        currentSelection.end < 0 ||
        currentSelection.start > textLength ||
        currentSelection.end > textLength) {
      controller.selection = TextSelection.collapsed(offset: textLength);
    }

    String keyboardLanguage = DatabaseService.getDefaultLanguage();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: FractionallySizedBox(
                  heightFactor: 0.78,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xCCF5F6FB),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 24,
                          offset: Offset(0, -6),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          const SizedBox(height: 1),
                          Container(
                            width: 44,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.keyboard_alt,
                                  color: Color(0xFF9B7C4A),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      color: Color(0xFF1F2330),
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    sheetSetState(() {
                                      keyboardLanguage =
                                          keyboardLanguage == 'ka'
                                          ? 'en'
                                          : 'ka';
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.language,
                                    color: Color(0xFF9B7C4A),
                                  ),
                                  label: Text(
                                    keyboardLanguage.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF1F2330),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF9B7C4A),
                                  ),
                                  label: const Text(
                                    'დასრულება',
                                    style: TextStyle(color: Color(0xFF1F2330)),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Color(0x991F2330),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE1E5EE),
                                ),
                              ),
                              child: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, _) {
                                  final displayText = value.text.isEmpty
                                      ? 'დასაწყებად შეეხეთ ქვემოთ არსებულ კლავიატურას'
                                      : value.text;
                                  return Text(
                                    displayText,
                                    style: const TextStyle(
                                      color: Color(0xFF1F2330),
                                      fontSize: 18,
                                      letterSpacing: 0.3,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: OnScreenKeyboard(
                                controller: controller,
                                language: keyboardLanguage,
                                onClose: () => Navigator.pop(sheetContext),
                                onEnter: () => Navigator.pop(sheetContext),
                                showHeader: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTakeAwayListCard(Reservation reservation, bool isMobile) {
    final statusColor = _takeAwayStatusColor(reservation.status);
    final statusLabel = _takeAwayStatusLabel(reservation.status);
    final itemCount = _calculateTakeAwayItems(reservation);
    final totalAmount = _calculateTakeAwayTotal(reservation);
    final pickupTime = reservation.reservationTime;
    final customerName = reservation.customerName.trim().isEmpty
        ? 'გატანის სტუმარი'
        : reservation.customerName.trim();
    final notes = reservation.notes?.trim();
    final hasPhone = reservation.customerPhone.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.primaryColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: widget.primaryColor.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: TextStyle(
                        color: widget.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_outlined,
                          size: 16,
                          color: widget.mutedText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$itemCount ერთეული • ₾${totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: widget.mutedText,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 8 : 10,
                      vertical: isMobile ? 3 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 16, color: widget.mutedText),
                      const SizedBox(width: 6),
                      Text(
                        pickupTime,
                        style: TextStyle(
                          color: widget.mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notes,
              style: TextStyle(color: widget.textPrimary, fontSize: 13),
            ),
          ],
          if (hasPhone) ...[
            const SizedBox(height: 8),
            Text(
              'ტელეფონი: ${reservation.customerPhone}',
              style: TextStyle(color: widget.mutedText, fontSize: 13),
            ),
          ],
          if (reservation.linkedOrderId != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openTakeAwayOrder(reservation.linkedOrderId!),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('შეკვეთის გახსნა'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.primaryColor,
                  side: BorderSide(
                    color: widget.primaryColor.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _calculateTakeAwayItems(Reservation reservation) {
    return reservation.preOrderItems?.fold<int>(
          0,
          (sum, item) => sum + item.quantity,
        ) ??
        0;
  }

  double _calculateTakeAwayTotal(Reservation reservation) {
    return reservation.preOrderItems?.fold<double>(
          0,
          (sum, item) => sum + item.total,
        ) ??
        0;
  }

  Color _takeAwayStatusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF047857);
      case 'preparing':
      case 'confirmed':
        return widget.secondaryColor;
      case 'cancelled':
        return const Color(0xFF9F1239);
      default:
        return const Color(0xFFB45309);
    }
  }

  String _takeAwayStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'დასრულებული';
      case 'preparing':
        return 'მომზადება';
      case 'confirmed':
        return 'დადასტურებული';
      case 'cancelled':
        return 'გაუქმებული';
      default:
        return 'მოლოდინში';
    }
  }

  Widget _buildTakeAwayEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: widget.primaryColor.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: widget.primaryColor.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: widget.mutedText.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'ჯერ არ არის გატანის შეკვეთები',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'დაამატე ახალი გატანის შეკვეთა, რომ სია შეივსოს.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.mutedText.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: widget.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: widget.primaryColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: widget.textPrimary,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: widget.mutedText,
                    fontSize: isMobile ? 13 : 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color backgroundColor,
    required Color iconColor,
    required bool isMobile,
  }) {
    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: widget.mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: widget.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: widget.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: widget.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> actions,
    required bool isMobile,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: widget.primaryColor.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: widget.primaryColor.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: widget.secondaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: widget.secondaryColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: widget.textPrimary,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        color: widget.mutedText,
                        fontSize: isMobile ? 13 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ),
    );
  }
}

class _TakeAwayDetailsSheet extends StatefulWidget {
  const _TakeAwayDetailsSheet({
    required this.initialTime,
    required this.onEditNumber,
  });

  final TimeOfDay initialTime;
  final Future<void> Function(TextEditingController controller) onEditNumber;

  @override
  State<_TakeAwayDetailsSheet> createState() => _TakeAwayDetailsSheetState();
}

class _TakeAwayDetailsSheetState extends State<_TakeAwayDetailsSheet> {
  static const Color _accent = Color(0xFF1D4ED8);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceAlt = Color(0xFFF4F8FF);
  static const Color _outline = Color(0xFFD6E4FF);
  static const Color _label = Color(0xFF1E3A8A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _textPrimary = Color(0xFF0F172A);

  late TimeOfDay _selectedTime;
  final TextEditingController _numberController = TextEditingController();
  bool _waitHere = false;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (selected != null) {
      setState(() => _selectedTime = selected);
    }
  }

  void _submit() {
    final number = _numberController.text.trim();
    if (!_waitHere && number.isEmpty) {
      unawaited(
        showErrorToast(
          context,
          'გთხოვთ, ჩაწეროთ ნომერი ან მონიშნოთ "აქ დაელოდება"',
        ),
      );
      return;
    }
    if (!_waitHere && !RegExp(r'^\d+$').hasMatch(number)) {
      unawaited(showErrorToast(context, 'მხოლოდ ციფრებია დასაშვები'));
      return;
    }

    final pickupString =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    Navigator.of(context).pop({
      'number': _waitHere ? '' : number,
      'waitHere': _waitHere ? 'true' : 'false',
      'pickupTime': pickupString,
    });
  }

  Future<void> _handleEditNumber() async {
    if (_waitHere) {
      return;
    }
    await widget.onEditNumber(_numberController);
    final raw = _numberController.text;
    final sanitized = raw.replaceAll(RegExp(r'\D+'), '');
    if (sanitized != raw) {
      _numberController
        ..text = sanitized
        ..selection = TextSelection.collapsed(offset: sanitized.length);
      if (mounted) {
        unawaited(
          showPosToast(
            context: context,
            message: 'მხოლოდ ციფრებია დასაშვები',
            style: PosToastStyle.info,
          ),
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDisplayTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(20);
    const double bottomPadding = 24;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_surface, _surfaceAlt],
            ),
            border: Border.all(color: _outline),
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: _surface,
                        border: Border(bottom: BorderSide(color: _outline)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ახალი გატანის შეკვეთა',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: _muted),
                            tooltip: 'დახურვა',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          bottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('გატანის დრო'),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _pickTime,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _outline),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x11000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule,
                                      color: _accent,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      _formatDisplayTime(_selectedTime),
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.edit,
                                      color: _muted,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildLabel('ნომერი'),
                            const SizedBox(height: 8),
                            _buildNumberField(),
                            const SizedBox(height: 14),
                            _buildWaitHereSwitch(),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _muted,
                                      side: BorderSide(
                                        color: _muted.withValues(alpha: 0.4),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('გაუქმება'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 3,
                                    ),
                                    child: const Text(
                                      'შეკვეთის დაწყება',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _label,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildNumberField() {
    return GestureDetector(
      onTap: _handleEditNumber,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _numberController,
        builder: (context, value, _) {
          final text = value.text.trim();
          final isEmpty = text.isEmpty || _waitHere;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: _waitHere ? _surfaceAlt.withValues(alpha: 0.8) : _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _outline, width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pin_outlined,
                      color: _waitHere ? _muted : _accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _waitHere
                          ? 'აქ დაელოდება ჩართულია'
                          : (isEmpty ? 'ჩაწერეთ ნომერი' : 'ნომერი'),
                      style: TextStyle(
                        color: isEmpty ? _muted : _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      _waitHere
                          ? 'ნომრის ველი გამორთულია'
                          : (isEmpty
                                ? 'დააჭირეთ და ჩაწერეთ ნომერი'
                                : value.text),
                      style: TextStyle(
                        color: isEmpty ? _muted : _textPrimary,
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWaitHereSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.chair_alt_outlined, color: _accent, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'აქ დაელოდება',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: _waitHere,
            activeThumbColor: _accent,
            onChanged: (value) {
              setState(() {
                _waitHere = value;
                if (_waitHere) {
                  _numberController.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }
}
