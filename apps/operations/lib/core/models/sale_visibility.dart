/// Presentation only. Never use this to rewrite history or financial totals.
abstract final class SaleVisibility {
  static bool nonFiscalPayment(String key) => const {
    'non-fiscal',
    'nonfiscal',
    'non_fiscal',
    'internal',
  }.contains(key.trim().toLowerCase());
  static bool isInternal(Map<String, dynamic> sale) {
    if (sale['isCancelled'] == true ||
        sale['isAdvance'] == true ||
        sale['isAdvanceReceipt'] == true ||
        sale['recordType'] == 'ADVANCE_RECEIPT')
      return false;
    final kind =
        (sale['classification'] ?? sale['kind'] ?? sale['recordType'] ?? '')
            .toString()
            .toUpperCase();
    if (const {
      'ADVANCE',
      'ADVANCE_RECEIPT',
      'CANCELLED',
      'CANCELLATION',
    }.contains(kind))
      return false;
    if (kind == 'INTERNAL' || sale['isFiscal'] == false) return true;
    final payments = sale['paymentBreakdown'];
    return payments is Map &&
        payments.keys.any((key) => nonFiscalPayment(key.toString()));
  }

  static bool visible(
    Map<String, dynamic> sale, {
    required bool nonFiscalEnabled,
  }) => nonFiscalEnabled || !isInternal(sale);
}
