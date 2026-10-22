import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'printer_destination.dart';
import 'printer_capability_profile.dart';

enum PrintQueueTarget { kitchen, receipt, bar, additional }

/// `sent` means the transport accepted the bytes, never that paper emerged. Only a
/// deliberate operator observation can move an attempt to `confirmed`.
enum PrintJobState {
  queued,
  reprint,
  sending,
  sent,
  failed,
  uncertain,
  confirmed,
}

enum PrintTransmissionState { sent, notSent, uncertain }

class PrintTransmissionResult {
  const PrintTransmissionResult(this.state, this.detail);
  final PrintTransmissionState state;
  final String detail;
  bool get sent => state == PrintTransmissionState.sent;
}

class PrintJob {
  PrintJob._(this._body);
  final Map<String, dynamic> _body;
  static const protocol = 1;
  static const routedProtocol = 2;
  static const maxPayloadBytes = 8 * 1024 * 1024;

  String get id => _body['id'] as String;
  int get protocolVersion => _body['protocol'] as int;
  PrintQueueTarget get target =>
      PrintQueueTarget.values.byName(_body['target']);
  PrinterDestination get destination => protocolVersion == protocol
      ? PrinterDestination.tcp(host: _body['host'], port: _body['port'])
      : PrinterDestination.decode(_body['destination']);
  String get host => destination.host ?? destination.queueName!;
  int get port => destination.port ?? 0;
  String? get printerId => _body['printerId'] as String?;
  int? get routeRevision => _body['routeRevision'] as int?;
  PrinterCapabilityProfile get capabilityProfile => protocolVersion == protocol
      ? PrinterCapabilityProfile.genericEscposRaster(cutter: PrinterCutter.full)
      : PrinterCapabilityProfile.decode(_body['capabilityProfile']);
  String get label => _body['label'] as String;
  String? get requiresConfirmedOrderUuid =>
      _body['requiresConfirmedOrderUuid'] as String?;
  String? get copyOf => _body['copyOf'] as String?;
  String? get venueId => _body['venueId'] as String?;
  String get createdAt => _body['createdAt'] as String;
  List<Map<String, dynamic>> get attempts => [
    for (final attempt in _body['attempts'])
      Map<String, dynamic>.from(jsonDecode(jsonEncode(attempt)) as Map),
  ];
  Map<String, dynamic> get latest => attempts.last;
  String get attemptId => latest['id'] as String;
  PrintJobState get state => PrintJobState.values.byName(latest['state']);
  bool get ready =>
      state == PrintJobState.queued || state == PrintJobState.reprint;
  bool get needsAttention =>
      state == PrintJobState.uncertain || state == PrintJobState.failed;
  String? get detail => latest['detail'] as String?;
  List<Map<String, dynamic>> get audit => [
    for (final event in _body['audit']) Map<String, dynamic>.from(event as Map),
  ];

  Map<String, dynamic> toMap() =>
      jsonDecode(jsonEncode(_body)) as Map<String, dynamic>;

  /// Printed identifiers and copy labels survive any later Order/Menu edits.
  List<int> get transmissionBytes => [
    0x1b,
    0x40,
    ...ascii.encode(
      attempts.length == 1 && copyOf == null
          ? 'JOB $id\n'
          : '*** REPRINT COPY ${attempts.length - (copyOf == null ? 1 : 0)} ***\nJOB $id\nOriginal may already have printed.\n',
    ),
    ...base64Decode(_body['payload'] as String),
  ];

