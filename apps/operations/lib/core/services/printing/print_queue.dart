import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../database/database_core.dart';
import 'dart:developer' as developer;
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'print_job.dart';
import 'printer_transport.dart';
import 'printer_destination.dart';
import 'windows_spooler_transport.dart';
import 'optional_printer_beep.dart';
export 'print_job.dart' show PrintQueueTarget;

/// Hive is the queue. The only memory state is a worker guard and optional
/// foreground notifications; losing either cannot lose/repeat a durable job.
/// One sender serializes both destinations, including a shared physical IP.
class PrintQueue {
  PrintQueue._();
  static bool _stopped = true;
  static Future<void>? _running;
  static final _callbacks = <String, List<void Function(bool)>>{};
  @visibleForTesting
  static WindowsSpoolerTransport? spoolerOverride;

  static int get pendingCount => PrintJobRepository.all()
      .where((j) => j.ready || j.state == PrintJobState.sending)
      .length;
  static int pendingCountFor(PrintQueueTarget target) =>
      PrintJobRepository.all()
          .where(
            (j) =>
                j.target == target &&
                (j.ready || j.state == PrintJobState.sending),
          )
          .length;

  static Future<PrintJob> enqueue(
    PrintJob job, {
    void Function(bool)? onComplete,
  }) async {
    final stored = await PrintJobRepository.enqueue(job);
    if (onComplete != null) {
      if (stored.ready || stored.state == PrintJobState.sending) {
        (_callbacks[stored.attemptId] ??= []).add(onComplete);
      } else {
        _notify(
          onComplete,
          stored.state == PrintJobState.sent ||
              stored.state == PrintJobState.confirmed,
        );
      }
    }
    wake();
    return stored;
  }

  static void start() {
    _stopped = false;
    wake();
  }

  static void stop() {
    _stopped = true;
  }

  static Future<void> get idle => _running ?? Future.value();

  static void wake() => LocalDataAdmission.afterMutation(() {
    if (_stopped || _running != null || PrintJobRepository.failure != null)
      return;
    _running = _run()
        .catchError((Object error, StackTrace stack) {
          for (final id in _callbacks.keys.toList()) _complete(id, false);
          PrintJobRepository.failure = 'Print dispatch stopped: $error';
          PrintJobRepository.changes.value++;
          developer.log(
            'Print dispatch stopped',
            error: error,
            stackTrace: stack,
          );
        })
        .whenComplete(() {
          _running = null;
          if (!_stopped &&
              PrintJobRepository.failure == null &&
              pendingCount > 0)
            wake();
        });
  });

  static Future<void> _run() async {
    while (!_stopped && PrintJobRepository.failure == null) {
      final jobs = PrintJobRepository.all();
      for (final attempt in _callbacks.keys.toList()) {
        final current = jobs.where((j) => j.attemptId == attempt);
        if (current.isEmpty)
          _complete(attempt, false);
        else if (!current.single.ready &&
            current.single.state != PrintJobState.sending)
          _complete(
            attempt,
            current.single.state == PrintJobState.sent ||
                current.single.state == PrintJobState.confirmed,
          );
      }
      final ready = jobs.where((j) => j.ready);
      if (ready.isEmpty) return;
      final id = ready.first.id;
      await UpdateReadiness.track('Print transmission', () async {
        // Read, decide and flush under the same owner as confirmation/restore.
        // A worker already running must not act on a provisional queued row.
        final job = await LocalDataAdmission.mutate<PrintJob?>(() async {
          final current = PrintJobRepository.read(id);
          if (current == null || !current.ready || _stopped) return null;
          final foreign = !_sameOwner(current);
          if (foreign ||
              !_confirmedOrder(current) ||
              !current.capabilityProfile.hasImplementedRenderer) {
            await PrintJobRepository.transition(
              id,
              current.attemptId,
              current.state,
              PrintJobState.uncertain,
              detail: foreign
                  ? 'Venue binding changed; automatic delivery held'
                  : !current.capabilityProfile.hasImplementedRenderer
                  ? 'Printer command language has no implemented renderer; delivery held'
                  : 'Order confirmation did not commit; initial ticket held for operator review',
            );
            return null;
          }
          await PrintJobRepository.transition(
            id,
            current.attemptId,
            current.state,
            PrintJobState.sending,
          );
          return current;
        });
        if (job == null) {
          final held = PrintJobRepository.read(id);
          if (held != null &&
              !held.ready &&
              held.state != PrintJobState.sending)
            _complete(held.attemptId, false);
          return;
        }
        // No path reaches Socket.add until `sending` has been flushed.
        final result = await _transmit(job, job.transmissionBytes);
        final state = switch (result.state) {
          PrintTransmissionState.sent => PrintJobState.sent,
          PrintTransmissionState.notSent => PrintJobState.failed,
          PrintTransmissionState.uncertain => PrintJobState.uncertain,
        };
        await PrintJobRepository.transition(
          id,
          job.attemptId,
          PrintJobState.sending,
          state,
          detail: result.detail,
        );
        developer.log(
          'Job ${job.id}, attempt ${job.attemptId}: ${state.name}. ${result.detail}',
          name: 'vynic.print',
        );
        _complete(job.attemptId, result.sent);
        if (result.sent && job.protocolVersion == PrintJob.routedProtocol) {
          await _optionalBeep(job);
        }
      });
    }
  }

