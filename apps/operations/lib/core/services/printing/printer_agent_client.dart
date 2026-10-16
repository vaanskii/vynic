import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart' as wire;

import 'printer_agent_profile.dart';

/// Exact supplied leaf identity. Go's constructor preflights SAN/serverAuth;
/// signed production provisioning remains a separate missing admission bridge.
class PrinterAgentCertificatePin {
  PrinterAgentCertificatePin(List<int> pem) : _der = _decode(pem);
  final Uint8List _der;
  Uint8List get der => Uint8List.fromList(_der);
  static Uint8List _decode(List<int> pem) {
    if (pem.isEmpty || pem.length > 16384) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
    final match = RegExp(
      r'^-----BEGIN CERTIFICATE-----\r?\n([A-Za-z0-9+/=\r\n]+)-----END CERTIFICATE-----\r?\n?$',
    ).firstMatch(utf8.decode(pem));
    if (match == null)
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    final body = match.group(1)!.replaceAll(RegExp(r'[\r\n]'), '');
    final raw = base64Decode(body);
    if (raw.isEmpty || raw.length > 16384 || base64Encode(raw) != body) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
    return Uint8List.fromList(raw);
  }

  bool matches(X509Certificate certificate, String host) {
    final now = DateTime.now().toUtc();
    if (host != printerAgentServerName ||
        now.isBefore(certificate.startValidity.toUtc()) ||
        !now.isBefore(certificate.endValidity.toUtc()) ||
        certificate.der.length != _der.length) {
      return false;
    }
    var different = 0;
    for (var i = 0; i < _der.length; i++) {
      different |= _der[i] ^ certificate.der[i];
    }
    return different == 0;
  }
}

class _MutualTls extends grpc.ChannelCredentials {
  _MutualTls(List<int> server, List<int> client, List<int> key)
    : _context = SecurityContext(withTrustedRoots: false),
      super.secure(
        authority: printerAgentServerName,
        onBadCertificate: PrinterAgentCertificatePin(server).matches,
      ) {
    _context.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
    // A normally trusted alternative must not bypass the exact-pin callback.
    _context.useCertificateChainBytes(client);
    _context.usePrivateKeyBytes(key);
    _context.setAlpnProtocols(['h2'], false);
  }
  final SecurityContext _context;
  @override
  SecurityContext get securityContext => _context;
}

/// Frozen printer-only bytes. No serialization, new ID or projection happens
/// during retries. This version's server always refuses admission explicitly.
class PrinterAgentLocalIntent {
  PrinterAgentLocalIntent({
    required this.requestId,
    required this.jobId,
    required List<int> frozenEnvelope,
  }) : _envelope = Uint8List.fromList(frozenEnvelope) {
    if (!printerAgentUuid(requestId) ||
        !printerAgentUuid(jobId) ||
        _envelope.isEmpty ||
        _envelope.length > 12 * 1024 * 1024) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
    envelopeSha256 = sha256.convert(_envelope).toString();
  }
  final String requestId, jobId;
  final Uint8List _envelope;
  late final String envelopeSha256;
  Uint8List get frozenEnvelope => Uint8List.fromList(_envelope);
}

class PrinterAgentWireCodec {
  PrinterAgentWireCodec(this.profile);
  final PrinterAgentProfile profile;

  static void known(wire.GeneratedMessage message) {
    if (message.unknownFields.isNotEmpty) {
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    }
  }

  static int integer(Int64 value) {
    if (value.isNegative)
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    return value.toInt();
  }

