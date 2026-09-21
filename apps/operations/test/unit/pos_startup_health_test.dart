import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';

void main() {
  test('background startup admits login only after Go verification', () async {
    final u = PosUpdater()..probation = true;
    addTearDown(u.dispose);
    var admitted = false;
    final waiting = u.waitForStartup().then((_) => admitted = true);
    await Future<void>.delayed(Duration.zero);
    expect(admitted, isFalse);
    expect(u.blockingOverlay, isFalse);
    u.probation = false;
    u.notifyListeners();
    await waiting;
    expect(admitted, isTrue);
  });

  test('background startup failure refuses login admission', () async {
    final u = PosUpdater()..probation = true;
    addTearDown(u.dispose);
    final waiting = expectLater(u.waitForStartup(), throwsStateError);
    u.startupFailure = 'Data recovery failed';
    u.notifyListeners();
    await waiting;
    expect(u.inputHeld, isTrue);
    expect(u.blockingOverlay, isTrue);
  });

  setUp(() {
    UpdateReadiness.startupReady = true;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    UpdateReadiness.recoveryChecks.clear();
    DatabaseCore.dbVersion = 9;
    DatabaseCore.dataDirectoryPath = '/isolated/hive';
  });
  tearDown(() {
    UpdateReadiness.recoveryChecks.clear();
  });
  PosUpdater client(
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)
    request,
  ) => PosUpdater(
    requestOverride: request,
    environmentOverride: {
      'VYNIC_POS_UPDATE_NONCE': 'test-nonce',
      'VYNIC_POS_UPDATE_VERSION': '1.0.2',
    },
    requestTimeout: const Duration(milliseconds: 30),
  )..probation = true;

  test(
    'publisher changes cannot redirect the pinned restaurant data',
    () async {
      final root = await Directory.systemTemp.createTemp('vynic-pinned-data-');
      addTearDown(() => root.delete(recursive: true));
      final legacy = await Directory(
        '${root.path}/vanski/Vynic POS',
      ).create(recursive: true);
      final marker = File('${legacy.path}/open-orders.hive');
      await marker.writeAsString('durable open orders');
      final config = File('${root.path}/config.json');
      await config.writeAsString(
        jsonEncode({'listen': '127.0.0.1:7444', 'token': 'local-test'}),
      );
      final u = PosUpdater(
        windowsOverride: true,
        environmentOverride: {'VYNIC_POS_UPDATER_CONFIG': config.path},
        requestOverride: (route, _) async {
          expect(route, 'status');
          return {'dataPath': legacy.path};
        },
      );
      addTearDown(u.dispose);
      expect(await u.pinnedDataDirectory(), legacy.path);
      expect(await marker.readAsString(), 'durable open orders');
      await legacy.delete(recursive: true);
      await expectLater(u.pinnedDataDirectory(), throwsStateError);
      expect(await legacy.exists(), isFalse);
    },
  );

  test('only a verified health handshake releases input', () async {
    var statuses = 0;
    final u = client((route, body) async {
      if (route == 'health') {
        expect(body!['nonce'], 'test-nonce');
        expect(body['pid'], pid);
        expect(body['hiveSchema'], 9);
        expect(body['dataPath'], '/isolated/hive');
        return {};
      }
      statuses++;
      return {'status': 'UP_TO_DATE', 'startupVerified': statuses > 1};
    });
    addTearDown(u.dispose);
    await u.refresh();
    expect(u.inputHeld, isFalse);
    expect(u.startupFailure, isNull);
  });
  test('readiness failure is visible and never sends false health', () async {
    UpdateReadiness.recoveryChecks.add(() => 'Unresolved close journal');
    final u = client((route, body) async {
      expect(route, 'status');
      return {'status': 'UP_TO_DATE'};
    });
    addTearDown(u.dispose);
    await u.refresh();
    expect(u.startupFailure, 'Unresolved close journal');
    expect(u.inputHeld, isTrue);
  });
  test(
    'rejected heartbeat exposes the server error while holding input',
    () async {
      final u = client((route, body) async {
        if (route == 'health')
          throw const HttpException('409 stale startup health');
        return {'status': 'FAILED', 'reason': 'POS startup health timeout'};
      });
      addTearDown(u.dispose);
      await u.refresh();
      expect(u.startupFailure, contains('stale startup health'));
      expect(u.startupFailure, contains('POS startup health timeout'));
      expect(u.inputHeld, isTrue);
    },
  );
  test(
    'unresponsive IPC times out instead of hanging the polling loop',
    () async {
      final u = client((_, __) => Completer<Map<String, dynamic>>().future);
      addTearDown(u.dispose);
      await u.refresh().timeout(const Duration(seconds: 1));
      expect(u.startupFailure, contains('TimeoutException'));
      expect(u.inputHeld, isTrue);
    },
  );
  test('nonce without configuration is an explicit startup failure', () async {
    final u = PosUpdater(
      windowsOverride: true,
      environmentOverride: {'VYNIC_POS_UPDATE_NONCE': 'nonce'},
    );
    addTearDown(u.dispose);
    await u.initialize();
    expect(u.configured, isFalse);
    expect(u.startupFailure, isNotNull);
    expect(u.inputHeld, isTrue);
  });
  test('bounded probation replaces waiting with an error', () async {
    final u = PosUpdater(
      startupTimeout: Duration.zero,
      requestOverride: (_, __) async => {'status': 'UP_TO_DATE'},
    )..probation = true;
    addTearDown(u.dispose);
    UpdateReadiness.recoveryChecks.add(() => 'recovering');
    await u.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(u.startupFailure, contains('დრო ამოიწურა'));
    expect(u.inputHeld, isTrue);
  });
}
