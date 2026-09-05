import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/sync/api_config.dart';

class InventoryProjectionClient {
  InventoryProjectionClient({
    http.Client? httpClient,
    String Function()? baseUrl,
    String? Function()? credential,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? (() => ApiConfig.baseUrl),
       _credential = credential ?? (() => EdgeDeviceCredentialStore.credential);

  final http.Client _http;
  final String Function() _baseUrl;
  final String? Function() _credential;
  final Duration timeout;

  Future<({EdgeTransportOutcome outcome, Map<String, dynamic>? catalog})>
  fetch() async {
    final credential = _credential();
    if (credential == null || credential.isEmpty) {
      return (outcome: EdgeTransportOutcome.notProvisioned, catalog: null);
    }
    try {
      final response = await _http
          .get(
            Uri.parse('${_baseUrl()}/edge/inventory/catalog'),
            headers: <String, String>{
              'Accept': 'application/json',
              'X-POS-Sync-Key': credential,
            },
          )
          .timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return (outcome: EdgeTransportOutcome.unauthorized, catalog: null);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (outcome: EdgeTransportOutcome.serverError, catalog: null);
      }
      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        return (outcome: EdgeTransportOutcome.serverError, catalog: null);
      }
      return (
        outcome: EdgeTransportOutcome.ok,
        catalog: Map<String, dynamic>.from(decoded),
      );
    } catch (error) {
      debugPrint('[Inventory] Catalog request failed: $error');
      return (outcome: EdgeTransportOutcome.unreachable, catalog: null);
    }
  }

  void close() => _http.close();
}

/// Periodically refreshes the POS's complete Inventory cache from Cloud.
/// Failures leave the last good Hive projection intact and never block POS.
class InventoryProjectionSyncService {
  InventoryProjectionSyncService({
    InventoryProjectionClient? client,
    this.refreshInterval = const Duration(minutes: 1),
  }) : _client = client ?? InventoryProjectionClient();

  static InventoryProjectionSyncService? _instance;
  static InventoryProjectionSyncService instance() =>
      _instance ??= InventoryProjectionSyncService();

  @visibleForTesting
  static void overrideInstance(InventoryProjectionSyncService? service) {
    _instance = service;
  }

  final InventoryProjectionClient _client;
  final Duration refreshInterval;
  Timer? _timer;
  bool _running = false;
  bool _syncing = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    if (!EdgeDeviceCredentialStore.isLoaded) {
      await EdgeDeviceCredentialStore.load();
    }
    if (!EdgeDeviceCredentialStore.hasCredential) return;
    _running = true;
    unawaited(syncOnce());
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(syncOnce()));
  }

  Future<EdgeTransportOutcome> syncOnce() async {
    if (_syncing) return EdgeTransportOutcome.ok;
    _syncing = true;
    try {
      final response = await _client.fetch();
      if (response.outcome == EdgeTransportOutcome.ok &&
          response.catalog != null) {
        await InventoryRepository.replaceCatalog(response.catalog!);
      }
      return response.outcome;
    } catch (error) {
      debugPrint('[Inventory] Projection refresh failed: $error');
      return EdgeTransportOutcome.serverError;
    } finally {
      _syncing = false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}
