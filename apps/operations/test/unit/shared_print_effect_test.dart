import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/shared_print_effect.dart';
import '../../tool/shared_print_fixture.dart';

void main() {
  final tcp = PrinterDestination.tcp(host: '192.168.10.20', port: 9100);
  FrozenSharedPrintEffect freeze(
    PrintJob job, {
    SharedPrintBinding? binding,
    String? attemptId,
  }) => FrozenSharedPrintEffect.fromQueuedJob(
    job: job,
    binding: binding ?? fixtureBinding(tcp),
    jobId: fixtureId(8),
    effectId: fixtureId(9),
    requestId: fixtureId(10),
    terminalId: fixtureId(15),
    attemptId: attemptId ?? fixtureId(16),
    beepAttemptId: fixtureId(17),
  );

  test(
    'freezes exact original header, raster and cut without mutable references',
    () {
      final job = fixtureJob(tcp);
      final original = jsonEncode(job.toMap());
      final effect = freeze(job);
      final body = jsonDecode(utf8.decode(effect.payload)) as Map;
      final bytes = base64Decode(body['primaryBytes']);
      expect(bytes, job.transmissionBytes);
      expect(bytes.sublist(bytes.length - 3), [0x1d, 0x56, 0x01]);
      expect(body['primarySha256'], sha256.convert(bytes).toString());
      expect(body['jobId'], fixtureId(8));
      expect(body['originInstallationId'], fixtureId(3));
      expect(body['installationId'], fixtureId(1));
      expect(body['registryRevision'], 14);
      expect(body['destination']['workerHostId'], fixtureId(7));
      expect(jsonEncode(job.toMap()), original);
      expect(freeze(job).payload, effect.payload);
      expect(() => effect.payload[0] = 1, throwsUnsupportedError);
      expect(effect.toProofEffect().payload, effect.payload);
    },
  );

  test(
    'Windows identity includes exact frozen owner, queue, driver and port',
    () {
      final destination = PrinterDestination.windowsSpooler(
        ownerDeviceId: fixtureId(4),
        queueName: 'SYNTHETIC ONLY',
        driverName: 'SYNTHETIC ESC POS',
        portName: 'USB_SYNTHETIC',
      );
      final effect = fixtureEffect(destination);
      final body = jsonDecode(utf8.decode(effect.payload)) as Map;
      expect(body['destination'], {
        'physicalPrinterId': fixtureId(5),
        'workerHostId': fixtureId(7),
        'transport': 'windowsSpooler',
        'host': '',
        'port': 0,
        'queueName': 'SYNTHETIC ONLY',
        'expectedDriverName': 'SYNTHETIC ESC POS',
        'expectedPortName': 'USB_SYNTHETIC',
        'documentName': 'Vynic ${fixtureId(8)}',
      });
    },
  );

  test(
    'refuses a changed Venue or retargeted registry before producing effects',
    () {
      final changed = fixtureJob(tcp).toMap()..['venueId'] = fixtureId(99);
      expect(() => freeze(PrintJob.decode(changed)), throwsFormatException);
      final elsewhere = PrinterDestination.tcp(
        host: '192.168.10.21',
        port: 9100,
      );
      expect(
        () => freeze(fixtureJob(tcp), binding: fixtureBinding(elsewhere)),
        throwsFormatException,
      );
    },
  );

  test('refuses submitted, uncertain, copied and repeat attempts', () {
    for (final state in ['sent', 'uncertain']) {
      final body = fixtureJob(tcp).toMap();
      body['attempts'][0]['state'] = state;
      body['audit'].addAll([
        {
          'action': 'sending',
          'at': '2026-10-06T00:00:01.000Z',
          'attemptId': 'synthetic-frozen-ticket',
        },
        {
          'action': state,
          'at': '2026-10-06T00:00:02.000Z',
          'attemptId': 'synthetic-frozen-ticket',
        },
      ]);
      final decoded = PrintJob.decode(body);
      expect(decoded.state.name, state);
      expect(() => freeze(decoded), throwsFormatException);
    }
    final copied = fixtureJob(tcp).toMap()..['copyOf'] = 'original-ticket';
    copied['audit'][0].addAll({
      'copyOf': 'original-ticket',
      'actorId': 'synthetic-staff',
      'reason': 'synthetic copy only',
    });
    final decodedCopy = PrintJob.decode(copied);
    expect(decodedCopy.copyOf, 'original-ticket');
    expect(() => freeze(decodedCopy), throwsFormatException);
    final repeated = fixtureJob(tcp).toMap();
    repeated['attempts'][0]['state'] = 'sent';
    repeated['attempts'].add({
      'id': 'second-attempt',
      'state': 'reprint',
      'queuedAt': '2026-10-06T00:00:03.000Z',
      'actorId': 'synthetic-staff',
      'reason': 'synthetic repeat only',
    });
    repeated['audit'].addAll([
      {
        'action': 'sending',
        'at': '2026-10-06T00:00:01.000Z',
        'attemptId': 'synthetic-frozen-ticket',
      },
      {
        'action': 'sent',
        'at': '2026-10-06T00:00:02.000Z',
        'attemptId': 'synthetic-frozen-ticket',
      },
      {
        'action': 'reprint',
        'at': '2026-10-06T00:00:03.000Z',
        'attemptId': 'second-attempt',
        'actorId': 'synthetic-staff',
        'reason': 'synthetic repeat only',
      },
    ]);
    final decodedRepeat = PrintJob.decode(repeated);
    expect(decodedRepeat.attempts.length, 2);
    expect(() => freeze(decodedRepeat), throwsFormatException);
  });

  test(
    'requires explicit canonical attempt and matching enrolled USB Device',
    () {
      expect(
        () => freeze(fixtureJob(tcp), attemptId: 'implicit-or-legacy-id'),
        throwsFormatException,
      );
      final otherOwner = PrinterDestination.windowsSpooler(
        ownerDeviceId: fixtureId(99),
        queueName: 'SYNTHETIC ONLY',
        driverName: 'SYNTHETIC ESC POS',
        portName: 'USB_SYNTHETIC',
      );
      expect(() => fixtureBinding(otherOwner), throwsFormatException);
    },
  );

  test(
    'holds conditional and previously requeued tickets for explicit migration',
    () {
      final conditional = fixtureJob(tcp).toMap()
        ..['requiresConfirmedOrderUuid'] = fixtureId(91);
      final decodedConditional = PrintJob.decode(conditional);
      expect(decodedConditional.requiresConfirmedOrderUuid, fixtureId(91));
      expect(() => freeze(decodedConditional), throwsFormatException);
      final requeued = fixtureJob(tcp).toMap();
      requeued['audit'].addAll([
        {
          'action': 'sending',
          'at': '2026-10-06T00:00:01.000Z',
          'attemptId': 'synthetic-frozen-ticket',
        },
        {
          'action': 'failed',
          'at': '2026-10-06T00:00:02.000Z',
          'attemptId': 'synthetic-frozen-ticket',
        },
        {
          'action': 'queued',
          'at': '2026-10-06T00:00:03.000Z',
          'attemptId': 'synthetic-frozen-ticket',
          'actionId': 'synthetic-operator-decision',
          'actorId': 'synthetic-staff',
          'reason': 'synthetic retry only',
        },
      ]);
      final decodedRequeued = PrintJob.decode(requeued);
      expect(decodedRequeued.state, PrintJobState.queued);
      expect(decodedRequeued.attempts.length, 1);
      expect(() => freeze(decodedRequeued), throwsFormatException);
      final started = fixtureJob(tcp).toMap();
      started['attempts'][0]['detail'] = 'original attempt touched transport';
      expect(() => freeze(PrintJob.decode(started)), throwsFormatException);
    },
  );

  test(
    'holds stale or different local alias mappings even at the same endpoint',
    () {
      final stale = fixtureJob(tcp).toMap()..['routeRevision'] = 10;
      expect(() => freeze(PrintJob.decode(stale)), throwsFormatException);
      final otherAlias = fixtureJob(tcp).toMap()
        ..['printerId'] = 'another-alias';
      expect(() => freeze(PrintJob.decode(otherAlias)), throwsFormatException);
    },
  );
}
