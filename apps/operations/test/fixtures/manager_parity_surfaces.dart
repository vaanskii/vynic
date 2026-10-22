// Actual Manager widgets with synthetic, local-only loaders for visual review.
import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/consumption_history_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/stock_movement_history_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/inventory_history_page.dart';
import 'manager_redesign_fixture.dart';

final parityStocks = managerStocks.map(StockItem.fromJson).toList();
final paritySuppliers = managerSuppliers.map(Supplier.fromJson).toList();
final parityRecipes = managerRecipeItems.map(RecipeMenuItem.fromJson).toList();
final parityReceipt = Receiving.fromJson(managerReceipt);
final parityHistory = <String, dynamic>{
  'periods': [
    {
      'id': 'period-1',
      'periodMonth': fixtureDate.substring(0, 7),
      'expected': '1500.00',
      'paid': '800.00',
      'remaining': '700.00',
      'payments': [
        {
          'id': 'payment-1',
          'amount': '800.00',
          'businessDate': fixtureDate,
          'paymentDate': fixtureDate,
          'actorName': 'ნინო',
          'notes': 'სატესტო გადახდა',
          'canReverse': true,
        },
      ],
    },
  ],
};
Map<String, Widget> parityPages() => {
  'inventory-menu-picker': InventoryMenuPicker(items: parityRecipes),
  for (final section in [0, 1, 2, 3])
    [
      'inventory-stock',
      'inventory-suppliers',
      'inventory-receivings',
      'inventory-recipes',
    ][section]: Scaffold(
      body: InventoryAdminTab(
        initialSection: section,
        loadStockItems: () async => parityStocks,
        loadSuppliers: () async => paritySuppliers,
        loadReceivings: () async => ReceivingPage(
          receivings: [parityReceipt],
          currentBusinessDate: fixtureDate,
        ),
        loadRecipes: () async => parityRecipes,
      ),
    ),
  'inventory-payables': SupplierPayablesScreen(
    load: () async => {
      'businessDate': fixtureDate,
      'receivings': [managerReceipt],
    },
  ),
  'stock-movement-history': StockMovementHistoryScreen(
    stockItemId: 'stock-1',
    name: 'საქონლის ხორცი',
    loadPage: (_) async => InventoryHistoryPage(items: [managerMovement]),
  ),
  'consumption-history': ConsumptionHistoryScreen(
    load: (_, _, _) async => [managerConsumption],
  ),
  'consumption-detail': ConsumptionHistoryScreen(
    consumptionId: 'consumption-1',
    loadDetail: (_) async => managerConsumption,
  ),
  'finance-history': FinanceHistoryScreen(
    title: 'გიორგი · ხელფასის ისტორია',
    path: 'payroll/period-1/history',
    correctionScope: 'synthetic-fixture',
    read: (_) async => parityHistory,
  ),
  'finance-legacy-history': FinanceHistoryScreen(
    title: 'ძველი ხელფასების ისტორია',
    path: 'legacy-salaries',
    read: (_) async => {
      'entries': [
        {
          'description': 'სატესტო ხელფასი',
          'amount': '800.00',
          'businessDate': fixtureDate,
        },
      ],
    },
  ),
};
Map<String, Widget> parityDialogs() => {
  'receiving-editor': ReceivingEditorDialog(
    suppliers: paritySuppliers,
    stockItems: parityStocks,
    businessDate: fixtureDate,
    save: (_) async {},
  ),
  'receiving-detail': ReceivingDetailDialog(
    receivingId: 'receiving-1',
    load: () async => parityReceipt,
    onEditDraft: (_) async {},
  ),
  'stock-detail': StockItemDetailDialog(
    stockItemId: 'stock-1',
    load: () async => StockItemDetail(
      item: parityStocks.first,
      weightedUnitCost: '28.00',
      lastPurchaseUnitCost: '28.00',
      recentMovements: [StockMovement.fromJson(managerMovement)],
    ),
  ),
  'supplier-detail': SupplierDetailDialog(
    supplier: paritySuppliers.first,
    stockItems: parityStocks,
    load: () async => {
      'stockItems': managerStocks,
      'recentReceivings': [managerReceipt],
      'settlement': {
        'outstanding': '360.00',
        'unverified': '0.00',
        'receivings': [managerReceipt],
      },
    },
  ),
  'supplier-product': SuppliedItemDialog(
    supplierId: 'supplier-1',
    supplierName: 'ადგილობრივი მეურნეობა',
    stockItems: parityStocks,
    menuItems: parityRecipes,
    save: (_) async {},
  ),
  'supplier-payment': SupplierPaymentDialog(
    receiving: {...managerReceipt, 'currentBusinessDate': fixtureDate},
    save: (_) async {},
  ),
  'supplier-payment-reversal': SupplierPaymentDialog(
    receiving: {...managerReceipt, 'currentBusinessDate': fixtureDate},
    reversal: {
      'id': 'payment-1',
      'amount': '200.00',
      'paymentDate': fixtureDate,
    },
    save: (_) async {},
  ),
  'ingredient-picker': InventoryIngredientPicker(items: parityStocks),
  'ingredient-create': const IngredientQuickDialog(
    initialName: 'ახალი ინგრედიენტი',
  ),
  'recipe-editor': RecipeEditorDialog(
    menuItemId: 'menu-1',
    menuItemName: 'ხინკალი ქალაქური',
    menuGroup: 'FOOD',
    stockItems: parityStocks,
    load: () async => MenuRecipeDetail.fromJson(managerRecipe),
    save: (_) async {},
    disable: (_) async {},
  ),
};