  PrinterAgentHealth health(wire.PrinterAgentHealthResponse raw) {
    known(raw);
    if (!raw.hasPins() ||
        raw.protocolVersion != 1 ||
        raw.clientId != profile.clientId ||
        raw.physicalState !=
            wire.PrinterAgentPhysicalState.PRINTER_AGENT_PHYSICAL_HELD ||
        raw.admissionState !=
            wire
                .PrinterAgentAdmissionState
                .PRINTER_AGENT_ADMISSION_HELD_PROVISIONING ||
        raw.holdReasons.length > 5 ||
        raw.printerHolds.length > 64) {
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    }
    final p = raw.pins;
    known(p);
    final pins = PrinterAgentPins.fromJson({
      'scope': p.scope,
      'ownershipPolicy': p.ownershipPolicy,
      'clusterId': p.clusterId,
      'membershipSha256': p.membershipSha256,
      'role': p.role,
      'venueId': p.venueId,
      'installationId': p.installationId,
      'deviceId': p.deviceId,
      'hostId': p.hostId,
      'gatewayHostId': p.gatewayHostId,
      'authorityEpoch': integer(p.authorityEpoch),
      'protocolVersion': p.protocolVersion,
      'helperProtocolVersion': p.helperProtocolVersion,
      'databaseSchemaVersion': p.databaseSchemaVersion,
      'minimumReaderVersion': p.minimumReaderVersion,
      'routeRevision': integer(p.routeRevision),
      'configRevision': integer(p.configRevision),
      'registryRevision': integer(p.registryRevision),
      'bindingRevision': integer(p.bindingRevision),
      'capabilityRevision': integer(p.capabilityRevision),
      'capabilityProfileSha256': p.capabilityProfileSha256,
      'hostBinarySha256': p.hostBinarySha256,
      'helperBinarySha256': p.helperBinarySha256,
    });
    if (!profile.pins.matches(pins)) {
      throw const PrinterAgentException(PrinterAgentFailure.profileMismatch);
    }
    final state = switch (raw.state) {
      wire.PrinterAgentLifecycle.PRINTER_AGENT_NEW =>
        PrinterAgentLifecycle.newHost,
      wire.PrinterAgentLifecycle.PRINTER_AGENT_STARTING =>
        PrinterAgentLifecycle.starting,
      wire.PrinterAgentLifecycle.PRINTER_AGENT_RUNNING =>
        PrinterAgentLifecycle.running,
      wire.PrinterAgentLifecycle.PRINTER_AGENT_DRAINING =>
        PrinterAgentLifecycle.draining,
      wire.PrinterAgentLifecycle.PRINTER_AGENT_STOPPED =>
        PrinterAgentLifecycle.stopped,
      wire.PrinterAgentLifecycle.PRINTER_AGENT_HELD =>
        PrinterAgentLifecycle.held,
      _ => throw const PrinterAgentException(
        PrinterAgentFailure.protocolMismatch,
      ),
    };
    PrinterAgentHoldReason reason(wire.PrinterAgentHoldReason r) => switch (r) {
      wire.PrinterAgentHoldReason.PRINTER_AGENT_PROVISIONING_UNQUALIFIED =>
        PrinterAgentHoldReason.provisioningUnqualified,
      wire.PrinterAgentHoldReason.PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING =>
        PrinterAgentHoldReason.physicalActivationPending,
      wire.PrinterAgentHoldReason.PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED =>
        PrinterAgentHoldReason.sharedFenceUnqualified,
      wire.PrinterAgentHoldReason.PRINTER_AGENT_HOST_UNAVAILABLE =>
        PrinterAgentHoldReason.hostUnavailable,
      wire.PrinterAgentHoldReason.PRINTER_AGENT_RETAINED_QUEUE_HOLD =>
        PrinterAgentHoldReason.retainedQueueHold,
      _ => throw const PrinterAgentException(
        PrinterAgentFailure.protocolMismatch,
      ),
    };
    return PrinterAgentHealth(
      pins: pins,
      clientId: raw.clientId,
      state: state,
      softwareReady: raw.softwareReady,
      activeAdmissions: integer(raw.activeAdmissions),
      holdReasons: raw.holdReasons.map(reason),
      printerHolds: raw.printerHolds.map((h) {
        known(h);
        return PrinterAgentPrinterHold(
          physicalPrinterId: h.physicalPrinterId,
          reason: h.reason,
        );
      }),
    );
  }
}

