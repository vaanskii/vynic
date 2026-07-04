import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/sync/mobile_edit_echo_guard.dart';
import 'package:vynic/core/services/notifications/notification_message_copy.dart';

/// Normalises Socket.IO / FCM payloads into the manager notification panel (dedupe-safe).
class ManagerNotificationInbox {
  ManagerNotificationInbox._();

  static const Duration _serviceFeeNotifyQuiet = Duration(milliseconds: 2500);
  static final Map<int, Timer> _serviceFeeNotifyTimers = {};
  static final Map<int, _PendingServiceFeeNotify> _serviceFeeNotifyPending = {};

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

  /// One line for service-fee alerts (dedupes merged POS hints).
  static String normalizeServiceFeeSummary(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 'სერვისის საფასური განახლდა';

    final unique = <String>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!unique.contains(trimmed)) unique.add(trimmed);
    }
    for (var i = unique.length - 1; i >= 0; i--) {
      final line = unique[i];
      if (line.contains('ჩართული') || line.contains('გამორთული')) {
        return line;
      }
    }
    return unique.last;
  }

  static String formatServiceFeeMessage({
    required int orderId,
    required String tableLabel,
    required String summary,
  }) {
    final state = normalizeServiceFeeSummary(summary);
    final label = tableLabel.trim();
    if (label.isNotEmpty && label != '-') {
      return 'მაგიდა $label — $state';
    }
    return 'შეკვეთა #$orderId — $state';
  }

  static bool _isDecreaseSummary(String summary) {
    final m = RegExp(r'(\d+)\s*→\s*(\d+)').firstMatch(summary);
    if (m == null) return false;
    final prev = int.tryParse(m.group(1) ?? '');
    final next = int.tryParse(m.group(2) ?? '');
    if (prev == null || next == null) return false;
    return next < prev;
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

  static void _scheduleServiceFeeNotify({
    required int posOrderId,
    String? dedupeId,
    required String title,
    required String message,
    required String source,
    Map<String, dynamic>? meta,
  }) {
    _serviceFeeNotifyTimers[posOrderId]?.cancel();
    _serviceFeeNotifyPending[posOrderId] = _PendingServiceFeeNotify(
      dedupeId: dedupeId,
      title: title,
      message: message,
      source: source,
      meta: meta,
    );
    _serviceFeeNotifyTimers[posOrderId] = Timer(_serviceFeeNotifyQuiet, () {
      _serviceFeeNotifyTimers.remove(posOrderId);
      final pending = _serviceFeeNotifyPending.remove(posOrderId);
      if (pending == null) return;
      _add(
        dedupeId: pending.dedupeId,
        title: pending.title,
        message: pending.message,
        source: pending.source,
        meta: pending.meta,
      );
    });
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
          final touchesList =
              touchesRaw is List ? touchesRaw : const <dynamic>[];
          final serviceFeeOnly = touchesList.isNotEmpty &&
              touchesList.every((t) {
                if (t is! Map) return false;
                final kind =
                    (t['changeKind'] ?? '').toString().trim().toLowerCase();
                return kind == 'service_fee';
              });
          // Realtime socket refresh (no notificationId) — wait for coalesced push.
          if (serviceFeeOnly && (nid == null || nid.isEmpty)) {
            break;
          }
          if (touchesRaw is List && touchesRaw.isNotEmpty) {
            final handledOrderIds = <int>{};
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
              final kind = (tm['changeKind'] ?? '').toString().trim().toLowerCase();
              // Requested behavior: ignore waiter increases; keep decreases + service fee only.
              final shouldNotify = kind == 'service_fee' || _isDecreaseSummary(summary);
              if (!shouldNotify) continue;
              if (handledOrderIds.contains(id)) continue;
              handledOrderIds.add(id);
              final isServiceFeeChange =
                  kind == 'service_fee' ||
                  summary.contains('სერვისის საფასური');
              final rawHighlights = tm['highlightItemKeys'];
              Iterable<String>? highlightKeys;
              if (rawHighlights is List && rawHighlights.isNotEmpty) {
                highlightKeys =
                    rawHighlights.map((e) => e.toString()).where((s) => s.isNotEmpty);
              }
              final title = isServiceFeeChange && tableLabel.isNotEmpty
                  ? 'მაგიდები'
                  : (isPos ? 'სალარო' : 'შეკვეთა');
              final summarySeg =
                  summary.isNotEmpty ? '\n$summary' : '';
              final message = isServiceFeeChange
                  ? formatServiceFeeMessage(
                      orderId: id,
                      tableLabel: tableLabel,
                      summary: summary,
                    )
                  : (isPos
                      ? 'შეკვეთა #$id — $tableSegდრო: $when$summarySeg'
                      : 'შეკვეთა #$id განახლდა — $tableSegდრო: $when$summarySeg');
              final meta = orderNavMeta(
                posOrderId: id,
                tableLabel: tableLabel.isNotEmpty && tableLabel != '-'
                    ? tableLabel
                    : null,
                floor: tm['floor']?.toString(),
                highlightItemKeys: highlightKeys,
              );
              if (isServiceFeeChange) {
                _scheduleServiceFeeNotify(
                  posOrderId: id,
                  dedupeId: nid,
                  title: title,
                  message: message.trim(),
                  source: source,
                  meta: meta,
                );
              } else {
                _add(
                  dedupeId: nid != null ? '$nid-$id' : null,
                  title: title,
                  message: message,
                  source: source,
                  meta: meta,
                );
              }
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
              final tableNumber = (tm['tableNumber'] ?? '').toString().trim();
              if (tableNumber.isEmpty) continue;
              final floor = (tm['floor'] ?? 'first').toString().trim();
              final changeType = (tm['changeType'] ?? '').toString();
              if (changeType == 'freed') {
                final when = _formatSyncOccurredAt(tm['occurredAt']?.toString());
                _add(
                  dedupeId: nid != null ? '$nid-$tableNumber-$floor-freed' : null,
                  title: 'მაგიდა',
                  message:
                      'მაგიდა $tableNumber გაუქმდა — დრო: $when',
                  source: source,
                  meta: {
                    'tableNumber': tableNumber,
                    'floor': floor,
                  },
                );
                continue;
              }
              // Reserved tables from POS sync are covered by orders_bulk_touch.
              if (tableSrc == 'pos_sync') continue;
              if (changeType != 'reserved') continue;
              if (MobileEditEchoGuard.shouldSuppressTableEcho(
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
          if (payloadMap != null) {
            final copy = buildOrderCancelledCopy(payloadMap);
            _add(
              dedupeId: nid,
              title: copy.title,
              message: copy.message,
              source: source,
              meta: payloadMap,
            );
          }
          break;
        case 'order_created':
          if (payloadMap != null) {
            final copy = buildOrderCreatedCopy(payloadMap);
            _add(
              dedupeId: nid,
              title: copy.title,
              message: copy.message,
              source: source,
              meta: payloadMap,
            );
          }
          break;
        case 'table_updated':
          // Too noisy and often duplicated with order/touch events.
          // Table-open notifications are surfaced via order_created / tables_bulk_touch.
          break;
        case 'data_updated':
          final inner = payloadMap?['type']?.toString();
          switch (inner) {
            case 'reservations':
              if (payloadMap != null) {
                final copy = buildReservationsCopy(payloadMap);
                _add(
                  dedupeId: nid,
                  title: copy.title,
                  message: copy.message,
                  source: source,
                  meta: enrichWalkInReservationNotificationMeta(payloadMap),
                );
              }
              break;
            case 'tables':
              if (payloadMap != null) {
                final tableNumber =
                    (payloadMap['tableNumber'] ?? '').toString().trim();
                final action =
                    (payloadMap['action'] ?? '').toString().trim().toLowerCase();
                if (action == 'freed' || action == 'cancelled') {
                  final label =
                      tableNumber.isNotEmpty ? tableNumber : 'მაგიდა';
                  _add(
                    dedupeId: nid,
                    title: 'მაგიდა',
                    message: 'მაგიდა $label გაუქმდა',
                    source: source,
                    meta: payloadMap,
                  );
                } else if (tableNumber.isNotEmpty) {
                  _add(
                    dedupeId: nid,
                    title: 'მაგიდები',
                    message: 'მაგიდა $tableNumber განახლდა',
                    source: source,
                    meta: payloadMap,
                  );
                }
              }
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

  /// Pull notifications persisted on the server while the socket was down.
  static Future<int> syncMissedFromServer() async {
    try {
      final lastSyncRaw = MobileCacheService.lastNotificationsSyncAt;
      final lastSyncDt = lastSyncRaw != null
          ? DateTime.tryParse(lastSyncRaw)
          : null;
      final since = (lastSyncDt ?? DateTime.now().subtract(const Duration(hours: 24)))
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String();

      final rows = await MobileApiService.getNotifications(since: since);
      var added = 0;
      for (final row in rows) {
        final envelope = row['envelope'];
        if (envelope is Map) {
          final env = Map<String, dynamic>.from(envelope);
          ingestWsEnvelope(env, source: 'catchup');
          added++;
        } else {
          final title = (row['title'] ?? '').toString();
          final body = (row['body'] ?? '').toString();
          final id = row['id']?.toString();
          if (body.isNotEmpty) {
            final ok = AppNotificationHistoryStore.instance.add(
              dedupeId: id,
              title: title.isEmpty ? 'შეტყობინება' : title,
              message: body,
              source: 'catchup',
              meta: row['type'] != null
                  ? {'type': row['type'].toString()}
                  : null,
            );
            if (ok) added++;
          }
        }
      }

      await MobileCacheService.setLastNotificationsSyncAt(
        DateTime.now().toUtc().toIso8601String(),
      );
      if (added > 0) {
        debugPrint('[Notifications] Catch-up: $added from server');
      }
      return added;
    } catch (e) {
      debugPrint('[Notifications] Catch-up failed: $e');
      return 0;
    }
  }
}

class _PendingServiceFeeNotify {
  const _PendingServiceFeeNotify({
    this.dedupeId,
    required this.title,
    required this.message,
    required this.source,
    this.meta,
  });

  final String? dedupeId;
  final String title;
  final String message;
  final String source;
  final Map<String, dynamic>? meta;
}
