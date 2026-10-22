import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../edge/operational_proof/domain.dart';
import 'print_job.dart';
import 'printer_destination.dart';

/// Original-only migration guard shared by the fixed-host and cluster envelope.
/// Requeued work and conditional Order confirmation need an explicit adapter.
void requirePristineOriginalPrintTicket(PrintJob job) {
  proofRequire(
    job.protocolVersion == PrintJob.routedProtocol &&
        job.state == PrintJobState.queued &&
        job.attempts.length == 1 &&
        job.copyOf == null &&
        job.requiresConfirmedOrderUuid == null &&
        job.capabilityProfile.hasImplementedRenderer,
    'pristine original rendered ticket',
  );
  final first = proofMap(job.latest, {'id', 'state', 'queuedAt'});
  proofRequire(job.audit.length == 1, 'pristine original print history');
  final queued = proofMap(job.audit.single, {'action', 'at', 'attemptId'});
  proofRequire(
    first['id'] == job.id &&
        first['queuedAt'] == job.createdAt &&
        queued['action'] == 'queued' &&
        queued['at'] == job.createdAt &&
        queued['attemptId'] == job.id,
    'pristine original print attempt',
  );
}

/// Pinned registry data received from an authenticated coordinator. Constructing
/// this value does not enroll a device, authorize printing or transfer ownership.
class SharedPrintBinding {
  SharedPrintBinding({
    required this.venueId,
    required this.installationId,
    required this.originInstallationId,
    required this.deviceId,
    required this.physicalPrinterId,
    required this.aliasId,
    required this.workerHostId,
    required this.authorityEpoch,
    required this.configRevision,
    required this.bindingRevision,
    required this.registryRevision,
    required this.routeId,
    required this.routeRevision,
    required this.destination,
  }) {
    for (final value in [
      venueId,
      installationId,
      originInstallationId,
      deviceId,
      physicalPrinterId,
      aliasId,
      workerHostId,
    ]) {
      proofRequire(proofUuid(value), 'shared printer registry identity');
    }
    for (final value in [
      authorityEpoch,
      configRevision,
      bindingRevision,
      registryRevision,
      routeRevision,
    ]) {
      proofInteger(value, positive: true);
    }
    proofRequire(
      RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(routeId) &&
          routeRevision <= 0x7fffffff,
      'pinned local route mapping',
    );
    if (destination.kind == PrinterTransportKind.windowsSpooler) {
      proofRequire(
        destination.ownerDeviceId == deviceId,
        'shared spooler owner Device',
      );
    }
  }

  final String venueId, installationId, originInstallationId, deviceId;
  final String physicalPrinterId, aliasId, workerHostId;
  final int authorityEpoch, configRevision, bindingRevision, registryRevision;
  final String routeId;
  final int routeRevision;
  final PrinterDestination destination;
}

/// Pure migration seam for the strict Go queue envelope. It freezes an already
/// rendered, original v2 ticket; it creates no Hive row, clock, UUID or transport.
/// All caller-supplied IDs survive pending-frame persistence and relayed retries.
/// Copies require separate, explicitly authorized attempts and are not inferred.
class FrozenSharedPrintEffect {
  FrozenSharedPrintEffect._(this.effectId, List<int> payload)
    : payload = List<int>.unmodifiable(payload);

  final String effectId;
  final List<int> payload;

  factory FrozenSharedPrintEffect.fromQueuedJob({
    required PrintJob job,
    required SharedPrintBinding binding,
    required String jobId,
    required String effectId,
    required String requestId,
    required String terminalId,
    required String attemptId,
    required String beepAttemptId,
  }) {
    for (final value in [
      jobId,
      effectId,
      requestId,
      terminalId,
      attemptId,
      beepAttemptId,
    ]) {
      proofRequire(proofUuid(value), 'shared print attempt identity');
    }
    proofRequire(
      job.protocolVersion == PrintJob.routedProtocol &&
          job.state == PrintJobState.queued &&
          job.attempts.length == 1 &&
          job.copyOf == null &&
          job.requiresConfirmedOrderUuid == null &&
          job.printerId == binding.routeId &&
          job.routeRevision == binding.routeRevision &&
          job.venueId == binding.venueId &&
          job.destination.identity == binding.destination.identity,
      'original queued ticket and frozen registry binding',
    );
    requirePristineOriginalPrintTicket(job);
    proofRequire(
      job.capabilityProfile.hasImplementedRenderer,
      'shared renderer',
    );
    final primary = job.transmissionBytes;
    proofRequire(
      primary.isNotEmpty && primary.length <= PrintJob.maxPayloadBytes + 1024,
      'shared primary transmission bounds',
    );
    final destination = job.destination;
    final body = <String, dynamic>{
      'version': 1,
      'jobId': jobId,
      'effectId': effectId,
      'requestId': requestId,
      'terminalId': terminalId,
      'venueId': binding.venueId,
      'installationId': binding.installationId,
      'originInstallationId': binding.originInstallationId,
      'authorityEpoch': binding.authorityEpoch,
      'deviceId': binding.deviceId,
      'physicalPrinterId': binding.physicalPrinterId,
      'aliasId': binding.aliasId,
      'routeRevision': job.routeRevision,
      'configRevision': binding.configRevision,
      'bindingRevision': binding.bindingRevision,
      'registryRevision': binding.registryRevision,
      'attemptId': attemptId,
      'beepAttemptId': beepAttemptId,
      'destination': {
        'physicalPrinterId': binding.physicalPrinterId,
        'workerHostId': binding.workerHostId,
        'transport': destination.kind.name,
        'host': destination.host ?? '',
        'port': destination.port ?? 0,
        'queueName': destination.queueName ?? '',
        'expectedDriverName': destination.driverName ?? '',
        'expectedPortName': destination.portName ?? '',
        'documentName': 'Vynic $jobId',
      },
      'capabilityProfile': job.capabilityProfile.toMap(),
      'primaryBytes': base64Encode(primary),
      'primarySha256': sha256.convert(primary).toString(),
    };
    return FrozenSharedPrintEffect._(effectId, utf8.encode(jsonEncode(body)));
  }

  /// Explicit isolated-proof adapter. Historical opaque PRINT effects stay
  /// inert; callers must negotiate versioned queue admission separately.
  ProofEffect toProofEffect() =>
      ProofEffect(id: effectId, kind: ProofEffectKind.print, payload: payload);
}
