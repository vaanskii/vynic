import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/order_edit_repository.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/edge/noop_edge_command_handler.dart';
import 'package:vynic/core/services/edge/pos_edge_command_handlers.dart';
import '../support/pos03_fixture.dart';
import 'mgr05_order_edit_test.dart' show seedMgr05, mgr05Id;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  late Map<String, dynamic> payload;
  const credential =
      'vynic-device-v1.11111111-1111-4111-8111-111111111111.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr05-edge-');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    payload = (await seedMgr05(fixture))..remove('_mutationRequestId');
    EdgeDeviceCredentialStore.directoryOverride = dir.path;
    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential);
  });
  tearDown(() async {
    await EdgeCommandJournal.close();
    await fixture.close();
    LocalDataAdmission.failure = null;
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    await dir.delete(recursive: true);
  });
  final acks = <Map<String, dynamic>>[];
  EdgeTransportService service({bool older = false}) => EdgeTransportService(
    client: EdgeTransportClient(
      baseUrl: () => 'http://synthetic.invalid',
      credential: () => credential,
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/claim'))
          return http.Response(
            jsonEncode({
              'contractVersion': 2,
              'commands': [
                {
                  'contractVersion': 2,
                  'commandId': mgr05Id,
                  'type': 'ORDER_EDIT',
                  'payload': payload,
                  'idempotencyKey': 'synthetic-edit',
                  'attempt': 1,
                  'issuedAt': '2026-10-07T10:00:00Z',
                  'leaseExpiresAt': '2026-10-07T10:02:00Z',
                },
              ],
            }),
            200,
          );
        acks.add(Map<String, dynamic>.from(jsonDecode(r.body)));
        return http.Response('{}', acks.length == 1 ? 503 : 200);
      }),
    ),
    registry: EdgeCommandRegistry(
      older ? const [NoopEdgeCommandHandler()] : const [OrderEditEdgeHandler()],
    ),
  );
  for (final prune in [false, true])
    test(
      'lost ACK retains frozen result and later edit with prune=$prune',
      () async {
        acks.clear();
        final transport = service();
        await transport.start();
        try {
          await transport.pollOnce();
          expect(acks.single['code'], 'order_edited');
          final first = acks.single['resultProjection'];
          final order = DatabaseCore.orderBox!.get('source')!
            ..items.single.comment = 'later edit';
          await DatabaseCore.orderBox!.put('source', order);
          final audit = DatabaseCore.auditLogBox!.toMap();
          if (prune) {
            await EdgeCommandJournal.close();
            await File('${dir.path}/edge_command_journal.hive').delete();
          } else {
            final rows = EdgeCommandJournal.snapshot();
            rows[mgr05Id] = {
              '...': null,
              ...rows[mgr05Id]!,
              'resultProjection': {'hostile': 'transport result'},
            };
            await EdgeCommandJournal.restoreSnapshot(rows);
          }
          await transport.pollOnce();
          expect(acks.last['resultProjection'], first);
          expect(acks.last['status'], 'SUCCEEDED');
          expect(
            DatabaseCore.orderBox!.get('source')!.items.single.comment,
            'later edit',
          );
          expect(DatabaseCore.auditLogBox!.toMap(), audit);
        } finally {
          await transport.stop();
        }
      },
    );
  for (final point in ['orders.flush:after', 'audit.flush:after'])
    test(
      'transport interruption $point remains unresolved until startup recovery',
      () async {
        acks.clear();
        var hit = false;
        fixture.fault = (p, _) async {
          if (!hit && p == point) {
            hit = true;
            throw StateError('Synthetic interruption');
          }
        };
        final first = service();
        await first.start();
        await first.pollOnce();
        expect(hit, isTrue);
        expect(acks, isEmpty);
        expect(EdgeCommandJournal.entryFor(mgr05Id)!.isTerminal, isFalse);
        await first.shutdown();
        await fixture.close();
        await fixture.open(dir.path);
        final second = service();
        await second.start();
        try {
          await second.pollOnce();
          expect(acks.single['status'], 'SUCCEEDED');
          expect(acks.single['code'], 'order_edited');
          expect(OrderEditRepository.records().single['phase'], 'completed');
        } finally {
          await second.stop();
        }
      },
    );
  for (final after in [false, true])
    test(
      'transport completion write failure after native success has no FAILED ACK, after=$after',
      () async {
        acks.clear();
        final first = service();
        await first.start();
        EdgeCommandJournal.wrapBoxForTest((box) => _FailCompletion(box, after));
        await first.pollOnce();
        expect(acks, isEmpty);
        expect(OrderEditRepository.records().single['phase'], 'completed');
        expect(
          EdgeCommandJournal.entryFor(mgr05Id)!.status,
          isNot(EdgeExecutionStatus.failed),
        );
        await first.shutdown();
        await fixture.close();
        await fixture.open(dir.path);
        final second = service();
        await second.start();
        try {
          await second.pollOnce();
          expect(acks.single['status'], 'SUCCEEDED');
          expect(acks.single['code'], 'order_edited');
        } finally {
          await second.stop();
        }
      },
    );
  test('old registry fails additive edit before native mutation', () async {
    acks.clear();
    final transport = service(older: true);
    await transport.start();
    try {
      await transport.pollOnce();
      expect(acks.single['code'], 'unsupported_command_type');
      expect(DatabaseCore.orderBox!.get('source')!.items.single.quantity, 4);
      expect(OrderEditRepository.records(), isEmpty);
    } finally {
      await transport.stop();
    }
  });
}

class _FailCompletion extends UpdateTrackedBox<Map> {
  _FailCompletion(super.inner, this.after);
  final bool after;
  @override
  Future<void> put(dynamic key, Map value) async {
    if (value['status'] == 'succeeded') {
      if (after) await super.put(key, value);
      throw StateError('Synthetic journal completion write failure');
    }
    await super.put(key, value);
  }
}
