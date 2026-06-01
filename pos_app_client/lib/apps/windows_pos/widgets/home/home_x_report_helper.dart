import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printer_service.dart';
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

class _WaiterSalesAccumulator {
  double total = 0;
  int orderCount = 0;
}
