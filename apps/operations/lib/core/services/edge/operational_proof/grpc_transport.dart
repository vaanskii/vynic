import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart' as wire;

import 'domain.dart';

/// Mapping to the generator-produced protocol only. Domain frames are never a
/// second HTTP/JSON wire contract. Every decoded integer/enum/scope is bounded.
class OperationalProofWireCodec {
  OperationalProofWireCodec(this.binding);
  final ProofBinding binding;

  static int integer(Int64 value, {bool positive = false}) {
    proofRequire(!value.isNegative, 'wire unsigned value exceeds signed int64');
    final number = value.toInt();
    proofInteger(number, positive: positive);
    return number;
  }

  static void known(wire.GeneratedMessage message) =>
      proofRequire(message.unknownFields.isEmpty, 'unknown protobuf fields');

  static wire.ProofEntity_Kind entityKind(ProofEntityKind kind) =>
      switch (kind) {
        ProofEntityKind.order => wire.ProofEntity_Kind.ORDER,
        ProofEntityKind.table => wire.ProofEntity_Kind.TABLE,
        ProofEntityKind.reservation => wire.ProofEntity_Kind.RESERVATION,
        ProofEntityKind.package => wire.ProofEntity_Kind.PACKAGE,
        ProofEntityKind.sale => wire.ProofEntity_Kind.SALE,
        ProofEntityKind.day => wire.ProofEntity_Kind.DAY,
        ProofEntityKind.operationalControl =>
          wire.ProofEntity_Kind.OPERATIONAL_CONTROL,
        ProofEntityKind.auditReport => wire.ProofEntity_Kind.AUDIT_REPORT,
        ProofEntityKind.closure => wire.ProofEntity_Kind.CLOSURE,
        ProofEntityKind.advance => wire.ProofEntity_Kind.ADVANCE,
        ProofEntityKind.expense => wire.ProofEntity_Kind.EXPENSE,
        ProofEntityKind.staff => wire.ProofEntity_Kind.STAFF,
        ProofEntityKind.operationalPolicy =>
          wire.ProofEntity_Kind.OPERATIONAL_POLICY,
      };

  static ProofEntityKind domainKind(wire.ProofEntity_Kind kind) {
    for (final candidate in ProofEntityKind.values) {
      if (entityKind(candidate) == kind) return candidate;
    }
    throw const FormatException('Invalid isolated proof: unknown entity kind');
  }

  void _epoch(String mode, Int64 epoch) {
    proofRequire(
      mode == operationalProofMode &&
          integer(epoch, positive: true) == binding.epoch,
      'wire mode/epoch',
    );
  }

  ProofEntity entity(wire.ProofEntity raw) {
    known(raw);
    return ProofEntity(
      key: ProofKey(domainKind(raw.kind), raw.id),
      revision: integer(raw.revision),
      tombstone: raw.tombstone,
      document: raw.document,
    );
  }

  ProofEffect effect(wire.ProofEffect raw) {
    known(raw);
    final kind = switch (raw.kind) {
      wire.ProofEffect_Kind.AUDIT => ProofEffectKind.audit,
      wire.ProofEffect_Kind.PRINT => ProofEffectKind.print,
      _ => throw const FormatException(
        'Invalid isolated proof: unknown effect kind',
      ),
    };
    return ProofEffect(id: raw.id, kind: kind, payload: raw.payload);
  }

  ProofPrintReceipt printReceipt(wire.ProofPrintReceipt raw) {
    known(raw);
    return ProofPrintReceipt(
      version: raw.version,
      jobId: raw.jobId,
      effectId: raw.effectId,
      physicalPrinterId: raw.physicalPrinterId,
      sequence: integer(raw.sequence, positive: true),
      admissionSha256: raw.admissionSha256,
    );
  }

  ProofEvent event(wire.ProofEvent raw) {
    known(raw);
    _epoch(raw.mode, raw.authorityEpoch);
    return ProofEvent(
      binding: binding,
      sequence: integer(raw.sequence, positive: true),
      requestId: raw.requestId,
      terminalId: raw.terminalId,
      entities: raw.entities.map(entity).toList(),
      effects: raw.effects.map(effect).toList(),
      printAdmission: raw.printAdmission,
      originInstallationId: raw.originInstallationId,
      printReceipts: raw.printReceipts.map(printReceipt).toList(),
    );
  }

