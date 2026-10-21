// Local synthetic values transcribed from the approved preview for visual comparison.
// Imported by tests only. Never used by the running Manager.
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';

final approvedStocks = <StockItem>[
  for (final row in [
    ('flour', 'ფქვილი', 'kg'),
    ('cheese', 'სულგუნი', 'kg'),
    ('egg', 'კვერცხი', 'piece'),
    ('butter', 'კარაქი', 'kg'),
    ('imeruli', 'იმერული ყველი', 'kg'),
  ])
    StockItem.fromJson({
      'id': row.$1,
      'name': row.$2,
      'baseUnit': row.$3,
      'isActive': true,
      'currentStock': '100',
      'recipeUnits': [row.$3],
    }),
];
final approvedSupplier = Supplier.fromJson({
  'id': 'agro',
  'name': 'აგრო სახლი',
  'stockItemIds': approvedStocks.map((s) => s.id).toList(),
});
final approvedReceiptJson = <String, dynamic>{
  'id': 'receipt-028',
  'supplierId': 'agro',
  'supplierName': 'აგრო სახლი',
  'waybillNumber': 'INV-028',
  'documentDate': '2026-10-16',
  'businessDate': '2026-10-16',
  'status': 'POSTED',
  'documentTotal': '620.00',
  'paid': '300.00',
  'remaining': '320.00',
  'paymentStatus': 'PARTIAL',
  'lines': [
    for (final row in [
      ('cheese', 'სულგუნი', '20', '18.50', '370.00'),
      ('imeruli', 'იმერული ყველი', '10', '25.00', '250.00'),
    ])
      {
        'id': row.$1,
        'stockItemId': row.$1,
        'stockItemName': row.$2,
        'enteredQuantity': row.$3,
        'enteredUnit': 'kg',
        'baseQuantity': row.$3,
        'baseUnit': 'kg',
        'unitPurchaseCost': row.$4,
        'lineTotal': row.$5,
        'effectiveBaseUnitCost': row.$4,
      },
  ],
};
final approvedReceipt = Receiving.fromJson(approvedReceiptJson);
final approvedRecipe = MenuRecipeDetail.fromJson({
  'menuItemId': 'khachapuri',
  'menuItemName': 'იმერული ხაჭაპური',
  'price': 18,
  'currentCost': {'status': 'AVAILABLE', 'total': '6.40'},
  'recipe': {
    'id': 'khachapuri-recipe',
    'menuItemId': 'khachapuri',
    'isActive': true,
    'yieldQuantity': '1',
    'components': [
      for (final row in [
        ('flour', 'ფქვილი', '0.25', 'kg'),
        ('cheese', 'სულგუნი', '0.18', 'kg'),
        ('egg', 'კვერცხი', '1', 'piece'),
        ('butter', 'კარაქი', '0.02', 'kg'),
      ])
        {
          'stockItemId': row.$1,
          'stockItemName': row.$2,
          'quantity': row.$3,
          'unit': row.$4,
          'baseQuantity': row.$3,
          'baseUnit': row.$4,
          'baseQuantityPerUnit': row.$3,
        },
    ],
  },
});
final approvedObligations = <String, dynamic>{
  'today': '2026-10-16',
  'businessDate': '2026-10-16',
  'periodMonth': '2026-10',
  'obligations': [
    {
      'id': 'rent',
      'name': 'ქირა',
      'type': 'RENT',
      'monthlyAmount': '1800.00',
      'dueDay': 25,
      'startsOn': '2026-10-01',
      'isActive': true,
    },
  ],
  'cycles': [
    {
      'id': 'cycle-rent',
      'obligationId': 'rent',
      'name': 'ქირა',
      'type': 'RENT',
      'targetAmount': '1800.00',
      'dueDate': '2026-10-25',
      'reservedAmount': '900.00',
      'paidAmount': '0.00',
      'remainingToCover': '900.00',
      'remainingToPay': '1800.00',
      'dailyRecommendedReserve': '90.00',
      'status': 'OPEN',
    },
  ],
};
