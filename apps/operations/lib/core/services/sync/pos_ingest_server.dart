import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import 'package:vynic/core/services/sync/pos_callback_config.dart';

/// Minimal HTTP server on Windows POS for cloud → Hive callbacks (Option A).
class PosIngestServer {
  PosIngestServer._();

  static HttpServer? _server;
  static int? _boundPort;
  static String? _callbackHost;

  static int get defaultPort {
    final fromEnv = int.tryParse(dotenv.env['POS_INGEST_PORT']?.trim() ?? '');
    return fromEnv ?? 8081;
  }

  static Future<void> start() async {
    if (_server != null) return;
    if (kIsWeb) return;
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;

    final key = DatabaseService.ensurePosIngestConnectionKey().trim();
    if (key.isEmpty) {
      // Every route behind this server is now closed without a key, so a
      // listener without one could only ever return 403. Do not open it.
      debugPrint('[PosIngest] No connection key available; not listening.');
      PosCallbackConfig.baseUrl = null;
      return;
    }
    PosCallbackConfig.connectionKey = key;
    _callbackHost = await _resolveCallbackHost();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, defaultPort);
      _boundPort = _server!.port;
      PosCallbackConfig.baseUrl = callbackBaseUrl;
      _server!.listen(
        _handleRequest,
        onError: (e) => debugPrint('[PosIngest] Request error: $e'),
      );
      debugPrint('[PosIngest] Listening at ${PosCallbackConfig.baseUrl}');
    } catch (e) {
      debugPrint('[PosIngest] Failed to bind port $defaultPort: $e');
      PosCallbackConfig.baseUrl = null;
    }
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _boundPort = null;
    PosCallbackConfig.baseUrl = null;
  }

  static String? get callbackBaseUrl {
    final host = _callbackHost;
    final port = _boundPort ?? defaultPort;
    if (host == null || host.isEmpty) return null;
    return 'http://$host:$port';
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/health') {
        await _json(request, 200, {'ok': true, 'service': 'pos-ingest'});
        return;
      }

      if (!_isAuthorized(request)) {
        await _json(request, 403, {'error': 'invalid_connection_key'});
        return;
      }

      final body = await _readJsonBody(request);
      switch ('${request.method} $path') {
        case 'POST /mobile-order-update':
          await _apply(request, () => PosCommandApplier.updateOrder(body));
          return;
        case 'POST /mobile-order-cancel':
          await _apply(request, () => PosCommandApplier.cancelOrder(body));
          return;
        case 'POST /mobile-order-status':
          await _apply(
            request,
            () => PosCommandApplier.updateOrderStatus(body),
          );
          return;
        case 'POST /mobile-order-create':
          await _apply(
            request,
            () => PosCommandApplier.upsertTakeawayOrder(body),
          );
          return;
        case 'POST /mobile-walk-in-order-create':
          await _apply(
            request,
            () => PosCommandApplier.upsertDineInOrder(body),
          );
          return;
        case 'POST /mobile-order-print-check':
          await _apply(request, () => PosCommandApplier.printOrderCheck(body));
          return;
        case 'GET /mobile-reservations':
          await _handleReservationsList(request);
          return;
        case 'POST /mobile-reservation-create':
          await _apply(
            request,
            () => PosCommandApplier.createReservation(body),
          );
          return;
        case 'POST /mobile-reservation-status':
          await _apply(
            request,
            () => PosCommandApplier.updateReservationStatus(body),
          );
          return;
        case 'POST /mobile-reservation-delete':
          await _apply(
            request,
            () => PosCommandApplier.deleteReservation(body),
          );
          return;
        case 'POST /mobile-reservation-print-check':
          await _apply(
            request,
            () => PosCommandApplier.printReservationCheck(body),
          );
          return;
        case 'POST /mobile-counted-menu-print':
          await _apply(request, () => PosCommandApplier.printCountedMenu(body));
          return;
        case 'POST /mobile-expense-create':
          await _apply(request, () => PosCommandApplier.createExpense(body));
          return;
        case 'POST /mobile-user-create':
          await _apply(request, () => PosCommandApplier.createStaff(body));
          return;
        case 'POST /mobile-user-update-pin':
          await _apply(request, () => PosCommandApplier.updateStaffPin(body));
          return;
        case 'POST /mobile-user-update-role':
          await _apply(request, () => PosCommandApplier.updateStaffRole(body));
          return;
        case 'POST /mobile-user-rename':
          await _apply(request, () => PosCommandApplier.renameStaff(body));
          return;
        case 'POST /mobile-user-delete':
          await _apply(request, () => PosCommandApplier.deleteStaff(body));
          return;
        default:
          await _json(request, 404, {'error': 'not_found'});
      }
    } catch (e, st) {
      debugPrint('[PosIngest] Handler error: $e\n$st');
      await _json(request, 500, {'error': 'internal_error'});
    }
  }

  static bool _isAuthorized(HttpRequest request) {
    return isRequestAuthorized(
      expectedKey: DatabaseService.getPosIngestConnectionKey(),
      providedKey: request.headers.value('x-connection-key'),
    );
  }

  /// Whether a callback request may be served.
  ///
  /// This used to return true when the terminal held no connection key —
  /// intended as a convenience for an unprovisioned install, but the effect
  /// was that a POS which had somehow lost its key accepted every caller on
  /// the LAN, on routes that create orders, delete users and print. Missing
  /// configuration is now a refusal, not an exemption: no key means no access,
  /// and the key is provisioned by `start()` before the socket is bound.
  ///
  /// Split out as a pure function so the closed-by-default property is
  /// testable without a socket.
  @visibleForTesting
  static bool isRequestAuthorized({
    required String? expectedKey,
    required String? providedKey,
  }) {
    final expected = expectedKey?.trim();
    if (expected == null || expected.isEmpty) return false;
    final provided = providedKey?.trim();
    if (provided == null || provided.isEmpty) return false;
    return provided == expected;
  }

  static Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.trim().isEmpty) return {};
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  /// Applies one operation and answers with the outcome's status code.
  ///
  /// The behaviour itself lives in [PosCommandApplier], because the Edge
  /// command transport reaches the same operations by a different route and the
  /// two must not drift. This server's remaining job is the one it always had:
  /// read a request, apply it, write a status.
  ///
  /// The `treat*AsDone` reconciliations the Edge handlers use are deliberately
  /// NOT enabled here. This transport reports delivery, not execution — the
  /// backend outbox marks a row delivered on a 2xx — so a 404 for an order that
  /// is already gone stays a 404, exactly as it was before.
  static Future<void> _apply(
    HttpRequest request,
    Future<PosCommandOutcome> Function() operation,
  ) async {
    final outcome = await operation();
    if (outcome.ok) {
      await _json(request, 200, {'success': true, ...outcome.data});
      return;
    }
    await _json(request, outcome.httpStatus, {
      'error': outcome.code,
      if (outcome.detail != null) 'detail': outcome.detail,
    });
  }

  static Future<void> _handleReservationsList(HttpRequest request) async {
    final data = DatabaseService.getAllReservations()
        .map(DatabaseService.serializeReservationForSync)
        .toList();
    await _json(request, 200, {'data': data});
  }

  static Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  static Future<String?> _resolveCallbackHost() async {
    final override = dotenv.env['POS_CALLBACK_HOST']?.trim();
    if (override != null && override.isNotEmpty) return override;

    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue;
          return ip;
        }
      }
    } catch (e) {
      debugPrint('[PosIngest] Could not detect LAN IP: $e');
    }
    return InternetAddress.loopbackIPv4.address;
  }
}
