import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'package:vynic/core/services/manager_app/order_edit_request.dart';

Map<String, dynamic> mgr05Projection() => OrderEditProjection.build(
  Order(
    orderId: 1,
    orderUuid: 'c5000000-0000-4000-8000-000000000010',
    floor: 'first',
    tableNumbers: ['7'],
    items: [
      OrderItem(
        itemKey: 'dish',
        itemName: 'Synthetic dish',
        unitPrice: 10,
        quantity: 1,
        total: 10,
        lineUuid: 'c5000000-0000-4000-8000-000000000011',
      ),
    ],
    totalAmount: 10,
    createdAt: DateTime(2026, 10, 1),
    createdBy: 'Synthetic',
    status: 'confirmed',
  ),
  effectiveServiceFeePercent: 10,
);
http.Response editResponse(
  String status, {
  Map<String, dynamic>? projection,
  String? code,
}) => http.Response(
  jsonEncode({
    'success': status == 'SUCCEEDED',
    'accepted': status != 'FAILED',
    'editProjection': projection,
    'posDelivery': {
      'transport': 'edge',
      'status': status,
      'commandId': 'synthetic-command',
      'code': code,
    },
  }),
  202,
);
void main() {
  late Directory dir;
  late Order order;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr05-client-');
    Hive.init(dir.path);
    await OrderEditRequests.init();
    order = OrderEditProjection.read(mgr05Projection());
    order.items.single.quantity = 2;
    order.items.single.total = 20;
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  for (final status in [
    'QUEUED',
    'CLAIMED',
    'FAILED',
    'UNAVAILABLE',
    'SUCCEEDED',
  ])
    test('$status has accurate typed completion', () {
      final result = OrderEditResult.fromResponse(
        editResponse(status, projection: mgr05Projection()),
        1,
      );
      expect(result.isDone, status == 'SUCCEEDED');
      expect(result.needsCheck, ['QUEUED', 'CLAIMED'].contains(status));
    });
  test(
    'legacy acceptance, invalid response and missing POS projection never claim completion',
    () {
      for (final response in [
        http.Response('{"success":true}', 200),
        editResponse('DELIVERED_LEGACY'),
        editResponse('SUCCEEDED'),
        http.Response('bad', 202),
      ])
        expect(OrderEditResult.fromResponse(response, 1).isDone, isFalse);
    },
  );
  for (final code in [
    'primary_replaced_outcome_unknown',
    'lease_expired_attempts_exhausted',
  ]) {
    test(
      'terminal $code preserves uncertain outcome for reconciliation',
      () async {
        final result = await OrderEditRequests.submit(
          scope: 'session',
          order: order,
          currentSession: () => true,
          send: (_) async => editResponse('FAILED', code: code),
        );
        expect(result.isDone, isFalse);
        expect(result.needsCheck, isTrue);
        expect(result.message, contains('შედეგი გაურკვეველია'));
        expect(OrderEditRequests.draft('session', 1), isNotNull);
        await expectLater(
          OrderEditRequests.discard('session', 1),
          throwsStateError,
        );
      },
    );
  }
  test(
    'lost response persists frozen draft/UUID before HTTP and survives app reopen',
    () async {
      final sent = <Map<String, dynamic>>[];
      final first = await OrderEditRequests.submit(
        scope: 'session',
        order: order,
        currentSession: () => true,
        send: (body) async {
          sent.add(body);
          expect(OrderEditRequests.read('session', 1)!['body'], body);
          throw StateError('Synthetic lost response');
        },
      );
      expect(first.needsCheck, isTrue);
      final id = sent.single['requestId'];
      await Hive.close();
      await OrderEditRequests.init();
      final draft = OrderEditRequests.draft('session', 1)!;
      expect(draft.items.single.quantity, 2);
      expect(draft.items.single.lineUuid, order.items.single.lineUuid);
      draft.items.single.quantity = 99;
      await OrderEditRequests.submit(
        scope: 'session',
        order: draft,
        currentSession: () => true,
        send: (body) async {
          sent.add(body);
          return editResponse('QUEUED');
        },
      );
      expect(sent.last['requestId'], id);
      expect(sent.last['items'][0]['quantity'], 2);
    },
  );
  test(
    'concurrent submits share one HTTP intent and terminal FAILED cannot revive',
    () async {
      final gate = Completer<http.Response>();
      var calls = 0;
      Future<http.Response> send(Map<String, dynamic> _) {
        calls++;
        return gate.future;
      }

      final a = OrderEditRequests.submit(
            scope: 'session',
            order: order,
            currentSession: () => true,
            send: send,
          ),
          b = OrderEditRequests.submit(
            scope: 'session',
            order: order,
            currentSession: () => true,
            send: send,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete(editResponse('FAILED', code: 'stale_order'));
      await a;
      await b;
      expect(calls, 1);
      await OrderEditRequests.submit(
        scope: 'session',
        order: order,
        currentSession: () => true,
        send: send,
      );
      expect(calls, 1);
      expect(OrderEditRequests.draft('session', 1)!.items.single.quantity, 2);
    },
  );
  test(
    'session changed before request or after response cannot publish success',
    () async {
      var current = false, calls = 0;
      final first = await OrderEditRequests.submit(
        scope: 'old',
        order: order,
        currentSession: () => current,
        send: (_) async {
          calls++;
          return editResponse('QUEUED');
        },
      );
      expect(first.code, 'session_changed');
      expect(calls, 0);
      current = true;
      final second = await OrderEditRequests.submit(
        scope: 'old',
        order: order,
        currentSession: () => current,
        send: (_) async {
          current = false;
          return editResponse('SUCCEEDED', projection: mgr05Projection());
        },
      );
      expect(second.code, 'session_changed');
      expect(OrderEditRequests.read('new', 1), isNull);
    },
  );
  test(
    'pending request cannot be discarded and other origin/principal cannot see draft',
    () async {
      await OrderEditRequests.submit(
        scope: 'old-origin-principal',
        order: order,
        currentSession: () => true,
        send: (_) async => editResponse('QUEUED'),
      );
      expect(OrderEditRequests.draft('new-origin-principal', 1), isNull);
      await expectLater(
        OrderEditRequests.discard('old-origin-principal', 1),
        throwsStateError,
      );
    },
  );
  test(
    'result-persistence failure is caught once and clears inflight without detached error',
    () async {
      await expectLater(
        OrderEditRequests.submit(
          scope: 'session',
          order: order,
          currentSession: () => true,
          send: (_) async {
            await Hive.close();
            return editResponse('QUEUED');
          },
        ),
        throwsA(isA<HiveError>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(OrderEditRequests.inflight, isEmpty);
    },
  );
  test(
    'completed original draft retains its exact UUID/result with zero extra HTTP',
    () async {
      final requests = <Map<String, dynamic>>[];
      Future<http.Response> send(Map<String, dynamic> body) async {
        requests.add(body);
        return editResponse('SUCCEEDED', projection: mgr05Projection());
      }

      final first = await OrderEditRequests.submit(
        scope: 'session',
        order: order,
        currentSession: () => true,
        send: send,
      );
      final original = OrderEditRequests.read('session', 1)!;
      final retry = await OrderEditRequests.submit(
        scope: 'session',
        order: order,
        currentSession: () => true,
        send: send,
      );
      expect(retry.toMap(), first.toMap());
      expect(requests, hasLength(1));
      expect(
        OrderEditRequests.read('session', 1)!['body']['requestId'],
        original['body']['requestId'],
      );
    },
  );
  test(
    'fresh POS result baseline with a changed edit allocates new UUID and fingerprint',
    () async {
      final requests = <Map<String, dynamic>>[];
      final saved = OrderEditProjection.read(mgr05Projection());
      saved.items.single.quantity = 2;
      saved.items.single.total = 20;
      saved.totalAmount = 20;
      final savedProjection = OrderEditProjection.build(
        saved,
        effectiveServiceFeePercent: 10,
      );
      await OrderEditRequests.submit(
        scope: 'session',
        order: order,
        currentSession: () => true,
        send: (body) async {
          requests.add(body);
          return editResponse('SUCCEEDED', projection: savedProjection);
        },
      );
      final next = OrderEditProjection.read(savedProjection);
      next.items.single.quantity = 3;
      next.items.single.total = 30;
      final result = await OrderEditRequests.submit(
        scope: 'session',
        order: next,
        currentSession: () => true,
        send: (body) async {
          requests.add(body);
          return editResponse('QUEUED');
        },
      );
      expect(result.needsCheck, isTrue);
      expect(requests, hasLength(2));
      expect(requests.last['requestId'], isNot(requests.first['requestId']));
      expect(
        requests.last['expectedFingerprint'],
        savedProjection['fingerprint'],
      );
      expect(
        requests.last['expectedFingerprint'],
        isNot(requests.first['expectedFingerprint']),
      );
    },
  );
  for (final after in [false, true]) {
    test(
      'result flush failure after successful put retains original request and draft, after=$after',
      () async {
        final box = _ResultFlushFault(
          Hive.box(OrderEditRequests.boxName),
          after,
        );
        OrderEditRequests.wrapBoxForTest((_) => box);
        final requests = <Map<String, dynamic>>[];
        Future<http.Response> send(Map<String, dynamic> body) async {
          requests.add(body);
          return editResponse('SUCCEEDED', projection: mgr05Projection());
        }

        await expectLater(
          OrderEditRequests.submit(
            scope: 'session',
            order: order,
            currentSession: () => true,
            send: send,
          ),
          throwsStateError,
        );
        final draft = OrderEditRequests.draft('session', 1)!;
        expect(
          OrderEditRequests.read('session', 1)!['body']['requestId'],
          requests.single['requestId'],
        );
        final result = await OrderEditRequests.submit(
          scope: 'session',
          order: draft,
          currentSession: () => true,
          send: send,
        );
        expect(result.isDone, isTrue);
        expect(requests, hasLength(2));
        expect(requests[1], requests[0]);
      },
    );
  }
}

class _ResultFlushFault implements Box {
  _ResultFlushFault(this.inner, this.after);
  final Box inner;
  final bool after;
  int flushes = 0;
  @override
  bool get isOpen => inner.isOpen;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) => inner.put(key, value);
  @override
  Future<void> delete(dynamic key) => inner.delete(key);
  @override
  Future<void> flush() async {
    flushes++;
    if (flushes == 2 && !after) throw StateError('Owned result flush failure');
    await inner.flush();
    if (flushes == 2 && after) throw StateError('Owned result flush failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected fixture Box member: ${invocation.memberName}',
  );
}
