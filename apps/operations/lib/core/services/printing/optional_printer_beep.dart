import 'print_job.dart';
import 'printer_capability_profile.dart';

enum PrinterBeepState { skipped, notSent, submitted, uncertain, failed }

/// Independent optional outcome. `submitted` means the transport accepted the
/// beep bytes, not that a sound occurred or that the primary paper printed.
class PrinterBeepResult {
  const PrinterBeepResult({
    required this.state,
    required this.attemptId,
    required this.detail,
  });

  final PrinterBeepState state;
  final String attemptId;
  final String detail;

  Map<String, dynamic> toMap() => {
    'state': state.name,
    'attemptId': attemptId,
    'detail': detail,
  };
}

/// Runs after primary print/cut delivery has been durably settled. This helper
/// never stores or changes a PrintJob, primary result, payload, or reprint.
/// The caller owns destination/tenant admission and durable reservation/audit.
class OptionalPrinterBeep {
  const OptionalPrinterBeep._();

  /// Epson ESC ( A fn=97, registered-pattern variant: Pattern A once.
  /// https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/esc_lparen_ca_fn97.html
  /// The explicit profile capability must establish this exact command and
  /// buzzer compatibility; it is not enabled for arbitrary ESC/POS printers.
  static const _epsonPatternOnce = [
    0x1b,
    0x28,
    0x41,
    0x03,
    0x00,
    0x61,
    0x01,
    0x01,
  ];

  /// [reserve] returns true only for a NEW reservation flushed durably before
  /// returning. It must atomically return false for an already reserved attempt,
  /// including after a crash. No state here authorizes replay or retries.
  /// [send] must enforce the frozen destination and current write admission.
  /// A timeout does not cancel either callback: the provider retains any native
  /// submission/admission guard until its original future actually settles.
  static Future<PrinterBeepResult> submit({
    required String attemptId,
    required PrinterCapabilityProfile profile,
    required Future<bool> Function(String attemptId) reserve,
    required Future<PrintTransmissionResult> Function(List<int> command) send,
    Duration operationTimeout = const Duration(seconds: 3),
  }) async {
    PrinterBeepResult result(PrinterBeepState state, String detail) =>
        PrinterBeepResult(state: state, attemptId: attemptId, detail: detail);
    if (!profile.hasImplementedRenderer) {
      return result(
        PrinterBeepState.skipped,
        'Beep skipped: driver-rendered command language is not implemented',
      );
    }
    if (!profile.beep.enabled) {
      return result(PrinterBeepState.skipped, 'Beep skipped: disabled');
    }
    if (profile.beep.capability != PrinterBeepCapability.epsonEscA97Pattern) {
      return result(
        PrinterBeepState.skipped,
        'Beep skipped: ${profile.beep.capability.name} capability',
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(attemptId)) {
      return result(
        PrinterBeepState.failed,
        'Beep refused: invalid attempt ID',
      );
    }
    if (operationTimeout <= Duration.zero) {
      return result(PrinterBeepState.failed, 'Beep refused: invalid timeout');
    }
    try {
      if (!await reserve(attemptId).timeout(operationTimeout)) {
        return result(
          PrinterBeepState.notSent,
          'Beep not sent: reservation denied or already spent; no replay',
        );
      }
    } catch (error) {
      return result(
        PrinterBeepState.failed,
        'Beep reservation failed before send: $error',
      );
    }
    try {
      final submitted = await send(
        List<int>.unmodifiable(_epsonPatternOnce),
      ).timeout(operationTimeout);
      return result(switch (submitted.state) {
        PrintTransmissionState.sent => PrinterBeepState.submitted,
        PrintTransmissionState.notSent => PrinterBeepState.notSent,
        PrintTransmissionState.uncertain => PrinterBeepState.uncertain,
      }, submitted.detail);
    } catch (error) {
      // An injected transport can throw after writing. Keep the reservation
      // spent and surface uncertainty separately without rejecting the print.
      return result(
        PrinterBeepState.uncertain,
        'Beep outcome uncertain after reservation: $error; no replay',
      );
    }
  }
}
