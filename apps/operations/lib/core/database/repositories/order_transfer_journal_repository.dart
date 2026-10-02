import 'dart:convert';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';

import 'backup_repository.dart';

/// Primitive, additive meta records. Completed identities are retained so an
/// exact caller retry never replays old images over later ordinary edits.
class OrderTransferIntent {
  OrderTransferIntent(Map<String, dynamic> value) : data = cloneMap(value);

  final Map<String, dynamic> data;
  String get id => data['transferId'] as String;
  String get fingerprint => data['fingerprint'] as String;
  Map<String, dynamic> get request => cloneMap(data['request'] as Map);
  int get nextEffect => data['nextEffect'] as int;
  bool get pending => data['phase'] != 'completed';
  List<Map<String, dynamic>> get effects =>
      (data['effects'] as List).map((value) => cloneMap(value as Map)).toList();

  OrderTransferIntent receipt(int completed) => OrderTransferIntent(
    {
      ...data,
      'nextEffect': completed,
      'phase': completed == 0 ? 'intent' : effects[completed - 1]['phase'],
    }..remove('sha256'),
  );
  OrderTransferIntent get complete => OrderTransferIntent(
    {...data, 'phase': 'completed', 'nextEffect': effects.length}
      ..remove('sha256'),
  );

  Map<String, dynamic> toMap() {
    final raw = cloneMap(data)..remove('sha256');
    return {...raw, 'sha256': PosBackupFormat.digest(raw)};
  }