/// Explicit loopback connection only. Nothing loads a profile, stores a
/// credential, starts a service, discovers an agent, or dispatches a printer.
class PrinterAgentClient implements PrinterAgentHealthReader {
  PrinterAgentClient._(this.profile, this._channel)
    : codec = PrinterAgentWireCodec(profile),
      _client = wire.PrinterAgentClient(
        _channel,
        options: grpc.CallOptions(timeout: const Duration(seconds: 5)),
      );

  factory PrinterAgentClient.connect({
    required PrinterAgentProfile profile,
    required List<int> clientCertificate,
    required List<int> clientKey,
  }) {
    for (final raw in [clientCertificate, clientKey]) {
      if (raw.isEmpty || raw.length > 16384) {
        throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
      }
    }
    try {
      final credentials = _MutualTls(
        profile.pinnedServerCertificate,
        Uint8List.fromList(clientCertificate),
        Uint8List.fromList(clientKey),
      );
      return PrinterAgentClient._(
        profile,
        grpc.ClientChannel(
          '127.0.0.1',
          port: profile.port,
          options: grpc.ChannelOptions(
            credentials: credentials,
            connectionTimeout: const Duration(seconds: 3),
          ),
        ),
      );
    } on PrinterAgentException {
      rethrow;
    } on TlsException {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    } on ArgumentError {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    } on FormatException {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
  }

  final PrinterAgentProfile profile;
  final PrinterAgentWireCodec codec;
  final grpc.ClientChannel _channel;
  final wire.PrinterAgentClient _client;
  wire.PrinterAgentAuth _auth() => wire.PrinterAgentAuth(
    hostId: profile.expectedHostId,
    clientId: profile.clientId,
    protocolMajor: 1,
    protocolMinor: 0,
    readerVersion: profile.pins.minimumReaderVersion,
    requiredCapabilities: [printerAgentCapability],
  );

  Never _error(grpc.GrpcError error) {
    final reason = switch (error.code) {
      grpc.StatusCode.unauthenticated => PrinterAgentFailure.authentication,
      grpc.StatusCode.permissionDenied => PrinterAgentFailure.profileMismatch,
      grpc.StatusCode.failedPrecondition
          when error.message?.startsWith('HELD_PROVISIONING:') == true =>
        PrinterAgentFailure.provisioningHeld,
      grpc.StatusCode.failedPrecondition ||
      grpc.StatusCode.invalidArgument ||
      grpc.StatusCode.dataLoss => PrinterAgentFailure.protocolMismatch,
      _ => PrinterAgentFailure.unavailable,
    };
    throw PrinterAgentException(reason);
  }

  @override
  Future<PrinterAgentHealth> health() async {
    try {
      return codec.health(
        await _client.health(wire.PrinterAgentHealthRequest(auth: _auth())),
      );
    } on grpc.GrpcError catch (error) {
      _error(error);
    }
  }

  Future<void> submitLocal(PrinterAgentLocalIntent intent) async {
    try {
      await _client.submitLocal(
        wire.PrinterAgentSubmitLocalRequest(
          auth: _auth(),
          requestId: intent.requestId,
          jobId: intent.jobId,
          frozenEnvelope: intent.frozenEnvelope,
          envelopeSha256: intent.envelopeSha256,
        ),
      );
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    } on grpc.GrpcError catch (error) {
      _error(error);
    }
  }

  Future<void> getLocalResult(PrinterAgentLocalIntent intent) async {
    try {
      await _client.getLocalResult(
        wire.PrinterAgentGetLocalResultRequest(
          auth: _auth(),
          requestId: intent.requestId,
          jobId: intent.jobId,
          envelopeSha256: intent.envelopeSha256,
        ),
      );
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    } on grpc.GrpcError catch (error) {
      _error(error);
    }
  }

  Future<void> close() => _channel.shutdown();
}
