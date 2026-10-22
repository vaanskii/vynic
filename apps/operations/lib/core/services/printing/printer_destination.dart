import 'dart:convert';
import 'printer_capability_profile.dart';

enum PrinterTransportKind { tcp, windowsSpooler }

/// Immutable physical destination. Queue names alone are insufficient: driver,
/// port and the owning enrolled Device are frozen with every spooler attempt.
class PrinterDestination {
  PrinterDestination._(this._body);
  final Map<String, dynamic> _body;

  PrinterTransportKind get kind =>
      PrinterTransportKind.values.byName(_body['kind'] as String);
  String? get host => _body['host'] as String?;
  int? get port => _body['port'] as int?;
  String? get ownerDeviceId => _body['ownerDeviceId'] as String?;
  String? get queueName => _body['queueName'] as String?;
  String? get driverName => _body['driverName'] as String?;
  String? get portName => _body['portName'] as String?;
  String get identity => jsonEncode(_body);
  String get display => kind == PrinterTransportKind.tcp
      ? '$host:$port'
      : '$queueName · $portName';

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_body);

  factory PrinterDestination.tcp({required String host, required int port}) =>
      PrinterDestination.decode({'kind': 'tcp', 'host': host, 'port': port});

  factory PrinterDestination.windowsSpooler({
    required String ownerDeviceId,
    required String queueName,
    required String driverName,
    required String portName,
  }) => PrinterDestination.decode({
    'kind': 'windowsSpooler',
    'ownerDeviceId': ownerDeviceId,
    'queueName': queueName,
    'driverName': driverName,
    'portName': portName,
  });

  factory PrinterDestination.decode(dynamic raw) {
    if (raw is! Map) throw const FormatException('Invalid printer destination');
    final body = Map<String, dynamic>.from(raw);
    bool text(dynamic value, int max) =>
        value is String &&
        value.isNotEmpty &&
        value.trim() == value &&
        value.length <= max &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
    if (body['kind'] == 'tcp' &&
        body.length == 3 &&
        text(body['host'], 255) &&
        body['port'] is int &&
        body['port'] >= 1 &&
        body['port'] <= 65535) {
      return PrinterDestination._(
        Map.unmodifiable({
          'kind': 'tcp',
          'host': body['host'],
          'port': body['port'],
        }),
      );
    }
    if (body['kind'] == 'windowsSpooler' &&
        body.length == 5 &&
        text(body['ownerDeviceId'], 120) &&
        text(body['queueName'], 255) &&
        text(body['driverName'], 1024) &&
        text(body['portName'], 1024)) {
      return PrinterDestination._(
        Map.unmodifiable({
          'kind': 'windowsSpooler',
          'ownerDeviceId': body['ownerDeviceId'],
          'queueName': body['queueName'],
          'driverName': body['driverName'],
          'portName': body['portName'],
        }),
      );
    }
    throw const FormatException('Invalid printer destination');
  }
}

enum PrinterRole { kitchen, bar, receipt, additional }

/// A configuration revision describes new jobs only. Accepted jobs retain the
/// captured destination/revision even when a developer changes this record.
class PrinterRoute {
  PrinterRoute._(
    this.id,
    this.name,
    this.role,
    this.revision,
    this.destination,
    this.capabilityProfile,
  );
  final String id;
  final String name;
  final PrinterRole role;
  final int revision;
  final PrinterDestination destination;
  final PrinterCapabilityProfile capabilityProfile;

  factory PrinterRoute.decode(dynamic raw) {
    if (raw is! Map ||
        ![6, 7].contains(raw.length) ||
        raw['protocol'] != 1 ||
        raw.keys.toSet().difference({
          'protocol',
          'id',
          'name',
          'role',
          'revision',
          'destination',
          'capabilityProfile',
        }).isNotEmpty) {
      throw const FormatException('Invalid printer route');
    }
    final id = raw['id'], name = raw['name'], revision = raw['revision'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        revision is! int ||
        revision < 1 ||
        revision > 0x7fffffff ||
        !PrinterRole.values.any((value) => value.name == raw['role'])) {
      throw const FormatException('Invalid printer route');
    }
    return PrinterRoute._(
      id,
      name,
      PrinterRole.values.byName(raw['role']),
      revision,
      PrinterDestination.decode(raw['destination']),
      raw.containsKey('capabilityProfile')
          ? PrinterCapabilityProfile.decode(raw['capabilityProfile'])
          : PrinterCapabilityProfile.genericEscposRaster(),
    );
  }

  Map<String, dynamic> toMap() => {
    'protocol': 1,
    'id': id,
    'name': name,
    'role': role.name,
    'revision': revision,
    'destination': destination.toMap(),
    'capabilityProfile': capabilityProfile.toMap(),
  };
}
