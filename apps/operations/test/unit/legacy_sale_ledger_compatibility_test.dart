import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/services/sync/sale_ledger_sync_state.dart';
import 'package:vynic/core/utils/payment_utils.dart';

/// What the POS may send Cloud from a sales box that has been in service for
/// years.
///
/// The reproduced failure was a Sale record written before `collectedNow`
/// existed: a cancelled Order, which by definition took no tender, whose money
/// was then inferred as `gross - advance` and whose `cancelled` sentinel was
/// inferred as the tender that collected it. Cloud refused the payload, and
/// correctly — but the refusal failed the whole snapshot, so one cancellation
/// from months ago blocked orders, tables, menu and staff sync too.
///
/// These are characterization tests: each fixture is a record shape that
/// really can be in the box, and each asserts what may legitimately cross the
/// wire for it.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('legacy_sale_ledger');
    Hive.init(directory.path);
    DatabaseCore.salesBox = await Hive.openBox('legacy_sales');
    DatabaseCore.settingsBox = await Hive.openBox('legacy_settings');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-09-05T00:00:00.000',
    );
  });

  tearDown(() async {
    await Hive.close();
    DatabaseCore.salesBox = null;
    DatabaseCore.settingsBox = null;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  /// The fields every retained Sale has carried since the box existed.
  Map<String, dynamic> base({
    required String id,
    required double total,
    required String method,
  }) => <String, dynamic>{
    'posSaleId': id,
    'ledgerRevision': 1,
    'ledgerUpdatedAt': '2026-09-04T10:30:00.000Z',
    'orderId': 7,
    'tableNumbers': const ['3'],
    'floor': 'first',
    'items': [
      {'itemName': 'Khinkali', 'quantity': 10, 'unitPrice': 1.2, 'total': 12.0},
    ],
    'totalAmount': total,
    'total': total,
    'paymentMethod': method,
    'createdBy': 'waiter',
    'createdAt': '2026-09-04T09:00:00.000Z',
    'closedAt': '2026-09-04T10:30:00.000Z',
    'date': '2026-09-04',
    'restoredToOrder': false,
    'recordType': 'sale',
  };

  /// A cancelled Order as written before commit `79ad18f`, which is when
  /// `collectedNow`, `grossSaleAmount` and `advanceApplied` were introduced.
  /// This is the shape that reproduced the 400.
  Map<String, dynamic> legacyCancelled() => {
    ...base(id: 'legacy-cancelled', total: 12.0, method: 'cancelled'),
    'paymentBreakdown': null,
    'isFiscal': false,
    'isCancelled': true,
    'cancelledAt': '2026-09-04T10:30:00.000Z',
  };

  /// An internal close from the same era: non-fiscal, no money fields.
  Map<String, dynamic> legacyNonFiscal() => {
    ...base(id: 'legacy-non-fiscal', total: 12.0, method: 'non-fiscal'),
    'isFiscal': false,
    'isCancelled': false,
  };

  /// An ordinary legacy cash close. It really did collect its total.
  Map<String, dynamic> legacyCash() => {
    ...base(id: 'legacy-cash', total: 12.0, method: 'cash'),
    'isFiscal': true,
    'isCancelled': false,
  };

  Map<String, dynamic> legacyCard() => {
    ...base(id: 'legacy-card', total: 12.0, method: 'card-tbc'),
    'isFiscal': true,
    'isCancelled': false,
  };

  Map<String, dynamic> payload(Map<String, dynamic> sale) =>
      SaleLedgerSyncState.buildBatch([sale]).single;

  group('the reproduced legacy cancelled Sale', () {
    test('sends no tender and no collection', () {
      final wire = payload(legacyCancelled());

      // The exact assertion the backend was making, from the other side.
      expect(wire['payments'], isEmpty);
      expect(wire['collectedNow'], '0.00');
      expect(wire['isFiscal'], isFalse);
      expect(wire['isCancelled'], isTrue);
    });

    test('still crosses the wire as durable history', () {
      final wire = payload(legacyCancelled());

      // Not deleted, not converted into revenue, not given a payment method
      // it never had: the operational value the Order reached is preserved.
      expect(wire['posSaleId'], 'legacy-cancelled');
      expect(wire['gross'], '12.00');
      expect(wire['amountDueNow'], '12.00');
      expect(wire['paymentMethod'], 'cancelled');
      expect(wire['lines'], hasLength(1));
    });

    test('satisfies every money equation Cloud enforces', () {
      final wire = payload(legacyCancelled());
      double money(String key) => double.parse(wire[key] as String);

      // gross == advanceApplied + amountDueNow
      expect(money('gross'), money('advanceApplied') + money('amountDueNow'));
      // a non-fiscal Sale collects no tender
      expect(money('collectedNow'), 0);
      // tender parts == collectedNow
      expect(wire['payments'], isEmpty);
    });
  });

  group('the sentinels', () {
    test('name what a Sale is, never how it was paid', () {
      expect(PaymentUtils.isNonTenderSentinel('cancelled'), isTrue);
      expect(PaymentUtils.isNonTenderSentinel('non-fiscal'), isTrue);
      expect(PaymentUtils.isNonTenderSentinel('split'), isTrue);

      // Real tenders must keep travelling.
      for (final method in const [
        'cash',
        'card',
        'card-tbc',
        'card-bog',
        'advance',
        'other',
        'other:Voucher',
      ]) {
        expect(
          PaymentUtils.isNonTenderSentinel(method),
          isFalse,
          reason: '$method is a real tender',
        );
      }
    });

    test('share one literal with the cancellation writer', () {
      // If these ever drift, a cancelled Sale silently becomes a tender again.
      expect(
        CancelOrderTransaction.cancelledPaymentMethod,
        PaymentUtils.methodCancelled,
      );
    });

    test('are dropped even from a stored breakdown', () {
      final wire = payload({
        ...legacyCancelled(),
        'paymentBreakdown': const {'cancelled': 12.0},
      });

      expect(wire['payments'], isEmpty);
      expect(wire['collectedNow'], '0.00');
    });

    test('a legacy non-fiscal close reads as zero collection', () {
      final wire = payload(legacyNonFiscal());

      expect(wire['payments'], isEmpty);
      expect(wire['collectedNow'], '0.00');
      expect(wire['isFiscal'], isFalse);
      expect(wire['gross'], '12.00');
    });
  });

  group('valid legacy Sales are untouched', () {
    test('a legacy cash Sale still collects its total', () {
      final wire = payload(legacyCash());

      expect(wire['collectedNow'], '12.00');
      expect(wire['payments'], [
        {'method': 'cash', 'amount': '12.00'},
      ]);
    });

    test('a legacy card Sale keeps its bank', () {
      final wire = payload(legacyCard());

      expect(wire['collectedNow'], '12.00');
      expect(wire['payments'], [
        {'method': 'card-tbc', 'amount': '12.00'},
      ]);
    });

    test('a stored breakdown of real tenders is preserved whole', () {
      final wire = payload({
        ...base(id: 'legacy-split', total: 12.0, method: 'split'),
        'isFiscal': true,
        'isCancelled': false,
        'collectedNow': 12.0,
        'grossSaleAmount': 12.0,
        'advanceApplied': 0.0,
        'paymentBreakdown': const {'cash': 5.0, 'card-bog': 7.0},
      });

      expect(wire['collectedNow'], '12.00');
      expect(wire['payments'], [
        {'method': 'cash', 'amount': '5.00'},
        {'method': 'card-bog', 'amount': '7.00'},
      ]);
    });

    test('an advance plus a final tender keeps both parts', () {
      final wire = payload({
        ...base(id: 'legacy-advance', total: 8.0, method: 'cash'),
        'isFiscal': true,
        'isCancelled': false,
        'grossSaleAmount': 12.0,
        'advanceApplied': 4.0,
        'collectedNow': 8.0,
        'paymentBreakdown': const {'cash': 8.0, 'advance': 4.0},
      });

      expect(wire['gross'], '12.00');
      expect(wire['advanceApplied'], '4.00');
      expect(wire['amountDueNow'], '8.00');
      expect(wire['collectedNow'], '8.00');
      expect(wire['payments'], [
        {'method': 'cash', 'amount': '8.00'},
        {'method': 'advance', 'amount': '4.00'},
      ]);
    });

    test('a restored Sale keeps its frozen tender', () {
      final wire = payload({
        ...legacyCash(),
        'posSaleId': 'legacy-restored',
        'restoredToOrder': true,
      });

      expect(wire['restoredToOrder'], isTrue);
      expect(wire['collectedNow'], '12.00');
      expect(wire['payments'], [
        {'method': 'cash', 'amount': '12.00'},
      ]);
    });
  });

  group('the current cancellation writer', () {
    test('is unchanged and still sends nothing collected', () async {
      final key = await SalesRepository.saveSaleRecord(
        orderId: 9,
        tableNumbers: const ['4'],
        floor: 'first',
        items: const [],
        totalAmount: 12.0,
        paymentMethod: CancelOrderTransaction.cancelledPaymentMethod,
        paymentBreakdown: null,
        createdBy: 'waiter',
        createdAt: DateTime.parse('2026-09-04T09:00:00Z'),
        closedAt: DateTime.parse('2026-09-04T10:30:00Z'),
        includeServiceFee: false,
        advanceApplied: 0.0,
        grossSaleAmount: 12.0,
        collectedNow: 0.0,
        subtotalAmount: 12.0,
        businessDate: '2026-09-04',
        isFiscal: false,
        isCancelled: true,
        cancelledAt: DateTime.parse('2026-09-04T10:30:00Z'),
      );
      final stored = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      final wire = payload(stored);

      expect(stored['collectedNow'], 0.0);
      expect(wire['collectedNow'], '0.00');
      expect(wire['payments'], isEmpty);
      expect(wire['isCancelled'], isTrue);
    });

    test('a record that states what it collected is always believed', () {
      // The fix reads a stored `collectedNow` first and only falls back for a
      // record that has none. A durable value is never second-guessed.
      final split = ClosureMoney.fromSaleMap({
        ...legacyCancelled(),
        'collectedNow': 3.0,
      });
      expect(split.collectedNow, 3.0);
    });
  });

  group('a mixed snapshot', () {
    test('carries the legacy cancellation beside ordinary Sales', () async {
      for (final sale in [
        legacyCash(),
        legacyCancelled(),
        legacyCard(),
        legacyNonFiscal(),
      ]) {
        await DatabaseCore.salesBox!.add(sale);
      }
      final all = DatabaseCore.salesBox!.values
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final batch = SaleLedgerSyncState.buildBatch(all);
      expect(batch, hasLength(4));
      // No row in the batch names a sentinel as a tender, so nothing in it can
      // fail Cloud validation and take the whole snapshot down with it.
      for (final wire in batch) {
        for (final part in wire['payments'] as List) {
          expect(
            PaymentUtils.isNonTenderSentinel(
              (part as Map)['method'] as String,
            ),
            isFalse,
          );
        }
      }

      // The day still declares only the revenue the fiscal Sales earned.
      final declaration = SaleLedgerSyncState.buildDayDeclarations(
        allRecords: all,
        currentBusinessDate: '2026-09-05',
      ).single;
      expect(declaration['expectedSaleCount'], 4);
      expect(declaration['expectedRevenue'], '24.00');
    });
  });
}
