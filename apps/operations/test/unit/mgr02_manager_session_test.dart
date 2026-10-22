import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/manager_app/table_repair_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  Future<void> session(String principal) => AuthTokenService.saveToken(
    token:
        'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': principal})))}.unsigned',
    username: 'Synthetic manager',
    role: 'MANAGER',
    expiresInSeconds: 3600,
    venueCode: principal,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr02-session-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await TableRepairRequests.init();
    await session('first-principal');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  for (final changed in [
    'principal',
    'logout',
    'malformed',
    'array_claims',
    'null_claims',
  ]) {
    test(
      '$changed session refuses initial repair before persistence and HTTP',
      () async {
        final scope = MobileApiService.tableRepairScope;
        if (changed == 'principal') {
          await session('second-principal');
        }
        if (changed == 'logout') {
          await AuthTokenService.clearToken();
        }
        if (changed == 'malformed') {
          await AuthTokenService.saveToken(
            token: 'bad',
            username: 'Synthetic',
            role: 'MANAGER',
            expiresInSeconds: 3600,
          );
        }
        if (changed.endsWith('_claims')) {
          final value = changed == 'array_claims' ? [] : null;
          await AuthTokenService.saveToken(
            token:
                'synthetic.${base64Url.encode(utf8.encode(jsonEncode(value)))}.unsigned',
            username: 'Synthetic',
            role: 'MANAGER',
            expiresInSeconds: 3600,
          );
        }
        expect(MobileApiService.isCurrentTableRepairScope(scope), isFalse);
        var calls = 0;
        final result = await http.runWithClient(
          () => MobileApiService.freeTable('7', 'first', expectedScope: scope),
          () => MockClient((_) async {
            calls++;
            throw StateError('Unexpected HTTP');
          }),
        );
        expect(result.isError, isTrue);
        expect(result.isDone, isFalse);
        expect(result.code, 'session_changed');
        expect(result.message, contains('სესია შეიცვალა'));
        expect(calls, 0);
        expect(Hive.box(TableRepairRequests.boxName).isEmpty, isTrue);
      },
    );
  }
}
