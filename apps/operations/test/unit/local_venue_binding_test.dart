import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_venue_binding.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_enrollment_client.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';

void main() {
  const oldVenue = '11111111-1111-4111-8111-111111111111';
  const newVenue = '22222222-2222-4222-8222-222222222222';
  final originalCredential = 'vynic-device-v1.$oldVenue.${'a' * 43}';
  final newCredential = 'vynic-device-v1.$newVenue.${'b' * 43}';
  String menu(String venue) =>
      CanonicalMenu(venueId: venue, sequence: 0).toJsonString();
  late Directory directory;
  late Box<String> state;
  late Box<String> journal;
  late Box settings;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('venue-binding-');
    state = await Hive.openBox<String>('canonical', path: directory.path);
    journal = await Hive.openBox<String>('journal', path: directory.path);
    settings = await Hive.openBox('settings', path: directory.path);
    DatabaseCore.menuCanonicalBox = state;
    DatabaseCore.menuJournalBox = journal;
    DatabaseCore.settingsBox = settings;
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    EdgeDeviceCredentialStore.resetForTest();
    await EdgeDeviceCredentialStore.load();
    await EdgeDeviceCredentialStore.saveEnrollment(
      rawCredential: originalCredential,
      venueId: oldVenue,
      venueName: 'Original restaurant',
    );
  });

  tearDown(() async {
    await Hive.close();
    DatabaseCore.menuCanonicalBox = null;
    DatabaseCore.menuJournalBox = null;
    DatabaseCore.settingsBox = null;
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    await directory.delete(recursive: true);
  });

  for (final source in ['state', 'baseline', 'commit', 'journal', 'restore']) {
    test(
      'foreign $source refuses enrollment without changing disk or memory',
      () async {
        switch (source) {
          case 'state':
            await state.put(MenuLocalStore.stateKey, menu(oldVenue));
          case 'baseline':
            await state.put(MenuLocalStore.baselineKey, menu(oldVenue));
          case 'commit':
            await state.put(
              MenuLocalStore.commitKey,
              jsonEncode({
                'canonical': menu(oldVenue),
                'projection': menu(oldVenue),
                'puts': [],
              }),
            );
          case 'journal':
            await journal.put(
              '000000000001',
              jsonEncode({'venueId': oldVenue}),
            );
          case 'restore':
            await settings.put('restoreVenueBinding', oldVenue);
        }
        final identityFile = File('${directory.path}/edge_device.json');
        final originalBytes = await identityFile.readAsBytes();
        final originalState = state.toMap();
        final originalJournal = journal.toMap();
        // Clearing credentials must not detach ownership of retained data.
        await EdgeDeviceCredentialStore.clear();
        final clearedBytes = await identityFile.readAsBytes();
        await expectLater(
          EdgeDeviceCredentialStore.saveEnrollment(
            rawCredential: newCredential,
            venueId: newVenue,
            venueName: 'Different restaurant',
          ),
          throwsA(isA<LocalVenueMismatch>()),
        );
        expect(await identityFile.readAsBytes(), clearedBytes);
        expect(originalBytes, isNot(clearedBytes));
        expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
        expect(state.toMap(), originalState);
        expect(journal.toMap(), originalJournal);
        EdgeDeviceCredentialStore.resetForTest();
        await EdgeDeviceCredentialStore.load();
        expect(EdgeDeviceCredentialStore.hasCredential, isFalse);
      },
    );
  }

  test(
    'same-Venue credential rotation survives restart with Menu intact',
    () async {
      await state.put(MenuLocalStore.stateKey, menu(oldVenue));
      expect(
        await EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: newCredential,
          venueId: oldVenue,
          venueName: 'Original restaurant',
        ),
        isTrue,
      );
      EdgeDeviceCredentialStore.resetForTest();
      await EdgeDeviceCredentialStore.load();
      DatabaseCore.validateVenueBinding(oldVenue);
      expect(EdgeDeviceCredentialStore.credential, newCredential);
      expect(state.get(MenuLocalStore.stateKey), menu(oldVenue));
    },
  );

  test(
    'enrollment reports a conflict and retains the original identity',
    () async {
      await state.put(MenuLocalStore.stateKey, menu(oldVenue));
      final service = PosEnrollmentService(
        client: EdgeEnrollmentClient(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'credential': newCredential,
                'venue': {'id': newVenue, 'name': 'Different restaurant'},
                'device': {'id': newVenue},
              }),
              200,
            ),
          ),
        ),
      );
      addTearDown(service.close);
      final result = await service.enroll(
        serverAddress: 'http://127.0.0.1:3000',
        code: 'synthetic-code',
      );
      expect(result.status, PosEnrollmentStatus.conflict);
      expect(result.message, contains('Existing data has been preserved'));
      expect(EdgeDeviceCredentialStore.credential, originalCredential);
      expect(EdgeDeviceCredentialStore.venueId, oldVenue);
    },
  );

  test('an enrollment response without a Venue is rejected', () async {
    final client = EdgeEnrollmentClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'credential': newCredential,
            'venue': {'name': 'Missing identity'},
            'device': {'id': newVenue},
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    final result = await client.enroll(
      baseUrl: 'http://127.0.0.1:3000',
      code: 'synthetic-code',
      installationId: 'synthetic-installation',
      platform: 'MACOS',
    );
    expect(result.outcome, EdgeEnrollmentOutcome.serverError);
  });

  test(
    'startup refuses mismatch before operational recovery mutates data',
    () async {
      await state.close();
      state = await Hive.openBox<String>(
        DatabaseCore.menuCanonicalBoxName,
        path: directory.path,
      );
      await state.put(MenuLocalStore.stateKey, menu(newVenue));
      await state.flush();
      await Hive.close();
      EdgeDeviceCredentialStore.resetForTest();
      await expectLater(
        DatabaseCore.open(managedDataDirectory: directory.path),
        throwsA(isA<LocalVenueMismatch>()),
      );
      expect(
        DatabaseCore.menuCanonicalBox!.get(MenuLocalStore.stateKey),
        menu(newVenue),
      );
      expect(DatabaseCore.menuBox!.isEmpty, isTrue);
      expect(DatabaseCore.metaBox!.isEmpty, isTrue);
      expect(EdgeDeviceCredentialStore.venueId, oldVenue);
    },
  );
}
