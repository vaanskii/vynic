import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';

/// Claim → execute → journal → acknowledge, over a real socket.
///
/// The POS speaks to an HTTP server on loopback that implements the Step 6A
/// queue semantics — device authentication, leases, at-least-once redelivery,
/// idempotent acknowledgment — rather than to a mocked client object. The
/// backend's own suite proves those semantics against real PostgreSQL; this
/// proves the Flutter side does the right thing when it meets them.
void main() {
  late Directory directory;
  late _FakeCloud cloud;
  late EdgeTransportService service;

  const credential = 'vynic-device-v1.11111111-1111-4111-8111-111111111111.'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const foreignCredential =
      'vynic-device-v1.22222222-2222-4222-8222-222222222222.'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  var executions = 0;

  setUp(() async {
    executions = 0;
    directory = await Directory.systemTemp.createTemp('edge-e2e-');
    Hive.init(directory.path);
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.save(credential);

    cloud = await _FakeCloud.start(acceptedCredential: credential);
    service = EdgeTransportService(
      client: EdgeTransportClient(
        baseUrl: () => cloud.baseUrl,
        credential: () => EdgeDeviceCredentialStore.credential,
      ),
      registry: EdgeCommandRegistry(<EdgeCommandHandler>[
        _CountingNoopHandler(() => executions += 1),
      ]),
    );
    await service.start();
  });

  tearDown(() async {
    await service.stop();
    await cloud.stop();
    await Hive.deleteFromDisk();
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('a NOOP goes all the way from enqueue to SUCCEEDED', () async {
    cloud.enqueue('cmd-1');

    final summary = await service.pollOnce();

    expect(summary.claimed, 1);
    expect(summary.executed, 1);
    expect(summary.acknowledged, 1);
    expect(executions, 1);
    expect(EdgeCommandJournal.entryFor('cmd-1')!.status,
        EdgeExecutionStatus.succeeded);
    expect(cloud.statusOf('cmd-1'), 'SUCCEEDED');
    expect(cloud.attemptsOf('cmd-1'), 1);
  });

  test('an acknowledgment lost to a dead connection costs nothing', () async {
    // The sequence the journal exists for: execute, lose the network before the
    // acknowledgment lands, watch the lease expire, receive the same command.
    cloud.enqueue('cmd-1');
    cloud.failNextAck = true;

    final first = await service.pollOnce();
    expect(first.executed, 1);
    expect(first.acknowledged, 0);
    expect(cloud.statusOf('cmd-1'), 'CLAIMED');

    cloud.expireLeases();
    final second = await service.pollOnce();

    expect(second.claimed, 1);
    expect(second.executed, 0, reason: 'already done here');
    expect(second.skippedAlreadyDone, 1);
    expect(second.acknowledged, 1);
    expect(executions, 1, reason: 'the side effect happened exactly once');
    expect(cloud.statusOf('cmd-1'), 'SUCCEEDED');
    expect(cloud.attemptsOf('cmd-1'), 2, reason: 'cloud did redeliver');
  });

  test('a redelivery after a clean acknowledgment still does not re-execute',
      () async {
    cloud.enqueue('cmd-1');
    await service.pollOnce();

    // Cloud would not normally offer a SUCCEEDED command again; if anything
    // ever did, the journal is the thing that refuses to run it twice.
    cloud.reopen('cmd-1');
    final summary = await service.pollOnce();

    expect(summary.skippedAlreadyDone, 1);
    expect(executions, 1);
  });

  test('the journal outlives a restart of the POS', () async {
    cloud.enqueue('cmd-1');
    cloud.failNextAck = true;
    await service.pollOnce();
    expect(executions, 1);

    // Restart: everything in memory is gone, only the disk survives.
    await service.stop();
    final restarted = EdgeTransportService(
      client: EdgeTransportClient(
        baseUrl: () => cloud.baseUrl,
        credential: () => EdgeDeviceCredentialStore.credential,
      ),
      registry: EdgeCommandRegistry(<EdgeCommandHandler>[
        _CountingNoopHandler(() => executions += 1),
      ]),
    );
    await restarted.start();
    cloud.expireLeases();
    final summary = await restarted.pollOnce();
    await restarted.stop();

    expect(summary.skippedAlreadyDone, 1);
    expect(executions, 1);
    expect(cloud.statusOf('cmd-1'), 'SUCCEEDED');
  });

  test('drains a batch in the order cloud handed it over', () async {
    cloud.enqueue('cmd-1');
    cloud.enqueue('cmd-2');
    cloud.enqueue('cmd-3');

    final summary = await service.pollOnce();

    expect(summary.claimed, 3);
    expect(executions, 3);
    expect(cloud.acknowledgedOrder, <String>['cmd-1', 'cmd-2', 'cmd-3']);
  });

  test('a credential cloud does not accept stops the loop, not the POS',
      () async {
    // What a revoked device, a disabled venue, or another venue's credential
    // all look like from here.
    await EdgeDeviceCredentialStore.save(foreignCredential);
    cloud.enqueue('cmd-1');

    final summary = await service.pollOnce();

    expect(summary.outcome, EdgeTransportOutcome.unauthorized);
    expect(executions, 0);
    expect(cloud.statusOf('cmd-1'), 'PENDING');
  });

  test('an unreachable cloud leaves the POS alone', () async {
    cloud.enqueue('cmd-1');
    await cloud.stop();

    final summary = await service.pollOnce();

    expect(summary.outcome, EdgeTransportOutcome.unreachable);
    expect(service.isRunning, isTrue);
    expect(executions, 0);
  });
}

class _CountingNoopHandler implements EdgeCommandHandler {
  _CountingNoopHandler(this._onExecute);
  final void Function() _onExecute;

  @override
  String get type => EdgeCommandTypes.noop;

  @override
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command) async {
    _onExecute();
    return EdgeCommandResult.succeeded(command.commandId);
  }
}

/// A loopback stand-in for the Step 6A endpoints.
///
/// Implements the parts of the queue the client actually depends on: the device
/// credential decides who may claim, a claim is a lease that increments the
/// attempt count, and an acknowledgment keeps the first outcome a command ended
/// with.
class _FakeCloud {
  _FakeCloud._(this._server, this._acceptedCredential) {
    _server.listen(_handle);
  }

  static Future<_FakeCloud> start({required String acceptedCredential}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeCloud._(server, acceptedCredential);
  }

  final HttpServer _server;
  final String _acceptedCredential;
  final Map<String, Map<String, Object?>> _commands = <String, Map<String, Object?>>{};
  final List<String> acknowledgedOrder = <String>[];

  /// Makes the next acknowledgment fail, as a dying connection would.
  bool failNextAck = false;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);

  void enqueue(String commandId) {
    _commands[commandId] = <String, Object?>{
      'status': 'PENDING',
      'attempt': 0,
      'leaseExpired': false,
    };
  }

  String statusOf(String commandId) => _commands[commandId]!['status'] as String;

  int attemptsOf(String commandId) => _commands[commandId]!['attempt'] as int;

  /// Every leased command becomes available again, as an expiry sweep would.
  void expireLeases() {
    for (final command in _commands.values) {
      if (command['status'] == 'CLAIMED') command['status'] = 'PENDING';
    }
  }

  /// Offers a finished command again — the case the local journal must catch.
  void reopen(String commandId) {
    _commands[commandId]!['status'] = 'PENDING';
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final credential = request.headers.value('X-POS-Sync-Key');

    if (credential != _acceptedCredential) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    if (request.uri.path == '/edge/commands/claim') {
      await _claim(request, body);
      return;
    }
    if (request.uri.path == '/edge/commands/ack') {
      await _ack(request, body);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> _claim(HttpRequest request, String body) async {
    final decoded = json.decode(body) as Map<String, dynamic>;
    // The client must never name a venue; the credential decides.
    if (decoded.containsKey('venueId')) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final accepted = (decoded['acceptedContractVersions'] as List)
        .cast<int>()
        .toSet();
    final limit = decoded['limit'] as int;

    final issued = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc();
    for (final entry in _commands.entries) {
      if (issued.length >= limit) break;
      if (entry.value['status'] != 'PENDING') continue;
      if (!accepted.contains(edgeCommandContractVersion)) continue;

      entry.value['status'] = 'CLAIMED';
      entry.value['attempt'] = (entry.value['attempt'] as int) + 1;
      issued.add(<String, dynamic>{
        'contractVersion': edgeCommandContractVersion,
        'commandId': entry.key,
        'type': EdgeCommandTypes.noop,
        'payload': null,
        'idempotencyKey': 'key-${entry.key}',
        'attempt': entry.value['attempt'],
        'issuedAt': now.toIso8601String(),
        'leaseExpiresAt': now
            .add(const Duration(seconds: edgeCommandClaimLeaseSeconds))
            .toIso8601String(),
      });
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      json.encode(<String, dynamic>{
        'contractVersion': edgeCommandContractVersion,
        'commands': issued,
        'serverTime': now.toIso8601String(),
      }),
    );
    await request.response.close();
  }

  Future<void> _ack(HttpRequest request, String body) async {
    if (failNextAck) {
      failNextAck = false;
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    final decoded = json.decode(body) as Map<String, dynamic>;
    final commandId = decoded['commandId'] as String;
    final command = _commands[commandId];
    if (command == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    acknowledgedOrder.add(commandId);
    // Idempotent: a terminal command keeps the outcome it ended with.
    if (command['status'] != 'SUCCEEDED' && command['status'] != 'FAILED') {
      command['status'] = decoded['status'];
    }

    request.response.statusCode = HttpStatus.created;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      json.encode(<String, dynamic>{
        'commandId': commandId,
        'status': command['status'],
      }),
    );
    await request.response.close();
  }
}
