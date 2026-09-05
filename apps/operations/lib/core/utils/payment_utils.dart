class PaymentUtils {
  static const String methodCash = 'cash';
  static const String methodCardTbc = 'card-tbc';
  static const String methodCardBog = 'card-bog';
  static const String methodCardLegacy = 'card';
  static const String methodOther = 'other';
  static const String methodNonFiscal = 'non-fiscal';
  static const String methodAdvance = 'advance';

  /// What a cancelled Order's Sale record carries as its `paymentMethod`.
  ///
  /// The same literal `CancelOrderTransaction.cancelledPaymentMethod` writes;
  /// a test asserts the two agree, so the vocabulary cannot drift.
  static const String methodCancelled = 'cancelled';

  /// The `paymentMethod` a split close records instead of naming a tender.
  static const String methodSplit = 'split';

  /// Values that say what a Sale *is*, not how it was paid.
  ///
  /// `cancelled` and `non-fiscal` mark records that collected nothing at all,
  /// and `split` means "there are parts" without naming any of them. None is a
  /// tender, so none may ever become a payment line in the Cloud ledger.
  static const Set<String> nonTenderSentinels = <String>{
    methodCancelled,
    methodNonFiscal,
    methodSplit,
  };

  static bool isNonTenderSentinel(String? key) =>
      key != null && nonTenderSentinels.contains(key);

  static Map<String, double> extractBreakdown(Map<dynamic, dynamic> sale) {
    final breakdown = <String, double>{};
    final raw = sale['paymentBreakdown'];
    if (raw is Map) {
      raw.forEach((key, value) {
        final keyStr = key?.toString();
        final amount = _toDouble(value);
        if (keyStr != null && amount != null && amount > 0) {
          breakdown[keyStr] = double.parse(amount.toStringAsFixed(2));
        }
      });
      if (breakdown.isNotEmpty) {
        return breakdown;
      }
    }

    final method = sale['paymentMethod']?.toString();
    final total =
        _toDouble(sale['total']) ?? _toDouble(sale['totalAmount']) ?? 0.0;

    if (method != null && total > 0) {
      if (method == methodOther) {
        final label = sale['customPaymentLabel']?.toString();
        final key = (label != null && label.isNotEmpty)
            ? 'other:$label'
            : methodOther;
        breakdown[key] = double.parse(total.toStringAsFixed(2));
      } else {
        breakdown[method] = double.parse(total.toStringAsFixed(2));
      }
    }

    return breakdown;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String normalizeMethodKey(String rawKey) {
    if (rawKey.startsWith('other:')) {
      return methodOther;
    }
    if (rawKey == methodCardTbc || rawKey == methodCardBog) {
      return rawKey;
    }
    if (rawKey.startsWith('card-')) {
      return methodCardLegacy;
    }
    return rawKey;
  }

  static String formatPaymentDisplay(Map<dynamic, dynamic> sale) {
    final breakdown = extractBreakdown(sale);
    final method = sale['paymentMethod']?.toString();
    final bool isNonFiscal =
        sale['isFiscal'] == false || method == methodNonFiscal;
    if (isNonFiscal) {
      if (breakdown.isEmpty) {
        return 'Non-Fiscal';
      }
      final detail = breakdown.entries
          .map(
            (entry) =>
                '${methodLabel(entry.key)} ₾${entry.value.toStringAsFixed(2)}',
          )
          .join(' + ');
      return detail.isEmpty ? 'Non-Fiscal' : 'Non-Fiscal • $detail';
    }
    if (breakdown.isEmpty) {
      return 'Unknown';
    }
    return breakdown.entries
        .map(
          (entry) =>
              '${methodLabel(entry.key)} ₾${entry.value.toStringAsFixed(2)}',
        )
        .join(' + ');
  }

  static String methodLabel(String key) {
    if (key == methodCash) {
      return 'Cash';
    }
    if (key == methodCardLegacy) {
      return 'Card';
    }
    if (key == methodCardTbc) {
      return 'Card (TBC)';
    }
    if (key == methodCardBog) {
      return 'Card (BOG)';
    }
    if (key.startsWith('card-')) {
      final bank = key.split('-').last.toUpperCase();
      return 'Card ($bank)';
    }
    if (key.startsWith('other:')) {
      final label = key.substring(6).trim();
      return label.isEmpty ? 'Other' : 'Other ($label)';
    }
    if (key == methodOther) {
      return 'Other';
    }
    if (key == 'split') {
      return 'Split';
    }
    if (key == methodNonFiscal) {
      return 'Non-Fiscal';
    }
    if (key == methodAdvance) {
      return 'Advance';
    }
    return key[0].toUpperCase() + key.substring(1);
  }

  static String? extractOtherLabel(Map<String, double>? breakdown) {
    if (breakdown == null) return null;
    for (final key in breakdown.keys) {
      if (key.startsWith('other:')) {
        final label = key.substring(6).trim();
        if (label.isNotEmpty) {
          return label;
        }
      }
    }
    return null;
  }
}