  ProofResult result(wire.ProofCommitResult raw, String requestId) {
    known(raw);
    _epoch(raw.mode, raw.authorityEpoch);
    proofRequire(
      raw.requestId == requestId && raw.terminalId == binding.terminalId,
      'wire result owner/request',
    );
    if (raw.printAdmission.isNotEmpty)
      proofRequire(
        raw.originInstallationId == binding.originInstallationId &&
            proofUuid(binding.originInstallationId),
        'wire result pinned origin',
      );
    final outcome = switch (raw.outcome) {
      wire.ProofCommitResult_Outcome.COMMITTED => ProofOutcome.committed,
      wire.ProofCommitResult_Outcome.CONFLICT => ProofOutcome.conflict,
      _ => throw const FormatException(
        'Invalid isolated proof: unknown outcome',
      ),
    };
    final committedEvent = raw.hasEvent() ? event(raw.event) : null;
    if (committedEvent != null)
      proofRequire(
        committedEvent.requestId == raw.requestId &&
            committedEvent.terminalId == raw.terminalId,
        'wire result/event identity',
      );
    return ProofResult(
      binding: binding,
      requestId: raw.requestId,
      terminalId: raw.terminalId,
      outcome: outcome,
      headSequence: integer(raw.headSequence),
      event: committedEvent,
      current: raw.current.map(entity).toList(),
      applicationData: raw.applicationData,
      printAdmission: raw.printAdmission,
      originInstallationId: raw.originInstallationId,
    );
  }

  ProofStatus status(wire.ProofStatus raw) {
    known(raw);
    _epoch(raw.mode, raw.authorityEpoch);
    proofRequire(
      raw.originInstallationId == binding.originInstallationId &&
          raw.venueId == binding.venueId &&
          raw.installationId == binding.installationId &&
          raw.grantSha256.length == 32 &&
          raw.grantSha256
                  .map((v) => v.toRadixString(16).padLeft(2, '0'))
                  .join() ==
              binding.grantFingerprint &&
          raw.hasProtocol() &&
          raw.hasLimits(),
      'wire status pin',
    );
    known(raw.protocol);
    known(raw.limits);
    proofUnique(raw.capabilities, (v) => v);
    proofRequire(
      raw.capabilities.every(
            (v) =>
                v == operationalProofCapability ||
                v == operationalProofPrintCapability,
          ) &&
          raw.protocol.requiredCapabilities.isEmpty,
      'wire status capabilities',
    );
    final limits = raw.limits;
    return ProofStatus(
      binding: binding,
      head: integer(raw.headSequence),
      protocolMajor: raw.protocol.major,
      protocolMinor: raw.protocol.minor,
      capabilities: raw.capabilities,
      limits: {
        'requestBytes': limits.maxRequestBytes,
        'documentBytes': limits.maxDocumentBytes,
        'effectBytes': limits.maxEffectBytes,
        'applicationBytes': limits.maxApplicationBytes,
        'eventBytes': limits.maxEventBytes,
        'resultBytes': limits.maxResultBytes,
        'snapshotBytes': limits.maxSnapshotBytes,
        'replayBytes': limits.maxReplayBytes,
        'stateBytes': limits.maxStateBytes,
        'journalBytes': limits.maxJournalBytes,
        'entities': limits.maxEntities,
        'requests': limits.maxRetainedRequests,
        'events': limits.maxRetainedEvents,
        'effects': limits.maxRetainedEffects,
        'writes': limits.maxWrites,
        'reads': limits.maxReads,
        'requestEffects': limits.maxRequestEffects,
        'replayEvents': limits.maxReplayEvents,
      },
    );
  }

  ProofReplayPage replay(wire.ProofReplayPage raw, int after) {
    known(raw);
    _epoch(raw.mode, raw.authorityEpoch);
    proofRequire(integer(raw.afterSequence) == after, 'wire replay cursor');
    return ProofReplayPage(
      binding: binding,
      after: integer(raw.afterSequence),
      head: integer(raw.headSequence),
      next: integer(raw.nextSequence),
      events: raw.events.map(event).toList(),
    );
  }

