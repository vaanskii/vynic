import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:vynic/core/services/printing/station_print_plan.dart';

/// Disposable Go/Dart interoperability input/output; never accesses a printer.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('Input and output paths required');
  final input =
      jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
  final raw = utf8.encode(jsonEncode(input['catalog']));
  final catalog = StationRoutingCatalog.decode(
    raw: raw,
    expectedDigest: sha256.convert(raw).toString(),
    venueId: input['catalog']['venueId'],
    sourceDeviceId: input['catalog']['sourceDeviceId'],
  );
  final results = <Map<String, dynamic>>[];
  for (final scenario in input['scenarios'] as List) {
    try {
      final plan = catalog.plan(
        effectId: scenario['effect'],
        orderType: scenario['orderType'],
        outputKind: scenario['kind'],
        businessRef: 'შეკვეთა <1> & bar',
        createdAt: 1791800000000,
        lines: [
          for (final line in scenario['lines'] as List)
            StationPrintLine(
              id: line['ID'],
              itemId: line['ItemID'],
              subcategoryId: line['SubcategoryID'],
              categoryId: line['CategoryID'],
              stationIds: List<String>.from(line['Stations'] ?? []),
            ),
        ],
      );
      final jobs = await plan.freeze(
        render: (ticket) async => utf8.encode(
          'სინთეზური ${ticket.lines.map((line) => line.id).join(',')}',
        ),
      );
      results.add({
        'outputs': [
          for (final ticket in plan.tickets)
            {
              'JobID': ticket.jobId,
              'StationID': ticket.station.id,
              'LineIDs': ticket.lines.map((line) => line.id).toList(),
            },
        ],
        'jobs': [for (final job in jobs) utf8.decode(job.bytes)],
        'digests': [for (final job in jobs) job.digest],
      });
    } on StationPlanningException catch (error) {
      results.add({'error': error.reason.name});
    }
  }
  await File(args[1]).writeAsString(jsonEncode(results), flush: true);
}
