import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';

import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'order_repository.dart';
import 'settings_repository.dart';
import 'table_repository.dart';

/// Sales history and money flow: closing orders with payment, sale/expense
/// records, cancellations, and restoring a closed order back onto a table.
class SalesRepository {
  SalesRepository._();

  static const Uuid _uuid = Uuid();

  static DateTime? _tryParseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  // Save sale record
  static Future<bool> saveSaleRecord({
    required int orderId,
    required List<String> tableNumbers,
    required String floor,
    required List<OrderItem> items,
    required double totalAmount,
    required String paymentMethod,
    Map<String, double>? paymentBreakdown,
    String? customPaymentLabel,
    required String createdBy,
    required DateTime createdAt,
    required DateTime closedAt,
    required bool includeServiceFee,
    double discountAmount = 0.0,
    double advanceAmount = 0.0,
    double? subtotalAmount,
    double? manualAdjustmentAmount,
    Map<String, dynamic>? finalTransaction,
    bool isFiscal = true,
    bool isCancelled = false,
    DateTime? cancelledAt,
  }) async {
    try {
      final saleRecord = {
        'orderId': orderId,
        'tableNumbers': tableNumbers,
        'floor': floor,
        'items': items
            .map(
              (item) => {
                'itemName': item.itemName,
                'quantity': item.quantity,
                'unitPrice': item.unitPrice,
                'total': item.total,
              },
            )
            .toList(),
        'totalAmount': totalAmount,
        'total': totalAmount, // Add this field for reports compatibility
        'paymentMethod': paymentMethod,
        'paymentBreakdown': paymentBreakdown,
        'customPaymentLabel': customPaymentLabel,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'closedAt': closedAt.toIso8601String(),
        'includeServiceFee': includeServiceFee,
        'discountAmount': discountAmount,
        'advanceAmount': advanceAmount,
        'subtotalAmount': subtotalAmount ?? totalAmount,
        'manualAdjustmentAmount': manualAdjustmentAmount ?? 0.0,
        'finalTransaction': finalTransaction,
        'date': BusinessDayRepository.getCurrentDate().toIso8601String().split(
          'T',
        )[0],
        'isCancelled': isCancelled,
        if (isCancelled)
          'cancelledAt':
              (cancelledAt ?? BusinessDayRepository.getCurrentDateTime())
                  .toIso8601String(),
        'isFiscal': isFiscal,
      };

      await DatabaseCore.salesBox!.add(saleRecord);

      // Update daily sales total
      if (isFiscal) {
        final currentTotal =
            DatabaseCore.settingsBox!.get('dailySalesTotal', defaultValue: 0.0)
                as double;
        await DatabaseCore.settingsBox!.put(
          'dailySalesTotal',
          currentTotal + totalAmount,
        );
      }

      return true;
    } catch (e) {
      developer.log('Error saving sale record: $e');
      return false;
    }
  }

  // Get daily sales total
  static double getDailySalesTotal() {
    return DatabaseCore.settingsBox!.get('dailySalesTotal', defaultValue: 0.0)
        as double;
  }

  static Future<Map<String, dynamic>> saveExpenseRecord({
    required String description,
    required double amount,
    required String category,
    String paymentType = 'cash',
    DateTime? createdAt,
    String? businessDate,
    String? sourceId,
  }) async {
    final now = createdAt ?? BusinessDayRepository.getCurrentDateTime();
    final date =
        businessDate ??
        BusinessDayRepository.getCurrentDate().toIso8601String().split('T')[0];
    final record = <String, dynamic>{
      'id': sourceId ?? _uuid.v4(),
      'description': description.trim(),
      'amount': double.parse(amount.toStringAsFixed(2)),
      'category': category.trim().isEmpty ? 'სხვა' : category.trim(),
      'paymentType': paymentType.trim().isEmpty ? 'cash' : paymentType.trim(),
      'createdAt': now.toIso8601String(),
      'date': date,
    };
    await DatabaseCore.expenseBox!.add(record);
    return record;
  }

  static List<Map<String, dynamic>> getExpensesForDate(String date) {
    final entries = <Map<String, dynamic>>[];
    for (final key in DatabaseCore.expenseBox!.keys) {
      final raw = DatabaseCore.expenseBox!.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      if ((data['date'] as String?) != date) continue;
      data['recordKey'] = key;
      entries.add(data);
    }
    entries.sort((a, b) {
      final aTs = (a['createdAt'] as String?) ?? '';
      final bTs = (b['createdAt'] as String?) ?? '';
      return bTs.compareTo(aTs);
    });
    return entries;
  }

