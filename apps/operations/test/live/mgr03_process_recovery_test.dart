import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/models/table.dart';
import '../support/pos03_fixture.dart';
import '../unit/mgr03_edge_operation_test.dart'
    show mgr03Payload, mgr03CommandId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['MGR03_PROCESS_DIRECTORY'];
  test('MGR03 owned native SIGKILL/restart operation honesty', () async {
    if (root == null) return;
    final path = Directory(root).absolute.path;
    if (!path.contains('vynic_mgr03_process_'))
      throw StateError('Owned synthetic recovery directory required');
    final stage = Platform.environment['MGR03_PROCESS_STAGE']!,
        kind = Platform.environment['MGR03_PROCESS_KIND']!;
    final fixture = Pos03Fixture();
    await fixture.open(path);
    final payload = mgr03Payload(kind);
    final acks = <Map<String, dynamic>>[];
    final transport = EdgeTransportService(
      client: EdgeTransportClient(
        baseUrl: () => 'http://synthetic.invalid',
        credential: () =>
            'vynic-device-v1.11111111-1111-4111-8111-111111111111.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/claim'))
            return http.Response(
              jsonEncode({
                'contractVersion': 2,
                'commands': [
                  {
                    'contractVersion': 2,
                    'commandId': mgr03CommandId,
                    'type': 'MANAGER_OPERATION',
                    'payload': payload,
                    'idempotencyKey': 'synthetic-operation',
                    'attempt': 1,
                    'issuedAt': '2026-10-07T10:00:00Z',
                    'leaseExpiresAt': '2026-10-07T10:02:00Z',
                  },
                ],
              }),
              200,
            );
          acks.add(Map<String, dynamic>.from(jsonDecode(r.body)));
          return http.Response('{}', 200);
        }),
      ),
    );
    if (stage == 'writer' || stage == 'boundaries') {
      await fixture.seed();
      // Dine-in creation uses a real free table from the seeded destination.
      if (kind == 'dine_in_create')
        await DatabaseCore.tableBox!.put(
          'free',
          TableModel(tableNumber: '19', floor: 'first'),
        );
      await EdgeCommandJournal.open();
      EdgeCommandJournal.wrapBoxForTest(
        (b) => _JournalBoundary(b, fixture.boundary),
      );
      fixture.trace.clear();
      if (stage == 'writer') {
        final target = int.parse(Platform.environment['MGR03_CHECKPOINT']!);
        fixture.fault = (point, position) async {
          if (position != target) return;
          for (final b in [
            DatabaseCore.metaBox!,
            DatabaseCore.tableBox!,
            DatabaseCore.orderBox!,
            DatabaseCore.reservationBox!,
            DatabaseCore.auditLogBox!,
          ]) {
            await (b as Pos03Box).inner.flush();
          }
          await _JournalBoundary.innerBox!.flush();
          final journal = EdgeCommandJournal.snapshot()[mgr03CommandId];
          await File('$path/ready.tmp').writeAsString(
            jsonEncode({
              'pid': pid,
              'checkpoint': target,
              'point': point,
              'journalStatus': journal?['status'],
              'httpBlocked': true,
              'boxesClosed': false,
              'kind': kind,
            }),
            flush: true,
          );
          await File('$path/ready.tmp').rename('$path/ready.json');
          await Completer<void>().future;
        };
      }
      await transport.pollOnce();
      if (stage == 'writer')
        fail('Owned orchestrator must SIGKILL this writer');
      expect(acks.single['status'], 'SUCCEEDED');
      await File('$path/boundaries.json').writeAsString(
        jsonEncode({'pid': pid, 'trace': fixture.trace}),
        flush: true,
      );
    } else if (stage == 'reader') {
      final ready =
          jsonDecode(await File('$path/ready.json').readAsString()) as Map;
      await EdgeCommandJournal.open();
      await transport.pollOnce();
      final uncertain =
          kind.startsWith('reservation_') &&
          ready['journalStatus'] != null &&
          ready['journalStatus'] != 'succeeded';
      expect(acks.single['status'], uncertain ? 'FAILED' : 'SUCCEEDED');
      if (uncertain)
        expect(acks.single['code'], 'manager_operation_outcome_unknown');
      // A retained result must not overwrite a later local edit or status.
      if (kind == 'takeaway_create' || kind == 'dine_in_create') {
        final order = OrderRepository.getOrder(90001)!
          ..customerName = 'Later local edit';
        await order.save();
      }
      if (kind.startsWith('reservation_')) {
        for (final r in DatabaseCore.reservationBox!.values.toList()) {
          r.status = 'cancelled';
          await r.save();
        }
      }
      final audit = DatabaseCore.auditLogBox!.toMap(),
          reservations = DatabaseCore.reservationBox!.values
              .map((r) => '${r.id}:${r.status}')
              .toList();
      await EdgeCommandJournal.prune();
      await transport.pollOnce();
      expect(acks.last['status'], acks.first['status']);
      expect(DatabaseCore.auditLogBox!.toMap(), audit);
      expect(
        DatabaseCore.reservationBox!.values
            .map((r) => '${r.id}:${r.status}')
            .toList(),
        reservations,
      );
      if (kind == 'takeaway_create' || kind == 'dine_in_create')
        expect(
          OrderRepository.getOrder(90001)!.customerName,
          'Later local edit',
        );
      await File('$path/result.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'readerPid': pid,
          'writerPid': ready['pid'],
          'kind': kind,
          'outcome': acks.first['status'],
          'code': acks.first['code'],
          'laterLocalWorkPreserved': true,
          'journalStatus': EdgeCommandJournal.entryFor(
            mgr03CommandId,
          )!.status.name,
        }),
        flush: true,
      );
    }
    await EdgeCommandJournal.close();
    await fixture.close();
  });
}

class _JournalBoundary extends UpdateTrackedBox<Map> {
  _JournalBoundary(super.inner, this.boundary) {
    innerBox = inner;
  }
  static dynamic innerBox;
  final Future<void> Function(String) boundary;
  @override
  Future<void> put(dynamic key, Map value) async {
    await boundary('edge.put:${value['status']}:before');
    await super.put(key, value);
    await boundary('edge.put:${value['status']}:after');
  }

  @override
  Future<void> flush() async {
    await boundary('edge.flush:before');
    await super.flush();
    await boundary('edge.flush:after');
  }
}
