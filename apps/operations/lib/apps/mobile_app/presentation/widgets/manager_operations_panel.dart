import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/manager_app/pos_command_delivery.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';

class ManagerOperationsPanel extends StatefulWidget {
  const ManagerOperationsPanel({
    super.key,
    required this.scope,
    this.compact = true,
    this.slot,
  });
  final String scope;
  final bool compact;
  final String? slot;
  @override
  State<ManagerOperationsPanel> createState() => _ManagerOperationsPanelState();
}

class _ManagerOperationsPanelState extends State<ManagerOperationsPanel> {
  final _busy = <String>{};
  String? _error;
  Future<void> _check(Map<String, dynamic> value) async {
    if (_busy.contains(value['slot'])) return;
    setState(() {
      _busy.add(value['slot']);
      _error = null;
    });
    try {
      await MobileApiService.refreshOperation(value);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'მოთხოვნის შემოწმება ვერ შეინახა მოწყობილობამ — სცადეთ ხელახლა',
        );
    } finally {
      if (mounted) setState(() => _busy.remove(value['slot']));
    }
  }

  Future<void> _dismiss(Map<String, dynamic> value) async {
    if (!MobileApiService.isCurrentTableRepairScope(widget.scope)) return;
    try {
      await ManagerOperationRequests.dismiss(widget.scope, value['slot']);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'მოთხოვნა ვერ დაიხურა — ჩანაწერი შენარჩუნებულია',
        );
    }
  }

  String _title(Map<String, dynamic> value) {
    const labels = {
      'order_cancel': 'შეკვეთის გაუქმება',
      'takeaway_cancel': 'გატანის გაუქმება',
      'takeaway_create': 'გატანის შექმნა',
      'dine_in_create': 'Walk-in შექმნა',
      'reservation_create': 'რეზერვაციის შექმნა',
      'reservation_status': 'რეზერვაციის სტატუსი',
      'reservation_delete': 'რეზერვაციის გაუქმება',
    };
    final body = value['body'] as Map;
    final ref =
        body['customerName'] ?? body['posOrderId'] ?? body['reservationId'];
    return '${labels[value['kind']] ?? 'POS მოთხოვნა'}${ref == null ? '' : ' · $ref'}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ManagerOperationRequests.revision,
    builder: (context, _, __) {
      final theme = managerThemeOf(context);
      if (!MobileApiService.isCurrentTableRepairScope(widget.scope))
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'სესია შეიცვალა — მოთხოვნები გახსენით თავიდან',
            style: TextStyle(color: theme.textSecondary),
          ),
        );
      final List<Map<String, dynamic>> entries;
      try {
        entries = ManagerOperationRequests.all(widget.scope)
            .where((v) => widget.slot == null || v['slot'] == widget.slot)
            .toList();
      } catch (_) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'მოთხოვნების ჟურნალი ვერ იკითხება — შედეგი ვერ დადასტურდა',
          ),
        );
      }
      if (entries.isEmpty) return const SizedBox.shrink();
      if (widget.compact)
        return SafeArea(
          bottom: false,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.pending_actions_rounded),
            title: Text(
              'POS მოთხოვნები · ${entries.length}',
              style: TextStyle(color: theme.textPrimary),
            ),
            subtitle: Text(
              'რიგი, შესრულების შედეგები და შენარჩუნებული მონახაზები',
              style: TextStyle(color: theme.textSecondary),
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 560,
                  height: math.min(
                    MediaQuery.sizeOf(context).height * 0.75,
                    640,
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('POS მოთხოვნები'),
                        trailing: IconButton(
                          tooltip: 'დახურვა',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: ManagerOperationsPanel(
                            scope: widget.scope,
                            compact: false,
                            slot: widget.slot,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.textSecondary),
              ),
            ),
          for (final value in entries)
            Builder(
              builder: (context) {
                final result = ManagerOperationResult.fromMap(value['result']);
                final body = value['body'] as Map;
                final items =
                    (body['items'] ?? body['preOrderItems']) as List? ?? [];
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title(value),
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (items.isNotEmpty)
                          Text(
                            items
                                .map(
                                  (i) => '${i['quantity']} × ${i['itemName']}',
                                )
                                .join(', '),
                            style: TextStyle(color: theme.textSecondary),
                          ),
                        if (body['tableNumbers'] is List)
                          Text(
                            'მაგიდები: ${(body['tableNumbers'] as List).join(', ')}',
                            style: TextStyle(color: theme.textSecondary),
                          ),
                        if (result.reference != null)
                          Text(
                            'POS ნომერი: ${result.reference}',
                            style: TextStyle(color: theme.textSecondary),
                          ),
                        Text(
                          result.message,
                          style: TextStyle(color: theme.textPrimary),
                        ),
                        if (result.isDone)
                          Text(
                            'მონაცემები განახლდება POS-ის სინქრონიზაციით',
                            style: TextStyle(color: theme.textSecondary),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (result.needsCheck ||
                                result.delivery ==
                                    PosCommandDelivery.unavailable)
                              TextButton.icon(
                                onPressed: _busy.contains(value['slot'])
                                    ? null
                                    : () => _check(value),
                                icon: const Icon(Icons.refresh),
                                label: Text(
                                  _busy.contains(value['slot'])
                                      ? 'მოწმდება…'
                                      : 'შედეგის შემოწმება',
                                ),
                              ),
                            if (!result.needsCheck &&
                                !_busy.contains(value['slot']))
                              TextButton(
                                onPressed: () => _dismiss(value),
                                child: const Text('ჩანაწერის დახურვა'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

class ManagerOperationBoundary extends StatelessWidget {
  const ManagerOperationBoundary({
    super.key,
    required this.scope,
    required this.child,
    this.slot,
  });
  final String? scope, slot;
  final Widget child;
  @override
  Widget build(BuildContext context) => scope == null
      ? const Material(
          child: SafeArea(
            child: Center(
              child: Text('სესია ვერ დადასტურდა — გახსენით გვერდი თავიდან'),
            ),
          ),
        )
      : Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              ManagerOperationsPanel(scope: scope!, slot: slot),
              Expanded(child: child),
            ],
          ),
        );
}
