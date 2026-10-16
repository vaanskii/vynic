import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'printer_destination.dart';
import 'printer_capability_profile.dart';
import 'windows_spooler_transport.dart';
import 'cloud_printer_runtime.dart';

/// Additional local printers are registered, but receive no implicit routing.
class LocalPrinterCatalog {
  LocalPrinterCatalog._();

  static const routesSettingKey = 'printerRoutes:v1';
  static const _maxRoutes = 1024;

  /// Tests use a synthetic channel; production always enumerates Windows.
  @visibleForTesting
  static WindowsSpoolerTransport? windowsTransportOverride;

  static bool get windowsQueuesAvailable =>
      Platform.isWindows || windowsTransportOverride != null;

  static String? get enrolledDeviceId => EdgeDeviceCredentialStore.hasCredential
      ? EdgeDeviceCredentialStore.deviceId
      : null;

  static void _requireAdministration() {
    if (!DeveloperAccess.can(DeveloperScope.printers)) {
      throw StateError('Developer printer access is required');
    }
  }

  /// Installed queues are configuration choices, not ESC/POS qualification.
  static Future<List<WindowsPrinterQueue>>
  listWindowsQueuesForAdministration() async {
    _requireAdministration();
    final owner = enrolledDeviceId;
    if (owner == null) {
      throw StateError('Windows printer queues require an enrolled Device');
    }
    final queues = await (windowsTransportOverride ?? WindowsSpoolerTransport())
        .listQueues();
    _requireAdministration();
    if (owner != enrolledDeviceId) {
      throw StateError(
        'The enrolled Device changed; enumerate Windows queues again',
      );
    }
    for (final queue in queues) {
      PrinterDestination.windowsSpooler(
        ownerDeviceId: owner,
        queueName: queue.name,
        driverName: queue.driver,
        portName: queue.port,
      );
    }
    return queues;
  }

  static bool _validName(String value) =>
      value.isNotEmpty &&
      value.trim() == value &&
      value.length <= 80 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

  static List<PrinterRoute> _readRoutes() {
    final settings = DatabaseCore.settingsBox;
    if (settings == null || !settings.isOpen) {
      throw StateError('Local printer settings are unavailable');
    }
    if (!settings.containsKey(routesSettingKey)) return const [];
    final raw = settings.get(routesSettingKey);
    if (raw is! List || raw.length > _maxRoutes) {
      throw StateError('Stored printer routes need review');
    }
    final ids = <String>{};
    final names = <String>{};
    final endpoints = <String>{};
    final roles = <PrinterRole>{};
    final routes = <PrinterRoute>[];
    for (final row in raw) {
      final route = PrinterRoute.decode(row);
      if (!_validName(route.name) ||
          !ids.add(route.id) ||
          !names.add(route.name.toLowerCase()) ||
          !endpoints.add(route.destination.identity) ||
          (route.role != PrinterRole.additional && !roles.add(route.role)) ||
          (route.destination.kind == PrinterTransportKind.tcp &&
              !validIp(route.destination.host!))) {
        throw StateError('Stored printer routes need review');
      }
      routes.add(route);
    }
    return List<PrinterRoute>.unmodifiable(routes);
  }

  /// The print worker reads accepted configuration without a developer grant.
  /// Legacy registrations are deliberately absent: they remain unassigned.
  static List<PrinterRoute> readRoutesForDispatch({PrinterRole? role}) {
    final cloud = _cloudRuntimeForDispatch();
    if (cloud != null) {
      if (role != null) {
        return List<PrinterRoute>.unmodifiable([
          cloud.resolveForDispatch(role: role),
        ]);
      }
      if (cloud.phase == CloudPrinterRuntimePhase.prepared) {
        cloud.resolveForDispatch(role: PrinterRole.kitchen);
      }
      // An all-routes plan never silently drops a disabled or held row.
      return List<PrinterRoute>.unmodifiable([
        for (final entry in cloud.routes)
          cloud.resolveForDispatch(
            role: entry.route.role,
            routeId: entry.route.id,
          ),
      ]);
    }
    // Structural corruption anywhere remains visible. A caller planning one
    // role may still use it while an unrelated valid route is explicitly held.
    final catalog = _readRoutes();
    final routes = role == null
        ? catalog
        : List<PrinterRoute>.unmodifiable(
            catalog.where((route) => route.role == role),
          );
    for (final route in routes) {
      final hold = routeHoldReason(route);
      if (hold != null) throw StateError(hold);
    }
    return routes;
  }

  /// Administration retains held routes so they can be reviewed explicitly.
  static List<PrinterRoute> readRoutesForAdministration() {
    _requireAdministration();
    return _readRoutes();
  }

