import 'package:vynic/apps/mobile_app/core/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';
import 'dart:ui';
import 'package:flutter/material.dart';


({Color color, String label, IconData icon}) _statusMeta(String status) {
  final s = status.toLowerCase();
  if (s.startsWith('confirmed')) {
    return (color: MobileGlassTheme.good, label: 'დადასტურებული', icon: Icons.check_circle_rounded);
  }
  if (s.startsWith('completed')) {
    return (color: MobileGlassTheme.good, label: 'დასრულებული', icon: Icons.done_all_rounded);
  }
  if (s.startsWith('cancelled') || s.startsWith('canceled')) {
    return (color: MobileGlassTheme.bad, label: 'გაუქმებული', icon: Icons.cancel_rounded);
  }
  return (color: MobileGlassTheme.warn, label: 'მოლოდინში', icon: Icons.schedule_rounded);
}

/// Full-screen, dark "glass" reservation detail. Slides in from the right.
///
/// Returns `true` on pop when something changed (status/delete).
class ReservationDetailScreen extends StatelessWidget {
  const ReservationDetailScreen({
    super.key,
    required this.row,
    required this.onUpdateStatus,
    required this.onDelete,
  });

  final Map<String, dynamic> row;
  final Future<void> Function(String id, String status) onUpdateStatus;
  final Future<void> Function(String id) onDelete;

