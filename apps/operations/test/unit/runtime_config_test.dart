import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/services/edge/runtime_config_sync.dart';

void main() {
  test(
    'printer cache survives restart, keeps ports and disabled state without Cloud',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vynic-printer-runtime',
      );
      Hive.init(directory.path);
      DatabaseCore.settingsBox = await Hive.openBox('runtime-settings');
      final config = <String, dynamic>{
        'version': 1,
        'printers': {
          'kitchen': {'enabled': true, 'host': '192.168.8.2', 'port': 9200},
          'receipt': {'enabled': false, 'host': '192.168.8.3', 'port': 9100},
        },
      };
      RuntimeConfigSync.validate(config);
      await DatabaseCore.settingsBox!.put('deviceRuntimeConfig', config);
      await Hive.close();
      DatabaseCore.settingsBox = await Hive.openBox('runtime-settings');
      expect(SettingsRepository.getKitchenPrinterIp(), '192.168.8.2');
      expect(SettingsRepository.getKitchenPrinterPort(), 9200);
      expect(SettingsRepository.getReceiptPrinterIp(), '');
      expect(
        () => RuntimeConfigSync.validate({'version': 1, 'printers': {}}),
        throwsFormatException,
      );
      expect(SettingsRepository.getKitchenPrinterPort(), 9200);
      await Hive.close();
      DatabaseCore.settingsBox = null;
      await directory.delete(recursive: true);
    },
  );
}
