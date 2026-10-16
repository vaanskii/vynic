import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/printer_agent_client.dart';
import 'package:vynic/core/services/printing/printer_agent_profile.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart' as wire;

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
PrinterAgentPins pins() => PrinterAgentPins(
  scope: PrinterAgentScope.local,
  ownershipPolicy: 'localHost',
  clusterId: '',
  membershipSha256: '',
  role: 'posAgent',
  venueId: id(1),
  installationId: id(2),
  deviceId: id(3),
  hostId: id(4),
  gatewayHostId: id(4),
  authorityEpoch: 1,
  protocolVersion: 1,
  helperProtocolVersion: 1,
  databaseSchemaVersion: 6,
  minimumReaderVersion: 2,
  routeRevision: 1,
  configRevision: 1,
  registryRevision: 1,
  bindingRevision: 1,
  capabilityRevision: 1,
  capabilityProfileSha256: 'a' * 64,
  hostBinarySha256: 'b' * 64,
  helperBinarySha256: 'c' * 64,
);
const pem = '-----BEGIN CERTIFICATE-----\nAQID\n-----END CERTIFICATE-----\n';
PrinterAgentProfile profile() => PrinterAgentProfile(
  pins: pins(),
  clientId: id(5),
  currentDeviceInstallationId: id(22),
  port: 12345,
  pinnedServerCertificate: utf8.encode(pem),
);
Matcher failure(PrinterAgentFailure reason) =>
    isA<PrinterAgentException>().having((e) => e.reason, 'reason', reason);

wire.PrinterAgentHealthResponse healthMessage() {
  final p = pins();
  return wire.PrinterAgentHealthResponse(
    protocolVersion: 1,
    clientId: id(5),
    pins: wire.PrinterAgentPins(
      scope: 'LOCAL',
      ownershipPolicy: p.ownershipPolicy,
      clusterId: p.clusterId,
      membershipSha256: p.membershipSha256,
      role: p.role,
      venueId: p.venueId,
      installationId: p.installationId,
      deviceId: p.deviceId,
      hostId: p.hostId,
      gatewayHostId: p.gatewayHostId,
      authorityEpoch: Int64(p.authorityEpoch),
      protocolVersion: 1,
      helperProtocolVersion: 1,
      databaseSchemaVersion: 6,
      minimumReaderVersion: 2,
      routeRevision: Int64(1),
      configRevision: Int64(1),
      registryRevision: Int64(1),
      bindingRevision: Int64(1),
      capabilityRevision: Int64(1),
      capabilityProfileSha256: p.capabilityProfileSha256,
      hostBinarySha256: p.hostBinarySha256,
      helperBinarySha256: p.helperBinarySha256,
    ),
    state: wire.PrinterAgentLifecycle.PRINTER_AGENT_RUNNING,
    softwareReady: true,
    physicalState: wire.PrinterAgentPhysicalState.PRINTER_AGENT_PHYSICAL_HELD,
    admissionState: wire
        .PrinterAgentAdmissionState
        .PRINTER_AGENT_ADMISSION_HELD_PROVISIONING,
    holdReasons: [
      wire.PrinterAgentHoldReason.PRINTER_AGENT_PROVISIONING_UNQUALIFIED,
      wire.PrinterAgentHoldReason.PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING,
    ],
  );
}

