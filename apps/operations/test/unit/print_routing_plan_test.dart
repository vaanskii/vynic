import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/print_routing_plan.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/print_job.dart';

PrinterRoute route(
  String id,
  String role, {
  int revision = 1,
  int port = 9100,
}) => PrinterRoute.decode({
  'protocol': 1,
  'id': id,
  'name': id,
  'role': role,
  'revision': revision,
  'destination': PrinterDestination.tcp(host: '10.0.0.4', port: port).toMap(),
});
void main() {
  final kitchen = route('kitchen-1', 'kitchen'),
      bar = route('bar-1', 'bar'),
      extra = route('station-1', 'additional');
  PrintRoutingPlan plan(
    List<RoutedPrintLine> lines, {
    List<PrinterRoute>? routes,
  }) => PrintRoutingPlan.create(
    effectId: 'confirmation-1',
    venueId: 'venue-1',
    lines: lines,
    routes: routes ?? [kitchen, bar, extra],
  );
  test(
    'three destinations receive exact intentional line groups without dispatch',
    () async {
      final p = plan([
        RoutedPrintLine(
          lineId: 'food',
          text: '2x Food',
          printerIds: ['kitchen-1', 'station-1'],
        ),
        RoutedPrintLine(
          lineId: 'drink',
          text: '1x Drink',
          printerIds: ['bar-1'],
        ),
      ]);
      final seen = <String, List<String>>{};
      final jobs = await p.freeze(
        render: (ticket) async {
          seen[ticket.route.id] = ticket.lines
              .map((line) => line.lineId)
              .toList();
          return [1, 2, 3];
        },
      );
      expect(seen, {
        'bar-1': ['drink'],
        'kitchen-1': ['food'],
        'station-1': ['food'],
      });
      expect(jobs.map((job) => job.id).toSet(), hasLength(3));
      expect(jobs.every((job) => job.protocolVersion == 2), true);
      expect(
        jobs.map((job) => job.target),
        containsAll([
          PrintQueueTarget.kitchen,
          PrintQueueTarget.bar,
          PrintQueueTarget.additional,
        ]),
      );
    },
  );
  test(
    'effect/printer identity remains stable across catalog order and edits',
    () {
      final lines = [
        RoutedPrintLine(
          lineId: 'food',
          text: 'Food',
          printerIds: ['kitchen-1'],
        ),
      ];
      final first = plan(lines).tickets.single;
      final changed = plan(
        lines,
        routes: [
          extra,
          bar,
          route('kitchen-1', 'kitchen', revision: 2, port: 9200),
        ],
      ).tickets.single;
      expect(
        first.jobId,
        changed.jobId,
      ); // Same effect cannot masquerade as a new print after route edits.
      expect(first.route.revision, 1);
      expect(first.route.destination.port, 9100);
      expect(changed.route.destination.port, 9200);
    },
  );
  test('missing/receipt destinations and repeated line identities refuse', () {
    for (final id in ['unknown', 'receipt-1']) {
      expect(
        () => plan(
          [
            RoutedPrintLine(lineId: 'x', text: 'X', printerIds: [id]),
          ],
          routes: [route('receipt-1', 'receipt')],
        ),
        throwsStateError,
      );
    }
    final line = RoutedPrintLine(
      lineId: 'x',
      text: 'X',
      printerIds: ['kitchen-1'],
    );
    expect(() => plan([line, line]), throwsArgumentError);
    expect(
      () => RoutedPrintLine(
        lineId: 'x',
        text: 'X',
        printerIds: ['kitchen-1', 'kitchen-1'],
      ),
      throwsArgumentError,
    );
  });
  test('a rendering failure returns no partial effect set', () async {
    final p = plan([
      RoutedPrintLine(
        lineId: 'x',
        text: 'X',
        printerIds: ['bar-1', 'kitchen-1'],
      ),
    ]);
    var calls = 0;
    await expectLater(
      p.freeze(
        render: (ticket) async {
          if (++calls == 2) throw StateError('render failed');
          return [1];
        },
      ),
      throwsStateError,
    );
    expect(calls, 2);
  });
}