  static Future<PrintTransmissionResult> _transmit(
    PrintJob job,
    List<int> bytes, {
    bool optionalSignal = false,
  }) async {
    final destination = job.destination;
    return !_sameOwner(job) || !_confirmedOrder(job)
        ? const PrintTransmissionResult(
            PrintTransmissionState.uncertain,
            'Printer owner or confirmed Order changed; delivery held',
          )
        : destination.kind == PrinterTransportKind.windowsSpooler
        ? await (spoolerOverride ?? WindowsSpoolerTransport()).submit(
            queueName: destination.queueName!,
            expectedDriverName: destination.driverName!,
            expectedPortName: destination.portName!,
            bytes: bytes,
            documentName: optionalSignal
                ? 'Vynic signal ${job.attemptId}'
                : 'Vynic JOB ${job.id}',
            maySubmit: () => _sameOwner(job) && _confirmedOrder(job),
          )
        : await PrinterTransport.sendToPrinter(
            printerIp: job.host,
            port: job.port,
            bytes: bytes,
            printerName: switch (job.target) {
              PrintQueueTarget.kitchen => 'Kitchen',
              PrintQueueTarget.receipt => 'Receipt',
              PrintQueueTarget.bar => 'Bar',
              PrintQueueTarget.additional => job.label,
            },
            usePersistentConnection: false,
            mayWrite: () => _sameOwner(job) && _confirmedOrder(job),
          );
  }

  static Future<void> _optionalBeep(PrintJob job) async {
    try {
      final outcome = await OptionalPrinterBeep.submit(
        attemptId: job.attemptId,
        profile: job.capabilityProfile,
        reserve: (attemptId) =>
            PrintJobRepository.reserveBeep(job.id, attemptId),
        send: (bytes) => _transmit(job, bytes, optionalSignal: true),
      );
      if (outcome.state != PrinterBeepState.skipped &&
          (PrintJobRepository.read(job.id)?.attempts.any(
                (attempt) =>
                    attempt['id'] == job.attemptId &&
                    attempt['beep']?['state'] == 'reserved',
              ) ??
              false)) {
        await PrintJobRepository.settleBeep(job.id, outcome);
      }
    } catch (error, stack) {
      // Primary delivery and its foreground callback already settled. Leave any
      // spent reservation intact, and never turn a signal failure into a copy.
      PrintJobRepository.optionalSignalFailure =
          'Optional printer signal failed: $error';
      PrintJobRepository.changes.value++;
      developer.log(
        'Optional printer signal failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  static bool _sameOwner(PrintJob job) =>
      job.venueId == EdgeDeviceCredentialStore.venueId &&
      (job.destination.kind != PrinterTransportKind.windowsSpooler ||
          job.destination.ownerDeviceId == EdgeDeviceCredentialStore.deviceId);

  static bool _confirmedOrder(PrintJob job) {
    final uuid = job.requiresConfirmedOrderUuid;
    return job.attempts.length > 1 ||
        job.copyOf != null ||
        uuid == null ||
        (DatabaseCore.orderBox?.values.any(
              (o) => o.orderUuid == uuid && o.status == 'confirmed',
            ) ??
            false);
  }

  static void _complete(String attemptId, bool sent) {
    final callbacks = _callbacks.remove(attemptId);
    if (callbacks != null)
      for (final callback in callbacks) _notify(callback, sent);
  }

  static void _notify(void Function(bool) callback, bool sent) {
    try {
      callback(sent);
    } catch (error, stack) {
      developer.log(
        'Print notification failed',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
