import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/edge/noop_edge_command_handler.dart';
import 'package:vynic/core/services/edge/pos_edge_command_handlers.dart';
import '../support/pos03_fixture.dart';
import 'mgr02_table_repair_test.dart' show seedMgr02, mgr02RequestId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  late Map<String, dynamic> payload;
  const credential =
      'vynic-device-v1.11111111-1111-4111-8111-111111111111.'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr02-edge-');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await fixture.seed();
    payload = (await seedMgr02())..remove('_mutationRequestId');
    EdgeDeviceCredentialStore.directoryOverride = dir.path;
    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential);
  });
  tearDown(() async {
    await EdgeCommandJournal.close();
    await fixture.close();
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    await dir.delete(recursive: true);
  });
  Future<void> exercise({
    required bool olderRegistry,
    required bool pruneJournal,
  }) async {
    final acks = <Map<String, dynamic>>[];
    final service = EdgeTransportService(
      client: EdgeTransportClient(
        baseUrl: () => 'http://synthetic.invalid',
        credential: () => credential,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/claim'))
            return http.Response(
              jsonEncode({
                'contractVersion': edgeCommandContractVersion,
                'commands': [
                  {
                    'contractVersion': edgeCommandContractVersion,
                    'commandId': mgr02RequestId,
                    'type': EdgeCommandTypes.tableRepair,
                    'payload': payload,
                    'idempotencyKey': 'synthetic-repair',
                    'attempt': acks.length + 1,
                    'issuedAt': '2026-10-07T10:00:00Z',
                    'leaseExpiresAt': '2026-10-07T10:02:00Z',
                  },
                ],
              }),
              200,
            );
          acks.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          return http.Response('{}', acks.length == 1 ? 503 : 200);
        }),
      ),
      registry: EdgeCommandRegistry(
        olderRegistry
            ? const [NoopEdgeCommandHandler()]
            : const [TableRepairEdgeHandler()],
      ),
    );
    await service.start();
    try {
      final first = await service.pollOnce();
      if (olderRegistry) {
        expect(first.executed, 0);
        expect(first.skippedUnsupported, 1);
        expect(acks.single['code'], 'unsupported_command_type');
        expect(acks.single['status'], 'FAILED');
        expect(DatabaseCore.auditLogBox!.length, 0);
        expect(
          DatabaseCore.tableBox!.values
              .singleWhere((t) => t.tableNumber == '7')
              .activeOrderId,
          999,
        );
        return;
      }
      expect(first.executed, 1);
      expect(first.acknowledged, 0);
      expect(acks.single['code'], 'table_repaired');
      final key = DatabaseCore.tableBox!
          .toMap()
          .entries
          .singleWhere((e) => e.value.tableNumber == '7')
          .key;
      await DatabaseCore.tableBox!.put(
        key,
        TableModel(
          floor: 'first',
          tableNumber: '7',
          isReserved: true,
          activeOrderId: 222,
        ),
      );
      if (pruneJournal) {
        await EdgeCommandJournal.close();
        await File('${dir.path}/edge_command_journal.hive').delete();
      }
      final second = await service.pollOnce();
      expect(second.acknowledged, 1);
      expect(acks.last['status'], 'SUCCEEDED');
      expect(acks.last['code'], 'table_repaired');
      expect(DatabaseCore.tableBox!.get(key)!.activeOrderId, 222);
      expect(DatabaseCore.auditLogBox!.length, 1);
      if (!pruneJournal) expect(second.skippedAlreadyDone, 1);
    } finally {
      await service.stop();
    }
  }

  test(
    'lost ACK redelivery keeps repair receipt code and later occupancy',
    () => exercise(olderRegistry: false, pruneJournal: false),
  );
  test(
    'business receipt outlives pruned Edge journal without second mutation',
    () => exercise(olderRegistry: false, pruneJournal: true),
  );
  test(
    'older registry explicitly fails additive command before mutation',
    () => exercise(olderRegistry: true, pruneJournal: false),
  );
}
