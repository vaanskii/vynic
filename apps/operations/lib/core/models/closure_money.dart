import 'package:vynic/core/models/order.dart';

/// What a table closure is worth, split four ways.
///
/// The POS used to keep one number. An order for 900 with a 50 advance
/// already taken had `totalAmount == 850`, the close booked an 850 sale, and
/// the 900 the guest actually consumed existed nowhere. Revenue was
/// understated by every advance ever taken, and no report could tell an 850
/// order from a 900 order settled with a deposit.
///
/// These four values are what a closure has to preserve to stay reconcilable:
///
/// ```text
/// gross            900   what the guest consumed — the sale
/// advanceApplied    50   money taken earlier, now spent against this order
/// amountDueNow     850   what was payable at the table
/// collectedNow     850   what the tender actually came to
/// ```
///
/// The identity that must always hold:
///
/// ```text
/// gross == advanceApplied + amountDueNow
/// ```
///
/// and, for a closure that is allowed to complete:
///
/// ```text
/// collectedNow == amountDueNow
/// ```
///
/// Discounts, manual adjustments and the service-fee rule are already folded
/// into [gross] by `Order.recalculateTotal` — this class does not re-derive
/// them, it only separates the advance from the balance.
class ClosureMoney {
  const ClosureMoney({
    required this.gross,
    required this.advanceApplied,
    required this.collectedNow,
  });

  /// The value of the completed sale, advance included.
  final double gross;

  /// Money collected before this closure and spent against this order.
  final double advanceApplied;

  /// What the tender at the table came to.
  final double collectedNow;

  /// What was payable at the table: [gross] less the advance.
  double get amountDueNow => _round(gross - advanceApplied);

  /// Reads the money off an order about to be closed.
  ///
  /// `order.totalAmount` is the balance the payment dialog collects against —
  /// it is already net of the advance — so gross is that balance plus the
  /// advance back on.
  factory ClosureMoney.fromOrder(Order order, {required double collectedNow}) {
    final advance = _round(order.effectiveAdvanceAmount);
    return ClosureMoney(
      gross: _round(order.totalAmount + advance),
      advanceApplied: advance,
      collectedNow: _round(collectedNow),
    );
  }

  /// Rebuilds the split from a stored sale record.
  ///
  /// Tolerant of records written before the split existed: those have no
  /// `grossSaleAmount`, and their `totalAmount` *was* the balance, so gross
  /// falls back to it and the advance to zero. That is what those records
  /// meant, and it keeps historical rows readable.
  factory ClosureMoney.fromSaleMap(Map<dynamic, dynamic> sale) {
    final advance =
        _num(sale['advanceApplied']) ?? _num(sale['advanceAmount']) ?? 0.0;
    final total = _num(sale['totalAmount']) ?? _num(sale['total']) ?? 0.0;
    final gross = _num(sale['grossSaleAmount']) ?? total;
    return ClosureMoney(
      gross: _round(gross),
      advanceApplied: _round(advance),
      collectedNow: _round(_num(sale['collectedNow']) ?? (gross - advance)),
    );
  }

  /// `null` when the split is internally consistent, otherwise why it is not.
  ///
  /// Two separate claims are checked, because they fail for different
  /// reasons: the identity is a modelling error, a tender shortfall is an
  /// operator or dialog error.
  String? describeMismatch({double tolerance = 0.01}) {
    final identity = _round(gross - (advanceApplied + amountDueNow));
    if (identity.abs() > tolerance) {
      return 'gross ${gross.toStringAsFixed(2)} does not equal advance '
          '${advanceApplied.toStringAsFixed(2)} + due '
          '${amountDueNow.toStringAsFixed(2)}';
    }
    final settled = _round(collectedNow - amountDueNow);
    if (settled.abs() > tolerance) {
      return 'tender ${collectedNow.toStringAsFixed(2)} does not settle the '
          'balance due ${amountDueNow.toStringAsFixed(2)} '
          '(difference ${settled.toStringAsFixed(2)})';
    }
    return null;
  }

  /// The tender lines plus the advance, so the breakdown sums to [gross].
  ///
  /// Reports that want money *collected on this day* read the tender keys and
  /// skip `advance`; reports that want the value of the sale read the lot.
  Map<String, double> breakdownWithAdvance(Map<String, double>? tender) {
    final result = <String, double>{...?tender};
    if (advanceApplied > 0) {
      result[advanceKey] = advanceApplied;
    }
    return result;
  }

  /// The payment-breakdown key under which an applied advance is recorded.
  ///
  /// It is not a tender: nothing was handed over at the table for this part.
  /// Every summary that adds up money taken today must skip it.
  static const String advanceKey = 'advance';

  Map<String, dynamic> toMap() => {
    'grossSaleAmount': gross,
    'advanceApplied': advanceApplied,
    'amountDueNow': amountDueNow,
    'collectedNow': collectedNow,
  };

  static double _round(double value) => (value * 100).roundToDouble() / 100;

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  String toString() =>
      'ClosureMoney(gross: $gross, advance: $advanceApplied, '
      'due: $amountDueNow, collected: $collectedNow)';
}