  ProofSnapshot snapshot(wire.ProofSnapshot raw) {
    known(raw);
    _epoch(raw.mode, raw.authorityEpoch);
    proofRequire(
      raw.venueId == binding.venueId &&
          raw.installationId == binding.installationId,
      'wire snapshot scope',
    );
    return ProofSnapshot(
      binding: binding,
      sequence: integer(raw.sequence),
      entities: raw.entities.map(entity).toList(),
    );
  }

  wire.ProofCommitRequest intent(
    ProofIntent intent,
    wire.AuthenticatedRequest auth,
  ) {
    proofRequire(
      intent.binding.fingerprint == binding.fingerprint,
      'wire pending binding',
    );
    return wire.ProofCommitRequest(
      auth: auth,
      requestId: intent.requestId,
      authorityEpoch: Int64(binding.epoch),
      reads: intent.reads.map(
        (r) => wire.ProofRead(
          kind: entityKind(r.key.kind),
          id: r.key.id,
          expectedRevision: Int64(r.expectedRevision),
          expectedTombstone: r.expectedTombstone,
        ),
      ),
      writes: intent.writes.map(
        (w) => wire.ProofWrite(
          kind: entityKind(w.key.kind),
          id: w.key.id,
          expectedRevision: Int64(w.expectedRevision),
          tombstone: w.tombstone,
          document: w.document,
        ),
      ),
      effects: intent.effects.map(
        (e) => wire.ProofEffect(
          id: e.id,
          kind: e.kind == ProofEffectKind.audit
              ? wire.ProofEffect_Kind.AUDIT
              : wire.ProofEffect_Kind.PRINT,
          payload: e.payload,
        ),
      ),
      applicationData: intent.applicationData,
      printAdmission: intent.printAdmission,
      originInstallationId: intent.originInstallationId,
    );
  }
}

/// A fixture's trusted out-of-band leaf pin. The Go proof constructor performs
/// SAN/serverAuth preflight with crypto/x509 before handing this pin to Dart.
/// Production provisioning/attestation is outside this isolated wire adapter.
class OperationalProofCertificatePin {
  OperationalProofCertificatePin(List<int> pem) : der = _decode(pem);
  final List<int> der;
  static List<int> _decode(List<int> pem) {
    final encoded = utf8.decode(pem, allowMalformed: false);
    final match = RegExp(
      r'^-----BEGIN CERTIFICATE-----\r?\n([A-Za-z0-9+/=\r\n]+)-----END CERTIFICATE-----\r?\n?$',
    ).firstMatch(encoded);
    proofRequire(match != null, 'one canonical pinned server certificate');
    final body = match!.group(1)!.replaceAll(RegExp(r'[\r\n]'), '');
    final der = proofBytes(base64Decode(body), 16384);
    proofRequire(
      der.isNotEmpty && base64Encode(der) == body,
      'canonical server certificate DER',
    );
    return der;
  }

  bool matches(X509Certificate certificate, String host) {
    final now = DateTime.now().toUtc();
    if (host != 'vynic-edge.local' ||
        now.isBefore(certificate.startValidity.toUtc()) ||
        !now.isBefore(certificate.endValidity.toUtc()) ||
        certificate.der.length != der.length)
      return false;
    var different = 0;
    for (var i = 0; i < der.length; i++) {
      different |= der[i] ^ certificate.der[i];
    }
    return different == 0;
  }
}

class _ProofMutualTlsCredentials extends grpc.ChannelCredentials {
  _ProofMutualTlsCredentials(List<int> server, List<int> client, List<int> key)
    : _context = SecurityContext(withTrustedRoots: false),
      super.secure(
        authority: 'vynic-edge.local',
        onBadCertificate: OperationalProofCertificatePin(server).matches,
      ) {
    _context.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
    // No CA/leaf trust shortcut: every server certificate must pass the exact
    // out-of-band pin callback, including on platforms that accept leaf roots.
    _context.useCertificateChainBytes(client);
    _context.usePrivateKeyBytes(key);
    _context.setAlpnProtocols(['h2'], false);
  }
  final SecurityContext _context;
  @override
  SecurityContext get securityContext => _context;
}

