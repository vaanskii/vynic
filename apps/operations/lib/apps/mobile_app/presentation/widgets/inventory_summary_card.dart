import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

class InventorySummaryCard extends StatefulWidget {
  const InventorySummaryCard({super.key, this.load, this.onOpen});
  final Future<Map<String, dynamic>> Function()? load;
  final void Function(String destination, String? businessDate)? onOpen;
  @override
  State<InventorySummaryCard> createState() => _InventorySummaryState();
}

class _InventorySummaryState extends State<InventorySummaryCard> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _failed = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data =
          await (widget.load?.call() ??
              MobileApiService.getInventoryOverview());
      if (mounted)
        setState(() {
          _data = data;
          _failed = false;
        });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(String destination, String? date) {
    if (widget.onOpen != null) {
      widget.onOpen!(destination, date);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => destination == 'unmapped'
            ? const ConsumptionHistoryScreen(initialUnmapped: true)
            : InventoryScreen(
                section: destination == 'receiving' ? 2 : 0,
                businessDate: destination == 'receiving' ? date : null,
                stockStatus: destination == 'low'
                    ? 'LOW'
                    : destination == 'negative'
                    ? 'NEGATIVE'
                    : null,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final procurement = _data?['procurement'] as Map?;
    final today = procurement?['calendarDay'] as Map?;
    return Card(
      key: const Key('dashboard-inventory-summary'),
      color: AdminTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AdminTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VynicSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'მარაგები და შესყიდვები',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'განახლება',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_failed)
              Text(
                _data == null
                    ? 'მონაცემები ვერ ჩაიტვირთა. სცადეთ განახლება.'
                    : 'განახლება ვერ მოხერხდა. ნაჩვენებია ბოლო მიღებული მონაცემები.',
              ),
            if (_data == null && !_failed) const LinearProgressIndicator(),
            if (_data != null)
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: VynicSpacing.xs,
                  runSpacing: VynicSpacing.xs,
                  children: [
                    for (final entry in [
                      (
                        'receiving',
                        'დღევანდელი შესყიდვები',
                        '${today?['total'] ?? '—'} ₾',
                      ),
                      ('low', 'დაბალი მარაგი', '${_data!['lowStock']}'),
                      (
                        'negative',
                        'უარყოფითი მარაგი',
                        '${_data!['negativeStock']}',
                      ),
                      (
                        'unmapped',
                        'მიუბმელი გაყიდული პროდუქტები',
                        '${_data!['unmappedCount']}',
                      ),
                    ])
                      SizedBox(
                        width: c.maxWidth < 280
                            ? c.maxWidth
                            : (c.maxWidth - VynicSpacing.xs) / 2,
                        child: OutlinedButton(
                          key: ValueKey('inventory-summary-${entry.$1}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 96),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: AdminTheme.text,
                            side: BorderSide(color: AdminTheme.border),
                            padding: const EdgeInsets.all(VynicSpacing.sm),
                          ),
                          onPressed: () => _open(
                            entry.$1,
                            procurement?['today']?.toString(),
                          ),
                          child: Column(
                            children: [
                              Text(
                                entry.$3,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(entry.$2, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
