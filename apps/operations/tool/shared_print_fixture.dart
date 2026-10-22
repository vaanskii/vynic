import 'dart:convert';
import 'dart:io';

import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/shared_print_effect.dart';

String fixtureId(int value) =>
    '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';

PrintJob fixtureJob(PrinterDestination destination) => PrintJob.decode({
  'protocol': 2,
  'id': 'synthetic-frozen-ticket',
  'target': 'kitchen',
  'destination': destination.toMap(),
  'printerId': 'synthetic-kitchen-alias',
  'routeRevision': 11,
  'capabilityProfile': PrinterCapabilityProfile.genericEscposRaster(
    cutter: PrinterCutter.partial,
    beep: const PrinterBeepSettings(
      capability: PrinterBeepCapability.epsonEscA97Pattern,
      enabled: true,
    ),
  ).toMap(),
  'label': 'SYNTHETIC ONLY',
  'venueId': fixtureId(2),
  'createdAt': '2026-10-06T00:00:00.000Z',
  'payload': 'HXYwAAEAAQCAHVYB',
  'payloadSha256':
      'b6a0858547ca938f883974db311bf6ec7a7396c5fcfea8af8fc4b6d172aa1f31',
  'attempts': [
    {
      'id': 'synthetic-frozen-ticket',
      'state': 'queued',
      'queuedAt': '2026-10-06T00:00:00.000Z',
    },
  ],
  'audit': [
    {
      'action': 'queued',
      'at': '2026-10-06T00:00:00.000Z',
      'attemptId': 'synthetic-frozen-ticket',
    },
  ],
});

SharedPrintBinding fixtureBinding(PrinterDestination destination) =>
    SharedPrintBinding(
      venueId: fixtureId(2),
      installationId: fixtureId(1),
      originInstallationId: fixtureId(3),
      deviceId: fixtureId(4),
      physicalPrinterId: fixtureId(5),
      aliasId: fixtureId(6),
      workerHostId: fixtureId(7),
      authorityEpoch: 41,
      configRevision: 12,
      bindingRevision: 13,
      registryRevision: 14,
      routeId: 'synthetic-kitchen-alias',
      routeRevision: 11,
      destination: destination,
    );

FrozenSharedPrintEffect fixtureEffect(PrinterDestination destination) =>
    FrozenSharedPrintEffect.fromQueuedJob(
      job: fixtureJob(destination),
      binding: fixtureBinding(destination),
      jobId: fixtureId(8),
      effectId: fixtureId(9),
      requestId: fixtureId(10),
      terminalId: fixtureId(15),
      attemptId: fixtureId(16),
      beepAttemptId: fixtureId(17),
    );

/// Writes only synthetic envelopes for strict Go decoder interoperability. This
/// tool has no printer connection, Hive box, credentials or operational data.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('One task-local output directory is required');
  }
  final output = Directory(args.single)..createSync(recursive: true);
  final destinations = {
    'tcp': PrinterDestination.tcp(host: '192.168.10.20', port: 9100),
    'windowsSpooler': PrinterDestination.windowsSpooler(
      ownerDeviceId: fixtureId(4),
      queueName: 'SYNTHETIC ONLY',
      driverName: 'SYNTHETIC ESC POS',
      portName: 'USB_SYNTHETIC',
    ),
  };
  for (final entry in destinations.entries) {
    final effect = fixtureEffect(entry.value);
    File('${output.path}/${entry.key}.json').writeAsBytesSync(effect.payload);
    if (effect.toProofEffect().id != fixtureId(9)) {
      throw StateError('Effect identity changed');
    }
  }
  stdout.writeln(jsonEncode({'syntheticEnvelopes': destinations.length}));
}
