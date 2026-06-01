import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'auth_token_service.dart';
import 'manager_notification_inbox.dart';
import 'mobile_cache_service.dart';

/// Manages the Socket.IO connection to the NestJS monitoring gateway.
///
/// Features:
///   • Exponential-backoff reconnection (max 60 s)
///   • Event deduplication via timestamp guard
///   • Heartbeat ping every 20 s to detect silent disconnects
///   • Exposes [ValueNotifier]s for reactive UI updates
class MonitoringSocketService {
  static io.Socket? _socket;
  static String get _serverUrl => ApiConfig.baseUrl;

  /// Current Socket.IO connection id; attached to REST calls so the server can skip echo notifications.
  static String? get monitoringSocketId {
    final id = _socket?.id;
    if (id == null) return null;
    final t = id.trim();
    return t.isEmpty ? null : t;
  }

  // ── Public state notifiers ─────────────────────────────────────────────────
  static final ValueNotifier<int> updateCounter = ValueNotifier<int>(0);
  static final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> apiError = ValueNotifier<bool>(false);

  /// Increments specifically on `audit_updated` socket events.
  static final ValueNotifier<int> auditCounter = ValueNotifier<int>(0);

  /// Date (ISO) of the most recent reservation change pushed from the POS.
  /// Mobile reservation screen jumps its date filter here so a new (often
  /// future-dated) reservation is visible right away.
  static final ValueNotifier<String?> lastReservationDate =
      ValueNotifier<String?>(null);

  /// Increments when the Windows POS closes the business day.
  /// Mobile screens listen to this to refresh sales/dashboard data.
  static final ValueNotifier<int> dayClosedCounter = ValueNotifier<int>(0);

  /// The current POS business date (YYYY-MM-DD) as set by the Windows app.
  /// Updated whenever the dashboard is fetched. Null until first fetch.
  static final ValueNotifier<String?> currentBusinessDate =
      ValueNotifier<String?>(null);

  /// True while the socket is making its very first connection attempt.
  /// The connection banner is suppressed during this window so the dashboard
  /// doesn't flash an error on every app launch.
  static final ValueNotifier<bool> isInitializing = ValueNotifier<bool>(false);

  // ── Reconnection state ─────────────────────────────────────────────────────
  static int _reconnectAttempts = 0;
  static Timer? _reconnectTimer;
  static Timer? _heartbeatTimer;
  static Timer? _initTimer;
  static bool _disposed = false;

  // ── Event deduplication ────────────────────────────────────────────────────
  static String? _lastEventSignature;

  // ── Init / Dispose ─────────────────────────────────────────────────────────

  static void initialize() {
    if (_socket != null) return;
    _disposed = false;
    // Mark as initialising; clear after first connect or 6-second timeout
    // so the UI never flashes a connection-error banner on first open.
    isInitializing.value = true;
    _initTimer = Timer(const Duration(seconds: 6), _clearInitializing);
    _connect();
  }

  static void _clearInitializing() {
    _initTimer?.cancel();
    _initTimer = null;
    isInitializing.value = false;
  }

  static void _connect() {
    if (_disposed) return;

    final builder = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setTimeout(10000);
    final jwt = AuthTokenService.token;
    if (jwt != null && jwt.isNotEmpty) {
      builder.setAuth(<String, dynamic>{'token': jwt});
    }
    _socket = io.io(_serverUrl, builder.build());

    _socket!.onConnect((_) {
      debugPrint('[WS] Connected');
      isConnected.value = true;
      _reconnectAttempts = 0;
      _cancelReconnectTimer();
      _clearInitializing(); // connected — safe to clear grace period early
      _startHeartbeat();
      // Re-fetch fresh data on reconnect
      updateCounter.value++;
    });

    _socket!.on('data_updated', _handleEvent);
    _socket!.on('order_created', _handleEvent);
    _socket!.on('order_updated', _handleEvent);
    _socket!.on('order_cancelled', _handleEvent);
    _socket!.on('orders_bulk_touch', _handleEvent);
    _socket!.on('tables_bulk_touch', _handleEvent);
    _socket!.on('takeaway_created', _handleEvent);
    _socket!.on('takeaway_deleted', _handleEvent);
    _socket!.on('table_updated', _handleEvent);
    _socket!.on('staff_sync', _handleEvent);
    _socket!.on('audit_updated', _handleAuditEvent);
    _socket!.on('day_closed', _handleDayClosedEvent);

    _socket!.on('heartbeat', (data) {
      debugPrint('[WS] Server heartbeat: $data');
    });

    _socket!.onDisconnect((_) {
      debugPrint('[WS] Disconnected');
      isConnected.value = false;
      _stopHeartbeat();
      _scheduleReconnect();
    });

    _socket!.onError((err) {
      debugPrint('[WS] Error: $err');
      _scheduleReconnect();
    });

    _socket!.connect();
  }

