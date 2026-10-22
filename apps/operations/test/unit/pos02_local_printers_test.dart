import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import '../support/pos02_fixture.dart';
import '../support/pos02_developer_fixture.dart';
import 'package:vynic/core/services/security/developer_access.dart';

void main() {
  late Directory root;
  late Pos02Fixture fixture;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_pos02_printers_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed();
    await unlockSyntheticPrinterDeveloper();
  });
  tearDown(() async {
    DeveloperAccess.resetForTest();
    DeveloperAccess.publicKeyOverride = null;
    await fixture.close();
    await root.delete(recursive: true);
  });

  test(
    'stores more than two named printers with stable IDs and no dispatch',
    () async {
      for (var n = 1; n <= 4; n++) {
        await LocalPrinterCatalog.add('Station $n', '10.0.0.$n');
      }
      final rows = LocalPrinterCatalog.read();
      expect(rows, hasLength(4));
      expect(rows.map((row) => row['id']).toSet(), hasLength(4));
      expect(rows.every((row) => row['routing'] == 'unassigned'), true);
      expect(rows.every((row) => row['registeredBy'] == 'developer'), true);
      expect(fixture.connections, 0);
      expect(DatabaseService.getKitchenPrinterIp(), 'synthetic.invalid');
      expect(DatabaseService.getReceiptPrinterIp(), 'synthetic.invalid');
    },
  );

  test(
    'addition persists across settings close/reopen and primary save',
    () async {
      await LocalPrinterCatalog.add(' ბარი ', ' 10.0.0.7 ');
      final id = LocalPrinterCatalog.read().single['id'];
      await DatabaseService.savePrinterConfiguration(
        kitchenIp: '10.0.0.8',
        receiptIp: '10.0.0.9',
        port: 9100,
      );
      final boxName = DatabaseCore.settingsBox!.name;
      await DatabaseCore.settingsBox!.close();
      DatabaseCore.settingsBox = await Hive.openBox(boxName);
      expect(LocalPrinterCatalog.read().single, containsPair('name', 'ბარი'));
      expect(LocalPrinterCatalog.read().single['id'], id);
      expect(DatabaseService.getKitchenPrinterIp(), '10.0.0.8');
      expect(DatabaseService.getReceiptPrinterIp(), '10.0.0.9');
    },
  );

  for (final input in [
    '',
    '999.0.0.1',
    '10.0.0',
    '10.0.0.01',
    'host.invalid',
  ]) {
    test('invalid IP $input never changes persistent registration', () async {
      await expectLater(
        LocalPrinterCatalog.add('Station', input),
        throwsArgumentError,
      );
      expect(LocalPrinterCatalog.read(), isEmpty);
      expect(fixture.connections, 0);
    });
  }

  test('blank names and duplicate names/IPs do not add records', () async {
    await expectLater(
      LocalPrinterCatalog.add(' ', '10.0.0.4'),
      throwsArgumentError,
    );
    await LocalPrinterCatalog.add('Bar', '10.0.0.4');
    await expectLater(
      LocalPrinterCatalog.add('bar', '10.0.0.5'),
      throwsArgumentError,
    );
    await expectLater(
      LocalPrinterCatalog.add('Other', '10.0.0.4'),
      throwsArgumentError,
    );
    await DatabaseService.savePrinterConfiguration(
      kitchenIp: '10.0.0.6',
      receiptIp: '',
      port: 9100,
    );
    await expectLater(
      LocalPrinterCatalog.add('Kitchen copy', '10.0.0.6'),
      throwsArgumentError,
    );
    expect(LocalPrinterCatalog.read(), hasLength(1));
  });

  test('legacy malformed data is visible and never replaced on add', () async {
    await DatabaseCore.settingsBox!.put('printersList', ['legacy-record']);
    expect(LocalPrinterCatalog.read, throwsA(anything));
    await expectLater(
      LocalPrinterCatalog.add('Station', '10.0.0.4'),
      throwsA(anything),
    );
    expect(DatabaseCore.settingsBox!.get('printersList'), ['legacy-record']);
  });

  for (final value in <dynamic>[
    {'unexpected': 'map'},
    'legacy',
    42,
  ]) {
    test('non-list printer registration $value is never overwritten', () async {
      await DatabaseCore.settingsBox!.put('printersList', value);
      expect(LocalPrinterCatalog.read, throwsStateError);
      await expectLater(
        LocalPrinterCatalog.add('Station', '10.0.0.4'),
        throwsStateError,
      );
      expect(DatabaseCore.settingsBox!.get('printersList'), value);
    });
  }

  test('manager cannot configure printers without developer scope', () async {
    DeveloperAccess.lock();
    await expectLater(
      LocalPrinterCatalog.add('Station', '10.0.0.4'),
      throwsStateError,
    );
    await expectLater(
      DatabaseService.savePrinterConfiguration(
        kitchenIp: '10.0.0.5',
        receiptIp: '',
        port: 9100,
      ),
      throwsStateError,
    );
    await expectLater(DatabaseService.savePrintersList([]), throwsStateError);
    expect(LocalPrinterCatalog.read, throwsStateError);
    expect(DatabaseService.getPrintersList, throwsStateError);
    expect(DatabaseService.getKitchenPrinterIp(), 'synthetic.invalid');
  });
  test(
    'a developer token without printer scope cannot add or edit printers',
    () async {
      await unlockSyntheticPrinterDeveloper(
        scopes: [DeveloperScope.diagnostics],
      );
      await expectLater(
        LocalPrinterCatalog.add('Station', '10.0.0.4'),
        throwsStateError,
      );
      await expectLater(
        DatabaseService.savePrinterConfiguration(
          kitchenIp: '10.0.0.5',
          receiptIp: '',
          port: 9100,
        ),
        throwsStateError,
      );
      expect(LocalPrinterCatalog.read, throwsStateError);
      expect(DatabaseService.getPrintersList, throwsStateError);
    },
  );
  test(
    'cloud primary role routing remains authoritative after an addition',
    () async {
      await DatabaseCore.settingsBox!.put('deviceRuntimeConfig', {
        'version': 1,
        'printers': {
          'kitchen': {'enabled': true, 'host': '10.0.0.8', 'port': 9200},
          'receipt': {'enabled': false, 'host': '', 'port': 9100},
        },
      });
      await LocalPrinterCatalog.add('Bar', '10.0.0.4');
      expect(DatabaseService.getKitchenPrinterIp(), '10.0.0.8');
      expect(DatabaseService.getKitchenPrinterPort(), 9200);
      expect(DatabaseService.getReceiptPrinterIp(), '');
    },
  );

  test(
    'kitchen copies need authenticated staff but no global receipt policy',
    () async {
      PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
      PrinterService.renderBytesOverride = () async => [1, 2, 3];
      expect(
        await PrinterService.printKitchenCheckInBackground(
          items: ['Synthetic food'],
          jobId: 'test-manual-kitchen',
          copyOf: 'order/test',
          copyReason: PrintReconciliation.kitchenCopyReason,
        ),
        true,
      );
      await fixture.dispatch();
      final job = DatabaseCore.metaBox!.get('print_job:v1:test-manual-kitchen');
      expect(
        (job as Map)['audit'][0]['reason'],
        PrintReconciliation.kitchenCopyReason,
      );
      expect(
        await PrinterService.printReceiptInBackground(
          items: ['Synthetic item'],
          total: 1,
          copyOf: 'sale/test',
          copyReason: 'copy test',
        ),
        false,
      );
      PosSession.clear();
      expect(
        await PrinterService.printKitchenCheckInBackground(
          items: ['Synthetic food'],
          copyOf: 'order/second',
          copyReason: 'copy test',
        ),
        false,
      );
      expect(fixture.transmitted, hasLength(1));
      PrintQueue.stop();
    },
  );
}
