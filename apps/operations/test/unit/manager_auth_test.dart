import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/contracts/manager_login.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('manager_auth_');
    Hive.init(directory.path);
    await AuthTokenService.init();
    await ManagerAppPreferences.init();
    await MobileCacheService.init();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'one-use linking retries with a durable origin-scoped installation identity and stores no code or PIN',
    () async {
      const code = '7K2Q-M4XB-9TFR-ABCD-EFGH';
      final identities = <String>[];
      var ready = false;
      final client = MockClient((request) async {
        expect(request.url.path, '/auth/manager-link');
        final body = jsonDecode(request.body) as Map;
        expect(body['code'], code);
        expect(body.containsKey('venueId'), false);
        expect(body.containsKey('pin'), false);
        identities.add(body['installationId'] as String);
        return ready
            ? http.Response(
                jsonEncode({'id': 'b', 'code': 'venue-b', 'name': 'B'}),
                200,
              )
            : http.Response('{}', 503);
      });
      await expectLater(
        MobileAuthService.linkVenue(code, client: client),
        throwsA(MobileAuthError.serverError),
      );
      await Hive.box('manager_preferences').close();
      await ManagerAppPreferences.init();
      ready = true;
      final selection = await MobileAuthService.linkVenue(code, client: client);
      await ManagerAppPreferences.rememberVenue(selection);
      expect(identities[0] == identities[1], true);
      expect(
        ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl)?.code,
        'venue-b',
      );
      expect(
        Hive.box('manager_preferences').toMap().toString().contains(code),
        false,
      );
      expect(AuthTokenService.token, isNull);
    },
  );
  test(
    'concurrent linking and preferences reopen retain one UUID per origin',
    () async {
      final ids = await Future.wait([
        ManagerAppPreferences.linkInstallationId(ApiConfig.baseUrl),
        ManagerAppPreferences.linkInstallationId(ApiConfig.baseUrl),
      ]);
      expect(ids[0] == ids[1], true);
      final foreign = await ManagerAppPreferences.linkInstallationId(
        'https://another.invalid',
      );
      expect(foreign == ids[0], false);
      await Hive.box('manager_preferences').close();
      await ManagerAppPreferences.init();
      expect(
        await ManagerAppPreferences.linkInstallationId(ApiConfig.baseUrl) ==
            ids[0],
        true,
      );
    },
  );
  test(
    'malformed linking success and denied linking do not establish selection or session',
    () async {
      for (final response in [
        http.Response('invalid', 200),
        http.Response('{}', 401),
        http.Response('{}', 429),
      ]) {
        await expectLater(
          MobileAuthService.linkVenue(
            'synthetic-code',
            client: MockClient((_) async => response),
          ),
          throwsA(isA<MobileAuthError>()),
        );
        expect(ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl), isNull);
        expect(AuthTokenService.token, isNull);
      }
    },
  );

  for (final entry in {
    403: MobileAuthError.accessDenied,
    429: MobileAuthError.rateLimited,
    500: MobileAuthError.serverError,
  }.entries) {
    test(
      'HTTP ${entry.key} keeps its category and cannot look like offline network access',
      () async {
        await expectLater(
          MobileAuthService.login(
            '481259',
            venueCode: 'synthetic',
            client: MockClient((_) async => http.Response('{}', entry.key)),
          ),
          throwsA(entry.value),
        );
        expect(AuthTokenService.token, isNull);
      },
    );
  }
  test('invalid response is a server error, not offline access', () async {
    await expectLater(
      MobileAuthService.login(
        '481259',
        venueCode: 'synthetic',
        client: MockClient((_) async => http.Response('invalid-json', 200)),
      ),
      throwsA(MobileAuthError.serverError),
    );
  });

  test(
    'selection is origin-bound and ignores extra credential fields',
    () async {
      final selection = await MobileAuthService.resolveVenue(
        'venue-b',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'id': 'b',
              'code': 'venue-b',
              'name': 'B',
              'pin': '654321',
              'access_token': 'not-a-session',
            }),
            200,
          ),
        ),
      );
      await ManagerAppPreferences.rememberVenue(selection);
      expect(
        ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl)?.code,
        'venue-b',
      );
      expect(
        ManagerAppPreferences.selectedVenue('https://another.invalid'),
        isNull,
      );
      expect(
        Hive.box('manager_preferences').values.toString(),
        isNot(contains('654321')),
      );
      expect(
        Hive.box('manager_preferences').values.toString(),
        isNot(contains('not-a-session')),
      );
      expect(AuthTokenService.token, isNull);
    },
  );

  test(
    'production network failures never expose endpoint details to UI',
    () async {
      await http.runWithClient(
        () async {
          try {
            await MobileApiService.registerPushDevice('test-token');
            fail('Expected a network error');
          } catch (error) {
            if (!ApiConfig.allowDeveloperOverride) {
              expect(error.toString(), isNot(contains('10.10.10.3')));
              expect(error.toString(), isNot(contains('3000')));
              expect(
                error.toString(),
                contains('სერვერთან კავშირი ვერ დამყარდა'),
              );
            } else {
              expect(error, isA<SocketException>());
            }
          }
        },
        () => MockClient(
          (_) async => throw const SocketException('http://10.10.10.3:3000'),
        ),
      );
    },
  );

  test(
    'Venue code and PIN use the generated contract; repeat login remembers only code',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, ManagerLoginContract.path);
        expect(jsonDecode(request.body), {
          'venueCode': 'venue-b',
          'pin': '123456',
        });
        return http.Response(
          jsonEncode({
            'access_token': 'token-b',
            'role': 'MANAGER',
            'username': 'manager',
            'expiresIn': 86400,
            'venueCode': 'venue-b',
          }),
          200,
        );
      });
      await AuthTokenService.saveToken(
        token: 'token-a',
        role: 'MANAGER',
        username: 'manager',
        expiresInSeconds: 86400,
        venueCode: 'venue-a',
      );
      await MobileCacheService.setLastNotificationsSyncAt('venue-a-data');
      final result = await MobileAuthService.login(
        '123456',
        venueCode: ' VENUE-B ',
        client: client,
      );
      expect(result.accessToken, 'token-b');
      expect(ManagerAppPreferences.loginVenueCode, 'venue-b');
      expect(AuthTokenService.venueCode, 'venue-b');
      expect(MobileCacheService.lastNotificationsSyncAt, isNull);
      expect(MobileAuthService.tryOfflineAccess(venueCode: 'venue-a'), isNull);
      expect(
        MobileAuthService.tryOfflineAccess(venueCode: 'venue-b')?.username,
        'manager',
      );
      for (final boxName in [
        'manager_preferences',
        'auth_tokens',
        'mobile_manager_cache',
      ]) {
        expect(Hive.box(boxName).values.toString(), isNot(contains('123456')));
      }
      await MobileAuthService.logout();
      expect(AuthTokenService.token, isNull);
      expect(ManagerAppPreferences.loginVenueCode, 'venue-b');
    },
  );

  test(
    'wrong credentials do not create a token or remember an unverified Venue',
    () async {
      final client = MockClient((_) async => http.Response('{}', 401));
      await expectLater(
        MobileAuthService.login(
          '123456',
          venueCode: 'wrong-venue',
          client: client,
        ),
        throwsA(MobileAuthError.invalidPin),
      );
      expect(AuthTokenService.token, isNull);
      expect(ManagerAppPreferences.loginVenueCode, isNull);
    },
  );

  test(
    'an old backend which ignores the Venue code cannot create a session',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'old-bootstrap-token',
            'role': 'MANAGER',
            'username': 'manager',
            'expiresIn': 86400,
          }),
          200,
        ),
      );
      await expectLater(
        MobileAuthService.login('123456', venueCode: 'venue-b', client: client),
        throwsA(MobileAuthError.accessDenied),
      );
      expect(AuthTokenService.token, isNull);
    },
  );

  test('network failure cannot open another Venue cached session', () async {
    await AuthTokenService.saveToken(
      token: 'old',
      role: 'MANAGER',
      username: 'manager',
      expiresInSeconds: 86400,
      venueCode: 'venue-a',
    );
    final client = MockClient(
      (_) async => throw const SocketException('offline'),
    );
    await expectLater(
      MobileAuthService.login('123456', venueCode: 'venue-b', client: client),
      throwsA(MobileAuthError.networkError),
    );
    expect(MobileAuthService.tryOfflineAccess(venueCode: 'venue-b'), isNull);
  });
}
