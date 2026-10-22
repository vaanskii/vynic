import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/sync/connection_status_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'full POS mirror retries, refreshes idle sources and preserves in-flight work',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'manager-sync-owned-',
      );
      await DatabaseCore.open(managedDataDirectory: directory.path);
      addTearDown(() async {
        ManagerSyncService.dispose();
        await Hive.close();
        await directory.delete(recursive: true);
      });
      final snapshots = <Map<String, dynamic>>[];
      var fail = true;
      Completer<http.Response>? held;
      Future<void> settle(bool Function() ready) async {
        for (var i = 0; i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (ready()) return;
        }
        throw StateError(
          'Synthetic snapshot did not settle: count=${snapshots.length} state=${ConnectionStatusService.backendState.value} pending=${ConnectionStatusService.hasPendingLocalChanges.value}',
        );
      }

      Future<void> push(Future<void> Function() action) async {
        var done = false;
        final pending = action();
        pending.whenComplete(() => done = true);
        await settle(() => done);
        await pending;
      }

      await http.runWithClient(
        () async {
          ManagerSyncService.initializeForTesting(
            retryInterval: const Duration(milliseconds: 40),
            refreshInterval: const Duration(milliseconds: 160),
            startupDelay: const Duration(milliseconds: 10),
          );

          await settle(
            () =>
                snapshots.length == 1 &&
                ConnectionStatusService.backendState.value ==
                    BackendConnectionState.offline,
          );
          fail = false;

          await settle(
            () =>
                snapshots.length >= 2 &&
                ConnectionStatusService.backendState.value ==
                    BackendConnectionState.connected,
          );
          await push(ManagerSyncService.syncToManagerApp);
          final beforeIdle = snapshots.length;
          expect(ConnectionStatusService.hasPendingLocalChanges.value, isFalse);

          await settle(
            () =>
                snapshots.length > beforeIdle &&
                ConnectionStatusService.backendState.value ==
                    BackendConnectionState.connected,
          );
          await push(ManagerSyncService.syncToManagerApp);
          expect(snapshots.last['realtimeOnly'], isNot(true));
          expect(snapshots.last, contains('saleLedgerDays'));

          ManagerSyncService.dispose();
          ManagerSyncService.syncToManagerAppDebounced();
          final beforeHeld = snapshots.length;
          held = Completer<http.Response>();
          final full = ManagerSyncService.syncToManagerApp();
          await settle(() => snapshots.length == beforeHeld + 1);
          ManagerSyncService.syncToManagerAppDebounced();
          held!.complete(
            http.Response('{"success":true,"saleLedgerAck":[]}', 201),
          );
          await push(() => full);
          held = null;
          expect(
            ConnectionStatusService.hasPendingLocalChanges.value,
            isTrue,
            reason:
                'The completed request did not contain the later local revision',
          );

          ManagerSyncService.initializeForTesting(
            retryInterval: const Duration(milliseconds: 40),
            refreshInterval: const Duration(days: 1),
            startupDelay: const Duration(days: 1),
          );
          await settle(
            () =>
                snapshots.length >= beforeHeld + 2 &&
                !ConnectionStatusService.hasPendingLocalChanges.value,
          );

          await push(ManagerSyncService.syncToManagerApp);
          ManagerSyncService.dispose();
          ManagerSyncService.syncToManagerAppDebounced();
          await push(ManagerSyncService.syncRealtimeToManagerApp);
          expect(snapshots.last['realtimeOnly'], isTrue);
          expect(
            ConnectionStatusService.hasPendingLocalChanges.value,
            isTrue,
            reason:
                'An operational-only snapshot cannot acknowledge full reporting work',
          );
          await push(ManagerSyncService.syncToManagerApp);
          expect(ConnectionStatusService.hasPendingLocalChanges.value, isFalse);
          final count = snapshots.length;
          ManagerSyncService.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(snapshots, hasLength(count));
        },
        () => MockClient((request) async {
          if (!request.url.path.startsWith('/sync/'))
            throw StateError('Unexpected fixture URL');
          if (request.url.path == '/sync/manager-data') {
            snapshots.add(jsonDecode(request.body) as Map<String, dynamic>);
            if (held != null) return held!.future;
            return http.Response(
              fail ? '{}' : '{"success":true,"saleLedgerAck":[]}',
              fail ? 503 : 201,
            );
          }
          return http.Response('{"acknowledged":[]}', 200);
        }),
      );
    },
  );
}
