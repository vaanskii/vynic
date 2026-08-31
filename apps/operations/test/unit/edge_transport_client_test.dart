import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';

/// The HTTP half of Cloud → Edge, driven the way the poll loop drives it.
///
/// Every failure here is an outcome rather than a throw, because the caller is
/// a background loop on a machine that has to keep taking orders whatever Cloud
/// is doing.
void main() {
  EdgeTransportClient clientFor(
    Future<http.Response> Function(http.Request request) handler, {
    String? credential = 'vynic-device-v1.device.secret',
  }) => EdgeTransportClient(
    httpClient: MockClient(handler),
    baseUrl: () => 'http://cloud.test',
    credential: () => credential,
  );

  String claimBody(List<Map<String, dynamic>> commands) => json.encode({
    'contractVersion': edgeCommandContractVersion,
    'commands': commands,
    'serverTime': '2026-09-01T10:00:00.000Z',
  });

  Map<String, dynamic> envelope(String id, {int version = 1}) =>
      <String, dynamic>{
        'contractVersion': version,
        'commandId': id,
        'type': 'NOOP',
        'payload': null,
        'idempotencyKey': 'key-$id',
        'attempt': 1,
        'issuedAt': '2026-09-01T10:00:00.000Z',
        'leaseExpiresAt': '2026-09-01T10:02:00.000Z',
      };

  group('claim', () {
    test('sends the device credential and never a venue', () async {
      late http.Request captured;
      final client = clientFor((request) async {
        captured = request;
        return http.Response(claimBody(const []), 200);
      });

      await client.claim();

      expect(captured.url.path, '/edge/commands/claim');
      expect(
        captured.headers['X-POS-Sync-Key'],
        'vynic-device-v1.device.secret',
      );
      final body = json.decode(captured.body) as Map<String, dynamic>;
      // Venue is Cloud's to decide, from the credential. A POS that could name
      // its own venue could name someone else's.
      expect(body.containsKey('venueId'), isFalse);
      expect(body.containsKey('deviceId'), isFalse);
      expect(body['acceptedContractVersions'], <int>[
        edgeCommandContractVersion,
      ]);
      expect(body['limit'], edgeCommandDefaultBatchSize);
    });

    test('parses the commands it was handed', () async {
      final client = clientFor(
        (_) async =>
            http.Response(claimBody([envelope('c1'), envelope('c2')]), 200),
      );

      final response = await client.claim();

      expect(response.isOk, isTrue);
      expect(
        response.commands.map((c) => c.commandId),
        <String>['c1', 'c2'],
      );
    });

    test('keeps the usable half of a batch with one broken envelope', () async {
      final client = clientFor(
        (_) async => http.Response(
          claimBody([
            envelope('c1'),
            <String, dynamic>{'type': 'NOOP'}, // no commandId
          ]),
          200,
        ),
      );

      final response = await client.claim();

      expect(response.commands.map((c) => c.commandId), <String>['c1']);
    });

    test('reports an unreachable cloud rather than throwing', () async {
      final client = clientFor((_) async => throw const SocketExceptionStub());

      final response = await client.claim();

      expect(response.outcome, EdgeTransportOutcome.unreachable);
      expect(response.commands, isEmpty);
    });

    test('separates a rejected credential from a broken server', () async {
      for (final status in <int>[401, 403]) {
        final client = clientFor((_) async => http.Response('', status));
        expect(
          (await client.claim()).outcome,
          EdgeTransportOutcome.unauthorized,
        );
      }
      final broken = clientFor((_) async => http.Response('', 500));
      expect((await broken.claim()).outcome, EdgeTransportOutcome.serverError);
    });

    test('treats a malformed body as a server problem, not as no work', () async {
      final client = clientFor((_) async => http.Response('not json', 200));

      expect((await client.claim()).outcome, EdgeTransportOutcome.serverError);
    });

    test('does not call cloud at all without a credential', () async {
      var called = false;
      final client = clientFor((_) async {
        called = true;
        return http.Response(claimBody(const []), 200);
      }, credential: null);

      expect(
        (await client.claim()).outcome,
        EdgeTransportOutcome.notProvisioned,
      );
      expect(called, isFalse);
    });
  });

  group('acknowledge', () {
    test('reports success with the contract version', () async {
      late http.Request captured;
      final client = clientFor((request) async {
        captured = request;
        return http.Response('{}', 201);
      });

      final outcome = await client.acknowledge(
        const EdgeCommandResult.succeeded('c1'),
      );

      expect(outcome, EdgeTransportOutcome.ok);
      expect(captured.url.path, '/edge/commands/ack');
      final body = json.decode(captured.body) as Map<String, dynamic>;
      expect(body['commandId'], 'c1');
      expect(body['status'], 'SUCCEEDED');
      expect(body['contractVersion'], edgeCommandContractVersion);
    });

    test('reports a failure with its reason', () async {
      late http.Request captured;
      final client = clientFor((request) async {
        captured = request;
        return http.Response('{}', 201);
      });

      await client.acknowledge(
        const EdgeCommandResult.failed('c1', code: 'handler_threw'),
      );

      final body = json.decode(captured.body) as Map<String, dynamic>;
      expect(body['status'], 'FAILED');
      expect(body['code'], 'handler_threw');
    });

    test('an acknowledgment lost to a dead connection is an outcome', () async {
      final client = clientFor((_) async => throw const SocketExceptionStub());

      expect(
        await client.acknowledge(const EdgeCommandResult.succeeded('c1')),
        EdgeTransportOutcome.unreachable,
      );
    });
  });
}

/// A network failure without depending on `dart:io` exception internals.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'connection failed';
}
