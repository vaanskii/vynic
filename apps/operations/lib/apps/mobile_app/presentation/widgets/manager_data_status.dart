import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';

const managerDataLabels = {
  'ledger_summary': 'გაყიდვების შეჯამება',
  'sale_history': 'გაყიდვების ისტორია',
  'product_analytics': 'პროდუქტების ანალიზი',
  'sale_staff': 'პერსონალის ანალიზი',
  'dashboard': 'დაფა',
  'tables': 'მაგიდები',
  'takeaway': 'გატანები',
  'financials': 'ფინანსები',
  'staff_performance': 'პერსონალის გაყიდვები',
  'menu': 'მენიუ',
  'top_items': 'პოპულარული პროდუქტები',
  'counted_menus': 'დათვლილი მენიუები',
  'sales_report': 'გაყიდვების ანგარიში',
  'sales_daily': 'დღიური ისტორია',
  'reservations': 'რეზერვაციები',
};

class ManagerDataStatusPanel extends StatefulWidget {
  final Map<String, ManagerReadStatus>? reads;
  final Set<String>? blocks;
  final VoidCallback? onRefresh;
  const ManagerDataStatusPanel({
    super.key,
    this.reads,
    this.blocks,
    this.onRefresh,
  });
  @override
  State<ManagerDataStatusPanel> createState() => _ManagerDataStatusPanelState();
}

class _ManagerDataStatusPanelState extends State<ManagerDataStatusPanel> {
  bool _expanded = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _time(DateTime? value) =>
      value?.toUtc().toIso8601String() ?? 'უცნობია';
  String _completeness(String value) =>
      const {
        'KNOWN': 'სრული',
        'PARTIAL': 'არასრული',
        'LEGACY_FALLBACK': 'ძველი შეჯამება',
        'UNKNOWN': 'უცნობია',
        'UNAVAILABLE': 'მიუწვდომელია',
      }[value] ??
      'უცნობია';
  String _query(String value) {
    final params =
        Uri.tryParse(value)?.queryParameters ?? const <String, String>{};
    return [
      for (final entry in params.entries)
        if (const ['period', 'month', 'date', 'from', 'to'].contains(entry.key))
          '${const {'period': 'პერიოდი', 'month': 'თვე', 'date': 'დღე', 'from': 'დან', 'to': 'მდე'}[entry.key]}: ${const {'today': 'დღეს', 'all': 'ყველა', 'week': 'კვირა', 'month': 'თვე'}[entry.value] ?? entry.value}',
    ].join(' · ');
  }

  String _age(DateTime? value, DateTime now) {
    if (value == null) return 'უცნობია';
    final seconds = now.difference(value).inSeconds;
    return seconds < 0 ? 'საათი შესამოწმებელია' : '$seconds წმ';
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, ManagerReadStatus>>(
    valueListenable: ManagerDataReads.statuses,
    builder: (context, global, _) {
      final reads = (widget.reads ?? global).values
          .toSet()
          .where(
            (r) =>
                r.completeness != 'DISABLED' &&
                (widget.blocks == null || widget.blocks!.contains(r.key)),
          )
          .toList();
      if (reads.isEmpty) return const SizedBox.shrink();
      final now = DateTime.now().toUtc();
      final apiError = reads.any((r) => !r.apiAvailable);
      final limited = reads.any((r) => r.limitedAt(now));
      final title =
          '${apiError ? 'API: განახლების შეცდომა' : 'API: ხელმისაწვდომია'} · ${limited ? 'მონაცემები შეზღუდულია' : 'მონაცემები განახლებულია'}';
      return Material(
        color: limited ? const Color(0xFF31271C) : const Color(0xFF152B29),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'წყარო და დრო',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white,
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    tooltip: 'მონაცემების განახლება',
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                  ),
              ],
            ),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in reads)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${managerDataLabels[r.key] ?? r.key}: ${r.location == 'cache'
                                ? 'ქეში'
                                : r.location == 'memory'
                                ? 'ბოლო ნაჩვენები'
                                : r.location == 'api'
                                ? 'API'
                                : 'მიუწვდომელია'} · წყარო: ${r.source}\n'
                            '${_query(r.query).isEmpty ? '' : '${_query(r.query)}\n'}'
                            'API-დან მიღება: ${_time(r.fetchedAt)} · ასაკი: ${_age(r.fetchedAt, now)}\n'
                            '${r.source == 'CLOUD' ? 'Cloud ცვლილების დრო' : 'POS წყაროს დრო'}: ${_time(r.sourceUpdatedAt)} · ასაკი: ${_age(r.sourceUpdatedAt, now)}\n'
                            'Cloud-ში მიღება: ${_time(r.receivedAt)} · სისრულე: ${_completeness(r.completeness)}'
                            '${r.error == null ? '' : '\n${r.error}'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (limited)
                        const Text(
                          'ეს მონაცემები მიმდინარე POS მდგომარეობას ვერ ადასტურებს. POS ოპერაციის დასრულება დასტურდება მხოლოდ POS-ის პასუხით.',
                          style: TextStyle(
                            color: Color(0xFFFFCF8A),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ManagerDataBoundary extends StatefulWidget {
  final Map<String, ManagerReadStatus>? reads;
  final Set<String> blocks;
  final Widget child;
  final VoidCallback? onRefresh;
  const ManagerDataBoundary({
    super.key,
    required this.blocks,
    required this.child,
    this.onRefresh,
    this.reads,
  });
  @override
  State<ManagerDataBoundary> createState() => _ManagerDataBoundaryState();
}

class _ManagerDataBoundaryState extends State<ManagerDataBoundary>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.onRefresh?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SafeArea(
        bottom: false,
        child: ManagerDataStatusPanel(
          reads: widget.reads,
          blocks: widget.blocks,
          onRefresh: widget.onRefresh,
        ),
      ),
      Expanded(child: widget.child),
    ],
  );
}

class ManagerDataUnavailable extends StatelessWidget {
  final String label;
  const ManagerDataUnavailable({super.key, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      '$label: მონაცემები მიუწვდომელია. სცადეთ განახლება.',
      style: const TextStyle(color: Color(0xFFFFCF8A), fontSize: 14),
    ),
  );
}

class ManagerDataSection extends StatelessWidget {
  final ManagerReadStatus? status;
  final String block;
  final Widget child;
  const ManagerDataSection({
    super.key,
    required this.block,
    required this.child,
    this.status,
  });
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, ManagerReadStatus>>(
        valueListenable: ManagerDataReads.statuses,
        builder: (context, reads, _) {
          final value = status ?? reads[block];
          if (value?.completeness == 'DISABLED') return const SizedBox.shrink();
          return value?.location == 'unavailable' ||
                  value?.completeness == 'UNAVAILABLE'
              ? ManagerDataUnavailable(label: managerDataLabels[block] ?? block)
              : child;
        },
      );
}
