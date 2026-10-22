@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';
import 'package:vynic/core/contracts/manager_login.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/core/services/edge/edge_enrollment_client.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

/// Live proof of the Docker native API ingress, through the app's own clients.
///
/// Skipped unless NATIVE_INGRESS_FIXTURE names a JSON file:
///   {"venues": {"A": {"id","loginCode","pin","enrollmentCode"}, "B": {...}}}
/// (one-time enrollment codes; see docs/DEPLOYMENT.md "Native POS / Manager
/// ingress"). Run from apps/operations with the origin under test in BOTH the
/// environment and the build define, because ApiConfig reads a compile-time value:
///
///   NATIVE_INGRESS_FIXTURE=/path/fixture.json \
///   NATIVE_INGRESS_API=http://api.vynic.localhost \
///   flutter test --dart-define=VYNIC_API_URL=http://api.vynic.localhost \
///     test/live/native_ingress_live_test.dart
///
/// The Venue is never supplied by the client: every assertion below derives it
/// from the Device credential or Staff session the client authenticated with.
final env = Platform.environment;
final fixturePath = env['NATIVE_INGRESS_FIXTURE'];
final apiUrl = env['NATIVE_INGRESS_API'];
final holdSeconds = int.tryParse(env['NATIVE_INGRESS_HOLD_SECONDS'] ?? '') ?? 0;

class Fixture {
  Fixture(this.id, this.loginCode, this.pin, this.enrollmentCode);
  final String id, loginCode, pin, enrollmentCode;
}

Fixture _load(Map<String, dynamic> venues, String key) {
  final v = venues[key] as Map<String, dynamic>;
  return Fixture(
    v['id'] as String,
    v['loginCode'] as String,
    v['pin'] as String,
    v['enrollmentCode'] as String,
  );
}

Future<Map<String, dynamic>> _json(http.Response r) async =>
    jsonDecode(r.body) as Map<String, dynamic>;

Future<io.Socket> _connect(String token, {Duration? wait}) async {
  // Same transport/auth options as MonitoringSocketService._connect.
  final socket = io.io(
    ApiConfig.baseUrl,
    io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setTimeout(10000)
        .setAuth(<String, dynamic>{'token': token})
        .build(),
  );
  final connected = Completer<void>();
  socket.onConnect((_) {
    if (!connected.isCompleted) connected.complete();
  });
  socket.onConnectError((e) {
    if (!connected.isCompleted) connected.completeError(StateError('$e'));
  });
  socket.connect();
  await connected.future.timeout(wait ?? const Duration(seconds: 10));
  return socket;
}

