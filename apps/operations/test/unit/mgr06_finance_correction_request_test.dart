import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/finance_correction_request.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

const mgr06Period = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const mgr06OriginalId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const mgr06Path = 'payroll/$mgr06Period/payments/$mgr06OriginalId/reversal';
final mgr06Original = <String, dynamic>{
  'id': mgr06OriginalId,
  'amount': '120.34',
  'businessDate': '2026-09-15',
  'paymentDate': '2026-09-15',
};
Map<String, dynamic> mgr06Receipt(Map<String, dynamic> body) => {
  ...mgr06Original,
  'id': body['id'],
  'reversalOfId': mgr06OriginalId,
  'amount': '-120.34',
  'notes': body['reason'],
  'payrollPeriodId': mgr06Period,
  'correctionBusinessDate': '2026-10-07',
  'actorId': 'synthetic-actor',
  'createdAt': '2026-10-07T10:00:00.000Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  Future<void> session(String principal) => AuthTokenService.saveToken(
    token:
        'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': principal})))}.unsigned',
    username: 'Synthetic',
    role: 'MANAGER',
    expiresInSeconds: 3600,
    venueCode: principal,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr06-client-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await session('a');
    await FinanceCorrectionRequests.init();
  });
  tearDown(() async {
    FinanceCorrectionRequests.storageFault = null;
    ManagerAppPreferences.backendUrlOverride.value = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Future<Map<String, dynamic>> submit(
    FinanceCorrectionSend send, {
    String reason = 'Wrong entry',
    String? scope,
    void Function()? fence,
    Map<String, dynamic>? original,
  }) => FinanceCorrectionRequests.submit(
    scope: scope ?? MobileApiService.tableRepairScope,
    path: mgr06Path,
    reason: reason,
    original: original ?? mgr06Original,
    send: send,
    requireSession: fence ?? () {},
  );

  test(
    'lost response/reopened storage retains UUID and frozen body before HTTP',
    () async {
      Map<String, dynamic>? first;
      await expectLater(
        submit((path, body) async {
          first = Map.from(body);
          final saved = FinanceCorrectionRequests.read(
            MobileApiService.tableRepairScope,
            path,
          )!;
          expect(saved['id'], body['id']);
          expect(saved['reason'], body['reason']);
          expect(
            (await File(
              '${dir.path}/${FinanceCorrectionRequests.boxName}.hive',
            ).stat()).size,
            greaterThan(0),
          );
          throw const SocketException('synthetic lost committed response');
        }),
        throwsA(isA<SocketException>()),
      );
      await Hive.close();
      await AuthTokenService.init();
      await FinanceCorrectionRequests.init();
      final result = await submit((path, body) async {
        expect(body, first);
        return mgr06Receipt(body);
      });
      expect(result['reversalOfId'], mgr06OriginalId);
      var calls = 0;
      await submit((path, body) async {
        calls++;
        return mgr06Receipt(body);
      });
      expect(calls, 0);
    },
  );
  for (final phase in [
    'pendingPutBefore',
    'pendingPutAfter',
    'pendingFlushBefore',
    'pendingFlushAfter',
    'receiptPutBefore',
    'receiptPutAfter',
    'receiptFlushBefore',
    'receiptFlushAfter',
  ]) {
    test(
      'storage fault $phase cannot report success; retry crosses a durable barrier',
      () async {
        var calls = 0;
        String? id;
        Future<Map<String, dynamic>> send(
          String path,
          Map<String, dynamic> body,
        ) async {
          calls++;
          id = body['id'];
          return mgr06Receipt(body);
        }

        FinanceCorrectionRequests.storageFault = (current) async {
          if (current == phase)
            throw const FileSystemException('Synthetic storage fault');
        };
        await expectLater(submit(send), throwsA(isA<FileSystemException>()));
        expect(calls, phase.startsWith('pending') ? 0 : 1);
        FinanceCorrectionRequests.storageFault = null;
        final retry = await submit(send);
        if (id != null) expect(retry['id'], id);
        final scope = MobileApiService.tableRepairScope;
        await Hive.close();
        await AuthTokenService.init();
        await FinanceCorrectionRequests.init();
        expect(
          FinanceCorrectionRequests.read(scope, mgr06Path)!['receipt']['id'],
          retry['id'],
        );
      },
    );
  }
  test('receipt already in RAM cannot bypass a failed replay flush', () async {
    await submit((path, body) async => mgr06Receipt(body));
    FinanceCorrectionRequests.storageFault = (phase) async {
      if (phase == 'replayFlushBefore')
        throw const FileSystemException('Synthetic failed replay flush');
    };
    await expectLater(
      submit((path, body) async => mgr06Receipt(body)),
      throwsA(isA<FileSystemException>()),
    );
  });
  test(
    'different reason or original cannot overwrite a pending request',
    () async {
      await expectLater(
        submit((path, body) async => throw const SocketException('lost')),
        throwsA(isA<SocketException>()),
      );
      var calls = 0;
      Future<Map<String, dynamic>> send(
        String path,
        Map<String, dynamic> body,
      ) async {
        calls++;
        return mgr06Receipt(body);
      }

      await expectLater(submit(send, reason: 'Changed'), throwsStateError);
      await expectLater(
        submit(send, original: {...mgr06Original, 'amount': '500.00'}),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
  test(
    'concurrent identical taps submit once; different reason conflicts',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var calls = 0;
      Future<Map<String, dynamic>> send(
        String path,
        Map<String, dynamic> body,
      ) async {
        calls++;
        entered.complete();
        await release.future;
        return mgr06Receipt(body);
      }

      final first = submit(send);
      await entered.future;
      final second = submit(send);
      await expectLater(submit(send, reason: 'Other'), throwsStateError);
      release.complete();
      expect(await first, await second);
      expect(calls, 1);
    },
  );
  test(
    'account, Venue and origin scopes cannot reuse a saved request',
    () async {
      final a = MobileApiService.tableRepairScope;
      await submit((path, body) async => mgr06Receipt(body));
      await session('b');
      final b = MobileApiService.tableRepairScope;
      expect(a, isNot(b));
      expect(FinanceCorrectionRequests.read(b, mgr06Path), isNull);
      ManagerAppPreferences.backendUrlOverride.value =
          'https://synthetic-other.invalid';
      final origin = MobileApiService.tableRepairScope;
      expect(origin, isNot(b));
      expect(FinanceCorrectionRequests.read(origin, mgr06Path), isNull);
      ManagerAppPreferences.backendUrlOverride.value = null;
      await session('a');
      await AuthTokenService.saveToken(
        token: AuthTokenService.token!,
        username: 'Synthetic',
        role: 'MANAGER',
        expiresInSeconds: 3600,
        venueCode: 'moved-venue',
      );
      final venue = MobileApiService.tableRepairScope;
      expect(venue, isNot(a));
      expect(FinanceCorrectionRequests.read(venue, mgr06Path), isNull);
    },
  );
  for (final field in [
    'id',
    'reversalOfId',
    'amount',
    'businessDate',
    'paymentDate',
    'notes',
    'payrollPeriodId',
    'correctionBusinessDate',
    'actorId',
    'createdAt',
  ]) {
    test(
      '2xx without valid $field remains unconfirmed and retains identity',
      () async {
        String? id;
        await expectLater(
          submit((path, body) async {
            id = body['id'];
            return mgr06Receipt(body)..remove(field);
          }),
          throwsFormatException,
        );
        expect(
          FinanceCorrectionRequests.read(
            MobileApiService.tableRepairScope,
            mgr06Path,
          )!['receipt'],
          isNull,
        );
        await submit((path, body) async {
          expect(body['id'], id);
          return mgr06Receipt(body);
        });
      },
    );
  }
  test(
    'cycle payment receipt must restore exactly the original reserve consumption',
    () async {
      const path = 'cycles/$mgr06Period/payments/$mgr06OriginalId/reversal';
      final original = {...mgr06Original, 'reserveConsumed': '80.00'};
      final body = {
        'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'reason': 'Wrong entry',
      };
      final receipt = {
        ...mgr06Receipt(body),
        'obligationCycleId': mgr06Period,
        'reserveConsumed': '-80',
      };
      expect(
        () => FinanceCorrectionRequests.validateReceipt(
          path,
          original,
          body,
          receipt,
        ),
        returnsNormally,
      );
      expect(
        () => FinanceCorrectionRequests.validateReceipt(path, original, body, {
          ...receipt,
          'reserveConsumed': '0',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'expired/changed session prevents storage submission and completion display',
    () async {
      var calls = 0;
      await expectLater(
        submit((path, body) async {
          calls++;
          return mgr06Receipt(body);
        }, fence: () => throw StateError('changed')),
        throwsStateError,
      );
      expect(calls, 0);
      var current = true;
      await expectLater(
        submit(
          (path, body) async {
            current = false;
            return mgr06Receipt(body);
          },
          fence: () {
            if (!current) throw StateError('changed');
          },
        ),
        throwsStateError,
      );
      expect(
        FinanceCorrectionRequests.read(
          MobileApiService.tableRepairScope,
          mgr06Path,
        )!['receipt'],
        isNull,
      );
    },
  );
  test(
    'corrupt local request blocks HTTP rather than replacing its UUID',
    () async {
      await expectLater(
        submit((path, body) async => throw const SocketException('lost')),
        throwsA(isA<SocketException>()),
      );
      final box = Hive.box(FinanceCorrectionRequests.boxName);
      await box.put(box.keys.single, 'synthetic corruption');
      await box.flush();
      var calls = 0;
      await expectLater(
        submit((path, body) async {
          calls++;
          return mgr06Receipt(body);
        }),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'actual HTTP uses one captured bearer/origin and refuses changed session response',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final initial = AuthTokenService.token;
      final future = http.runWithClient(
        () => MobileApiService.financeCorrectionWrite(mgr06Path, {
          'id': 'x',
          'reason': 'why',
        }),
        () => MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer $initial');
          expect(request.url.path, '/mobile/finance/$mgr06Path');
          entered.complete();
          await release.future;
          return http.Response('{}', 201);
        }),
      );
      await entered.future;
      await session('b');
      release.complete();
      await expectLater(future, throwsStateError);
    },
  );
  test(
    'actual HTTP rejects failure and malformed success; valid receipt completes store',
    () async {
      await expectLater(
        http.runWithClient(
          () => submit(MobileApiService.financeCorrectionWrite),
          () => MockClient(
            (_) async => http.Response('{"message":"Synthetic denied"}', 403),
          ),
        ),
        throwsException,
      );
      await expectLater(
        http.runWithClient(
          () => submit(MobileApiService.financeCorrectionWrite),
          () => MockClient((_) async => http.Response('[]', 201)),
        ),
        throwsFormatException,
      );
      final result = await http.runWithClient(
        () => submit(MobileApiService.financeCorrectionWrite),
        () => MockClient(
          (request) async => http.Response(
            jsonEncode(
              mgr06Receipt(Map<String, dynamic>.from(jsonDecode(request.body))),
            ),
            201,
          ),
        ),
      );
      expect(result['amount'], '-120.34');
    },
  );
}
