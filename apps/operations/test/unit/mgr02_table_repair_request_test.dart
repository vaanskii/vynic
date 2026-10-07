import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/manager_app/pos_command_delivery.dart';
import 'package:vynic/core/services/manager_app/table_repair_request.dart';

http.Response repairResponse(String status, {int httpStatus = 202, String? code}) =>
  http.Response(jsonEncode({'success': status == 'SUCCEEDED', 'accepted': status != 'FAILED',
    'posDelivery': {'transport': 'edge', 'status': status, 'commandId': 'synthetic-command', 'code': code}}), httpStatus);
void main() {
  late Directory dir;
  setUp(() async { dir = await Directory.systemTemp.createTemp('vynic-mgr02-client-'); Hive.init(dir.path); await TableRepairRequests.init(); });
  tearDown(() async { await Hive.close(); await dir.delete(recursive: true); });
  for (final status in ['QUEUED', 'CLAIMED', 'SUCCEEDED', 'FAILED', 'UNAVAILABLE']) {
    test('$status has explicit delivery, retained command and accurate completion', () {
      final result = TableRepairResult.fromResponse(repairResponse(status));
      expect(result.isDone, status == 'SUCCEEDED');
      expect(result.isPending, ['QUEUED', 'CLAIMED'].contains(status));
      expect(result.commandId, 'synthetic-command');
      if (status != 'SUCCEEDED') expect(result.message.contains('გათავისუფლდა'), isFalse);
    });
  }
  test('false legacy/malformed completion and genuine missing table are distinct', () {
    expect(TableRepairResult.fromResponse(http.Response('{"success":true}', 200)).isDone, isFalse);
    expect(TableRepairResult.fromResponse(http.Response('{"success":false,"posDelivery":{"status":"SUCCEEDED","commandId":"x"}}', 202)).isDone, isFalse);
    expect(TableRepairResult.fromResponse(repairResponse('DELIVERED_LEGACY')).isDone, isFalse);
    final missing = TableRepairResult.fromResponse(http.Response('{"message":"table_not_found"}', 404));
    expect(missing.delivery, PosCommandDelivery.failed); expect(missing.code, 'table_not_found');
    expect(missing.message, 'მაგიდა ვერ მოიძებნა');
    expect(TableRepairResult.fromResponse(http.Response('invalid', 202)).delivery, PosCommandDelivery.unknown);
  });
  test('network ambiguity persists same UUID before retry and screen/process reopen', () async {
    String? first;
    final unknown = await TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', send: (body) async {
      first = body['requestId']; expect(TableRepairRequests.read('a', '7', 'first')!['requestId'], first);
      throw const SocketException('synthetic lost response');
    });
    expect(unknown.delivery, PosCommandDelivery.unknown);
    await Hive.close(); await TableRepairRequests.init();
    final queued = await TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', send: (body) async {
      expect(body['requestId'], first); return repairResponse('QUEUED');
    });
    expect(queued.isPending, isTrue);
    await TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', refresh: true, send: (body) async {
      expect(body['requestId'], first); return repairResponse('SUCCEEDED');
    });
    expect(TableRepairRequests.read('a', '7', 'first')!['result']['status'], 'succeeded');
  });
  test('concurrent taps share one in-flight submission', () async {
    final entered = Completer<void>(); final release = Completer<void>(); var calls = 0;
    Future<http.Response> send(Map<String, dynamic> body) async { calls++; entered.complete(); await release.future; return repairResponse('QUEUED'); }
    final first = TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', send: send);
    await entered.future;
    final second = TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', send: send);
    release.complete(); await Future.wait([first, second]); expect(calls, 1);
  });
  test('refresh keeps completed identity; a deliberate later action gets a new UUID', () async {
    final ids = <String>[];
    Future<http.Response> send(Map<String, dynamic> body) async { ids.add(body['requestId']); return repairResponse('SUCCEEDED'); }
    await TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', send: send);
    await TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', refresh: true, send: send);
    await TableRepairRequests.submit(scope: 'a', number: '7', floor: 'first', send: send);
    expect(ids[0], ids[1]); expect(ids[2], isNot(ids[0]));
  });
  test('principal/origin scopes cannot reveal or reuse another request', () async {
    final a = TableRepairRequests.scope('https://a.invalid', 'staff-a');
    final b = TableRepairRequests.scope('https://a.invalid', 'staff-b');
    final moved = TableRepairRequests.scope('https://b.invalid', 'staff-a');
    await TableRepairRequests.submit(scope: a, number: '7', floor: 'first', send: (_) async => repairResponse('QUEUED'));
    expect(TableRepairRequests.list(b), isEmpty); expect(TableRepairRequests.list(moved), isEmpty);
    await expectLater(TableRepairRequests.submit(scope: b, number: '7', floor: 'first', refresh: true, send: (_) async => repairResponse('SUCCEEDED')), throwsStateError);
  });
}
