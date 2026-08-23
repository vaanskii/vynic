import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';

/// What a terminal comes up with the very first time it is switched on.
///
/// `.env` is bundled as a Flutter asset, which means it is baked into whatever
/// build ships. Seeding the database from it meant a POS installed at a
/// customer site started life pre-configured with the printer addresses from
/// the developer's file — real-looking values for a network it has never been
/// on. Nobody looks at a filled-in field.
///
/// These tests load a `.env` deliberately full of the wrong answers and then
/// check that none of them reached the database.

late Directory _tempDir;

Future<void> _loadPoisonedEnv() async {
  dotenv.loadFromString(
    envString: '''
PRINTER_KITCHEN_IP=10.10.10.4
PRINTER_RECEIPT_IP=10.10.10.5
PRINTER_PORT=9999
DEFAULT_LANGUAGE=en
''',
  );
}

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_first_run');
    Hive.init(_tempDir.path);
    await _loadPoisonedEnv();
  });

  setUp(() async {
    // A brand new install: an empty settings box and nothing else.
    await Hive.deleteBoxFromDisk('fr_settings');
    DatabaseCore.settingsBox = await Hive.openBox('fr_settings');
    await SettingsRepository.seedDefaults();
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('printers', () {
    test('start blank rather than pointing at the developer network', () {
      expect(SettingsRepository.getKitchenPrinterIp(), '');
      expect(SettingsRepository.getReceiptPrinterIp(), '');
    });

    test('an address cleared in Settings stays cleared', () async {
      // The getters used to fall through to `.env` whenever the stored value
      // was blank, so clearing the field did not clear the printer — it
      // reverted it to a build-time address, and the admin panel then showed
      // that address back as though someone had typed it.
      await DatabaseCore.settingsBox!.put('printerKitchenIp', '10.0.0.9');
      expect(SettingsRepository.getKitchenPrinterIp(), '10.0.0.9');

      await DatabaseCore.settingsBox!.put('printerKitchenIp', '');
      expect(SettingsRepository.getKitchenPrinterIp(), '');
    });

    test('the port is the standard one, not whatever the build carried', () {
      expect(DatabaseCore.settingsBox!.get('printerPort'), 9100);
    });
  });

  group('language', () {
    test('starts Georgian regardless of what the build carried', () {
      expect(SettingsRepository.getDefaultLanguage(), 'ka');
    });
  });

  test('a second start does not overwrite what the venue configured', () async {
    // The defaults only fill gaps. If re-running them clobbered real settings,
    // every restart would undo the install.
    await DatabaseCore.settingsBox!.put('printerKitchenIp', '192.168.1.50');
    await DatabaseCore.settingsBox!.put('defaultLanguage', 'en');

    await SettingsRepository.seedDefaults();

    expect(SettingsRepository.getKitchenPrinterIp(), '192.168.1.50');
    expect(SettingsRepository.getDefaultLanguage(), 'en');
  });
}
