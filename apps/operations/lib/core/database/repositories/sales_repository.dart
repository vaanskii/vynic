import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/sale_record.dart';

import 'package:vynic/core/services/audit/money_audit.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import 'closure_journal_repository.dart';
import '../database_core.dart';
import 'order_repository.dart';
import 'settings_repository.dart';
import 'table_repository.dart';

/// Why a void was refused, so the caller can say which rule stopped it.
///
/// A bare `false` used to cover "no such record", "already void" and "you may
/// not do that" alike, which left the operator staring at one generic error.
enum SaleCancellationOutcome {
  cancelled,
  alreadyCancelled,
  notFound,

  /// No reason was given. A void with no stated reason is the thing this
  /// whole flow exists to prevent.
  reasonRequired,

  /// The sale belongs to an earlier business day. Ordinary Manager use may
  /// only void today's sales; reaching back into a closed period is support
  /// work and needs the `salesRepair` developer scope.
  historicalNotPermitted,

  failed,
}

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

  /// Writes one closed-order record into the sales box.
  ///
  /// Returns the record's Hive key, or null when nothing was written.
  ///
  /// Two things changed in Phase 1B. It no longer increments
  /// `dailySalesTotal`: that counter now has exactly one author,
  /// `BusinessDayRepository.refreshDailySalesTotalForDate`, which derives it
  /// from these records — a counter incremented here and recomputed elsewhere
  /// drifts, and only one of the two can be right. And when [closureId] is
  /// given it refuses to write a second record for a closure that already has
  /// one, which is what makes a retried or double-clicked close harmless.
  static Future<Object?> saveSaleRecord({
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
    String? closureId,
    String? closedById,
    double? grossSaleAmount,
    double advanceApplied = 0.0,
    double? collectedNow,
    String? businessDate,
    String? advanceReceiptId,
  }) async {
    try {
      if (closureId != null) {
        final existing = findSaleKeyByClosureId(closureId);
        if (existing != null) {
          return existing;
        }
      }

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
        'date':
            businessDate ??
            BusinessDayRepository.getCurrentDate().toIso8601String().split(
              'T',
            )[0],
        'isCancelled': isCancelled,
        if (isCancelled)
          'cancelledAt':
              (cancelledAt ?? BusinessDayRepository.getCurrentDateTime())
                  .toIso8601String(),
        'isFiscal': isFiscal,
        'restoredToOrder': false,
        'recordType': SaleRecord.recordTypeSale,
        // The value of the sale, advance included. Records written before
        // Phase 1B have no such field and their `totalAmount` was the balance
        // — readers fall back, which is what those records meant.
        'grossSaleAmount': grossSaleAmount ?? totalAmount,
        'advanceApplied': advanceApplied,
        'collectedNow': collectedNow ?? totalAmount,
        if (closureId != null) 'closureId': closureId,
        if (closedById != null) 'closedById': closedById,
        // Written onto the sale, not only the journal: a restore reads the
        // sale to find which deposit to un-apply, and the sales box is the
        // record that survives everything.
        if (advanceReceiptId != null) 'advanceReceiptId': advanceReceiptId,
      };

      return await DatabaseCore.salesBox!.add(saleRecord);
    } catch (e) {
      developer.log('Error saving sale record: $e');
      return null;
    }
  }

  /// The Hive key of the sale a closure already wrote, if it wrote one.
  ///
  /// This is the backstop that makes recovery safe: the journal records the
  /// key after the write, so a process killed between the two would otherwise
  /// have no way to know the sale exists. The sale itself carries the closure
  /// id, so the truth is always recoverable from the sales box alone.
  static Object? findSaleKeyByClosureId(String closureId) {
    final box = DatabaseCore.salesBox;
    if (box == null) return null;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (raw['closureId'] == closureId) return key;
    }
    return null;
  }

  // ── Advance receipts ──────────────────────────────────────────────────────

  /// Records money taken against a future closure.
  ///
  /// An advance is cash in the drawer on the day it is handed over, and it is
  /// not revenue on any day — the revenue is the sale, later. Before Phase 1B
  /// nothing was written when the advance was taken; a non-fiscal record
  /// appeared at *close* time, dated the closing day, so a deposit taken on
  /// Monday and spent on Friday showed up in Friday's cash. The receipt is
  /// written here instead, dated when it was collected.
  ///
  /// Idempotent on [receiptId]: editing the amount rewrites the same receipt
  /// rather than adding a second one. Returns the receipt id.
  static Future<String?> recordAdvanceReceipt({
    required int orderId,
    required double amount,
    required String collectedBy,
    String? receiptId,
    String? businessDate,
  }) async {
    final box = DatabaseCore.salesBox;
    if (box == null) return null;
    final id = receiptId ?? _uuid.v4();
    final existingKey = _advanceReceiptKey(id);

    if (amount <= 0) {
      if (existingKey != null) {
        await box.delete(existingKey);
      }
      return null;
    }

    final now = BusinessDayRepository.getCurrentDateTime();
    final date =
        businessDate ??
        (existingKey != null
            ? ((box.get(existingKey) as Map)['date'] as String?) ??
                  BusinessDayRepository.dateKey(
                    BusinessDayRepository.getCurrentDate(),
                  )
            : BusinessDayRepository.dateKey(
                BusinessDayRepository.getCurrentDate(),
              ));
    final rounded = double.parse(amount.toStringAsFixed(2));

    final record = <String, dynamic>{
      'recordType': SaleRecord.recordTypeAdvanceReceipt,
      'advanceReceiptId': id,
      'orderId': orderId,
      'tableNumbers': <String>[],
      'floor': '',
      'items': <Map<String, dynamic>>[],
      'totalAmount': rounded,
      'total': rounded,
      'grossSaleAmount': rounded,
      'collectedNow': rounded,
      'advanceApplied': 0.0,
      'paymentMethod': 'advance',
      'paymentBreakdown': <String, double>{'advance': rounded},
      'createdBy': collectedBy,
      'createdAt': now.toIso8601String(),
      'closedAt': now.toIso8601String(),
      'includeServiceFee': false,
      'discountAmount': 0.0,
      'advanceAmount': rounded,
      'subtotalAmount': rounded,
      'manualAdjustmentAmount': 0.0,
      'date': date,
      'isCancelled': false,
      'restoredToOrder': false,
      // An advance is never revenue on its own. Every revenue path filters on
      // `recordType` now, but this stays false so a reader that predates the
      // discriminator also leaves it out of fiscal totals.
      'isFiscal': false,
    };

    if (existingKey != null) {
      await box.put(existingKey, record);
    } else {
      await box.add(record);
    }
    return id;
  }

  /// Marks an advance receipt as consumed by [closureId]. Idempotent.
  static Future<void> _clearAdvanceReceiptApplied(String receiptId) async {
    final box = DatabaseCore.salesBox;
    final key = _advanceReceiptKey(receiptId);
    if (box == null || key == null) return;
    final raw = box.get(key);
    if (raw is! Map) return;
    final updated = Map<String, dynamic>.from(raw)
      ..remove('appliedToClosureId')
      ..remove('appliedAt');
    await box.put(key, updated);
  }

  static Future<void> markAdvanceReceiptApplied({
    required String receiptId,
    required String closureId,
  }) async {
    final box = DatabaseCore.salesBox;
    final key = _advanceReceiptKey(receiptId);
    if (box == null || key == null) return;
    final raw = box.get(key);
    if (raw is! Map) return;
    final updated = Map<String, dynamic>.from(raw);
    if (updated['appliedToClosureId'] == closureId) return;
    updated['appliedToClosureId'] = closureId;
    updated['appliedAt'] = BusinessDayRepository.getCurrentDateTime()
        .toIso8601String();
    await box.put(key, updated);
  }

  static Map<String, dynamic>? findAdvanceReceipt(String receiptId) {
    final box = DatabaseCore.salesBox;
    final key = _advanceReceiptKey(receiptId);
    if (box == null || key == null) return null;
    final raw = box.get(key);
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw)..['recordKey'] = key;
  }

  static Object? _advanceReceiptKey(String receiptId) {
    final box = DatabaseCore.salesBox;
    if (box == null) return null;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (raw['recordType'] == SaleRecord.recordTypeAdvanceReceipt &&
          raw['advanceReceiptId'] == receiptId) {
        return key;
      }
    }
    return null;
  }

  // ── Record classification ─────────────────────────────────────────────────

  /// Whether [sale] is a closed order rather than an advance receipt.
  ///
  /// Records written before the discriminator existed have no `recordType`
  /// and are all closed orders, so absence means sale.
  static bool isSaleRecord(Map<dynamic, dynamic> sale) =>
      (sale['recordType'] ?? SaleRecord.recordTypeSale) ==
      SaleRecord.recordTypeSale;

  static bool isAdvanceReceipt(Map<dynamic, dynamic> sale) =>
      sale['recordType'] == SaleRecord.recordTypeAdvanceReceipt;

  /// Whether [sale] counts toward revenue.
  ///
  /// One predicate, used by every revenue total in the app, so a report
  /// cannot quietly disagree with the daily figure about what a sale is. A
  /// void, a sale restored to an open table, an internal (non-fiscal) closure
  /// and an advance receipt are all excluded — the first two because they
  /// were reversed, the last two because they were never collected revenue.
  static bool countsAsRevenue(Map<dynamic, dynamic> sale) {
    if (!isSaleRecord(sale)) return false;
    if (sale['isCancelled'] == true) return false;
    if (sale['restoredToOrder'] == true) return false;
    if (sale['isFiscal'] == false) return false;
    return true;
  }

  /// The value of a sale: gross where recorded, the stored total otherwise.
  static double grossOf(Map<dynamic, dynamic> sale) {
    final gross = sale['grossSaleAmount'];
    if (gross is num) return gross.toDouble();
    final total = sale['totalAmount'] ?? sale['total'];
    return total is num ? total.toDouble() : 0.0;
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

  /// Gives every stored expense a stable id.
  ///
  /// `saveExpenseRecord` has always written one, but a record restored from a
  /// backup taken before that, or hand-edited, may not have one. Cloud
  /// ingestion keys on this id to stay idempotent, so a record without one
  /// would either be dropped or duplicated on every sync. Runs once at
  /// startup and is a no-op afterwards.
  static Future<int> ensureExpenseIdentities() async {
    final box = DatabaseCore.expenseBox;
    if (box == null) return 0;
    var backfilled = 0;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      final existing = raw['id'];
      if (existing is String && existing.trim().isNotEmpty) continue;
      final data = Map<String, dynamic>.from(raw);
      data['id'] = _uuid.v4();
      await box.put(key, data);
      backfilled++;
    }
    return backfilled;
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

  /// Voids a sale so it stops counting toward revenue.
  ///
  /// The record is never deleted or rewritten — `isCancelled` is set and the
  /// original amounts, items and payment breakdown stay exactly as they were,
  /// so the history remains readable and the void remains reversible by
  /// inspection.
  ///
  /// Three things are required that were not before: a named actor, a stated
  /// [reason], and — for anything older than the current business day —
  /// [allowHistorical], which only a caller holding the support scope may
  /// pass. Voiding a past day's sale silently lowers a figure the restaurant
  /// has already reported, and that is not an ordinary Manager action.
  static Future<SaleCancellationOutcome> cancelSaleRecord({
    required dynamic recordKey,
    required String cancelledBy,
    required String reason,
    bool allowHistorical = false,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      return SaleCancellationOutcome.reasonRequired;
    }
    final actor = cancelledBy.trim();
    if (actor.isEmpty) {
      return SaleCancellationOutcome.reasonRequired;
    }

    try {
      final sale = DatabaseCore.salesBox!.get(recordKey);
      if (sale == null) return SaleCancellationOutcome.notFound;

      final updated = Map<String, dynamic>.from(sale as Map);
      if (updated['isCancelled'] == true) {
        return SaleCancellationOutcome.alreadyCancelled;
      }

      final dateString = (updated['date'] as String?) ?? '';
      final todayString = BusinessDayRepository.getCurrentDate()
          .toIso8601String()
          .split('T')[0];
      final isHistorical = dateString.isNotEmpty && dateString != todayString;
      if (isHistorical && !allowHistorical) {
        return SaleCancellationOutcome.historicalNotPermitted;
      }

      updated['isCancelled'] = true;
      updated['cancelledAt'] = BusinessDayRepository.getCurrentDateTime()
          .toIso8601String();
      updated['cancelledBy'] = actor;
      updated['cancellationReason'] = trimmedReason;
      await DatabaseCore.salesBox!.put(recordKey, updated);

      if (dateString.isNotEmpty) {
        await BusinessDayRepository.refreshDailySalesTotalForDate(
          DateTime.parse(dateString),
        );
      }

      await MoneyAudit.saleCancelled(
        actorId: actor,
        orderId: updated['orderId'],
        businessDate: dateString,
        totalAmount:
            (updated['totalAmount'] as num?)?.toDouble() ??
            (updated['total'] as num?)?.toDouble() ??
            0.0,
        reason: trimmedReason,
        historical: isHistorical,
      );

      return SaleCancellationOutcome.cancelled;
    } catch (e) {
      developer.log('Error cancelling sale record: $e');
      return SaleCancellationOutcome.failed;
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

      // The advance the closure consumed goes back to the reopened order, so
      // re-closing it produces the same gross sale rather than booking the
      // deposit as revenue a second time.
      final restoredAdvance =
          (sale['advanceApplied'] as num?)?.toDouble() ??
          (sale['advanceAmount'] as num?)?.toDouble() ??
          0.0;

      // The closure that wrote this sale is undone. It stays in the journal —
      // the lifecycle has to remain traceable — but it no longer counts as
      // this order's live closure, so closing the table again is a new
      // closure with its own id rather than being refused as a duplicate.
      final closureId = sale['closureId']?.toString();
      if (closureId != null && closureId.isNotEmpty) {
        await ClosureJournalRepository.markReversed(closureId);
      }

      if (order == null) {
        final parsedCreatedAt = _tryParseDate(sale['createdAt'] as String?);
        final includeServiceFee = sale['includeServiceFee'] == true;
        final discountAmount =
            (sale['discountAmount'] as num?)?.toDouble() ?? 0.0;
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
          // The balance the guest still owed, not the gross sale — the
          // advance goes back on the order as an advance and comes off the
          // total again in recalculateTotal.
          totalAmount: (sale['totalAmount'] as num?)?.toDouble() ?? 0.0,
          createdAt: parsedCreatedAt ?? restoreTimestamp,
          createdBy: (sale['createdBy'] as String?) ?? restoredBy,
          status: OrderStatus.confirmed.storageValue,
          includeServiceFee: includeServiceFee,
          discountAmount: discountAmount,
          manualAdjustmentAmount: manualAdjustment,
          openedByUserId: restoredBy,
          paymentMethod: null,
          closedAt: null,
          updatedAt: restoreTimestamp,
          advanceAmount: restoredAdvance,
          advanceReceiptId: sale['advanceReceiptId']?.toString(),
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

      order.statusEnum = OrderStatus.confirmed;
      order.paymentMethod = null;
      order.closedAt = null;
      order.updatedAt = restoreTimestamp;
      order.advanceAmount = restoredAdvance;
      order.advanceReceiptId = sale['advanceReceiptId']?.toString();
      // A reopened order is not a closed one. Leaving the old closure id on
      // it would make the next close look like a retry of the reversed one.
      order.closureId = null;
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

      // The deposit is unspent again: it is held against an open order once
      // more, so it must stop pointing at a closure that was reversed.
      final receiptId = sale['advanceReceiptId']?.toString();
      if (receiptId != null && receiptId.isNotEmpty) {
        await _clearAdvanceReceiptApplied(receiptId);
      }

      await BusinessDayRepository.refreshDailySalesTotalForDate(
        BusinessDayRepository.getCurrentDate(),
      );

      await MoneyAudit.saleRestoredToOrder(
        actorId: restoredBy,
        orderId: orderId,
        businessDate: saleDate,
        totalAmount: (sale['totalAmount'] as num?)?.toDouble() ?? 0.0,
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
