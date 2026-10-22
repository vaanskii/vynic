import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/services/edge/restaurant_foundation_import.dart';

void main() {
  late Directory dir;
  late Box<String> staging;
  late Box<dynamic> orders;
  late Map<String, dynamic> snapshot;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('foundation-hive-');
    Hive.init(dir.path);
    staging = await Hive.openBox<String>('foundation');
    orders = await Hive.openBox<dynamic>('orders');
    snapshot = {
      'version': 1,
      'authority': 'CLOUD',
      'operationalActivationAllowed': false,
      'venueId': 'venue-a',
      'deviceId': 'device-a',
      'snapshotId': 'snapshot-1',
      'profile': {'id': 'venue-a', 'name': 'Restaurant'},
      'categories': [
        {
          'id': 'category-a',
          'subcategories': [
            {
              'id': 'sub-a',
              'items': [
                {
                  'id': 'item-a',
                  'price': 12.5,
                  'variants': [
                    {'id': 'variant-a', 'size': 0.5, 'price': 8.5},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Future<bool> run() => RestaurantFoundationImport(staging).stage(
    snapshot: snapshot,
    enrolledVenueId: snapshot['venueId'] as String,
    enrolledDeviceId: snapshot['deviceId'] as String,
    operationalBoxes: [orders],
  );
  test(
    'preserves whole foundation offline after reopen and exact retry',
    () async {
      expect(await run(), isTrue);
      await staging.close();
      staging = await Hive.openBox<String>('foundation');
      expect(RestaurantFoundationImport(staging).read(), snapshot);
      expect(await run(), isFalse);
      snapshot = Map.fromEntries(snapshot.entries.toList().reversed);
      expect(await run(), isFalse);
      expect(orders.isEmpty, isTrue);
      snapshot['snapshotId'] = 'changed';
      await expectLater(run(), throwsStateError);
    },
  );
  test('refuses operational history and wrong venue without writes', () async {
    await orders.put('sale', {'amount': 12});
    await expectLater(run(), throwsStateError);
    expect(staging.isEmpty, isTrue);
    await orders.clear();
    await expectLater(
      RestaurantFoundationImport(staging).stage(
        snapshot: snapshot,
        enrolledVenueId: 'venue-b',
        enrolledDeviceId: 'device-a',
        operationalBoxes: [orders],
      ),
      throwsStateError,
    );
    expect(staging.isEmpty, isTrue);
  });
  test('imports real server fixture when supplied', () async {
    final path = Platform.environment['FOUNDATION_BOOTSTRAP_FIXTURE'];
    if (path == null) return;
    snapshot =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    expect(await run(), isTrue);
    await staging.close();
    staging = await Hive.openBox<String>('foundation');
    expect(RestaurantFoundationImport(staging).read(), snapshot);
  });
}
