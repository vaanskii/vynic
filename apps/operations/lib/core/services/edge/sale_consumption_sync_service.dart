import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/sync/api_config.dart';

/// Independent from financial Sale ACKs. A failed inventory effect remains in
/// its Sale and cannot prevent other Sales from being acknowledged.
class SaleConsumptionSyncService {
  SaleConsumptionSyncService({
    http.Client? client,
    String Function()? baseUrl,
    String? Function()? credential,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? (() => ApiConfig.baseUrl),
       _credential = credential ?? (() => EdgeDeviceCredentialStore.credential);
  final http.Client _client;
  final String Function() _baseUrl;
  final String? Function() _credential;
  bool _syncing = false;
  String? _lastAttemptedId;

  static int revision(Map sale) => sale['restoredToOrder'] == true ? 2 : 1;
  static List<Map> pending() =>
      DatabaseCore.salesBox?.values
          .whereType<Map>()
          .where(
            (s) =>
                s['inventoryConsumption'] is Map &&
                (s['inventoryConsumptionAck'] as num? ?? 0) < revision(s),
          )
          .toList() ??
      [];

  Future<void> syncOnce() async {
    if (_syncing || _credential() == null) return;
    _syncing = true;
    try {
      // Bounded, sequential, per-effect failure isolation; retry next minute.
      final rows = pending();
      final previous = rows.indexWhere(
        (s) => s['posSaleId'] == _lastAttemptedId,
      );
      final start = previous < 0 ? 0 : previous + 1;
      final ordered = [...rows.skip(start), ...rows.take(start)];
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      for (final sale in ordered.take(100)) {
        if (DateTime.now().isAfter(deadline)) break;
        _lastAttemptedId = sale['posSaleId']?.toString();
        final sentRevision = revision(sale);
        try {
          final response = await _client
              .post(
                Uri.parse('${_baseUrl()}/edge/inventory/consumption'),
                headers: {
                  'Content-Type': 'application/json',
                  'X-POS-Sync-Key': _credential()!,
                },
                body: jsonEncode({
                  'posSaleId': sale['posSaleId'],
                  'closureId': sale['closureId'],
                  'orderId': sale['orderId'],
                  'businessDate': sale['date'],
                  'closedAt': sale['closedAt'],
                  'snapshot': sale['inventoryConsumption'],
                  'restoreBusinessDate': sale['restoredToOrder'] == true
                      ? sale['inventoryRestoreBusinessDate'] ??
                            sale['restoredAt']?.toString().substring(0, 10)
                      : null,
                  'reversedAt': sale['restoredToOrder'] == true
                      ? sale['restoredAt']
                      : null,
                }),
              )
              .timeout(const Duration(seconds: 20));
          if (response.statusCode != 201 && response.statusCode != 200) {
            debugPrint(
              '[Inventory] Effect ${sale['posSaleId']} pending: HTTP ${response.statusCode}',
            );
            continue;
          }
          final ack = jsonDecode(response.body);
          if (ack is! Map ||
              ack['posSaleId'] != sale['posSaleId'] ||
              ack['revision'] != sentRevision) {
            throw const FormatException('Invalid inventory acknowledgement');
          }
          // Re-read: a concurrent restore must never be overwritten by ACK.
          final box = DatabaseCore.salesBox!;
          for (final key in box.keys) {
            final current = box.get(key);
            if (current is Map && current['posSaleId'] == sale['posSaleId']) {
              await box.put(key, {
                ...current,
                'inventoryConsumptionAck': sentRevision,
              });
              break;
            }
          }
        } catch (error) {
          debugPrint(
            '[Inventory] Effect ${sale['posSaleId']} retry pending: $error',
          );
        }
      }
    } finally {
      _syncing = false;
    }
  }
}