  factory OrderTransferIntent.fromMap(Object? value) {
    try {
      if (value is! Map) throw const FormatException('Missing transfer record');
      final raw = cloneMap(value);
      final unsigned = cloneMap(raw)..remove('sha256');
      if (raw['version'] != 1 ||
          raw['sha256'] != PosBackupFormat.digest(unsigned)) {
        throw const FormatException(
          'Unsupported or damaged Order transfer journal',
        );
      }
      final id = raw['transferId'];
      if (id is! String || !OrderTransferJournalRepository.validId(id)) {
        throw const FormatException('Invalid transfer identity');
      }
      final request = cloneMap(raw['request'] as Map);
      if (raw['fingerprint'] != PosBackupFormat.digest(request) ||
          !['move', 'releaseEmpty'].contains(request['kind']) ||
          request['actorId'] is! String ||
          (request['actorId'] as String).isEmpty ||
          !AuditSource.values.any((v) => v.wireValue == request['source']) ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}$',
          ).hasMatch(request['businessDate'] as String)) {
        throw const FormatException('Invalid transfer request fingerprint');
      }
      DateTime.parse(raw['startedAt'] as String);
      final source = orderImage(request['sourceOrder']);
      final destination = request['destinationOrder'] == null
          ? null
          : orderImage(request['destinationOrder']);
      if (destination?.orderId == source.orderId ||
          destination != null && destination.orderUuid == source.orderUuid) {
        throw const FormatException('Transfer identities are equal');
      }
      final effects = (raw['effects'] as List)
          .map((v) => cloneMap(v as Map))
          .toList();
      final index = raw['nextEffect'];
      if (effects.isEmpty ||
          index is! int ||
          index < 0 ||
          index > effects.length ||
          raw['phase'] != 'completed' &&
              raw['phase'] !=
                  (index == 0 ? 'intent' : effects[index - 1]['phase']) ||
          raw['phase'] == 'completed' && index != effects.length) {
        throw const FormatException('Invalid transfer phase');
      }
      final phases = <String>{};
      final previousImages = <String, Object?>{};
      final firstOrders = <int>{};
      final finalOrders = <int, Order>{};
      var moves = 0;
      var closes = 0;
      final movedLines = (raw['result'] as Map)['moved'] as List;
      final auditLines = <int, Set<int>>{};
      for (final effect in effects) {
        final store = effect['store'];
        final key = effect['key'];
        if (![
              'orders',
              'auditReport',
              'tables',
              'reservationState',
              'auditEvent',
            ].contains(store) ||
            !(key is String || key is int) ||
            effect['phase'] is! String ||
            !phases.add(effect['phase'] as String) ||
            effect['after'] is! Map) {
          throw const FormatException('Invalid transfer effect');
        }
        final identity = jsonEncode([store, key]);
        if (previousImages.containsKey(identity) &&
            !sameImage(previousImages[identity], effect['before'])) {
          throw const FormatException('Transfer image chain disagrees');
        }
        previousImages[identity] = effect['after'];
        if (store == 'orders') {
          final before = orderImage(effect['before']);
          final after = orderImage(effect['after']);
          final own = before.orderId == source.orderId ? source : destination;
          if (own == null ||
              before.orderUuid != own.orderUuid ||
              after.orderId != own.orderId ||
              after.orderUuid != own.orderUuid) {
            throw const FormatException('Transfer Order identity changed');
          }
          if (firstOrders.add(before.orderId) &&
              !sameImage(effect['before'], snapshot(own))) {
            throw const FormatException(
              'Transfer request/before image differs',
            );
          }
          final original = cloneMap(effect['before'] as Map);
          final result = cloneMap(effect['after'] as Map);
          for (final field in [
            'items',
            'totalAmount',
            'updatedAt',
            'status',
            'closedAt',
          ]) {
            original.remove(field);
            result.remove(field);
          }
          if (!sameImage(original, result) ||
              after.status != before.status &&
                  !(after.orderId == source.orderId &&
                      after.status == 'closed' &&
                      after.items.isEmpty &&
                      after.packageItems.isEmpty)) {
            throw const FormatException(
              'Transfer changed unrelated Order fields',
            );
          }
          finalOrders[after.orderId] = after;
        } else if (store == 'auditReport') {
          final after = AuditReport.fromMap(effect['after'] as Map);
          final before = effect['before'] == null
              ? null
              : AuditReport.fromMap(effect['before'] as Map);
          if (key != 'audit_report_order_${after.orderId}' ||
              ![source.orderId, destination?.orderId].contains(after.orderId) ||
              before?.locked == true ||
              before != null && before.orderId != after.orderId) {
            throw const FormatException('Invalid transfer audit target');
          }
          final prior = before?.orderedEvents ?? <AuditEvent>[];
          final events = after.orderedEvents;
          if (events.length <= prior.length ||
              !sameImage(
                events.take(prior.length).map((e) => e.toMap()).toList(),
                prior.map((e) => e.toMap()).toList(),
              )) {
            throw const FormatException('Transfer rewrote prior audit history');
          }
          for (final event in events.skip(prior.length)) {
            if (event.details?['transferId'] != id ||
                event.waiterId != request['actorId'] ||
                event.details?['source'] != request['source'] ||
                ![
                  AuditEventType.moveItems,
                  AuditEventType.transferClose,
                ].contains(event.type)) {
              throw const FormatException('Invalid transfer audit event');
            }
            if (event.type == AuditEventType.moveItems) {
              final ordinal = event.details?['transferLine'];
              if (ordinal is! int ||
                  ordinal < 0 ||
                  ordinal >= movedLines.length ||
                  !auditLines
                      .putIfAbsent(after.orderId, () => <int>{})
                      .add(ordinal)) {
                throw const FormatException(
                  'Duplicate or invalid transfer audit line',
                );
              }
              final line = movedLines[ordinal] as Map;
              final incoming = after.orderId == destination?.orderId;
              if (event.itemName != line['itemName'] ||
                  event.previousQty != (incoming ? 0 : line['quantity']) ||
                  event.newQty != (incoming ? line['quantity'] : 0) ||
                  event.details?['direction'] != (incoming ? 'IN' : 'OUT') ||
                  event.details?['quantity'] != line['quantity'] ||
                  event.details?['amount'] != line['amount'] ||
                  event.details?['menuItemId'] != line['menuItemId'] ||
                  event.details?['variantId'] != line['variantId'] ||
                  event.details?['fromOrderId'] != source.orderId ||
                  event.details?['fromOrderUuid'] != source.orderUuid ||
                  event.details?['toOrderId'] != destination?.orderId ||
                  event.details?['toOrderUuid'] != destination?.orderUuid) {
                throw const FormatException(
                  'Transfer audit differs from immutable move',
                );
              }
            } else if (after.orderId != source.orderId ||
                !after.locked ||
                after.status != AuditReportStatus.closed ||
                event.details?['isFiscal'] != false ||
                event.details?['grossAmount'] != 0.0 ||
                event.details?['collectedNow'] != 0.0) {
              throw const FormatException(
                'Invalid empty-source transfer closure',
              );
            }
            event.type == AuditEventType.moveItems ? moves++ : closes++;
          }
        } else if (store == 'tables') {
          final before = effect['before'] as Map;
          final after = effect['after'] as Map;
          if (before['activeOrderId'] != source.orderId ||
              before['floor'] != source.floor ||
              !source.tableNumbers.contains(before['tableNumber']) ||
              after['tableNumber'] != before['tableNumber'] ||
              after['floor'] != before['floor'] ||
              after['edgeRevision'] != before['edgeRevision'] ||
              after['isReserved'] != false ||
              after['activeOrderId'] != null ||
              after['reservationId'] != null) {
            throw const FormatException('Invalid transfer table ownership');
          }
        } else if (store == 'reservationState') {
          final before = effect['before'] as Map;
          final after = effect['after'] as Map;
          if (before['id'] is! String ||
              before['linkedOrderId'] != source.orderId ||
              after['id'] != before['id'] ||
              after['linkedOrderId'] != before['linkedOrderId'] ||
              after['status'] != 'completed') {
            throw const FormatException('Invalid transfer reservation target');
          }
        } else if (store == 'auditEvent') {
          final after = AuditEventLog.fromMap(cloneMap(effect['after'] as Map));
          if (effect['before'] != null ||
              after.id != key ||
              after.action != 'COMPLETE_RESERVATION' ||
              after.userId != request['actorId'] ||
              after.entityType != 'RESERVATION' ||
              after.data['source'] != request['source'] ||
              after.data['transferId'] != id) {
            throw const FormatException('Invalid transfer reservation audit');
          }
        }
      }
      final result = raw['result'] as Map;
      final moved = result['moved'] as List;
      if (request['kind'] == 'move') {
        final selected = <int, int>{};
        for (final move in request['moves'] as List) {
          final index = move['index'];
          final quantity = move['quantity'];
          if (quantity is! int) {
            throw const FormatException('Invalid immutable transfer selection');
          }
          // The existing arithmetic ignores unselected/nonpositive rows.
          if (quantity <= 0) continue;
          if (index is! int || index < 0 || index >= source.items.length) {
            throw const FormatException('Invalid immutable transfer selection');
          }
          selected[index] = (selected[index] ?? 0) + quantity;
          if (selected[index]! > source.items[index].quantity) {
            throw const FormatException(
              'Transfer selection exceeds original quantity',
            );
          }
        }
        final indexes = selected.keys.toList()..sort();
        final expected = [
          for (final index in indexes)
            {
              'itemName': source.items[index].itemName,
              'quantity': selected[index],
              'amount': double.parse(
                (source.items[index].total *
                        selected[index]! /
                        source.items[index].quantity)
                    .toStringAsFixed(2),
              ),
              'comment': source.items[index].comment,
              'menuItemId': source.items[index].menuItemId,
              'variantId': source.items[index].variantId,
            },
        ];
        if (!sameImage(expected, moved)) {
          throw const FormatException(
            'Transfer result differs from immutable selection',
          );
        }
      }
      if (!finalOrders.containsKey(source.orderId) ||
          destination != null &&
              !finalOrders.containsKey(destination.orderId) ||
          request['kind'] == 'move' &&
              (destination == null ||
                  moved.isEmpty ||
                  moves != moved.length * 2) ||
          request['kind'] == 'releaseEmpty' &&
              (moved.isNotEmpty || moves != 0)) {
        throw const FormatException('Incomplete transfer images/audits');
      }
      final finalSource = finalOrders[source.orderId]!;
      final empty =
          finalSource.items.isEmpty && finalSource.packageItems.isEmpty;
      if (result['sourceLeftEmpty'] != empty ||
          closes != (empty ? 1 : 0) ||
          empty && finalSource.status != 'closed' ||
          !sameImage(
            _conservation([source, if (destination != null) destination]),
            _conservation(finalOrders.values.toList()),
          )) {
        throw const FormatException(
          'Transfer quantity/value or empty-source conservation failed',
        );
      }
      return OrderTransferIntent(raw);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid Order transfer journal structure');
    }
  }

  static Map<String, dynamic> cloneMap(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  static bool sameImage(Object? left, Object? right) =>
      PosBackupFormat.canonical(left) == PosBackupFormat.canonical(right);
  static Map<String, dynamic> snapshot(Order order) {
    final image = cloneMap(BackupRepository.serializeOrder(order));
    for (final field in ['createdAt', 'updatedAt', 'closedAt']) {
      final value = image[field];
      if (value == null) continue;
      final date = DateTime.parse(value as String);
      image[field] = DateTime.fromMillisecondsSinceEpoch(
        date.millisecondsSinceEpoch,
        isUtc: date.isUtc,
      ).toIso8601String();
    }
    return image;
  }

  static Order orderImage(Object? raw) {
    if (raw is! Map)
      throw const FormatException('Missing transfer Order image');
    final map = cloneMap(raw);
    final order = BackupRepository.deserializeOrderSnapshot(map);
    if (order.orderUuid?.isNotEmpty != true ||
        !sameImage(map, snapshot(order))) {
      throw const FormatException('Lossy or invalid transfer Order image');
    }
    for (final item in [...order.items, ...order.packageItems]) {
      if (item.lineUuid?.isNotEmpty != true ||
          item.quantity < 0 ||
          !item.unitPrice.isFinite ||
          !item.total.isFinite) {
        throw const FormatException('Invalid transfer line image');
      }
    }
    return order;
  }

  static Map<String, dynamic> _conservation(List<Order> orders) {
    final totals = <String, List<int>>{};
    for (final order in orders) {
      for (final item in [...order.items, ...order.packageItems]) {
        final comment = item.comment?.trim();
        final key = jsonEncode([
          item.itemKey,
          item.menuItemId,
          item.variantId,
          comment?.isEmpty == true ? null : comment,
        ]);
        final total = totals.putIfAbsent(key, () => [0, 0]);
        total[0] += item.quantity;
        total[1] += (item.total * 100).round();
      }
    }
    return totals;
  }
}

