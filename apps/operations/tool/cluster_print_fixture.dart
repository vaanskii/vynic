import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:vynic/core/services/printing/cluster_print_effect.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';

import 'shared_print_fixture.dart';

Map<String, dynamic> clusterConfigBody(
  PrinterDestination destination, {
  String scope = 'VENUE_SHARED',
}) => {
  'version': 1,
  'scope': scope,
  'clusterId': fixtureId(20),
  'venueId': fixtureId(2),
  'physicalPrinterId': fixtureId(5),
  'routeId': fixtureId(6),
  'role': 'kitchen',
  'routeRevision': 11,
  'configRevision': 12,
  'ownership': {
    'generation': 13,
    'kind':
        scope == 'VENUE_SHARED' && destination.kind == PrinterTransportKind.tcp
        ? 'cluster'
        : 'device',
    'ownerId':
        scope == 'VENUE_SHARED' && destination.kind == PrinterTransportKind.tcp
        ? fixtureId(20)
        : fixtureId(4),
  },
  'destination': destination.toMap(),
  'capabilityProfile': fixtureJob(destination).capabilityProfile.toMap(),
};

RetainedClusterPrinterConfig clusterConfig(
  PrinterDestination destination, {
  String scope = 'VENUE_SHARED',
}) {
  final raw = utf8.encode(
    jsonEncode(clusterConfigBody(destination, scope: scope)),
  );
  return RetainedClusterPrinterConfig.decode(
    raw: raw,
    expectedSha256: sha256.convert(raw).toString(),
    sourceRouteId: 'synthetic-kitchen-alias',
  );
}

FrozenClusterPrintEffect clusterEffect(
  PrinterDestination destination, {
  String scope = 'VENUE_SHARED',
}) => FrozenClusterPrintEffect.fromQueuedJob(
  job: fixtureJob(destination),
  config: clusterConfig(destination, scope: scope),
  jobId: fixtureId(8),
  effectId: fixtureId(9),
  requestId: fixtureId(10),
  originTerminalId: fixtureId(15),
  originInstallationId: fixtureId(3),
);

/// Isolated interoperability goldens. No RPC, printer or credentials exist.
void main(List<String> args) {
  if (args.length != 1)
    throw ArgumentError('One task-local directory required');
  final output = Directory(args.single)..createSync(recursive: true);
  final tcp = PrinterDestination.tcp(host: '192.168.10.20', port: 9100);
  final windows = PrinterDestination.windowsSpooler(
    ownerDeviceId: fixtureId(4),
    queueName: 'SYNTHETIC ONLY',
    driverName: 'SYNTHETIC ESC POS',
    portName: 'USB_SYNTHETIC',
  );
  for (final entry in {
    'shared_tcp': tcp,
    'local_tcp': tcp,
    'shared_usb': windows,
  }.entries) {
    final scope = entry.key == 'local_tcp' ? 'LOCAL' : 'VENUE_SHARED';
    final config = clusterConfig(entry.value, scope: scope);
    File(
      '${output.path}/${entry.key}.config.json',
    ).writeAsBytesSync(config.raw);
    File(
      '${output.path}/${entry.key}.job.json',
    ).writeAsBytesSync(clusterEffect(entry.value, scope: scope).payload);
  }
  final unknownSoundBody = clusterConfigBody(tcp);
  unknownSoundBody['capabilityProfile']['beep'] = {
    'capability': 'futureUnqualifiedSound',
    'enabled': true,
  };
  final raw = utf8.encode(jsonEncode(unknownSoundBody));
  final config = RetainedClusterPrinterConfig.decode(
    raw: raw,
    expectedSha256: sha256.convert(raw).toString(),
    sourceRouteId: 'synthetic-kitchen-alias',
  );
  final ticket = fixtureJob(tcp).toMap();
  ticket['capabilityProfile'] = unknownSoundBody['capabilityProfile'];
  final effect = FrozenClusterPrintEffect.fromQueuedJob(
    job: PrintJob.decode(ticket),
    config: config,
    jobId: fixtureId(8),
    effectId: fixtureId(9),
    requestId: fixtureId(10),
    originTerminalId: fixtureId(15),
    originInstallationId: fixtureId(3),
  );
  File('${output.path}/unknown_beep.config.json').writeAsBytesSync(config.raw);
  File('${output.path}/unknown_beep.job.json').writeAsBytesSync(effect.payload);
  stdout.writeln(jsonEncode({'syntheticConfigJobPairs': 4}));
}
