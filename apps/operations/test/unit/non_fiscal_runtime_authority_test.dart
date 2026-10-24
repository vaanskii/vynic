import 'package:vynic/core/services/printing/print_identity_admission.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/feature_keys.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/runtime_config_sync.dart';

void main() {
  late Directory directory;
  const device = '00000000-0000-4000-8000-000000000001';
  const credential =
      'vynic-device-v1.$device.test-only-000000000000000000000000';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic_authority_');
    Hive.init(directory.path);
    DatabaseCore.settingsBox = await Hive.openBox('authority-settings');
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await EdgeDeviceCredentialStore.saveEnrollment(
      rawCredential: credential,
      venueId: 'venue-a',
      venueName: 'Synthetic A',
    );
  });
  tearDown(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    EdgeDeviceCredentialStore.resetForTest();
    await directory.delete(recursive: true);
  });
  Future<void> pull(List<String> features) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'version': 1,
          'venue': {'id': 'venue-a'},
          'features': features,
          'device': {'id': device, 'runtimeConfig': null},
        }),
        200,
      ),
    );
    await RuntimeConfigSync(client: client).pull();
    client.close();
  }

  bool allowed() => InventoryRepository.hasFeature(FeatureKeys.nonFiscalClose);

  test(
    'legacy cached lists cannot enable; explicit pull survives offline and restart; revocation persists',
    () async {
      expect(allowed(), false);
      await DatabaseCore.settingsBox!.put('runtimeFeatures', [
        FeatureKeys.nonFiscalClose,
      ]);
      expect(allowed(), false);
      await pull([FeatureKeys.nonFiscalClose]);
      expect(allowed(), true);
      final offline = MockClient(
        (_) async => throw http.ClientException('synthetic offline'),
      );
      await RuntimeConfigSync(client: offline).pull();
      expect(allowed(), true);
      offline.close();
      await Hive.close();
      DatabaseCore.settingsBox = await Hive.openBox('authority-settings');
      EdgeDeviceCredentialStore.resetForTest();
      EdgeDeviceCredentialStore.directoryOverride = directory.path;
      expect(allowed(), false, reason: 'no current enrollment identity yet');
      await EdgeDeviceCredentialStore.load();
      expect(
        allowed(),
        true,
        reason: 'known explicit offline permission survives restart',
      );
      await pull([]);
      expect(allowed(), false);
      await Hive.close();
      DatabaseCore.settingsBox = await Hive.openBox('authority-settings');
      expect(
        allowed(),
        false,
        reason: 'clock or restart cannot resurrect a persisted revocation',
      );
      await DatabaseCore.settingsBox!.put('runtimeFeatures', [
        FeatureKeys.nonFiscalClose,
      ]);
      expect(
        allowed(),
        false,
        reason: 'a stale legacy list cannot override revocation',
      );
    },
  );

  test(
    'foreign Venue, rotated credential and malformed authority cannot reuse an old grant',
    () async {
      await pull([FeatureKeys.nonFiscalClose]);
      final original = Map<String, dynamic>.from(
        DatabaseCore.settingsBox!.get(
              InventoryRepository.runtimeFeatureAuthorityKey,
            )
            as Map,
      );
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: credential,
        venueId: 'venue-b',
        venueName: 'Synthetic B',
      );
      expect(allowed(), false);
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential:
            'vynic-device-v1.$device.rotated-test-000000000000000000000000',
        venueId: 'venue-a',
        venueName: 'Synthetic A',
      );
      expect(allowed(), false);
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: credential,
        venueId: 'venue-a',
        venueName: 'Synthetic A',
      );
      for (final value in [
        null,
        [FeatureKeys.nonFiscalClose],
        {...original, 'enabled': 'true'},
        {...original, 'installationId': 'different-installation'},
      ]) {
        await DatabaseCore.settingsBox!.put(
          InventoryRepository.runtimeFeatureAuthorityKey,
          value,
        );
        expect(allowed(), false);
      }
    },
  );

  test(
    'authentication denial or malformed feature decision revokes capability; transient outage does not',
    () async {
      for (final status in [401, 403, 200]) {
        await pull([FeatureKeys.nonFiscalClose]);
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode(
              status == 200
                  ? {
                      'version': 1,
                      'venue': {'id': 'venue-a'},
                      'features': 'invalid',
                      'device': {'id': device, 'runtimeConfig': null},
                    }
                  : {'message': 'Unauthorized'},
            ),
            status,
          ),
        );
        await RuntimeConfigSync(client: client).pull();
        client.close();
        expect(allowed(), false);
      }
    },
  );
  test(
    'validated revocation is applied despite bad printer/profile or active native submission',
    () async {
      for (final problem in ['printer', 'profile', 'native']) {
        await pull([FeatureKeys.nonFiscalClose]);
        Object? submission;
        if (problem == 'native')
          submission = PrintIdentityAdmission.beginSubmission();
        try {
          final client = MockClient(
            (_) async => http.Response(
              jsonEncode({
                'version': 1,
                'venue': {
                  'id': 'venue-a',
                  if (problem == 'profile') 'name': 123,
                },
                'features': <String>[],
                'device': {
                  'id': device,
                  'runtimeConfig': problem == 'printer'
                      ? {'version': 'invalid'}
                      : null,
                },
              }),
              200,
            ),
          );
          await RuntimeConfigSync(client: client).pull();
          client.close();
          expect(allowed(), false, reason: problem);
        } finally {
          if (submission != null)
            PrintIdentityAdmission.finishSubmission(submission);
        }
      }
    },
  );
}
