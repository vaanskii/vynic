import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

typedef FinanceCorrectionSend =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> body,
    );

/// A Cloud-owned record correction, persisted before HTTP. This stores no
/// credentials and never queues a financial transaction for offline execution.
abstract final class FinanceCorrectionRequests {
  static const boxName = 'manager_finance_corrections_v1';
  static Box? _box;
  static Future<void>? _opening;
  static final _flights =
      <String, ({String reason, Future<Map<String, dynamic>> result})>{};

  static Future<void> init() async {
    if (_box?.isOpen == true) return;
    if (_opening != null) return _opening!;
    final opening = Hive.openBox(boxName).then((box) {
      _box = box;
    });
    _opening = opening;
    try {
      await opening;
    } finally {
      _opening = null;
    }
  }

  @visibleForTesting
  static Future<void> Function(String phase)? storageFault;
  static Future<void> _persist(
    String key,
    Map<String, dynamic> row,
    String phase,
  ) async {
    await storageFault?.call('${phase}PutBefore');
    await _box!.put(key, row);
    await storageFault?.call('${phase}PutAfter');
    await storageFault?.call('${phase}FlushBefore');
    await _box!.flush();
    await storageFault?.call('${phase}FlushAfter');
  }

  static String _key(String scope, String path) =>
      sha256.convert(utf8.encode(jsonEncode([scope, path]))).toString();
  static Map<String, dynamic>? read(String scope, String path) {
    if (_box?.isOpen != true)
      throw StateError('Correction storage is unavailable');
    final raw = _box!.get(_key(scope, path));
    if (raw == null) return null;
    if (raw is! Map) throw const FormatException('Invalid saved correction');
    final row = Map<String, dynamic>.from(raw);
    if (row['version'] != 1 ||
        row['scope'] != scope ||
        row['path'] != path ||
        row['id'] is! String ||
        !Uuid.isValidUUID(fromString: row['id'] as String) ||
        row['reason'] is! String ||
        (row['reason'] as String).trim().isEmpty ||
        row['original'] is! Map ||
        (row['receipt'] != null && row['receipt'] is! Map)) {
      throw const FormatException('Invalid saved correction');
    }
    return row;
  }

  static BigInt _cents(dynamic value) {
    if (value is! String || !RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(value)) {
      throw const FormatException('Invalid correction amount');
    }
    final parts = value.replaceFirst('-', '').split('.');
    final cents =
        BigInt.parse(parts[0]) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    return value.startsWith('-') ? -cents : cents;
  }

  static void validateReceipt(
    String path,
    Map<String, dynamic> original,
    Map<String, dynamic> body,
    Map<String, dynamic> receipt,
  ) {
    final route = RegExp(
      r'^(payroll|cycles)/([^/]+)/(payments|reserves)/([^/]+)/reversal$',
    ).firstMatch(path);
    final parent = route?.group(1) == 'payroll'
        ? 'payrollPeriodId'
        : 'obligationCycleId';
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (route == null ||
        route.group(4) != original['id'] ||
        receipt['id'] != body['id'] ||
        receipt['reversalOfId'] != original['id'] ||
        receipt[parent] != route.group(2) ||
        receipt['notes'] != body['reason'] ||
        _cents(original['amount']) <= BigInt.zero ||
        _cents(receipt['amount']) != -_cents(original['amount']) ||
        receipt['businessDate'] != original['businessDate'] ||
        (route.group(3) == 'payments' &&
            receipt['paymentDate'] != original['paymentDate']) ||
        receipt['correctionBusinessDate'] is! String ||
        !date.hasMatch(receipt['correctionBusinessDate'] as String) ||
        receipt['actorId'] is! String ||
        (receipt['actorId'] as String).isEmpty ||
        receipt['createdAt'] is! String ||
        DateTime.tryParse(receipt['createdAt'] as String) == null) {
      throw const FormatException(
        'კორექტირების შედეგი ვერ დადასტურდა — გაიმეორეთ იგივე მოთხოვნა',
      );
    }
    if (route.group(3) == 'payments' &&
        route.group(1) == 'cycles' &&
        _cents(receipt['reserveConsumed']) !=
            -_cents(original['reserveConsumed'])) {
      throw const FormatException('კორექტირების რეზერვი ვერ დადასტურდა');
    }
  }

  static Future<Map<String, dynamic>> submit({
    required String scope,
    required String path,
    required String reason,
    required Map<String, dynamic> original,
    required FinanceCorrectionSend send,
    required void Function() requireSession,
  }) {
    final normalized = reason.trim();
    if (normalized.isEmpty || normalized.length > 1000) {
      return Future.error(
        ArgumentError('კორექტირების მიზეზი აუცილებელია (მაქს. 1000 სიმბოლო)'),
      );
    }
    final key = _key(scope, path), flight = _flights[_key(scope, path)];
    if (flight != null) {
      if (flight.reason != normalized)
        return Future.error(StateError('მოთხოვნის მიზეზი უკვე დაფიქსირებულია'));
      // Each caller still fences the result before displaying it.
      return flight.result.then((result) {
        requireSession();
        return result;
      });
    }
    final result = _submit(
      scope,
      path,
      normalized,
      original,
      send,
      requireSession,
    );
    _flights[key] = (reason: normalized, result: result);
    return result.whenComplete(() => _flights.remove(key));
  }

  static Future<Map<String, dynamic>> _submit(
    String scope,
    String path,
    String reason,
    Map<String, dynamic> original,
    FinanceCorrectionSend send,
    void Function() requireSession,
  ) async {
    requireSession();
    await init();
    requireSession();
    final previous = read(scope, path);
    final row =
        previous ??
        <String, dynamic>{
          'version': 1,
          'scope': scope,
          'path': path,
          'id': const Uuid().v4(),
          'reason': reason,
          'original': Map<String, dynamic>.from(original),
        };
    if (row['reason'] != reason ||
        jsonEncode(row['original']) != jsonEncode(original)) {
      throw StateError('შენახული მოთხოვნა განსხვავდება — განაახლეთ ისტორია');
    }
    final body = <String, dynamic>{'id': row['id'], 'reason': row['reason']};
    if (row['receipt'] is Map) {
      final receipt = Map<String, dynamic>.from(row['receipt']);
      validateReceipt(path, original, body, receipt);
      await storageFault?.call('replayFlushBefore');
      await _box!.flush();
      requireSession();
      return receipt;
    }
    await _persist(_key(scope, path), row, 'pending');
    requireSession();
    final receipt = await send(path, body);
    requireSession();
    validateReceipt(path, original, body, receipt);
    await _persist(_key(scope, path), {...row, 'receipt': receipt}, 'receipt');
    requireSession();
    return receipt;
  }
}
