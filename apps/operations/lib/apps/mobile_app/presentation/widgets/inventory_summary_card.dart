import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

class InventorySummaryCard extends StatefulWidget {
  const InventorySummaryCard({
    super.key,
    this.load,
    this.onOpen,
    this.onOpenInventory,
  });
  final Future<Map<String, dynamic>> Function()? load;
  final void Function(String destination, String? businessDate)? onOpen;
  final VoidCallback? onOpenInventory;
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
                section: destination == 'home'
                    ? 4
                    : destination == 'receiving'
                    ? 2
                    : 0,
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
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'მარაგები',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('dashboard-open-inventory'),
                  onPressed:
                      widget.onOpenInventory ?? () => _open('home', null),
                  label: const Text('გახსნა'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                ),
                IconButton(
                  tooltip: 'განახლება',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 20),
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
            if (_data != null) ...[
              ListTile(
                key: const ValueKey('inventory-summary-receiving'),
                contentPadding: EdgeInsets.zero,
                title: const Text('დღევანდელი შესყიდვები'),
                trailing: Text(
                  '${today?['total'] ?? '—'} ₾',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                onTap: () =>
                    _open('receiving', procurement?['today']?.toString()),
              ),
              for (final entry in [
                ('low', 'დაბალი მარაგი', _data!['lowStock']),
                ('negative', 'უარყოფითი მარაგი', _data!['negativeStock']),
                (
                  'unmapped',
                  'გაყიდული პროდუქტები შემადგენლობის გარეშე',
                  _data!['unmappedCount'],
                ),
              ])
                if ((int.tryParse('${entry.$3}') ?? 0) > 0)
                  ListTile(
                    key: ValueKey('inventory-summary-${entry.$1}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: AdminTheme.warn,
                      size: 20,
                    ),
                    title: Text(entry.$2),
                    trailing: Text('${entry.$3} ›'),
                    onTap: () =>
                        _open(entry.$1, procurement?['today']?.toString()),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
