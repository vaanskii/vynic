import 'dart:convert';

import 'printer_capability_profile.dart';
import 'printer_destination.dart';

enum CloudPrinterRuntimePhase { prepared, active }

enum CloudPrinterDispatchHoldKind {
  prepared,
  notConfigured,
  ambiguousSelection,
  disabled,
  rendererUnavailable,
}

/// A valid authoritative configuration can still intentionally prohibit a
/// dispatch. Callers must surface this hold rather than try local fallbacks.
class CloudPrinterDispatchHold extends StateError {
  CloudPrinterDispatchHold({
    required this.kind,
    required this.role,
    required this.configRevision,
    required String message,
    this.routeId,
  }) : super(message);

  final CloudPrinterDispatchHoldKind kind;
  final PrinterRole role;
  final int configRevision;
  final String? routeId;
}

/// Flat wire rows add enabled to the canonical immutable PrinterRoute shape.
class CloudPrinterRoute {
  CloudPrinterRoute._(this.route, this.enabled);

  final PrinterRoute route;
  final bool enabled;

  Map<String, dynamic> toMap() => {...route.toMap(), 'enabled': enabled};
}

/// Version 2 is server-owned Device/Venue configuration, independent of a local
/// developer grant. The supplied binding must come from enrolled identity,
/// never from this untrusted body. The caller rechecks that binding after HTTP
/// and before committing a cache; this pure reader has no persistence effects.
class CloudPrinterRuntime {
  CloudPrinterRuntime._({
    required this.deviceId,
    required this.venueId,
    required this.revision,
    required this.phase,
    required this.routes,
  });

  static const readerVersion = 2;
  static const maxRoutes = 64;
  static const maxEncodedBytes = 256 * 1024;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final _routeId = RegExp(r'^[a-zA-Z0-9_-]{1,120}$');
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');

  final String deviceId;
  final String venueId;
  final int revision;
  final CloudPrinterRuntimePhase phase;
  final List<CloudPrinterRoute> routes;

  static Map _object(
    dynamic raw,
    Set<String> required, {
    Set<String> optional = const {},
    required String label,
  }) {
    if (raw is! Map ||
        raw.keys.any((key) => key is! String) ||
        !raw.keys.toSet().containsAll(required) ||
        raw.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
      throw FormatException('Invalid Cloud printer $label fields');
    }
    return raw;
  }

  static bool _text(dynamic value, int max) =>
      value is String &&
      value.isNotEmpty &&
      value.trim() == value &&
      value.length <= max &&
      !_controls.hasMatch(value);

  static void _legacyDisabled(dynamic raw) {
    final row = _object(raw, {'enabled', 'host', 'port'}, label: 'legacy stub');
    if (row['enabled'] != false ||
        row['host'] != '' ||
        row['port'] is! int ||
        row['port'] != 9100) {
      throw const FormatException(
        'Cloud v2 requires disabled legacy printer stubs',
      );
    }
  }

  static PrinterCapabilityProfile _profile(dynamic raw) {
    final body = _object(
      raw,
      {
        'protocol',
        'paperWidthMm',
        'rasterWidthDots',
        'language',
        'cutter',
        'encoding',
      },
      optional: {'beep'},
      label: 'capability profile',
    );
    final profile = PrinterCapabilityProfile.decode(body);
    // Optional sound never prevents the primary printing profile from loading.
    // The shared decoder discards malformed/unknown optional command input.
    final beep = profile.beep;
    return PrinterCapabilityProfile(
      paperWidthMm: profile.paperWidthMm,
      rasterWidthDots: profile.rasterWidthDots,
      language: profile.language,
      cutter: profile.cutter,
      encoding: profile.encoding,
      beep: PrinterBeepSettings(
        capability: beep.capability,
        enabled:
            beep.enabled &&
            beep.capability == PrinterBeepCapability.epsonEscA97Pattern &&
            profile.language == PrinterCommandLanguage.escposRaster,
      ),
    );
  }

  static CloudPrinterRoute _route(dynamic raw, String deviceId) {
    final body = _object(raw, {
      'protocol',
      'id',
      'name',
      'role',
      'revision',
      'destination',
      'capabilityProfile',
      'enabled',
    }, label: 'route');
    if (body['protocol'] is! int ||
        body['protocol'] != 1 ||
        body['enabled'] is! bool ||
        !_text(body['name'], 80)) {
      throw const FormatException('Invalid Cloud printer route');
    }
    final rawDestination = body['destination'];
    if (rawDestination is! Map) {
      throw const FormatException('Invalid Cloud printer destination');
    }
    if (rawDestination['kind'] == 'tcp') {
      _object(rawDestination, {
        'kind',
        'host',
        'port',
      }, label: 'TCP destination');
    } else if (rawDestination['kind'] == 'windowsSpooler') {
      _object(rawDestination, {
        'kind',
        'ownerDeviceId',
        'queueName',
        'driverName',
        'portName',
      }, label: 'Windows destination');
      if (rawDestination['ownerDeviceId'] != deviceId) {
        throw const FormatException(
          'Cloud Windows printer belongs to a different Device',
        );
      }
    } else {
      throw const FormatException('Unknown Cloud printer transport');
    }
    final route = PrinterRoute.decode({
      'protocol': body['protocol'],
      'id': body['id'],
      'name': body['name'],
      'role': body['role'],
      'revision': body['revision'],
      'destination': PrinterDestination.decode(rawDestination).toMap(),
      'capabilityProfile': _profile(body['capabilityProfile']).toMap(),
    });
    return CloudPrinterRoute._(route, body['enabled'] as bool);
  }

