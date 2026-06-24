// Characterization tests for [PaymentUtils].
//
// These lock in the CURRENT behavior of payment-breakdown parsing, method
// normalization, and display formatting before any refactor. They make no
// assertion about what the behavior *should* be — only what it *is* today.
// If a future change alters a result here, that change is intentional and the
// expectation should be updated deliberately.

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/utils/payment_utils.dart';

void main() {
  group('PaymentUtils.extractBreakdown', () {
    test('uses explicit paymentBreakdown map when present', () {
      final sale = {
        'paymentBreakdown': {'cash': 10, 'card-tbc': 5.5},
        'paymentMethod': 'cash',
        'total': 999, // ignored when breakdown present
      };
      expect(PaymentUtils.extractBreakdown(sale), {
        'cash': 10.0,
        'card-tbc': 5.5,
      });
    });

    test('drops non-positive amounts from the breakdown', () {
      final sale = {
        'paymentBreakdown': {'cash': 10, 'card': 0, 'other': -3},
      };
      expect(PaymentUtils.extractBreakdown(sale), {'cash': 10.0});
    });

    test('rounds breakdown amounts to two decimals', () {
      final sale = {
        'paymentBreakdown': {'cash': 10.005, 'card': 2.001},
      };
      expect(PaymentUtils.extractBreakdown(sale), {'cash': 10.01, 'card': 2.0});
    });

    test('falls back to paymentMethod + total when breakdown empty', () {
      final sale = {'paymentMethod': 'cash', 'total': 42.5};
      expect(PaymentUtils.extractBreakdown(sale), {'cash': 42.5});
    });

    test('falls back to totalAmount when total absent', () {
      final sale = {'paymentMethod': 'card-bog', 'totalAmount': '17.30'};
      expect(PaymentUtils.extractBreakdown(sale), {'card-bog': 17.3});
    });

    test('encodes other:<label> key for custom payment labels', () {
      final sale = {
        'paymentMethod': 'other',
        'customPaymentLabel': 'voucher',
        'total': 8,
      };
      expect(PaymentUtils.extractBreakdown(sale), {'other:voucher': 8.0});
    });

    test('uses bare "other" key when no custom label', () {
      final sale = {'paymentMethod': 'other', 'total': 8};
      expect(PaymentUtils.extractBreakdown(sale), {'other': 8.0});
    });

    test('returns empty map when nothing usable', () {
      expect(PaymentUtils.extractBreakdown({}), <String, double>{});
      expect(
        PaymentUtils.extractBreakdown({'paymentMethod': 'cash', 'total': 0}),
        <String, double>{},
      );
    });
  });

  group('PaymentUtils.normalizeMethodKey', () {
    test('collapses other:<label> to "other"', () {
      expect(PaymentUtils.normalizeMethodKey('other:voucher'), 'other');
    });

    test('preserves explicit bank card keys', () {
      expect(PaymentUtils.normalizeMethodKey('card-tbc'), 'card-tbc');
      expect(PaymentUtils.normalizeMethodKey('card-bog'), 'card-bog');
    });

    test('collapses unknown card-* to legacy "card"', () {
      expect(PaymentUtils.normalizeMethodKey('card-amex'), 'card');
    });

    test('passes through plain keys unchanged', () {
      expect(PaymentUtils.normalizeMethodKey('cash'), 'cash');
    });
  });

  group('PaymentUtils.methodLabel', () {
    test('maps known method keys to display labels', () {
      expect(PaymentUtils.methodLabel('cash'), 'Cash');
      expect(PaymentUtils.methodLabel('card'), 'Card');
      expect(PaymentUtils.methodLabel('card-tbc'), 'Card (TBC)');
      expect(PaymentUtils.methodLabel('card-bog'), 'Card (BOG)');
      expect(PaymentUtils.methodLabel('non-fiscal'), 'Non-Fiscal');
      expect(PaymentUtils.methodLabel('advance'), 'Advance');
      expect(PaymentUtils.methodLabel('split'), 'Split');
      expect(PaymentUtils.methodLabel('other'), 'Other');
    });

    test('derives bank name for unknown card-* keys', () {
      expect(PaymentUtils.methodLabel('card-amex'), 'Card (AMEX)');
    });

    test('renders other:<label> with the label', () {
      expect(PaymentUtils.methodLabel('other:voucher'), 'Other (voucher)');
      expect(PaymentUtils.methodLabel('other:'), 'Other');
    });

    test('capitalizes unrecognized keys', () {
      expect(PaymentUtils.methodLabel('bonus'), 'Bonus');
    });
  });

  group('PaymentUtils.formatPaymentDisplay', () {
    test('joins multiple breakdown entries with " + "', () {
      final sale = {
        'paymentBreakdown': {'cash': 10, 'card-tbc': 5},
      };
      expect(
        PaymentUtils.formatPaymentDisplay(sale),
        'Cash ₾10.00 + Card (TBC) ₾5.00',
      );
    });

    test('prefixes non-fiscal sales', () {
      final sale = {
        'isFiscal': false,
        'paymentBreakdown': {'cash': 10},
      };
      expect(
        PaymentUtils.formatPaymentDisplay(sale),
        'Non-Fiscal • Cash ₾10.00',
      );
    });

    test('returns bare Non-Fiscal when no breakdown', () {
      expect(
        PaymentUtils.formatPaymentDisplay({'isFiscal': false}),
        'Non-Fiscal',
      );
    });

    test('returns Unknown for fiscal sale with no breakdown', () {
      expect(PaymentUtils.formatPaymentDisplay({}), 'Unknown');
    });
  });

  group('PaymentUtils.extractOtherLabel', () {
    test('returns the first non-empty other:<label>', () {
      expect(
        PaymentUtils.extractOtherLabel({'cash': 5, 'other:voucher': 3}),
        'voucher',
      );
    });

    test('returns null when no other label present', () {
      expect(PaymentUtils.extractOtherLabel({'cash': 5}), isNull);
      expect(PaymentUtils.extractOtherLabel(null), isNull);
    });
  });
}