void main() {
  final skip = fixturePath == null || apiUrl == null
      ? 'NATIVE_INGRESS_FIXTURE / NATIVE_INGRESS_API not set'
      : null;

  test(
    'native ingress: POS, Manager, tenancy and realtime',
    () async {
      final venues =
          (jsonDecode(File(fixturePath!).readAsStringSync())
                  as Map<String, dynamic>)['venues']
              as Map<String, dynamic>;
      final a = _load(venues, 'A');
      final b = _load(venues, 'B');
      final base = ApiConfig.normalizeEditableBackendUrl(apiUrl!)!;
      expect(base, apiUrl, reason: 'the typed URL must survive normalization');
      expect(ApiConfig.baseUrl, base, reason: 'define and env must agree');

      // ── Health and unknown-route behavior are the backend's, not a frontend's.
      final health = await http.get(Uri.parse('$base/healthz'));
      expect(health.statusCode, 200);
      expect((await _json(health))['status'], 'ok');
      final unknown = await http.get(Uri.parse('$base/edge/no-such-route'));
      expect(unknown.statusCode, 404);
      expect(unknown.headers['content-type'], contains('application/json'));
      expect(unknown.body, isNot(contains('<html')));

      // ── POS: enrollment through the real client, credential -> Venue.
      final enrollment = EdgeEnrollmentClient();
      Future<EdgeEnrollmentResult> enroll(Fixture f, String tag) =>
          enrollment.enroll(
            baseUrl: base,
            code: f.enrollmentCode,
            installationId: const Uuid().v4(),
            platform: 'macos',
            displayName: 'Native ingress live $tag',
          );
      final ea = await enroll(a, 'A');
      final eb = await enroll(b, 'B');
      expect(ea.isEnrolled, isTrue, reason: '${ea.outcome} ${ea.message}');
      expect(eb.isEnrolled, isTrue, reason: '${eb.outcome} ${eb.message}');
      expect(ea.venueId, a.id);
      expect(eb.venueId, b.id);
      // ignore: avoid_print
      print('offered apiBaseUrl: ${ea.apiBaseUrl}');

      Future<Map<String, dynamic>> runtimeConfig(
        String credential, {
        String query = '',
        Map<String, String> extra = const {},
      }) async {
        final r = await http.get(
          Uri.parse('$base/edge/runtime-config$query'),
          headers: {'X-POS-Sync-Key': credential, ...extra},
        );
        expect(r.statusCode, 200);
        return _json(r);
      }

      final cfgA = await runtimeConfig(ea.credential!);
      final cfgB = await runtimeConfig(eb.credential!);
      expect((cfgA['venue'] as Map)['id'], a.id);
      expect((cfgB['venue'] as Map)['id'], b.id);
      // A terminal cannot name a Venue: query, headers and a forged host are inert.
      final spoofed = await runtimeConfig(
        ea.credential!,
        query: '?venueId=${b.id}',
        extra: {'X-Venue-Id': b.id, 'X-Forwarded-Host': 'beta.vynic.localhost'},
      );
      expect((spoofed['venue'] as Map)['id'], a.id);
      // Device transport (claim) works through the ingress and is Venue-scoped.
      final claimA = await EdgeTransportClient(
        baseUrl: () => base,
        credential: () => ea.credential,
      ).claim();
      expect(claimA.outcome, EdgeTransportOutcome.ok);
      // The legacy shared-key path is not a way in.
      final bad = await http.get(
        Uri.parse('$base/edge/runtime-config'),
        headers: {'X-POS-Sync-Key': 'not-a-device-credential'},
      );
      expect(bad.statusCode, 401);

      // ── Manager: Restaurant Code, PIN, API access, tenant resolution.
      final venueA = await MobileAuthService.resolveVenue(a.loginCode);
      final venueB = await MobileAuthService.resolveVenue(b.loginCode);
      expect(venueA.code, a.loginCode);
      expect(venueB.code, b.loginCode);

      Future<String> login(Fixture f) async {
        final r = await http.post(
          Uri.parse('$base${ManagerLoginContract.path}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            ManagerLoginContract.pinField: f.pin,
            ManagerLoginContract.venueCodeField: f.loginCode,
          }),
        );
        expect(r.statusCode, 200);
        return (await _json(r))['access_token'] as String;
      }

      final tokenA = await login(a);
      final tokenB = await login(b);
      Future<String> managerVenue(
        String token, {
        String query = '',
        Map<String, String> extra = const {},
      }) async {
        final r = await http.get(
          Uri.parse('$base/mobile/entitlements$query'),
          headers: {'Authorization': 'Bearer $token', ...extra},
        );
        expect(r.statusCode, 200);
        return ((await _json(r))['profile'] as Map)['id'] as String;
      }

      expect(await managerVenue(tokenA), a.id);
      expect(await managerVenue(tokenB), b.id);
      expect(
        await managerVenue(
          tokenA,
          query: '?venueId=${b.id}',
          extra: {
            'X-Venue-Id': b.id,
            'X-Forwarded-Host': 'beta.vynic.localhost',
          },
        ),
        a.id,
      );
      final wrongPin = await http.post(
        Uri.parse('$base${ManagerLoginContract.path}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ManagerLoginContract.pinField: a.pin,
          ManagerLoginContract.venueCodeField: b.loginCode,
        }),
      );
      expect(
        wrongPin.statusCode,
        isNot(200),
        reason: 'A PIN is not valid at B',
      );

      // ── Realtime: the app's real MonitoringSocketService over the ingress.
      final hive = await Directory.systemTemp.createTemp(
        'native-ingress-hive-',
      );
      Hive.init(hive.path);
      await AuthTokenService.init();
      await AuthTokenService.saveToken(
        venueCode: a.loginCode,
        token: tokenA,
        role: 'MANAGER',
        username: 'nativeproof',
        expiresInSeconds: 3600,
      );
      MonitoringSocketService.initialize();
      final until = DateTime.now().add(const Duration(seconds: 12));
      while (!MonitoringSocketService.isConnected.value &&
          DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(MonitoringSocketService.isConnected.value, isTrue);
      expect(MonitoringSocketService.monitoringSocketId, isNotNull);

      // Room isolation: an event caused in Venue A reaches A's second socket and
      // never B's. (A's REST call carries no socket id, so nobody is echo-skipped.)
      final socketA2 = await _connect(tokenA);
      final socketB = await _connect(tokenB);
      final eventsA = <String>[];
      final eventsB = <String>[];
      for (final type in ['data_updated', 'order_created', 'table_updated']) {
        socketA2.on(type, (_) => eventsA.add(type));
        socketB.on(type, (_) => eventsB.add(type));
      }
      final counterBefore = MonitoringSocketService.updateCounter.value;
      final created = await http.post(
        Uri.parse('$base/mobile/reservations'),
        headers: {
          'Authorization': 'Bearer $tokenA',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'customerName': 'Native ingress live',
          'customerPhone': '+995555000001',
          'tableNumbers': [1],
          'reservationDate': '2026-10-02',
          'reservationTime': '20:00',
          'numberOfGuests': 2,
          'status': 'confirmed',
          'preOrderItems': <Object>[],
        }),
      );
      expect(created.statusCode, 201);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        eventsA,
        isNotEmpty,
        reason: 'Venue A manager socket got the event',
      );
      expect(eventsB, isEmpty, reason: 'Venue B manager socket saw nothing');
      expect(
        MonitoringSocketService.updateCounter.value,
        greaterThan(counterBefore),
        reason: 'the app service itself received the push',
      );

      // Device claim works through the ingress for both Venues; Venue B's Device
      // never receives work created in Venue A. (Enrollment does not designate a
      // Primary POS, so this Venue still uses legacy delivery and A's queue is empty.)
      final claimedA = await EdgeTransportClient(
        baseUrl: () => base,
        credential: () => ea.credential,
      ).claim();
      final claimedB = await EdgeTransportClient(
        baseUrl: () => base,
        credential: () => eb.credential,
      ).claim();
      expect(claimedA.outcome, EdgeTransportOutcome.ok);
      expect(claimedB.outcome, EdgeTransportOutcome.ok);
      expect(claimedB.commands, isEmpty);

      if (holdSeconds > 0) {
        // Long-lived connection through the proxy: pings keep it up past every
        // default idle timeout, and it is still delivering afterwards.
        await Future<void>.delayed(Duration(seconds: holdSeconds));
        expect(MonitoringSocketService.isConnected.value, isTrue);
        expect(socketA2.connected, isTrue);
        expect(socketB.connected, isTrue);
        eventsA.clear();
        final again = await http.post(
          Uri.parse('$base/mobile/reservations'),
          headers: {
            'Authorization': 'Bearer $tokenA',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'customerName': 'Native ingress live hold',
            'customerPhone': '+995555000002',
            'tableNumbers': [2],
            'reservationDate': '2026-10-02',
            'reservationTime': '21:00',
            'numberOfGuests': 2,
            'status': 'confirmed',
            'preOrderItems': <Object>[],
          }),
        );
        expect(again.statusCode, 201);
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(eventsA, isNotEmpty, reason: 'event delivered after idle hold');
      }

      socketA2.dispose();
      socketB.dispose();
      MonitoringSocketService.dispose();
      await Hive.close();
      await hive.delete(recursive: true);
      // ignore: avoid_print
      print(
        'PASS enroll A/B (${ea.venueName}/${eb.venueName}), commands A=${claimedA.commands.length} B=${claimedB.commands.length}',
      );
    },
    skip: skip,
    timeout: Timeout(Duration(seconds: 120 + holdSeconds)),
  );
}
