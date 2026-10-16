import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/local_venue_binding.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Startup Venue proof permits no network');
}

void main() {
  const venue = '11111111-1111-4111-8111-111111111111';
  const foreign = '22222222-2222-4222-8222-222222222222';
  const category = '33333333-3333-4333-8333-333333333333';
  const item = '44444444-4444-4444-8444-444444444444';
  late Directory directory;
  late HttpOverrides? previousHttp;
  File getIdentity() => File('${directory.path}/edge_device.json');

  Map<String, Object?> snapshot() => {
    'orders': {
      for (final entry in DatabaseCore.orderBox!.toMap().entries)
        '${entry.key}': entry.value.toJson(),
    },
    'tables': {
      for (final entry in DatabaseCore.tableBox!.toMap().entries)
        '${entry.key}': entry.value.toJson(),
    },
    'canonical': DatabaseCore.menuCanonicalBox!.toMap(),
    'journal': DatabaseCore.menuJournalBox!.toMap(),
    'menuProjection': {
      for (final entry in CanonicalMenu.readHive(
        DatabaseCore.menuBox!.values,
      ).entries)
        entry.key: {
          'kind': entry.value.kind.wire,
          'position': entry.value.position,
          'fields': entry.value.fields,
        },
    },
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos-startup-venue-');
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    LocalDataAdmission.failure = null;
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await DatabaseCore.open(managedDataDirectory: directory.path);
    expect(
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: 'vynic-device-v1.$venue.${'a' * 43}',
        venueId: venue,
        venueName: 'Synthetic original Venue',
      ),
      isTrue,
    );
    final local = MenuLocalStore.forBox(DatabaseCore.menuBox!);
    final canonical = CanonicalMenu(
      venueId: venue,
      sequence: 1,
      nodes: {
        category: CanonicalNode(
          kind: MenuKind.category,
          id: category,
          revision: 1,
          fields: {
            'slug': 'food',
            'nameEn': 'Food',
            'nameKa': 'Food',
            'sendToKitchen': true,
            'enabled': true,
            'sortOrder': 0,
          },
        ),
        item: CanonicalNode(
          kind: MenuKind.item,
          id: item,
          revision: 1,
          fields: {
            'categoryId': category,
            'subcategoryId': null,
            'nameEn': 'Captured',
            'nameKa': 'Captured',
            'price': 7.0,
            'sendToKitchen': true,
            'enabled': true,
            'sortOrder': 0,
          },
        ),
      },
    );
    await local.run(
      () => local.commit(canonical, expectedGeneration: local.generation),
    );
    await MenuRepository.updateItemInCategory(
      categoryIndex: 0,
      itemIndex: 0,
      nameEn: 'Offline edited',
      nameKa: 'Offline edited',
      price: 8,
    );
    await DatabaseCore.orderBox!.put(
      1,
      Order(
        orderId: 42,
        orderUuid: 'synthetic-unpaid-order',
        tableNumbers: ['42'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'captured-line',
            itemName: 'Captured',
            unitPrice: 7,
            quantity: 2,
            total: 14,
            menuItemId: item,
          ),
        ],
        totalAmount: 14,
        createdAt: DateTime.utc(2026, 10, 14),
        createdBy: 'synthetic-staff',
        status: 'confirmed',
        includeServiceFee: false,
      ),
    );
    await DatabaseCore.tableBox!.put(
      1,
      TableModel(tableNumber: '42', floor: 'first', activeOrderId: 42),
    );
    for (final box in [
      DatabaseCore.orderBox!,
      DatabaseCore.tableBox!,
      DatabaseCore.menuBox!,
      DatabaseCore.menuCanonicalBox!,
      DatabaseCore.menuJournalBox!,
    ]) {
      await box.flush();
    }
    expect(
      local.journal.all().where((entry) => entry.unresolved),
      hasLength(1),
    );
  });

  tearDown(() async {
    await Hive.close();
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    LocalDataAdmission.failure = null;
    HttpOverrides.global = previousHttp;
    await directory.delete(recursive: true);
  });

  test(
    'cold startup refuses a foreign identity without changing unpaid orders or Menu intents',
    () async {
      final before = snapshot();
      final original = await getIdentity().readAsString();
      final identity = jsonDecode(original) as Map;
      identity['venueId'] = foreign;
      identity['credential'] = 'vynic-device-v1.$foreign.${'b' * 43}';
      await getIdentity().writeAsString(jsonEncode(identity), flush: true);
      final foreignFile = await getIdentity().readAsBytes();
      await Hive.close();
      EdgeDeviceCredentialStore.resetForTest();

      await expectLater(
        DatabaseCore.open(managedDataDirectory: directory.path),
        throwsA(isA<LocalVenueMismatch>()),
      );

      expect(snapshot(), before);
      expect(await getIdentity().readAsBytes(), foreignFile);
      expect(
        DatabaseCore.orderBox!.get(1)!.orderUuid,
        'synthetic-unpaid-order',
      );
      expect(DatabaseCore.tableBox!.get(1)!.activeOrderId, 42);
    },
  );

  test(
    'startup reloads this directory before Menu recovery instead of trusting cached foreign metadata',
    () async {
      final before = snapshot();
      final original = await getIdentity().readAsString();
      final identity = jsonDecode(original) as Map;
      identity['venueId'] = foreign;
      identity['credential'] = 'vynic-device-v1.$foreign.${'b' * 43}';
      await getIdentity().writeAsString(jsonEncode(identity), flush: true);
      await EdgeDeviceCredentialStore.load();
      expect(EdgeDeviceCredentialStore.venueId, foreign);
      // Only the synthetic fixture file is restored; no real identity is edited.
      await getIdentity().writeAsString(original, flush: true);
      await Hive.close();

      await DatabaseCore.open(managedDataDirectory: directory.path);

      expect(EdgeDeviceCredentialStore.venueId, venue);
      expect(snapshot(), before);
    },
  );

  test(
    'rejected foreign enrollment leaves the original identity and offline work restartable',
    () async {
      final before = snapshot();
      final original = await getIdentity().readAsBytes();

      await expectLater(
        EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: 'vynic-device-v1.$foreign.${'b' * 43}',
          venueId: foreign,
          venueName: 'Synthetic different Venue',
        ),
        throwsA(isA<LocalVenueMismatch>()),
      );
      expect(await getIdentity().readAsBytes(), original);
      expect(snapshot(), before);
      await Hive.close();
      EdgeDeviceCredentialStore.resetForTest();

      await DatabaseCore.open(managedDataDirectory: directory.path);

      expect(EdgeDeviceCredentialStore.venueId, venue);
      expect(snapshot(), before);
    },
  );

  test(
    'a foreign pending projection is refused before WAL recovery touches offline work',
    () async {
      final canonical = DatabaseCore.menuCanonicalBox!.get(
        MenuLocalStore.stateKey,
      )!;
      await DatabaseCore.menuCanonicalBox!.put(
        MenuLocalStore.commitKey,
        jsonEncode({
          'version': 1,
          'baseGeneration': 1,
          'generation': 2,
          'canonical': canonical,
          'projection': CanonicalMenu(
            venueId: foreign,
            sequence: 1,
          ).toJsonString(),
          'puts': [],
          'removes': [],
        }),
      );
      final before = snapshot();
      await Hive.close();
      EdgeDeviceCredentialStore.resetForTest();

      await expectLater(
        DatabaseCore.open(managedDataDirectory: directory.path),
        throwsA(isA<LocalVenueMismatch>()),
      );

      expect(snapshot(), before);
      expect(
        DatabaseCore.menuCanonicalBox!.containsKey(MenuLocalStore.commitKey),
        isTrue,
      );
    },
  );

  test(
    'Menu initialization returns the actionable mismatch while retaining the guard and data',
    () async {
      final before = snapshot();
      final local = MenuLocalStore.attach(
        menuBox: DatabaseCore.menuBox!,
        stateBox: DatabaseCore.menuCanonicalBox!,
        journalBox: DatabaseCore.menuJournalBox!,
        venueId: () => foreign,
      );

      await expectLater(
        local.initialize(),
        throwsA(
          isA<LocalVenueMismatch>()
              .having((error) => error.storedVenueId, 'stored Venue', venue)
              .having((error) => error.targetVenueId, 'target Venue', foreign)
              .having(
                (error) => error.message,
                'message',
                contains('Existing data has been preserved'),
              ),
        ),
      );

      expect(snapshot(), before);
    },
  );
}
