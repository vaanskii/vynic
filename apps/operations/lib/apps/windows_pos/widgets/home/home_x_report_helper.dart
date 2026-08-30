import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_names.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/payment_utils.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

class HomeXReportHelper {
  const HomeXReportHelper._();

  static List<Map<String, dynamic>> buildWaiterSummaries(
    List<Map<String, dynamic>> sales,
  ) {
    final summaries = <String, _WaiterSalesAccumulator>{};
    for (final sale in sales) {
      final isCancelled = (sale['isCancelled'] ?? false) == true;
      final isFiscal = (sale['isFiscal'] ?? true) == true;
      if (isCancelled || !isFiscal) {
        continue;
      }

      final username = (sale['createdBy'] as String?)?.trim();
      if (username == null || username.isEmpty) {
        continue;
      }

      final accumulator = summaries.putIfAbsent(
        username,
        () => _WaiterSalesAccumulator(),
      );
      accumulator.total += _extractSaleTotal(sale);
      accumulator.orderCount += 1;
    }

    final results =
        summaries.entries
            .map(
              (entry) => {
                'username': entry.key,
                'total': entry.value.total,
                'orderCount': entry.value.orderCount,
              },
            )
            .toList()
          ..sort(
            (a, b) => ((b['total'] as num?) ?? 0).compareTo(
              (a['total'] as num?) ?? 0,
            ),
          );

    return results;
  }

  /// One closed table on the X report: what was sold on it, and when it was
  /// open.
  ///
  /// Everything here comes off the sale record the closure already writes —
  /// no new persisted fields. `createdAt` is when the table was opened and
  /// `closedAt` is when it was paid, so the report can state how long each
  /// table ran rather than only what it took.
  static List<XReportTableRow> buildClosedTables(
    List<Map<String, dynamic>> sales, {
    RestaurantTableLayout? layout,
  }) {
    final resolved = layout ?? DatabaseService.getRestaurantTableLayout();
    final rows = <XReportTableRow>[];

    for (final sale in sales) {
      final floor = (sale['floor'] as String?) ?? '';
      final numbers = _stringList(sale['tableNumbers']);
      final openedAt = _dateTime(sale['createdAt']);
      final closedAt = _dateTime(sale['closedAt']);

      var itemCount = 0;
      for (final item in _mapList(sale['items'])) {
        itemCount += _int(item['quantity']);
      }

      rows.add((
        orderId: sale['orderId'] as int?,
        // The table's own name, so the report agrees with the floor plan the
        // waiter was looking at rather than showing a bare number.
        tables: numbers.isEmpty
            ? 'გატანა'
            : numbers
                  .map(
                    (number) => floorPlanTableNameOrNumber(
                      resolved,
                      floor: floor,
                      tableNumber: number,
                    ),
                  )
                  .join(' + '),
        waiter: ((sale['createdBy'] as String?) ?? '').trim(),
        openedAt: openedAt,
        closedAt: closedAt,
        itemCount: itemCount,
        total: _extractSaleTotal(sale),
        payment: PaymentUtils.formatPaymentDisplay(sale),
        cancelled: (sale['isCancelled'] ?? false) == true,
        fiscal: (sale['isFiscal'] ?? true) == true,
      ));
    }

    // Most recently closed first — the tail of the day is what anyone
    // checking a running X report actually wants to see.
    rows.sort((a, b) {
      final aClosed = a.closedAt;
      final bClosed = b.closedAt;
      if (aClosed == null && bClosed == null) return 0;
      if (aClosed == null) return 1;
      if (bClosed == null) return -1;
      return bClosed.compareTo(aClosed);
    });
    return rows;
  }

