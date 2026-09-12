import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/pos_command_delivery.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/sync/mobile_edit_echo_guard.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/models/global_audit_entry.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/models/menu_recipe.dart';

/// Production-grade mobile API service.
///
/// Strategy: Network-first with retry → fallback to Hive cache on failure.
/// All requests carry the JWT Bearer token automatically.
///
/// Retry policy: up to 3 attempts with 1s/2s/4s delays (exponential backoff).
class MobileApiService {
  static String get _base => ApiConfig.baseUrl;

  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 12);

  // ── Internal HTTP helpers ──────────────────────────────────────────────────

  static Map<String, String> get _headers {
    final map = <String, String>{
      'Content-Type': 'application/json',
      ...AuthTokenService.authHeader,
    };
    final sid = MonitoringSocketService.monitoringSocketId;
    if (sid != null && sid.isNotEmpty) {
      map['X-Monitoring-Socket-Id'] = sid;
    }
    return map;
  }

  /// GET with retry + exponential backoff.
  static Future<http.Response> _get(String path) async {
    final uri = Uri.parse('$_base$path');
    Exception? lastError;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(_timeout);
        return response;
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = Exception(e.toString());
      }

      if (attempt < _maxRetries - 1) {
        await Future<void>.delayed(
          Duration(seconds: 1 << attempt),
        ); // 1s, 2s, 4s
      }
    }

    throw lastError ?? Exception('Unknown network error');
  }

  static Future<http.Response> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_base$path');
    return http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
  }

  static Future<http.Response> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_base$path');
    return http
        .patch(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
  }

  static Future<http.Response> _delete(String path) async {
    final uri = Uri.parse('$_base$path');
    return http.delete(uri, headers: _headers).timeout(_timeout);
  }

  /// Registers FCM device token (JWT required). Server uses it for offline push only.
  static Future<void> registerPushDevice(String fcmToken) async {
    final response = await _post('/mobile/push/register', {
      'fcmToken': fcmToken,
      'platform': Platform.operatingSystem,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        '[API] registerPushDevice ${response.statusCode}: ${response.body}',
      );
    }
  }

  static Future<void> unregisterPushDevice(String fcmToken) async {
    final response = await _post('/mobile/push/unregister', {
      'fcmToken': fcmToken,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        '[API] unregisterPushDevice ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Persisted manager notifications (while app was in background).
  static Future<List<Map<String, dynamic>>> getNotifications({
    String? since,
  }) async {
    final sinceParam = (since ?? '').trim();
    final path = sinceParam.isNotEmpty
        ? '/mobile/notifications?since=${Uri.encodeComponent(sinceParam)}'
        : '/mobile/notifications';
    final response = await _get(path);
    if (response.statusCode != 200) {
      debugPrint(
        '[API] notifications ${response.statusCode}: ${response.body}',
      );
      return const [];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<ManagerDashboardMetrics> getDashboard() async {
    try {
      final response = await _get('/mobile/dashboard');
      if (response.statusCode == 200) {
        final metrics = ManagerDashboardMetrics.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        await MobileCacheService.saveDashboard(metrics);
        if (metrics.businessDate != null) {
          MonitoringSocketService.currentBusinessDate.value =
              metrics.businessDate;
        }
        return metrics;
      }
      debugPrint('[API] Dashboard ${response.statusCode}: ${response.body}');
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      debugPrint('[API] getDashboard failed ($e), using cache');
      final cached = MobileCacheService.getCachedDashboard();
      if (cached != null) return cached;
      rethrow;
    }
  }

  // ── Tables ─────────────────────────────────────────────────────────────────

  static Future<List<TableModel>> getTables() async {
    try {
      final response = await _get('/mobile/tables');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        final tables = data
            .map((e) => TableModel.fromJson(e as Map<String, dynamic>))
            .toList();
        await MobileCacheService.saveTables(tables);
        return tables;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      debugPrint('[API] getTables failed ($e), using cache');
      final cached = MobileCacheService.getCachedTables();
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Force-frees a ghost table (emergency manager action).
  static Future<bool> freeTable(String tableNumber, String floor) async {
    try {
      final response = await _post(
        '/mobile/tables/$tableNumber/free?floor=${Uri.encodeComponent(floor)}',
        {},
      );
      final ok = response.statusCode == 200 || response.statusCode == 201;
      if (ok) {
        MobileEditEchoGuard.markTableEdited(tableNumber, floor);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ── Takeaway orders ────────────────────────────────────────────────────────

  static Future<List<Order>> getTakeawayOrders() async {
    final response = await _get('/mobile/takeaway-orders');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('getTakeawayOrders failed: ${response.statusCode}');
  }

  static Future<Order> createTakeawayOrder({
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await _post('/mobile/takeaway-orders', {
      'customerName': customerName,
      'pickupTime': pickupTime,
      'waiterName': waiterName,
      'items': items,
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      final order = Order.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      MobileEditEchoGuard.markOrderEdited(order.orderId);
      return order;
    }
    throw Exception(
      'createTakeawayOrder failed: ${response.statusCode} ${response.body}',
    );
  }

  /// Create a dine-in (walk-in) order on one or more tables of a single floor.
  static Future<Map<String, dynamic>> createWalkInOrder({
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<Map<String, dynamic>> items,
    int guestCount = 0,
  }) async {
    final response = await _post('/mobile/walk-in-orders', {
      'tableNumbers': tableNumbers,
      'floor': floor,
      'waiterName': waiterName,
      'guestCount': guestCount,
      'items': items,
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final posOrderId = (data['posOrderId'] as num?)?.toInt();
      if (posOrderId != null) {
        MobileEditEchoGuard.markOrderEdited(posOrderId);
      }
      for (final t in tableNumbers) {
        MobileEditEchoGuard.markTableEdited(t, floor);
      }
      return data;
    }
    throw Exception(
      'createWalkInOrder failed: ${response.statusCode} ${response.body}',
    );
  }

  static Future<void> deleteTakeawayOrder(int posOrderId) async {
    final uri = Uri.parse('$_base/mobile/takeaway-orders/$posOrderId');
    final response = await http
        .delete(uri, headers: _headers)
        .timeout(_timeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('deleteTakeawayOrder failed: ${response.statusCode}');
    }
    MobileEditEchoGuard.markOrderEdited(posOrderId);
  }

  // ── Staff performance ──────────────────────────────────────────────────────

  static Future<List<StaffMetric>> getStaffPerformance() async {
    try {
      final response = await _get('/mobile/staff-performance');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        final staff = data
            .map((e) => StaffMetric.fromJson(e as Map<String, dynamic>))
            .toList();
        await MobileCacheService.saveStaffPerformance(staff);
        return staff;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      debugPrint('[API] getStaffPerformance failed ($e), using cache');
      final cached = MobileCacheService.getCachedStaffPerformance();
      if (cached != null) return cached;
      rethrow;
    }
  }

  // ── Reservations ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getReservations({
    String? date,
  }) async {
    final query = (date != null && date.isNotEmpty) ? '?date=$date' : '';
    final response = await _get('/mobile/reservations$query');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw Exception('getReservations failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> createReservation({
    required String customerName,
    required String customerPhone,
    required List<int> tableNumbers,
    required String reservationDate,
    required String reservationTime,
    required int numberOfGuests,
    String? notes,
    String? createdBy,
    List<Map<String, dynamic>>? preOrderItems,
  }) async {
    final response = await _post('/mobile/reservations', {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'tableNumbers': tableNumbers,
      'reservationDate': reservationDate,
      'reservationTime': reservationTime,
      'numberOfGuests': numberOfGuests,
      'notes': notes,
      'createdBy': createdBy,
      'status': 'confirmed',
      'preOrderItems': preOrderItems ?? const [],
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('createReservation failed: ${response.statusCode}');
  }

  static Future<void> updateReservationStatus({
    required String reservationId,
    required String status,
  }) async {
    final response = await _post('/mobile/reservations/$reservationId/status', {
      'status': status,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('updateReservationStatus failed: ${response.statusCode}');
    }
  }

  static Future<void> deleteReservation(String reservationId) async {
    final response = await _delete('/mobile/reservations/$reservationId');
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('deleteReservation failed: ${response.statusCode}');
    }
  }

  /// Ask the backend to print the reservation check on the Windows POS.
  ///
  /// The manager client never prints directly, and Cloud does not print either:
  /// it records the request and the terminal claims it. The returned delivery
  /// says whether the POS has actually reported back — see
  /// [PosCommandDelivery] for why a 2xx alone stopped meaning "printed".
  static Future<PosCommandDelivery> printReservationCheck(
    String reservationId,
  ) async {
    final response = await _post(
      '/mobile/reservations/$reservationId/print-check',
      const {},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('printReservationCheck failed: ${response.statusCode}');
    }
    return _deliveryOf(response);
  }

  // ── Financials ─────────────────────────────────────────────────────────────

  /// Finance mutations carry a caller-generated UUID, retained across retries.
  /// Cloud confirms persistence; no optimistic/offline financial writes.
  static Future<Map<String, dynamic>> financeRead(String path) async {
    final response = await _get('/mobile/finance/$path');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('მონაცემები ვერ ჩაიტვირთა (${response.statusCode})');
  }

  static Future<void> financeWrite(
    String path,
    Map<String, dynamic> data, {
    bool update = false,
  }) async {
    final response = update
        ? await _patch('/mobile/finance/$path', data)
        : await _post('/mobile/finance/$path', data);
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final decoded = jsonDecode(response.body);
    throw Exception(
      decoded is Map
          ? decoded['message'] ?? 'შენახვა ვერ მოხერხდა'
          : 'შენახვა ვერ მოხერხდა (${response.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> getFinancials() async {
    try {
      final response = await _get('/mobile/financials');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await MobileCacheService.saveFinancials(data);
        return data;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      debugPrint('[API] getFinancials failed ($e), using cache');
      final cached = MobileCacheService.getCachedFinancials();
      if (cached != null) return cached;
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getFinancialSummary({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };
    final suffix = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    final response = await _get('/mobile/financial-summary$suffix');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('getFinancialSummary failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getSales({
    String? from,
    String? to,
    String? cursor,
    int limit = 30,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (cursor != null) 'cursor': cursor,
    };
    final response = await _get(
      '/mobile/sales?${Uri(queryParameters: params).query}',
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('getSales failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getSale(String id) async {
    final response = await _get('/mobile/sales/${Uri.encodeComponent(id)}');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('getSale failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getProductAnalytics({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };
    final suffix = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    final response = await _get('/mobile/product-analytics$suffix');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('getProductAnalytics failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getSaleStaffAnalytics({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };
    final suffix = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    final response = await _get('/mobile/sale-staff-analytics$suffix');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('getSaleStaffAnalytics failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> createExpense({
    required String description,
    required double amount,
    required String category,
    String paymentType = 'cash',
  }) async {
    final response = await _post('/mobile/expenses', {
      'description': description,
      'amount': amount,
      'category': category,
      'paymentType': paymentType,
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('createExpense failed: ${response.statusCode}');
  }

  static Future<void> deleteExpense(String id) async {
    final response = await _delete('/mobile/expenses/$id');
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('deleteExpense failed: ${response.statusCode}');
    }
  }

  // ── Orders (paginated) ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getOrders({
    int page = 1,
    int pageSize = 20,
    String? status,
  }) async {
    final query = StringBuffer('?page=$page&pageSize=$pageSize');
    if (status != null) query.write('&status=$status');
    final response = await _get('/mobile/orders$query');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Status ${response.statusCode}');
  }

  // ── Single order ───────────────────────────────────────────────────────────

  static Future<Order> getOrder(int posOrderId) async {
    final response = await _get('/mobile/order/$posOrderId');
    if (response.statusCode == 200) {
      return Order.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Status ${response.statusCode}');
  }

  // ── Update order ───────────────────────────────────────────────────────────

  static Future<void> updateOrder(Order order, {String? updatedBy}) async {
    final payload = order.toJson();
    if (updatedBy != null && updatedBy.trim().isNotEmpty) {
      payload['updatedBy'] = updatedBy.trim();
    }
    debugPrint('[API] updateOrder orderId=${order.orderId}');
    debugPrint('[API] updateOrder payload: ${jsonEncode(payload)}');
    final response = await _post('/mobile/order/${order.orderId}', payload);
    debugPrint(
      '[API] updateOrder response ${response.statusCode}: ${response.body}',
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Update failed: ${response.statusCode} ${response.body}');
    }
    MobileEditEchoGuard.markOrderEdited(order.orderId);
  }

  // ── Cancel order (manager-only) ────────────────────────────────────────────

  static Future<void> cancelOrder(int posOrderId) async {
    final response = await _post('/mobile/order/$posOrderId/cancel', {});
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Cancel failed: ${response.statusCode} ${response.body}');
    }
    MobileEditEchoGuard.markOrderEdited(posOrderId);
  }

  // ── Print order/table check (manager-only) ─────────────────────────────────

  /// Ask the backend to print the order/table check (customer pre-bill) on the
  /// Windows POS, the only print host. Not a mutation — no echo-guard marking.
  ///
  /// The returned delivery says whether the POS reported back inside the
  /// backend's bounded wait, or whether the request is still queued for a
  /// terminal that has not asked for it yet.
  static Future<PosCommandDelivery> printOrderCheck(int orderId) async {
    final response = await _post(
      '/mobile/order/$orderId/print-check',
      const {},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('printOrderCheck failed: ${response.statusCode}');
    }
    return _deliveryOf(response);
  }

  // ── Menu ───────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getMenu() async {
    try {
      final response = await _get('/mobile/menu');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        await MobileCacheService.saveMenu(data);
        return data;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      debugPrint('[API] getMenu failed ($e), using cache');
      final cached = MobileCacheService.getCachedMenu();
      if (cached != null) return cached;
      rethrow;
    }
  }

  // ── Restaurant settings ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getRestaurantSettings({
    bool throwOnFailure = false,
  }) async {
    try {
      final response = await _get('/mobile/restaurant-settings');
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      if (throwOnFailure) rethrow;
      debugPrint('[API] getRestaurantSettings failed ($e), using defaults');
      return {
        'serviceFeePercent': 10,
        'serviceFeeEnabled': false,
        'serviceFeeAvailable': false,
      };
    }
  }

  // ── Counted Menus (QuickOrderDrafts) ───────────────────────────────────────

  static Future<List<dynamic>> getCountedMenus() async {
    try {
      final response = await _get('/mobile/counted-menus');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        await MobileCacheService.saveCountedMenus(data);
        return data;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      debugPrint('[API] getCountedMenus failed ($e), using cache');
      final cached = MobileCacheService.getCachedCountedMenus();
      if (cached != null) return cached;
      rethrow;
    }
  }

  static Future<void> deleteCountedMenu(String draftId) async {
    final response = await _post('/mobile/counted-menu/$draftId/delete', {});
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Delete failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Ask the backend to print a counted menu on the Windows POS. The manager
  /// client never prints directly: the backend loads the draft and relays it to
  /// the POS callback path, and the Windows POS (the only print host) prints it
  /// on the receipt printer.
  static Future<PosCommandDelivery> printCountedMenu(String draftId) async {
    final response = await _post(
      '/mobile/counted-menu/$draftId/print',
      const {},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('printCountedMenu failed: ${response.statusCode}');
    }
    return _deliveryOf(response);
  }

  /// Reads the delivery block off a response body, tolerating anything.
  ///
  /// A malformed or absent body is [PosCommandDelivery.unknown], never an
  /// exception: the operation was accepted, and only the report on it is
  /// missing.
  static PosCommandDelivery _deliveryOf(http.Response response) {
    try {
      return PosCommandDelivery.fromResponse(json.decode(response.body));
    } catch (_) {
      return PosCommandDelivery.unknown;
    }
  }

  static Future<void> saveCountedMenu({
    required String name,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required bool includeServiceFee,
    required String createdBy,
  }) async {
    final payload = {
      'displayName': name,
      'items': items,
      'subtotal': subtotal,
      'includeServiceFee': includeServiceFee,
      'createdBy': createdBy,
    };
    final response = await _post('/mobile/counted-menu/save', payload);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Save failed: ${response.statusCode}');
    }
    // Refresh local cache after successful save
    await getCountedMenus();
  }

  /// Edit an existing counted menu in place (backend/Postgres only — not synced
  /// to the Windows POS). Mirrors [saveCountedMenu] but targets the update route.
  static Future<void> updateCountedMenu({
    required String draftId,
    required String name,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required bool includeServiceFee,
    double? serviceFeeRate,
  }) async {
    final payload = {
      'displayName': name,
      'items': items,
      'subtotal': subtotal,
      'includeServiceFee': includeServiceFee,
      if (serviceFeeRate != null) 'serviceFeeRate': serviceFeeRate,
    };
    final response = await _post(
      '/mobile/counted-menu/$draftId/update',
      payload,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('updateCountedMenu failed: ${response.statusCode}');
    }
    // Refresh local cache after successful update
    await getCountedMenus();
  }

  // ── Users (admin panel) ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getInventoryOverview() async {
    final response = await _get('/mobile/inventory/overview');
    if (response.statusCode != 200)
      throw Exception('მარაგების მიმოხილვა ვერ ჩაიტვირთა');
    return Map<String, dynamic>.from(json.decode(response.body) as Map);
  }

  static Future<List<StockItem>> getStockItems({String? search}) async {
    final query = search == null || search.trim().isEmpty
        ? ''
        : '?q=${Uri.encodeQueryComponent(search.trim())}';
    final response = await _get('/mobile/inventory/stock-items$query');
    if (response.statusCode != 200) {
      throw Exception(_apiError('Stock items', response));
    }
    return (jsonDecode(response.body) as List)
        .whereType<Map>()
        .map((row) => StockItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  static Future<StockItem> saveStockItem({
    String? id,
    String? requestId,
    required String name,
    String? sku,
    required InventoryUnit baseUnit,
    double? minimumStock,
    String? notes,
    required bool isActive,
    StockItemClassification? classification,
    List<String>? supplierIds,
    List<StockItemPurchaseUnit>? purchaseUnits,
  }) async {
    final payload = <String, dynamic>{
      if (requestId != null) 'requestId': requestId,
      'name': name,
      'sku': sku,
      'baseUnit': baseUnit.wireValue,
      if (classification != null) 'classification': classification.wireValue,
      if (supplierIds != null) 'supplierIds': supplierIds,
      'minimumStock': minimumStock,
      'notes': notes,
      'isActive': isActive,
      // Omitted entirely when the caller is not editing packaging, so a save
      // that says nothing about purchase units cannot silently clear them.
      if (purchaseUnits != null)
        'purchaseUnits': [
          for (final unit in purchaseUnits)
            {
              'unit': unit.unit.wireValue,
              'baseUnitMultiplier': unit.baseUnitMultiplier,
            },
        ],
    };
    final response = id == null
        ? await _post('/mobile/inventory/stock-items', payload)
        : await _patch('/mobile/inventory/stock-items/$id', payload);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Stock item', response));
    }
    return StockItem.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  /// One Stock Item with its derived balance and recent ledger movements.
  static Future<StockItemDetail> getStockItem(String id) async {
    final response = await _get(
      '/mobile/inventory/stock-items/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 200) {
      throw Exception(_apiError('Stock item', response));
    }
    return StockItemDetail.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  static Future<List<Supplier>> getSuppliers({String? search}) async {
    final query = search == null || search.trim().isEmpty
        ? ''
        : '?q=${Uri.encodeQueryComponent(search.trim())}';
    final response = await _get('/mobile/inventory/suppliers$query');
    if (response.statusCode != 200) {
      throw Exception(_apiError('Suppliers', response));
    }
    return (jsonDecode(response.body) as List)
        .whereType<Map>()
        .map((row) => Supplier.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  static Future<Supplier> saveSupplier({
    String? id,
    required String name,
    String? taxId,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required bool isActive,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'taxId': taxId,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'isActive': isActive,
    };
    final response = id == null
        ? await _post('/mobile/inventory/suppliers', payload)
        : await _patch('/mobile/inventory/suppliers/$id', payload);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Supplier', response));
    }
    return Supplier.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  static Future<Map<String, dynamic>> getSupplierDetail(String id) async {
    final response = await _get(
      '/mobile/inventory/suppliers/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 200)
      throw Exception(_apiError('მომწოდებელი', response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<Map<String, dynamic>> procurementRequest(
    String path, [
    Map<String, dynamic>? payload,
  ]) async {
    final response = payload == null
        ? await _get('/mobile/inventory/$path')
        : await _post('/mobile/inventory/$path', payload);
    if (response.statusCode != 200 && response.statusCode != 201)
      throw Exception(_apiError('მარაგები', response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<void> setSupplierProduct(
    String supplierId,
    String stockItemId,
    bool linked,
  ) async {
    final path =
        '/mobile/inventory/suppliers/${Uri.encodeComponent(supplierId)}/products/${Uri.encodeComponent(stockItemId)}';
    final response = linked ? await _post(path, {}) : await _delete(path);
    if (response.statusCode != 200 && response.statusCode != 201)
      throw Exception(_apiError('მომწოდებლის პროდუქტი', response));
  }

  // ── Receiving / waybills ──────────────────────────────────────────────

  static Future<ReceivingPage> getReceivings({
    String? from,
    String? to,
    String? supplierId,
    String? status,
    String? search,
    int? take,
    String? cursor,
  }) async {
    final params = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (supplierId != null && supplierId.isNotEmpty) 'supplierId': supplierId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
      if (take != null) 'take': '$take',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
    final response = await _get('/mobile/inventory/receivings$query');
    if (response.statusCode != 200) {
      throw Exception(_apiError('Receivings', response));
    }
    return ReceivingPage.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  static Future<Receiving> getReceiving(String id) async {
    final response = await _get(
      '/mobile/inventory/receivings/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 200) {
      throw Exception(_apiError('Receiving', response));
    }
    return _receiving(response);
  }

  /// Creates or replaces a draft. Cloud refuses to edit anything else, so a
  /// posted document can never be rewritten through this path.
  static Future<Receiving> saveReceivingDraft({
    String? id,
    String? requestId,
    String? dueDate,
    required String supplierId,
    String sourceType = 'SUPPLIER',
    String? sourceLabel,
    required String documentDate,
    String? businessDate,
    String? waybillNumber,
    String? invoiceNumber,
    String? notes,
    DateTime? receivedAt,
    required List<Map<String, dynamic>> lines,
  }) async {
    final payload = <String, dynamic>{
      if (requestId != null) 'requestId': requestId,
      if (dueDate != null && dueDate.isNotEmpty) 'dueDate': dueDate,
      'supplierId': sourceType == 'SELF_PURCHASE' ? null : supplierId,
      'sourceType': sourceType,
      if (sourceLabel != null) 'sourceLabel': sourceLabel,
      'documentDate': documentDate,
      if (businessDate != null) 'businessDate': businessDate,
      'waybillNumber': waybillNumber,
      'invoiceNumber': invoiceNumber,
      'notes': notes,
      if (receivedAt != null)
        'receivedAt': receivedAt.toUtc().toIso8601String(),
      'lines': lines,
    };
    final response = id == null
        ? await _post('/mobile/inventory/receivings', payload)
        : await _patch(
            '/mobile/inventory/receivings/${Uri.encodeComponent(id)}',
            payload,
          );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Receiving', response));
    }
    return _receiving(response);
  }

  static Future<void> deleteReceivingDraft(String id) async {
    final response = await _delete(
      '/mobile/inventory/receivings/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(_apiError('Receiving', response));
    }
  }

  /// Posting is idempotent server-side; a redelivered request returns the
  /// same document rather than moving stock again.
  static Future<Receiving> postReceiving(String id) async {
    final response = await _post(
      '/mobile/inventory/receivings/${Uri.encodeComponent(id)}/post',
      const <String, dynamic>{},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Receiving', response));
    }
    return _receiving(response);
  }

  static Future<Receiving> cancelReceiving(String id, {String? reason}) async {
    final response = await _post(
      '/mobile/inventory/receivings/${Uri.encodeComponent(id)}/cancel',
      <String, dynamic>{'reason': reason},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Receiving', response));
    }
    return _receiving(response);
  }

  // ── Recipes / technological cards ─────────────────────────────────────

  /// Menu-oriented: every Menu Item, marked configured or not.
  static Future<List<Map<String, dynamic>>> getConsumptions({
    String? from,
    String? to,
    bool unmapped = false,
  }) async {
    final query = Uri(
      queryParameters: {
        'unmapped': '$unmapped',
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
    ).query;
    final response = await _get('/mobile/inventory/consumptions?$query');
    if (response.statusCode != 200)
      throw Exception(_apiError('Consumption history', response));
    return (jsonDecode(response.body) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> getConsumption(String id) async {
    final response = await _get(
      '/mobile/inventory/consumptions/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 200)
      throw Exception(_apiError('Consumption detail', response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<List<RecipeMenuItem>> getRecipeMenuItems({
    String? search,
    String? status,
  }) async {
    final params = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
    final response = await _get('/mobile/inventory/recipes$query');
    if (response.statusCode != 200) {
      throw Exception(_apiError('Recipes', response));
    }
    return (jsonDecode(response.body) as List)
        .whereType<Map>()
        .map((row) => RecipeMenuItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  /// The definition for one product. `recipe` is null when none is configured.
  static Future<MenuRecipeDetail> getRecipe(
    String menuItemId, {
    String? variantId,
  }) async {
    final query = variantId == null || variantId.isEmpty
        ? ''
        : '?variantId=${Uri.encodeQueryComponent(variantId)}';
    final response = await _get(
      '/mobile/inventory/recipes/menu-item/${Uri.encodeComponent(menuItemId)}$query',
    );
    if (response.statusCode != 200) {
      throw Exception(_apiError('Recipe', response));
    }
    return MenuRecipeDetail.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  /// Creates or replaces the one definition for this Menu Item + variant.
  /// Components are a declared set: sending them without an ingredient is how
  /// that ingredient is removed.
  static Future<MenuRecipe> saveRecipe({
    required String menuItemId,
    String? variantId,
    String? yieldQuantity,
    String? notes,
    required List<Map<String, dynamic>> components,
  }) async {
    final response = await _post('/mobile/inventory/recipes', <String, dynamic>{
      'menuItemId': menuItemId,
      'variantId': variantId,
      if (yieldQuantity != null) 'yieldQuantity': yieldQuantity,
      'notes': notes,
      'components': components,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Recipe', response));
    }
    return MenuRecipe.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  /// Stops applying a definition. Cloud keeps the card; disabling is
  /// idempotent, so a repeated request changes nothing.
  static Future<MenuRecipe> disableRecipe(String id) async {
    final response = await _post(
      '/mobile/inventory/recipes/${Uri.encodeComponent(id)}/disable',
      const <String, dynamic>{},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_apiError('Recipe', response));
    }
    return MenuRecipe.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  static Receiving _receiving(http.Response response) {
    return Receiving.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  static String _apiError(String fallback, http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        final message = decoded['message'];
        return message is List ? message.join(', ') : message.toString();
      }
    } catch (error) {
      debugPrint('[Manager API] Could not decode error response: $error');
    }
    return '$fallback request failed (${response.statusCode})';
  }

  // ── Users (admin panel) ───────────────────────────────────────────────────

  static Future<List<dynamic>> getUsers() async {
    final response = await _get('/mobile/users');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Status ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> createUser({
    required String username,
    required String pinCode,
    required String role,
  }) async {
    final response = await _post('/mobile/users', {
      'username': username,
      'pinCode': pinCode,
      'role': role,
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'createUser failed: ${response.statusCode} ${response.body}',
    );
  }

  static Future<void> renameUser({
    required String oldUsername,
    required String newUsername,
  }) async {
    final response = await _patch('/mobile/users/$oldUsername', {
      'username': newUsername,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'renameUser failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> updateUserPin({
    required String username,
    required String pinCode,
  }) async {
    final response = await _post('/mobile/users/$username/pin', {
      'pinCode': pinCode,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'updateUserPin failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> updateUserRole({
    required String username,
    required String role,
  }) async {
    final response = await _post('/mobile/users/$username/role', {
      'role': role,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'updateUserRole failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> deleteUser(String username) async {
    final response = await _delete('/mobile/users/$username');
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'deleteUser failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ── Audit log ─────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getAuditReports({
    int? year,
    int? month,
    String? status,
    bool allHistory = false,
  }) async {
    final query = StringBuffer('?');
    if (year != null) query.write('year=$year&');
    if (month != null) query.write('month=$month&');
    if (allHistory) query.write('all=1&');
    if (status != null) query.write('status=$status');
    final response = await _get('/mobile/audit$query');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Status ${response.statusCode}');
  }

  /// The venue-wide audit feed: staff, menu, packages, expenses, close day,
  /// backups, settings and the business date.
  ///
  /// Newest first and keyset-paginated — pass the previous response's
  /// `nextCursor` to continue rather than an offset, so a row written while
  /// the manager scrolls cannot shift the window.
  static Future<({List<GlobalAuditEntry> items, String? nextCursor})>
  getGlobalAuditLog({
    String? from,
    String? to,
    String? action,
    String? entityType,
    String? entityId,
    String? actor,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (action != null && action.isNotEmpty) 'action': action,
      if (entityType != null && entityType.isNotEmpty) 'entityType': entityType,
      if (entityId != null && entityId.isNotEmpty) 'entityId': entityId,
      if (actor != null && actor.isNotEmpty) 'actor': actor,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    final response = await _get('/mobile/audit-log?$query');
    if (response.statusCode != 200) {
      throw Exception('Status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['items'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => GlobalAuditEntry.fromCloud(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
    return (items: items, nextCursor: body['nextCursor'] as String?);
  }

  /// The actions and entity types this Venue has actually recorded, for the
  /// filter chips. Offering a filter that can only ever return nothing is
  /// worse than offering none.
  static Future<({List<String> actions, List<String> entityTypes})>
  getGlobalAuditLogFacets() async {
    final response = await _get('/mobile/audit-log/facets');
    if (response.statusCode != 200) {
      throw Exception('Status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      actions: (body['actions'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => (row['action'] ?? '').toString())
          .where((action) => action.isNotEmpty)
          .toList(growable: false),
      entityTypes: (body['entityTypes'] as List? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  // ── Sales report ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSalesReport({
    String period = 'today',
    String? month,
  }) async {
    final query = StringBuffer('?period=$period');
    if (month != null && month.isNotEmpty) {
      query.write('&month=$month');
    }
    final response = await _get('/mobile/sales-report$query');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Status ${response.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> getSalesDaily({
    String? month,
  }) async {
    final query = (month != null && month.isNotEmpty) ? '?month=$month' : '';
    final response = await _get('/mobile/sales-daily$query');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw Exception('getSalesDaily failed: ${response.statusCode}');
  }

  // ── Top items ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getTopItems({int limit = 10}) async {
    try {
      final response = await _get('/mobile/top-items?limit=$limit');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        await MobileCacheService.saveTopItems(data);
        return data;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      final cached = MobileCacheService.getCachedTopItems();
      if (cached != null) return cached;
      rethrow;
    }
  }
}
