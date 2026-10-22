import 'dart:io';

// Synthetic UI-only records. Never used by a product entry point.
final fixtureDate = Platform.environment['MANAGER_APPROVED_DATA'] == '1'
    ? '2026-10-16'
    : DateTime.now().toIso8601String().substring(0, 10);
final fixtureNow = DateTime.now().toUtc().toIso8601String();
final managerMenu = [
  {
    'slug': 'food',
    'nameKa': 'კერძები',
    'nameEn': 'Food',
    'items': [
      {
        'nameKa': 'იმერული ხაჭაპური',
        'nameEn': 'Imeretian khachapuri',
        'price': 24,
      },
      {'nameKa': 'ხინკალი ქალაქური', 'nameEn': 'Khinkali', 'price': 2.5},
      {'nameKa': 'ბადრიჯანი ნიგვზით', 'nameEn': 'Eggplant', 'price': 18},
      {'nameKa': 'ქართული სალათი', 'nameEn': 'Georgian salad', 'price': 16},
    ],
  },
  {
    'slug': 'drinks',
    'nameKa': 'სასმელები',
    'nameEn': 'Drinks',
    'items': [],
    'subcategories': [
      {
        'slug': 'wine',
        'nameKa': 'ღვინო',
        'nameEn': 'Wine',
        'items': [
          {
            'nameKa': 'საფერავი',
            'nameEn': 'Saperavi',
            'price': 40,
            'variants': [
              {'size': .15, 'price': 9},
              {'size': .75, 'price': 40},
            ],
          },
        ],
      },
      {
        'slug': 'water',
        'nameKa': 'წყალი',
        'nameEn': 'Water',
        'items': [
          {'nameKa': 'მინერალური წყალი', 'nameEn': 'Mineral water', 'price': 4},
        ],
      },
    ],
  },
];
final managerTables = [
  for (var i = 1; i <= 12; i++)
    {
      'tableNumber': '$i',
      'tableLabel': 'მაგიდა $i',
      'floor': i < 9 ? 'first' : 'second',
      'floorLabel': i < 9 ? 'მთავარი დარბაზი' : 'ტერასა',
      'floorSortOrder': i < 9 ? 0 : 1,
      'tableSortOrder': i,
      'isOccupied': i <= 5,
      'activeOrderId': i <= 5 ? 70 + i : null,
      'currentBill': i <= 5 ? 48.0 + i * 24 : 0.0,
      'reservedBy': 'ნინო',
      'reservedAt': fixtureNow,
    },
];
final managerReservations = [
  for (var i = 0; i < 5; i++)
    {
      'id': 'reservation-$i',
      'customerName': [
        'ნინო ბერიძე',
        'გიორგი ლომიძე',
        'ანა მაისურაძე',
        'დავით კაპანაძე',
        'თამარ ჯაფარიძე',
      ][i],
      'customerPhone': '555 00 00 0$i',
      'numberOfGuests': [4, 6, 2, 8, 3][i],
      'reservationDate': fixtureDate,
      'reservationTime': '${17 + i}:30',
      'status': i == 2 ? 'pending' : 'confirmed',
      'tableNumbers': ['${i + 2}'],
      'floor': 'first',
      'notes': i == 0 ? 'ფანჯარასთან, თუ შესაძლებელია' : '',
      'menuItems': [],
    },
];
final managerCounted = <Map<String, dynamic>>[
  {
    'id': 'count-1',
    'displayName': 'საოჯახო ვახშამი',
    'createdAt': fixtureNow,
    'subtotal': 106.0,
    'total': 116.6,
    'includeServiceFee': true,
    'serviceFeeRate': .1,
    'serviceFeeAmount': 10.6,
    'items': [
      {'itemName': 'იმერული ხაჭაპური', 'unitPrice': 24.0, 'quantity': 2},
      {'itemName': 'ხინკალი ქალაქური', 'unitPrice': 2.5, 'quantity': 20},
      {'itemName': 'მინერალური წყალი', 'unitPrice': 4.0, 'quantity': 2},
    ],
  },
];
final managerReport = <String, dynamic>{
  'totalRevenue': 8420.0,
  'orderCount': 64,
  'avgOrderValue': 131.56,
  'paymentBreakdown': {'cash': 2420.0, 'tbc': 4200.0, 'bog': 1800.0},
  'byWaiter': [
    {'waiterName': 'გიორგი ლომიძე', 'totalSales': 4200.0, 'orderCount': 32},
    {'waiterName': 'თამარ ბერიძე', 'totalSales': 2600.0, 'orderCount': 20},
    {'waiterName': 'ანა მაისურაძე', 'totalSales': 1620.0, 'orderCount': 12},
  ],
  'cashRevenue': 2420.0,
  'cardRevenue': 6000.0,
  'topItems': [
    {'name': 'ხინკალი ქალაქური', 'qty': 240, 'revenue': 600.0},
    {'name': 'იმერული ხაჭაპური', 'qty': 22, 'revenue': 528.0},
    {'name': 'საფერავი', 'qty': 12, 'revenue': 480.0},
  ],
};
final managerDashboard = <String, dynamic>{
  'todayRevenue': 8420.0,
  'shiftTotalRevenue': 9860.0,
  'closedTablesRevenue': 8420.0,
  'nonFiscalClosedRevenue': 320.0,
  'todayOrderCount': 64,
  'activeTablesCount': 5,
  'openTablesAmount': 1440.0,
  'openTablesPayable': 1440.0,
  'occupancyPercentage': 41.67,
  'yesterdayRevenue': 7240.0,
  'businessDate': fixtureDate,
  'businessDayId': 'fixture-day',
  'businessDayStatus': 'OPEN',
  'businessDayOpenedAt': fixtureNow,
  'businessDayDurationMinutes': 420,
  'cashRevenue': 2420.0,
  'cardRevenue': 6000.0,
  'refunds': 0,
  'totalTables': 12,
  'occupiedTables': 5,
  'reservedTables': 2,
  'freeTables': 5,
  'snapshotAt': fixtureNow,
  'tbcRevenue': 4200.0,
  'bogRevenue': 1800.0,
  'advanceApplied': 200.0,
};
final managerPlanning = {
  'dailyRecommendedReserve': '240.00',
  'payrollRemaining': '4200.00',
  'obligationsRemaining': '1800.00',
  'recommendations': <Object>[],
};
final managerOverview = {
  'procurement': {
    'today': fixtureDate,
    'businessDate': fixtureDate,
    'month': fixtureDate.substring(0, 7),
    'calendarDay': {'total': '560.00', 'count': 2},
    'businessDay': {'total': '560.00', 'count': 2},
    'calendarMonth': {'total': '7800.00', 'count': 24},
  },
  'lowStock': 2,
  'negativeStock': 0,
  'unmappedCount': 1,
  'unmapped': [
    {'itemName': 'სალათი'},
  ],
};
final managerStocks = [
  {
    'id': 'stock-1',
    'name': 'საქონლის ხორცი',
    'baseUnit': 'kg',
    'currentStock': '12.500',
    'minimumStock': 5,
    'stockStatus': 'OK',
    'lastPurchaseUnitCost': '24.00',
    'supplierIds': ['supplier-1'],
  },
  {
    'id': 'stock-2',
    'name': 'სულგუნი',
    'baseUnit': 'kg',
    'currentStock': '2.500',
    'minimumStock': 5,
    'stockStatus': 'LOW',
    'lastPurchaseUnitCost': '22.00',
    'supplierIds': ['supplier-1'],
  },
  {
    'id': 'stock-3',
    'name': 'ფქვილი',
    'baseUnit': 'kg',
    'currentStock': '48.000',
    'minimumStock': 10,
    'stockStatus': 'OK',
    'lastPurchaseUnitCost': '2.50',
    'supplierIds': ['supplier-1'],
  },
];