abstract final class OrderTransferJournalRepository {
  static const prefix = 'orderTransferV1:';
  static bool validId(String id) =>
      RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(id);
  static String key(String id) => '$prefix$id';
  static List<OrderTransferIntent> records() => [
    for (final entry in DatabaseCore.metaBox!.toMap().entries)
      if (entry.key is String && (entry.key as String).startsWith(prefix))
        decode(entry.key as String, entry.value),
  ];
  static OrderTransferIntent decode(String key, Object? raw) {
    final intent = OrderTransferIntent.fromMap(raw);
    if (key != OrderTransferJournalRepository.key(intent.id)) {
      throw const FormatException('Order transfer key/identity mismatch');
    }
    return intent;
  }

  static OrderTransferIntent? read(String id) {
    final raw = DatabaseCore.metaBox!.get(key(id));
    return raw == null ? null : decode(key(id), raw);
  }

  static Future<void> write(OrderTransferIntent intent) async {
    final raw = intent.toMap();
    decode(key(intent.id), raw);
    await DatabaseCore.metaBox!.put(key(intent.id), raw);
    await DatabaseCore.metaBox!.flush();
  }

  /// Exactly the receipted prefix, with only its next write allowed to have
  /// happened before its receipt. Completed records intentionally skip this:
  /// their Orders may have been edited, settled or archived afterward.
  static void validateCurrent(
    OrderTransferIntent intent,
    Object? Function(String store, Object key) read,
  ) {
    if (!intent.pending) return;
    final expected = <String, Map<String, dynamic>>{};
    final effects = intent.effects;
    for (var i = 0; i < effects.length; i++) {
      final effect = effects[i];
      final identity = jsonEncode([effect['store'], effect['key']]);
      expected.putIfAbsent(
        identity,
        () => {'effect': effect, 'image': effect['before']},
      );
      if (i < intent.nextEffect) expected[identity]!['image'] = effect['after'];
    }
    for (final row in expected.values) {
      final effect = row['effect'] as Map;
      final actual = read(effect['store'] as String, effect['key'] as Object);
      final next = intent.nextEffect < effects.length
          ? effects[intent.nextEffect]
          : null;
      final mayBeAfter =
          next != null &&
          next['store'] == effect['store'] &&
          next['key'] == effect['key'];
      if (!OrderTransferIntent.sameImage(actual, row['image']) &&
          !(mayBeAfter &&
              OrderTransferIntent.sameImage(actual, next['after']))) {
        throw StateError(
          'Order transfer persisted image disagrees with ${effect['phase']}',
        );
      }
    }
  }
}
