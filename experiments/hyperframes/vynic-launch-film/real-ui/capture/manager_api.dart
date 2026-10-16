import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Revenue before/after the Table 4 order lands (pull-to-refresh).
var afterRefresh = false;
var afterReceiving = false;
var reservationConfirmed = false;

/// Demo Manager API (synthetic "ფიქალი" data). Unknown paths are logged and answered with {}.
final requested = <String>[];
Map<String, Object?> Function(String path)? extra;

http.Client managerMock() => MockClient((req) async {
  final path = req.url.path + (req.url.hasQuery ? '?${req.url.query}' : '');
  requested.add('${req.method} $path');
  if (req.method != 'GET' && path.contains('reservation')) reservationConfirmed = true;
  if (req.method != 'GET' && path.contains('receiving')) afterReceiving = true;
  final body = extra?.call(path) ?? _route(req.url.path);
  return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
});

Object _route(String p) {
  if (p.endsWith('/mobile/entitlements')) {
    return {'features': ['POS', 'MANAGER_APP', 'INVENTORY', 'MANAGER_RESERVATIONS', 'WEBSITE']};
  }
  if (p.endsWith('/mobile/dashboard')) {
    return {
      'todayRevenue': 1282.45, 'closedTablesRevenue': 1282.45,
      'openTablesAmount': afterRefresh ? 1632.40 : 1586.20, 'openTablesPayable': afterRefresh ? 1632.40 : 1586.20,
      'shiftTotalRevenue': afterRefresh ? 2914.85 : 2868.65, 'todayOrderCount': 23, 'activeTablesCount': afterRefresh ? 3 : 2, 'occupancyPercentage': 33,
      'yesterdayRevenue': 2512.30, 'businessDate': '2026-09-30', 'businessDayId': '2026-09-30', 'businessDayStatus': 'OPEN',
      'businessDayOpenedAt': '2026-09-30T11:02:00.000', 'businessDayDurationMinutes': 572,
      'cashRevenue': 340.85, 'cardRevenue': 941.60, 'totalTables': 9, 'occupiedTables': 3, 'reservedTables': 0, 'freeTables': 6,
    };
  }
  if (p.endsWith('/mobile/sales-report')) {
    return {
      'orderCount': 23, 'totalRevenue': 1282.45,
      'paymentBreakdown': {'cash': 340.85, 'card-tbc': 612.30, 'card-bog': 329.30},
      'topItems': [
        {'itemName': 'ხინკალი ქალაქური', 'quantity': 184, 'total': 220.80},
        {'itemName': 'ხაჭაპური აჭარული', 'quantity': 11, 'total': 242.00},
        {'itemName': 'მწვადი ღორის', 'quantity': 7, 'total': 168.00},
      ],
    };
  }
  if (p.endsWith('/mobile/staff-performance')) {
    return [
      {'waiterName': 'გიორგი', 'totalSales': 612.40, 'orderCount': 11},
      {'waiterName': 'ანა', 'totalSales': 438.25, 'orderCount': 8},
      {'waiterName': 'ლევანი', 'totalSales': 231.80, 'orderCount': 4},
    ];
  }
  if (p.endsWith('/mobile/sales-daily')) {
    return [
      for (var i = 7; i >= 1; i--) {'date': DateTime(2026, 9, 30).subtract(Duration(days: i)).toIso8601String().substring(0, 10), 'total': [2210.5, 1980.2, 2402.8, 2512.3, 3120.9, 3388.4, 2512.3][7 - i]},
    ];
  }
  if (p.endsWith('/mobile/tables')) {
    return [
      for (var i = 1; i <= 9; i++)
        {'tableNumber': '$i', 'floor': 'first', 'isOccupied': (afterRefresh ? [1, 4, 7] : [1, 7]).contains(i), 'activeOrderId': (afterRefresh ? [1, 4, 7] : [1, 7]).contains(i) ? 1700 + i : null,
         'currentBill': {1: 127.60, 4: 46.20, 7: 1458.60}[i] ?? 0, 'reservedBy': 'გიორგი', 'reservedAt': '2026-09-30T19:48:00.000'},
    ];
  }
  if (p.contains('/mobile/takeaway-orders') || p.contains('/mobile/counted-menus') || p.contains('/mobile/notifications')) return [];
  if (p.contains('/mobile/reservations')) {
    return [
      {'id': 'r1', 'customerName': 'ნინო ბერიძე', 'customerPhone': '555 12 34 50', 'reservationDate': '2026-09-30', 'reservationTime': '22:00', 'numberOfGuests': 4, 'status': 'confirmed', 'tableNumbers': [6], 'notes': 'ფანჯარასთან'},
      {'id': 'r2', 'customerName': 'ლევან კაპანაძე', 'customerPhone': '599 44 21 07', 'reservationDate': '2026-09-30', 'reservationTime': '22:30', 'numberOfGuests': 6, 'status': reservationConfirmed ? 'confirmed' : 'pending', 'tableNumbers': [], 'notes': 'დაბადების დღე', 'source': 'website'},
    ];
  }
  if (p.contains('/mobile/inventory/stock-items')) {
    Map<String, Object?> st(String id, String name, String unit, String cur, String min, String status) =>
        {'id': id, 'name': name, 'baseUnit': unit, 'classification': 'FOOD', 'currentStock': cur, 'minimumStock': min, 'stockStatus': status,
         'supplierIds': id == 'flour' ? ['mill'] : [], 'isActive': true, 'costStatus': 'KNOWN', 'weightedUnitCost': '3.00', 'lastPurchaseUnitCost': '3.00'};
    return [
      st('flour', 'ფქვილი', 'kg', afterReceiving ? '21.500' : '1.500', '5', afterReceiving ? 'OK' : 'LOW'),
      st('sulguni', 'ყველი სულგუნი', 'kg', '1.200', '3', 'LOW'),
      st('butter', 'კარაქი', 'kg', '4.500', '2', 'OK'),
      st('oil', 'მზესუმზირის ზეთი', 'L', '8.000', '3', 'OK'),
      st('lemon', 'ლიმონი', 'kg', '3.200', '1', 'OK'),
    ];
  }
  if (p.contains('/mobile/inventory/suppliers')) {
    return [
      {'id': 'mill', 'name': 'ქალაქის წისქვილი', 'stockItemIds': ['flour'], 'phone': '+995 555 10 20 30', 'isActive': true},
    ];
  }
  if (p.contains('/mobile/inventory/receivings')) {
    return {'currentBusinessDate': '2026-09-30', 'receivings': [
      if (afterReceiving) {'id': 'rc1', 'status': 'POSTED', 'supplierId': 'mill', 'supplierName': 'ქალაქის წისქვილი', 'documentDate': '2026-09-30',
        'businessDate': '2026-09-30', 'documentTotal': '60.00', 'lineCount': 1, 'paid': '30.00', 'remaining': '30.00', 'paymentStatus': 'PARTIAL',
        'createdByName': 'ნინო', 'createdAt': '2026-09-30T20:42:00.000', 'receivedAt': '2026-09-30T20:42:00.000'},
    ]};
  }
  if (p.contains('/mobile/inventory/recipes')) return [];
  if (p.endsWith('/mobile/inventory/overview')) {
    return {'procurement': {'calendarDay': {'total': afterReceiving ? '60.00' : '0.00'}, 'today': '2026-09-30'}, 'lowStock': afterReceiving ? 1 : 2, 'negativeStock': 0, 'unmappedCount': 0};
  }
  return {};
}