final managerUsers = [
  for (final row in [
    ('user-1', 'ნინო მაისურაძე', 'MANAGER', '0000'),
    ('user-2', 'გიორგი ლომიძე', 'SUPERVISOR', '0001'),
    ('user-3', 'ანა კობახიძე', 'WAITER', '0002'),
    ('user-4', 'დავით ბერიძე', 'WAITER', '0003'),
  ])
    {
      'id': row.$1,
      'username': row.$2,
      'role': row.$3,
      'isActive': true,
      'pinCode': row.$4,
    },
];
final managerAudits = [
  for (var i = 0; i < 3; i++)
    {
      'reportId': 'audit-$i',
      'orderId': 71 + i,
      'tableNumbers': ['${i + 1}'],
      'floor': 'first',
      'openedById': 'user-2',
      'openedByName': 'გიორგი ლომიძე',
      'openedAt': fixtureNow,
      'status': i == 0 ? 'active' : 'closed',
      'updatedAt': fixtureNow,
      'events': [
        {
          'type': 'ORDER_CREATED',
          'itemName': '',
          'previousQty': 0,
          'newQty': 0,
          'waiterId': 'user-2',
          'waiterName': 'გიორგი ლომიძე',
          'timestamp': fixtureNow,
          'sequence': 1,
        },
        {
          'type': 'ADD_ITEM',
          'itemName': 'იმერული ხაჭაპური',
          'previousQty': 0,
          'newQty': 2,
          'waiterId': 'user-2',
          'waiterName': 'გიორგი ლომიძე',
          'timestamp': fixtureNow,
          'sequence': 2,
        },
        {
          'type': 'CHANGE_QUANTITY',
          'itemName': 'იმერული ხაჭაპური',
          'previousQty': 2,
          'newQty': 3,
          'waiterId': 'user-2',
          'waiterName': 'გიორგი ლომიძე',
          'timestamp': fixtureNow,
          'sequence': 3,
        },
      ],
    },
];
final managerActivity = {
  'items': [
    for (var i = 0; i < 6; i++)
      {
        'id': 'activity-$i',
        'action': 'MENU_ITEM_UPDATED',
        'actorId': 'user-1',
        'actorName': 'ნინო',
        'entityType': 'MENU_ITEM',
        'entityId': 'menu-$i',
        'entityLabel': [
          'იმერული ხაჭაპური',
          'ხინკალი ქალაქური',
          'საფერავი',
        ][i % 3],
        'createdAt': DateTime.now()
            .subtract(Duration(minutes: i * 18))
            .toUtc()
            .toIso8601String(),
        'source': 'POS',
        'deviceType': 'WINDOWS',
        'businessDate': fixtureDate,
        'changes': [
          {'field': 'price', 'previousValue': 22, 'newValue': 24},
        ],
      },
  ],
};
final managerSuppliers = [
  {
    'id': 'supplier-1',
    'name': 'ადგილობრივი მეურნეობა',
    'isActive': true,
    'stockItemIds': ['stock-1', 'stock-2', 'stock-3'],
  },
];
final managerReceipt = <String, dynamic>{
  'id': 'receiving-1',
  'supplierId': 'supplier-1',
  'supplierName': 'ადგილობრივი მეურნეობა',
  'waybillNumber': '00001234',
  'documentDate': fixtureDate,
  'businessDate': fixtureDate,
  'receivedAt': fixtureNow,
  'status': 'POSTED',
  'documentTotal': '560.00',
  'lineCount': 1,
  'createdByName': 'ნინო',
  'createdAt': fixtureNow,
  'paid': '200.00',
  'remaining': '360.00',
  'paymentStatus': 'PARTIAL',
  'payments': <Object>[],
  'lines': [
    {
      'id': 'line-1',
      'lineSequence': 0,
      'stockItemId': 'stock-1',
      'stockItemName': 'საქონლის ხორცი',
      'enteredQuantity': '20.000',
      'enteredUnit': 'kg',
      'baseQuantity': '20.000',
      'baseUnit': 'kg',
      'unitPurchaseCost': '28.0000',
      'lineTotal': '560.00',
      'effectiveBaseUnitCost': '28.000000',
    },
  ],
  'movements': [managerMovement],
};
final managerMovement = <String, dynamic>{
  'id': 'movement-1',
  'stockItemId': 'stock-1',
  'movementType': 'RECEIVING',
  'quantityDeltaBase': '20.000',
  'baseUnit': 'kg',
  'businessDate': fixtureDate,
  'actorName': 'ნინო',
  'createdAt': fixtureNow,
};
final managerRecipeItems = [
  {
    'menuItemId': 'menu-1',
    'nameKa': 'ხინკალი ქალაქური',
    'nameEn': 'Khinkali',
    'price': 2.5,
    'categoryName': 'კერძები',
    'menuGroup': 'FOOD',
    'recipe': {
      'id': 'recipe-1',
      'isActive': true,
      'revision': 1,
      'componentCount': 2,
    },
  },
  {
    'menuItemId': 'menu-2',
    'nameKa': 'იმერული ხაჭაპური',
    'nameEn': 'Khachapuri',
    'price': 24,
    'categoryName': 'კერძები',
    'menuGroup': 'FOOD',
  },
];
final managerRecipe = <String, dynamic>{
  'menuItemId': 'menu-1',
  'menuItemName': 'ხინკალი ქალაქური',
  'price': 2.5,
  'recipe': {
    'id': 'recipe-1',
    'menuItemId': 'menu-1',
    'revision': 1,
    'isActive': true,
    'components': [
      {
        'id': 'component-1',
        'stockItemId': 'stock-1',
        'stockItemName': 'საქონლის ხორცი',
        'baseUnit': 'kg',
        'unit': 'kg',
        'quantity': '0.035000',
        'baseQuantity': '0.035000',
        'baseQuantityPerUnit': '0.035000',
      },
      {
        'id': 'component-2',
        'stockItemId': 'stock-3',
        'stockItemName': 'ფქვილი',
        'baseUnit': 'kg',
        'unit': 'kg',
        'quantity': '0.025000',
        'baseQuantity': '0.025000',
        'baseQuantityPerUnit': '0.025000',
      },
    ],
  },
};
final managerConsumption = <String, dynamic>{
  'id': 'consumption-1',
  'posSaleId': 'sale-1',
  'closureId': 'close-1',
  'orderId': 71,
  'businessDate': fixtureDate,
  'policy': 'FISCAL_CLOSE',
  'reversedAt': null,
  'lines': [
    {
      'itemName': 'ხინკალი ქალაქური',
      'soldQuantity': 10,
      'status': 'MAPPED',
      'recipeId': 'recipe-1',
      'recipeRevision': 1,
      'components': [
        {
          'stockItemNameSnapshot': 'საქონლის ხორცი',
          'baseQuantityPerUnit': '0.035000',
          'totalBaseQuantity': '0.350000',
          'baseUnit': 'kg',
        },
      ],
    },
    {
      'itemName': 'ხელით დამატებული კერძი',
      'soldQuantity': 1,
      'status': 'UNMAPPED',
    },
  ],
};

