import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';

/// Investigation view over frozen history, never an inventory editor.
class ConsumptionHistoryScreen extends StatefulWidget {
  const ConsumptionHistoryScreen({
    super.key,
    this.consumptionId,
    this.load,
    this.loadDetail,
  });
  final String? consumptionId;
  final Future<List<Map<String, dynamic>>> Function(
    bool unmapped,
    String? from,
    String? to,
  )?
  load;
  final Future<Map<String, dynamic>> Function(String id)? loadDetail;
  @override
  State<ConsumptionHistoryScreen> createState() => _ConsumptionHistoryState();
}

class _ConsumptionHistoryState extends State<ConsumptionHistoryScreen> {
  bool _unmapped = false;
  DateTimeRange? _dates;
  late Future<List<Map<String, dynamic>>> _rows;
  String _date(DateTime date) => date.toIso8601String().split('T').first;
  @override
  void initState() {
    super.initState();
    _rows = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final id = widget.consumptionId;
    if (id != null)
      return [
        await (widget.loadDetail?.call(id) ??
            MobileApiService.getConsumption(id)),
      ];
    return widget.load?.call(
          _unmapped,
          _dates == null ? null : _date(_dates!.start),
          _dates == null ? null : _date(_dates!.end),
        ) ??
        MobileApiService.getConsumptions(
          unmapped: _unmapped,
          from: _dates == null ? null : _date(_dates!.start),
          to: _dates == null ? null : _date(_dates!.end),
        );
  }

  void _reload() => setState(() {
    _rows = _fetch();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.consumptionId == null
            ? 'მარაგის ჩამოწერები'
            : 'ჩამოწერის დეტალები',
      ),
    ),
    body: Column(
      children: [
        if (widget.consumptionId == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('დაუკავშირებელი გაყიდვები'),
                  selected: _unmapped,
                  onSelected: (value) {
                    _unmapped = value;
                    _reload();
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dates == null
                        ? 'თარიღის არჩევა'
                        : '${_date(_dates!.start)} — ${_date(_dates!.end)}',
                  ),
                  onPressed: () async {
                    final dates = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: _dates,
                    );
                    if (dates != null && mounted) {
                      _dates = dates;
                      _reload();
                    }
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _rows,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (state.hasError)
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ისტორია ვერ ჩაიტვირთა'),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('ხელახლა ცდა'),
                      ),
                    ],
                  ),
                );
              final rows = state.data ?? [];
              if (rows.isEmpty)
                return const Center(child: Text('ჩამოწერები ვერ მოიძებნა'));
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.consumptionId == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'ბოლო 100 ჩანაწერი · ძველი ჩანაწერებისთვის აირჩიეთ თარიღი',
                      ),
                    ),
                  for (final row in rows)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'შეკვეთა #${row['orderId']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${row['businessDate']} · ${row['reversedAt'] != null
                                  ? 'აღდგენილი'
                                  : row['policy'] == 'INTERNAL_EXCLUDED'
                                  ? 'შიდა დახურვა — ჩამოწერის გარეშე'
                                  : 'ჩამოწერილი'}',
                            ),
                            if (widget.consumptionId != null) ...[
                              SelectableText('Sale: ${row['posSaleId']}'),
                              SelectableText('Closure: ${row['closureId']}'),
                            ],
                            const Divider(),
                            for (final line
                                in (row['lines'] as List? ?? [])
                                    .whereType<Map>()) ...[
                              Text(
                                '${line['itemName']}${(line['variantName'] ?? line['variantId']) == null ? '' : ' · ${line['variantName'] ?? line['variantId']}'} × ${line['soldQuantity']}',
                              ),
                              if (line['status'] == 'UNMAPPED')
                                const Text(
                                  'დაუკავშირებელია — მარაგი არ ჩამოწერილა',
                                  style: TextStyle(color: Colors.deepOrange),
                                ),
                              if (line['status'] == 'EXCLUDED')
                                const Text(
                                  'შიდა დახურვა — ავტომატური ჩამოწერა გამორიცხულია',
                                ),
                              if (widget.consumptionId != null &&
                                  line['recipeId'] != null) ...[
                                SelectableText(
                                  'რეცეპტი: ${line['recipeId']} · ვერსია ${line['recipeRevision']}',
                                ),
                                if (line['variantId'] != null)
                                  SelectableText(
                                    'ვარიანტი: ${line['variantId']}',
                                  ),
                                for (final c
                                    in (line['components'] as List? ?? [])
                                        .whereType<Map>())
                                  Text(
                                    '${c['stockItemNameSnapshot']}: ${c['baseQuantityPerUnit']} × ${line['soldQuantity']} = ${c['totalBaseQuantity']} ${_unit(c['baseUnit']?.toString() ?? '')}',
                                  ),
                              ],
                              const SizedBox(height: 10),
                            ],
                            if (widget.consumptionId == null)
                              TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ConsumptionHistoryScreen(
                                      consumptionId: row['id'] as String,
                                      loadDetail: widget.loadDetail,
                                    ),
                                  ),
                                ),
                                child: const Text('დეტალები'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

String _unit(String unit) =>
    const {
      'kg': 'კგ',
      'g': 'გ',
      'L': 'ლ',
      'ml': 'მლ',
      'piece': 'ცალი',
      'bottle': 'ბოთლი',
      'pack': 'შეკვრა',
      'box': 'ყუთი',
    }[unit] ??
    unit;
