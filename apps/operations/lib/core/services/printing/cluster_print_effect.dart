import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../edge/operational_proof/domain.dart';
import 'print_job.dart';
import 'printer_capability_profile.dart';
import 'printer_destination.dart';
import 'shared_print_effect.dart';

enum PrinterScope { local, venueShared }

/// A retained configuration receipt from the coordinator. Its digest is checked
/// here for detached freezing; only the server's committed registry establishes
/// authority. IP address, selected leader and clock cannot transfer ownership.
class RetainedClusterPrinterConfig {
  RetainedClusterPrinterConfig._(
    this._body,
    this.raw,
    this.sha256Digest,
    this.sourceRouteId,
    this.destination,
    this.profile,
  );

  final Map<String, dynamic> _body;
  final List<int> raw;
  final String sha256Digest, sourceRouteId;
  final PrinterDestination destination;
  final PrinterCapabilityProfile profile;
  PrinterScope get scope =>
      _body['scope'] == 'LOCAL' ? PrinterScope.local : PrinterScope.venueShared;

  factory RetainedClusterPrinterConfig.decode({
    required List<int> raw,
    required String expectedSha256,
    required String sourceRouteId,
  }) {
    final frozen = proofBytes(raw, 65536);
    proofRequire(
      sha256.convert(frozen).toString() == expectedSha256 &&
          RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(sourceRouteId),
      'retained printer configuration digest and local mapping',
    );
    final body = proofMap(jsonDecode(utf8.decode(frozen)), {
      'version',
      'scope',
      'clusterId',
      'venueId',
      'physicalPrinterId',
      'routeId',
      'role',
      'routeRevision',
      'configRevision',
      'ownership',
      'destination',
      'capabilityProfile',
    });
    proofRequire(body['version'] == 1, 'retained printer config version');
    proofRequire(
      ['LOCAL', 'VENUE_SHARED'].contains(body['scope']),
      'explicit printer scope',
    );
    for (final key in [
      'clusterId',
      'venueId',
      'physicalPrinterId',
      'routeId',
    ]) {
      proofRequire(body[key] is String && proofUuid(body[key]), 'config UUID');
    }
    for (final key in ['routeRevision', 'configRevision']) {
      proofRequire(body[key] is int, 'config revision type');
      proofInteger(body[key], positive: true);
    }
    proofRequire(
      PrintQueueTarget.values.any((v) => v.name == body['role']),
      'printer role',
    );
    final destination = PrinterDestination.decode(body['destination']);
    final ownership = proofMap(body['ownership'], {
      'generation',
      'kind',
      'ownerId',
    });
    proofRequire(ownership['generation'] is int, 'ownership generation type');
    proofInteger(ownership['generation'], positive: true);
    proofRequire(
      ownership['ownerId'] is String && proofUuid(ownership['ownerId']),
      'ownership identity',
    );
    if (ownership['kind'] == 'cluster') {
      proofRequire(
        body['scope'] == 'VENUE_SHARED' &&
            ownership['ownerId'] == body['clusterId'] &&
            destination.kind == PrinterTransportKind.tcp,
        'cluster-owned destination',
      );
    } else {
      proofRequire(
        ownership['kind'] == 'device',
        'explicit fixed Device owner',
      );
      if (destination.kind == PrinterTransportKind.windowsSpooler) {
        proofRequire(
          ownership['ownerId'] == destination.ownerDeviceId,
          'fixed spooler Device',
        );
      } else {
        proofRequire(body['scope'] == 'LOCAL', 'local TCP Device owner');
      }
    }
    final profile = PrinterCapabilityProfile.decode(body['capabilityProfile']);
    proofRequire(
      profile.hasImplementedRenderer,
      'cluster implemented renderer',
    );
    return RetainedClusterPrinterConfig._(
      Map<String, dynamic>.unmodifiable(body),
      frozen,
      expectedSha256,
      sourceRouteId,
      destination,
      profile,
    );
  }
}

/// Version 2 is a cluster-owned logical job, distinct from the fixed-host v1
/// adapter. Election/attempt/term metadata belongs in a separate committed claim.
/// This object performs no RPC, local enqueue, consensus or physical dispatch.
class FrozenClusterPrintEffect {
  FrozenClusterPrintEffect._(List<int> payload)
    : payload = List<int>.unmodifiable(payload);
  final List<int> payload;

  factory FrozenClusterPrintEffect.fromQueuedJob({
    required PrintJob job,
    required RetainedClusterPrinterConfig config,
    required String jobId,
    required String effectId,
    required String requestId,
    required String originTerminalId,
    required String originInstallationId,
  }) {
    requirePristineOriginalPrintTicket(job);
    for (final id in [
      jobId,
      effectId,
      requestId,
      originTerminalId,
      originInstallationId,
    ]) {
      proofRequire(proofUuid(id), 'explicit immutable cluster job identity');
    }
    final b = config._body;
    proofRequire(
      job.venueId == b['venueId'] &&
          job.printerId == config.sourceRouteId &&
          job.routeRevision == b['routeRevision'] &&
          job.target.name == b['role'] &&
          job.destination.identity == config.destination.identity &&
          jsonEncode(job.capabilityProfile.toMap()) ==
              jsonEncode(config.profile.toMap()),
      'frozen job matches retained configuration',
    );
    final primary = job.transmissionBytes;
    proofRequire(
      primary.isNotEmpty && primary.length <= PrintJob.maxPayloadBytes + 1024,
      'cluster primary transmission bounds',
    );
    return FrozenClusterPrintEffect._(
      utf8.encode(
        jsonEncode({
          'version': 2,
          'scope': b['scope'],
          'clusterId': b['clusterId'],
          'venueId': b['venueId'],
          'jobId': jobId,
          'effectId': effectId,
          'requestId': requestId,
          'originTerminalId': originTerminalId,
          'originInstallationId': originInstallationId,
          'physicalPrinterId': b['physicalPrinterId'],
          'routeId': b['routeId'],
          'role': b['role'],
          'routeRevision': b['routeRevision'],
          'configRevision': b['configRevision'],
          'configSha256': config.sha256Digest,
          'capabilityProfile': job.capabilityProfile.toMap(),
          'primaryBytes': base64Encode(primary),
          'primarySha256': sha256.convert(primary).toString(),
          'reprintOf': null,
        }),
      ),
    );
  }
}