  static String _endpoint(PrinterDestination destination) =>
      destination.kind == PrinterTransportKind.tcp
      ? jsonEncode(['tcp', destination.host!.toLowerCase(), destination.port])
      : jsonEncode([
          'windowsSpooler',
          destination.ownerDeviceId,
          destination.queueName!.toLowerCase(),
        ]);

  factory CloudPrinterRuntime.decode(
    dynamic raw, {
    required String boundDeviceId,
    required String boundVenueId,
  }) {
    final body = _object(raw, {
      'version',
      'deviceId',
      'venueId',
      'revision',
      'phase',
      'minimumReaderVersion',
      'printers',
      'routes',
    }, label: 'runtime');
    if (!_uuid.hasMatch(boundDeviceId) ||
        !_uuid.hasMatch(boundVenueId) ||
        body['version'] is! int ||
        body['version'] != 2 ||
        body['minimumReaderVersion'] is! int ||
        body['minimumReaderVersion'] != readerVersion ||
        body['deviceId'] != boundDeviceId ||
        body['venueId'] != boundVenueId ||
        body['revision'] is! int ||
        body['revision'] < 1 ||
        body['revision'] > 0x7fffffff ||
        !['PREPARED', 'ACTIVE'].contains(body['phase'])) {
      throw const FormatException('Invalid or foreign Cloud printer runtime');
    }
    final printers = _object(body['printers'], {
      'kitchen',
      'receipt',
    }, label: 'legacy printers');
    _legacyDisabled(printers['kitchen']);
    _legacyDisabled(printers['receipt']);
    final rawRoutes = body['routes'];
    if (rawRoutes is! List || rawRoutes.length > maxRoutes) {
      throw const FormatException('Invalid Cloud printer route count');
    }
    final routes = <CloudPrinterRoute>[];
    final ids = <String>{};
    final names = <String>{};
    final endpoints = <String>{};
    final roles = <PrinterRole>{};
    for (final row in rawRoutes) {
      final entry = _route(row, boundDeviceId);
      final route = entry.route;
      if (!ids.add(route.id) ||
          !names.add(route.name.toLowerCase()) ||
          !endpoints.add(_endpoint(route.destination)) ||
          (route.role != PrinterRole.additional && !roles.add(route.role))) {
        throw const FormatException(
          'Duplicate Cloud printer route identity, endpoint or role',
        );
      }
      routes.add(entry);
    }
    final runtime = CloudPrinterRuntime._(
      deviceId: boundDeviceId,
      venueId: boundVenueId,
      revision: body['revision'] as int,
      phase: body['phase'] == 'PREPARED'
          ? CloudPrinterRuntimePhase.prepared
          : CloudPrinterRuntimePhase.active,
      routes: List<CloudPrinterRoute>.unmodifiable(routes),
    );
    if (utf8.encode(jsonEncode(runtime.toMap())).length > maxEncodedBytes) {
      throw const FormatException('Cloud printer runtime exceeds 256 KiB');
    }
    return runtime;
  }

  /// Every v2 role is Cloud authoritative, including disabled or missing roles.
  bool ownsRole(PrinterRole role) => true;

  PrinterRoute resolveForDispatch({
    required PrinterRole role,
    String? routeId,
  }) {
    if (routeId != null && !_routeId.hasMatch(routeId)) {
      throw ArgumentError('Provide a valid Cloud printer route id');
    }
    Never hold(CloudPrinterDispatchHoldKind kind, String message) =>
        throw CloudPrinterDispatchHold(
          kind: kind,
          role: role,
          configRevision: revision,
          routeId: routeId,
          message: message,
        );
    if (phase == CloudPrinterRuntimePhase.prepared) {
      hold(
        CloudPrinterDispatchHoldKind.prepared,
        'Cloud printer configuration is PREPARED; controlled activation is required',
      );
    }
    final selected = routes
        .where(
          (entry) =>
              entry.route.role == role &&
              (routeId == null || entry.route.id == routeId),
        )
        .toList();
    if (selected.isEmpty) {
      hold(
        CloudPrinterDispatchHoldKind.notConfigured,
        'Cloud has no configured ${role.name} route for this selection; local fallback is prohibited',
      );
    }
    if (selected.length != 1) {
      hold(
        CloudPrinterDispatchHoldKind.ambiguousSelection,
        'Select one explicit Cloud ${role.name} route id before dispatch',
      );
    }
    final entry = selected.single;
    if (!entry.enabled) {
      hold(
        CloudPrinterDispatchHoldKind.disabled,
        'Cloud ${role.name} printer route is disabled; local fallback is prohibited',
      );
    }
    if (!entry.route.capabilityProfile.hasImplementedRenderer) {
      hold(
        CloudPrinterDispatchHoldKind.rendererUnavailable,
        'Cloud printer route requires Windows driver-rendered output; renderer is not implemented',
      );
    }
    return entry.route;
  }

  /// Canonical detached serialization keeps mandatory old-reader stop stubs.
  Map<String, dynamic> toMap() => {
    'version': 2,
    'deviceId': deviceId,
    'venueId': venueId,
    'revision': revision,
    'phase': phase == CloudPrinterRuntimePhase.prepared ? 'PREPARED' : 'ACTIVE',
    'minimumReaderVersion': readerVersion,
    'printers': {
      'kitchen': {'enabled': false, 'host': '', 'port': 9100},
      'receipt': {'enabled': false, 'host': '', 'port': 9100},
    },
    'routes': [for (final entry in routes) entry.toMap()],
  };
}