class Observation implements X509Certificate {
  Observation(List<int> raw, this.startValidity, this.endValidity)
    : der = Uint8List.fromList(raw);
  @override
  final Uint8List der;
  @override
  final DateTime startValidity, endValidity;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('complete pins roundtrip exact values without granting admission', () {
    final p = pins();
    expect(p.matches(PrinterAgentPins.fromJson(p.toJson())), true);
    final h = PrinterAgentWireCodec(profile()).health(healthMessage());
    expect(h.softwareReady, true);
    expect(h.physicalHeld, true);
    expect(h.admissionHeld, true);
    expect(h.configuredScope, PrinterAgentScope.local);
  });
  for (final change in [
    'extra',
    'missing',
    'badType',
    'overflow',
    'derivedHost',
  ]) {
    test('explicit complete pin rejects $change', () {
      final p = pins().toJson();
      switch (change) {
        case 'extra':
          p['enabled'] = true;
        case 'missing':
          p.remove('hostId');
        case 'badType':
          p['configRevision'] = 1.0;
        case 'overflow':
          p['configRevision'] = -1;
        case 'derivedHost':
          p['hostId'] = id(2);
      }
      expect(
        () => PrinterAgentPins.fromJson(p),
        throwsA(failure(PrinterAgentFailure.invalidProfile)),
      );
    });
  }
  test('certificate and immutable retry bytes defensively copy', () {
    final bytes = utf8.encode(pem);
    final p = PrinterAgentProfile(
      pins: pins(),
      clientId: id(5),
      currentDeviceInstallationId: id(22),
      port: 12345,
      pinnedServerCertificate: bytes,
    );
    bytes[0] = 0;
    final other = p.pinnedServerCertificate;
    other[0] = 0;
    expect(utf8.decode(p.pinnedServerCertificate), pem);
    final raw = Uint8List.fromList([0, 255, 1, 27]);
    final intent = PrinterAgentLocalIntent(
      requestId: id(6),
      jobId: id(7),
      frozenEnvelope: raw,
    );
    final digest = intent.envelopeSha256;
    raw[0] = 8;
    intent.frozenEnvelope[1] = 9;
    expect(intent.frozenEnvelope, [0, 255, 1, 27]);
    expect(intent.envelopeSha256, digest);
  });
  for (final field in [
    'version',
    'client',
    'venue',
    'host',
    'route',
    'profile',
    'uint64',
    'state',
    'physical',
    'admission',
    'reason',
    'missingReason',
    'unknownWire',
    'nestedWire',
  ]) {
    test('wire refuses $field without reporting ready', () {
      final h = healthMessage();
      switch (field) {
        case 'version':
          h.protocolVersion = 2;
        case 'client':
          h.clientId = id(20);
        case 'venue':
          h.pins.venueId = id(20);
        case 'host':
          h.pins.hostId = id(20);
          h.pins.gatewayHostId = id(20);
        case 'route':
          h.pins.routeRevision = Int64(2);
        case 'profile':
          h.pins.capabilityProfileSha256 = 'd' * 64;
        case 'uint64':
          h.pins.authorityEpoch = Int64(-1);
        case 'state':
          h.state =
              wire.PrinterAgentLifecycle.PRINTER_AGENT_LIFECYCLE_UNSPECIFIED;
        case 'physical':
          h.physicalState =
              wire.PrinterAgentPhysicalState.PRINTER_AGENT_PHYSICAL_UNSPECIFIED;
        case 'admission':
          h.admissionState = wire
              .PrinterAgentAdmissionState
              .PRINTER_AGENT_ADMISSION_UNSPECIFIED;
        case 'reason':
          h.holdReasons.add(
            wire.PrinterAgentHoldReason.PRINTER_AGENT_HOLD_UNSPECIFIED,
          );
        case 'missingReason':
          h.holdReasons.clear();
        case 'unknownWire':
          h.mergeFromBuffer([0xf8, 0x07, 0x01]);
        case 'nestedWire':
          h.pins.mergeFromBuffer([0xf8, 0x07, 0x01]);
      }
      expect(
        () => PrinterAgentWireCodec(profile()).health(h),
        throwsA(isA<PrinterAgentException>()),
      );
    });
  }
  test('pin refuses alternate certificate, endpoint and time bounds', () {
    final pin = PrinterAgentCertificatePin(utf8.encode(pem));
    final now = DateTime.now();
    Observation c(List<int> bytes, DateTime start, DateTime end) =>
        Observation(bytes, start, end);
    expect(
      pin.matches(
        c(
          [1, 2, 3],
          now.subtract(const Duration(seconds: 1)),
          now.add(const Duration(seconds: 1)),
        ),
        printerAgentServerName,
      ),
      true,
    );
    expect(
      pin.matches(
        c(
          [1, 2, 4],
          now.subtract(const Duration(seconds: 1)),
          now.add(const Duration(seconds: 1)),
        ),
        printerAgentServerName,
      ),
      false,
    );
    expect(
      pin.matches(
        c(
          [1, 2, 3],
          now.subtract(const Duration(seconds: 1)),
          now.add(const Duration(seconds: 1)),
        ),
        'other.local',
      ),
      false,
    );
    expect(
      pin.matches(
        c(
          [1, 2, 3],
          now.add(const Duration(seconds: 1)),
          now.add(const Duration(seconds: 2)),
        ),
        printerAgentServerName,
      ),
      false,
    );
    expect(
      pin.matches(
        c(
          [1, 2, 3],
          now.subtract(const Duration(seconds: 2)),
          now.subtract(const Duration(seconds: 1)),
        ),
        printerAgentServerName,
      ),
      false,
    );
    final der = pin.der;
    der[0] = 0;
    expect(pin.der, [1, 2, 3]);
    expect(
      () => PrinterAgentCertificatePin(utf8.encode('$pem$pem')),
      throwsA(isA<PrinterAgentException>()),
    );
  });
  test(
    'actual child-process mTLS health, exact held retries and result refusal',
    () async {
      final binary = Platform.environment['VYNIC_PRINTER_AGENT_GO_FIXTURE'];
      if (binary == null)
        throw StateError(
          'Set VYNIC_PRINTER_AGENT_GO_FIXTURE to the isolated compiled printeragent test binary; real wire is required',
        );
      final dir = await Directory.systemTemp.createTemp('printer-agent-wire-');
      final process = await Process.start(
        binary,
        [r'-test.run=^TestPrinterAgentProcess$', '-test.v'],
        environment: {'VYNIC_PRINTER_AGENT_FIXTURE_DIR': dir.path},
      );
      final stdout = process.stdout.transform(utf8.decoder).join(),
          stderr = process.stderr.transform(utf8.decoder).join();
      final clients = <PrinterAgentClient>[];
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (!await File('${dir.path}/ready').exists()) {
          if (DateTime.now().isAfter(deadline)) {
            process.kill();
            throw StateError('printeragent fixture not ready');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final raw =
            jsonDecode(await File('${dir.path}/profile.json').readAsString())
                as Map<String, dynamic>;
        final p = PrinterAgentProfile(
          pins: PrinterAgentPins.fromJson(raw['pins'] as Map<String, dynamic>),
          clientId: raw['clientId'] as String,
          currentDeviceInstallationId:
              raw['currentDeviceInstallationId'] as String,
          port: int.parse((raw['listenAddress'] as String).split(':').last),
          pinnedServerCertificate: await File(
            raw['serverCertificatePath'] as String,
          ).readAsBytes(),
        );
        final cert = await File(
          raw['clientCertificatePath'] as String,
        ).readAsBytes();
        final key = await File(
          raw['clientPrivateKeyPath'] as String,
        ).readAsBytes();
        PrinterAgentClient open(PrinterAgentProfile p) {
          final c = PrinterAgentClient.connect(
            profile: p,
            clientCertificate: cert,
            clientKey: key,
          );
          clients.add(c);
          return c;
        }

        var client = open(p);
        expect(p.currentDeviceInstallationId, isNot(p.pins.installationId));
        expect(p.expectedInstallationId, p.currentDeviceInstallationId);
        expect(p.expectedAgentInstallationId, p.pins.installationId);
        final h = await client.health();
        expect(h.softwareReady, true);
        expect(h.physicalHeld, true);
        expect(h.admissionHeld, true);
        expect(h.pins.matches(p.pins), true);
        final envelope = await File('${dir.path}/envelope.json').readAsBytes();
        final body = jsonDecode(utf8.decode(envelope)) as Map;
        final intent = PrinterAgentLocalIntent(
          requestId: body['requestId'] as String,
          jobId: body['jobId'] as String,
          frozenEnvelope: envelope,
        );
        await expectLater(
          client.submitLocal(intent),
          throwsA(failure(PrinterAgentFailure.provisioningHeld)),
        );
        await client.close();
        client = open(p);
        await expectLater(
          client.submitLocal(intent),
          throwsA(failure(PrinterAgentFailure.provisioningHeld)),
        );
        await expectLater(
          client.getLocalResult(intent),
          throwsA(failure(PrinterAgentFailure.provisioningHeld)),
        );
        expect(intent.frozenEnvelope, envelope);
        final bad = PrinterAgentProfile(
          pins: p.pins,
          clientId: p.clientId,
          currentDeviceInstallationId: p.currentDeviceInstallationId,
          port: p.port,
          pinnedServerCertificate: cert,
        );
        await expectLater(
          open(bad).health(),
          throwsA(failure(PrinterAgentFailure.unavailable)),
        );
      } finally {
        for (final client in clients) {
          await client.close();
        }
        await File('${dir.path}/stop').writeAsString('stop', flush: true);
        final exit = await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        final out = await stdout, err = await stderr;
        await dir.delete(recursive: true);
        expect(exit, 0, reason: 'held printeragent fixture: $out $err');
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
