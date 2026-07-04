import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/services/notifications/manager_notification_inbox.dart';
import 'package:vynic/core/services/sync/pos_callback_config.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/core/services/sync/pos_live_refresh.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/audit/audit_order_diff_service.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_helper.dart';

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

    final key = DatabaseService.ensurePosIngestConnectionKey();
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
          await _handleOrderUpdate(request, body);
          return;
        case 'POST /mobile-order-cancel':
          await _handleOrderCancel(request, body);
          return;
        case 'POST /mobile-order-status':
          await _handleOrderStatus(request, body);
          return;
        case 'POST /mobile-order-create':
          await _handleOrderCreate(request, body);
          return;
        case 'POST /mobile-walk-in-order-create':
          await _handleWalkInOrderCreate(request, body);
          return;
        case 'POST /mobile-order-print-check':
          await _handleOrderPrintCheck(request, body);
          return;
        case 'GET /mobile-reservations':
          await _handleReservationsList(request);
          return;
        case 'POST /mobile-reservation-create':
          await _handleReservationCreate(request, body);
          return;
        case 'POST /mobile-reservation-status':
          await _handleReservationStatus(request, body);
          return;
        case 'POST /mobile-reservation-delete':
          await _handleReservationDelete(request, body);
          return;
        case 'POST /mobile-reservation-print-check':
          await _handleReservationPrintCheck(request, body);
          return;
        case 'POST /mobile-counted-menu-print':
          await _handleCountedMenuPrint(request, body);
          return;
        case 'POST /mobile-expense-create':
          await _handleExpenseCreate(request, body);
          return;
        case 'POST /mobile-user-create':
          await _handleUserCreate(request, body);
          return;
        case 'POST /mobile-user-update-pin':
          await _handleUserPinUpdate(request, body);
          return;
        case 'POST /mobile-user-update-role':
          await _handleUserRoleUpdate(request, body);
          return;
        case 'POST /mobile-user-rename':
          await _handleUserRename(request, body);
          return;
        case 'POST /mobile-user-delete':
          await _handleUserDelete(request, body);
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
    final expected = DatabaseService.getPosIngestConnectionKey();
    if (expected == null || expected.isEmpty) return true;
    final provided = request.headers.value('x-connection-key')?.trim();
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

  static Future<void> _handleOrderUpdate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final posOrderId = (body['posOrderId'] as num?)?.toInt();
    if (posOrderId == null) {
      await _json(request, 400, {'error': 'posOrderId_required'});
      return;
    }
    final order = DatabaseService.getOrder(posOrderId);
    if (order == null) {
      await _json(request, 404, {'error': 'order_not_found'});
      return;
    }

    final beforeItems = order.items.map((i) => i.clone()).toList();
    final newItems = _parseOrderItemsFromBody(body['items']);

    final diff = PosChangeHighlightService.computeOrderItemChanges(
      before: beforeItems,
      after: newItems,
    );

    final prevTotal = order.totalAmount;
    final prevServiceFee = order.includeServiceFee;

    final performer =
        (body['updatedBy'] ?? body['waiterName'] ?? 'მობილური მენეჯერი')
            .toString()
            .trim();
    final performerName = performer.isNotEmpty
        ? performer
        : 'მობილური მენეჯერი';
    final ts = DatabaseService.getCurrentDateTime();
    final auditEvents = AuditOrderDiffService.buildEvents(
      previousItems: beforeItems,
      updatedItems: newItems,
      performerId: performerName,
      performerName: performerName,
      timestamp: ts,
    );
    if (auditEvents.isNotEmpty) {
      await DatabaseService.appendOrderAuditEvents(
        orderId: posOrderId,
        events: auditEvents,
      );
    }

    order.items = newItems;
    if (body['totalAmount'] != null) {
      order.totalAmount = (body['totalAmount'] as num).toDouble();
    }
    if (body['includeServiceFee'] is bool) {
      order.includeServiceFee = body['includeServiceFee'] as bool;
    }
    order.updatedAt = ts;
    order.recalculateTotal();
    await DatabaseService.updateOrder(order);

    final message = _orderChangeMessage(
      posOrderId: posOrderId,
      diff: diff,
      totalChanged: (order.totalAmount - prevTotal).abs() > 0.009,
      serviceFeeToggled:
          body['includeServiceFee'] is bool &&
          order.includeServiceFee != prevServiceFee,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
    );
    final tableLabel = order.tableNumbers.isNotEmpty
        ? order.tableNumbers.join(', ')
        : null;
    _notifySystemChange(
      message: message,
      meta: {
        'posOrderId': posOrderId,
        if (tableLabel != null) 'tableLabel': tableLabel,
        if (order.floor.isNotEmpty) 'floor': order.floor,
        if (diff.highlightKeys.isNotEmpty)
          'highlightItemKeys': diff.highlightKeys.toList(),
      },
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleOrderCancel(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final posOrderId = (body['posOrderId'] as num?)?.toInt();
    if (posOrderId == null) {
      await _json(request, 400, {'error': 'posOrderId_required'});
      return;
    }
    // Capture the tables before the order (and its cleanup) removes them.
    final existing = DatabaseService.getOrder(posOrderId);
    final tableSeg = existing != null
        ? _formatTablesSegment(existing.tableNumbers, existing.floor)
        : '';
    final ok = await DatabaseService.deleteOrderAndCleanup(
      orderId: posOrderId,
      deletedBy: 'mobile_manager',
    );
    if (!ok) {
      await _json(request, 404, {'error': 'order_not_found'});
      return;
    }
    _notifySystemChange(
      message: tableSeg.isNotEmpty
          ? 'შეკვეთა #$posOrderId გაუქმდა — $tableSeg'
          : 'შეკვეთა #$posOrderId წაიშალა',
      meta: {
        'posOrderId': posOrderId,
        if (tableSeg.isNotEmpty)
          'tableLabel': existing!.tableNumbers.join(', '),
      },
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleOrderStatus(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final posOrderId = (body['posOrderId'] as num?)?.toInt();
    final status = (body['status'] as String?)?.trim();
    if (posOrderId == null || status == null || status.isEmpty) {
      await _json(request, 400, {'error': 'posOrderId_and_status_required'});
      return;
    }
    // Capture tables before the status change frees them (paid/cancelled).
    final existing = DatabaseService.getOrder(posOrderId);
    final tableSeg = existing != null
        ? _formatTablesSegment(existing.tableNumbers, existing.floor)
        : '';
    await DatabaseService.updateOrderStatus(
      orderId: posOrderId,
      status: status,
    );
    final isCancelled = status.toLowerCase() == 'cancelled';
    final String message;
    if (isCancelled) {
      message = tableSeg.isNotEmpty
          ? 'შეკვეთა #$posOrderId გაუქმდა — $tableSeg'
          : 'შეკვეთა #$posOrderId გაუქმდა';
    } else {
      message = tableSeg.isNotEmpty
          ? 'შეკვეთა #$posOrderId — სტატუსი: $status ($tableSeg)'
          : 'შეკვეთა #$posOrderId — სტატუსი: $status';
    }
    _notifySystemChange(
      message: message,
      meta: {
        'posOrderId': posOrderId,
        'status': status,
        if (tableSeg.isNotEmpty)
          'tableLabel': existing!.tableNumbers.join(', '),
      },
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleOrderCreate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final posOrderId = (body['posOrderId'] as num?)?.toInt();
    if (posOrderId == null) {
      await _json(request, 400, {'error': 'posOrderId_required'});
      return;
    }

    final items = _parseOrderItemsFromBody(body['items']);
    final isNew = DatabaseService.getOrder(posOrderId) == null;
    final waiterName = (body['waiterName'] ?? 'mobile_manager').toString();

    final order = await DatabaseService.upsertMobileTakeawayOrder(
      posOrderId: posOrderId,
      customerName: (body['customerName'] ?? '').toString(),
      pickupTime: (body['pickupTime'] ?? '').toString(),
      waiterName: waiterName,
      items: items,
      totalAmount: (body['totalAmount'] as num?)?.toDouble(),
    );
    if (order == null) {
      await _json(request, 500, {'error': 'create_failed'});
      return;
    }
    // Auto-send the kitchen check once, on first arrival from mobile.
    if (isNew) {
      _sendKitchenCheckForMobileOrder(
        items: items,
        orderLabel: 'გატანა #${order.orderId}',
        waiterName: waiterName,
      );
    }
    final highlightKeys = items
        .expand((i) => [i.itemKey, i.itemName])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final customer = (body['customerName'] ?? '').toString().trim();
    final pickup = (body['pickupTime'] ?? '').toString().trim();
    final detailSeg = [
      if (customer.isNotEmpty) customer,
      if (pickup.isNotEmpty) 'აღება: $pickup',
    ].join(' • ');
    _notifySystemChange(
      message: detailSeg.isNotEmpty
          ? 'ახალი გატანა #${order.orderId} — $detailSeg'
          : 'ახალი გატანა #${order.orderId}',
      meta: {
        'posOrderId': order.orderId,
        if (highlightKeys.isNotEmpty)
          'highlightItemKeys': highlightKeys.toList(),
      },
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true, 'posOrderId': order.orderId});
  }

  /// Fire-and-forget kitchen check for a mobile-originated walk-in / takeaway.
  /// Drinks-only orders and missing-printer setups are handled gracefully by
  /// PrinterService (no-op). Non-kitchen items are filtered downstream.
  static void _sendKitchenCheckForMobileOrder({
    required List<OrderItem> items,
    required String orderLabel,
    required String waiterName,
    String? tableLabel,
  }) {
    final lines = <String>[];
    for (final item in items) {
      var line = '${item.quantity}x ${item.itemName}';
      final comment = item.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        line += '\n  ⮑ $comment';
      }
      lines.add(line);
    }
    if (lines.isEmpty) return;
    PrinterService.printKitchenCheckInBackground(
      items: lines,
      tableNumber: tableLabel,
      orderNumber: orderLabel,
      waiterName: waiterName,
      createdAt: DateTime.now(),
    );
  }

  static Future<void> _handleWalkInOrderCreate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final posOrderId = (body['posOrderId'] as num?)?.toInt();
    if (posOrderId == null) {
      await _json(request, 400, {'error': 'posOrderId_required'});
      return;
    }

    final tableNumbers = ((body['tableNumbers'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (tableNumbers.isEmpty) {
      await _json(request, 400, {'error': 'tableNumbers_required'});
      return;
    }

    final floor = (body['floor'] ?? 'first').toString();
    final items = _parseOrderItemsFromBody(body['items']);
    final isNew = DatabaseService.getOrder(posOrderId) == null;
    final waiterName = (body['waiterName'] ?? 'mobile_manager').toString();

    final order = await DatabaseService.upsertMobileDineInOrder(
      posOrderId: posOrderId,
      tableNumbers: tableNumbers,
      floor: floor,
      waiterName: waiterName,
      items: items,
      guestCount: (body['guestCount'] as num?)?.toInt() ?? 0,
      totalAmount: (body['totalAmount'] as num?)?.toDouble(),
    );
    if (order == null) {
      await _json(request, 500, {'error': 'create_failed'});
      return;
    }
    // Auto-send the kitchen check once, on first arrival from mobile.
    if (isNew) {
      _sendKitchenCheckForMobileOrder(
        items: items,
        orderLabel: 'Walk-in #${order.orderId}',
        waiterName: waiterName,
        tableLabel: tableNumbers.join(', '),
      );
    }

    final highlightKeys = items
        .expand((i) => [i.itemKey, i.itemName])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final tableSeg = _formatTablesSegment(tableNumbers, floor);
    _notifySystemChange(
      message: tableSeg.isNotEmpty
          ? 'ახალი walk-in #${order.orderId} — $tableSeg'
          : 'ახალი walk-in #${order.orderId}',
      meta: {
        'posOrderId': order.orderId,
        'walkIn': true,
        if (tableSeg.isNotEmpty) 'tableLabel': tableNumbers.join(', '),
        if (order.floor.isNotEmpty) 'floor': order.floor,
        if (highlightKeys.isNotEmpty)
          'highlightItemKeys': highlightKeys.toList(),
      },
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true, 'posOrderId': order.orderId});
  }

  /// Manager-triggered table/order check print (Mac / iOS / Android → backend →
  /// POS callback). The Windows POS remains the only print host: the manager
  /// client never prints directly. We look the order up in local Hive (the
  /// source of truth) and print a customer pre-bill receipt on the receipt
  /// printer, mirroring the POS order-detail "print receipt" (receiptType
  /// 'client'). Georgian only; raw item names (menu localization lives in the
  /// POS UI layer and is not reused here).
  static Future<void> _handleOrderPrintCheck(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final posOrderId = (body['posOrderId'] as num?)?.toInt();
    if (posOrderId == null) {
      await _json(request, 400, {'error': 'posOrderId_required'});
      return;
    }

    final order = DatabaseService.getOrder(posOrderId);
    if (order == null) {
      await _json(request, 404, {'error': 'order_not_found'});
      return;
    }

    final isTakeAway = order.floor.toLowerCase().contains('takeaway');
    final receiptLines = <String>[];

    if (order.packageItems.isNotEmpty) {
      final packageLabel =
          (order.packageName != null && order.packageName!.trim().isNotEmpty)
          ? order.packageName!.trim()
          : 'პაკეტი';
      final packageTotalRaw = order.getPackageSubtotal();
      final packageTotal = packageTotalRaw > 0
          ? packageTotalRaw
          : order.packagePrice;

      receiptLines.add('[$packageLabel]');
      final summary = StringBuffer();
      if (order.packageGuestCount > 0) {
        summary.write('${order.packageGuestCount}x ');
      }
      summary.write(packageLabel);
      if (packageTotal > 0) {
        summary.write(' - ${packageTotal.toStringAsFixed(2)} GEL');
      }
      receiptLines.add(summary.toString());

      for (final packageItem in order.packageItems) {
        receiptLines.add(
          '  ⮑ ${packageItem.quantity}x ${packageItem.itemName}',
        );
      }
      if (order.items.isNotEmpty) {
        receiptLines.add('---');
      }
    }

    if (order.items.isNotEmpty) {
      if (order.packageItems.isNotEmpty) {
        receiptLines.add('[დამატებითი]');
      }
      receiptLines.addAll(
        order.items.map(
          (item) =>
              '${item.quantity}x ${item.itemName} - '
              '${item.total.toStringAsFixed(2)} GEL',
        ),
      );
    }

    final itemsWithWaiter = <String>[
      'ოფიციანტი: ${order.createdBy}',
      '---',
      ...receiptLines,
    ];

    final packageSubtotal = order.getPackageSubtotal();
    final additionalSubtotal = order.getAdditionalItemsSubtotal();
    final discountAmount = order.discountAmount > 0
        ? order.discountAmount
        : null;
    final manualAdjustment = order.manualAdjustmentAmount.abs() >= 0.01
        ? order.manualAdjustmentAmount
        : null;

    PrinterService.printReceiptInBackground(
      items: itemsWithWaiter,
      total: order.totalAmount,
      subtotal: order.getItemsSubtotal(),
      serviceFee: order.getServiceFee(),
      includeServiceFee: order.includeServiceFee,
      tableNumber: isTakeAway ? null : order.tableNumbers.join(', '),
      orderNumber: order.orderId.toString(),
      language: 'ka',
      packageSubtotal: packageSubtotal > 0 ? packageSubtotal : null,
      additionalSubtotal: additionalSubtotal > 0 ? additionalSubtotal : null,
      discountAmount: discountAmount,
      manualAdjustment: manualAdjustment,
      receiptType: isTakeAway ? 'take_away' : 'client',
    );

    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleReservationsList(HttpRequest request) async {
    final data = DatabaseService.getAllReservations()
        .map(DatabaseService.serializeReservationForSync)
        .toList();
    await _json(request, 200, {'data': data});
  }

  static Future<void> _handleReservationCreate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    try {
      final id = await DatabaseService.createReservationFromJson(body);
      final reservation = DatabaseService.getReservationById(id);
      final customerName =
          (reservation?['customerName'] ?? body['customerName'] ?? '')
              .toString()
              .trim();
      final isTakeAway = body['isTakeAway'] == true;
      final resTables = ((body['tableNumbers'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      final resTime = (body['reservationTime'] ?? '').toString().trim();
      final tableSeg = isTakeAway
          ? 'გატანა'
          : _formatTablesSegment(resTables, 'first');
      final detailSeg = [
        if (customerName.isNotEmpty) customerName,
        if (tableSeg.isNotEmpty) tableSeg,
        if (resTime.isNotEmpty) 'დრო: $resTime',
      ].join(' • ');
      _notifySystemChange(
        message: detailSeg.isEmpty
            ? 'ახალი რეზერვაცია'
            : 'ახალი რეზერვაცია — $detailSeg',
        meta: {
          'reservationId': id,
          if (tableSeg.isNotEmpty && !isTakeAway)
            'tableLabel': resTables.join(', '),
        },
      );
      _scheduleCloudSync();
      await _json(request, 200, {
        'success': true,
        'reservation': reservation ?? {'id': id},
      });
    } catch (e) {
      await _json(request, 400, {'error': e.toString()});
    }
  }

  static Future<void> _handleReservationStatus(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final reservationId = (body['reservationId'] ?? '').toString();
    final status = (body['status'] ?? '').toString();
    if (reservationId.isEmpty || status.isEmpty) {
      await _json(request, 400, {'error': 'reservationId_and_status_required'});
      return;
    }
    await DatabaseService.updateReservationStatus(reservationId, status);
    _notifySystemChange(
      message: 'რეზერვაცია — სტატუსი: $status',
      meta: {'reservationId': reservationId, 'status': status},
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleReservationDelete(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final reservationId = (body['reservationId'] ?? '').toString();
    if (reservationId.isEmpty) {
      await _json(request, 400, {'error': 'reservationId_required'});
      return;
    }
    await DatabaseService.deleteReservation(reservationId);
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  /// Manager-triggered reservation check print (Mac / iOS / Android → backend →
  /// POS callback). The Windows POS remains the only print host: the manager
  /// client never touches a printer. We look the reservation up in local Hive
  /// (the source of truth) and reuse the exact kitchen-check formatting the POS
  /// uses when a reservation is created locally.
  static Future<void> _handleReservationPrintCheck(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final reservationId = (body['reservationId'] ?? '').toString().trim();
    if (reservationId.isEmpty) {
      await _json(request, 400, {'error': 'reservationId_required'});
      return;
    }

    final reservation = DatabaseService.findReservationById(reservationId);
    if (reservation == null) {
      await _json(request, 404, {'error': 'reservation_not_found'});
      return;
    }

    final kitchenItems = HomeReservationsHelper.buildKitchenCheckLines(
      reservation,
    );
    if (kitchenItems.isEmpty) {
      // No kitchen-bound items (e.g. no pre-order) — nothing to print.
      await _json(request, 200, {'success': true, 'printed': false});
      return;
    }

    final requestedBy = (body['requestedBy'] ?? reservation.createdBy)
        .toString()
        .trim();
    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: reservation.tableNumbers.isNotEmpty
          ? reservation.tableNumbers.join(', ')
          : null,
      orderNumber: HomeReservationsHelper.buildKitchenOrderLabel(reservation),
      waiterName: requestedBy.isNotEmpty ? requestedBy : 'mobile_manager',
      createdAt: HomeReservationsHelper.buildKitchenTime(reservation),
    );

    await _json(request, 200, {'success': true, 'printed': true});
  }

  /// Manager-triggered counted-menu (quick-order draft) print. Mac / iOS /
  /// Android → backend → POS callback. The Windows POS is the only print host.
  /// Counted menus don't reliably exist in POS Hive (mobile-created ones live
  /// only in the backend), so this prints from the request payload directly,
  /// mirroring the POS counted-menu receipt (receiptType 'menu_count') on the
  /// receipt printer.
  static Future<void> _handleCountedMenuPrint(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final rawItems = (body['items'] as List?) ?? const [];
    if (rawItems.isEmpty) {
      await _json(request, 400, {'error': 'items_required'});
      return;
    }

    final lines = <String>['---'];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final name = (map['itemName'] ?? map['name'] ?? '').toString().trim();
      final qty = (map['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice =
          ((map['unitPrice'] ?? map['price']) as num?)?.toDouble() ?? 0.0;
      final total = (map['total'] as num?)?.toDouble() ?? unitPrice * qty;
      lines.add('${qty}x $name - ${total.toStringAsFixed(2)} GEL');
      final comment = (map['comment'] as String?)?.trim();
      if (comment != null && comment.isNotEmpty) {
        lines.add('  ⮑ $comment');
      }
    }

    final subtotal = (body['subtotal'] as num?)?.toDouble() ?? 0.0;
    final serviceFeeAmount =
        (body['serviceFeeAmount'] as num?)?.toDouble() ?? 0.0;
    final total = (body['total'] as num?)?.toDouble() ?? subtotal;
    final includeServiceFee =
        body['includeServiceFee'] == true && serviceFeeAmount > 0;
    final receiptTotal = includeServiceFee ? total : subtotal;
    final language = (body['language'] ?? 'ka').toString() == 'en'
        ? 'en'
        : 'ka';

    PrinterService.printReceiptInBackground(
      items: lines,
      total: receiptTotal,
      subtotal: subtotal,
      serviceFee: includeServiceFee ? serviceFeeAmount : null,
      includeServiceFee: includeServiceFee,
      language: language,
      receiptType: 'menu_count',
    );

    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleExpenseCreate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final description = (body['description'] ?? '').toString().trim();
    final amount = (body['amount'] as num?)?.toDouble() ?? 0;
    if (description.isEmpty || amount <= 0) {
      await _json(request, 400, {'error': 'invalid_expense'});
      return;
    }
    final expense = await DatabaseService.saveExpenseRecord(
      description: description,
      amount: amount,
      category: (body['category'] ?? 'სხვა').toString(),
      paymentType: (body['paymentType'] ?? 'cash').toString(),
      createdAt: body['createdAt'] != null
          ? DateTime.tryParse(body['createdAt'].toString())
          : null,
      businessDate: body['businessDate'] as String?,
      sourceId: body['id'] as String?,
    );
    _scheduleCloudSync();
    await _json(request, 200, {'success': true, 'expense': expense});
  }

  static Future<void> _handleUserCreate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final username = (body['username'] ?? '').toString().trim();
    final pinCode = (body['pinCode'] ?? body['pin'] ?? '').toString().trim();
    final roleRaw = (body['role'] ?? 'waiter').toString();
    if (username.isEmpty || pinCode.isEmpty) {
      await _json(request, 400, {'error': 'username_and_pin_required'});
      return;
    }
    final role = StaffRole.normalizeClient(roleRaw);
    final ok = await DatabaseService.addUser(
      username: username,
      pinCode: pinCode,
      role: role,
    );
    if (!ok) {
      await _json(request, 409, {'error': 'user_exists_or_pin_taken'});
      return;
    }
    _scheduleCloudSync();
    await _json(request, 200, {
      'success': true,
      'user': {'username': username, 'role': role},
    });
  }

  static Future<void> _handleUserPinUpdate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final username = (body['username'] ?? '').toString().trim();
    final pinCode = (body['pinCode'] ?? body['pin'] ?? '').toString().trim();
    if (username.isEmpty || pinCode.isEmpty) {
      await _json(request, 400, {'error': 'username_and_pin_required'});
      return;
    }
    final ok = await DatabaseService.updateUserPinByUsername(
      username: username,
      pinCode: pinCode,
    );
    if (!ok) {
      await _json(request, 404, {'error': 'update_failed'});
      return;
    }
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  static Future<void> _handleUserRoleUpdate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final username = (body['username'] ?? '').toString().trim();
    final roleRaw = (body['role'] ?? '').toString().trim();
    if (username.isEmpty || roleRaw.isEmpty) {
      await _json(request, 400, {'error': 'username_and_role_required'});
      return;
    }
    final role = StaffRole.normalizeClient(roleRaw);
    final ok = await DatabaseService.updateUserRoleByUsername(
      username: username,
      role: role,
    );
    if (!ok) {
      await _json(request, 409, {'error': 'role_update_failed'});
      return;
    }
    _scheduleCloudSync();
    await _json(request, 200, {
      'success': true,
      'user': {'username': username, 'role': role},
    });
  }

  static Future<void> _handleUserRename(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final oldUsername = (body['oldUsername'] ?? '').toString().trim();
    final newUsername = (body['newUsername'] ?? body['username'] ?? '')
        .toString()
        .trim();
    if (oldUsername.isEmpty || newUsername.isEmpty) {
      await _json(request, 400, {'error': 'old_and_new_username_required'});
      return;
    }
    final ok = await DatabaseService.renameUserByUsername(
      oldUsername: oldUsername,
      newUsername: newUsername,
    );
    if (!ok) {
      await _json(request, 409, {'error': 'rename_failed'});
      return;
    }
    _scheduleCloudSync();
    await _json(request, 200, {
      'success': true,
      'user': {'username': newUsername},
    });
  }

  static Future<void> _handleUserDelete(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final username = (body['username'] ?? '').toString().trim();
    if (username.isEmpty) {
      await _json(request, 400, {'error': 'username_required'});
      return;
    }
    final ok = await DatabaseService.deleteUserByUsername(username);
    if (!ok) {
      await _json(request, 409, {'error': 'delete_failed'});
      return;
    }
    _scheduleCloudSync();
    await _json(request, 200, {'success': true});
  }

  static void _scheduleCloudSync() {
    ManagerSyncService.syncToManagerAppDebounced();
  }

  static List<OrderItem> _parseOrderItemsFromBody(dynamic itemsRaw) {
    final list = (itemsRaw as List?) ?? const [];
    final items = <OrderItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final name = (map['itemName'] ?? map['name'] ?? '').toString().trim();
      final unitPrice =
          (map['unitPrice'] ?? map['price'] as num?)?.toDouble() ?? 0.0;
      final qty = (map['quantity'] as num?)?.toInt() ?? 1;
      final itemKey = (map['itemKey'] ?? name).toString().trim();
      items.add(
        OrderItem(
          itemKey: itemKey.isNotEmpty ? itemKey : name,
          itemName: name,
          unitPrice: unitPrice,
          quantity: qty,
          total: unitPrice * qty,
          comment: map['comment'] as String?,
        ),
      );
    }
    return items;
  }

  static String _orderChangeMessage({
    required int posOrderId,
    required OrderItemChangeDiff diff,
    required bool totalChanged,
    required bool serviceFeeToggled,
    List<String> tableNumbers = const [],
    String floor = '',
  }) {
    if (diff.summaryLines.isNotEmpty) {
      final detail = diff.summaryLines.take(4).join('; ');
      final more = diff.summaryLines.length > 4
          ? ' (+${diff.summaryLines.length - 4})'
          : '';
      return 'შეკვეთა #$posOrderId — $detail$more';
    }
    if (serviceFeeToggled) {
      final tableSeg = _formatTablesSegment(tableNumbers, floor);
      if (tableSeg.isNotEmpty) {
        return '$tableSeg — სერვისის საფასური განახლდა';
      }
      return 'შეკვეთა #$posOrderId — სერვისის საფასური განახლდა';
    }
    if (totalChanged) {
      return 'შეკვეთა #$posOrderId — თანხა განახლდა';
    }
    return 'შეკვეთა #$posOrderId განახლდა';
  }

  static String _tableWordForFloor(String floor) {
    switch (floor.toLowerCase()) {
      case 'second':
        return 'კუპე';
      case 'takeaway':
        return 'გატანა';
      default:
        return 'მაგიდა';
    }
  }

  /// Builds a "მაგიდა 5, 6" style segment from a list of table identifiers.
  /// Accepts raw numbers ("5") or POS-prefixed names ("Table 5", "VIP Zone 1").
  /// Takeaway pseudo-tables ("TA-90013") are skipped. Returns an empty string
  /// when there are no usable tables.
  static String _formatTablesSegment(List<String> tables, String floor) {
    final clean = tables
        .map(
          (e) => e
              .toString()
              .trim()
              .replaceAll('Table ', '')
              .replaceAll('VIP Zone ', '')
              .trim(),
        )
        .where((e) => e.isNotEmpty && e != '0' && !e.startsWith('TA-'))
        .toList();
    if (clean.isEmpty) return '';
    return '${_tableWordForFloor(floor)} ${clean.join(', ')}';
  }

  static void _notifySystemChange({
    required String message,
    Map<String, dynamic>? meta,
  }) {
    PosLiveRefresh.bump();
    ManagerNotificationInbox.ingestLocal(
      title: 'სისტემა:',
      message: message,
      source: 'system',
      meta: meta,
    );
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
