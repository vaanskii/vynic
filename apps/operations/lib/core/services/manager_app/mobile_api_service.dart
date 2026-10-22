import 'manager_data_read.dart';
import '../../models/inventory_history_page.dart';
import 'manager_operation_request.dart';
import 'table_repair_request.dart';
import 'order_edit_request.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'manager_entitlements.dart';
import 'manager_notification_page.dart';
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

  static final Map<String, Future<Object>> _readFlights = {};
  static final Expando<ManagerReadStatus> _dataStatuses = Expando();
  static Future<T> _readData<T extends Object>(
    String key,
    String path,
    T Function(dynamic) parse,
  ) async {
    final scope = tableRepairScope;
    final session = AuthTokenService.authHeader['Authorization'];
    final headers = Map<String, String>.from(_headers);
    final uri = Uri.parse('$_base$path');
    final identity = '$scope:$session:$path';
    ManagerDataReads.activate(scope);
    void requireSession() {
      if (!isCurrentTableRepairScope(scope) ||
          session != AuthTokenService.authHeader['Authorization'])
        throw StateError('Manager session changed');
    }

    Future<T> perform() async {
      http.Response? response;
      Object? failure;
      for (var attempt = 0; attempt < _maxRetries; attempt++) {
        requireSession();
        try {
          response = await http.get(uri, headers: headers).timeout(_timeout);
          requireSession();
          break;
        } catch (e) {
          requireSession();
          failure = e;
          if (attempt < _maxRetries - 1)
            await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
      requireSession();
      final cached = MobileCacheService.cachedRead(scope, path);
      if (response?.statusCode == 200) {
        try {
          final json = jsonDecode(response!.body);
          final data = parse(json);
          Map<String, dynamic> stamp = {};
          final header = response.headers['x-vynic-data-freshness'];
          if (header != null)
            stamp = Map<String, dynamic>.from(jsonDecode(header) as Map);
          if (json is Map) {
            final provenance =
                json['financialProvenance'] ?? json['provenance'];
            if (provenance == 'PARTIAL' || provenance == 'LEGACY_FALLBACK')
              stamp['completeness'] = provenance;
          }
          var status = ManagerReadStatus.fromJson(key, {
            ...stamp,
            'location': 'api',
            'fetchedAt': DateTime.now().toUtc().toIso8601String(),
            'apiAvailable': true,
            'query': path,
          });
          requireSession();
          try {
            await MobileCacheService.saveRead(
              scope,
              path,
              json as Object,
              status,
            );
          } catch (_) {
            // Remote data is valid even when local persistence fails. Never serve
            // an optimistic Hive memory write as a durable cache on the next failure.
            status = ManagerReadStatus.fromJson(key, {
              ...status.toJson(),
              'error':
                  'ქეში ვერ შეინახა; ინტერნეტის გარეშე ეს განახლება მიუწვდომელია.',
            });
          }
          requireSession();
          ManagerDataReads.publish(scope, status);
          _dataStatuses[data] = status;
          MonitoringSocketService.apiError.value = ManagerDataReads.hasApiError;
          return data;
        } catch (e) {
          requireSession();
          failure = e;
        }
      }
      final message = response == null
          ? 'API მიუწვდომელია — მონაცემები ვერ განახლდა.'
          : response.statusCode == 200
          ? 'API მონაცემები ვერ წაიკითხა — განახლება არ მიღებულა.'
          : 'API შეცდომა (${response.statusCode}) — მონაცემები ვერ განახლდა.';
      if (cached != null &&
          response?.statusCode != 401 &&
          response?.statusCode != 403) {
        try {
          final value = parse(cached['data']);
          final status =
              ManagerReadStatus.fromJson(
                key,
                Map<String, dynamic>.from(cached['status'] as Map),
              ).failed(
                message,
                location: 'cache',
                httpStatus: response?.statusCode,
              );
          requireSession();
          ManagerDataReads.publish(scope, status);
          _dataStatuses[value] = status;
          MonitoringSocketService.apiError.value = ManagerDataReads.hasApiError;
          return value;
        } catch (e) {
          requireSession();
          failure = e;
        }
      }
      final unavailable = ManagerReadStatus(
        key: key,
        query: path,
        error: message,
        httpStatus: response?.statusCode,
      );
      ManagerDataReads.publish(scope, unavailable);
      MonitoringSocketService.apiError.value = true;
      // Diagnostic details remain in developer logs; release UI receives safe copy.
      debugPrint('[Manager read $key] $failure');
      throw ManagerReadFailure(unavailable);
    }

    final existing = _readFlights[identity];
    if (existing != null) return await existing as T;
    final future = perform();
    _readFlights[identity] = future;
    try {
      return await future;
    } finally {
      if (identical(_readFlights[identity], future))
        _readFlights.remove(identity);
    }
  }

  static Future<ManagerDataRead<T>> captureRead<T>(
    String key,
    Future<T> Function() fetch,
  ) async {
    final scope = tableRepairScope;
    T? data;
    ManagerReadStatus? failure;
    try {
      data = await fetch();
    } catch (e) {
      if (!isCurrentTableRepairScope(scope)) rethrow;
      if (e is ManagerReadFailure) failure = e.status;
    }
    if (!isCurrentTableRepairScope(scope))
      throw StateError('Manager session changed');
    return ManagerDataRead(
      data,
      (data == null ? failure : _dataStatuses[data as Object]) ??
          ManagerDataReads.statuses.value[key] ??
          ManagerReadStatus(key: key, error: 'მონაცემები მიუწვდომელია.'),
    );
  }

  static ManagerReadStatus? statusFor(Object data) => _dataStatuses[data];

  static void releaseReadStatuses(Iterable<ManagerReadStatus> reads) {
    ManagerDataReads.release(tableRepairScope, reads);
    MonitoringSocketService.apiError.value = ManagerDataReads.hasApiError;
  }

  // Network exceptions may contain endpoint/IP details. Keep them out of release UI.
  static Never _throwNetworkError(Object error, StackTrace stack) {
    if (ApiConfig.allowDeveloperOverride)
      Error.throwWithStackTrace(error, stack);
    throw Exception('სერვერთან კავშირი ვერ დამყარდა. გადაამოწმეთ ინტერნეტი.');
  }

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

  static Future<void> saveVenueProfile(Map<String, dynamic> profile) async {
    final response = await http
        .put(
          Uri.parse('$_base/mobile/venue-profile'),
          headers: _headers,
          body: jsonEncode(profile),
        )
        .timeout(_timeout)
        .catchError(_throwNetworkError);
    if (response.statusCode != 200)
      throw Exception('პროფილი ვერ შეინახა (${response.statusCode})');
    ManagerEntitlements.profile.value =
        jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> refreshEntitlements() async {
    final session = AuthTokenService.authHeader['Authorization'];
    final response = await _get('/mobile/entitlements');
    if (session != AuthTokenService.authHeader['Authorization']) return;
    if (response.statusCode != 200) {
      ManagerEntitlements.clear();
      await MobileCacheService.clear();
      throw Exception('წვდომა ვერ განახლდა (${response.statusCode})');
    }
    final old = ManagerEntitlements.features.value;
    ManagerEntitlements.apply(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (!setEquals(old, ManagerEntitlements.features.value))
      await MobileCacheService.clear();
  }

  /// GET with retry + exponential backoff.
  static Future<http.Response> _get(String path) async {
    final uri = Uri.parse('$_base$path');
    Exception? lastError;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(_timeout)
            .catchError(_throwNetworkError);
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
        .timeout(_timeout)
        .catchError(_throwNetworkError);
  }

  static Future<http.Response> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_base$path');
    return http
        .patch(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout)
        .catchError(_throwNetworkError);
  }

  static Future<http.Response> _delete(String path) async {
    final uri = Uri.parse('$_base$path');
    return http
        .delete(uri, headers: _headers)
        .timeout(_timeout)
        .catchError(_throwNetworkError);
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
  static Future<ManagerNotificationPage> getNotificationsPage({
    String? since,
    String? cursor,
  }) async {
    final query = Uri(queryParameters: {
      if (since != null) 'since': since,
      if (cursor != null) 'cursor': cursor,
    }).query;
    final response = await _get('/mobile/notifications/page?$query');
    if (response.statusCode != 200)
      throw HttpException('Notification catch-up failed (${response.statusCode})');
    return ManagerNotificationPage.fromJson(jsonDecode(response.body));
  }

  /// Legacy array response retained for compatible callers.
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
    final value = await _readData('dashboard', '/mobile/dashboard', (json) {
      final map = Map<String, dynamic>.from(json as Map);
      for (final key in ['todayRevenue', 'openTablesPayable', 'totalTables']) {
        if (map[key] is! num)
          throw const FormatException('Incomplete dashboard response');
      }
      return ManagerDashboardMetrics.fromJson(map);
    });
    MonitoringSocketService.currentBusinessDate.value = value.businessDate;
    return value;
  }

  // ── Tables ─────────────────────────────────────────────────────────────────

  static Future<List<TableModel>> getTables() => _readData(
    'tables',
    '/mobile/tables',
    (json) => (json as List)
        .map((e) => TableModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  static String get tableRepairScope {
    final token = AuthTokenService.token;
    if (token == null || AuthTokenService.username == null)
      throw StateError('Manager authentication is required');
    final pieces = token.split('.');
    if (pieces.length != 3)
      throw const FormatException('Invalid Manager session');
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))),
    );
    if (claims is! Map) throw const FormatException('Invalid Manager claims');
    final subject = claims['sub'];
    if (subject is! String || subject.isEmpty)
      throw const FormatException('Missing Manager principal');
    // Namespacing only; the server derives all actual authority from Staff.
    return TableRepairRequests.scope(
      _base,
      jsonEncode([subject, AuthTokenService.venueCode]),
    );
  }

  static bool isCurrentTableRepairScope(String scope) {
    try {
      return tableRepairScope == scope;
    } on StateError {
      return false;
    } on FormatException {
      return false;
    }
  }

  static Future<TableRepairResult> freeTable(
    String tableNumber,
    String floor, {
    bool refresh = false,
    String? expectedScope,
  }) {
    final String scope;
    const changed = TableRepairResult(
      delivery: PosCommandDelivery.failed,
      code: 'session_changed',
    );
    try {
      scope = tableRepairScope;
    } on StateError {
      return Future.value(changed);
    } on FormatException {
      return Future.value(changed);
    }
    if (expectedScope != null && scope != expectedScope)
      return Future.value(changed);
    return TableRepairRequests.submit(
      scope: scope,
      number: tableNumber,
      floor: floor,
      refresh: refresh,
      send: (body) {
        if (tableRepairScope != scope)
          throw StateError('Manager session changed before repair request');
        return _post(
          '/mobile/tables/${Uri.encodeComponent(tableNumber)}/free?floor=${Uri.encodeComponent(floor)}',
          body,
        );
      },
    );
  }

  // ── Takeaway orders ────────────────────────────────────────────────────────

  static Future<List<Order>> getTakeawayOrders() => _readData(
    'takeaway',
    '/mobile/takeaway-orders',
    (json) => (json as List)
        .map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  static Future<ManagerOperationResult> createTakeawayOrder({
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<Map<String, dynamic>> items,
    String? expectedScope,
    bool newRequest = false,
  }) => _operation(
    'takeaway_create',
    'takeaway_create',
    {'customerName': customerName, 'pickupTime': pickupTime, 'items': items},
    expectedScope: expectedScope,
    newRequest: newRequest,
  );

  /// Create a dine-in (walk-in) order on one or more tables of a single floor.
  static Future<ManagerOperationResult> createWalkInOrder({
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<Map<String, dynamic>> items,
    int guestCount = 0,
    String? expectedScope,
    bool newRequest = false,
  }) => _operation(
    'dine_in_create',
    'dine_in_create',
    {
      'tableNumbers': tableNumbers,
      'floor': floor,
      'items': items,
      'guestCount': guestCount,
    },
    expectedScope: expectedScope,
    newRequest: newRequest,
  );

  static Future<ManagerOperationResult> deleteTakeawayOrder(
    int posOrderId, {
    String? expectedScope,
  }) => _operation('takeaway_cancel', 'order_cancel:$posOrderId', {
    'posOrderId': posOrderId,
  }, expectedScope: expectedScope);

  static Future<ManagerOperationResult> _operation(
    String kind,
    String slot,
    Map<String, dynamic> body, {
    String? expectedScope,
    bool refresh = false,
    bool newRequest = false,
  }) {
    final String scope;
    try {
      scope = tableRepairScope;
    } catch (_) {
      return Future.value(
        const ManagerOperationResult(
          PosCommandDelivery.failed,
          code: 'session_changed',
        ),
      );
    }
    if (expectedScope == null || expectedScope != scope)
      return Future.value(
        const ManagerOperationResult(
          PosCommandDelivery.failed,
          code: 'session_changed',
        ),
      );
    return ManagerOperationRequests.submit(
      scope: scope,
      slot: slot,
      kind: kind,
      body: body,
      refresh: refresh,
      newRequest: newRequest,
      currentSession: () => isCurrentTableRepairScope(scope),
      exchange: (request, statusOnly) {
        if (!isCurrentTableRepairScope(scope))
          throw StateError('Manager session changed');
        if (statusOnly)
          return http
              .get(
                Uri.parse(
                  '$_base/mobile/operation-requests/${request['requestId']}',
                ),
                headers: _headers,
              )
              .timeout(_timeout);
        return _post('/mobile/operation-requests/${request['kind']}', {
          'requestId': request['requestId'],
          'body': request['body'],
        });
      },
    );
  }

  static Future<ManagerOperationResult> refreshOperation(
    Map<String, dynamic> request,
  ) => _operation(
    request['kind'],
    request['slot'],
    Map<String, dynamic>.from(request['body']),
    expectedScope: request['scope'],
    refresh: true,
  );

  // ── Staff performance ──────────────────────────────────────────────────────

  static Future<List<StaffMetric>> getStaffPerformance({
    String? from,
    String? to,
  }) => _readData(
    'staff_performance',
    '/mobile/staff-performance${from == null ? '' : '?${Uri(queryParameters: {'from': from, if (to != null) 'to': to}).query}'}',
    (json) => (json as List)
        .map((e) => StaffMetric.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  // ── Reservations ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getReservations({
    String? date,
  }) async {
    final query = (date != null && date.isNotEmpty) ? '?date=$date' : '';
    return _readData(
      'reservations',
      '/mobile/reservations$query',
      (json) => (json as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  static Future<ManagerOperationResult> createReservation({
    required String customerName,
    required String customerPhone,
    required List<int> tableNumbers,
    required String reservationDate,
    required String reservationTime,
    required int numberOfGuests,
    String? notes,
    String? createdBy,
    List<Map<String, dynamic>>? preOrderItems,
    String? expectedScope,
    bool newRequest = false,
  }) => _operation(
    'reservation_create',
    'reservation_create',
    {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'tableNumbers': tableNumbers,
      'reservationDate': reservationDate,
      'reservationTime': reservationTime,
      'numberOfGuests': numberOfGuests,
      'notes': notes ?? '',
      'preOrderItems': preOrderItems ?? [],
    },
    expectedScope: expectedScope,
    newRequest: newRequest,
  );

  static Future<ManagerOperationResult> updateReservationStatus({
    required String reservationId,
    required String status,
    String? expectedScope,
  }) => _operation('reservation_status', 'reservation:$reservationId', {
    'reservationId': reservationId,
    'status': status,
  }, expectedScope: expectedScope);

  static Future<ManagerOperationResult> deleteReservation(
    String reservationId, {
    String? expectedScope,
  }) => _operation('reservation_delete', 'reservation:$reservationId', {
    'reservationId': reservationId,
  }, expectedScope: expectedScope);

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
    final scope = tableRepairScope, token = AuthTokenService.token;
    final uri = Uri.parse('$_base/mobile/finance/$path');
    final headers = Map<String, String>.from(_headers);
    void requireSession() {
      if (!isCurrentTableRepairScope(scope) ||
          AuthTokenService.token != token) {
        throw StateError('სესია შეიცვალა — განაახლეთ ისტორია');
      }
    }

    http.Response? result;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      requireSession();
      try {
        result = await http.get(uri, headers: headers).timeout(_timeout);
        requireSession();
        break;
      } catch (_) {
        requireSession();
        if (attempt == _maxRetries - 1) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    requireSession();
    final response = result!;
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

  /// One captured authenticated Cloud request. The correction store owns the
  /// retained UUID and receipt validation; retries are deliberate, never offline.
  static Future<Map<String, dynamic>> financeCorrectionWrite(
    String path,
    Map<String, dynamic> body,
  ) async {
    final scope = tableRepairScope, token = AuthTokenService.token;
    final uri = Uri.parse('$_base/mobile/finance/$path');
    final headers = Map<String, String>.from(_headers);
    void requireSession() {
      if (!isCurrentTableRepairScope(scope) ||
          AuthTokenService.token != token) {
        throw StateError('სესია შეიცვალა — განაახლეთ ისტორია');
      }
    }

    requireSession();
    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    requireSession();
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded is Map
            ? decoded['message'] ?? 'კორექტირება ვერ შესრულდა'
            : 'კორექტირება ვერ შესრულდა (${response.statusCode})',
      );
    }
    if (decoded is! Map)
      throw const FormatException('კორექტირების შედეგი ვერ დადასტურდა');
    return Map<String, dynamic>.from(decoded);
  }

  static Future<Map<String, dynamic>> getFinancials() => _readData(
    'financials',
    '/mobile/financials',
    (json) => Map<String, dynamic>.from(json as Map),
  );

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
    return _readData(
      'ledger_summary',
      '/mobile/financial-summary$suffix',
      (json) => Map<String, dynamic>.from(json as Map),
    );
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
    return _readData(
      'sale_history',
      '/mobile/sales?${Uri(queryParameters: params).query}',
      (json) => Map<String, dynamic>.from(json as Map),
    );
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
    return _readData(
      'product_analytics',
      '/mobile/product-analytics$suffix',
      (json) => Map<String, dynamic>.from(json as Map),
    );
  }

  static Future<Map<String, dynamic>> getSaleStaffAnalytics({
    String? from,
    String? to,
    String? attribution,
  }) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (attribution != null) 'attribution': attribution,
    };
    final suffix = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    return _readData(
      'sale_staff',
      '/mobile/sale-staff-analytics$suffix',
      (json) => Map<String, dynamic>.from(json as Map),
    );
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
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['editProjection'] is Map
          ? OrderEditProjection.read(
              Map<String, dynamic>.from(body['editProjection']),
            )
          : Order.fromJson(body);
    }
    throw Exception('Status ${response.statusCode}');
  }

  // ── Update order ───────────────────────────────────────────────────────────

  static Future<OrderEditResult> updateOrder(
    Order order, {
    String? updatedBy,
    String? expectedScope,
  }) {
    final String scope;
    try {
      scope = tableRepairScope;
    } catch (_) {
      return Future.value(
        const OrderEditResult(
          PosCommandDelivery.failed,
          code: 'session_changed',
        ),
      );
    }
    if (expectedScope != null && scope != expectedScope)
      return Future.value(
        const OrderEditResult(
          PosCommandDelivery.failed,
          code: 'session_changed',
        ),
      );
    return OrderEditRequests.submit(
      scope: scope,
      order: order,
      currentSession: () => isCurrentTableRepairScope(scope),
      send: (body) =>
          _post('/mobile/order/${order.orderId}/edit-request', body),
    );
  }

  // ── Cancel order (manager-only) ────────────────────────────────────────────

  static Future<ManagerOperationResult> cancelOrder(
    int posOrderId, {
    String? expectedScope,
  }) => _operation('order_cancel', 'order_cancel:$posOrderId', {
    'posOrderId': posOrderId,
  }, expectedScope: expectedScope);

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

  static Future<List<dynamic>> getMenu() =>
      _readData('menu', '/mobile/menu', (json) => json as List<dynamic>);

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

  static Future<List<dynamic>> getCountedMenus() => _readData(
    'counted_menus',
    '/mobile/counted-menus',
    (json) => json as List<dynamic>,
  );

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
    double? serviceFeeRate,
  }) async {
    final payload = {
      'displayName': name,
      'items': items,
      'subtotal': subtotal,
      'includeServiceFee': includeServiceFee,
      'createdBy': createdBy,
      if (serviceFeeRate != null) 'serviceFeeRate': serviceFeeRate,
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
  static Future<void> setStockItemActive(String id, bool active) async {
    final response = await _patch(
      '/mobile/inventory/stock-items/${Uri.encodeComponent(id)}',
      {'isActive': active},
    );
    if (response.statusCode != 200)
      throw Exception(_apiError('პროდუქტის სტატუსი', response));
  }

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
  static Future<InventoryHistoryPage> getInventoryHistoryPage({
    String? stockItemId,
    String? from,
    String? to,
    bool unmapped = false,
    String? cursor,
  }) async {
    final scope = tableRepairScope;
    final session = AuthTokenService.authHeader['Authorization'];
    final path = stockItemId == null
        ? '/mobile/inventory/consumptions/page'
        : '/mobile/inventory/stock-items/${Uri.encodeComponent(stockItemId)}/movements';
    final query = Uri(
      queryParameters: {
        'unmapped': '$unmapped',
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (cursor != null) 'cursor': cursor,
      },
    ).query;
    final response = await _get('$path?$query');
    if (!isCurrentTableRepairScope(scope) ||
        session != AuthTokenService.authHeader['Authorization'])
      throw StateError('Manager session changed');
    if (response.statusCode != 200)
      throw Exception(_apiError('Inventory history', response));
    return InventoryHistoryPage.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

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
  }) => _readData(
    'sales_report',
    '/mobile/sales-report?period=${Uri.encodeQueryComponent(period)}${month == null || month.isEmpty ? '' : '&month=${Uri.encodeQueryComponent(month)}'}',
    (json) => Map<String, dynamic>.from(json as Map),
  );

  static Future<List<Map<String, dynamic>>> getSalesDaily({
    String? month,
  }) => _readData(
    'sales_daily',
    '/mobile/sales-daily${month == null || month.isEmpty ? '' : '?month=${Uri.encodeQueryComponent(month)}'}',
    (json) =>
        (json as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
  );

  // ── Top items ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getTopItems({int limit = 10}) => _readData(
    'top_items',
    '/mobile/top-items?limit=$limit',
    (json) => json as List<dynamic>,
  );
}
