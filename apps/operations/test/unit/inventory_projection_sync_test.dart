import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/inventory_projection_sync_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('inventory_projection');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('inventory_projection_test');
    DatabaseCore.inventoryBox = await Hive.openBox('inventory_projection_test');
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.inventoryBox = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('Device-authenticated pull replaces the local projection', () async {
    late Uri requested;
    late String? credential;
    final client = InventoryProjectionClient(
      baseUrl: () => 'https://cloud.example',
      credential: () => 'vynic-device-v1.device.secret',
      httpClient: MockClient((request) async {
        requested = request.url;
        credential = request.headers['x-pos-sync-key'];
        return http.Response(
          jsonEncode({
            'version': 1,
            'generatedAt': '2026-09-05T10:00:00Z',
            'stockItems': [
              {
                'id': 'stock-1',
                'name': 'Flour',
                'baseUnit': 'kg',
                'isActive': true,
                'createdAt': '2026-09-05T10:00:00Z',
                'updatedAt': '2026-09-05T10:00:00Z',
              },
            ],
            'suppliers': <Object>[],
          }),
          200,
        );
      }),
    );
    final service = InventoryProjectionSyncService(client: client);

    expect(await service.syncOnce(), EdgeTransportOutcome.ok);
    expect(requested.path, '/edge/inventory/catalog');
    expect(requested.queryParameters['version'], '5');
    expect(requested.queryParameters, {'version': '5'});
    expect(credential, 'vynic-device-v1.device.secret');
    expect(InventoryRepository.getStockItems().single.id, 'stock-1');
  });

  test('failed refresh keeps the last known good offline catalog', () async {
    await InventoryRepository.replaceCatalog({
      'stockItems': [
        {
          'id': 'kept',
          'name': 'Kept item',
          'baseUnit': 'piece',
          'createdAt': '2026-09-05T10:00:00Z',
          'updatedAt': '2026-09-05T10:00:00Z',
        },
      ],
      'suppliers': <Object>[],
    });
    final client = InventoryProjectionClient(
      baseUrl: () => 'https://cloud.example',
      credential: () => 'vynic-device-v1.device.secret',
      httpClient: MockClient((_) async => http.Response('offline', 503)),
    );
    final service = InventoryProjectionSyncService(client: client);

    expect(await service.syncOnce(), EdgeTransportOutcome.serverError);
    expect(InventoryRepository.getStockItems().single.id, 'kept');
  });
}
