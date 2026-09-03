import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';

/// The Edge's own answer to at-least-once delivery.
///
/// Cloud acknowledgment cannot cover the sequence that actually happens: the
/// POS executes a command, the connection dies before the acknowledgment lands,
/// the lease expires, and the same command arrives again. Without this record
/// the side effect happens twice.
void main() {
  late Directory directory;

  EdgeCommandEnvelope command(String id) => EdgeCommandEnvelope(
    contractVersion: edgeCommandContractVersion,
    commandId: id,
    type: EdgeCommandTypes.noop,
    payload: null,
    idempotencyKey: 'key-$id',
    attempt: 1,
    issuedAt: DateTime.now().toUtc(),
    leaseExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('edge-journal-');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await EdgeCommandJournal.close();
    await Hive.deleteFromDisk();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('a first delivery has nothing recorded against it', () async {
    await EdgeCommandJournal.open();

    expect(await EdgeCommandJournal.beginExecution(command('c1')), isNull);
    expect(
      EdgeCommandJournal.entryFor('c1')!.status,
      EdgeExecutionStatus.running,
    );
  });

  test('a redelivered command that already succeeded is recognised', () async {
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(command('c1'));
    await EdgeCommandJournal.completeExecution('c1', succeeded: true);

    final previous = await EdgeCommandJournal.beginExecution(command('c1'));

    expect(previous, isNotNull);
    expect(previous!.status, EdgeExecutionStatus.succeeded);
    expect(previous.isTerminal, isTrue);
  });

  test('a failed outcome is remembered with its reason', () async {
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(command('c1'));
    await EdgeCommandJournal.completeExecution(
      'c1',
      succeeded: false,
      code: 'printer_offline',
    );

    final entry = EdgeCommandJournal.entryFor('c1')!;
    expect(entry.status, EdgeExecutionStatus.failed);
    expect(entry.code, 'printer_offline');
    expect(entry.isTerminal, isTrue);
  });

  test('survives a restart', () async {
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(command('c1'));
    await EdgeCommandJournal.completeExecution('c1', succeeded: true);
    await EdgeCommandJournal.close();

    await EdgeCommandJournal.open();

    expect(
      EdgeCommandJournal.entryFor('c1')!.status,
      EdgeExecutionStatus.succeeded,
    );
  });

  test('a command interrupted by a crash is marked, not assumed', () async {
    // Left `running` by a process that never came back. The outcome genuinely
    // is unknown, so it is neither claimed as done nor silently retried as new.
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(command('c1'));
    await EdgeCommandJournal.close();

    await EdgeCommandJournal.open();

    final entry = EdgeCommandJournal.entryFor('c1')!;
    expect(entry.status, EdgeExecutionStatus.interrupted);
    expect(entry.isTerminal, isFalse);
    // Not terminal, so an idempotent command may be executed again.
    expect(await EdgeCommandJournal.beginExecution(command('c1')), isNotNull);
    expect(
      EdgeCommandJournal.entryFor('c1')!.status,
      EdgeExecutionStatus.running,
    );
  });

  test('keeps the first-seen time across redeliveries', () async {
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(command('c1'));
    final firstSeen = EdgeCommandJournal.entryFor('c1')!.firstSeenAt;

    await EdgeCommandJournal.close();
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(command('c1'));

    expect(EdgeCommandJournal.entryFor('c1')!.firstSeenAt, firstSeen);
  });

  test('prunes finished entries past retention and keeps unfinished ones', () async {
    await EdgeCommandJournal.open();
    final box = Hive.box<Map>(EdgeCommandJournal.boxName);
    final old = DateTime.now()
        .toUtc()
        .subtract(EdgeCommandJournal.retention + const Duration(days: 1))
        .toIso8601String();

    await box.put('finished-old', <String, dynamic>{
      'commandId': 'finished-old',
      'idempotencyKey': 'k',
      'type': 'NOOP',
      'status': 'succeeded',
      'firstSeenAt': old,
      'completedAt': old,
    });
    await box.put('unfinished-old', <String, dynamic>{
      'commandId': 'unfinished-old',
      'idempotencyKey': 'k',
      'type': 'NOOP',
      'status': 'interrupted',
      'firstSeenAt': old,
    });

    await EdgeCommandJournal.prune();

    expect(EdgeCommandJournal.entryFor('finished-old'), isNull);
    // Unfinished entries are exactly the ones a redelivery still needs.
    expect(EdgeCommandJournal.entryFor('unfinished-old'), isNotNull);
  });

  test('stores no command payload', () async {
    await EdgeCommandJournal.open();
    await EdgeCommandJournal.beginExecution(
      EdgeCommandEnvelope(
        contractVersion: 1,
        commandId: 'c1',
        type: EdgeCommandTypes.noop,
        payload: <String, dynamic>{'secret': 'do-not-persist'},
        idempotencyKey: 'k',
        attempt: 1,
        issuedAt: DateTime.now().toUtc(),
        leaseExpiresAt: DateTime.now().toUtc(),
      ),
    );

    final raw = Hive.box<Map>(EdgeCommandJournal.boxName).get('c1')!;
    expect(raw.toString(), isNot(contains('do-not-persist')));
  });
}
