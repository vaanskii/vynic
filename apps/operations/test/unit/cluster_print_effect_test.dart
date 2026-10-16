import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/cluster_print_effect.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';

import '../../tool/cluster_print_fixture.dart';
import '../../tool/shared_print_fixture.dart';

void main() {
  final tcp = PrinterDestination.tcp(host: '192.168.10.20', port: 9100);
  FrozenClusterPrintEffect freeze(
    PrintJob job,
    RetainedClusterPrinterConfig cfg,
  ) => FrozenClusterPrintEffect.fromQueuedJob(
    job: job,
    config: cfg,
    jobId: fixtureId(8),
    effectId: fixtureId(9),
    requestId: fixtureId(10),
    originTerminalId: fixtureId(15),
    originInstallationId: fixtureId(3),
  );

  test('cluster job pins exact config and bytes without electing a writer', () {
    final cfg = clusterConfig(tcp);
    final frozen = freeze(fixtureJob(tcp), cfg);
    final body = jsonDecode(utf8.decode(frozen.payload)) as Map;
    expect(body.length, 19);
    expect(body['version'], 2);
    expect(body['scope'], 'VENUE_SHARED');
    expect(body['configSha256'], sha256.convert(cfg.raw).toString());
    expect(
      base64Decode(body['primaryBytes']),
      fixtureJob(tcp).transmissionBytes,
    );
    expect(body['reprintOf'], isNull);
    expect(body.containsKey('workerHostId'), isFalse);
    expect(body.containsKey('attemptId'), isFalse);
    expect(body.containsKey('leaderTerm'), isFalse);
    expect(freeze(fixtureJob(tcp), cfg).payload, frozen.payload);
    expect(() => frozen.payload[0] = 1, throwsUnsupportedError);
  });

  test('scope is independent of TCP versus Windows transport', () {
    expect(clusterConfig(tcp, scope: 'LOCAL').scope, PrinterScope.local);
    final local = jsonDecode(
      utf8.decode(clusterEffect(tcp, scope: 'LOCAL').payload),
    );
    expect(local['scope'], 'LOCAL');
    final windows = PrinterDestination.windowsSpooler(
      ownerDeviceId: fixtureId(4),
      queueName: 'SYNTHETIC ONLY',
      driverName: 'SYNTHETIC ESC POS',
      portName: 'USB_SYNTHETIC',
    );
    expect(clusterConfig(windows).scope, PrinterScope.venueShared);
    expect(clusterEffect(windows).payload, isNotEmpty);
  });

  test('a changed retained receipt or unsupported scope is refused', () {
    final raw = utf8.encode(jsonEncode(clusterConfigBody(tcp)));
    expect(
      () => RetainedClusterPrinterConfig.decode(
        raw: raw,
        expectedSha256: '0' * 64,
        sourceRouteId: 'synthetic-kitchen-alias',
      ),
      throwsFormatException,
    );
    final body = clusterConfigBody(tcp)..['scope'] = 'FIRST_DISCOVERED';
    final changed = utf8.encode(jsonEncode(body));
    expect(
      () => RetainedClusterPrinterConfig.decode(
        raw: changed,
        expectedSha256: sha256.convert(changed).toString(),
        sourceRouteId: 'synthetic-kitchen-alias',
      ),
      throwsFormatException,
    );
  });

  test(
    'retarget, stale alias/revision, profile and role changes cannot freeze',
    () {
      final config = clusterConfig(tcp);
      for (final entry in {
        'printerId': 'another-alias',
        'routeRevision': 10,
        'target': 'bar',
      }.entries) {
        final body = fixtureJob(tcp).toMap()..[entry.key] = entry.value;
        final decoded = PrintJob.decode(body);
        expect(() => freeze(decoded, config), throwsFormatException);
      }
      final elsewhere = PrinterDestination.tcp(
        host: '192.168.10.21',
        port: 9100,
      );
      expect(
        () => freeze(fixtureJob(elsewhere), config),
        throwsFormatException,
      );
      final profile = fixtureJob(tcp).toMap();
      profile['capabilityProfile']['rasterWidthDots'] = 384;
      final decodedProfile = PrintJob.decode(profile);
      expect(() => freeze(decodedProfile, config), throwsFormatException);
    },
  );

  test(
    'TCP ownership cannot transfer between local Device and shared cluster',
    () {
      for (final scope in ['LOCAL', 'VENUE_SHARED']) {
        final body = clusterConfigBody(tcp, scope: scope);
        body['ownership'] = {
          'generation': 13,
          'kind': scope == 'LOCAL' ? 'cluster' : 'device',
          'ownerId': scope == 'LOCAL' ? fixtureId(20) : fixtureId(4),
        };
        final raw = utf8.encode(jsonEncode(body));
        expect(
          () => RetainedClusterPrinterConfig.decode(
            raw: raw,
            expectedSha256: sha256.convert(raw).toString(),
            sourceRouteId: 'synthetic-kitchen-alias',
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unknown optional sound preserves primary and exact retained config',
    () {
      final body = clusterConfigBody(tcp);
      body['capabilityProfile']['beep'] = {
        'capability': 'futureUnqualifiedSound',
        'enabled': true,
      };
      final raw = utf8.encode(jsonEncode(body));
      final cfg = RetainedClusterPrinterConfig.decode(
        raw: raw,
        expectedSha256: sha256.convert(raw).toString(),
        sourceRouteId: 'synthetic-kitchen-alias',
      );
      final ticket = fixtureJob(tcp).toMap();
      ticket['capabilityProfile'] = body['capabilityProfile'];
      final job = PrintJob.decode(ticket);
      final frozen = jsonDecode(utf8.decode(freeze(job, cfg).payload));
      expect(frozen['configSha256'], sha256.convert(raw).toString());
      expect(frozen['capabilityProfile']['beep'], {
        'capability': 'unknown',
        'enabled': false,
      });
      expect(base64Decode(frozen['primaryBytes']), job.transmissionBytes);
    },
  );

  test('configuration receipt retains detached immutable bytes', () {
    final raw = utf8.encode(jsonEncode(clusterConfigBody(tcp)));
    final cfg = RetainedClusterPrinterConfig.decode(
      raw: raw,
      expectedSha256: sha256.convert(raw).toString(),
      sourceRouteId: 'synthetic-kitchen-alias',
    );
    final before = freeze(fixtureJob(tcp), cfg).payload;
    raw[0] = 0;
    expect(freeze(fixtureJob(tcp), cfg).payload, before);
    expect(() => cfg.raw[0] = 0, throwsUnsupportedError);
  });
}