  // ── Event handler ──────────────────────────────────────────────────────────

  static void _handleEvent(dynamic data) {
    // Deduplication guard: skip only exact same event signature.
    // Using only timestamp can drop valid rapid events emitted in the same ms.
    if (data is Map) {
      final ts = data['timestamp'] as String?;
      final type = data['type']?.toString() ?? 'unknown';
      final eventPayload = data['payload'];
      final signature = '$type|$ts|${jsonEncode(eventPayload)}';
      if (_lastEventSignature != null && signature == _lastEventSignature) {
        debugPrint('[WS] Duplicate event skipped: $signature');
        return;
      }
      _lastEventSignature = signature;

      // Update cache diff if table data is included
      final payload = data['payload'];
      if (payload is Map && payload['tables'] is List) {
        final tables = (payload['tables'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        MobileCacheService.applyTableDiff(tables);
      }

      // Update lastServerTime for diff sync
      if (ts != null) {
        MobileCacheService.setLastServerTime(ts);
      }

      // Surface the reservation date so the reservations screen can jump to it.
      if (payload is Map && payload['type']?.toString() == 'reservations') {
        final resDate = payload['reservationDate']?.toString().trim();
        if (resDate != null && resDate.isNotEmpty) {
          lastReservationDate.value = resDate;
        }
      }

      ManagerNotificationInbox.ingestWsEnvelope(
        _stringKeyedMap(data),
        source: 'ws',
      );
    }

    debugPrint('[WS] Event received');
    updateCounter.value++;
  }

  static Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> raw) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  static void _handleAuditEvent(dynamic _) {
    debugPrint('[WS] audit_updated received');
    updateCounter.value++;
    auditCounter.value++;
  }

  static void _handleDayClosedEvent(dynamic data) {
    debugPrint('[WS] day_closed received: $data');
    // Also bump updateCounter so all data-dependent screens refresh.
    updateCounter.value++;
    dayClosedCounter.value++;
    try {
      final Map<String, dynamic> envelope;
      if (data is Map && data['type']?.toString() == 'day_closed') {
        envelope = _stringKeyedMap(data);
      } else if (data is Map<dynamic, dynamic>) {
        envelope = {
          'type': 'day_closed',
          'payload': _stringKeyedMap(data),
          'timestamp': DateTime.now().toIso8601String(),
        };
      } else {
        return;
      }
      ManagerNotificationInbox.ingestWsEnvelope(envelope, source: 'ws');
    } catch (_) {}
  }

  // ── Reconnection ───────────────────────────────────────────────────────────

  static void _scheduleReconnect() {
    if (_disposed) return;
    _cancelReconnectTimer();

    // Exponential backoff: 2s → 4s → 8s → 16s → 32s → 60s cap
    final delaySeconds = _reconnectAttempts < 6
        ? (1 << _reconnectAttempts).clamp(2, 60)
        : 60;
    _reconnectAttempts++;

    debugPrint(
      '[WS] Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts)',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_disposed) return;
      _socket?.dispose();
      _socket = null;
      _connect();
    });
  }

  static void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  static void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_socket?.connected == true) {
        _socket!.emit('ping');
      } else {
        _stopHeartbeat();
        _scheduleReconnect();
      }
    });
  }

  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  static void dispose() {
    _disposed = true;
    _cancelReconnectTimer();
    _stopHeartbeat();
    _socket?.dispose();
    _socket = null;
    isConnected.value = false;
  }
}
