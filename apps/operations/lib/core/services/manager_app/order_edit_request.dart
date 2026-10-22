import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'pos_command_delivery.dart';

class OrderEditResult {
  const OrderEditResult(
    this.delivery, {
    this.code,
    this.commandId,
    this.projection,
  });
  final PosCommandDelivery delivery;
  final String? code, commandId;
  final Map<String, dynamic>? projection;
  bool get isDone => delivery == PosCommandDelivery.succeeded;
  bool get needsCheck =>
      delivery.isPending ||
      delivery == PosCommandDelivery.unknown ||
      delivery == PosCommandDelivery.failed &&
          [
            'primary_replaced_outcome_unknown',
            'lease_expired_attempts_exhausted',
          ].contains(code);
  String get message => switch (delivery) {
    PosCommandDelivery.succeeded => 'შეკვეთა შეინახა POS-მა',
    PosCommandDelivery.queued => 'რიგშია — POS-ს შეკვეთა ჯერ არ შეუცვლია',
    PosCommandDelivery.claimed => 'POS ასრულებს ცვლილებას — გადაამოწმეთ შედეგი',
    PosCommandDelivery.unavailable =>
      'POS-ის რედაქტირება მიუწვდომელია — განაახლეთ მონაცემები',
    PosCommandDelivery.failed => switch (code) {
      'primary_replaced_outcome_unknown' ||
      'lease_expired_attempts_exhausted' =>
        'შედეგი გაურკვეველია — გადაამოწმეთ შეკვეთა POS-ზე; მონახაზი შენარჩუნებულია',
      'session_changed' => 'სესია შეიცვალა — გახსენით შეკვეთა თავიდან',
      'stale_order' ||
      'stale_date' ||
      'closed_order' => 'შეკვეთა შეიცვალა ან დაიხურა — განაახლეთ მონაცემები',
      'unsupported_command_type' => 'საჭიროა POS-ის განახლება',
      _ => 'ცვლილება უარყოფილია — მონახაზი შენარჩუნებულია',
    },
    _ => 'შედეგი უცნობია — გადაამოწმეთ იგივე მოთხოვნა',
  };
  Map<String, dynamic> toMap() => {
    'delivery': delivery.name,
    'code': code,
    'commandId': commandId,
    'projection': projection,
  };
  factory OrderEditResult.fromMap(Map value) => OrderEditResult(
    PosCommandDelivery.values.firstWhere(
      (v) => v.name == value['delivery'],
      orElse: () => PosCommandDelivery.unknown,
    ),
    code: value['code'],
    commandId: value['commandId'],
    projection: value['projection'] is Map
        ? Map<String, dynamic>.from(value['projection'])
        : null,
  );
  factory OrderEditResult.fromResponse(http.Response response, int orderId) {
    Object? value;
    try {
      value = jsonDecode(response.body);
    } on FormatException {
      return const OrderEditResult(
        PosCommandDelivery.unknown,
        code: 'invalid_response',
      );
    }
    if (value is! Map)
      return const OrderEditResult(
        PosCommandDelivery.unknown,
        code: 'invalid_response',
      );
    if ([400, 404, 409, 403].contains(response.statusCode))
      return OrderEditResult(
        PosCommandDelivery.failed,
        code: value['message'] is String
            ? value['message']
            : 'request_rejected',
      );
    final delivery = PosCommandDelivery.fromResponse(value),
        d = value['posDelivery'];
    if (response.statusCode != 202 ||
        d is! Map ||
        delivery == PosCommandDelivery.deliveredLegacy ||
        delivery == PosCommandDelivery.unknown ||
        (delivery.isPending || delivery == PosCommandDelivery.succeeded) &&
            (d['commandId'] is! String || (d['commandId'] as String).isEmpty))
      return const OrderEditResult(
        PosCommandDelivery.unknown,
        code: 'invalid_response',
      );
    Map<String, dynamic>? projection;
    if (delivery == PosCommandDelivery.succeeded) {
      try {
        projection = Map<String, dynamic>.from(value['editProjection'] as Map);
        if (OrderEditProjection.read(projection).orderId != orderId)
          throw const FormatException();
      } catch (_) {
        return const OrderEditResult(
          PosCommandDelivery.unknown,
          code: 'invalid_result',
        );
      }
      if (value['success'] != true)
        return const OrderEditResult(
          PosCommandDelivery.unknown,
          code: 'invalid_result',
        );
    }
    return OrderEditResult(
      delivery,
      code: d['code'],
      commandId: d['commandId'],
      projection: projection,
    );
  }
}

/// Frozen draft and identity are flushed before HTTP. No tokens are stored.
abstract final class OrderEditRequests {
  static const boxName = 'manager_order_edits_v1';
  static Box? _box;
  static final _unflushedResults = <String, Map<String, dynamic>>{};
  static final inflight = <String, Future<OrderEditResult>>{};
  static Future<void> init() async {
    if (_box?.isOpen != true) {
      _unflushedResults.clear();
      _box = await Hive.openBox(boxName);
    }
  }

