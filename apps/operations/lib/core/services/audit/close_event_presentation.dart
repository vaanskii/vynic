import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/utils/payment_utils.dart';

/// One displayable fact about a close, e.g. `Payment` → `Cash 40 + TBC 60`.
typedef CloseEventChip = ({String label, String value});

/// Renders a closure event's payment semantics from its structured details.
///
/// The `note` on a `CLOSE` event ("Order closed with card-tbc") predates the
/// structured details and stays for readability, but it is not the source of
/// truth: everything shown here is read from `details.paymentMethod`,
/// `paymentBreakdown`, `advanceApplied`, `collectedNow` and `grossAmount`.
/// An event written before those details existed has none, and for it the
/// caller falls back to the note. Historical rows are never rewritten.
abstract final class CloseEventPresentation {
  static bool isCloseEvent(AuditEvent event) =>
      event.type == AuditEventType.close ||
      event.type == AuditEventType.internalClose;

  /// Whether the event carries structured payment details.
  static bool hasStructuredPayment(AuditEvent event) {
    if (!isCloseEvent(event)) return false;
    final details = event.details;
    if (details == null) return false;
    return details['paymentMethod'] != null ||
        details['paymentBreakdown'] is Map ||
        details['isFiscal'] != null;
  }

  /// `TBC` / `BOG` derived from the durable payment method or breakdown;
  /// null when no card provider is involved. Nothing is persisted.
  static String? providerOf(AuditEvent event) {
    final details = event.details;
    if (details == null) return null;
    final providers = <String>{};
    final method = details['paymentMethod']?.toString();
    final fromMethod = _providerFromKey(method);
    if (fromMethod != null) providers.add(fromMethod);
    final breakdown = _breakdown(details);
    for (final key in breakdown.keys) {
      final provider = _providerFromKey(key);
      if (provider != null) providers.add(provider);
    }
    if (providers.isEmpty) return null;
    return (providers.toList()..sort()).join(' + ');
  }

  /// `Cash`, `Card — TBC`, `Cash 40.00 + TBC 60.00`, `Advance 50.00 + TBC
  /// 130.00`, `Non-fiscal`. Null when there are no structured details.
  static String? paymentSummary(AuditEvent event) {
    if (!hasStructuredPayment(event)) return null;
    final details = event.details!;
    final method = details['paymentMethod']?.toString() ?? '';
    final isFiscal =
        details['isFiscal'] != false && method != PaymentUtils.methodNonFiscal;
    if (!isFiscal) return 'Non-fiscal';

    final breakdown = _breakdown(details);
    final advance = _amount(details['advanceApplied']);
    if (advance > 0 && !breakdown.containsKey(PaymentUtils.methodAdvance)) {
      breakdown[PaymentUtils.methodAdvance] = advance;
    }
    final parts = breakdown.entries.where((e) => e.value > 0).toList();

    if (parts.length > 1 || method == 'split') {
      if (parts.isEmpty) return 'Split';
      return parts
          .map((e) => '${_shortLabel(e.key, details)} ${_fmt(e.value)}')
          .join(' + ');
    }
    return _methodLabel(method, details);
  }

  /// Money facts worth a chip: payment, provider, gross, advance, collected.
  static List<CloseEventChip> chips(AuditEvent event) {
    if (!hasStructuredPayment(event)) return const [];
    final details = event.details!;
    final chips = <CloseEventChip>[];
    final summary = paymentSummary(event);
    if (summary != null) chips.add((label: 'Payment', value: summary));
    final provider = providerOf(event);
    if (provider != null) chips.add((label: 'Provider', value: provider));
    final gross = details['grossAmount'];
    if (gross != null) chips.add((label: 'Gross', value: _fmt(_amount(gross))));
    final advance = _amount(details['advanceApplied']);
    if (advance > 0) chips.add((label: 'Advance', value: _fmt(advance)));
    final collected = details['collectedNow'];
    if (collected != null) {
      chips.add((label: 'Collected', value: _fmt(_amount(collected))));
    }
    return chips;
  }

  /// What to show as the event's free text: nothing when structured payment
  /// details already say it, the historical note otherwise.
  static String? displayNote(AuditEvent event) {
    if (hasStructuredPayment(event)) return null;
    final note = event.note?.trim();
    return (note == null || note.isEmpty) ? null : note;
  }

  static Map<String, double> _breakdown(Map<String, dynamic> details) {
    final raw = details['paymentBreakdown'];
    final result = <String, double>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final amount = _amount(value);
        if (key != null && amount > 0) result[key.toString()] = amount;
      });
    }
    return result;
  }

  static String? _providerFromKey(String? key) {
    if (key == null) return null;
    if (key == PaymentUtils.methodCardTbc) return 'TBC';
    if (key == PaymentUtils.methodCardBog) return 'BOG';
    if (key.startsWith('card-')) return key.split('-').last.toUpperCase();
    return null;
  }

  static String _methodLabel(String method, Map<String, dynamic> details) {
    if (method == PaymentUtils.methodCash) return 'Cash';
    if (method == PaymentUtils.methodCardLegacy) return 'Card';
    final provider = _providerFromKey(method);
    if (provider != null) return 'Card — $provider';
    if (method == PaymentUtils.methodOther || method.startsWith('other')) {
      final label = details['customPaymentLabel']?.toString().trim();
      return (label == null || label.isEmpty) ? 'Other' : 'Other — $label';
    }
    if (method.isEmpty) return 'Unknown';
    return PaymentUtils.methodLabel(method);
  }

  static String _shortLabel(String key, Map<String, dynamic> details) {
    if (key == PaymentUtils.methodCash) return 'Cash';
    if (key == PaymentUtils.methodAdvance) return 'Advance';
    if (key == PaymentUtils.methodCardLegacy) return 'Card';
    final provider = _providerFromKey(key);
    if (provider != null) return provider;
    if (key.startsWith('other:')) {
      final label = key.substring(6).trim();
      return label.isEmpty ? 'Other' : label;
    }
    if (key == PaymentUtils.methodOther) {
      final label = details['customPaymentLabel']?.toString().trim();
      return (label == null || label.isEmpty) ? 'Other' : label;
    }
    return PaymentUtils.methodLabel(key);
  }

  static double _amount(Object? raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  static String _fmt(double value) => value.toStringAsFixed(2);
}
