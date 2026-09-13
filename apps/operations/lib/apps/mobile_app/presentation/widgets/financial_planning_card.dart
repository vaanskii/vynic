import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

class FinancialPlanningCard extends StatefulWidget {
  const FinancialPlanningCard({super.key, this.load, this.onOpen});
  final Future<Map<String, dynamic>> Function()? load;
  final void Function(bool obligations)? onOpen;
  @override
  State<FinancialPlanningCard> createState() => _FinancialPlanningCardState();
}

class _FinancialPlanningCardState extends State<FinancialPlanningCard> {
  Map<String, dynamic>? _data;
  bool _loading = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await (widget.load?.call() ??
              MobileApiService.financeRead('planning'));
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

  Future<void> _open(bool obligations) async {
    if (widget.onOpen != null) {
      widget.onOpen!(obligations);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinancePlanningScreen(obligations: obligations),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('dashboard-financial-planning'),
    color: AdminTheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(VynicSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ფინანსური გეგმა',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: 'ფინანსური გეგმის განახლება',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_loading && _data == null) const LinearProgressIndicator(),
          if (_failed)
            Text(
              _data == null
                  ? 'გეგმა ვერ ჩაიტვირთა. სცადეთ განახლება.'
                  : 'განახლება ვერ მოხერხდა. ნაჩვენებია ბოლო მიღებული გეგმა.',
            ),
          if (_data != null) ...[
            Text(
              'დღეს გადასადები: ${_data!['dailyRecommendedReserve']} ₾',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final r in financeRows(_data!['recommendations']).take(3))
              Text('${r['name']} · ${r['periodMonth']}: ${r['amount']} ₾'),
            const SizedBox(height: 8),
            for (final entry in [
              if (ManagerEntitlements.has(FeatureKeys.payroll))
                (false, 'ხელფასებზე დარჩენილი', 'payrollRemaining'),
              (true, 'ვალდებულებებზე დარჩენილი', 'obligationsRemaining'),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  key: ValueKey('planning-${entry.$3}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => _open(entry.$1),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${entry.$2}: ${_data![entry.$3]} ₾'),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