  /// Everything sold today, rolled up by dish and ranked by takings.
  ///
  /// Cancelled sales are left out: they were reversed, so counting their
  /// dishes would overstate what actually left the kitchen.
  static List<XReportSoldItem> buildSoldItems(
    List<Map<String, dynamic>> sales,
  ) {
    final byName = <String, ({int quantity, double total})>{};

    for (final sale in sales) {
      if ((sale['isCancelled'] ?? false) == true) {
        continue;
      }
      for (final item in _mapList(sale['items'])) {
        final name = (item['itemName'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final quantity = _int(item['quantity']);
        final total = _double(item['total']);
        final existing = byName[name];
        byName[name] = existing == null
            ? (quantity: quantity, total: total)
            : (
                quantity: existing.quantity + quantity,
                total: existing.total + total,
              );
      }
    }

    final rows =
        [
          for (final entry in byName.entries)
            (
              name: entry.key,
              quantity: entry.value.quantity,
              total: entry.value.total,
            ),
        ]..sort((a, b) {
          final byTotal = b.total.compareTo(a.total);
          return byTotal != 0 ? byTotal : b.quantity.compareTo(a.quantity);
        });
    return rows;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry != null) entry.toString(),
    ];
  }

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is Map)
          entry.map((key, value) => MapEntry(key.toString(), value)),
    ];
  }

  static DateTime? _dateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Future<void> printReport(BuildContext context) async {
    try {
      final currentDate = DatabaseService.getCurrentDate();
      final georgianDate = DatabaseService.getGeorgianFormattedDate(
        currentDate,
      );
      final dailyTotal = DatabaseService.getDailySalesTotal();
      final dateString = currentDate.toIso8601String().split('T')[0];
      final sales = DatabaseService.getSalesForDate(dateString);
      final waiterSummaries = buildWaiterSummaries(sales);

      final StringBuffer report = StringBuffer();
      report.writeln('╔═══════════════════════════════════╗');
      report.writeln('║          X ანგარიში              ║');
      report.writeln('╚═══════════════════════════════════╝');
      report.writeln();
      report.writeln('თარიღი: $georgianDate');
      report.writeln(
        'დრო: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      );
      report.writeln('-----------------------------------');
      report.writeln();
      report.writeln('დღიური გაყიდვების შეჯამება');
      report.writeln('-----------------------------------');
      report.writeln('ჯამური გაყიდვები: ₾${dailyTotal.toStringAsFixed(2)}');
      report.writeln('შეკვეთების რაოდენობა: ${sales.length}');
      report.writeln();

      double cardTbcTotal = 0;
      double cardBogTotal = 0;
      double cashTotal = 0;
      double otherTotal = 0;
      final cardTbcOrders = <int>{};
      final cardBogOrders = <int>{};
      final cashOrders = <int>{};
      final otherOrders = <int>{};

      for (var sale in sales) {
        final orderId = sale['orderId'] as int?;
        final breakdown = PaymentUtils.extractBreakdown(sale);
        if (breakdown.isEmpty) {
          continue;
        }

        breakdown.forEach((methodKey, amount) {
          final normalized = PaymentUtils.normalizeMethodKey(methodKey);
          switch (normalized) {
            case PaymentUtils.methodCardTbc:
              cardTbcTotal += amount;
              if (orderId != null) {
                cardTbcOrders.add(orderId);
              }
              break;
            case PaymentUtils.methodCardBog:
              cardBogTotal += amount;
              if (orderId != null) {
                cardBogOrders.add(orderId);
              }
              break;
            case PaymentUtils.methodCardLegacy:
              cardTbcTotal += amount;
              if (orderId != null) {
                cardTbcOrders.add(orderId);
              }
              break;
            case PaymentUtils.methodCash:
              cashTotal += amount;
              if (orderId != null) {
                cashOrders.add(orderId);
              }
              break;
            case PaymentUtils.methodOther:
              otherTotal += amount;
              if (orderId != null) {
                otherOrders.add(orderId);
              }
              break;
          }
        });
      }

      final cardTbcCount = cardTbcOrders.length;
      final cardBogCount = cardBogOrders.length;
      final cashCount = cashOrders.length;
      final otherCount = otherOrders.length;
      final totalCardCount = cardTbcCount + cardBogCount;
      final totalCardAmount = cardTbcTotal + cardBogTotal;

      report.writeln('გადახდების დეტალიზაცია');
      report.writeln('-----------------------------------');
      report.writeln();
      report.writeln('TBC ბარათი:');
      report.writeln('  რაოდენობა: $cardTbcCount');
      report.writeln('  ჯამი: ₾${cardTbcTotal.toStringAsFixed(2)}');
      report.writeln();
      report.writeln('BOG ბარათი:');
      report.writeln('  რაოდენობა: $cardBogCount');
      report.writeln('  ჯამი: ₾${cardBogTotal.toStringAsFixed(2)}');
      report.writeln();
      report.writeln('ბარათით გადახდების რაოდენობა: $totalCardCount');
      report.writeln(
        'ბარათით გადახდის ჯამი: ₾${totalCardAmount.toStringAsFixed(2)}',
      );
      report.writeln();
      report.writeln('-----------------------------------');
      report.writeln();
      report.writeln('ნაღდი გადახდები:');
      report.writeln('  რაოდენობა: $cashCount');
      report.writeln('  ჯამი: ₾${cashTotal.toStringAsFixed(2)}');
      report.writeln();
      if (otherCount > 0 || otherTotal > 0) {
        report.writeln('სხვა გადახდები:');
        report.writeln('  რაოდენობა: $otherCount');
        report.writeln('  ჯამი: ₾${otherTotal.toStringAsFixed(2)}');
        report.writeln();
      }

      if (waiterSummaries.isNotEmpty) {
        report.writeln('ოფიციანტების გაყიდვები');
        report.writeln('-----------------------------------');
        for (final summary in waiterSummaries) {
          report.writeln('ოფიციანტი: ${summary['username']}');
          report.writeln('  შეკვეთები: ${summary['orderCount']}');
          report.writeln(
            '  ჯამი: ₾${((summary['total'] as num?) ?? 0).toStringAsFixed(2)}',
          );
          report.writeln();
        }
      }

      report.writeln('===================================');
      report.writeln('საერთო ჯამი: ₾${dailyTotal.toStringAsFixed(2)}');
      report.writeln('===================================');
      report.writeln();
      report.writeln('* ეს არის X ანგარიში');
      report.writeln('* დღე ჯერ არ არის დახურული');
      report.writeln();
      report.writeln();
      report.writeln();

      await PrinterService.printTextReport(
        report.toString(),
        reportType: 'X REPORT',
      );

      if (!context.mounted) {
        return;
      }
      unawaited(showSuccessToast(context, 'X ანგარიში წარმატებით დაიბეჭდა'));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      unawaited(showErrorToast(context, 'X ანგარიშის ბეჭდვის შეცდომა: $error'));
    }
  }

  static double _extractSaleTotal(Map<String, dynamic> sale) {
    final primary = sale['total'];
    if (primary is num) {
      return primary.toDouble();
    }
    if (primary is String) {
      final parsed = double.tryParse(primary);
      if (parsed != null) {
        return parsed;
      }
    }

    final fallback = sale['totalAmount'];
    if (fallback is num) {
      return fallback.toDouble();
    }
    if (fallback is String) {
      final parsed = double.tryParse(fallback);
      if (parsed != null) {
        return parsed;
      }
    }

    return 0.0;
  }
}

/// One closed table on the X report.
typedef XReportTableRow = ({
  int? orderId,
  String tables,
  String waiter,
  DateTime? openedAt,
  DateTime? closedAt,
  int itemCount,
  double total,
  String payment,
  bool cancelled,
  bool fiscal,
});

/// One dish, rolled up across every sale of the day.
typedef XReportSoldItem = ({String name, int quantity, double total});

class _WaiterSalesAccumulator {
  double total = 0;
  int orderCount = 0;
}
