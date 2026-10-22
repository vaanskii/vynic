import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'print_identity_admission.dart';
import 'print_job.dart';

/// An installed Windows queue, not a claim that its hardware supports ESC/POS.
class WindowsPrinterQueue {
  const WindowsPrinterQueue({
    required this.name,
    required this.driver,
    required this.port,
  });

  final String name;
  final String driver;
  final String port;
}

class WindowsSpoolerException implements Exception {
  const WindowsSpoolerException({
    required this.stage,
    required this.writeAttempted,
    required this.message,
    this.windowsError,
  });

  final String stage;

  /// True once StartDocPrinter may have been called, even before WritePrinter.
  final bool writeAttempted;
  final String message;
  final int? windowsError;

  @override
  String toString() =>
      'Windows spooler $stage: $message'
      '${windowsError == null ? '' : ' (Windows error $windowsError)'}';

  factory WindowsSpoolerException.fromPlatform(PlatformException error) {
    final details = error.details;
    return WindowsSpoolerException(
      stage: details is Map && details['stage'] is String
          ? details['stage'] as String
          : 'unknown',
      writeAttempted: !(details is Map && details['writeAttempted'] == false),
      message: error.message ?? error.code,
      windowsError: details is Map && details['windowsError'] is int
          ? details['windowsError'] as int
          : null,
    );
  }
}

/// RAW ESC/POS submission to an independently qualified, installed Windows queue.
/// Other printer languages require a separate renderer/profile integration.
/// No driver installation, USB device access, retry, or paper confirmation.
class WindowsSpoolerTransport {
  WindowsSpoolerTransport({
    MethodChannel? channel,
    bool Function()? isWindows,
    this.responseTimeout = const Duration(seconds: 30),
  }) : _channel = channel ?? const MethodChannel('vynic/windows_spooler'),
       _isWindows = isWindows ?? (() => Platform.isWindows);

  // The durable job's visible JOB/reprint header accompanies its frozen payload.
  static const maxTransmissionBytes = PrintJob.maxPayloadBytes + 1024;
  static const maxQueueNameLength = 255;
  static const maxDescriptorLength = 1024;
  static const maxDocumentNameLength = 255;
  static const maxQueues = 1024;
  static const _preSubmissionStages = {
    'validate',
    'enumerate',
    'selectQueue',
    'openPrinter',
    'inspectPrinter',
    'dispatch',
  };
  static final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

  final MethodChannel _channel;
  final bool Function() _isWindows;
  final Duration responseTimeout;

  static bool _validText(String value, int max) =>
      value.trim().isNotEmpty &&
      value.length <= max &&
      !_controlCharacters.hasMatch(value);

  /// Read-only inventory. A failed inventory is surfaced, never an empty list.
  Future<List<WindowsPrinterQueue>> listQueues() async {
    if (!_isWindows()) {
      throw UnsupportedError('Windows printer queues require Windows');
    }
    dynamic response;
    try {
      response = await _channel
          .invokeMethod<dynamic>('listQueues')
          .timeout(responseTimeout);
    } on PlatformException catch (error) {
      throw WindowsSpoolerException.fromPlatform(error);
    }
    if (response is! List || response.length > maxQueues) {
      throw const FormatException('Invalid Windows printer inventory');
    }
    final queues = <WindowsPrinterQueue>[];
    final names = <String>{};
    for (final row in response) {
      if (row is! Map ||
          row['name'] is! String ||
          !_validText(row['name'] as String, maxQueueNameLength) ||
          row['driver'] is! String ||
          (row['driver'] as String).length > maxDescriptorLength ||
          _controlCharacters.hasMatch(row['driver'] as String) ||
          row['port'] is! String ||
          (row['port'] as String).length > maxDescriptorLength ||
          _controlCharacters.hasMatch(row['port'] as String) ||
          !names.add(row['name'] as String)) {
        throw const FormatException('Invalid Windows printer descriptor');
      }
      queues.add(
        WindowsPrinterQueue(
          name: row['name'] as String,
          driver: row['driver'] as String,
          port: row['port'] as String,
        ),
      );
    }
    return List<WindowsPrinterQueue>.unmodifiable(queues);
  }

