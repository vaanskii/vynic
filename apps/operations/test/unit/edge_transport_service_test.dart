import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/edge/noop_edge_command_handler.dart';

/// The poll loop: one lifecycle owner, no overlapping claims, and no failure
/// mode that reaches the till.
void main() {
  late Directory directory;
  const credential = 'vynic-device-v1.11111111-1111-4111-8111-111111111111.'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Map<String, dynamic> envelope(
    String id, {
    String type = 'NOOP',
    int version = 1,
    int attempt = 1,
  }) => <String, dynamic>{
    'contractVersion': version,
    'commandId': id,
    'type': type,
    'payload': null,
    'idempotencyKey': 'key-$id',
    'attempt': attempt,
    'issuedAt': '2026-09-01T10:00:00.000Z',
    'leaseExpiresAt': '2026-09-01T10:02:00.000Z',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('edge-service-');
    Hive.init(directory.path);
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential);
  });

  tearDown(() async {
    await EdgeCommandJournal.close();
    await Hive.deleteFromDisk();
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    EdgeTransportService.overrideInstance(null);
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  EdgeTransportService serviceWith(
    Future<http.Response> Function(http.Request) handler, {
    List<EdgeCommandHandler> handlers = const <EdgeCommandHandler>[
      NoopEdgeCommandHandler(),
    ],
    String? credentialOverride = credential,
  }) => EdgeTransportService(
    client: EdgeTransportClient(
      httpClient: MockClient(handler),
      baseUrl: () => 'http://cloud.test',
      credential: () => credentialOverride,
    ),
    registry: EdgeCommandRegistry(handlers),
  );

  String claimBody(List<Map<String, dynamic>> commands) => json.encode({
    'contractVersion': edgeCommandContractVersion,
    'commands': commands,
  });

  group('claim, execute, acknowledge', () {
    test('runs a NOOP and reports it succeeded', () async {
      final acks = <Map<String, dynamic>>[];
      var claims = 0;
      final service = serviceWith((request) async {
        if (request.url.path.endsWith('/claim')) {
          claims += 1;
          return http.Response(
            claimBody(claims == 1 ? [envelope('c1')] : const []),
            200,
          );
        }
        acks.add(json.decode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 201);
      });

      await service.start();
      final summary = await service.pollOnce();

      expect(summary.claimed, 1);
      expect(summary.executed, 1);
      expect(summary.acknowledged, 1);
      expect(acks.single['commandId'], 'c1');
      expect(acks.single['status'], 'SUCCEEDED');
      expect(
        EdgeCommandJournal.entryFor('c1')!.status,
        EdgeExecutionStatus.succeeded,
      );
      await service.stop();
    });

    test('does not execute a redelivered command twice', () async {
      var executions = 0;
      final acks = <Map<String, dynamic>>[];
      final service = serviceWith(
        (request) async {
          if (request.url.path.endsWith('/claim')) {
            // Cloud offers the same command again — the acknowledgment never
            // reached it, the lease expired, and here it is a second time.
            return http.Response(claimBody([envelope('c1', attempt: 2)]), 200);
          }
          acks.add(json.decode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 201);
        },
        handlers: <EdgeCommandHandler>[_CountingHandler(() => executions += 1)],
      );

      await service.start();
      final first = await service.pollOnce();
      final second = await service.pollOnce();

      expect(first.executed, 1);
      expect(second.executed, 0);
      expect(second.skippedAlreadyDone, 1);
      expect(executions, 1, reason: 'the side effect must happen once');
      // Still acknowledged, so Cloud can stop offering it.
      expect(acks.length, 2);
      expect(acks.last['status'], 'SUCCEEDED');
      expect(acks.last['code'], 'already_executed');
      await service.stop();
    });

    test('a handler that throws fails the command, not the POS', () async {
      final service = serviceWith(
        (request) async => request.url.path.endsWith('/claim')
            ? http.Response(claimBody([envelope('c1')]), 200)
            : http.Response('{}', 201),
        handlers: <EdgeCommandHandler>[_ThrowingHandler()],
      );

      await service.start();
      final summary = await service.pollOnce();

      expect(summary.outcome, EdgeTransportOutcome.ok);
      expect(
        EdgeCommandJournal.entryFor('c1')!.status,
        EdgeExecutionStatus.failed,
      );
      await service.stop();
    });

    test('refuses a newer contract instead of guessing at it', () async {
      final acks = <Map<String, dynamic>>[];
      final service = serviceWith((request) async {
        if (request.url.path.endsWith('/claim')) {
          return http.Response(
            claimBody([
              envelope('c1', version: edgeCommandContractVersion + 1),
            ]),
            200,
          );
        }
        acks.add(json.decode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 201);
      });

      await service.start();
      final summary = await service.pollOnce();

      expect(summary.skippedUnsupported, 1);
      expect(summary.executed, 0);
      expect(acks.single['code'], 'unsupported_contract_version');
      // Nothing was started, so nothing is journalled as run.
      expect(EdgeCommandJournal.entryFor('c1'), isNull);
      await service.stop();
    });

    test('reports an unknown command type without executing anything', () async {
      final acks = <Map<String, dynamic>>[];
      final service = serviceWith((request) async {
        if (request.url.path.endsWith('/claim')) {
          return http.Response(
            claimBody([envelope('c1', type: 'PRINT_ORDER_CHECK')]),
            200,
          );
        }
        acks.add(json.decode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 201);
      });

      await service.start();
      final summary = await service.pollOnce();

      expect(summary.skippedUnsupported, 1);
      expect(acks.single['code'], 'unsupported_command_type');
      await service.stop();
    });
  });

  group('lifecycle', () {
    test('does not start without a device credential', () async {
      // Every installation looks like this until one is provisioned, and it has
      // to open its till exactly as it always did.
      await EdgeDeviceCredentialStore.clear();
      EdgeDeviceCredentialStore.resetForTest();
      await EdgeDeviceCredentialStore.load();
      expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
      var called = false;
      final service = serviceWith((_) async {
        called = true;
        return http.Response(claimBody(const []), 200);
      }, credentialOverride: null);

      await service.start();

      expect(service.isRunning, isFalse);
      expect(called, isFalse);
    });

    test('stands down when cloud rejects the credential', () async {
      // A revoked device or a disabled venue. Hammering will not help, and it
      // must not destabilise anything either.
      final service = serviceWith((_) async => http.Response('', 401));

      await service.start();
      expect(service.isRunning, isTrue);
      final summary = await service.pollOnce();

      expect(summary.outcome, EdgeTransportOutcome.unauthorized);
      await service.stop();
    });

    test('keeps running when cloud is simply unreachable', () async {
      final service = serviceWith((_) async => throw const _Offline());

      await service.start();
      final summary = await service.pollOnce();

      expect(summary.outcome, EdgeTransportOutcome.unreachable);
      expect(service.isRunning, isTrue, reason: 'offline is not a failure');
      await service.stop();
    });

    test('never runs two claims at once', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final service = serviceWith((request) async {
        if (request.url.path.endsWith('/claim')) {
          inFlight += 1;
          maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight -= 1;
        }
        return http.Response(claimBody(const []), 200);
      });

      await service.start();
      await Future.wait<void>(<Future<void>>[
        service.pollOnce(),
        service.pollOnce(),
        service.pollOnce(),
      ]);

      expect(maxInFlight, 1);
      await service.stop();
    });

    test('stops cleanly and can be started again', () async {
      final service = serviceWith(
        (_) async => http.Response(claimBody(const []), 200),
      );

      await service.start();
      await service.stop();
      expect(service.isRunning, isFalse);

      await service.start();
      expect(service.isRunning, isTrue);
      await service.stop();
    });

    test('stopping without starting is harmless', () async {
      final service = serviceWith(
        (_) async => http.Response(claimBody(const []), 200),
      );
      await service.stop();
      expect(service.isRunning, isFalse);
    });
  });
}

class _CountingHandler implements EdgeCommandHandler {
  _CountingHandler(this._onExecute);
  final void Function() _onExecute;

  @override
  String get type => EdgeCommandTypes.noop;

  @override
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command) async {
    _onExecute();
    return EdgeCommandResult.succeeded(command.commandId);
  }
}

class _ThrowingHandler implements EdgeCommandHandler {
  @override
  String get type => EdgeCommandTypes.noop;

  @override
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command) async {
    throw StateError('handler exploded');
  }
}

class _Offline implements Exception {
  const _Offline();
}