// Test-only adapter for matched full-screen comparisons against the immutable
// approved experiment. No product entrypoint imports this file.
void useApprovedDashboardFixture() {
  managerDashboard.addAll({
    'todayRevenue': 8450.0,
    'closedTablesRevenue': 8450.0,
    'shiftTotalRevenue': 10750.0,
    'todayOrderCount': 42,
    'activeTablesCount': 8,
    'occupiedTables': 8,
    'totalTables': 18,
    'freeTables': 10,
    'openTablesAmount': 2300.0,
    'openTablesPayable': 2300.0,
    'occupancyPercentage': 44.4444,
    'businessDayId': fixtureDate,
    'businessDate': fixtureDate,
  });
  managerReport['topItems'] = [
    {'name': 'ხინკალი ქალაქური', 'qty': 120, 'revenue': 240.0},
    {'name': 'იმერული ხაჭაპური', 'qty': 24, 'revenue': 432.0},
    {'name': 'ქათმის მწვადი', 'qty': 18, 'revenue': 396.0},
  ];
  managerPlanning['payrollRemaining'] = '3240.00';
  managerReservations.clear();
  managerReservations.addAll([
    for (final r in [
      ('18:30', 'მარიამ გელაშვილი', 6, ['04', '05']),
      ('19:00', 'გიორგი ბერიძე', 4, ['08']),
      ('19:30', 'ანა ქავთარაძე', 8, ['12', '13']),
    ])
      {
        'id': 'reference-${r.$1}',
        'customerName': r.$2,
        'numberOfGuests': r.$3,
        'reservationTime': r.$1,
        'reservationDate': fixtureDate,
        'tableNumbers': r.$4,
        'status': 'confirmed',
      },
  ]);
}
