import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'pos_command_delivery.dart';

class ManagerOperationResult {
  const ManagerOperationResult(
    this.delivery, {
    this.kind = '',
    this.requestId = '',
    this.commandId,
    this.code,
    this.reference,
  });
  final PosCommandDelivery delivery;
  final String kind, requestId;
  final String? commandId, code, reference;
  bool get isDone => delivery == PosCommandDelivery.succeeded;
  bool get needsCheck =>
      delivery.isPending ||
      delivery == PosCommandDelivery.unknown ||
      delivery == PosCommandDelivery.failed &&
          [
            'primary_replaced_outcome_unknown',
            'lease_expired_attempts_exhausted',
            'manager_operation_outcome_unknown',
          ].contains(code);
  String get message => switch (delivery) {
    PosCommandDelivery.succeeded => 'POS-მა შეასრულა მოთხოვნა',
    PosCommandDelivery.queued => 'მოთხოვნა რიგშია — POS-ს ჯერ არ შეუსრულებია',
    PosCommandDelivery.claimed => 'POS ასრულებს მოთხოვნას — დაელოდეთ შედეგს',
    PosCommandDelivery.unavailable => 'POS მიუწვდომელია — მოთხოვნა არ ჩაწერილა',
    PosCommandDelivery.failed =>
      needsCheck
          ? 'შედეგი გაურკვეველია — გადაამოწმეთ POS-ზე; მოთხოვნა შენარჩუნებულია'
          : code == 'session_changed'
          ? 'სესია შეიცვალა — გახსენით გვერდი თავიდან'
          : 'POS-ის მოთხოვნა უარყოფილია — მონახაზი შენარჩუნებულია',
    _ =>
      'შედეგი უცნობია — გადაამოწმეთ იგივე მოთხოვნა; დროის გასვლა დასრულებას არ ნიშნავს',
  };
  Map<String, dynamic> toMap() => {
    'delivery': delivery.name,
    'kind': kind,
    'requestId': requestId,
    'commandId': commandId,
    'code': code,
    'reference': reference,
  };
  factory ManagerOperationResult.fromMap(Map value) => ManagerOperationResult(
    PosCommandDelivery.values.firstWhere(
      (v) => v.name == value['delivery'],
      orElse: () => PosCommandDelivery.unknown,
    ),
    kind: value['kind'] as String? ?? '',
    requestId: value['requestId'] as String? ?? '',
    commandId: value['commandId'] as String?,
    code: value['code'] as String?,
    reference: value['reference'] as String?,
  );
  static ManagerOperationResult parse(
    http.Response response,
    Map request, {
    bool statusOnly = false,
  }) {
    final old = ManagerOperationResult.fromMap(request['result']);
    ManagerOperationResult unknown(String code) => ManagerOperationResult(
      PosCommandDelivery.unknown,
      kind: request['kind'],
      requestId: request['requestId'],
      commandId: old.commandId,
      reference: old.reference,
      code: code,
    );
    Object? raw;
    try {
      raw = jsonDecode(response.body);
    } on FormatException {
      return unknown('invalid_response');
    }
    if (raw is! Map) return unknown('invalid_response');
    final code = raw['message'] is String
        ? raw['message'] as String
        : 'request_rejected';
    if (response.statusCode != 202) {
      if (!statusOnly &&
          (request['attempts'] as int? ?? 0) <= 1 &&
          old.commandId == null &&
          [400, 403, 404, 409].contains(response.statusCode) &&
          code != 'request_conflict') {
        final unavailable =
            response.statusCode == 404 && code.startsWith('Cannot POST ');
        return ManagerOperationResult(
          unavailable
              ? PosCommandDelivery.unavailable
              : PosCommandDelivery.failed,
          kind: request['kind'],
          requestId: request['requestId'],
          code: unavailable ? 'cloud_upgrade_required' : code,
        );
      }
      return unknown('status_unconfirmed');
    }
    final d = raw['posDelivery'];
    final delivery = PosCommandDelivery.fromResponse(raw);
    if (raw['requestId'] != request['requestId'] ||
        raw['kind'] != request['kind'] ||
        d is! Map ||
        d['transport'] != 'edge' ||
        delivery == PosCommandDelivery.unknown ||
        delivery == PosCommandDelivery.deliveredLegacy)
      return unknown('invalid_response');
    final id = d['commandId'];
    if (delivery != PosCommandDelivery.unavailable &&
        (id is! String ||
            id.isEmpty ||
            old.commandId != null && id != old.commandId))
      return unknown('invalid_command');
    if (delivery == PosCommandDelivery.succeeded && raw['success'] != true ||
        delivery == PosCommandDelivery.unavailable &&
            (raw['accepted'] != false || old.commandId != null))
      return unknown('invalid_result');
    return ManagerOperationResult(
      delivery,
      kind: request['kind'],
      requestId: request['requestId'],
      commandId: id as String?,
      code: d['code'] as String?,
      reference: (raw['posOrderId'] ?? raw['id'])?.toString(),
    );
  }
}

