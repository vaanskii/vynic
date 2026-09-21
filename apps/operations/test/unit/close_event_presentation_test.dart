import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/audit/close_event_presentation.dart';

/// The close row is read from its structured details. The free-text note is
/// what an event written before those details existed falls back to, and it
/// is never parsed when the details are there.
void main() {
  AuditEvent close({
    AuditEventType type = AuditEventType.close,
    Map<String, dynamic>? details,
    String? note,
  }) => AuditEvent(
    type: type,
    itemName: 'ORDER',
    previousQty: 0,
    newQty: 0,
    waiterId: 'n',
    waiterName: 'n',
    timestamp: DateTime(2026, 9, 4, 20),
    note: note,
    details: details,
  );

  Map<String, dynamic> fiscal({
    required String method,
    required Map<String, double> breakdown,
    double gross = 100,
    double advance = 0,
    double? collected,
  }) => {
    'isFiscal': true,
    'paymentMethod': method,
    'paymentBreakdown': breakdown,
    'grossAmount': gross,
    'advanceApplied': advance,
    'collectedNow': collected ?? (gross - advance),
    'closureId': 'c-1',
  };

  test('cash', () {
    final event = close(
      details: fiscal(method: 'cash', breakdown: {'cash': 100}),
      note: 'Order closed with cash',
    );
    expect(CloseEventPresentation.paymentSummary(event), 'Cash');
    expect(CloseEventPresentation.providerOf(event), isNull);
    expect(CloseEventPresentation.displayNote(event), isNull);
  });

  test('card — TBC', () {
    final event = close(
      details: fiscal(method: 'card-tbc', breakdown: {'card-tbc': 100}),
    );
    expect(CloseEventPresentation.paymentSummary(event), 'Card — TBC');
    expect(CloseEventPresentation.providerOf(event), 'TBC');
  });

  test('card — BOG', () {
    final event = close(
      details: fiscal(method: 'card-bog', breakdown: {'card-bog': 100}),
    );
    expect(CloseEventPresentation.paymentSummary(event), 'Card — BOG');
    expect(CloseEventPresentation.providerOf(event), 'BOG');
  });

  test('split lists every tender with its amount', () {
    final event = close(
      details: fiscal(method: 'split', breakdown: {'cash': 40, 'card-tbc': 60}),
    );
    expect(
      CloseEventPresentation.paymentSummary(event),
      'Cash 40.00 + TBC 60.00',
    );
    expect(CloseEventPresentation.providerOf(event), 'TBC');
  });

  test('advance with card shows both parts distinctly', () {
    final event = close(
      details: fiscal(
        method: 'card-tbc',
        breakdown: {'advance': 50, 'card-tbc': 130},
        gross: 180,
        advance: 50,
        collected: 130,
      ),
    );
    expect(
      CloseEventPresentation.paymentSummary(event),
      'Advance 50.00 + TBC 130.00',
    );
    final chips = CloseEventPresentation.chips(event);
    expect(chips.map((c) => c.label), [
      'Payment',
      'Provider',
      'Gross',
      'Advance',
      'Collected',
    ]);
    expect(chips.firstWhere((c) => c.label == 'Gross').value, '180.00');
    expect(chips.firstWhere((c) => c.label == 'Advance').value, '50.00');
    expect(chips.firstWhere((c) => c.label == 'Collected').value, '130.00');
  });

  test('advance not listed in the breakdown is still shown', () {
    // Older close details carried advanceApplied without an `advance` key
    // in the breakdown; the advance still belongs in the summary.
    final event = close(
      details: fiscal(
        method: 'cash',
        breakdown: {'cash': 130},
        gross: 180,
        advance: 50,
        collected: 130,
      ),
    );
    expect(
      CloseEventPresentation.paymentSummary(event),
      'Cash 130.00 + Advance 50.00',
    );
  });

  test('advance with split', () {
    final event = close(
      details: fiscal(
        method: 'split',
        breakdown: {'advance': 50, 'cash': 30, 'card-bog': 100},
        gross: 180,
        advance: 50,
        collected: 130,
      ),
    );
    expect(
      CloseEventPresentation.paymentSummary(event),
      'Advance 50.00 + Cash 30.00 + BOG 100.00',
    );
    expect(CloseEventPresentation.providerOf(event), 'BOG');
  });

  test('internal close is non-fiscal with nothing collected', () {
    final event = close(
      type: AuditEventType.internalClose,
      details: {
        'isFiscal': false,
        'paymentMethod': 'non-fiscal',
        'paymentBreakdown': <String, double>{},
        'grossAmount': 100.0,
        'advanceApplied': 0.0,
        'collectedNow': 0.0,
      },
      note: 'Order closed (non-fiscal)',
    );
    expect(CloseEventPresentation.paymentSummary(event), 'Non-fiscal');
    expect(CloseEventPresentation.providerOf(event), isNull);
    expect(
      CloseEventPresentation.chips(
        event,
      ).firstWhere((c) => c.label == 'Collected').value,
      '0.00',
    );
    expect(CloseEventPresentation.displayNote(event), isNull);
  });

  test('a historical close without details falls back to its note', () {
    final event = close(note: 'Order closed with card-tbc');
    expect(CloseEventPresentation.hasStructuredPayment(event), isFalse);
    expect(CloseEventPresentation.paymentSummary(event), isNull);
    expect(CloseEventPresentation.chips(event), isEmpty);
    expect(
      CloseEventPresentation.displayNote(event),
      'Order closed with card-tbc',
    );
    // The provider is not guessed from the note either.
    expect(CloseEventPresentation.providerOf(event), isNull);
  });

  test('details that carry no payment keys are not structured payment', () {
    final event = close(
      details: {'orderId': 1, 'closureId': 'c-1'},
      note: 'Order closed with cash',
    );
    expect(CloseEventPresentation.hasStructuredPayment(event), isFalse);
    expect(CloseEventPresentation.displayNote(event), 'Order closed with cash');
  });

  test('non-close events keep their note', () {
    final event = AuditEvent(
      type: AuditEventType.cancelTable,
      itemName: 'ORDER',
      previousQty: 2,
      newQty: 0,
      waiterId: 'n',
      waiterName: 'n',
      timestamp: DateTime(2026, 9, 4, 20),
      note: 'Guest left',
      details: const {'paymentMethod': 'cancelled'},
    );
    expect(CloseEventPresentation.hasStructuredPayment(event), isFalse);
    expect(CloseEventPresentation.displayNote(event), 'Guest left');
  });

  test('close details survive a wire round trip', () {
    final original = close(
      details: fiscal(method: 'split', breakdown: {'cash': 40, 'card-tbc': 60}),
    );
    final parsed = AuditEvent.fromMap(original.toMap());
    expect(
      CloseEventPresentation.paymentSummary(parsed),
      'Cash 40.00 + TBC 60.00',
    );
  });
}