  /// Freeze the bytes and expected queue identity before crossing the channel.
  /// A timeout cannot cancel a blocking spooler call, so it remains uncertain.
  /// Identity admission lasts until the original native future settles.
  Future<PrintTransmissionResult> submit({
    required String queueName,
    required String expectedDriverName,
    required String expectedPortName,
    required List<int> bytes,
    required String documentName,
    bool Function()? maySubmit,
  }) async {
    if (!_isWindows()) {
      return const PrintTransmissionResult(
        PrintTransmissionState.notSent,
        'Windows RAW printer submission requires Windows',
      );
    }
    if (!_validText(queueName, maxQueueNameLength) ||
        !_validText(expectedDriverName, maxDescriptorLength) ||
        !_validText(expectedPortName, maxDescriptorLength) ||
        !_validText(documentName, maxDocumentNameLength) ||
        bytes.isEmpty ||
        bytes.length > maxTransmissionBytes ||
        bytes.any((byte) => byte < 0 || byte > 255) ||
        responseTimeout <= Duration.zero) {
      return const PrintTransmissionResult(
        PrintTransmissionState.notSent,
        'Invalid Windows RAW printer configuration or payload; no submission attempted',
      );
    }
    final frozenBytes = Uint8List.fromList(bytes);
    final arguments = {
      'queueName': queueName,
      'expectedDriverName': expectedDriverName,
      'expectedPortName': expectedPortName,
      'documentName': documentName,
      'bytes': frozenBytes,
    };
    final Object admission;
    try {
      admission = PrintIdentityAdmission.beginSubmission(maySubmit: maySubmit);
    } catch (error) {
      return PrintTransmissionResult(
        PrintTransmissionState.notSent,
        'Printer ownership no longer permits this submission; no native call attempted. $error',
      );
    }
    try {
      final Future<dynamic> nativeCall;
      try {
        nativeCall = _channel.invokeMethod<dynamic>('submitRaw', arguments);
      } catch (_) {
        // A synchronous invocation failure has no future to settle the lease.
        PrintIdentityAdmission.finishSubmission(admission);
        rethrow;
      }
      // Both callbacks belong to the ORIGINAL call, so a Dart timeout cannot
      // release ownership while Winspool might still start or write a job.
      // The resulting future is observed by timeout, including late errors.
      final response = await nativeCall
          .then<dynamic>(
            (value) {
              PrintIdentityAdmission.finishSubmission(admission);
              return value;
            },
            onError: (Object error, StackTrace stackTrace) {
              PrintIdentityAdmission.finishSubmission(admission);
              Error.throwWithStackTrace(error, stackTrace);
            },
          )
          .timeout(responseTimeout);
      if (response is Map &&
          response['accepted'] == true &&
          response['jobId'] is int &&
          (response['jobId'] as int) > 0 &&
          response['bytesWritten'] == frozenBytes.length) {
        return const PrintTransmissionResult(
          PrintTransmissionState.sent,
          'Windows spooler accepted RAW bytes; physical paper output is not confirmed',
        );
      }
      return const PrintTransmissionResult(
        PrintTransmissionState.uncertain,
        'Windows spooler returned an incomplete submission result; check paper before a labeled reprint',
      );
    } on MissingPluginException {
      return const PrintTransmissionResult(
        PrintTransmissionState.notSent,
        'Windows RAW spooler adapter is unavailable; no submission attempted',
      );
    } on PlatformException catch (error) {
      final failure = WindowsSpoolerException.fromPlatform(error);
      final beforeSubmission =
          error.code == 'vynic_spooler_error' &&
          !failure.writeAttempted &&
          _preSubmissionStages.contains(failure.stage);
      return PrintTransmissionResult(
        beforeSubmission
            ? PrintTransmissionState.notSent
            : PrintTransmissionState.uncertain,
        beforeSubmission
            ? 'Windows submission failed before starting a document. $failure'
            : 'Windows submission may have begun; check paper before a labeled reprint. $failure',
      );
    } catch (error) {
      return PrintTransmissionResult(
        PrintTransmissionState.uncertain,
        'Windows submission outcome is unknown; check paper before a labeled reprint. $error',
      );
    }
  }
}
