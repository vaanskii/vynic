import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_notification_page.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/core/services/notifications/manager_notification_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const checkpoint = '2026-10-07T09:00:00.000Z';
  const watermark = '2026-10-07T10:00:00.000Z';
  final history = AppNotificationHistoryStore.instance;

  Future<void> session(String subject) => AuthTokenService.saveToken(
    token:
        'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': subject})))}.unsigned',
    username: 'Synthetic Manager',
    role: 'MANAGER',
    expiresInSeconds: 3600,
    venueCode: subject,
  );

  Map<String, dynamic> row(int id) => {
    'id': 'notification-$id',
    'title': 'Synthetic notification',
    'body': 'Notification $id',
  };

  http.Response page(
    List<Map<String, dynamic>> items, {
    String? cursor,
    String serverWatermark = watermark,
  }) => http.Response(
    jsonEncode({
      'items': items,
      'watermark': serverWatermark,
      'nextCursor': cursor,
    }),
    200,
  );

  Future<int> catchUp(FutureOr<http.Response> Function(http.Request) handler) =>
      http.runWithClient(
        ManagerNotificationInbox.syncMissedFromServer,
        () => MockClient((request) async => await handler(request)),
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('notification-inbox-');
    Hive.init(directory.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    await session('venue-a');
    ManagerNotificationInbox.resetSession();
  });

  tearDown(() async {
    ManagerNotificationInbox.resetSession();
    ManagerAppPreferences.backendUrlOverride.value = null;
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('drains beyond 100 rows before saving the server watermark', () async {
    await MobileCacheService.setLastNotificationsSyncAt(checkpoint);
    final requests = <Uri>[];
    final added = await catchUp((request) {
      requests.add(request.url);
      expect(request.method, 'GET');
      expect(request.url.path, '/mobile/notifications/page');
      expect(request.url.queryParameters['since'], '2026-10-07T08:59:00.000Z');
      expect(MobileCacheService.lastNotificationsSyncAt, checkpoint);
      if (requests.length == 1) {
        expect(request.url.queryParameters['cursor'], isNull);
        return page(List.generate(100, row), cursor: 'second-page');
      }
      expect(request.url.queryParameters['cursor'], 'second-page');
      return page(List.generate(25, (index) => row(index + 100)));
    });

    expect(added, 125);
    expect(requests, hasLength(2));
    // The panel intentionally retains only its most recent 100 entries. Every
    // fetched page is nevertheless ingested before advancing the checkpoint.
    expect(history.entries.value, hasLength(100));
    expect(history.entries.value.first.id, 'notification-124');
    expect(MobileCacheService.lastNotificationsSyncAt, watermark);
    await Hive.box('mobile_manager_cache').close();
    await MobileCacheService.init();
    expect(MobileCacheService.lastNotificationsSyncAt, watermark);
  });

  test(
    'initial catch-up uses the server window regardless of client date',
    () async {
      expect(DateTime.now().toUtc().toIso8601String(), isNot(watermark));
      await catchUp((request) {
        expect(request.url.queryParameters.containsKey('since'), isFalse);
        return page([row(1)]);
      });
      expect(MobileCacheService.lastNotificationsSyncAt, watermark);
      await catchUp((request) {
        expect(
          request.url.queryParameters['since'],
          '2026-10-07T09:59:00.000Z',
        );
        return page([]);
      });
    },
  );

  test(
    'a failed later page retains checkpoint and replay deduplicates rows',
    () async {
      await MobileCacheService.setLastNotificationsSyncAt(checkpoint);
      var failed = false;
      Future<http.Response> respond(http.Request request) async {
        if (request.url.queryParameters['cursor'] == null) {
          return page([row(1)], cursor: 'second-page');
        }
        if (!failed) return http.Response('Synthetic unavailable', 503);
        return page([row(2)]);
      }

      expect(await catchUp(respond), 0);
      expect(history.entries.value.map((entry) => entry.id), [
        'notification-1',
      ]);
      expect(MobileCacheService.lastNotificationsSyncAt, checkpoint);
      failed = true;
      expect(await catchUp(respond), 1);
      expect(history.entries.value.map((entry) => entry.id), [
        'notification-2',
        'notification-1',
      ]);
      expect(MobileCacheService.lastNotificationsSyncAt, watermark);
    },
  );

  for (final change in ['reset', 'principal', 'origin']) {
    test(
      '$change during an in-flight page cannot ingest or checkpoint it',
      () async {
        await MobileCacheService.setLastNotificationsSyncAt(checkpoint);
        final response = Completer<http.Response>();
        final requested = Completer<void>();
        final pending = catchUp((request) {
          requested.complete();
          return response.future;
        });
        await requested.future;
        if (change == 'reset') {
          ManagerNotificationInbox.resetSession();
        } else if (change == 'principal') {
          await session('venue-b');
        } else {
          ManagerAppPreferences.backendUrlOverride.value =
              'http://127.0.0.1:54321';
        }
        response.complete(page([row(1)]));
        expect(await pending, 0);
        expect(history.entries.value, isEmpty);
        expect(MobileCacheService.lastNotificationsSyncAt, checkpoint);
      },
    );
  }

  for (final failure in ['watermark', 'cursor', 'malformed']) {
    test('$failure mismatch preserves the previous checkpoint', () async {
      await MobileCacheService.setLastNotificationsSyncAt(checkpoint);
      var calls = 0;
      expect(
        await catchUp((request) {
          calls++;
          if (calls == 1) return page([row(1)], cursor: 'second-page');
          if (failure == 'watermark') {
            return page([row(2)], serverWatermark: '2026-10-07T10:01:00.000Z');
          }
          if (failure == 'cursor') return page([row(2)], cursor: 'second-page');
          return http.Response('{"items":[],"watermark":"invalid"}', 200);
        }),
        0,
      );
      expect(calls, 2);
      expect(MobileCacheService.lastNotificationsSyncAt, checkpoint);
    });
  }

  test('notification page parser rejects structurally unusable responses', () {
    for (final value in [
      null,
      [],
      {'items': 'invalid', 'watermark': watermark},
      {
        'items': [null],
        'watermark': watermark,
      },
      {'items': [], 'watermark': 'invalid'},
      {'items': [], 'watermark': watermark, 'nextCursor': ''},
    ]) {
      expect(
        () => ManagerNotificationPage.fromJson(value),
        throwsFormatException,
      );
    }
  });
}