  static Route<bool> route({
    required Map<String, dynamic> row,
    required Future<void> Function(String id, String status) onUpdateStatus,
    required Future<void> Function(String id) onDelete,
  }) {
    return PageRouteBuilder<bool>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => managerThemedPage(
            ReservationDetailScreen(
              row: row,
              onUpdateStatus: onUpdateStatus,
              onDelete: onDelete,
            ),
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

  List<Map<String, dynamic>> get _preOrder {
    for (final key in ['preOrderItems', 'preOrders', 'preOrder']) {
      final raw = row[key];
      if (raw is List && raw.isNotEmpty) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  double get _preOrderTotal => _preOrder.fold<double>(0, (sum, e) {
        final t = e['total'] ?? e['totalPrice'];
        if (t is num) return sum + t.toDouble();
        final unit = (e['unitPrice'] ?? e['price'] ?? 0);
        final qty = (e['quantity'] ?? e['qty'] ?? 0);
        final u = unit is num ? unit.toDouble() : 0.0;
        final q = qty is num ? qty.toDouble() : 0.0;
        return sum + u * q;
      });

  @override
  Widget build(BuildContext context) {
    final id = (row['id'] ?? '').toString();
    final status = (row['status'] ?? 'pending').toString();
    final meta = _statusMeta(status);
    final name = (row['customerName'] ?? '').toString();
    final phone = (row['customerPhone'] ?? '').toString();
    final time = (row['reservationTime'] ?? '').toString();
    final date = (row['reservationDate'] ?? '').toString();
    final guests = (row['numberOfGuests'] ?? 0).toString();
    final notes = (row['notes'] ?? '').toString();
    final tables = (row['tableNumbers'] is List)
        ? (row['tableNumbers'] as List).join(', ')
        : '';

    return Scaffold(
      backgroundColor: MobileGlassTheme.bg,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            right: -60,
            child: _GlowOrb(color: meta.color, size: 280),
          ),
          Positioned(
            bottom: 80,
            left: -90,
            child: _GlowOrb(color: MobileGlassTheme.primary, size: 240),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 20, 8),
                  child: Row(
                    children: [
                      _GlassCircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'რეზერვაცია',
                        style: TextStyle(
                          color: MobileGlassTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name.isEmpty ? 'უსახელო' : name,
                                    style: TextStyle(
                                      color: MobileGlassTheme.textPrimary,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _statusPill(meta),
                              ],
                            ),
                            SizedBox(height: 18),
                            _infoRow(Icons.schedule_rounded, 'დრო',
                                time.isEmpty ? '—' : time),
                            _infoRow(Icons.calendar_today_rounded, 'თარიღი',
                                date.isEmpty ? '—' : date),
                            _infoRow(Icons.groups_rounded, 'სტუმრები',
                                '$guests სტუმარი'),
                            _infoRow(Icons.table_bar_rounded, 'მაგიდები',
                                tables.isEmpty ? '—' : tables),
                            _infoRow(Icons.phone_rounded, 'ტელეფონი',
                                phone.isEmpty ? '—' : phone),
                          ],
                        ),
                      ),
                      if (notes.isNotEmpty) ...[
                        SizedBox(height: 16),
                        _GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.notes_rounded,
                                      color: MobileGlassTheme.textSecondary, size: 18),
                                  SizedBox(width: 8),
                                  Text('შენიშვნა',
                                      style: TextStyle(
                                          color: MobileGlassTheme.textSecondary, fontSize: 13)),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(notes,
                                  style: TextStyle(
                                      color: MobileGlassTheme.textPrimary,
                                      fontSize: 14,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                      if (_preOrder.isNotEmpty) ...[
                        SizedBox(height: 16),
                        _buildPreOrderCard(),
                      ],
                      SizedBox(height: 24),
                      _buildActions(context, id, status),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreOrderCard() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu_rounded,
                  color: MobileGlassTheme.primary, size: 18),
              SizedBox(width: 8),
              Text('წინასწარი შეკვეთა',
                  style: TextStyle(
                      color: MobileGlassTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              const Spacer(),
              Text('₾${_preOrderTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: MobileGlassTheme.good, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 12),
          ..._preOrder.map((e) {
            final itemName =
                (e['itemName'] ?? e['name'] ?? 'პოზიცია').toString();
            final qty = (e['quantity'] ?? e['qty'] ?? 1).toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: MobileGlassTheme.surface(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('×$qty',
                        style: TextStyle(
                            color: MobileGlassTheme.textPrimary, fontSize: 12)),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(itemName,
                        style: TextStyle(
                            color: MobileGlassTheme.textPrimary, fontSize: 14)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, String id, String status) {
    final s = status.toLowerCase();
    final canConfirm = !s.startsWith('confirmed') && !s.startsWith('cancelled');
    final canComplete = !s.startsWith('completed') && !s.startsWith('cancelled');
    final canCancel = !s.startsWith('cancelled');

    Future<void> doStatus(String newStatus) async {
      await onUpdateStatus(id, newStatus);
      if (context.mounted) Navigator.of(context).pop(true);
    }

    Future<void> doDelete() async {
      final ok = await _confirmDelete(context);
      if (ok != true) return;
      await onDelete(id);
      if (context.mounted) Navigator.of(context).pop(true);
    }

    return Column(
      children: [
        Row(
          children: [
            if (canConfirm)
              Expanded(
                child: _actionButton(
                  label: 'დადასტურება',
                  icon: Icons.check_rounded,
                  color: MobileGlassTheme.good,
                  onTap: () => doStatus('confirmed'),
                ),
              ),
            if (canConfirm && canComplete) SizedBox(width: 12),
            if (canComplete)
              Expanded(
                child: _actionButton(
                  label: 'დასრულება',
                  icon: Icons.done_all_rounded,
                  color: MobileGlassTheme.good,
                  onTap: () => doStatus('completed'),
                ),
              ),
          ],
        ),
        if (canConfirm || canComplete) SizedBox(height: 12),
        if (canCancel)
          _actionButton(
            label: 'რეზერვაციის გაუქმება',
            icon: Icons.block_rounded,
            color: MobileGlassTheme.warn,
            filled: false,
            onTap: () => doStatus('cancelled'),
          ),
        SizedBox(height: 12),
        _actionButton(
          label: 'წაშლა',
          icon: Icons.delete_outline_rounded,
          color: MobileGlassTheme.bad,
          filled: false,
          onTap: doDelete,
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15151C),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('წაშლა?', style: TextStyle(color: MobileGlassTheme.textPrimary)),
        content: Text(
          'ნამდვილად გსურთ ამ რეზერვაციის წაშლა?',
          style: TextStyle(color: MobileGlassTheme.muted(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('არა', style: TextStyle(color: MobileGlassTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('წაშლა', style: TextStyle(color: MobileGlassTheme.bad)),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(({Color color, String label, IconData icon}) meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: meta.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, color: meta.color, size: 14),
          SizedBox(width: 6),
          Text(meta.label,
              style: TextStyle(
                  color: meta.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: MobileGlassTheme.muted(0.4), size: 18),
          SizedBox(width: 12),
          Text('$label  ',
              style: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: MobileGlassTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      child: filled
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: BorderSide(color: color.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
            ),
    );
  }
}

/// ── shared dark glass widgets ───────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MobileGlassTheme.surface(0.04),
            borderRadius: radius,
            border: Border.all(color: MobileGlassTheme.data.borderSubtle, width: 1),
          ),
          child: child,
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
              color: MobileGlassTheme.surface(0.05),
              border: Border.all(color: MobileGlassTheme.data.borderSubtle),
            ),
            child: Icon(icon, color: MobileGlassTheme.textPrimary, size: 18),
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
