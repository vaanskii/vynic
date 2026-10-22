import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'printer_capability_profile.dart';

enum StationScope { local, venueShared }

enum StationPlanningFailure {
  invalidCatalog,
  identityMismatch,
  invalidInput,
  unmappedLine,
  stationUnavailable,
  foreignLocalStation,
  invalidPayload,
}

class StationPlanningException implements Exception {
  const StationPlanningException(this.reason);
  final StationPlanningFailure reason;
  @override
  String toString() => 'StationPlanningException(${reason.name})';
}

void _require(bool valid, StationPlanningFailure reason) {
  if (!valid) throw StationPlanningException(reason);
}

bool _uuid(Object? value) =>
    value is String &&
    value != '00000000-0000-0000-0000-000000000000' &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value);
bool _digest(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
bool _label(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.trim() == value &&
    utf8.encode(value).length <= 160 &&
    !RegExp(r'[\x00\r\n\t]').hasMatch(value) &&
    utf8.decode(utf8.encode(value)) == value;

Map<String, dynamic> _map(Object? value, Set<String> fields) {
  _require(
    value is Map<String, dynamic> &&
        value.length == fields.length &&
        value.keys.toSet().containsAll(fields),
    StationPlanningFailure.invalidCatalog,
  );
  return value as Map<String, dynamic>;
}

List<dynamic> _list(Object? value, int min, int max) {
  _require(
    value is List && value.length >= min && value.length <= max,
    StationPlanningFailure.invalidCatalog,
  );
  return value as List<dynamic>;
}

// Go encoding/json escapes these characters even inside otherwise UTF-8 JSON.
// OutputID uses those exact bytes, including for user-supplied effect labels.
String _goJson(Object value) => jsonEncode(value)
    .replaceAll('&', r'\u0026')
    .replaceAll('<', r'\u003c')
    .replaceAll('>', r'\u003e')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029');

String _outputId(String venue, String effect, String station, String kind) {
  final hash = sha256.convert(
    utf8.encode(_goJson([venue, effect, station, kind])),
  );
  final bytes = hash.bytes.take(16).toList();
  bytes[6] = (bytes[6] & 15) | 0x50;
  bytes[8] = (bytes[8] & 63) | 0x80;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class PrintStation {
  const PrintStation._({
    required this.id,
    required this.name,
    required this.scope,
    required this.ownerDeviceId,
    required this.enabled,
    required this.queueDigest,
    required this.profile,
  });
  final String id, name, ownerDeviceId, queueDigest;
  final StationScope scope;
  final bool enabled;
  final PrinterCapabilityProfile profile;
}

class _Rule {
  const _Rule(this.kind, this.matchId, this.orderType, this.stations);
  final String kind, matchId, orderType;
  final List<String> stations;
}

/// Detached service projection, never proof of signed authority. The eventual
/// authenticated local client must obtain it from the current Go inventory and
/// retain the identity/configuration checks through admission. No Hive, network,
/// credentials, printer addresses or service startup are accessed here.
class StationRoutingCatalog {
  StationRoutingCatalog._(
    this.venueId,
    this.sourceDeviceId,
    this.revision,
    this.catalogDigest,
    this.stations,
    this._rules,
  );
  final String venueId, sourceDeviceId, catalogDigest;
  final int revision;
  final Map<String, PrintStation> stations;
  final List<_Rule> _rules;

  factory StationRoutingCatalog.decode({
    required List<int> raw,
    required String expectedDigest,
    required String venueId,
    required String sourceDeviceId,
  }) {
    const invalid = StationPlanningFailure.invalidCatalog;
    _require(
      raw.isNotEmpty &&
          raw.length <= 1024 * 1024 &&
          raw.every((b) => b >= 0 && b <= 255) &&
          _digest(expectedDigest) &&
          sha256.convert(raw).toString() == expectedDigest,
      invalid,
    );
    try {
      final body = _map(jsonDecode(utf8.decode(raw)), {
        'version',
        'venueId',
        'sourceDeviceId',
        'revision',
        'catalogDigest',
        'stations',
        'rules',
      });
      _require(
        body['version'] is int &&
            body['version'] == 1 &&
            _uuid(body['venueId']) &&
            _uuid(body['sourceDeviceId']) &&
            body['revision'] is int &&
            body['revision'] > 0 &&
            body['revision'] <= 9007199254740991 &&
            _digest(body['catalogDigest']),
        invalid,
      );
      _require(
        body['venueId'] == venueId && body['sourceDeviceId'] == sourceDeviceId,
        StationPlanningFailure.identityMismatch,
      );
      final stations = <String, PrintStation>{};
      final queueDigests = <String, String>{};
      for (final value in _list(body['stations'], 1, 64)) {
        final s = _map(value, {
          'id',
          'name',
          'scope',
          'ownerDeviceId',
          'enabled',
          'queueDigest',
          'profile',
        });
        _require(
          _uuid(s['id']) &&
              _label(s['name']) &&
              s['enabled'] is bool &&
              _digest(s['queueDigest']) &&
              !stations.containsKey(s['id']),
          invalid,
        );
        final scope = switch (s['scope']) {
          'LOCAL' => StationScope.local,
          'VENUE_SHARED' => StationScope.venueShared,
          _ => throw const StationPlanningException(invalid),
        };
        _require(
          scope == StationScope.local
              ? _uuid(s['ownerDeviceId'])
              : s['ownerDeviceId'] == '',
          invalid,
        );
        final queueKey = '${s['scope']}/${s['ownerDeviceId']}';
        _require(
          !queueDigests.containsKey(queueKey) ||
              queueDigests[queueKey] == s['queueDigest'],
          invalid,
        );
        queueDigests[queueKey] = s['queueDigest'];
        final profile = PrinterCapabilityProfile.decode(s['profile']);
        _require(profile.hasImplementedRenderer, invalid);
        stations[s['id']] = PrintStation._(
          id: s['id'],
          name: s['name'],
          scope: scope,
          ownerDeviceId: s['ownerDeviceId'],
          enabled: s['enabled'],
          queueDigest: s['queueDigest'],
          profile: profile,
        );
      }
      final rules = <_Rule>[];
      final keys = <String>{};
      for (final value in _list(body['rules'], 0, 2048)) {
        _require(value is Map<String, dynamic>, invalid);
        final r = _map(value, {
          'kind',
          'matchId',
          'stations',
          if ((value as Map<String, dynamic>).containsKey('orderType'))
            'orderType',
        });
        final kind = r['kind'],
            match = r['matchId'],
            order = r['orderType'] ?? '';
        _require(
          ['item', 'subcategory', 'category', 'default'].contains(kind) &&
              (kind == 'default' ? match == '' : _label(match)) &&
              (order == '' || _label(order)) &&
              (!r.containsKey('orderType') || r['orderType'] is String) &&
              keys.add(jsonEncode([kind, match, order])),
          invalid,
        );
        final targets = _list(r['stations'], 1, 64);
        _require(
          targets.every(stations.containsKey) &&
              targets.toSet().length == targets.length,
          invalid,
        );
        rules.add(
          _Rule(kind, match, order, List<String>.unmodifiable(targets)),
        );
      }
      return StationRoutingCatalog._(
        venueId,
        sourceDeviceId,
        body['revision'],
        body['catalogDigest'],
        Map.unmodifiable(stations),
        List.unmodifiable(rules),
      );
    } on FormatException {
      throw const StationPlanningException(invalid);
    }
  }

  StationPrintPlan plan({
    required String effectId,
    required String orderType,
    required String outputKind,
    required String businessRef,
    required int createdAt,
    required List<StationPrintLine> lines,
  }) {
    _require(
      _label(effectId) &&
          _label(orderType) &&
          _label(outputKind) &&
          _label(businessRef) &&
          createdAt > 0 &&
          createdAt <= 9007199254740991 &&
          lines.isNotEmpty &&
          lines.length <= 1000 &&
          lines.map((line) => line.id).toSet().length == lines.length,
      StationPlanningFailure.invalidInput,
    );
    final grouped = <String, List<StationPrintLine>>{};
    for (final line in lines) {
      var targets = line.stationIds;
      if (targets.isEmpty) {
        for (final match in [
          ('item', line.itemId),
          ('subcategory', line.subcategoryId),
          ('category', line.categoryId),
          ('default', ''),
        ]) {
          for (final order in [orderType, '']) {
            for (final rule in _rules) {
              if (rule.kind == match.$1 &&
                  rule.matchId == match.$2 &&
                  rule.orderType == order) {
                targets = rule.stations;
                break;
              }
            }
            if (targets.isNotEmpty) break;
          }
          if (targets.isNotEmpty) break;
        }
      }
      _require(targets.isNotEmpty, StationPlanningFailure.unmappedLine);
      for (final id in targets) {
        final station = stations[id];
        _require(
          station != null && station.enabled,
          StationPlanningFailure.stationUnavailable,
        );
        _require(
          station!.scope != StationScope.local ||
              station.ownerDeviceId == sourceDeviceId,
          StationPlanningFailure.foreignLocalStation,
        );
        (grouped[id] ??= []).add(line);
      }
    }
    final ids = grouped.keys.toList()..sort();
    return StationPrintPlan._(
      venueId,
      sourceDeviceId,
      effectId,
      outputKind,
      businessRef,
      createdAt,
      [
        for (final id in ids)
          PlannedStationTicket._(
            _outputId(venueId, effectId, id, outputKind),
            stations[id]!,
            grouped[id]!,
          ),
      ],
    );
  }
}

class StationPrintLine {
  StationPrintLine({
    required this.id,
    this.itemId = '',
    this.subcategoryId = '',
    this.categoryId = '',
    Iterable<String> stationIds = const [],
  }) : stationIds = List.unmodifiable(stationIds) {
    _require(
      _label(id) &&
          [
            itemId,
            subcategoryId,
            categoryId,
          ].every((v) => v.isEmpty || _label(v)) &&
          this.stationIds.length <= 64 &&
          this.stationIds.every(_uuid) &&
          this.stationIds.toSet().length == this.stationIds.length,
      StationPlanningFailure.invalidInput,
    );
  }
  final String id, itemId, subcategoryId, categoryId;
  final List<String> stationIds;
}

class PlannedStationTicket {
  PlannedStationTicket._(this.jobId, this.station, List<StationPrintLine> lines)
    : lines = List.unmodifiable(lines);
  final String jobId;
  final PrintStation station;
  final List<StationPrintLine> lines;
}

class StationPrintPlan {
  StationPrintPlan._(
    this.venueId,
    this.sourceDeviceId,
    this.effectId,
    this.outputKind,
    this.businessRef,
    this.createdAt,
    List<PlannedStationTicket> tickets,
  ) : tickets = List.unmodifiable(tickets);
  final String venueId, sourceDeviceId, effectId, outputKind, businessRef;
  final int createdAt;
  final List<PlannedStationTicket> tickets;
  Future<List<FrozenStationJob>>? _frozen;

  /// Render once per plan, with all-or-error output and immutable byte copies.
  /// The future admission adapter must durably retain the complete result before
  /// sending any job. This in-memory plan is not a recovery journal or receipt.
  Future<List<FrozenStationJob>> freeze({
    required Future<List<int>> Function(PlannedStationTicket) render,
  }) => _frozen ??= _render(render);

  Future<List<FrozenStationJob>> _render(
    Future<List<int>> Function(PlannedStationTicket) render,
  ) async {
    final jobs = <FrozenStationJob>[];
    for (final ticket in tickets) {
      final payload = List<int>.unmodifiable(await render(ticket));
      _require(
        payload.isNotEmpty &&
            payload.length <= 8 * 1024 * 1024 + 1024 &&
            payload.every((b) => b >= 0 && b <= 255),
        StationPlanningFailure.invalidPayload,
      );
      jobs.add(
        FrozenStationJob._(ticket, {
          'version': 1,
          'id': ticket.jobId,
          'venueId': venueId,
          'stationId': ticket.station.id,
          'sourceDeviceId': sourceDeviceId,
          'effectId': effectId,
          'outputKind': outputKind,
          'businessRef': businessRef,
          'configDigest': ticket.station.queueDigest,
          'createdAt': createdAt,
          'payload': base64Encode(payload),
          'payloadDigest': sha256.convert(payload).toString(),
        }),
      );
    }
    return List.unmodifiable(jobs);
  }
}

/// Exact printstation.Job JSON. No printer endpoint or physical controller is
/// selected, and a frozen job is neither an admission ACK nor proof of paper.
class FrozenStationJob {
  FrozenStationJob._(this.ticket, Map<String, Object> body)
    : bytes = List.unmodifiable(utf8.encode(_goJson(body)));
  final PlannedStationTicket ticket;
  final List<int> bytes;
  String get digest => sha256.convert(bytes).toString();
}
