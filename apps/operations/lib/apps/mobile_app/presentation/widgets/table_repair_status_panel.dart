import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/table_repair_request.dart';

/// Reopened screens retain pending requests. Refresh observes the same command.
class TableRepairStatusPanel extends StatefulWidget {
  const TableRepairStatusPanel({
    super.key,
    required this.scope,
    required this.refresh,
  });
  final String scope;
  final Future<TableRepairResult> Function(String number, String floor) refresh;
  @override
  State<TableRepairStatusPanel> createState() => _TableRepairStatusPanelState();
}

class _TableRepairStatusPanelState extends State<TableRepairStatusPanel> {
  String? _error;
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    TableRepairRequests.init()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object error) {
          if (mounted)
            setState(() => _error = 'მოთხოვნის ისტორია ვერ წაიკითხა');
        });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: TableRepairRequests.revision,
    builder: (context, _, child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        for (final record in TableRepairRequests.list(widget.scope))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${record['floor']} · ${record['tableNumber']}'),
                  Text(
                    TableRepairResult.fromMap(
                      Map<String, dynamic>.from(record['result']),
                    ).message,
                  ),
                  if ((record['result'] as Map)['commandId'] != null)
                    SelectableText(
                      'მოთხოვნის კოდი: ${(record['result'] as Map)['commandId']}',
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('შედეგის განახლება'),
                    onPressed: _busy.contains(record['requestId'])
                        ? null
                        : () async {
                            setState(() {
                              _busy.add(record['requestId']);
                              _error = null;
                            });
                            try {
                              await widget.refresh(
                                record['tableNumber'],
                                record['floor'],
                              );
                            } catch (error) {
                              if (mounted)
                                setState(
                                  () => _error =
                                      'შედეგი ვერ გადამოწმდა — სცადეთ ხელახლა',
                                );
                            } finally {
                              if (mounted)
                                setState(
                                  () => _busy.remove(record['requestId']),
                                );
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
