import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/edge/pos_edge_command_handlers.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import '../support/pos03_fixture.dart';

const mgr03CommandId = 'c3000000-0000-4000-8000-000000000001';
const mgr03RequestId = 'c3000000-0000-4000-8000-000000000002';
const mgr03ActorId = 'c3000000-0000-4000-8000-000000000003';
Map<String, dynamic> mgr03Payload(String kind) => {
  'operationType': {
    'order_cancel': 'ORDER_STATUS_UPDATE',
    'takeaway_cancel': 'ORDER_CANCEL',
    'takeaway_create': 'TAKEAWAY_ORDER_UPSERT',
    'dine_in_create': 'DINE_IN_ORDER_UPSERT',
    'reservation_create': 'RESERVATION_CREATE',
    'reservation_status': 'RESERVATION_STATUS_UPDATE',
    'reservation_delete': 'RESERVATION_DELETE',
  }[kind],
  'actorStaffId': mgr03ActorId,
  'actorUsername': 'Synthetic manager',
  'createdBy': 'Synthetic manager',
  'updatedBy': 'Synthetic manager',
  'waiterName': 'Synthetic manager',
  'source': 'MANAGER',
  'businessDate': '2026-10-01',
  'orderUuid': pos03SourceUuid,
  'posOrderId': kind.endsWith('_cancel') ? 1 : 90001,
  'status': kind.endsWith('_cancel') ? 'cancelled' : 'confirmed',
  'floor': 'first',
  'tableNumbers': kind == 'dine_in_create' ? ['19'] : [19],
  'customerName': 'Synthetic guest',
  'customerPhone': 'synthetic',
  'numberOfGuests': 2,
  'reservationDate': '2026-10-02',
  'reservationTime': '18:00',
  'pickupTime': '18:00',
  'reservationId': kind == 'reservation_create'
      ? 'synthetic-new-booking'
      : 'booking',
  'items': [
    {'itemName': 'Synthetic dish', 'unitPrice': 10.0, 'quantity': 2},
  ],
  'preOrderItems': [],
  'totalAmount': 20.0,
  'managerOperation': {
    'requestId': mgr03RequestId,
    'kind': kind,
    'body': {},
    'reply': {},
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  late Map<String, dynamic> payload;
  late String commandId;
  final acks = <Map<String, dynamic>>[];
  const credential =
      'vynic-device-v1.11111111-1111-4111-8111-111111111111.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr03-edge-');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await fixture.seed();
    await DatabaseCore.tableBox!.put(
      'free',
      TableModel(tableNumber: '19', floor: 'first'),
    );
    payload = mgr03Payload('takeaway_create');
    commandId = mgr03CommandId;
    acks.clear();
    EdgeDeviceCredentialStore.directoryOverride = dir.path;
    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential);
  });
  tearDown(() async {
    await EdgeCommandJournal.close();
    await fixture.close();
    LocalDataAdmission.failure = null;
    UpdateReadiness.failure = null;
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    await dir.delete(recursive: true);
  });
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
                  'commandId': commandId,
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
        return http.Response('{}', acks.length == 1 ? 503 : 200);
      }),
    ),
    registry: EdgeCommandRegistry(
      older
          ? const [
              OrderStatusUpdateEdgeHandler(),
              OrderCancelEdgeHandler(),
              TakeawayOrderUpsertEdgeHandler(),
              DineInOrderUpsertEdgeHandler(),
              ReservationCreateEdgeHandler(),
              ReservationStatusUpdateEdgeHandler(),
              ReservationDeleteEdgeHandler(),
            ]
          : const [ManagerOperationEdgeHandler()],
    ),
  );
  Future<void> poll({bool older = false}) async {
    final t = service(older: older);
    await t.start();
    try {
      await t.pollOnce();
    } finally {
      await t.stop();
    }
  }

  for (final kind in [
    'order_cancel',
    'takeaway_cancel',
    'takeaway_create',
    'dine_in_create',
    'reservation_create',
    'reservation_status',
    'reservation_delete',
  ]) {
    test(
      '$kind ACKs only native completion and reopened lost-ACK replay preserves later POS work',
      () async {
        payload = mgr03Payload(kind);
        await poll();
        expect(acks.single['status'], 'SUCCEEDED');
        final orders = DatabaseCore.orderBox!.toMap().map(
          (k, v) =>
              MapEntry(k, jsonEncode(OrderTableMutationRepository.image(v))),
        );
        final audit = DatabaseCore.auditLogBox!.toMap();
        final reservations = DatabaseCore.reservationBox!.values
            .map((r) => '${r.id}:${r.status}')
            .toList();
        if (kind == 'reservation_status') {
          final r = DatabaseCore.reservationBox!.get('booking')!
            ..status = 'cancelled';
          await r.save();
        }
        if (kind.endsWith('_create') && kind != 'reservation_create') {
          final order = OrderRepository.getOrder(90001)!
            ..customerName = 'Later local edit';
          await order.save();
        }
        await EdgeCommandJournal.close();
        await fixture.close();
        await fixture.open(dir.path);
        await poll();
        expect(acks.last['status'], 'SUCCEEDED');
        expect(DatabaseCore.auditLogBox!.toMap(), audit);
        if (kind == 'reservation_status')
          expect(
            DatabaseCore.reservationBox!.get('booking')!.status,
            'cancelled',
          );
        else
          expect(
            DatabaseCore.reservationBox!.values
                .map((r) => '${r.id}:${r.status}')
                .toList(),
            reservations,
          );
        if (kind.endsWith('_create') && kind != 'reservation_create')
          expect(
            OrderRepository.getOrder(90001)!.customerName,
            'Later local edit',
          );
        else
          expect(
            DatabaseCore.orderBox!.toMap().map(
              (k, v) => MapEntry(
                k,
                jsonEncode(OrderTableMutationRepository.image(v)),
              ),
            ),
            orders,
          );
      },
    );
  }
  test(
    'older registry containing all legacy operations refuses MANAGER_OPERATION before effects',
    () async {
      final before = DatabaseCore.orderBox!.length,
          audit = DatabaseCore.auditLogBox!.length;
      await poll(older: true);
      expect(acks.single['code'], 'unsupported_command_type');
      expect(DatabaseCore.orderBox!.length, before);
      expect(DatabaseCore.auditLogBox!.length, audit);
      expect(OrderTableMutationRepository.read(mgr03CommandId), isNull);
    },
  );
  for (final kind in ['takeaway_create', 'dine_in_create']) {
    test(
      '$kind delayed across business date rejects before local effect',
      () async {
        payload = mgr03Payload(kind)..['businessDate'] = '2026-09-30';
        final before = DatabaseCore.auditLogBox!.toMap();
        await poll();
        expect(acks.single['code'], 'stale_date');
        expect(OrderRepository.getOrder(90001), isNull);
        expect(DatabaseCore.auditLogBox!.toMap(), before);
      },
    );
    test(
      '$kind unsynced local ID collision cannot overwrite local Order',
      () async {
        payload = mgr03Payload(kind)..['posOrderId'] = 1;
        final before = OrderTableMutationRepository.image(
          OrderRepository.getOrder(1)!,
        );
        await poll();
        expect(acks.single['code'], 'order_id_conflict');
        expect(
          OrderTableMutationRepository.image(OrderRepository.getOrder(1)!),
          before,
        );
      },
    );
  }
  for (final mismatch in ['uuid', 'date']) {
    test(
      'cancel rejects different original $mismatch before any lifecycle effect',
      () async {
        payload = mgr03Payload('order_cancel');
        payload[mismatch == 'uuid' ? 'orderUuid' : 'businessDate'] =
            mismatch == 'uuid' ? mgr03ActorId : '2026-09-30';
        final before = DatabaseCore.auditLogBox!.toMap();
        await poll();
        expect(acks.single['code'], 'stale_order_identity');
        expect(OrderRepository.getOrder(1)!.status, 'confirmed');
        expect(DatabaseCore.auditLogBox!.toMap(), before);
      },
    );
  }
  for (final point in ['orders.flush:after', 'audit.flush:after']) {
    test(
      'Order effect interrupted at $point has no failed ACK; startup recovers original receipt',
      () async {
        var hit = false;
        fixture.fault = (p, _) async {
          if (!hit && p == point) {
            hit = true;
            throw StateError('Synthetic effect interruption');
          }
        };
        final first = service();
        await first.start();
        await first.pollOnce();
        expect(hit, isTrue);
        expect(acks, isEmpty);
        await first.shutdown();
        await fixture.close();
        await fixture.open(dir.path);
        await poll();
        expect(acks.single['status'], 'SUCCEEDED');
        expect(OrderRepository.getOrder(90001), isNotNull);
      },
    );
  }
  for (final kind in [
    'reservation_create',
    'reservation_status',
    'reservation_delete',
  ]) {
    for (final point in [
      'audit.put:reservation-event:before',
      'audit.flush:after',
      'reservations.flush:after',
    ]) {
      test(
        '$kind actual storage failure at $point is retained uncertainty, never ordinary rejection or reexecution',
        () async {
          payload = mgr03Payload(kind);
          var hit = false;
          fixture.fault = (p, _) async {
            if (!hit && p == point) {
              hit = true;
              throw StateError('Synthetic reservation storage interruption');
            }
          };
          await poll();
          expect(hit, isTrue);
          expect(acks.single['code'], 'manager_operation_outcome_unknown');
          expect(acks.single['status'], 'FAILED');
          fixture.fault = null;
          final snapshot = DatabaseCore.reservationBox!.values
              .map((r) => '${r.id}:${r.status}')
              .toList();
          final audit = DatabaseCore.auditLogBox!.toMap();
          await fixture.close();
          await fixture.open(dir.path);
          await poll();
          expect(acks.last['code'], 'manager_operation_outcome_unknown');
          expect(
            DatabaseCore.reservationBox!.values
                .map((r) => '${r.id}:${r.status}')
                .toList(),
            snapshot,
          );
          expect(DatabaseCore.auditLogBox!.toMap(), audit);
        },
      );
    }
  }
  for (final kind in [
    'takeaway_create',
    'reservation_create',
    'reservation_status',
    'reservation_delete',
  ]) {
    for (final after in [false, true]) {
      test(
        '$kind terminal journal put failure after=$after cannot ACK failure after native success',
        () async {
          payload = mgr03Payload(kind);
          final first = service();
          await first.start();
          EdgeCommandJournal.wrapBoxForTest(
            (b) => _CompletionFault(b, after: after),
          );
          await first.pollOnce();
          expect(acks, isEmpty);
          final audit = DatabaseCore.auditLogBox!.toMap();
          await first.shutdown();
          await fixture.close();
          await fixture.open(dir.path);
          await poll();
          expect(
            acks.single['status'],
            kind == 'takeaway_create' || after ? 'SUCCEEDED' : 'FAILED',
          );
          if (kind != 'takeaway_create' && !after)
            expect(acks.single['code'], 'manager_operation_outcome_unknown');
          expect(DatabaseCore.auditLogBox!.toMap(), audit);
        },
      );
    }
  }
  test(
    'age and overflow prune retain guarded success, uncertainty and interrupted tombstones',
    () async {
      payload = mgr03Payload('reservation_status');
      await poll();
      await EdgeCommandJournal.open();
      final rows = EdgeCommandJournal.snapshot();
      rows[mgr03CommandId] = {
        ...rows[mgr03CommandId]!,
        'firstSeenAt': '2000-01-01T00:00:00Z',
        'completedAt': '2000-01-01T00:00:00Z',
      };
      rows['uncertain'] = {
        ...rows[mgr03CommandId]!,
        'commandId': 'uncertain',
        'status': 'failed',
        'code': 'manager_operation_outcome_unknown',
      };
      rows['interrupted'] = {
        ...rows[mgr03CommandId]!,
        'commandId': 'interrupted',
        'status': 'interrupted',
      };
      for (var i = 0; i <= EdgeCommandJournal.maxEntries; i++)
        rows['ordinary-$i'] = {
          'commandId': 'ordinary-$i',
          'idempotencyKey': 'ordinary-$i',
          'type': 'NOOP',
          'status': 'succeeded',
          'firstSeenAt': DateTime.now().toUtc().toIso8601String(),
          'completedAt': DateTime.now().toUtc().toIso8601String(),
        };
      await EdgeCommandJournal.open();
      await EdgeCommandJournal.restoreSnapshot(rows);
      await EdgeCommandJournal.prune();
      expect(EdgeCommandJournal.entryFor(mgr03CommandId), isNotNull);
      expect(
        EdgeCommandJournal.entryFor('uncertain')!.code,
        'manager_operation_outcome_unknown',
      );
      expect(EdgeCommandJournal.entryFor('interrupted'), isNotNull);
      final r = DatabaseCore.reservationBox!.get('booking')!
        ..status = 'cancelled';
      await r.save();
      await poll();
      expect(DatabaseCore.reservationBox!.get('booking')!.status, 'cancelled');
      expect(acks.last['status'], 'SUCCEEDED');
    },
  );
  for (final kind in ['reservation_status', 'reservation_delete']) {
    test(
      '$kind distinct no-op request cannot ACK success after a prior failed flush left the goal in RAM',
      () async {
        payload = mgr03Payload(kind);
        var broken = true, hits = 0;
        fixture.fault = (point, _) async {
          if (point == 'reservations.flush:before' && broken) {
            hits++;
            throw StateError('Synthetic retained storage flush failure');
          }
        };
        await poll();
        expect(acks.single['code'], 'manager_operation_outcome_unknown');
        commandId = 'c3000000-0000-4000-8000-000000000010';
        payload['managerOperation']['requestId'] = commandId;
        await poll();
        expect(acks.last['code'], 'manager_operation_outcome_unknown');
        expect(hits, 2);
        broken = false;
        commandId = 'c3000000-0000-4000-8000-000000000011';
        payload['managerOperation']['requestId'] = commandId;
        await poll();
        expect(acks.last['status'], 'SUCCEEDED');
      },
    );
  }
  test(
    'reservation create ID collision is an explicit no-effect conflict',
    () async {
      payload = mgr03Payload('reservation_create')
        ..['reservationId'] = 'booking';
      final before = DatabaseCore.auditLogBox!.toMap();
      await poll();
      expect(acks.single['code'], 'reservation_id_conflict');
      expect(DatabaseCore.auditLogBox!.toMap(), before);
    },
  );
}

class _CompletionFault extends UpdateTrackedBox<Map> {
  _CompletionFault(super.inner, {required this.after});
  final bool after;
  @override
  Future<void> put(dynamic key, Map value) async {
    if (value['status'] == 'succeeded') {
      if (after) await super.put(key, value);
      throw StateError('Synthetic completion put failure');
    }
    await super.put(key, value);
  }
}