  static CloudPrinterRuntime? _cloudRuntimeForDispatch() {
    final raw = DatabaseCore.settingsBox?.get('deviceRuntimeConfig');
    if (raw == null || (raw is Map && raw['version'] == 1)) return null;
    final device = enrolledDeviceId;
    final venue = EdgeDeviceCredentialStore.venueId;
    if (device == null ||
        venue == null ||
        EdgeDeviceCredentialStore.credential == null) {
      throw StateError(
        'Cloud printer routes require the matching enrolled Device and Venue',
      );
    }
    return CloudPrinterRuntime.decode(
      raw,
      boundDeviceId: device,
      boundVenueId: venue,
    );
  }

  static bool cloudOwnsRole(PrinterRole role) {
    final raw = DatabaseCore.settingsBox?.get('deviceRuntimeConfig');
    if (raw == null) return false;
    // Unknown/corrupt future configuration cannot authorize a local override.
    return (raw is! Map || raw['version'] != 1) ||
        role == PrinterRole.kitchen ||
        role == PrinterRole.receipt;
  }

  /// A Cloud primary cache, including disabled/malformed values, cannot be
  /// replaced by a local route without a separate transport-aware migration.
  static String? routeHoldReason(PrinterRoute route) {
    if (cloudOwnsRole(route.role)) {
      return 'Cloud owns the ${route.role.name} printer role; '
          'transport-aware configuration migration is required';
    }
    if (route.destination.kind == PrinterTransportKind.windowsSpooler &&
        route.destination.ownerDeviceId != enrolledDeviceId) {
      return 'Windows printer route belongs to a different enrolled Device; '
          'review the local queue before dispatch';
    }
    if (!route.capabilityProfile.hasImplementedRenderer) {
      return 'Printer route uses Windows driver-rendered output; '
          'the required renderer is not implemented';
    }
    return null;
  }

  /// Compare-and-swap a single route. Creation expects revision zero; edits
  /// retain the accepted id and increment its revision for future jobs only.
  static Future<PrinterRoute> saveRoute({
    String? id,
    required String name,
    required PrinterRole role,
    required PrinterDestination destination,
    required int expectedRevision,
    PrinterCapabilityProfile? capabilityProfile,
  }) => LocalDataAdmission.mutate(() async {
    _requireAdministration();
    name = name.trim();
    if (!_validName(name)) {
      throw ArgumentError('Printer name must contain 1–80 valid characters');
    }
    if (expectedRevision < 0 ||
        expectedRevision >= 0x7fffffff ||
        (id == null && expectedRevision != 0) ||
        (id != null && expectedRevision == 0)) {
      throw ArgumentError('Provide the current printer route revision');
    }
    final legacy = read(); // Never replace or adopt malformed legacy data.
    final routes = _readRoutes(); // Never overwrite malformed route records.
    final existing = routes.where((route) => route.id == id).firstOrNull;
    if (id != null &&
        (existing == null || existing.revision != expectedRevision)) {
      throw PrinterRouteRevisionConflict(
        id,
        expectedRevision,
        existing?.revision,
      );
    }
    if (id == null && routes.length >= _maxRoutes) {
      throw StateError('The local printer route limit has been reached');
    }
    if (cloudOwnsRole(role)) {
      throw StateError(
        'Cloud owns the ${role.name} printer role; '
        'transport-aware configuration migration is required',
      );
    }
    if (destination.kind == PrinterTransportKind.tcp) {
      if (!validIp(destination.host!)) {
        throw ArgumentError('Enter a valid IPv4 address');
      }
    } else {
      if (destination.ownerDeviceId != enrolledDeviceId ||
          enrolledDeviceId == null) {
        throw StateError(
          'Windows printer route must belong to this enrolled Device',
        );
      }
      final queues = await listWindowsQueuesForAdministration();
      if (!queues.any(
        (queue) =>
            queue.name == destination.queueName &&
            queue.driver == destination.driverName &&
            queue.port == destination.portName,
      )) {
        throw StateError(
          'The exact Windows queue, driver and port are no longer installed',
        );
      }
      // Enumeration is asynchronous: locking the panel or replacing the Device
      // while it is pending must never authorize a later settings write.
      _requireAdministration();
      if (destination.ownerDeviceId != enrolledDeviceId) {
        throw StateError(
          'The enrolled Device changed; select the Windows queue again',
        );
      }
    }
    final candidate = PrinterRoute.decode({
      'protocol': 1,
      'id': existing?.id ?? const Uuid().v4(),
      'name': name,
      'role': role.name,
      'revision': expectedRevision + 1,
      'destination': destination.toMap(),
      'capabilityProfile':
          (capabilityProfile ??
                  existing?.capabilityProfile ??
                  PrinterCapabilityProfile.genericEscposRaster())
              .toMap(),
    });
    for (final route in routes.where((route) => route.id != candidate.id)) {
      if (route.name.toLowerCase() == name.toLowerCase()) {
        throw ArgumentError('A printer route with this name already exists');
      }
      if (route.destination.identity == destination.identity) {
        throw ArgumentError('This printer endpoint is already configured');
      }
      if (role != PrinterRole.additional && route.role == role) {
        throw ArgumentError(
          'The ${role.name} printer role is already configured',
        );
      }
    }
    if (legacy.any(
      (row) =>
          (row['name'] as String).trim().toLowerCase() == name.toLowerCase() ||
          (destination.kind == PrinterTransportKind.tcp &&
              row['ip'] == destination.host &&
              (row['port'] ?? 9100) == destination.port),
    )) {
      throw ArgumentError(
        'A legacy unassigned printer already uses this name or endpoint',
      );
    }
    if (destination.kind == PrinterTransportKind.tcp &&
        ((role != PrinterRole.kitchen &&
                DatabaseService.getKitchenPrinterIp() == destination.host &&
                DatabaseService.getKitchenPrinterPort() == destination.port) ||
            (role != PrinterRole.receipt &&
                DatabaseService.getReceiptPrinterIp() == destination.host &&
                DatabaseService.getReceiptPrinterPort() == destination.port))) {
      throw ArgumentError(
        'This printer endpoint is already configured for a primary role',
      );
    }
    _requireAdministration();
    if (cloudOwnsRole(role)) {
      throw StateError(
        'Cloud owns the ${role.name} printer role; '
        'transport-aware configuration migration is required',
      );
    }
    final settings = DatabaseCore.settingsBox!;
    await settings.put(routesSettingKey, [
      for (final route in routes)
        if (route.id != candidate.id) route.toMap(),
      candidate.toMap(),
    ]);
    await settings.flush();
    return candidate;
  });