  factory PrintJob.create({
    required String id,
    required PrintQueueTarget target,
    String? host,
    int? port,
    PrinterDestination? destination,
    String? printerId,
    int? routeRevision,
    PrinterCapabilityProfile? capabilityProfile,
    required String label,
    required List<int> bytes,
    String? venueId,
    String? copyOf,
    String? requiresConfirmedOrderUuid,
    String? copyActorId,
    String? copyReason,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return PrintJob.decode({
      'protocol': destination == null ? protocol : routedProtocol,
      'id': id,
      'target': target.name,
      if (destination == null) 'host': host,
      if (destination == null) 'port': port,
      if (destination != null) 'destination': destination.toMap(),
      if (destination != null) 'printerId': printerId,
      if (destination != null) 'routeRevision': routeRevision,
      if (destination != null)
        'capabilityProfile':
            (capabilityProfile ??
                    PrinterCapabilityProfile.genericEscposRaster())
                .toMap(),
      'label': label,
      'venueId': venueId,
      if (copyOf != null) 'copyOf': copyOf,
      if (requiresConfirmedOrderUuid != null)
        'requiresConfirmedOrderUuid': requiresConfirmedOrderUuid,
      'createdAt': now,
      'payload': base64Encode(bytes),
      'payloadSha256': sha256.convert(bytes).toString(),
      'attempts': [
        {'id': id, 'state': 'queued', 'queuedAt': now},
      ],
      'audit': [
        {
          'action': 'queued',
          'at': now,
          'attemptId': id,
          if (copyOf != null) 'copyOf': copyOf,
          if (copyActorId != null) 'actorId': copyActorId,
          if (copyReason != null) 'reason': copyReason,
        },
      ],
    });
  }

  /// Strictly validate before startup dispatch or any backup replacement.
  factory PrintJob.decode(dynamic raw) {
    try {
      final b = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      bool text(dynamic v, int max) =>
          v is String && v.trim().isNotEmpty && v.length <= max;
      void require(bool condition) {
        if (!condition)
          throw const FormatException('Invalid durable print job');
      }

      require(
        b['protocol'] is int &&
            [protocol, routedProtocol].contains(b['protocol']) &&
            text(b['id'], 120),
      );
      require(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(b['id']));
      require(PrintQueueTarget.values.any((v) => v.name == b['target']));
      if (b['protocol'] == protocol) {
        require(['kitchen', 'receipt'].contains(b['target']));
        require(
          !b.containsKey('destination') &&
              !b.containsKey('printerId') &&
              !b.containsKey('routeRevision'),
        );
        require(!b.containsKey('capabilityProfile'));
        require(
          text(b['host'], 255) &&
              b['port'] is int &&
              b['port'] >= 1 &&
              b['port'] <= 65535,
        );
      } else {
        require(text(b['venueId'], 120));
        require(!b.containsKey('host') && !b.containsKey('port'));
        PrinterDestination.decode(b['destination']);
        PrinterCapabilityProfile.decode(b['capabilityProfile']);
        require(
          text(b['printerId'], 120) &&
              RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(b['printerId']),
        );
        require(
          b['routeRevision'] is int &&
              b['routeRevision'] >= 1 &&
              b['routeRevision'] <= 0x7fffffff,
        );
      }
      require(text(b['label'], 300));
      require(b['venueId'] == null || text(b['venueId'], 120));
      require(b['copyOf'] == null || text(b['copyOf'], 300));
      require(
        b['requiresConfirmedOrderUuid'] == null ||
            text(b['requiresConfirmedOrderUuid'], 120),
      );
      DateTime.parse(b['createdAt'] as String);
      final bytes = base64Decode(b['payload'] as String);
      require(bytes.isNotEmpty && bytes.length <= maxPayloadBytes);
      require(b['payloadSha256'] == sha256.convert(bytes).toString());
      require(b['attempts'] is List && (b['attempts'] as List).isNotEmpty);
      final ids = <String>{};
      for (final a in b['attempts']) {
        require(a is Map && text(a['id'], 120));
        require(
          ids.add(a['id']) &&
              PrintJobState.values.any((v) => v.name == a['state']),
        );
        DateTime.parse(a['queuedAt'] as String);
        require(a['detail'] == null || a['detail'] is String);
        if (a.containsKey('beep')) {
          final beep = a['beep'];
          require(b['protocol'] == routedProtocol && beep is Map);
          require(
            beep.keys.toSet().difference({
              'state',
              'reservedAt',
              'settledAt',
              'detail',
            }).isEmpty,
          );
          require(
            [
              'reserved',
              'notSent',
              'submitted',
              'uncertain',
              'failed',
            ].contains(beep['state']),
          );
          DateTime.parse(beep['reservedAt'] as String);
          require(['sent', 'confirmed'].contains(a['state']));
          if (beep['state'] != 'reserved') {
            DateTime.parse(beep['settledAt'] as String);
            require(text(beep['detail'], 4000));
          } else {
            require(
              !beep.containsKey('settledAt') && !beep.containsKey('detail'),
            );
          }
        }
        if (ids.length > 1) {
          require(text(a['actorId'], 120) && text(a['reason'], 500));
          require(a['state'] != 'queued');
        } else {
          require(a['id'] == b['id'] && a['state'] != 'reprint');
        }
      }
      require(b['audit'] is List && (b['audit'] as List).isNotEmpty);
      final states = <String, String>{};
      final actionIds = <String>{};
      String? latestId;
      for (final e in b['audit']) {
        require(
          e is Map && text(e['action'], 40) && ids.contains(e['attemptId']),
        );
        DateTime.parse(e['at'] as String);
        final id = e['attemptId'] as String;
        final action = e['action'] as String;
        final prior = states[id];
        final operator =
            action == 'confirmed' ||
            action == 'reprint' ||
            action == 'queued' && prior != null ||
            e['copyOf'] != null;
        if (operator) {
          require(text(e['actorId'], 120) && text(e['reason'], 500));
          if (e['actionId'] != null)
            require(text(e['actionId'], 120) && actionIds.add(e['actionId']));
        }
        if (prior == null) {
          require(id == (b['attempts'] as List)[states.length]['id']);
          require(states.isEmpty ? action == 'queued' : action == 'reprint');
          if (latestId != null)
            require(
              ['sent', 'uncertain', 'confirmed'].contains(states[latestId]),
            );
          final attempt = (b['attempts'] as List)[states.length];
          if (states.isNotEmpty) {
            require(
              attempt['actorId'] == e['actorId'] &&
                  attempt['reason'] == e['reason'],
            );
            require(actionIds.add(id));
          } else if (b['copyOf'] != null) {
            require(e['copyOf'] == b['copyOf']);
          } else {
            require(e['copyOf'] == null);
          }
          latestId = id;
        } else {
          require(id == latestId);
          final allowed = switch (prior) {
            'queued' || 'reprint' => ['sending', 'uncertain'],
            'sending' => ['sent', 'failed', 'uncertain'],
            'sent' || 'uncertain' => ['confirmed'],
            'failed' => [id == b['id'] ? 'queued' : 'reprint'],
            _ => <String>[],
          };
          require(allowed.contains(action));
          if (action == 'confirmed' || prior == 'failed')
            require(e['actionId'] != null);
        }
        states[id] = action;
      }
      require(states.length == (b['attempts'] as List).length);
      for (final a in b['attempts']) require(states[a['id']] == a['state']);
      return PrintJob._(b);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid durable print job');
    }
  }
}
