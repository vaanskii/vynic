import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/core/services/manager_app/pos_command_delivery.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:hive/hive.dart';

const mgr03Body = <String, dynamic>{
  'customerName': 'Synthetic guest',
  'pickupTime': '18:00',
  'items': [
    {'itemName': 'Synthetic dish', 'quantity': 2, 'unitPrice': 10},
  ],
};
http.Response mgr03Response(
  Map request,
  String status, {
  String? code,
  String? commandId = 'synthetic-command',
}) => http.Response(
  jsonEncode({
    'requestId': request['requestId'],
    'kind': request['kind'],
    'posOrderId': 90001,
    'success': status == 'SUCCEEDED',
    'accepted': status != 'UNAVAILABLE',
    'posDelivery': {
      'transport': 'edge',
      'status': status,
      'commandId': status == 'UNAVAILABLE' ? null : commandId,
      'code': code,
    },
  }),
  202,
);
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr03-client-');
    Hive.init(dir.path);
    await ManagerOperationRequests.init();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Future<ManagerOperationResult> submit(
    OperationExchange exchange, {
    Map<String, dynamic> body = mgr03Body,
    bool refresh = false,
    bool newRequest = false,
    bool Function()? current,
  }) => ManagerOperationRequests.submit(
    scope: 'own-session',
    slot: 'takeaway_create',
    kind: 'takeaway_create',
    body: body,
    currentSession: current ?? () => true,
    exchange: exchange,
    refresh: refresh,
    newRequest: newRequest,
  );
  Map<String, dynamic> entry() =>
      ManagerOperationRequests.read('own-session', 'takeaway_create')!;
  for (final status in [
    'QUEUED',
    'CLAIMED',
    'SUCCEEDED',
    'FAILED',
    'UNAVAILABLE',
  ]) {
    test(
      '$status claims completion only after POS success and durable local result',
      () async {
        final r = await submit((q, statusOnly) async {
          expect(statusOnly, isFalse);
          expect(entry()['requestId'], q['requestId']);
          return mgr03Response(q, status);
        });
        expect(r.isDone, status == 'SUCCEEDED');
        expect(r.delivery.name, status.toLowerCase());
        expect(entry()['result']['delivery'], r.delivery.name);
      },
    );
  }
  for (final code in [
    'manager_operation_outcome_unknown',
    'primary_replaced_outcome_unknown',
    'lease_expired_attempts_exhausted',
  ]) {
    test('$code retains reference and permits only status reads', () async {
      final first = await submit(
        (q, _) async => mgr03Response(q, 'FAILED', code: code),
      );
      expect(first.needsCheck, isTrue);
      expect(first.reference, '90001');
      await expectLater(
        ManagerOperationRequests.dismiss('own-session', 'takeaway_create'),
        throwsStateError,
      );
      var calls = 0;
      await submit(
        (q, statusOnly) async {
          calls++;
          expect(statusOnly, isTrue);
          return mgr03Response(q, 'FAILED', code: code);
        },
        refresh: true,
        body: {'changed': 'new draft'},
      );
      expect(calls, 1);
      expect(entry()['body'], mgr03Body);
      await submit((q, _) async {
        fail('Uncertain request must never be reexecuted');
      }, body: {'changed': 'new draft'});
      expect(entry()['requestId'], first.requestId);
    });
  }
  test(
    'lost POST then reopen resends original UUID/body, not changed form',
    () async {
      Map? first;
      await submit((q, _) async {
        first = q;
        throw const SocketException('synthetic response lost');
      });
      await Hive.close();
      await ManagerOperationRequests.init();
      final r = await submit((q, statusOnly) async {
        expect(q['requestId'], first!['requestId']);
        expect(q['body'], mgr03Body);
        expect(statusOnly, isFalse);
        return mgr03Response(q, 'QUEUED');
      }, body: {'changed': 'new draft'});
      expect(r.delivery, PosCommandDelivery.queued);
      expect(entry()['attempts'], 2);
    },
  );
  for (final status in [400, 403, 404, 409]) {
    test(
      'negative $status after a lost POST stays unknown and cannot allocate a new UUID',
      () async {
        await submit(
          (q, _) async =>
              throw const SocketException('synthetic response lost'),
        );
        final id = entry()['requestId'];
        final r = await submit(
          (q, _) async => http.Response(
            jsonEncode({
              'message': status == 404
                  ? 'Cannot POST /mobile/operation-requests/takeaway_create'
                  : 'request_rejected',
            }),
            status,
          ),
        );
        expect(r.delivery, PosCommandDelivery.unknown);
        expect(r.isDone, isFalse);
        await expectLater(
          ManagerOperationRequests.dismiss('own-session', 'takeaway_create'),
          throwsStateError,
        );
        await submit((q, _) async {
          expect(q['requestId'], id);
          expect(q['body'], mgr03Body);
          return mgr03Response(q, 'QUEUED');
        }, body: {'changed': 'new'});
      },
    );
  }
  test(
    'first old-Cloud 404 is explicit unavailable, with safe local dismissal',
    () async {
      final r = await submit(
        (q, _) async => http.Response(
          '{"message":"Cannot POST /mobile/operation-requests/takeaway_create"}',
          404,
        ),
      );
      expect(r.delivery, PosCommandDelivery.unavailable);
      expect(r.code, 'cloud_upgrade_required');
      await ManagerOperationRequests.dismiss('own-session', 'takeaway_create');
      expect(entryOrNull(), isNull);
    },
  );
  test(
    'queued identity uses GET for every delayed status; unknown keeps its assigned reference',
    () async {
      final queued = await submit((q, _) async => mgr03Response(q, 'QUEUED'));
      final unknown = await submit((q, readOnly) async {
        expect(readOnly, isTrue);
        throw const SocketException('synthetic status lost');
      }, refresh: true);
      expect(unknown.commandId, queued.commandId);
      expect(unknown.reference, queued.reference);
      final done = await submit((q, readOnly) async {
        expect(readOnly, isTrue);
        return mgr03Response(q, 'SUCCEEDED');
      }, refresh: true);
      expect(done.isDone, isTrue);
    },
  );
  test(
    'concurrent submits use one durable intent and one HTTP exchange',
    () async {
      final gate = Completer<http.Response>();
      Map? request;
      var calls = 0;
      Future<http.Response> send(Map<String, dynamic> q, bool _) {
        request = q;
        calls++;
        return gate.future;
      }

      final a = submit(send), b = submit(send);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete(mgr03Response(request!, 'QUEUED'));
      expect((await a).requestId, (await b).requestId);
      expect(calls, 1);
    },
  );
  test(
    'session changed after response never returns success or retargets saved intent',
    () async {
      var current = true;
      final r = await submit((q, _) async {
        current = false;
        return mgr03Response(q, 'SUCCEEDED');
      }, current: () => current);
      expect(r.code, 'session_changed');
      expect(r.isDone, isFalse);
      expect(ManagerOperationRequests.all('different-session'), isEmpty);
      expect(entry()['result']['delivery'], 'succeeded');
    },
  );
  test('session changed while intent flush waits prevents all HTTP', () async {
    var current = true;
    var calls = 0;
    ManagerOperationRequests.wrapBoxForTest(
      (b) => _FaultBox(
        b,
        onFlush: () {
          current = false;
        },
      ),
    );
    final r = await submit((q, _) async {
      calls++;
      return mgr03Response(q, 'SUCCEEDED');
    }, current: () => current);
    expect(r.code, 'session_changed');
    expect(calls, 0);
  });
  for (final afterPut in [false, true]) {
    test(
      'intent put failure after=$afterPut preserves same UUID, no HTTP before recovery',
      () async {
        var broken = true, calls = 0;
        ManagerOperationRequests.wrapBoxForTest(
          (b) => _FaultBox(
            b,
            failPut: (v) => broken && v['attempts'] == 0,
            afterPut: afterPut,
          ),
        );
        await expectLater(
          submit((q, _) async {
            calls++;
            return mgr03Response(q, 'QUEUED');
          }),
          throwsStateError,
        );
        final id = entry()['requestId'];
        expect(calls, 0);
        broken = false;
        await submit((q, _) async {
          calls++;
          expect(q['requestId'], id);
          return mgr03Response(q, 'QUEUED');
        });
        expect(calls, 1);
      },
    );
  }
  test(
    'intent flush failure leaves unknown frozen entry and no HTTP',
    () async {
      var broken = true, calls = 0;
      ManagerOperationRequests.wrapBoxForTest(
        (b) => _FaultBox(b, failFlush: () => broken),
      );
      await expectLater(
        submit((q, _) async {
          calls++;
          return mgr03Response(q, 'QUEUED');
        }),
        throwsStateError,
      );
      final id = entry()['requestId'];
      expect(calls, 0);
      broken = false;
      await submit((q, _) async {
        expect(q['requestId'], id);
        return mgr03Response(q, 'QUEUED');
      });
    },
  );
  for (final afterPut in [false, true]) {
    test(
      'terminal result put failure after=$afterPut cannot publish completion',
      () async {
        var broken = true;
        ManagerOperationRequests.wrapBoxForTest(
          (b) => _FaultBox(
            b,
            failPut: (v) => broken && v['result']['delivery'] == 'succeeded',
            afterPut: afterPut,
          ),
        );
        await expectLater(
          submit((q, _) async => mgr03Response(q, 'SUCCEEDED')),
          throwsStateError,
        );
        final retained = ManagerOperationResult.fromMap(entry()['result']);
        expect(retained.isDone, isFalse);
        expect(retained.reference, '90001');
        broken = false;
        final r = await submit((q, readOnly) async {
          expect(readOnly, isTrue);
          return mgr03Response(q, 'SUCCEEDED');
        }, refresh: true);
        expect(r.isDone, isTrue);
      },
    );
  }
  test(
    'result flush failure remains unknown with reference until flushed status recheck',
    () async {
      var count = 0, broken = true;
      ManagerOperationRequests.wrapBoxForTest(
        (b) => _FaultBox(b, failFlush: () => ++count == 3 && broken),
      );
      await expectLater(
        submit((q, _) async => mgr03Response(q, 'SUCCEEDED')),
        throwsStateError,
      );
      expect(ManagerOperationResult.fromMap(entry()['result']).isDone, isFalse);
      expect(entry()['result']['reference'], '90001');
      broken = false;
      expect(
        (await submit((q, readOnly) async {
          expect(readOnly, isTrue);
          return mgr03Response(q, 'SUCCEEDED');
        }, refresh: true)).isDone,
        isTrue,
      );
    },
  );
  test(
    'completed retry with reordered map keys uses no HTTP; changed explicit draft gets new UUID',
    () async {
      final first = await submit((q, _) async => mgr03Response(q, 'SUCCEEDED'));
      final same = await submit(
        (q, _) async {
          fail('Completed identical request must be retained');
        },
        body: {
          'items': mgr03Body['items'],
          'pickupTime': '18:00',
          'customerName': 'Synthetic guest',
        },
      );
      expect(same.requestId, first.requestId);
      final next = await submit(
        (q, _) async => mgr03Response(q, 'QUEUED'),
        body: {...mgr03Body, 'customerName': 'New synthetic guest'},
      );
      expect(next.requestId, isNot(first.requestId));
    },
  );
  test(
    'explicit fresh identical creation after completion gets a new UUID',
    () async {
      final first = await submit((q, _) async => mgr03Response(q, 'SUCCEEDED'));
      final next = await submit((q, statusOnly) async {
        expect(statusOnly, isFalse);
        expect(q['body'], mgr03Body);
        return mgr03Response(q, 'QUEUED');
      }, newRequest: true);
      expect(next.requestId, isNot(first.requestId));
    },
  );
  for (final status in ['QUEUED', 'CLAIMED', 'FAILED', 'UNKNOWN']) {
    test(
      'fresh creation cannot replace retained $status identity or draft',
      () async {
        final first = await submit(
          (q, _) async => status == 'UNKNOWN'
              ? throw StateError('lost POST')
              : mgr03Response(
                  q,
                  status,
                  code: status == 'FAILED'
                      ? 'manager_operation_outcome_unknown'
                      : null,
                ),
        );
        final next = await submit(
          (q, statusOnly) async {
            expect(q['requestId'], first.requestId);
            expect(q['body'], mgr03Body);
            expect(statusOnly, status != 'UNKNOWN');
            return mgr03Response(q, 'QUEUED');
          },
          body: {'changed': 'fresh form'},
          newRequest: true,
          refresh: status == 'FAILED',
        );
        expect(next.requestId, first.requestId);
        expect(entry()['body'], mgr03Body);
      },
    );
  }
  test(
    'delete failure retains terminal entry and blocks false local disappearance',
    () async {
      await submit(
        (q, _) async => mgr03Response(q, 'FAILED', code: 'order_id_conflict'),
      );
      ManagerOperationRequests.wrapBoxForTest(
        (b) => _FaultBox(b, failDelete: true),
      );
      await expectLater(
        ManagerOperationRequests.dismiss('own-session', 'takeaway_create'),
        throwsStateError,
      );
      expect(entry(), isNotEmpty);
    },
  );
  for (final invalid in [
    'legacy',
    'wrong-id',
    'different-command',
    'malformed',
  ]) {
    test('$invalid response never becomes completion', () async {
      await submit((q, _) async => mgr03Response(q, 'QUEUED'));
      final r = await submit(
        (q, _) async => switch (invalid) {
          'legacy' => http.Response('{"success":true}', 200),
          'wrong-id' => mgr03Response({
            ...q,
            'requestId': 'other',
          }, 'SUCCEEDED'),
          'different-command' => mgr03Response(
            q,
            'SUCCEEDED',
            commandId: 'different',
          ),
          _ => http.Response('not JSON', 202),
        },
        refresh: true,
      );
      expect(r.isDone, isFalse);
      expect(r.needsCheck, isTrue);
    });
  }
}

Map? entryOrNull() =>
    ManagerOperationRequests.read('own-session', 'takeaway_create');

class _FaultBox extends UpdateTrackedBox<dynamic> {
  _FaultBox(
    super.inner, {
    this.failPut,
    this.afterPut = false,
    this.failFlush,
    this.onFlush,
    this.failDelete = false,
  });
  final bool Function(dynamic)? failPut;
  final bool afterPut;
  final bool Function()? failFlush;
  final void Function()? onFlush;
  final bool failDelete;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    final failed = failPut?.call(value) == true;
    if (failed && !afterPut) throw StateError('Synthetic put failure');
    await super.put(key, value);
    if (failed) throw StateError('Synthetic put failure after IO');
  }

  @override
  Future<void> flush() async {
    onFlush?.call();
    if (failFlush?.call() == true) throw StateError('Synthetic flush failure');
    await super.flush();
  }

  @override
  Future<void> delete(dynamic key) async {
    if (failDelete) throw StateError('Synthetic delete failure');
    await super.delete(key);
  }
}
