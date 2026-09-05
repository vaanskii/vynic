import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/utils/payment_utils.dart';

/// Durable selection/ACK state for the bounded POS → Cloud Sale upload.
///
/// Sale maps remain the local operational truth. This class only gives each
/// genuine retained Sale a backup-stable identity and tracks which revision
/// Cloud has acknowledged. Advance-receipt records are never projected as
/// Sales.
class SaleLedgerSyncState {
  SaleLedgerSyncState._();

  static const int batchSize = 250;
  static const String _ackKey = 'saleLedgerSyncAcks';
  static const Uuid _uuid = Uuid();

  static Future<void> ensureSaleIdentities() async {
    final box = DatabaseCore.salesBox;
    if (box == null) return;
    for (final key in box.keys.toList(growable: false)) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      final sale = Map<String, dynamic>.from(raw);
      if (!_isSaleRecord(sale)) continue;
      var changed = false;
      if ((sale['posSaleId']?.toString().trim() ?? '').isEmpty) {
        sale['posSaleId'] = _uuid.v4();
        changed = true;
      }
      if (sale['ledgerRevision'] is! int || sale['ledgerRevision'] < 1) {
        sale['ledgerRevision'] = 1;
        changed = true;
      }
      if ((sale['ledgerUpdatedAt']?.toString().trim() ?? '').isEmpty) {
        sale['ledgerUpdatedAt'] =
            sale['closedAt']?.toString() ?? DateTime.now().toIso8601String();
        changed = true;
      }
      if (changed) await box.put(key, sale);
    }
  }

  static void markLifecycleChanged(Map<String, dynamic> sale, DateTime at) {
    final revision = (sale['ledgerRevision'] as num?)?.toInt() ?? 0;
    sale['ledgerRevision'] = revision + 1;
    sale['ledgerUpdatedAt'] = at.toIso8601String();
  }

  static Map<String, int> _acks() {
    final raw = DatabaseCore.settingsBox?.get(_ackKey);
    if (raw is! Map) return <String, int>{};
    return raw.map(
      (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
    );
  }

  /// Returns whether the backend advertised the additive ledger ACK contract.
  static Future<bool> acknowledgeResponse(String responseBody) async {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map || decoded['saleLedgerAck'] is! List) return false;
      final acknowledgements = _acks();
      for (final raw in decoded['saleLedgerAck'] as List) {
        if (raw is! Map) continue;
        final id = raw['posSaleId']?.toString().trim() ?? '';
        final revision = (raw['revision'] as num?)?.toInt() ?? 0;
        if (id.isNotEmpty && revision > (acknowledgements[id] ?? 0)) {
          acknowledgements[id] = revision;
        }
      }
      await DatabaseCore.settingsBox?.put(_ackKey, acknowledgements);
      return true;
    } catch (_) {
      // Old backends may return a non-ledger response. The Sale remains
      // unacknowledged and is retried without affecting local operation.
      return false;
    }
  }

  static List<Map<String, dynamic>> buildBatch(
    Iterable<Map<String, dynamic>> allRecords,
  ) {
    final acknowledgements = _acks();
    return allRecords
        .where(_isSaleRecord)
        .where((sale) {
          final id = sale['posSaleId']?.toString() ?? '';
          final revision = (sale['ledgerRevision'] as num?)?.toInt() ?? 1;
          return id.isNotEmpty && (acknowledgements[id] ?? 0) < revision;
        })
        .take(batchSize)
        .map(_salePayload)
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> buildDayDeclarations({
    required Iterable<Map<String, dynamic>> allRecords,
    required String currentBusinessDate,
  }) {
    final acknowledgements = _acks();
    final sales = allRecords.where(_isSaleRecord).toList();
    final dates = <String>{
      ...BusinessDayRepository.getOperatedBusinessDateKeys(),
      ...sales
          .map((sale) => sale['date']?.toString() ?? '')
          .where((date) => date.isNotEmpty),
    };
    return dates
        .map((date) {
          final daySales = sales
              .where((sale) => sale['date']?.toString() == date)
              .toList();
          final revenue = daySales
              .where(_countsAsRevenue)
              .fold<double>(0, (sum, sale) => sum + _grossOf(sale));
          final allAcknowledged = daySales.every((sale) {
            final id = sale['posSaleId']?.toString() ?? '';
            final revision = (sale['ledgerRevision'] as num?)?.toInt() ?? 1;
            return id.isNotEmpty && (acknowledgements[id] ?? 0) >= revision;
          });
          return <String, dynamic>{
            'businessDate': date,
            'expectedSaleCount': daySales.length,
            'expectedRevenue': _money(revenue),
            // The local daily summary is derived from these same retained Sales.
            // It remains a separate input so Cloud can report, not repair, drift.
            'legacyRevenue': _money(revenue),
            // Close Day is the completeness boundary. Today's still-open period is
            // always partial even if every row so far has reached Cloud.
            'uploadComplete': date != currentBusinessDate && allAcknowledged,
          };
        })
        .toList(growable: false)
      ..sort(
        (a, b) => (a['businessDate'] as String).compareTo(
          b['businessDate'] as String,
        ),
      );
  }

  static Map<String, dynamic> _salePayload(Map<String, dynamic> sale) {
    final split = ClosureMoney.fromSaleMap(sale);
    final subtotal = _number(sale['subtotalAmount'], split.gross);
    final discount = _number(sale['discountAmount'], 0);
    final adjustment = _number(sale['manualAdjustmentAmount'], 0);
    final finalTransaction = sale['finalTransaction'];
    final storedServiceFee = finalTransaction is Map
        ? (finalTransaction['serviceFee'] as num?)?.toDouble()
        : null;
    final serviceFee =
        storedServiceFee ??
        _round(split.gross - subtotal + discount - adjustment);
    // `extractBreakdown` falls back to `{paymentMethod: total}` when a record
    // stored no breakdown, which is right for a legacy cash or card Sale and
    // wrong for a sentinel: `cancelled` names what the record is, not what was
    // tendered. Sentinels are dropped here rather than inside PaymentUtils so
    // the Admin display of a historical row keeps saying what it always said.
    final rawBreakdown = Map<String, double>.of(
      PaymentUtils.extractBreakdown(sale),
    )..removeWhere((key, _) => PaymentUtils.isNonTenderSentinel(key));
    final tenderTotal = rawBreakdown.entries
        .where((entry) => entry.key != ClosureMoney.advanceKey)
        .fold<double>(0, (sum, entry) => sum + entry.value);
    final validBreakdown =
        _round(tenderTotal) == _round(split.collectedNow) &&
        _round(rawBreakdown[ClosureMoney.advanceKey] ?? 0) ==
            _round(split.advanceApplied);
    final breakdown = validBreakdown
        ? rawBreakdown
        : <String, double>{
            if (split.collectedNow > 0) _paymentKey(sale): split.collectedNow,
            if (split.advanceApplied > 0)
              ClosureMoney.advanceKey: split.advanceApplied,
          };
    final items = ((sale['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .toList(growable: false);
    return <String, dynamic>{
      'posSaleId': sale['posSaleId'],
      'posOrderId': (sale['orderId'] as num?)?.toInt() ?? 0,
      if ((sale['closureId']?.toString() ?? '').isNotEmpty)
        'closureId': sale['closureId'],
      'businessDate': sale['date']?.toString() ?? '',
      'createdAt': sale['createdAt']?.toString(),
      'closedAt': sale['closedAt']?.toString(),
      'gross': _money(split.gross),
      'subtotal': _money(subtotal),
      'serviceFee': _money(serviceFee),
      'discount': _money(discount),
      'manualAdjustment': _money(adjustment),
      'advanceApplied': _money(split.advanceApplied),
      'amountDueNow': _money(split.amountDueNow),
      'collectedNow': _money(split.collectedNow),
      'paymentMethod': sale['paymentMethod']?.toString() ?? 'other',
      if ((sale['customPaymentLabel']?.toString() ?? '').isNotEmpty)
        'customPaymentLabel': sale['customPaymentLabel'],
      'isFiscal': sale['isFiscal'] != false,
      'isCancelled': sale['isCancelled'] == true,
      if (sale['cancelledAt'] != null) 'cancelledAt': sale['cancelledAt'],
      if (sale['cancelledBy'] != null) 'cancelledBy': sale['cancelledBy'],
      if (sale['cancellationReason'] != null)
        'cancellationReason': sale['cancellationReason'],
      'restoredToOrder': sale['restoredToOrder'] == true,
      if (sale['restoredAt'] != null) 'restoredAt': sale['restoredAt'],
      if (sale['restoredBy'] != null) 'restoredBy': sale['restoredBy'],
      'createdBy': sale['createdBy']?.toString() ?? 'unknown',
      if ((sale['closedById']?.toString() ?? '').isNotEmpty)
        'closedById': sale['closedById'],
      'tableNumbers': ((sale['tableNumbers'] as List?) ?? const <dynamic>[])
          .map((table) => table.toString())
          .toList(growable: false),
      'floor': sale['floor']?.toString() ?? '',
      'revision': (sale['ledgerRevision'] as num?)?.toInt() ?? 1,
      'sourceUpdatedAt': sale['ledgerUpdatedAt']?.toString(),
      'lines': [
        for (var index = 0; index < items.length; index++)
          <String, dynamic>{
            'lineSeq': index,
            if ((items[index]['menuItemId']?.toString() ?? '').isNotEmpty)
              'menuItemId': items[index]['menuItemId'],
            if ((items[index]['variantId']?.toString() ?? '').isNotEmpty)
              'variantId': items[index]['variantId'],
            'itemName': (items[index]['itemName'] ?? items[index]['name'] ?? '')
                .toString(),
            'quantity': (items[index]['quantity'] as num?)?.toInt() ?? 0,
            'unitPrice': _money(
              _number(items[index]['unitPrice'] ?? items[index]['price'], 0),
            ),
            'lineTotal': _money(
              _number(
                items[index]['total'],
                _number(items[index]['unitPrice'] ?? items[index]['price'], 0) *
                    ((items[index]['quantity'] as num?)?.toInt() ?? 0),
              ),
            ),
            if ((items[index]['comment']?.toString() ?? '').isNotEmpty)
              'comment': items[index]['comment'],
          },
      ],
      'payments': breakdown.entries
          .where((entry) => entry.value > 0)
          .map(
            (entry) => <String, dynamic>{
              'method': entry.key,
              'amount': _money(entry.value),
            },
          )
          .toList(growable: false),
    };
  }

  /// The tender key for money a record says it collected but did not itemise.
  ///
  /// Only reached when there is tender to attribute. A sentinel is not a
  /// tender name, so it resolves to `other` rather than travelling to Cloud as
  /// itself — `split` and `non-fiscal` already did, and `cancelled` is the
  /// third of the same kind.
  static String _paymentKey(Map<String, dynamic> sale) {
    final method =
        sale['paymentMethod']?.toString() ?? PaymentUtils.methodOther;
    if (method == PaymentUtils.methodOther) {
      final label = sale['customPaymentLabel']?.toString().trim() ?? '';
      if (label.isNotEmpty) return 'other:$label';
    }
    if (PaymentUtils.isNonTenderSentinel(method)) {
      return PaymentUtils.methodOther;
    }
    return method;
  }

  static bool _isSaleRecord(Map<dynamic, dynamic> sale) =>
      (sale['recordType'] ?? 'sale') == 'sale';

  static bool _countsAsRevenue(Map<dynamic, dynamic> sale) =>
      _isSaleRecord(sale) &&
      sale['isCancelled'] != true &&
      sale['restoredToOrder'] != true &&
      sale['isFiscal'] != false;

  static double _grossOf(Map<dynamic, dynamic> sale) => _number(
    sale['grossSaleAmount'] ?? sale['totalAmount'] ?? sale['total'],
    0,
  );

  static double _number(Object? value, double fallback) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  static String _money(double value) => _round(value).toStringAsFixed(2);
}
