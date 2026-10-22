import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import '../support/pos02_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos02Fixture f;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_pos02_backup_');
    f = Pos02Fixture();
    await f.open('${root.path}/source');
    await f.seed();
  });
  tearDown(() async {
    await f.close();
    await root.delete(recursive: true);
  });
  Future<String> backup() async => (await BackupRepository.createDataBackup(
    targetFilePath: '${root.path}/backup.json',
  )).readAsString();
  Future<void> fresh(String payload) async {
    await f.close();
    await f.open('${root.path}/fresh');
    await BackupRepository.restoreDataBackupFromJson(
      payload,
      backupBeforeRestore: false,
    );
  }

  String seal(Map<String, dynamic> p) {
    p.remove('integrity');
    PosBackupFormat.seal(p);
    return jsonEncode(p);
  }

  test(
    'format2 backup preserves attempts, frozen bytes and operator audit; queued source work is held on restore',
    () async {
      await PrintQueue.enqueue(f.job());
      await f.dispatch();
      PrintQueue.stop();
      await PrintReconciliation.reprint(
        PrintJobRepository.read(Pos02Fixture.jobId)!,
        'synthetic explicit copy',
        Pos02Fixture.copyId,
      );
      final original = PrintJobRepository.all().single;
      final payload = await backup();
      final decoded = await PosBackupFormat.decode(payload);
      expect(decoded['formatVersion'], 2);
      expect(decoded['manifest'], hasLength(17));
      await fresh(payload);
      final restored = PrintJobRepository.all().single;
      expect(restored.id, original.id);
      expect(restored.attemptId, original.attemptId);
      expect(restored.toMap()['payload'], original.toMap()['payload']);
      expect(restored.state, PrintJobState.uncertain);
      expect(restored.audit.take(original.audit.length), original.audit);
      await f.dispatch();
      expect(f.transmitted, hasLength(1)); // one source write only
      expect(restored.detail, contains('Restore'));
      final stable = restored.toMap();
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      expect(PrintJobRepository.all().single.toMap(), stable);
      expect(DatabaseCore.dbVersion, 9);
    },
  );
  test('pre-POS02 format2 without print rows remains compatible', () async {
    final payload = await backup();
    await fresh(payload);
    expect(PrintJobRepository.all(), isEmpty);
    expect(DatabaseCore.orderBox!.values, isNotEmpty);
    expect(DatabaseCore.dbVersion, 9);
  });
  for (final malformed in ['digest', 'confirm', 'version', 'key']) {
    test(
      'malformed $malformed print row is rejected before destination replacement',
      () async {
        await PrintQueue.enqueue(f.job());
        final payload = await PosBackupFormat.decode(await backup());
        final rows = payload['stores']['meta'] as List;
        final row = rows.singleWhere(
          (r) =>
              PosBackupFormat.decodeValue(r['key']) ==
              PrintJobRepository.key(Pos02Fixture.jobId),
        );
        final job = Map<String, dynamic>.from(
          PosBackupFormat.decodeValue(row['value']),
        );
        if (malformed == 'digest') job['payloadSha256'] = 'wrong';
        if (malformed == 'confirm') job['attempts'].last['state'] = 'confirmed';
        if (malformed == 'version') job['protocol'] = 99;
        if (malformed == 'key')
          row['key'] = PosBackupFormat.encodeValue('print_job:v99:unexpected');
        row['value'] = PosBackupFormat.encodeValue(job);
        final before = DatabaseCore.metaBox!.toMap();
        await expectLater(
          BackupRepository.restoreDataBackupFromJson(
            seal(payload),
            backupBeforeRestore: false,
          ),
          throwsFormatException,
        );
        expect(DatabaseCore.metaBox!.toMap(), before);
      },
    );
  }
  test(
    'legacy replacement refuses a print-only recovery destination',
    () async {
      await f.close();
      await f.open('${root.path}/empty');
      await PrintQueue.enqueue(f.job());
      await DatabaseCore.menuCanonicalBox!.clear();
      await DatabaseCore.menuJournalBox!.clear();
      await DatabaseCore.closureJournalBox!.clear();
      await EdgeCommandJournal.clearForTest();
      final before = DatabaseCore.metaBox!.toMap();
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          jsonEncode({'orders': []}),
          allowLegacyIncomplete: true,
          backupBeforeRestore: false,
        ),
        throwsStateError,
      );
      expect(DatabaseCore.metaBox!.toMap(), before);
    },
  );
}
