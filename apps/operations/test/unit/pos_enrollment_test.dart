import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_enrollment_client.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';

/// POS self-enrollment: what a terminal sends, what it keeps, and what it
/// refuses to do to itself.
///
/// The properties that matter here are the ones a restaurant would feel: a
/// terminal must never claim it is connected when the credential did not reach
/// the disk, must never adopt an address that cannot reach the server it just
/// talked to, and must never announce a venue it was not actually enrolled into.
void main() {
  const venueId = '22222222-2222-4222-8222-222222222222';
  const deviceId = '11111111-1111-4111-8111-111111111111';
  final credential = 'vynic-device-v1.$deviceId.${'a' * 43}';

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos-enrollment-');
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    EdgeDeviceCredentialStore.resetForTest();
  });

  tearDown(() async {
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  String successBody({String? apiBaseUrl}) => json.encode(<String, dynamic>{
    'enrollmentId': 'aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'device': {
      'id': deviceId,
      'installationId': '88888888-8888-4888-8888-888888888888',
      'displayName': 'Front POS',
      'platform': 'WINDOWS',
      'status': 'ACTIVE',
    },
    'venue': {
      'id': venueId,
      'name': 'Vankisi',
      'timezone': 'Asia/Tbilisi',
      'currency': 'GEL',
    },
    'credential': credential,
    'apiBaseUrl': apiBaseUrl,
    'edgeContractVersion': 1,
    'reusedExistingDevice': false,
    'enrolledAt': '2026-09-03T10:00:00.000Z',
  });

  EdgeEnrollmentClient clientFor(
    Future<http.Response> Function(http.Request request) handler,
  ) => EdgeEnrollmentClient(httpClient: MockClient(handler));

  group('the enrollment request', () {
    test('carries the code and installation, and never a venue', () async {
      late http.Request captured;
      final client = clientFor((request) async {
        captured = request;
        return http.Response(successBody(), 200);
      });

      final result = await client.enroll(
        baseUrl: 'http://10.0.0.3:3000',
        code: '7K2Q-M4XB-9TFR',
        installationId: '88888888-8888-4888-8888-888888888888',
        platform: 'WINDOWS',
      );

      expect(captured.url.path, '/edge/enroll');
      final body = json.decode(captured.body) as Map<String, dynamic>;
      expect(body['enrollmentCode'], '7K2Q-M4XB-9TFR');
      expect(body['installationId'], '88888888-8888-4888-8888-888888888888');
      // A terminal cannot name the restaurant it would like to join.
      expect(body.containsKey('venueId'), isFalse);
      expect(result.isEnrolled, isTrue);
      expect(result.venueName, 'Vankisi');
    });

    test('reports the reason the server gave for a refusal', () async {
      final client = clientFor(
        (_) async => http.Response(
          json.encode({'message': 'This enrollment code has expired.'}),
          401,
        ),
      );

      final result = await client.enroll(
        baseUrl: 'http://10.0.0.3:3000',
        code: '7K2Q-M4XB-9TFR',
        installationId: '88888888-8888-4888-8888-888888888888',
        platform: 'WINDOWS',
      );

      expect(result.outcome, EdgeEnrollmentOutcome.rejected);
      expect(result.message, 'This enrollment code has expired.');
      expect(result.credential, isNull);
    });

    test('tells a conflict and a throttle apart from a bad code', () async {
      Future<EdgeEnrollmentOutcome> outcomeFor(int status) async {
        final client = clientFor((_) async => http.Response('{}', status));
        final result = await client.enroll(
          baseUrl: 'http://10.0.0.3:3000',
          code: '7K2Q-M4XB-9TFR',
          installationId: '88888888-8888-4888-8888-888888888888',
          platform: 'WINDOWS',
        );
        return result.outcome;
      }

      expect(await outcomeFor(409), EdgeEnrollmentOutcome.conflict);
      expect(await outcomeFor(429), EdgeEnrollmentOutcome.throttled);
      expect(await outcomeFor(401), EdgeEnrollmentOutcome.rejected);
      expect(await outcomeFor(500), EdgeEnrollmentOutcome.serverError);
    });

    test('treats an unreachable server as its own outcome', () async {
      final client = clientFor((_) async => throw const SocketException('no'));

      final result = await client.enroll(
        baseUrl: 'http://10.0.0.3:3000',
        code: '7K2Q-M4XB-9TFR',
        installationId: '88888888-8888-4888-8888-888888888888',
        platform: 'WINDOWS',
      );

      expect(result.outcome, EdgeEnrollmentOutcome.unreachable);
    });

    test('refuses a success that carries no usable credential', () async {
      final client = clientFor(
        (_) async => http.Response(json.encode({'venue': {}}), 200),
      );

      final result = await client.enroll(
        baseUrl: 'http://10.0.0.3:3000',
        code: '7K2Q-M4XB-9TFR',
        installationId: '88888888-8888-4888-8888-888888888888',
        platform: 'WINDOWS',
      );

      expect(result.outcome, EdgeEnrollmentOutcome.serverError);
    });
  });

  group('what the terminal keeps', () {
    test('persists the credential and its venue across a restart', () async {
      await EdgeDeviceCredentialStore.load();
      final installationId = EdgeDeviceCredentialStore.installationId;

      expect(
        await EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: credential,
          venueId: venueId,
          venueName: 'Vankisi',
        ),
        isTrue,
      );

      // Close the POS and start it again.
      EdgeDeviceCredentialStore.resetForTest();
      await EdgeDeviceCredentialStore.load();

      expect(EdgeDeviceCredentialStore.installationId, installationId);
      expect(EdgeDeviceCredentialStore.credential, credential);
      expect(EdgeDeviceCredentialStore.deviceId, deviceId);
      expect(EdgeDeviceCredentialStore.venueId, venueId);
      expect(EdgeDeviceCredentialStore.venueName, 'Vankisi');
      expect(EdgeDeviceCredentialStore.enrolledAt, isNotNull);
    });

    test('reports failure rather than a phantom enrollment when the write '
        'cannot land', () async {
      await EdgeDeviceCredentialStore.load();

      // A path that cannot be a directory, because a file is already there.
      final blocker = File('${directory.path}/blocked');
      await blocker.writeAsString('x');
      EdgeDeviceCredentialStore.directoryOverride = '${blocker.path}/inside';

      final saved = await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: credential,
        venueId: venueId,
        venueName: 'Vankisi',
      );

      expect(saved, isFalse);
      // Nothing half-applied: the terminal is still unenrolled in memory too,
      // so a retry of the same code is the honest next step.
      expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
      expect(EdgeDeviceCredentialStore.venueName, isNull);
    });

    test('refuses to store anything that is not a device credential', () async {
      await EdgeDeviceCredentialStore.load();

      expect(
        await EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: 'legacy-shared-key',
          venueId: venueId,
          venueName: 'Vankisi',
        ),
        isFalse,
      );
      expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
    });

    test('an operator drop file still provisions a terminal', () async {
      // The support path stays. An installation provisioned before enrollment
      // existed must keep working exactly as it did.
      final drop = File('${directory.path}/edge_device_provision.txt');
      await drop.writeAsString('$credential\n');

      await EdgeDeviceCredentialStore.load();

      expect(EdgeDeviceCredentialStore.credential, credential);
      expect(drop.existsSync(), isFalse);
      // It was never enrolled, so it names no venue — and that is not an error.
      expect(EdgeDeviceCredentialStore.venueName, isNull);
    });

    test('keeps the venue name out of nothing it should not be in', () async {
      await EdgeDeviceCredentialStore.load();
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: credential,
        venueId: venueId,
        venueName: 'Vankisi',
      );

      final stored =
          json.decode(
                File('${directory.path}/edge_device.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      // Still one file outside the Hive boxes a backup serializes.
      expect(stored['credential'], credential);
      expect(stored['venueName'], 'Vankisi');
      expect(File('${directory.path}/edge_device.json').existsSync(), isTrue);
    });
  });

  group('which address the terminal ends up using', () {
    test('keeps the address it enrolled through when none is offered', () {
      expect(
        PosEnrollmentService.resolveBackendUrl(
          enrolledThrough: 'http://10.0.0.3:3000',
          offered: null,
        ),
        'http://10.0.0.3:3000',
      );
    });

    test('adopts a canonical address the deployment declares', () {
      expect(
        PosEnrollmentService.resolveBackendUrl(
          enrolledThrough: 'http://10.0.0.3:3000',
          offered: 'https://api.vynic.ge',
        ),
        'https://api.vynic.ge',
      );
    });

    test('ignores a loopback answer that would break a working link', () {
      // A server describing itself to itself. Adopting it on a till on another
      // machine would replace an address that demonstrably reached the backend
      // with one that cannot.
      expect(
        PosEnrollmentService.resolveBackendUrl(
          enrolledThrough: 'http://10.0.0.3:3000',
          offered: 'http://127.0.0.1:3000',
        ),
        'http://10.0.0.3:3000',
      );
      expect(
        PosEnrollmentService.resolveBackendUrl(
          enrolledThrough: 'http://10.0.0.3:3000',
          offered: 'http://localhost:3000',
        ),
        'http://10.0.0.3:3000',
      );
    });

    test('still lets a genuinely local terminal keep localhost', () {
      expect(
        PosEnrollmentService.resolveBackendUrl(
          enrolledThrough: 'http://localhost:3000',
          offered: 'http://127.0.0.1:3000',
        ),
        'http://127.0.0.1:3000',
      );
    });

    test('ignores an unusable answer', () {
      expect(
        PosEnrollmentService.resolveBackendUrl(
          enrolledThrough: 'http://10.0.0.3:3000',
          offered: 'not a url at all',
        ),
        'http://10.0.0.3:3000',
      );
    });
  });
}
