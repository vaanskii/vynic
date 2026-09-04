import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/utils/payment_utils.dart';

/// Builds the per-business-day Manager projection from authoritative Sale rows.
///
/// Revenue fields are populated only from [SalesRepository.countsAsRevenue].
/// Operational counts may still describe cancelled, restored, or internal Sale
/// records, but those records never enter revenue, tender, item-revenue, or
/// closed-revenue detail fields.
class ManagerSalesHistoryBuilder {
  ManagerSalesHistoryBuilder._();

  static Map<String, Map<String, dynamic>> build({
    required Iterable<Map<String, dynamic>> sales,
    required double Function(String businessDate) expenseTotalForDate,
  }) {
    final history = <String, Map<String, dynamic>>{};

    for (final sale in sales) {
      final date = (sale['date'] as String?)?.trim();
      if (date == null || date.isEmpty) continue;
      final bucket = history.putIfAbsent(
        date,
        () => {
          'date': date,
          'totalRevenue': 0.0,
          'orderCount': 0,
          'totalOrders': 0,
          'cancelledOrders': 0,
          'cashRevenue': 0.0,
          'cardRevenue': 0.0,
          'paymentBreakdown': <String, double>{},
          'topItems': <Map<String, dynamic>>[],
          'closedTables': <Map<String, dynamic>>[],
          'advanceReceived': 0.0,
        },
      );

      if (SalesRepository.isAdvanceReceipt(sale)) {
        final amount = (sale['totalAmount'] as num?)?.toDouble() ?? 0.0;
        bucket['advanceReceived'] =
            ((bucket['advanceReceived'] as num?)?.toDouble() ?? 0.0) + amount;
        continue;
      }

      bucket['totalOrders'] = (bucket['totalOrders'] as int) + 1;
      if (sale['isCancelled'] == true) {
        bucket['cancelledOrders'] = (bucket['cancelledOrders'] as int) + 1;
      }

      if (!SalesRepository.countsAsRevenue(sale)) continue;

      final gross = SalesRepository.grossOf(sale);
      bucket['totalRevenue'] = (bucket['totalRevenue'] as double) + gross;
      bucket['orderCount'] = (bucket['orderCount'] as int) + 1;

      final paymentBreakdown = (bucket['paymentBreakdown'] as Map)
          .cast<String, double>();
      final saleBreakdown = PaymentUtils.extractBreakdown(sale);
      saleBreakdown.forEach((key, amount) {
        paymentBreakdown[key] = (paymentBreakdown[key] ?? 0) + amount;
      });

      final rawTableNumbers = (sale['tableNumbers'] as List?) ?? const [];
      final tableValues = rawTableNumbers
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      final fallbackTable = (sale['tableNumber'] as String?)?.trim() ?? '';
      final floor = (sale['floor'] as String?)?.trim() ?? 'first';
      final orderId = (sale['orderId'] as num?)?.toInt();
      final closedAt = (sale['closedAt'] as String?)?.trim() ?? '';
      final label = tableValues.isNotEmpty
          ? tableValues.join(', ')
          : (fallbackTable.isNotEmpty ? fallbackTable : '#${orderId ?? 0}');
      final normalizedItems = ((sale['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((rawItem) {
            final item = Map<String, dynamic>.from(rawItem);
            final qty = (item['quantity'] as num?)?.toInt() ?? 0;
            final unitPrice =
                (item['unitPrice'] as num?)?.toDouble() ??
                (item['price'] as num?)?.toDouble() ??
                0.0;
            return {
              'name': (item['itemName'] ?? item['name'] ?? '').toString(),
              'qty': qty,
              'unitPrice': double.parse(unitPrice.toStringAsFixed(2)),
              'total': double.parse((qty * unitPrice).toStringAsFixed(2)),
            };
          })
          .toList();
      final closedTables =
          (bucket['closedTables'] as List)
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
            ..add({
              'orderId': orderId,
              'tableLabel': label,
              'tableNumbers': tableValues,
              'floor': floor,
              'isFiscal': true,
              'totalAmount': double.parse(gross.toStringAsFixed(2)),
              'closedAt': closedAt,
              'paymentBreakdown': saleBreakdown.map(
                (key, value) =>
                    MapEntry(key, double.parse(value.toStringAsFixed(2))),
              ),
              'items': normalizedItems,
            });
      bucket['closedTables'] = closedTables;

      final itemTotals = <String, Map<String, double>>{};
      for (final existing in (bucket['topItems'] as List).whereType<Map>()) {
        final item = Map<String, dynamic>.from(existing);
        final name = (item['name'] as String?) ?? '';
        if (name.isEmpty) continue;
        itemTotals[name] = {
          'qty': (item['qty'] as num?)?.toDouble() ?? 0,
          'revenue': (item['revenue'] as num?)?.toDouble() ?? 0,
        };
      }
      for (final rawItem in (sale['items'] as List?) ?? const []) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final name = (item['itemName'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitPrice =
            (item['unitPrice'] as num?)?.toDouble() ??
            (item['price'] as num?)?.toDouble() ??
            0.0;
        final current = itemTotals[name] ?? {'qty': 0, 'revenue': 0};
        current['qty'] = (current['qty'] ?? 0) + qty;
        current['revenue'] = (current['revenue'] ?? 0) + (qty * unitPrice);
        itemTotals[name] = current;
      }
      final sortedItems =
          itemTotals.entries
              .map(
                (entry) => {
                  'name': entry.key,
                  'qty': (entry.value['qty'] ?? 0).round(),
                  'revenue': double.parse(
                    (entry.value['revenue'] ?? 0).toStringAsFixed(2),
                  ),
                },
              )
              .toList()
            ..sort(
              (a, b) => ((b['revenue'] as num?) ?? 0).compareTo(
                (a['revenue'] as num?) ?? 0,
              ),
            );
      bucket['topItems'] = sortedItems.take(300).toList();
    }

    for (final entry in history.entries) {
      final bucket = entry.value;
      final breakdown = (bucket['paymentBreakdown'] as Map)
          .cast<String, double>();
      breakdown.forEach(
        (key, value) => breakdown[key] = double.parse(value.toStringAsFixed(2)),
      );
      bucket['paymentBreakdown'] = breakdown;
      bucket['cashRevenue'] = breakdown['cash'] ?? 0.0;
      bucket['cardRevenue'] = breakdown.entries.fold<double>(
        0,
        (sum, item) => item.key.startsWith('card') ? sum + item.value : sum,
      );
      bucket['totalRevenue'] = double.parse(
        (bucket['totalRevenue'] as double).toStringAsFixed(2),
      );
      final expenseTotal = expenseTotalForDate(entry.key);
      bucket['totalExpenses'] = double.parse(expenseTotal.toStringAsFixed(2));
      bucket['profit'] = double.parse(
        ((bucket['totalRevenue'] as double) - expenseTotal).toStringAsFixed(2),
      );
    }

    return history;
  }
}