  @visibleForTesting
  static void wrapBoxForTest(Box Function(Box) wrap) {
    _box = wrap(_box!);
  }

  static String key(String scope, int orderId) =>
      sha256.convert(utf8.encode(jsonEncode([scope, orderId]))).toString();
  static Map<String, dynamic>? read(String scope, int id) {
    if (_box?.isOpen != true) return null;
    final k = key(scope, id);
    final raw = _unflushedResults[k] ?? _box!.get(k);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  static Order? draft(String scope, int id) {
    final v = read(scope, id);
    if (v == null || OrderEditResult.fromMap(v['result']).isDone) return null;
    final o = OrderEditProjection.read(
      Map<String, dynamic>.from(v['baseline']),
    );
    final body = v['body'] as Map;
    o.items = [
      for (final i in body['items'])
        OrderItem.fromJson(Map<String, dynamic>.from(i)),
    ];
    o.includeServiceFee = body['includeServiceFee'];
    o.customServiceFeePercentage = (body['customServiceFeePercentage'] as num?)
        ?.toDouble();
    o.recalculateTotal();
    return o;
  }

  static Future<void> discard(String scope, int id) async {
    await init();
    final v = read(scope, id);
    if (v != null && OrderEditResult.fromMap(v['result']).needsCheck)
      throw StateError('Resolve pending edit before discarding');
    await _box!.delete(key(scope, id));
    await _box!.flush();
  }

  static Future<OrderEditResult> submit({
    required String scope,
    required Order order,
    required bool Function() currentSession,
    required Future<http.Response> Function(Map<String, dynamic>) send,
  }) {
    final k = key(scope, order.orderId);
    final existing = inflight[k];
    if (existing != null) return existing;
    final future = _submit(scope, order, currentSession, send);
    inflight[k] = future;
    future.then(
      (_) {
        inflight.remove(k);
      },
      onError: (Object _, StackTrace __) {
        inflight.remove(k);
      },
    );
    return future;
  }

  static Future<OrderEditResult> _submit(
    String scope,
    Order order,
    bool Function() currentSession,
    Future<http.Response> Function(Map<String, dynamic>) send,
  ) async {
    await init();
    if (!currentSession())
      return const OrderEditResult(
        PosCommandDelivery.failed,
        code: 'session_changed',
      );
    var v = read(scope, order.orderId);
    if (v != null && OrderEditResult.fromMap(v['result']).isDone) {
      final body = v['body'] as Map;
      if (order.managerEditProjection?['fingerprint'] ==
              v['baseline']['fingerprint'] &&
          jsonEncode(order.items.map((i) => i.toJson()).toList()) ==
              jsonEncode(body['items']) &&
          order.includeServiceFee == body['includeServiceFee'] &&
          order.customServiceFeePercentage ==
              body['customServiceFeePercentage']) {
        return OrderEditResult.fromMap(v['result']);
      }
      v = null;
    }
    if (v == null) {
      final baseline = order.managerEditProjection;
      if (baseline == null)
        return const OrderEditResult(
          PosCommandDelivery.unavailable,
          code: 'pos_edit_baseline_required',
        );
      OrderEditProjection.read(baseline);
      v = {
        'baseline': baseline,
        'body': {
          'requestId': const Uuid().v4(),
          'expectedFingerprint': baseline['fingerprint'],
          'items': order.items.map((i) => i.toJson()).toList(),
          'includeServiceFee': order.includeServiceFee,
          'customServiceFeePercentage': order.customServiceFeePercentage,
        },
        'result': const OrderEditResult(PosCommandDelivery.unknown).toMap(),
      };
      await _box!.put(key(scope, order.orderId), v);
    }
    // A previous failed intent flush must settle before any HTTP retry.
    await _box!.flush();
    final old = OrderEditResult.fromMap(v['result']);
    if (old.delivery == PosCommandDelivery.failed)
      return old; // terminal never revived
    OrderEditResult result;
    try {
      if (!currentSession())
        return const OrderEditResult(
          PosCommandDelivery.failed,
          code: 'session_changed',
        );
      result = OrderEditResult.fromResponse(
        await send(Map<String, dynamic>.from(v['body'])),
        order.orderId,
      );
    } catch (_) {
      result = const OrderEditResult(
        PosCommandDelivery.unknown,
        code: 'transport_failure',
      );
    }
    final k = key(scope, order.orderId);
    // Hive exposes put values before flush completes. Keep the original
    // frozen request unresolved until this result is durably acknowledged.
    _unflushedResults[k] = {
      ...v,
      'result': const OrderEditResult(
        PosCommandDelivery.unknown,
        code: 'local_request_error',
      ).toMap(),
    };
    await _box!.put(k, {...v, 'result': result.toMap()});
    await _box!.flush();
    _unflushedResults.remove(k);
    if (!currentSession())
      return const OrderEditResult(
        PosCommandDelivery.failed,
        code: 'session_changed',
      );
    return result;
  }
}
