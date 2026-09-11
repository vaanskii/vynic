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
