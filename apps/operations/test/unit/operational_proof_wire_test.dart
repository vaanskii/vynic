import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:hive/hive.dart';
import 'package:vynic/core/services/edge/operational_proof/client.dart';
import 'package:vynic/core/services/edge/operational_proof/domain.dart';
import 'package:vynic/core/services/edge/operational_proof/frame_store.dart';
import 'package:vynic/core/services/edge/operational_proof/grpc_transport.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart' as wire;

String _id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

// Callback observations only; the positive integration below uses real TLS
// and the Go constructor's crypto/x509 SAN/serverAuth preflight.
class _CertificateObservation implements X509Certificate {
  _CertificateObservation(List<int> bytes, this.startValidity, this.endValidity)
    : der = Uint8List.fromList(bytes);
  @override
  final Uint8List der;
  @override
  final DateTime startValidity, endValidity;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProofBinding _pin({String origin = ''}) => ProofBinding(
  installationId: _id(1),
  venueId: _id(2),
  terminalId: _id(3),
  epoch: 41,
  grantFingerprint: 'a' * 64,
  mode: operationalProofMode,
  originInstallationId: origin,
);
wire.ProofEntity _entity(ProofEntityKind kind) => wire.ProofEntity(
  kind: OperationalProofWireCodec.entityKind(kind),
  id: _id(11),
  revision: Int64(1),
  document: utf8.encode('{"exact":"ქართული"}'),
);
wire.ProofCommitResult _result() => wire.ProofCommitResult(
  mode: operationalProofMode,
  requestId: _id(100),
  terminalId: _id(3),
  outcome: wire.ProofCommitResult_Outcome.COMMITTED,
  authorityEpoch: Int64(41),
  headSequence: Int64(1),
  event: wire.ProofEvent(
    mode: operationalProofMode,
    authorityEpoch: Int64(41),
    sequence: Int64(1),
    requestId: _id(100),
    terminalId: _id(3),
    entities: [_entity(ProofEntityKind.order)],
  ),
);

class _FlushedBox implements Box<dynamic> {
  _FlushedBox(this.box);
  final Box<dynamic> box;
  int writes = 0, flushes = 0;
  String? lastFlushed;
  @override
  String get name => box.name;
  @override
  bool get isOpen => box.isOpen;
  @override
  Iterable<dynamic> get keys => box.keys;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      box.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    writes++;
    await box.put(key, value);
  }