/// Explicit isolated wiring only. Certificate roots and client key are supplied
/// out of band, kept in memory and never included in a durable proof frame.
/// No plaintext, discovery, auto-pin, normal startup or physical sender exists.
class OperationalProofGrpcTransport implements OperationalProofTransport {
  OperationalProofGrpcTransport._(
    this.binding,
    this._terminalSecret,
    this._channel,
  ) : codec = OperationalProofWireCodec(binding),
      _client = wire.OperationalProofClient(
        _channel,
        options: grpc.CallOptions(timeout: const Duration(seconds: 10)),
      );

  factory OperationalProofGrpcTransport.connect({
    required ProofBinding binding,
    required String terminalSecret,
    required String host,
    required int port,
    required List<int> pinnedServerCertificate,
    required List<int> terminalCertificate,
    required List<int> terminalPrivateKey,
  }) {
    final secret = base64Url.decode('$terminalSecret=');
    proofRequire(
      secret.length == 32 &&
          base64Url.encode(secret).replaceAll('=', '') == terminalSecret &&
          host.isNotEmpty &&
          port > 0 &&
          port <= 65535,
      'wire endpoint/secret',
    );
    for (final bytes in [
      pinnedServerCertificate,
      terminalCertificate,
      terminalPrivateKey,
    ]) {
      proofRequire(
        bytes.isNotEmpty && bytes.length <= 16384,
        'wire TLS credential bound',
      );
    }
    final credentials = _ProofMutualTlsCredentials(
      pinnedServerCertificate,
      terminalCertificate,
      terminalPrivateKey,
    );
    return OperationalProofGrpcTransport._(
      binding,
      terminalSecret,
      grpc.ClientChannel(
        host,
        port: port,
        options: grpc.ChannelOptions(
          credentials: credentials,
          connectionTimeout: const Duration(seconds: 3),
        ),
      ),
    );
  }

  final ProofBinding binding;
  final String _terminalSecret;
  final grpc.ClientChannel _channel;
  final wire.OperationalProofClient _client;
  final OperationalProofWireCodec codec;
  wire.AuthenticatedRequest _auth() => wire.AuthenticatedRequest(
    scope: wire.Scope(
      venueId: binding.venueId,
      installationId: binding.installationId,
      protocol: wire.Protocol(
        major: 1,
        minor: 3,
        requiredCapabilities: [
          operationalProofCapability,
          if (binding.originInstallationId.isNotEmpty)
            operationalProofPrintCapability,
        ],
      ),
    ),
    terminalId: binding.terminalId,
    terminalSecret: _terminalSecret,
  );
  void _epoch(int epoch) =>
      proofRequire(epoch == binding.epoch, 'wire caller epoch');
  Future<void> close() => _channel.shutdown();

  @override
  Future<ProofStatus> status() async =>
      codec.status(await _client.status(_auth()));
  @override
  Future<ProofResult> commit(ProofIntent intent) async => codec.result(
    await _client.commit(codec.intent(intent, _auth())),
    intent.requestId,
  );
  @override
  Future<ProofResultLookup> getResult({
    required String requestId,
    required int epoch,
  }) async {
    _epoch(epoch);
    proofRequire(proofUuid(requestId), 'wire lookup UUID');
    try {
      final raw = await _client.getResult(
        wire.ProofResultRequest(
          auth: _auth(),
          requestId: requestId,
          authorityEpoch: Int64(epoch),
        ),
      );
      return ProofResultLookup.found(codec.result(raw, requestId));
    } on grpc.GrpcError catch (error) {
      if (error.code == grpc.StatusCode.notFound)
        return const ProofResultLookup.notFound();
      rethrow;
    }
  }

  @override
  Future<ProofReplayPage> replay({
    required int epoch,
    required int after,
    required int limit,
  }) async {
    _epoch(epoch);
    proofInteger(after);
    proofRequire(
      limit > 0 && limit <= ProofBounds.replayEvents,
      'wire replay limit',
    );
    return codec.replay(
      await _client.replay(
        wire.ProofReplayRequest(
          auth: _auth(),
          authorityEpoch: Int64(epoch),
          afterSequence: Int64(after),
          limit: limit,
        ),
      ),
      after,
    );
  }

  @override
  Future<ProofSnapshot> snapshot({required int epoch}) async {
    _epoch(epoch);
    return codec.snapshot(
      await _client.snapshot(
        wire.ProofSnapshotRequest(auth: _auth(), authorityEpoch: Int64(epoch)),
      ),
    );
  }
}
