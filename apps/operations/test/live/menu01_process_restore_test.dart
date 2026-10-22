import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import '../support/menu01_fixture.dart';
import '../unit/menu02_durability_test.dart' show FaultBox;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['MENU01_PROCESS_DIRECTORY'];
  final mode = Platform.environment['MENU01_PROCESS_STAGE'];
  test(
    'native isolated MENU01 process restore',
    () async {
      HttpOverrides.global = Menu01NoHttp();
      final directory = Directory(root!);
      if (!directory.isAbsolute ||
          !directory.path.startsWith('/private/tmp/vynic_menu01_process_'))
        throw StateError(
          'Only the orchestrator temporary directory is allowed',
        );
      final file = File('$root/restaurant.json');
      Future<void> write(String name, Map<String, dynamic> value) async {
        final staging = File('$root/$name.tmp');
        await staging.writeAsString(jsonEncode(value), flush: true);
        await staging.rename('$root/$name.json');
      }

      if (mode == 'writer') {
        await Directory('$root/source').create();
        await openMenu01('$root/source');
        await seedMenu01();
        final local = MenuLocalStore.forBox(DatabaseCore.menuBox!);
        final ids = local.journal.all().map((e) => e.mutationId).toList();
        await BackupRepository.createDataBackup(
          targetFilePath: file.path,
          password: menu01Password,
        );
        await write('writer', {
          'pid': pid,
          'mutationIds': ids,
          'generation': local.generation,
          'backupSha256': sha256.convert(await file.readAsBytes()).toString(),
          'metrics': BackupRepository.lastBackupMetrics,
          'sourceDirectory': 'source',
        });
        await closeMenu01();
        return;
      }
      if (mode == 'crash-restore') {
        await Directory('$root/crash-fresh').create();
        await openMenu01('$root/crash-fresh');
        final box = FaultBox(DatabaseCore.salesBox!);
        DatabaseCore.salesBox = box;
        box.fault = (point) async {
          if (point == 'clear:after') {
            await box.inner.flush();
            await write('ready', {
              'pid': pid,
              'checkpoint': 'sales.clear:after',
              'restoreMarkerPresent': File(
                '$root/crash-fresh/${BackupRepository.restoreMarkerName}',
              ).existsSync(),
              'salesEmpty': box.isEmpty,
            });
            await Completer<void>().future;
          }
        };
        await BackupRepository.restoreDataBackupFromFile(
          file,
          password: menu01Password,
          backupBeforeRestore: false,
        );
        throw StateError('Crash checkpoint not reached');
      }
      final path = mode == 'recover' ? '$root/crash-fresh' : '$root/fresh';
      if (mode != 'recover') await Directory(path).create();
      await openMenu01(path);
      final initialFresh = DatabaseCore.salesBox!.isEmpty;
      if (mode != 'recover')
        await BackupRepository.restoreDataBackupFromFile(
          file,
          password: menu01Password,
          backupBeforeRestore: false,
        );
      final metrics = BackupRepository.lastRestoreMetrics;
      await closeMenu01();
      await openMenu01(path);
      final result = await verifyMenu01Recovery();
      final writer =
          jsonDecode(await File('$root/writer.json').readAsString()) as Map;
      expect(result['menuMutationIds'], writer['mutationIds']);
      expect(result['generation'], writer['generation']);
      expect(result['menuPrice'], 12);
      expect(result['conflictPrice'], 22);
      expect(result['closurePhase'], 'completed');
      expect(result['capturedOrderPrice'], 7);
      expect(result['salePrice'], 7);
      expect(result['orderUuid'], 'stable-order-42');
      expect(result['hasCredential'], false);
      expect(result['uncertainCommand'], 'interrupted');
      final before = DatabaseCore.salesBox!.toMap();
      final gen = result['generation'];
      await BackupRepository.restoreDataBackupFromFile(
        file,
        password: menu01Password,
        backupBeforeRestore: false,
      );
      expect(DatabaseCore.salesBox!.toMap(), before);
      expect(MenuLocalStore.forBox(DatabaseCore.menuBox!).generation, gen);
      await write(mode == 'recover' ? 'recovered' : 'reader', {
        'status': 'PASS',
        'pid': pid,
        'writerPid': writer['pid'],
        'freshDirectory': mode == 'recover' ? 'crash-fresh' : 'fresh',
        'initiallyEmpty': initialFresh,
        'reopenedBeforeVerification': true,
        'repeatedRestore': 'PASS',
        'metrics': metrics,
        ...result,
      });
      await closeMenu01();
    },
    skip: root == null || mode == null,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
