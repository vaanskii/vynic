import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/services/edge/runtime_config_sync.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/feature_keys.dart';

void main() {
  test(
    'printer cache survives restart, keeps ports and disabled state without Cloud',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vynic-printer-runtime',
      );
      Hive.init(directory.path);
      DatabaseCore.settingsBox = await Hive.openBox('runtime-settings');
      EdgeDeviceCredentialStore.resetForTest();
      EdgeDeviceCredentialStore.directoryOverride = directory.path;
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential:
            'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-000000000000000000000000',
        venueId: 'test-venue',
        venueName: 'Test venue',
      );
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'version': 1,
            'venue': {
              'id': 'test-venue',
              'name': 'რესტორანი',
              'branchName': 'ვაკე',
              'address': 'თბილისი',
              'profileUpdatedAt': '2026-09-13T10:00:00Z',
            },
            'features': [FeatureKeys.pos],
            'device': {
              'id': EdgeDeviceCredentialStore.deviceId,
              'displayName': 'vankisi-terminal1',
              'runtimeConfig': null,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await RuntimeConfigSync(client: client).pull();
      expect(
        DatabaseCore.settingsBox!.get('enrolledDeviceName'),
        'vankisi-terminal1',
      );
      expect(InventoryRepository.hasFeature(FeatureKeys.inventory), isFalse);
      expect(SettingsRepository.getVenueAddress(), 'თბილისი');
      expect(DatabaseCore.settingsBox!.get('venueBranchName'), 'ვაკე');
      await DatabaseCore.settingsBox!.put('pendingVenueProfile', {
        'venueId': 'test-venue',
        'profile': {'name': 'ოფლაინ სახელი', 'branchName': 'დიდუბე'},
      });
      await DatabaseCore.settingsBox!.put('venueName', 'ოფლაინ სახელი');
      final offlineProfile = MockClient(
        (request) async => request.method == 'PUT'
            ? http.Response('unavailable', 503)
            : client.get(request.url),
      );
      await RuntimeConfigSync(client: offlineProfile).pull();
      expect(SettingsRepository.getVenueName(), 'ოფლაინ სახელი');
      expect(DatabaseCore.settingsBox!.get('pendingVenueProfile'), isNotNull);
      expect(InventoryRepository.hasFeature(FeatureKeys.inventory), isFalse);
      offlineProfile.close();
      await Hive.close();
      DatabaseCore.settingsBox = await Hive.openBox('runtime-settings');
      expect(DatabaseCore.settingsBox!.get('pendingVenueProfile'), isNotNull);
      expect(SettingsRepository.getVenueName(), 'ოფლაინ სახელი');
      final acceptedProfile = MockClient(
        (request) async => request.method == 'PUT'
            ? http.Response('{}', 200)
            : client.get(request.url),
      );
      await RuntimeConfigSync(client: acceptedProfile).pull();
      expect(DatabaseCore.settingsBox!.get('pendingVenueProfile'), isNull);
      expect(SettingsRepository.getVenueName(), 'რესტორანი');
      await DatabaseCore.settingsBox!.put('pendingVenueProfile', {
        'venueId': 'other-venue',
        'profile': {'name': 'Do not send'},
      });
      final foreign = MockClient((request) async {
        expect(request.method, 'GET');
        return client.get(request.url);
      });
      await RuntimeConfigSync(client: foreign).pull();
      expect(DatabaseCore.settingsBox!.get('pendingVenueProfile'), isNull);
      foreign.close();
      acceptedProfile.close();
      client.close();
      EdgeDeviceCredentialStore.resetForTest();
      var updates = 0;
      void changed() => updates++;
      InventoryRepository.featureRevision.addListener(changed);
      await InventoryRepository.applyRuntimeFeatures([
        FeatureKeys.pos,
        FeatureKeys.nonFiscalClose,
      ]);
      expect(
        InventoryRepository.hasFeature(FeatureKeys.nonFiscalClose),
        isTrue,
      );
      await InventoryRepository.applyRuntimeFeatures([FeatureKeys.pos]);
      expect(
        InventoryRepository.hasFeature(FeatureKeys.nonFiscalClose),
        isFalse,
      );
      expect(updates, 2);
      InventoryRepository.featureRevision.removeListener(changed);
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
      expect(
        InventoryRepository.hasFeature(FeatureKeys.nonFiscalClose),
        isFalse,
      );
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
