import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_receipt_preview_dialog.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

class MobileCountedMenusScreen extends StatefulWidget {
  final User user;
  const MobileCountedMenusScreen({super.key, required this.user});

  @override
  State<MobileCountedMenusScreen> createState() =>
      _MobileCountedMenusScreenState();
}

class _MobileCountedMenusScreenState extends State<MobileCountedMenusScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _drafts = [];
  String? _error;

  static const _bg = Color(0xFF050508);
  static const _primary = Color(0xFF6366F1);
  static const _good = Color(0xFF10B981);
  static const _bad = Color(0xFFEF4444);
  static const _warn = Color(0xFFF59E0B);

  static final _money = NumberFormat('#,##0.00', 'en_US');
  static final _date = DateFormat('dd MMM, HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await MobileApiService.getCountedMenus();
      final drafts = data
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList()
        ..sort((a, b) {
          final ad = DateTime.tryParse('${a['createdAt'] ?? ''}');
          final bd = DateTime.tryParse('${b['createdAt'] ?? ''}');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  double get _totalValue => _drafts.fold<double>(
        0,
        (sum, d) =>
            sum +
            ((d['total'] as num?)?.toDouble() ??
                (d['subtotal'] as num?)?.toDouble() ??
                0),
      );

  int get _totalItems => _drafts.fold<int>(
        0,
        (sum, d) => sum + ((d['items'] as List?)?.length ?? 0),
      );

  Future<void> _startNewCount() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const MobileCalculatorScreen(isCountMode: true),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF15151C),
        title: const Text('წაშლა', style: TextStyle(color: Colors.white)),
        content: Text(
          'ნამდვილად გსურთ ამ ჩანაწერის წაშლა?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('არა'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _bad),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await MobileApiService.deleteCountedMenu(id);
      if (mounted) showSuccessToast(context, 'წარმატებით წაიშალა');
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, 'წაშლა ვერ მოხერხდა: $e');
    }
  }

  Future<void> _printPdf(Map<String, dynamic> draft) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: _primary),
        ),
      );

      final items = (draft['items'] as List).cast<Map<String, dynamic>>();
      final itemStrings = items.map((i) {
        return '${i['quantity']}x ${i['itemName']} - ${i['unitPrice']}';
      }).toList();

      final pngBytes = await PrinterService.generateReceiptPngBytes(
        items: itemStrings,
        total: (draft['total'] as num?)?.toDouble() ??
            (draft['subtotal'] as num?)?.toDouble() ??
            0.0,
        subtotal: (draft['subtotal'] as num?)?.toDouble(),
        serviceFee: (draft['serviceFeeAmount'] as num?)?.toDouble(),
        includeServiceFee: draft['includeServiceFee'] ?? false,
        receiptType: 'menu_count',
        language: 'ka',
      );

      if (mounted) {
        Navigator.pop(context);
        if (pngBytes != null) {
          MobileReceiptPreviewDialog.show(
            context,
            pngBytes,
            title: 'მენიუს ნახვა: ${draft['displayName'] ?? ''}',
          );
        } else {
          showErrorToast(context, 'ქვითრის გენერაცია ვერ მოხერხდა');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showErrorToast(context, 'შეცდომა: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          const Positioned(
            top: -80,
            right: -60,
            child: _GlowOrb(color: Color(0xFFF59E0B), size: 220),
          ),
          const Positioned(
            bottom: 120,
            left: -80,
            child: _GlowOrb(color: Color(0xFF6366F1), size: 260),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                if (!_loading && _error == null && _drafts.isNotEmpty)
                  _buildStatsBar(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewCount,
        backgroundColor: _primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'ახალი დათვლა',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Expanded(
            child: Text(
              'დათვლილი მენიუ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh_rounded,
                color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              label: 'ჯამი',
              value: '₾${_money.format(_totalValue)}',
              color: _good,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatChip(
              label: 'ჩანაწერები',
              value: '${_drafts.length}',
              color: _primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatChip(
              label: 'პოზიციები',
              value: '$_totalItems',
              color: _warn,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: 4,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _GlassCard(
            child: SizedBox(
              height: 96,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: Colors.white.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text(
                'ჩატვირთვა ვერ მოხერხდა',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('თავიდან')),
            ],
          ),
        ),
      );
    }

    if (_drafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _warn.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fact_check_outlined,
                      color: _warn, size: 36),
                ),
                const SizedBox(height: 20),
                const Text(
                  'ჩანაწერები არ არის',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'დააჭირე „ახალი დათვლა“ — აირჩიე პოზიციები მენიუდან და შეინახე სახელით (მაგ. ბანკეტი #1).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _primary,
      backgroundColor: const Color(0xFF15151C),
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        itemCount: _drafts.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _DraftCard(
            draft: _drafts[i],
            onPdf: () => _printPdf(_drafts[i]),
            onDelete: () => _delete('${_drafts[i]['id']}'),
            money: _money,
            date: _date,
          ),
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  final Map<String, dynamic> draft;
  final VoidCallback onPdf;
  final VoidCallback onDelete;
  final NumberFormat money;
  final DateFormat date;

  const _DraftCard({
    required this.draft,
    required this.onPdf,
    required this.onDelete,
    required this.money,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt = DateTime.tryParse('${draft['createdAt'] ?? ''}');
    final items = (draft['items'] as List?) ?? const [];
    final total = (draft['total'] as num?)?.toDouble() ??
        (draft['subtotal'] as num?)?.toDouble() ??
        0.0;
    final qty = items.fold<int>(0, (sum, raw) {
      final it = (raw as Map).cast<String, dynamic>();
      return sum + ((it['quantity'] as num?)?.toInt() ?? 0);
    });

    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withOpacity(0.35),
                      const Color(0xFFF59E0B).withOpacity(0.25),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft['displayName']?.toString() ?? 'დაუსახელებელი',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      createdAt != null
                          ? '${date.format(createdAt.toLocal())} · ${items.length} პოზ. · $qty ც.'
                          : '${items.length} პოზიცია',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₾${money.format(total)}',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...items.take(3).map((raw) {
              final it = (raw as Map).cast<String, dynamic>();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text(
                      '${it['quantity']}×',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${it['itemName'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (items.length > 3)
              Text(
                '+${items.length - 3} სხვა',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                ),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('წაშლა'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassCard({
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.18), color.withOpacity(0)],
        ),
      ),
    );
  }
}