  @override
  Future<void> flush() async {
    await box.flush();
    flushes++;
    lastFlushed = box.get(HiveOperationalProofFrameStore.frameKey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only observation is synthetic. Every RPC goes through the generated client
/// and real mutual TLS socket to the independent Go gateway process.
class _ObservedWire implements OperationalProofTransport {
  _ObservedWire(this.real, this.box);
  final OperationalProofGrpcTransport real;
  final _FlushedBox box;
  int sends = 0;
  @override
  Future<ProofResult> commit(ProofIntent intent) {
    final frame = jsonDecode(box.lastFlushed!) as Map;
    expect(frame['pending'], intent.toFrame());
    expect(box.writes, box.flushes);
    expect(frame['effects'], isEmpty);
    sends++;
    return real.commit(intent);
  }

  @override
  Future<ProofStatus> status() => real.status();
  @override
  Future<ProofResultLookup> getResult({
    required String requestId,
    required int epoch,
  }) => real.getResult(requestId: requestId, epoch: epoch);
  @override
  Future<ProofReplayPage> replay({
    required int epoch,
    required int after,
    required int limit,
  }) => real.replay(epoch: epoch, after: after, limit: limit);
  @override
  Future<ProofSnapshot> snapshot({required int epoch}) =>
      real.snapshot(epoch: epoch);
}

Future<void> _waitFile(File file, Process process) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    if (await file.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  process.kill();
  throw StateError('Isolated Go fixture did not become ready');
}

ProofBinding _fixturePin(Map<String, dynamic> f, int index, {String? origin}) {
  final c = f['clients'][index] as Map;
  return ProofBinding(
    installationId: f['installationId'],
    venueId: f['venueId'],
    terminalId: c['terminalId'],
    epoch: f['epoch'],
    grantFingerprint: f['grantFingerprint'],
    mode: operationalProofMode,
    originInstallationId: origin ?? c['originInstallationId'],
  );
}

OperationalProofGrpcTransport _fixtureTransport(
  Map<String, dynamic> f,
  int index,
  int port, {
  ProofBinding? binding,
}) {
  final c = f['clients'][index] as Map;
  return OperationalProofGrpcTransport.connect(
    binding: binding ?? _fixturePin(f, index),
    terminalSecret: c['terminalSecret'],
    host: '127.0.0.1',
    port: port,
    pinnedServerCertificate: base64Decode(f['serverCertificate']),
    terminalCertificate: base64Decode(c['certificate']),
    terminalPrivateKey: base64Decode(c['key']),
  );
}

ProofIntent _fixtureIntent(
  Map<String, dynamic> f,
  int client,
  String request,
  int revision,
  int nonce,
) {
  final pin = _fixturePin(f, client);
  final r = f['registries'][0] as Map;
  final primary = [0x1b, 0x40, 0xff, 0, 0x1d, 0x56, 0];
  final physical = r['physicalPrinterId'];
  final payload = utf8.encode(
    jsonEncode({
      'version': 1,
      'jobId': _id(nonce),
      'effectId': _id(nonce + 1),
      'requestId': request,
      'terminalId': pin.terminalId,
      'venueId': pin.venueId,
      'installationId': pin.installationId,
      'originInstallationId': pin.originInstallationId,
      'authorityEpoch': pin.epoch,
      'deviceId': r['deviceId'],
      'physicalPrinterId': physical,
      'aliasId': r['aliases'][client % 2],
      'routeRevision': 1,
      'configRevision': 1,
      'bindingRevision': 1,
      'registryRevision': 1,
      'attemptId': _id(nonce + 2),
      'beepAttemptId': _id(nonce + 3),
      'destination': {
        ...(r['destination'] as Map),
        'documentName': 'frozen Dart→Go synthetic raster + cut',
      },
      'capabilityProfile': {
        'protocol': 1,
        'paperWidthMm': 80,
        'rasterWidthDots': 576,
        'language': 'escposRaster',
        'cutter': 'partial',
        'encoding': 'georgianViaRaster',
        'beep': {'capability': 'epsonEscA97Pattern', 'enabled': false},
      },
      'primaryBytes': base64Encode(primary),
      'primarySha256': sha256.convert(primary).toString(),
    }),
  );
  return ProofIntent(
    binding: pin,
    requestId: request,
    printAdmission: operationalProofPrintAdmission,
    reads: [
      ProofRead(
        key: ProofKey(ProofEntityKind.operationalControl, f['controlId']),
        expectedRevision: revision,
      ),
    ],
    writes: [
      ProofWrite(
        key: ProofKey(ProofEntityKind.operationalControl, f['controlId']),
        expectedRevision: revision,
        tombstone: false,
        document: utf8.encode('{"lastOrderId":${revision + 1}}'),
      ),
      ProofWrite(
        key: ProofKey(ProofEntityKind.table, f['tableId']),
        expectedRevision: revision,
        tombstone: false,
        document: utf8.encode('{"synthetic":true}'),
      ),
    ],
    effects: [
      ProofEffect(
        id: _id(nonce + 1),
        kind: ProofEffectKind.print,
        payload: payload,
      ),
    ],
    applicationData: utf8.encode('exact frozen caller data'),
  );
}

void main() {
  final codec = OperationalProofWireCodec(_pin());
  test(
    'exact server pin refuses mismatched DER, SNI, expiry and future validity',
    () {
      final der = [0x30, 1, 0];
      final pem = utf8.encode(
        '-----BEGIN CERTIFICATE-----\n${base64Encode(der)}\n-----END CERTIFICATE-----\n',
      );
      final pin = OperationalProofCertificatePin(pem);
      final now = DateTime.now().toUtc();
      final valid = _CertificateObservation(
        der,
        now.subtract(const Duration(hours: 1)),
        now.add(const Duration(hours: 1)),
      );
      expect(pin.matches(valid, 'vynic-edge.local'), isTrue);
      expect(pin.matches(valid, 'another-host.local'), isFalse);
      expect(
        pin.matches(
          _CertificateObservation(
            [0x30, 1, 1],
            valid.startValidity,
            valid.endValidity,
          ),
          'vynic-edge.local',
        ),
        isFalse,
      );
      expect(
        pin.matches(
          _CertificateObservation(
            der,
            now.subtract(const Duration(hours: 2)),
            now.subtract(const Duration(hours: 1)),
          ),
          'vynic-edge.local',
        ),
        isFalse,
      );
      expect(
        pin.matches(
          _CertificateObservation(
            der,
            now.add(const Duration(hours: 1)),
            now.add(const Duration(hours: 2)),
          ),
          'vynic-edge.local',
        ),
        isFalse,
      );
      expect(() => pin.der[0] = 1, throwsUnsupportedError);
      expect(
        () => OperationalProofCertificatePin([...pem, ...pem]),
        throwsFormatException,
      );
    },
  );
  for (final kind in ProofEntityKind.values) {
    test(
      'generated wire entity ${kind.name} preserves exact bytes/revision',
      () {
        final raw = _entity(kind);
        final decoded = codec.entity(
          wire.ProofEntity.fromBuffer(raw.writeToBuffer()),
        );
        expect(decoded.key.kind, kind);
        expect(decoded.document, raw.document);
        expect(decoded.revision, 1);
      },
    );
  }
  test(
    'wire refuses unspecified enums, unsigned overflow and unknown fields',
    () {
      expect(
        () => codec.entity(
          wire.ProofEntity(
            kind: wire.ProofEntity_Kind.UNSPECIFIED,
            id: _id(11),
            revision: Int64(1),
            document: utf8.encode('{}'),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => OperationalProofWireCodec.integer(Int64.MIN_VALUE),
        throwsFormatException,
      );
      expect(
        () => OperationalProofWireCodec.integer(Int64.ZERO, positive: true),
        throwsFormatException,
      );
      final unknown = _entity(ProofEntityKind.order)
        ..mergeFromBuffer([0xa0, 0x06, 0x01]);
      expect(() => codec.entity(unknown), throwsFormatException);
    },
  );
  test(
    'wire rejects foreign result/epoch, event mismatch and fabricated outcomes',
    () {
      expect(codec.result(_result(), _id(100)).headSequence, 1);
      for (final field in [
        'request',
        'terminal',
        'epoch',
        'event',
        'outcome',
      ]) {
        final r = _result();
        switch (field) {
          case 'request':
            r.requestId = _id(101);
          case 'terminal':
            r.terminalId = _id(4);
          case 'epoch':
            r.authorityEpoch = Int64(42);
          case 'event':
            r.event.requestId = _id(101);
          case 'outcome':
            r.outcome = wire.ProofCommitResult_Outcome.UNSPECIFIED;
        }
        expect(
          () => codec.result(r, _id(100)),
          throwsFormatException,
          reason: field,
        );
      }
    },
  );
  test('old binding and admission-free request/result frames remain exact', () {
    final pin = _pin();
    expect(pin.toFrame().keys.toSet(), {
      'installationId',
      'venueId',
      'terminalId',
      'epoch',
      'grantFingerprint',
      'mode',
    });
    expect(ProofBinding.fromFrame(pin.toFrame()).fingerprint, pin.fingerprint);
    final r = codec.result(_result(), _id(100));
    expect(r.toFrame().containsKey('printAdmission'), isFalse);
    expect(r.event!.toFrame().containsKey('printReceipts'), isFalse);
    expect(ProofResult.fromFrame(r.toFrame()).fingerprint, r.fingerprint);
    expect(
      () => ProofIntent(
        binding: pin,
        requestId: _id(200),
        printAdmission: operationalProofPrintAdmission,
        writes: [
          ProofWrite(
            key: ProofKey(ProofEntityKind.order, _id(11)),
            expectedRevision: 0,
            tombstone: false,
            document: utf8.encode('{}'),
          ),
        ],
      ),
      throwsFormatException,
    );
  });
  test('receipt binds exact frozen payload and refuses spoofing', () {
    final body = {
      'version': 1,
      'jobId': _id(20),
      'effectId': _id(21),
      'physicalPrinterId': _id(22),
    };
    final effect = ProofEffect(
      id: _id(21),
      kind: ProofEffectKind.print,
      payload: utf8.encode(jsonEncode(body)),
    );
    final r = ProofPrintReceipt(
      version: 1,
      jobId: _id(20),
      effectId: _id(21),
      physicalPrinterId: _id(22),
      sequence: 1,
      admissionSha256: sha256.convert(effect.payload).toString(),
    );
    r.verify(effect);
    expect(ProofPrintReceipt.fromFrame(r.toFrame()).toFrame(), r.toFrame());
    expect(
      () => r.verify(
        ProofEffect(
          id: _id(21),
          kind: ProofEffectKind.print,
          payload: utf8.encode('changed'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => ProofPrintReceipt(
        version: 2,
        jobId: _id(20),
        effectId: _id(21),
        physicalPrinterId: _id(22),
        sequence: 1,
        admissionSha256: 'a' * 64,
      ),
      throwsFormatException,
    );
  });

  test(
    'actual Dart→Go mutual TLS loses ACK, flushes before send, reopens and retains other-origin receipts',
    () async {
      final binary = Platform.environment['VYNIC_OPERATIONAL_PROOF_GO_FIXTURE'];
      if (binary == null) {
        throw StateError(
          'Compile the isolated Go server test fixture and set VYNIC_OPERATIONAL_PROOF_GO_FIXTURE; actual wire qualification is required',
        );
      }
      final dir = await Directory.systemTemp.createTemp(
        'vynic-operational-wire-',
      );
      final process = await Process.start(
        binary,
        [r'-test.run=^TestOperationalProofProcess$', '-test.v'],
        environment: {
          'VYNIC_OPERATIONAL_WIRE_DIR': dir.path,
          'VYNIC_OPERATIONAL_WIRE_ROLE': 'dart-gateway',
        },
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final transports = <OperationalProofGrpcTransport>[];
      try {
        await _waitFile(File('${dir.path}/gateway-ready.json'), process);
        final fixture = Map<String, dynamic>.from(
          jsonDecode(await File('${dir.path}/fixture.json').readAsString()),
        );
        final ready =
            jsonDecode(
                  await File('${dir.path}/gateway-ready.json').readAsString(),
                )
                as Map;
        final port = int.parse((ready['address'] as String).split(':').last);
        final hive = Directory('${dir.path}/hive');
        await hive.create();
        Hive.init(hive.path);
        final transport = _fixtureTransport(fixture, 0, port);
        transports.add(transport);
        final box = await Hive.openBox<dynamic>(
          'isolated_operational_proof_wire',
        );
        final observed = _FlushedBox(box);
        final client = OperationalProofClient(
          store: HiveOperationalProofFrameStore(observed),
          transport: _ObservedWire(transport, observed),
          binding: _fixturePin(fixture, 0),
        );
        await client.open();
        final intent = _fixtureIntent(
          fixture,
          0,
          fixture['lostRequestId'],
          0,
          1000,
        );
        await client.prepare(intent);
        expect(client.entities, isEmpty);
        expect(client.effectReceipts, isEmpty);
        expect(observed.lastFlushed, contains(intent.requestId));
        await expectLater(
          client.sendPending(),
          throwsA(
            isA<grpc.GrpcError>().having(
              (e) => e.code,
              'code',
              grpc.StatusCode.unavailable,
            ),
          ),
        );
        expect(client.pending!.fingerprint, intent.fingerprint);
        expect(client.entities, isEmpty);
        expect(client.effectReceipts, isEmpty);
        expect(client.ready, isFalse);
        final prepared = jsonDecode(observed.lastFlushed!) as Map;
        expect(
          jsonEncode(prepared),
          isNot(contains(fixture['clients'][0]['terminalSecret'])),
        );
        expect(prepared['pending'], intent.toFrame());
        await box.close();
        await transport.close();
        transports.remove(transport);
        final reopenedBox = await Hive.openBox<dynamic>(
          'isolated_operational_proof_wire',
        );
        final reopenedTransport = _fixtureTransport(fixture, 0, port);
        transports.add(reopenedTransport);
        final reopened = OperationalProofClient(
          store: HiveOperationalProofFrameStore(reopenedBox),
          transport: reopenedTransport,
          binding: _fixturePin(fixture, 0),
        );
        await reopened.open();
        expect(reopened.pending, isNull);
        expect(reopened.ready, isTrue);
        expect(reopened.cursor, 1);
        expect(reopened.effectReceipts.single.printReceipt!.jobId, _id(1000));
        expect(
          reopened.effectReceipts.single.originInstallationId,
          intent.binding.originInstallationId,
        );
        expect(
          reopened.lastResult!.event!.printReceipts.single.admissionSha256,
          sha256.convert(intent.effects.single.payload).toString(),
        );
        final outcome = reopened.lastResult!.fingerprint;
        final exact = await reopenedTransport.commit(intent);
        expect(exact.fingerprint, outcome);
        expect(
          (await reopenedTransport.replay(
            epoch: 41,
            after: 0,
            limit: 100,
          )).events.length,
          1,
        );
        final otherTransport = _fixtureTransport(fixture, 1, port);
        transports.add(otherTransport);
        final otherBox = await Hive.openBox<dynamic>(
          'isolated_operational_proof_wire_other',
        );
        final other = OperationalProofClient(
          store: HiveOperationalProofFrameStore(otherBox),
          transport: otherTransport,
          binding: _fixturePin(fixture, 1),
        );
        await other.open();
        expect(
          other.effectReceipts.single.originInstallationId,
          intent.binding.originInstallationId,
        );
        final next = _fixtureIntent(fixture, 1, _id(2000), 1, 2001);
        await other.prepare(next);
        await other.sendPending();
        await reopened.catchUp();
        expect(reopened.cursor, 2);
        expect(reopened.effectReceipts.length, 2);
        expect(
          reopened.effectReceipts.last.originInstallationId,
          next.binding.originInstallationId,
        );
        await reopened.verifySnapshot();
        final historical = await reopenedTransport.getResult(
          requestId: intent.requestId,
          epoch: 41,
        );
        expect(historical.result!.headSequence, 1);
        expect(historical.result!.fingerprint, outcome);
        final wrongOrigin = _fixtureTransport(
          fixture,
          0,
          port,
          binding: _fixturePin(fixture, 0, origin: _id(9999)),
        );
        transports.add(wrongOrigin);
        await expectLater(wrongOrigin.status(), throwsFormatException);
        final c = fixture['clients'][0] as Map;
        final wrongServerPin = OperationalProofGrpcTransport.connect(
          binding: _fixturePin(fixture, 0),
          terminalSecret: c['terminalSecret'],
          host: '127.0.0.1',
          port: port,
          pinnedServerCertificate: base64Decode(fixture['clientCa']),
          terminalCertificate: base64Decode(c['certificate']),
          terminalPrivateKey: base64Decode(c['key']),
        );
        transports.add(wrongServerPin);
        await expectLater(
          wrongServerPin.status(),
          throwsA(
            isA<grpc.GrpcError>().having(
              (e) => e.code,
              'code',
              grpc.StatusCode.unavailable,
            ),
          ),
        );
        final base = _fixtureTransport(fixture, 8, port);
        transports.add(base);
        await expectLater(
          base.getResult(requestId: intent.requestId, epoch: 41),
          throwsA(
            isA<grpc.GrpcError>().having(
              (e) => e.code,
              'code',
              grpc.StatusCode.unauthenticated,
            ),
          ),
        );
        await reopenedBox.close();
        await otherBox.close();
      } finally {
        for (final transport in transports) {
          await transport.close();
        }
        await Hive.close();
        await File(
          '${dir.path}/gateway-stop',
        ).writeAsString('stop', flush: true);
        final exit = await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        final output = await stdout;
        final error = await stderr;
        await dir.delete(recursive: true);
        expect(exit, 0, reason: 'isolated Go fixture: $output $error');
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
