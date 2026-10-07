import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'pos_command_delivery.dart';

class TableRepairResult {
  const TableRepairResult({required this.delivery, this.commandId, this.code});
  final PosCommandDelivery delivery;
  final String? commandId;
  final String? code;
  bool get isDone => delivery == PosCommandDelivery.succeeded;
  bool get isPending => delivery.isPending;
  bool get isError => !isDone && !isPending;
  String get message => switch (delivery) {
    PosCommandDelivery.succeeded => 'მოთხოვნა შესრულებულია POS-ის მიერ',
    PosCommandDelivery.queued =>
      'მოთხოვნა რიგშია — მაგიდა ჯერ არ გათავისუფლებულა',
    PosCommandDelivery.claimed => 'POS ასრულებს მოთხოვნას — დაელოდეთ შედეგს',
    PosCommandDelivery.unavailable =>
      'მთავარი POS მიუწვდომელია — მაგიდა არ შეცვლილა',
    PosCommandDelivery.failed => switch (code) {
      'session_changed' =>
        'სესია შეიცვალა — განაახლეთ ეკრანი და სცადეთ ხელახლა',
      'table_busy' => 'მაგიდას აქტიური შეკვეთა ან რეზერვაცია ეკუთვნის',
      'unsupported_command_type' =>
        'მაგიდის შესამოწმებლად საჭიროა POS-ის განახლება',
      'stale_table' => 'მაგიდა შეიცვალა — განაახლეთ მონაცემები',
      'table_not_found' => 'მაგიდა ვერ მოიძებნა',
      _ => 'POS-მა მოთხოვნა უარყო — განაახლეთ მონაცემები',
    },
    _ => 'შედეგი უცნობია — უსაფრთხოდ გადაამოწმეთ იგივე მოთხოვნა',
  };
  Map<String, dynamic> toMap() => {
    'status': delivery.name,
    'commandId': commandId,
    'code': code,
  };
  factory TableRepairResult.fromMap(Map<String, dynamic> value) =>
      TableRepairResult(
        delivery: PosCommandDelivery.values.firstWhere(
          (d) => d.name == value['status'],
          orElse: () => PosCommandDelivery.unknown,
        ),
        commandId: value['commandId'] as String?,
        code: value['code'] as String?,
      );
  factory TableRepairResult.fromResponse(http.Response response) {
    final Object? raw;
    try {
      raw = jsonDecode(response.body);
    } on FormatException {
      return const TableRepairResult(
        delivery: PosCommandDelivery.unknown,
        code: 'invalid_response',
      );
    }
    if (raw is! Map)
      return const TableRepairResult(
        delivery: PosCommandDelivery.unknown,
        code: 'invalid_response',
      );
    final body = Map<String, dynamic>.from(raw);
    final status = PosCommandDelivery.fromResponse(body);
    final detail = body['posDelivery'];
    if (response.statusCode == 404)
      return const TableRepairResult(
        delivery: PosCommandDelivery.failed,
        code: 'table_not_found',
      );
    if (detail is! Map ||
        (response.statusCode != 200 && response.statusCode != 202) ||
        status == PosCommandDelivery.deliveredLegacy ||
        status == PosCommandDelivery.succeeded && body['success'] != true ||
        (status.isPending || status == PosCommandDelivery.succeeded) &&
            (detail['commandId'] is! String ||
                (detail['commandId'] as String).isEmpty)) {
      return TableRepairResult(
        delivery: PosCommandDelivery.unknown,
        code: response.statusCode == 404
            ? 'table_not_found'
            : 'invalid_response',
      );
    }
    return TableRepairResult(
      delivery: status,
      commandId: detail['commandId'] as String?,
      code: detail['code'] as String?,
    );
  }
}

/// Persist BEFORE HTTP so a lost response, app restart or reopened screen uses
/// the same immutable Cloud command. This box stores no token or credential.
abstract final class TableRepairRequests {
  static const boxName = 'manager_table_repairs_v1';
  static final revision = ValueNotifier<int>(0);
  static Box? _box;
  static final _inflight = <String, Future<TableRepairResult>>{};
  static Future<void> init() async {
    if (_box?.isOpen != true) _box = await Hive.openBox(boxName);
  }

  static String scope(String origin, String principal) =>
      sha256.convert(utf8.encode(jsonEncode([origin, principal]))).toString();
  static String key(String scope, String number, String floor) => sha256
      .convert(utf8.encode(jsonEncode([scope, number, floor])))
      .toString();
  static Map<String, dynamic>? read(String scope, String number, String floor) {
    if (_box?.isOpen != true) return null;
    final value = _box!.get(key(scope, number, floor));
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  static List<Map<String, dynamic>> list(String scope) => _box?.isOpen == true
      ? _box!.values
            .whereType<Map>()
            .where((v) => v['scope'] == scope)
            .map((v) => Map<String, dynamic>.from(v))
            .toList()
      : [];
  static Future<TableRepairResult> submit({
    required String scope,
    required String number,
    required String floor,
    required Future<http.Response> Function(Map<String, dynamic>) send,
    bool refresh = false,
  }) {
    final identity = key(scope, number, floor);
    final previous = _inflight[identity];
    if (previous != null) return previous;
    final future = _submit(
      scope: scope,
      number: number,
      floor: floor,
      send: send,
      refresh: refresh,
    );
    _inflight[identity] = future;
    return future.whenComplete(() => _inflight.remove(identity));
  }

  static Future<TableRepairResult> _submit({
    required String scope,
    required String number,
    required String floor,
    required Future<http.Response> Function(Map<String, dynamic>) send,
    required bool refresh,
  }) async {
    await init();
    final previous = read(scope, number, floor);
    final previousResult = previous == null
        ? null
        : TableRepairResult.fromMap(
            Map<String, dynamic>.from(previous['result']),
          );
    final reuse =
        refresh ||
        previousResult != null &&
            (previousResult.isPending ||
                previousResult.delivery == PosCommandDelivery.unknown);
    if (refresh && previous == null)
      throw StateError('No repair request to refresh');
    final value = reuse
        ? previous!
        : <String, dynamic>{
            'scope': scope,
            'tableNumber': number,
            'floor': floor,
            'requestId': const Uuid().v4(),
            'result': const TableRepairResult(
              delivery: PosCommandDelivery.unknown,
            ).toMap(),
          };
    await _box!.put(key(scope, number, floor), value);
    await _box!.flush();
    final TableRepairResult result;
    try {
      result = TableRepairResult.fromResponse(
        await send({'requestId': value['requestId']}),
      );
    } catch (error, stack) {
      debugPrint(
        'Table repair response unavailable: ${error.runtimeType}\n$stack',
      );
      final unknown = const TableRepairResult(
        delivery: PosCommandDelivery.unknown,
        code: 'transport_failure',
      );
      await _box!.put(key(scope, number, floor), {
        ...value,
        'result': unknown.toMap(),
      });
      await _box!.flush();
      revision.value++;
      return unknown;
    }
    await _box!.put(key(scope, number, floor), {
      ...value,
      'result': result.toMap(),
    });
    await _box!.flush();
    revision.value++;
    return result;
  }
}