  static bool validIp(String value) {
    final parts = value.split('.');
    return parts.length == 4 &&
        parts.every(
          (part) =>
              RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part) &&
              int.parse(part) <= 255,
        );
  }

  static List<Map<String, dynamic>> read() {
    final rows = DatabaseService.getPrintersList();
    final names = <String>{};
    final ips = <String>{};
    final ids = <String>{};
    for (final row in rows) {
      final name = row['name'];
      final ip = row['ip'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > 80 ||
          ip is! String ||
          !validIp(ip) ||
          !names.add(name.trim().toLowerCase()) ||
          !ips.add(ip) ||
          (row['id'] != null &&
              (row['id'] is! String ||
                  (row['id'] as String).isEmpty ||
                  !ids.add(row['id'] as String)))) {
        throw StateError(
          'Stored additional printer configuration needs review',
        );
      }
    }
    return rows;
  }

  static Future<void> add(
    String name,
    String ip,
  ) => LocalDataAdmission.mutate(() async {
    if (!DeveloperAccess.can(DeveloperScope.printers)) {
      throw StateError('Developer printer access is required');
    }
    name = name.trim();
    ip = ip.trim();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('Printer name must contain 1–80 characters');
    }
    if (!validIp(ip)) throw ArgumentError('Enter a valid IPv4 address');
    final rows = read(); // Malformed legacy records are never overwritten.
    final routes = _readRoutes();
    if (routes.any(
      (route) =>
          route.name.toLowerCase() == name.toLowerCase() ||
          (route.destination.kind == PrinterTransportKind.tcp &&
              route.destination.host == ip &&
              route.destination.port == 9100),
    )) {
      throw ArgumentError('A printer route already uses this name or endpoint');
    }
    if (rows.any(
      (row) =>
          (row['name'] as String).trim().toLowerCase() == name.toLowerCase(),
    )) {
      throw ArgumentError('A printer with this name already exists');
    }
    if (rows.any((row) => row['ip'] == ip) ||
        DatabaseService.getKitchenPrinterIp() == ip ||
        DatabaseService.getReceiptPrinterIp() == ip) {
      throw ArgumentError('This printer address is already configured');
    }
    final detached =
        jsonDecode(
              jsonEncode([
                ...rows,
                {
                  'id': const Uuid().v4(),
                  'name': name,
                  'ip': ip,
                  'port': 9100,
                  'routing': 'unassigned',
                  'registeredBy': 'developer',
                  'createdAt': DateTime.now().toUtc().toIso8601String(),
                },
              ]),
            )
            as List;
    await DatabaseService.savePrintersList([
      for (final row in detached) Map<String, dynamic>.from(row as Map),
    ]);
    await DatabaseCore.settingsBox!.flush();
  });
}

class PrinterRouteRevisionConflict extends StateError {
  PrinterRouteRevisionConflict(
    this.id,
    this.expectedRevision,
    this.actualRevision,
  ) : super('Printer route revision changed; reload before saving');
  final String id;
  final int expectedRevision;
  final int? actualRevision;
}