typedef OperationExchange =
    Future<http.Response> Function(
      Map<String, dynamic> request,
      bool statusOnly,
    );

/// Frozen draft/UUID and terminal result flush before HTTP or success feedback.
abstract final class ManagerOperationRequests {
  static const boxName = 'manager_operations_v1';
  static Box? _box;
  static final revision = ValueNotifier<int>(0);
  static final _unflushed = <String, Map<String, dynamic>>{};
  static final _inflight = <String, Future<ManagerOperationResult>>{};
  static Future<void> init() async {
    if (_box?.isOpen != true) {
      _unflushed.clear();
      _box = await Hive.openBox(boxName);
    }
  }

  @visibleForTesting
  static void wrapBoxForTest(Box Function(Box) wrap) {
    _box = wrap(_box!);
  }

  static Object? _canonical(Object? value) => value is Map
      ? {
          for (final k
              in (value.keys.map((k) => k.toString()).toList()..sort()))
            k: _canonical(value[k]),
        }
      : value is List
      ? value.map(_canonical).toList()
      : value;
  static String key(String scope, String slot) =>
      sha256.convert(utf8.encode(jsonEncode([scope, slot]))).toString();
  static Map<String, dynamic>? read(String scope, String slot) {
    final k = key(scope, slot);
    final value = _unflushed[k] ?? (_box?.isOpen == true ? _box!.get(k) : null);
    if (value == null) return null;
    if (value is! Map ||
        value['scope'] != scope ||
        value['slot'] != slot ||
        value['body'] is! Map ||
        value['result'] is! Map ||
        value['requestId'] is! String ||
        value['kind'] is! String)
      throw const FormatException('Corrupt Manager operation journal');
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  static List<Map<String, dynamic>> all(String scope) {
    if (_box?.isOpen != true) return [];
    final slots = <String>{};
    for (final value in [..._box!.values, ..._unflushed.values]) {
      if (value is! Map ||
          value['scope'] is! String ||
          value['slot'] is! String)
        throw const FormatException('Corrupt Manager operation journal');
      if (value['scope'] == scope && value['slot'] is String)
        slots.add(value['slot']);
    }
    return [
      for (final slot in slots) read(scope, slot)!,
    ]..sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
  }

  static Future<void> dismiss(String scope, String slot) async {
    await init();
    final v = read(scope, slot);
    if (_inflight.containsKey(key(scope, slot)) ||
        v != null && ManagerOperationResult.fromMap(v['result']).needsCheck)
      throw StateError('Resolve the retained POS request first');
    final k = key(scope, slot);
    // Keep the original entry visible until both delete and flush succeed.
    if (v != null) _unflushed[k] = v;
    await _box!.delete(k);
    await _box!.flush();
    _unflushed.remove(k);
    revision.value++;
  }

  static Future<ManagerOperationResult> submit({
    required String scope,
    required String slot,
    required String kind,
    required Map<String, dynamic> body,
    required bool Function() currentSession,
    required OperationExchange exchange,
    bool refresh = false,
    bool newRequest = false,
  }) {
    final k = key(scope, slot);
    final existing = _inflight[k];
    if (existing != null) return existing;
    final future = _submit(
      scope,
      slot,
      kind,
      body,
      currentSession,
      exchange,
      refresh,
      newRequest,
    );
    _inflight[k] = future;
    future.then(
      (_) {
        _inflight.remove(k);
      },
      onError: (Object _, StackTrace __) {
        _inflight.remove(k);
      },
    );
    return future;
  }

  static Future<ManagerOperationResult> _submit(
    String scope,
    String slot,
    String kind,
    Map<String, dynamic> body,
    bool Function() currentSession,
    OperationExchange exchange,
    bool refresh,
    bool newRequest,
  ) async {
    await init();
    const changed = ManagerOperationResult(
      PosCommandDelivery.failed,
      code: 'session_changed',
    );
    if (!currentSession()) return changed;
    final k = key(scope, slot);
    var v = read(scope, slot);
    if (v != null) {
      final old = ManagerOperationResult.fromMap(v['result']);
      if (old.isDone &&
          !refresh &&
          (newRequest ||
              v['kind'] != kind ||
              jsonEncode(_canonical(v['body'])) !=
                  jsonEncode(_canonical(body))))
        v = null;
    }
    if (v == null) {
      if (refresh) throw StateError('No retained POS request');
      final id = const Uuid().v4();
      v = {
        'version': 1,
        'scope': scope,
        'slot': slot,
        'kind': kind,
        'requestId': id,
        'body': jsonDecode(jsonEncode(body)),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
        'result': ManagerOperationResult(
          PosCommandDelivery.unknown,
          kind: kind,
          requestId: id,
        ).toMap(),
      };
      // Shadow put failures as well: Hive can publish memory before IO returns.
      _unflushed[k] = v;
    }
    var entry = v;
    // Re-persist on every retry: a prior put may have failed before IO.
    _unflushed[k] = entry;
    await _box!.put(k, entry);
    await _box!.flush();
    _unflushed.remove(k);
    revision.value++;
    if (!currentSession()) return changed;
    final previous = ManagerOperationResult.fromMap(entry['result']);
    if (previous.isDone ||
        previous.delivery == PosCommandDelivery.failed &&
            (!previous.needsCheck || !refresh || previous.commandId == null))
      return previous;
    ManagerOperationResult result;
    try {
      final statusOnly = previous.commandId != null;
      if (!statusOnly) {
        entry = {...entry, 'attempts': (entry['attempts'] as int? ?? 0) + 1};
        _unflushed[k] = entry;
        await _box!.put(k, entry);
        await _box!.flush();
        _unflushed.remove(k);
      }
      if (!currentSession()) return changed;
      final response = await exchange(
        Map<String, dynamic>.from(entry),
        statusOnly,
      );
      result = ManagerOperationResult.parse(
        response,
        entry,
        statusOnly: statusOnly,
      );
    } catch (_) {
      result = ManagerOperationResult(
        PosCommandDelivery.unknown,
        kind: entry['kind'],
        requestId: entry['requestId'],
        commandId: previous.commandId,
        reference: previous.reference,
        code: 'transport_failure',
      );
    }
    final shadow = ManagerOperationResult(
      PosCommandDelivery.unknown,
      kind: entry['kind'],
      requestId: entry['requestId'],
      commandId: result.commandId ?? previous.commandId,
      reference: result.reference ?? previous.reference,
      code: 'local_request_error',
    );
    _unflushed[k] = {...entry, 'result': shadow.toMap()};
    revision.value++;
    await _box!.put(k, {...entry, 'result': result.toMap()});
    await _box!.flush();
    _unflushed.remove(k);
    revision.value++;
    if (!currentSession()) return changed;
    return result;
  }
}
