import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('manager_login_ux_');
    Hive.init(directory.path);
    await ManagerAppPreferences.init();
    await AuthTokenService.init();
    await MobileCacheService.init();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final size in [
    const Size(360, 800),
    const Size(768, 1024),
    const Size(1280, 900),
  ]) {
    testWidgets('code once, PIN login and restaurant switch at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      var authenticated = false;
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/manager-venue') {
          expect(jsonDecode(request.body), {'venueCode': 'venue-b'});
          return http.Response(
            jsonEncode({
              'id': 'b',
              'code': 'venue-b',
              'name': 'Vankisi',
              'branchName': 'ბათუმი — ცენტრი',
              'address': 'ბათუმი, რუსთაველის 1',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(jsonDecode(request.body), {
          'venueCode': 'venue-b',
          'pin': '123456',
        });
        return http.Response(
          jsonEncode({
            'venueCode': 'venue-b',
            'access_token': 'token-b',
            'role': 'MANAGER',
            'username': 'nino',
            'expiresIn': 86400,
          }),
          200,
        );
      });
      await tester.runAsync(
        () => AuthTokenService.saveToken(
          token: 'old-origin',
          role: 'MANAGER',
          username: 'old',
          expiresInSeconds: 86400,
          venueCode: 'venue-b',
        ),
      );
      Widget screen() => MaterialApp(
        home: MobileLoginScreen(
          client: client,
          onAuthenticated: (_) => authenticated = true,
        ),
      );
      await tester.pumpWidget(screen());
      final field = find.byKey(const Key('manager-venue-code'));
      expect(field, findsOneWidget);
      expect(find.text('შესვლა'), findsNothing);
      await tester.enterText(field, ' VENUE-B ');
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('გაგრძელება'));
      await tester.runAsync(() => tester.tap(find.text('გაგრძელება')));
      // Hive writes complete outside the widget fake clock.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(field, findsNothing);
      expect(find.text('Vankisi'), findsOneWidget);
      expect(find.text('ბათუმი — ცენტრი'), findsOneWidget);
      expect(find.text('ბათუმი, რუსთაველის 1'), findsOneWidget);
      expect(AuthTokenService.token, isNull);
      expect(requests, hasLength(1));
      // A real preferences reopen simulates the next application launch.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Hive.box('manager_preferences').close();
        await ManagerAppPreferences.init();
      });
      await tester.pumpWidget(screen());
      expect(field, findsNothing);
      expect(find.text('Vankisi'), findsOneWidget);
      for (final digit in '123456'.split('')) {
        await tester.ensureVisible(find.text(digit));
        await tester.runAsync(() => tester.tap(find.text(digit)));
        await tester.pump();
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(authenticated, isTrue);
      expect(requests, hasLength(2));
      expect(AuthTokenService.venueCode, 'venue-b');
      for (final box in [
        'manager_preferences',
        'auth_tokens',
        'mobile_manager_cache',
      ]) {
        expect(Hive.box(box).toMap().toString(), isNot(contains('123456')));
      }
      await tester.runAsync(() async {
        await MobileAuthService.logout();
        await MobileCacheService.setLastNotificationsSyncAt('old-venue-data');
      });
      expect(
        ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl)?.code,
        'venue-b',
      );
      await tester.ensureVisible(find.text('რესტორნის შეცვლა'));
      await tester.runAsync(() => tester.tap(find.text('რესტორნის შეცვლა')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(field, findsOneWidget);
      expect(ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl), isNull);
      expect(AuthTokenService.token, isNull);
      expect(MobileCacheService.lastNotificationsSyncAt, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'unavailable code never persists selection; production hides API controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileLoginScreen(
            client: MockClient((_) async => http.Response('{}', 401)),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('manager-venue-code')),
        'unknown',
      );
      await tester.ensureVisible(find.text('გაგრძელება'));
      await tester.runAsync(() async {
        await tester.tap(find.text('გაგრძელება'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl), isNull);
      expect(find.textContaining('რესტორანი ვერ მოიძებნა'), findsOneWidget);
      if (!ApiConfig.allowDeveloperOverride) {
        expect(find.textContaining('Backend'), findsNothing);
        expect(find.textContaining('http'), findsNothing);
        expect(find.textContaining('localhost'), findsNothing);
        expect(find.textContaining('127.0.0.1'), findsNothing);
        expect(find.textContaining('API'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
