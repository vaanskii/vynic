import 'package:vynic/core/services/app_notification_history_store.dart';
import 'package:vynic/core/services/mobile_edit_echo_guard.dart';

/// Normalises Socket.IO / FCM payloads into the manager notification panel (dedupe-safe).
class ManagerNotificationInbox {
  ManagerNotificationInbox._();

  static Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> raw) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  static String _formatSyncOccurredAt(String? iso) {
    final parsed = iso != null ? DateTime.tryParse(iso) : null;
    final dt = parsed ?? DateTime.now();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  /// Meta stored on each entry so notification tap can open [MobileOrderDetailScreen].
  static Map<String, dynamic> orderNavMeta({
    required int posOrderId,
    String? tableLabel,
    String? floor,
    Iterable<String>? highlightItemKeys,
  }) {
    return {
      'posOrderId': posOrderId,
      if (tableLabel != null && tableLabel.trim().isNotEmpty)
        'tableLabel': tableLabel.trim(),
      if (floor != null && floor.trim().isNotEmpty) 'floor': floor.trim(),
      if (highlightItemKeys != null && highlightItemKeys.isNotEmpty)
        'highlightItemKeys': highlightItemKeys.toList(),
    };
  }

  static void _add({
    String? dedupeId,
    required String title,
    required String message,
    required String source,
    Map<String, dynamic>? meta,
  }) {
    AppNotificationHistoryStore.instance.add(
      dedupeId: dedupeId,
      title: title,
      message: message,
      source: source,
      meta: meta,
    );
  }

  /// Local events (e.g. mobile → POS ingest) without Socket.IO.
  static void ingestLocal({
    required String title,
    required String message,
    String source = 'local',
    Map<String, dynamic>? meta,
    String? dedupeId,
  }) {
    _add(
      dedupeId: dedupeId,
      title: title,
      message: message,
      source: source,
      meta: meta,
    );
  }

  /// Ingest a full WS envelope `{ type, payload, timestamp, notificationId? }`.
  static void ingestWsEnvelope(
    Map<String, dynamic> envelope, {
    String source = 'ws',
  }) {
    try {
      final eventType = envelope['type']?.toString() ?? '';
      final nid = envelope['notificationId']?.toString();
      final payloadRaw = envelope['payload'];
      final payloadMap = payloadRaw is Map<dynamic, dynamic>
          ? _stringKeyedMap(payloadRaw)
          : null;

      switch (eventType) {
        case 'takeaway_created':
          final id = payloadMap?['posOrderId'];
          final customer = (payloadMap?['customerName'] ?? '').toString().trim();
          final pickup = (payloadMap?['pickupTime'] ?? '').toString().trim();
          final detail = [
            if (customer.isNotEmpty) customer,
            if (pickup.isNotEmpty) 'აღება: $pickup',
          ].join(' • ');
          _add(
            dedupeId: nid,
            title: 'გატანა',
            message:
                'დაემატა შეკვეთა${id != null ? ' #$id' : ''}${detail.isNotEmpty ? ' — $detail' : ''}',
            source: source,
            meta: payloadMap,
          );
          break;
        case 'takeaway_deleted':
          final id = payloadMap?['posOrderId'];
          _add(
            dedupeId: nid,
            title: 'გატანა',
            message: 'შეკვეთა წაიშალა${id != null ? ' #$id' : ''}',
            source: source,
            meta: payloadMap,
          );
          break;
        case 'orders_bulk_touch':
          final src = (payloadMap?['source'] ?? 'pos_sync').toString();
          final isPos = src == 'pos_sync';
          final touchesRaw = payloadMap?['touches'];
          if (touchesRaw is List && touchesRaw.isNotEmpty) {
            for (final t in touchesRaw) {
              if (t is! Map) continue;
              final tm = _stringKeyedMap(t);
              final idRaw = tm['posOrderId'];
              final id = idRaw is num
                  ? idRaw.toInt()
                  : int.tryParse(idRaw?.toString() ?? '');
              if (id == null) continue;
              if ((isPos || src == 'mobile_manager') &&
                  MobileEditEchoGuard.shouldSuppressPosEcho(id)) {
                continue;
              }
              final tableLabel = (tm['tableLabel'] ?? '').toString().trim();
              final when = _formatSyncOccurredAt(tm['occurredAt']?.toString());
              final tableSeg = tableLabel.isNotEmpty
                  ? 'მაგიდა: $tableLabel — '
                  : '';
              final summary = (tm['changeSummary'] ?? '').toString().trim();
              final isServiceFeeChange =
                  tm['changeKind']?.toString() == 'service_fee' ||
                  summary.contains('სერვისის საფასური');
              final summarySeg =
                  summary.isNotEmpty ? '\n$summary' : '';
              final rawHighlights = tm['highlightItemKeys'];
              Iterable<String>? highlightKeys;
              if (rawHighlights is List && rawHighlights.isNotEmpty) {
                highlightKeys =
                    rawHighlights.map((e) => e.toString()).where((s) => s.isNotEmpty);
              }
              final title = isServiceFeeChange && tableLabel.isNotEmpty
                  ? 'მაგიდები'
                  : (isPos ? 'სალარო' : 'შეკვეთა');
              final message = isServiceFeeChange && tableLabel.isNotEmpty
                  ? 'მაგიდა $tableLabel — სერვისის საფასური განახლდა$summarySeg'
                  : (isPos
                      ? 'შეკვეთა #$id — $tableSegდრო: $when$summarySeg'
                      : 'შეკვეთა #$id განახლდა — $tableSegდრო: $when$summarySeg');
              _add(
                dedupeId: nid != null ? '$nid-$id' : null,
                title: title,
                message: message,
                source: source,
                meta: orderNavMeta(
                  posOrderId: id,
                  tableLabel: tableLabel.isNotEmpty ? tableLabel : null,
                  floor: tm['floor']?.toString(),
                  highlightItemKeys: highlightKeys,
                ),
              );
            }
            break;
          }
          final idsRaw = payloadMap?['posOrderIds'];
          if (idsRaw is List && idsRaw.isNotEmpty) {
            final ids = idsRaw
                .map((e) {
                  if (e is num) return e.toInt();
                  return int.tryParse(e.toString());
                })
                .whereType<int>()
                .where(
                  (id) => !isPos || !MobileEditEchoGuard.shouldSuppressPosEcho(id),
                )
                .toList();
            if (ids.isEmpty) break;
            if (ids.length == 1) {
              _add(
                dedupeId: nid,
                title: isPos ? 'სალარო' : 'შეკვეთა',
                message: isPos
                    ? 'შეკვეთა #${ids.first} განახლდა (მენიუ / რაოდენობა)'
                    : 'შეკვეთა #${ids.first} განახლდა',
                source: source,
                meta: orderNavMeta(posOrderId: ids.first),
              );
            } else if (ids.length <= 5) {
              _add(
                dedupeId: nid,
                title: isPos ? 'სალარო' : 'შეკვეთები',
                message: isPos
                    ? 'განახლდა შეკვეთები: ${ids.map((i) => '#$i').join(', ')}'
                    : 'განახლდა: ${ids.map((i) => '#$i').join(', ')}',
                source: source,
                meta: payloadMap,
              );
            } else {
              _add(
                dedupeId: nid,
                title: isPos ? 'სალარო' : 'შეკვეთები',
                message: isPos
                    ? 'განახლდა ${ids.length} შეკვეთა (მენიუ / თანხები)'
                    : 'განახლდა ${ids.length} შეკვეთა',
                source: source,
                meta: payloadMap,
              );
            }
          }
          break;
        case 'tables_bulk_touch':
          final tableSrc = (payloadMap?['source'] ?? 'pos_sync').toString();
          final tableTouchesRaw = payloadMap?['touches'];
          if (tableTouchesRaw is List && tableTouchesRaw.isNotEmpty) {
            for (final t in tableTouchesRaw) {
              if (t is! Map) continue;
              final tm = _stringKeyedMap(t);
              final changeType = (tm['changeType'] ?? '').toString();
              if (changeType != 'reserved') continue;
              final tableNumber = (tm['tableNumber'] ?? '').toString().trim();
              if (tableNumber.isEmpty) continue;
              final floor = (tm['floor'] ?? 'first').toString().trim();
              if (tableSrc == 'pos_sync' &&
                  MobileEditEchoGuard.shouldSuppressTableEcho(
                    tableNumber,
                    floor,
                  )) {
                continue;
              }
              final orderIdRaw = tm['activeOrderId'];
              final orderId = orderIdRaw is num
                  ? orderIdRaw.toInt()
                  : int.tryParse(orderIdRaw?.toString() ?? '');
              if (tableSrc == 'pos_sync' &&
                  orderId != null &&
                  MobileEditEchoGuard.shouldSuppressPosEcho(orderId)) {
                continue;
              }
              final when = _formatSyncOccurredAt(tm['occurredAt']?.toString());
              final orderSeg =
                  orderId != null ? ' — შეკვეთა #$orderId' : '';
              _add(
                dedupeId: nid != null ? '$nid-$tableNumber-$floor' : null,
                title: 'მაგიდები',
                message:
                    'მაგიდა $tableNumber დაკავდა$orderSeg — დრო: $when',
                source: source,
                meta: orderId != null
                    ? orderNavMeta(
                        posOrderId: orderId,
                        tableLabel: tableNumber,
                        floor: floor,
                      )
                    : {
                        'tableNumber': tableNumber,
                        'floor': floor,
                      },
              );
            }
            break;
          }
          break;
        case 'order_updated':
          final orderSrc = (payloadMap?['source'] ?? '').toString();
          if (orderSrc == 'pos_sync') {
            break;
          }
          if (orderSrc == 'mobile_manager') {
            final selfId = payloadMap?['posOrderId'];
            final selfIdInt = selfId is num
                ? selfId.toInt()
                : int.tryParse(selfId?.toString() ?? '');
            if (MobileEditEchoGuard.shouldSuppressPosEcho(selfIdInt)) {
              break;
            }
          }
          final idsRaw = payloadMap?['posOrderIds'];
          if (idsRaw is List && idsRaw.isNotEmpty) {
            final ids = idsRaw
                .map((e) {
                  if (e is num) return e.toInt();
                  return int.tryParse(e.toString());
                })
                .whereType<int>()
                .toList();
            if (ids.isNotEmpty) {
              final src = (payloadMap?['source'] ?? '').toString();
              _add(
                dedupeId: nid,
                title: src == 'pos_sync' ? 'სალარო' : 'შეკვეთა',
                message: ids.length == 1
                    ? 'შეკვეთა #${ids.first} განახლდა'
                    : 'განახლდა ${ids.length} შეკვეთა',
                source: source,
                meta: ids.length == 1
                    ? orderNavMeta(posOrderId: ids.first)
                    : payloadMap,
              );
              break;
            }
          }
          final id = payloadMap?['posOrderId'];
          if (id == null) break;
          final src = (payloadMap?['source'] ?? '').toString();
          _add(
            dedupeId: nid,
            title: src == 'pos_sync' ? 'სალარო' : 'მენეჯერი',
            message: src == 'pos_sync'
                ? 'შეკვეთა #$id განახლდა (სალარო)'
                : 'შეკვეთა #$id განახლდა (მენეჯერი)',
            source: source,
            meta: payloadMap,
          );
          break;
        case 'order_cancelled':
          final id = payloadMap?['posOrderId'];
          final tableLabel = (payloadMap?['tableLabel'] ?? '').toString().trim();
          final tableSeg = tableLabel.isNotEmpty ? ' — მაგიდა $tableLabel' : '';
          _add(
            dedupeId: nid,
            title: 'შეკვეთა',
            message: 'გაუქმდა${id != null ? ' #$id' : ''}$tableSeg',
            source: source,
            meta: payloadMap,
          );
          break;
        case 'order_created':
          final id = payloadMap?['posOrderId'];
          final tableLabel = (payloadMap?['tableLabel'] ?? '').toString().trim();
          final isWalkIn = payloadMap?['walkIn'] == true;
          final tableSeg = tableLabel.isNotEmpty ? ' — მაგიდა $tableLabel' : '';
          _add(
            dedupeId: nid,
            title: 'შეკვეთა',
            message:
                '${isWalkIn ? 'ახალი walk-in' : 'შეიქმნა ახალი შეკვეთა'}${id != null ? ' #$id' : ''}$tableSeg',
            source: source,
            meta: payloadMap,
          );
          break;
        case 'table_updated':
          if ((payloadMap?['source'] ?? '').toString() == 'pos_sync') {
            break;
          }
          _add(
            dedupeId: nid,
            title: 'მაგიდები',
            message: 'მაგიდების სტატუსი განახლდა',
            source: source,
            meta: payloadMap,
          );
          break;
        case 'data_updated':
          final inner = payloadMap?['type']?.toString();
          switch (inner) {
            case 'reservations':
              final customerName = payloadMap?['customerName']
                  ?.toString()
                  .trim();
              final isNew =
                  payloadMap?['action']?.toString().trim() == 'created';
              final tablesRaw = payloadMap?['tableNumbers'];
              final tables = tablesRaw is List
                  ? tablesRaw
                        .map((e) => e.toString().trim())
                        .where((s) => s.isNotEmpty && s != '0')
                        .toList()
                  : const <String>[];
              final resTime =
                  (payloadMap?['reservationTime'] ?? '').toString().trim();
              final detail = [
                if (customerName != null && customerName.isNotEmpty)
                  customerName,
                if (tables.isNotEmpty) 'მაგიდა ${tables.join(', ')}',
                if (resTime.isNotEmpty) 'დრო: $resTime',
              ].join(' • ');
              _add(
                dedupeId: nid,
                title: 'რეზერვაციები',
                message: detail.isNotEmpty
                    ? (isNew
                          ? 'ახალი რეზერვაცია — $detail'
                          : 'რეზერვაცია განახლდა — $detail')
                    : 'მონაცემები განახლდა',
                source: source,
                meta: payloadMap,
              );
              break;
            case 'tables':
              _add(
                dedupeId: nid,
                title: 'მაგიდები',
                message: 'მონაცემები განახლდა',
                source: source,
                meta: payloadMap,
              );
              break;
            case 'all':
              break;
            case 'menu':
              _add(
                dedupeId: nid,
                title: 'მენიუ',
                message: 'მენიუ განახლდა',
                source: source,
                meta: payloadMap,
              );
              break;
            default:
              break;
          }
          break;
        case 'day_closed':
          final meta = payloadMap;
          _add(
            dedupeId: nid,
            title: 'დღის დახურვა',
            message: 'ბიზნეს დღის სტატუსი შეიცვალა',
            source: source,
            meta: meta,
          );
          break;
        default:
          break;
      }
    } catch (_) {}
  }
}