  static double getExpenseTotalForDate(String date) {
    return getExpensesForDate(date).fold<double>(
      0.0,
      (sum, expense) => sum + ((expense['amount'] as num?)?.toDouble() ?? 0.0),
    );
  }

  static List<Map<String, dynamic>> getAllExpenseRecords() {
    final entries = <Map<String, dynamic>>[];
    for (final key in DatabaseCore.expenseBox!.keys) {
      final raw = DatabaseCore.expenseBox!.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      data['recordKey'] = key;
      entries.add(data);
    }
    entries.sort((a, b) {
      final aTs = (a['createdAt'] as String?) ?? '';
      final bTs = (b['createdAt'] as String?) ?? '';
      return bTs.compareTo(aTs);
    });
    return entries;
  }

  // Get sales for a specific date
  static List<Map<String, dynamic>> getSalesForDate(String date) {
    return _mapSalesRecords(filterDate: date);
  }

  // Get all sales records
  static List<Map<String, dynamic>> getAllSales() {
    return _mapSalesRecords();
  }

  static List<Map<String, dynamic>> _mapSalesRecords({String? filterDate}) {
    final records = <Map<String, dynamic>>[];

    for (final key in DatabaseCore.salesBox!.keys) {
      final raw = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      if (filterDate != null && raw['date'] != filterDate) {
        continue;
      }
      raw['recordKey'] = key;
      raw['isCancelled'] = raw['isCancelled'] ?? false;
      raw['restoredToOrder'] = raw['restoredToOrder'] ?? false;
      raw['isFiscal'] = raw['isFiscal'] ?? true;
      records.add(raw);
    }

    records.sort(
      (a, b) => (b['closedAt'] as String).compareTo(a['closedAt'] as String),
    );

    return records;
  }

  static Future<bool> cancelSaleRecord(dynamic recordKey) async {
    try {
      final sale = DatabaseCore.salesBox!.get(recordKey);
      if (sale == null) return false;

      final updated = Map<String, dynamic>.from(sale as Map);
      if (updated['isCancelled'] == true) {
        return true;
      }

      updated['isCancelled'] = true;
      updated['cancelledAt'] = BusinessDayRepository.getCurrentDateTime()
          .toIso8601String();
      await DatabaseCore.salesBox!.put(recordKey, updated);

      final dateString = updated['date'] as String?;
      if (dateString != null && dateString.isNotEmpty) {
        await BusinessDayRepository.refreshDailySalesTotalForDate(
          DateTime.parse(dateString),
        );
      }

      return true;
    } catch (e) {
      developer.log('Error cancelling sale record: $e');
      return false;
    }
  }

