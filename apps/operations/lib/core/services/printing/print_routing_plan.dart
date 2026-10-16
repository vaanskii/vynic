import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'print_job.dart';
import 'printer_destination.dart';

/// Routing uses stable explicit destinations, never a name/keyword guess.
/// One line may intentionally target several stations; repeated IDs are invalid.
class RoutedPrintLine {
  RoutedPrintLine({
    required this.lineId,
    required this.text,
    required Iterable<String> printerIds,
  }) : printerIds = List<String>.unmodifiable(printerIds) {
    if (lineId.isEmpty ||
        lineId.length > 120 ||
        text.trim().isEmpty ||
        text.length > 2000 ||
        this.printerIds.isEmpty ||
        this.printerIds.toSet().length != this.printerIds.length) {
      throw ArgumentError(
        'Each print line needs stable identity and explicit unique destinations',
      );
    }
  }
  final String lineId;
  final String text;
  final List<String> printerIds;
}

class PlannedPrintTicket {
  PlannedPrintTicket._(this.jobId, this.route, Iterable<RoutedPrintLine> lines)
    : lines = List.unmodifiable(lines);
  final String jobId;
  final PrinterRoute route;
  final List<RoutedPrintLine> lines;
}

/// Detached preparation for a shared operation: rendering creates no Hive jobs
/// and performs no transport. The coordinator must commit the complete frozen
/// effect set atomically with the business operation before workers may dispatch.
class PrintRoutingPlan {
  PrintRoutingPlan._(
    this.effectId,
    this.venueId,
    Iterable<PlannedPrintTicket> tickets,
  ) : tickets = List.unmodifiable(tickets);
  final String effectId;
  final String venueId;
  final List<PlannedPrintTicket> tickets;

  factory PrintRoutingPlan.create({
    required String effectId,
    required String venueId,
    required List<RoutedPrintLine> lines,
    required List<PrinterRoute> routes,
  }) {
    if (effectId.isEmpty ||
        effectId.length > 120 ||
        venueId.isEmpty ||
        venueId.length > 120 ||
        lines.isEmpty ||
        lines.length > 1000 ||
        lines.map((line) => line.lineId).toSet().length != lines.length) {
      throw ArgumentError('Invalid immutable print effect identity or lines');
    }
    final catalog = {for (final route in routes) route.id: route};
    if (catalog.length != routes.length || catalog.length > 64) {
      throw ArgumentError('Printer catalog needs unique bounded identities');
    }
    final grouped = <String, List<RoutedPrintLine>>{};
    for (final line in lines) {
      for (final printerId in line.printerIds) {
        final route = catalog[printerId];
        if (route == null || route.role == PrinterRole.receipt) {
          throw StateError(
            'A production destination is missing or is a receipt route',
          );
        }
        (grouped[printerId] ??= []).add(line);
      }
    }
    final ids = grouped.keys.toList()..sort();
    return PrintRoutingPlan._(effectId, venueId, [
      for (final id in ids)
        PlannedPrintTicket._(
          'production-${sha256.convert(utf8.encode(jsonEncode([venueId, effectId, id])))}',
          catalog[id]!,
          grouped[id]!,
        ),
    ]);
  }

  Future<List<PrintJob>> freeze({
    required Future<List<int>> Function(PlannedPrintTicket ticket) render,
    String? requiresConfirmedOrderUuid,
  }) async {
    final jobs = <PrintJob>[];
    for (final ticket in tickets) {
      final payload = await render(ticket);
      jobs.add(
        PrintJob.create(
          id: ticket.jobId,
          target: switch (ticket.route.role) {
            PrinterRole.kitchen => PrintQueueTarget.kitchen,
            PrinterRole.bar => PrintQueueTarget.bar,
            PrinterRole.additional => PrintQueueTarget.additional,
            PrinterRole.receipt => throw StateError(
              'Receipt is not a production route',
            ),
          },
          destination: ticket.route.destination,
          printerId: ticket.route.id,
          routeRevision: ticket.route.revision,
          capabilityProfile: ticket.route.capabilityProfile,
          label: ticket.route.name,
          bytes: payload,
          venueId: venueId,
          requiresConfirmedOrderUuid: requiresConfirmedOrderUuid,
        ),
      );
    }
    return List.unmodifiable(jobs);
  }
}
