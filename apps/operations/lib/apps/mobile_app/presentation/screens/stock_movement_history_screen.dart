import 'package:flutter/material.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/models/inventory_history_page.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import '../widgets/inventory_history_view.dart';
import '../widgets/inventory_movement_value.dart';

class StockMovementHistoryScreen extends StatefulWidget {
  const StockMovementHistoryScreen({
    super.key,
    required this.stockItemId,
    required this.name,
    this.loadPage,
    this.saveCsv,
  });
  final String stockItemId, name;
  final InventoryHistoryLoader? loadPage;
  final Future<void> Function(String)? saveCsv;
  @override
  State<StockMovementHistoryScreen> createState() =>
      _StockMovementHistoryState();
}

class _StockMovementHistoryState extends State<StockMovementHistoryScreen> {
  DateTimeRange? _dates;
  String date(DateTime d) => d.toIso8601String().split('T').first;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.name} · მოძრაობები')),
    body: Column(
      children: [
        TextButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text(
            _dates == null
                ? 'თარიღის არჩევა'
                : '${date(_dates!.start)} — ${date(_dates!.end)}',
          ),
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDateRange: _dates,
            );
            if (range != null && mounted) setState(() => _dates = range);
          },
        ),
        if (_dates != null)
          TextButton(
            onPressed: () => setState(() => _dates = null),
            child: const Text('ყველა თარიღი'),
          ),
        Expanded(
          child: InventoryHistoryView(
            key: ValueKey(_dates),
            filters: {
              'stockItemId': widget.stockItemId,
              'from': _dates == null ? null : date(_dates!.start),
              'to': _dates == null ? null : date(_dates!.end),
            },
            load:
                widget.loadPage ??
                (cursor) => MobileApiService.getInventoryHistoryPage(
                  stockItemId: widget.stockItemId,
                  from: _dates == null ? null : date(_dates!.start),
                  to: _dates == null ? null : date(_dates!.end),
                  cursor: cursor,
                ),
            saveCsv: widget.saveCsv,
            itemBuilder: (row) {
              final movement = StockMovement.fromJson(row);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${movement.quantityDeltaBase} ${movement.baseUnit.label} · ${movement.businessDate}',
                      ),
                      Text(
                        '${movement.movementType.label} · ${movement.actorName}',
                      ),
                      SelectableText('ID: ${movement.id}'),
                      InventoryMovementValue(movement: movement),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