  static Future<bool> restoreClosedOrderFromSale({
    required dynamic recordKey,
    required String restoredBy,
  }) async {
    try {
      final rawSale = DatabaseCore.salesBox!.get(recordKey);
      if (rawSale == null) {
        return false;
      }

      final sale = Map<String, dynamic>.from(rawSale as Map);
      if (sale['restoredToOrder'] == true) {
        return false;
      }

      final saleDate = (sale['date'] as String?) ?? '';
      final todayDate = BusinessDayRepository.getCurrentDate()
          .toIso8601String()
          .split('T')[0];
      if (saleDate != todayDate) {
        return false;
      }

      final paymentMethod = (sale['paymentMethod'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (paymentMethod == 'advance') {
        return false;
      }

      final orderIdRaw = sale['orderId'];
      final int? orderId = orderIdRaw is int
          ? orderIdRaw
          : int.tryParse(orderIdRaw?.toString() ?? '');
      if (orderId == null) {
        return false;
      }

      final saleFloor = (sale['floor'] as String?)?.trim().isNotEmpty == true
          ? (sale['floor'] as String).trim()
          : 'first';

      final saleTableNumbers = <String>[];
      final seenSaleTables = <String>{};
      final rawTables = (sale['tableNumbers'] as List?) ?? const [];
      for (final raw in rawTables) {
        final normalized = TableRepository.normalizeTableIdentifier(
          raw.toString(),
          saleFloor,
        );
        if (normalized == null || normalized.isEmpty) {
          continue;
        }
        if (!TableRepository.isTableConfigured(
          tableNumber: normalized,
          floor: saleFloor,
        )) {
          continue;
        }
        if (seenSaleTables.add(normalized)) {
          saleTableNumbers.add(normalized);
        }
      }
      if (saleTableNumbers.isEmpty) {
        return false;
      }

      Order? order = OrderRepository.getOrder(orderId);
      final targetFloor = order?.floor ?? saleFloor;
      final targetTables = order?.tableNumbers.isNotEmpty == true
          ? List<String>.from(order!.tableNumbers)
          : saleTableNumbers;

      if (order != null) {
        final normalizedOrderStatus = order.status.toLowerCase();
        if (normalizedOrderStatus != 'closed' &&
            normalizedOrderStatus != 'cancelled') {
          return false;
        }
      }

      for (final tableNumber in targetTables) {
        final table = TableRepository.getTable(tableNumber, targetFloor);
        if (table == null) {
          continue;
        }

        final occupiedByAnotherOrder =
            table.isReserved &&
            table.activeOrderId != null &&
            table.activeOrderId != orderId;
        if (occupiedByAnotherOrder) {
          return false;
        }
      }

      final restoreTimestamp = BusinessDayRepository.getCurrentDateTime();

      if (order == null) {
        final parsedCreatedAt = _tryParseDate(sale['createdAt'] as String?);
        final includeServiceFee = sale['includeServiceFee'] == true;
        final discountAmount =
            (sale['discountAmount'] as num?)?.toDouble() ??
            (sale['advanceAmount'] as num?)?.toDouble() ??
            0.0;
        final manualAdjustment =
            (sale['manualAdjustmentAmount'] as num?)?.toDouble() ?? 0.0;

        final reconstructedItems = <OrderItem>[];
        final rawItems = (sale['items'] as List?) ?? const [];
        for (final raw in rawItems.whereType<Map>()) {
          final quantity = (raw['quantity'] as num?)?.toInt() ?? 0;
          final total = (raw['total'] as num?)?.toDouble() ?? 0.0;
          final unitPrice =
              (raw['unitPrice'] as num?)?.toDouble() ??
              (quantity > 0 ? total / quantity : total);
          final itemName = (raw['itemName'] ?? raw['name'] ?? 'უცნობი პოზიცია')
              .toString();

          reconstructedItems.add(
            OrderItem(
              itemKey: itemName,
              itemName: itemName,
              unitPrice: double.parse(unitPrice.toStringAsFixed(2)),
              quantity: quantity,
              total: double.parse(total.toStringAsFixed(2)),
              comment: raw['comment']?.toString(),
            ),
          );
        }

        order = Order(
          orderId: orderId,
          tableNumbers: targetTables,
          floor: targetFloor,
          items: reconstructedItems,
          totalAmount: (sale['totalAmount'] as num?)?.toDouble() ?? 0.0,
          createdAt: parsedCreatedAt ?? restoreTimestamp,
          createdBy: (sale['createdBy'] as String?) ?? restoredBy,
          status: 'confirmed',
          includeServiceFee: includeServiceFee,
          discountAmount: discountAmount,
          manualAdjustmentAmount: manualAdjustment,
          openedByUserId: restoredBy,
          paymentMethod: null,
          closedAt: null,
          updatedAt: restoreTimestamp,
        );
        order.recalculateTotal(
          serviceFeeRate: SettingsRepository.getServiceFeeRate(),
        );
        await DatabaseCore.orderBox!.add(order);

        final storedLastOrderId =
            (DatabaseCore.settingsBox?.get('lastOrderId') as int?) ?? 0;
        if (orderId > storedLastOrderId) {
          await DatabaseCore.settingsBox?.put('lastOrderId', orderId);
        }
      }

      for (final tableNumber in targetTables) {
        final table = TableRepository.getTable(tableNumber, targetFloor);
        if (table == null) {
          continue;
        }

        await TableRepository.reserveTable(
          tableNumber: tableNumber,
          floor: targetFloor,
          username: restoredBy,
          orderId: orderId,
        );
      }

      order.status = 'confirmed';
      order.paymentMethod = null;
      order.closedAt = null;
      order.updatedAt = restoreTimestamp;
      await order.save();

      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.orders,
          action: 'restored',
          payload: {'orderId': orderId, 'restoredBy': restoredBy},
        ),
      );

      final updatedSale = Map<String, dynamic>.from(sale)
        ..['isCancelled'] = false
        ..remove('cancelledAt')
        ..['restoredToOrder'] = true
        ..['restoredAt'] = restoreTimestamp.toIso8601String()
        ..['restoredBy'] = restoredBy;
      await DatabaseCore.salesBox!.put(recordKey, updatedSale);

      await BusinessDayRepository.refreshDailySalesTotalForDate(
        BusinessDayRepository.getCurrentDate(),
      );
      return true;
    } catch (e) {
      developer.log('Error restoring sale record to order: $e');
      return false;
    }
  }

  // Reset daily sales total (called when closing day)
  static Future<void> resetDailySalesTotal() async {
    await DatabaseCore.settingsBox!.put('dailySalesTotal', 0.0);
  }
}
