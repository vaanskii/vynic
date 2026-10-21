import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'manager_design_components.dart';
import '../../theme/manager_theme.dart';

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
    await showManagerFinancePlanning(context, obligations: obligations);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    return ManagerPanel(
      key: const Key('dashboard-financial-planning'),
      padding: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ManagerSectionHeading(
                  'ფინანსური დაგეგმვა',
                  subtitle: 'პერიოდის დაგეგმილი თანხები',
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: 'ფინანსური გეგმის განახლება',
                icon: const Icon(Icons.refresh, size: 18),
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
            for (final entry in [
              if (ManagerEntitlements.has(FeatureKeys.payroll))
                (false, 'ხელფასები', 'payrollRemaining', Icons.people_outline),
              (
                true,
                'ვალდებულებები',
                'obligationsRemaining',
                Icons.event_repeat_outlined,
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: InkWell(
                  key: ValueKey('planning-${entry.$3}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _open(entry.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: t.scaffoldBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            entry.$4,
                            size: 19,
                            color: t.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.$2,
                                style: managerDesignText(
                                  context,
                                  13,
                                  weight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'დარჩენილი გადასახდელი',
                                style: managerDesignText(
                                  context,
                                  10,
                                  muted: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_data![entry.$3]} ₾',
                          style: managerDesignText(
                            context,
                            13,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 17,
                          color: t.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // The existing recommendation is retained in addition to the approved rows.
            ManagerKeyValue(
              'დღეს გადასადები',
              '${_data!['dailyRecommendedReserve']} ₾',
            ),
            for (final r in financeRows(_data!['recommendations']).take(3))
              ManagerKeyValue(
                '${r['name']} · ${r['periodMonth']}',
                '${r['amount']} ₾',
              ),
            const SizedBox(height: 16),
            Text(
              'რეზერვი გასავლად არ ითვლება.',
              style: managerDesignText(context, 10, muted: true),
            ),
          ],
        ],
      ),
    );
  }
}
