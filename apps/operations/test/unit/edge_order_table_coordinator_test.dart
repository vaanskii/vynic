import 'dart:convert';
import 'dart:io';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/edge/orders_tables/coordinator.dart';
import 'package:vynic/core/services/edge/orders_tables/projection_codec.dart';
import 'package:vynic/core/services/edge/orders_tables/shadow.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';

// Scripted responses model loss/gaps rather than reimplementing the Edge store.
class ScriptedTransport implements OrderTableTransport {
  Future<CommitResult> Function(CommitIntent)? onCommit;
  List<CommittedEvent> events = [];
  bool gap = false;
  @override
  Future<CommitResult> commit(CommitIntent intent) => onCommit!(intent);
  @override
  Future<ReplayPage> replay(ReplayRequest r) async => ReplayPage(
    authorityEpoch: Int64.ONE,
    headSequence: Int64(events.length),
    events: gap ? [] : events.where((e) => e.sequence > r.afterSequence),
  );
  @override
  Future<ProjectionSnapshot> snapshot(SnapshotRequest r) async =>
      ProjectionSnapshot(
        authorityEpoch: Int64.ONE,
        sequence: Int64.ZERO,
        mode: 'SHADOW',
      );
}

void main() {
  late Directory dir;
  late Box box;
  late ScriptedTransport transport;
  late AuthenticatedRequest auth;
  late OrderTableCoordinator client;
  ProjectionEntity entity() => OrderTableCodec.order(
    Order(
      orderId: 1,
      tableNumbers: [],
      floor: 'takeaway',
      items: [],
      totalAmount: 0,
      createdAt: DateTime(2026),
      createdBy: 'test',
    ),
    [],
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edge-client-test-');
    Hive.init(dir.path);
    box = await Hive.openBox('projection');
    transport = ScriptedTransport();
    auth = AuthenticatedRequest(
      scope: Scope(
        venueId: const Uuid().v4(),
        installationId: const Uuid().v4(),
        protocol: Protocol(major: 1, minor: 1),
      ),
      terminalId: const Uuid().v4(),
      terminalSecret: 'never-journal-this-secret',
    );
    client = OrderTableCoordinator(box: box, transport: transport, auth: auth);
    await client.open();
  });
  tearDown(() async {
    OrderTableShadow.observer = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'durable intent precedes transport; lost ACK retries same request after reopen',
    () async {
      final draft = entity();
      final first = await client.prepare([EntityChange(entity: draft)]);
      expect(client.cursor, Int64.ZERO);
      expect(client.entities, isEmpty);
      expect(box.get('frame').toString(), isNot(contains(auth.terminalSecret)));
      final event = CommittedEvent(
        sequence: Int64.ONE,
        authorityEpoch: Int64.ONE,
        requestId: first.requestId,
        terminalId: auth.terminalId,
        entities: [draft.deepCopy()..revision = Int64.ONE],
      );
      transport.onCommit = (r) async {
        expect(r.requestId, first.requestId);
        transport.events = [event];
        throw const SocketException('lost ACK');
      };
      await expectLater(client.sendPending(), throwsA(isA<SocketException>()));
      expect(client.entities, isEmpty);
      expect(client.pendingRequestId, first.requestId);
      await box.close();
      box = await Hive.openBox('projection');
      transport.onCommit = (r) async {
        expect(r.requestId, first.requestId);
        return CommitResult(
          outcome: CommitResult_Outcome.COMMITTED,
          event: event,
          authorityEpoch: Int64.ONE,
          headSequence: Int64.ONE,
        );
      };
      client = OrderTableCoordinator(
        box: box,
        transport: transport,
        auth: auth,
      );
      await client.open();
      expect(client.cursor, Int64.ONE);
      expect(client.pendingRequestId, isNull);
      expect(client.entities.single.revision, Int64.ONE);
      expect(client.lastResult!.event.requestId, first.requestId);
    },
  );
  test(
    'ACK catch-up includes another terminal event and never skips a sequence',
    () async {
      final a = entity(), b = entity();
      await client.prepare([EntityChange(entity: b)]);
      transport.onCommit = (r) async {
        transport.events = [
          CommittedEvent(
            sequence: Int64.ONE,
            authorityEpoch: Int64.ONE,
            entities: [a..revision = Int64.ONE],
          ),
          CommittedEvent(
            sequence: Int64(2),
            authorityEpoch: Int64.ONE,
            requestId: r.requestId,
            entities: [b..revision = Int64.ONE],
          ),
        ];
        return CommitResult(
          outcome: CommitResult_Outcome.COMMITTED,
          event: transport.events.last,
          authorityEpoch: Int64.ONE,
          headSequence: Int64(2),
        );
      };
      await client.sendPending();
      expect(client.entities.length, 2);
      expect(client.cursor, Int64(2));
      await expectLater(
        client.bootstrap(),
        throwsStateError,
      ); // rolled-back snapshot
      expect(client.cursor, Int64(2));
    },
  );
  test('replay gaps and binding reuse fail closed', () async {
    transport.events = [
      CommittedEvent(sequence: Int64.ONE, authorityEpoch: Int64.ONE),
    ];
    transport.gap = true;
    await expectLater(client.catchUp(), throwsStateError);
    expect(client.cursor, Int64.ZERO);
    final other = auth.deepCopy()..terminalId = const Uuid().v4();
    await expectLater(
      OrderTableCoordinator(box: box, transport: transport, auth: other).open(),
      throwsStateError,
    );
  });
  test(
    'shadow transport failure preserves primary operation and reports uncompared',
    () async {
      transport.onCommit = (_) async => throw const SocketException('offline');
      OrderTableShadow.observer = OrderTableShadow(client);
      var written = false;
      final e = entity();
      await OrderTableShadow.observe(
        proposed: () => [e],
        operation: () async {
          written = true;
        },
        actual: () => [e],
      );
      expect(written, isTrue);
      final diagnostics = (box.get('diagnostics') as List).map(
        (v) => jsonDecode(v as String)['kind'],
      );
      expect(diagnostics, containsAll(['proposal_failed', 'uncompared']));
      expect(client.pendingRequestId, isNotNull);
    },
  );
  test('shadow compares post-operation result and detects mismatch', () async {
    transport.onCommit = (r) async {
      final event = CommittedEvent(
        sequence: Int64.ONE,
        authorityEpoch: Int64.ONE,
        requestId: r.requestId,
        entities: r.changes.map(
          (c) => c.entity.deepCopy()..revision = Int64.ONE,
        ),
      );
      transport.events = [event];
      return CommitResult(
        outcome: CommitResult_Outcome.COMMITTED,
        event: event,
        authorityEpoch: Int64.ONE,
      );
    };
    OrderTableShadow.observer = OrderTableShadow(client);
    final before = entity();
    var writes = 0;
    await OrderTableShadow.observe(
      proposed: () => [before],
      operation: () async {
        expect(client.cursor, Int64.ONE);
        writes++;
      },
      actual: () => [
        before.deepCopy()
          ..tombstone = true
          ..clearDocument(),
      ],
    );
    expect(writes, 1);
    expect(
      jsonDecode((box.get('diagnostics') as List).last as String)['kind'],
      'mismatch',
    );
  });
}
