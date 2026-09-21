import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_glass_nav_bar.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/inventory_summary_card.dart';
import 'package:vynic/core/models/inventory.dart';
import 'package:vynic/core/models/menu_recipe.dart';
import 'package:vynic/core/models/receiving.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';
import 'procurement_rework_test.dart' as qa;
import 'inventory_test_actions.dart';

class NavigationHarness extends StatefulWidget {
  const NavigationHarness({super.key, required this.inventory});
  final Widget inventory;
  @override
  State<NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends State<NavigationHarness> {
  final pages = PageController(initialPage: 3);
  int selected = 3;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ManagerNavigationFrame(
    backgroundColor: AdminTheme.bg,
    body: PageView(
      controller: pages,
      onPageChanged: (index) => setState(() => selected = index),
      children: [
        for (var index = 0; index < ManagerAppShell.navItems.length; index++)
          index == 3 ? widget.inventory : Center(child: Text('გვერდი $index')),
      ],
    ),
    bottomNavigationBar: ManagerGlassNavBar(
      pageController: pages,
      selectedIndex: selected,
      itemCount: ManagerAppShell.navItems.length,
      items: ManagerAppShell.navItems,
      onTap: pages.jumpToPage,
    ),
  );
}

final beef = StockItem.fromJson({
  'id': 'beef',
  'name': 'საქონლის ხორცი',
  'baseUnit': 'kg',
  'isActive': true,
});

void main() {
  setUpAll(() async {
    for (final name in ['NotoSansGeorgian', 'Ahem']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('Inventory is a main destination beside Financials', () {
    final labels = ManagerAppShell.navItems.map((item) => item.label).toList();
    expect(labels[labels.indexOf('ფინანსები') + 1], 'მარაგები');
    expect(
      MobileAdminScreen.adminTabs.any((tab) => tab.label == 'მარაგები'),
      isFalse,
    );
  });

  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(768, 700),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'last composition product and variant remain tappable above navigation $size',
      (t) async {
        qa.size(t, size.width);
        t.view.physicalSize = size;
        t.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        addTearDown(t.view.resetPadding);
        InventoryMenuSelection? chosen;
        await t.pumpWidget(
          qa.app(
            NavigationHarness(
              inventory: SafeArea(
                child: Builder(
                  builder: (context) => Theme(
                    data: inventoryTheme(context),
                    child: InventoryMenuBrowser(
                      composition: true,
                      items: [
                        for (var index = 0; index < 45; index++)
                          RecipeMenuItem(
                            menuItemId: 'dish-$index',
                            name: 'კერძი $index',
                            price: 12,
                            categoryName: 'კერძები',
                            variants: index == 43
                                ? const [
                                    RecipeMenuVariant(
                                      variantId: 'large',
                                      size: 2,
                                      price: 20,
                                    ),
                                  ]
                                : const [],
                          ),
                      ],
                      onSelected: (item) => chosen = item,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('menu-show-all')));
        await t.pumpAndSettle();
        final results = find.byKey(const Key('inventory-menu-results'));
        final scroll = t.widget<ListView>(results).controller!;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await t.pumpAndSettle();
        final last = find.byKey(const Key('recipe-card-dish-44'));
        await t.ensureVisible(last);
        await t.pumpAndSettle();
        final navTop = t.getTopLeft(find.byType(ManagerGlassNavBar)).dy;
        expect(t.getBottomRight(last).dy, lessThanOrEqualTo(navTop));
        expect(last.hitTestable(), findsOneWidget);
        await qa.shot(t, 'navigation-last-${size.width.toInt()}');
        await t.tap(last);
        expect(chosen!.item.menuItemId, 'dish-44');
        final variant = find.byKey(const Key('recipe-variant-large'));
        await t.ensureVisible(variant);
        await t.pumpAndSettle();
        await t.tap(variant);
        expect(chosen!.variant!.variantId, 'large');
        await t.tap(find.byKey(const Key('manager-nav-ფინანსები')));
        await t.pumpAndSettle();
        expect(find.text('გვერდი 2'), findsOneWidget);
        await t.tap(find.byKey(const Key('manager-nav-მარაგები')));
        await t.pumpAndSettle();
        expect(find.byType(InventoryMenuBrowser), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets(
      'receiving reviews without saving, back preserves goods and explicit payment $width',
      (t) async {
        qa.size(t, width);
        Map<String, dynamic>? sent;
        await t.pumpWidget(
          qa.app(
            ReceivingEditorDialog(
              suppliers: const [],
              stockItems: [beef],
              businessDate: '2026-09-13',
              save: (payload) async => sent = payload,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const Key('receiving-payment-mode')), findsNothing);
        await reviewReceiving(t);
        expect(find.byKey(const Key('receiving-error')), findsOneWidget);
        expect(sent, isNull);
        await qa.chooseReceivingProduct(t);
        await t.enterText(
          find.byKey(const Key('receiving-line-quantity-0')),
          '20',
        );
        await t.enterText(find.byKey(const Key('receiving-line-cost-0')), '40');
        await t.pumpAndSettle();
        // Choosing the same item again must not erase the entered quantities.
        final chosenProduct = find.byKey(
          const Key('receiving-line-item-0-beef'),
        );
        await t.ensureVisible(chosenProduct);
        await t.pumpAndSettle();
        await t.tap(chosenProduct);
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(ListTile, 'საქონლის ხორცი'));
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(
                find.byKey(const Key('receiving-line-quantity-0')),
              )
              .controller!
              .text,
          '20',
        );
        await reviewReceiving(t);
        expect(sent, isNull);
        expect(
          find.byKey(const Key('receiving-line-quantity-0')),
          findsNothing,
        );
        await t.ensureVisible(
          find.byKey(const Key('receiving-payment-partial')),
        );
        await t.tap(find.byKey(const Key('receiving-payment-partial')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('receiving-paid-now')), '300');
        await t.pumpAndSettle();
        final dueDate = find.byKey(const Key('receiving-due-date'));
        await t.ensureVisible(dueDate);
        await t.pumpAndSettle();
        await t.tap(dueDate);
        await t.pumpAndSettle();
        final calendar = find.byType(DatePickerDialog);
        expect(calendar, findsOneWidget);
        final calendarContext = t.element(calendar);
        expect(
          Theme.of(calendarContext).colorScheme.surface,
          inventoryTheme(calendarContext).colorScheme.surface,
        );
        await t.tap(
          find.text(MaterialLocalizations.of(calendarContext).okButtonLabel),
        );
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(dueDate).controller!.text,
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
        await qa.shot(t, 'guided-review-${width.toInt()}');
        await t.tap(find.byKey(const Key('receiving-back')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(
                find.byKey(const Key('receiving-line-quantity-0')),
              )
              .controller!
              .text,
          '20',
        );
        expect(sent, isNull);
        await reviewReceiving(t);
        await t.tap(find.byKey(const Key('receiving-save')));
        await t.pumpAndSettle();
        expect(sent!['post'], true);
        expect((sent!['payment'] as Map)['amount'], '300');
        expect((sent!['lines'] as List).single['stockItemId'], 'beef');
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'small keyboard viewport keeps receiving next and inline error reachable',
    (t) async {
      qa.size(t, 360);
      t.view.physicalSize = const Size(360, 640);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(t.view.resetViewInsets);
      await t.pumpWidget(
        qa.app(
          ReceivingEditorDialog(
            suppliers: const [],
            stockItems: [beef],
            businessDate: '2026-09-13',
            save: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      final next = find.byKey(const Key('receiving-next'));
      expect(next.hitTestable(), findsOneWidget);
      expect(t.getBottomRight(next).dy, lessThanOrEqualTo(360));
      await t.tap(next);
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('receiving-error')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'home is grouped and accessible in the dark main shell at large text',
    (t) async {
      qa.size(t, 360);
      final old = ManagerAppPreferences.dashboardAppearance.value;
      ManagerAppPreferences.dashboardAppearance.value =
          ManagerDashboardAppearance.dark;
      addTearDown(() => ManagerAppPreferences.dashboardAppearance.value = old);
      await t.pumpWidget(
        qa.app(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 900),
              textScaler: TextScaler.linear(1.3),
              padding: EdgeInsets.only(top: 24, bottom: 34),
            ),
            child: NavigationHarness(
              inventory: SafeArea(
                child: InventoryAdminTab(
                  loadStockItems: () async => [beef],
                  loadSuppliers: () async => [],
                  loadRecipes: () async => [],
                  loadReceivings: () async => const ReceivingPage(
                    receivings: [],
                    currentBusinessDate: '2026-09-13',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('inventory-add')).hitTestable(),
        findsOneWidget,
      );
      await qa.shot(t, 'navigation-home-dark-360');
      await openInventorySection(t, 'recipes');
      expect(find.byType(InventoryMenuBrowser), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('unfinished variants remain discoverable in composition setup', (
    t,
  ) async {
    qa.size(t, 360);
    InventoryMenuSelection? selected;
    await t.pumpWidget(
      qa.app(
        InventoryMenuBrowser(
          composition: true,
          items: const [
            RecipeMenuItem(
              menuItemId: 'beer',
              name: 'ლუდი',
              price: 5,
              variants: [
                RecipeMenuVariant(
                  variantId: 'small',
                  size: 0.3,
                  price: 5,
                  recipe: MenuRecipeSummary(
                    id: 'small-recipe',
                    isActive: true,
                    componentCount: 1,
                  ),
                ),
                RecipeMenuVariant(variantId: 'large', size: 0.5, price: 8),
              ],
            ),
          ],
          onSelected: (item) => selected = item,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-show-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('recipe-filter-unlinked')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('recipe-card-beer')), findsOneWidget);
    await t.tap(find.byKey(const Key('recipe-variant-large')));
    expect(selected!.variant!.variantId, 'large');
    await t.tap(find.byKey(const Key('recipe-filter-linked')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('recipe-card-beer')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('dashboard inventory entry works with zero warnings', (t) async {
    qa.size(t, 360);
    var opened = false;
    await t.pumpWidget(
      qa.app(
        InventorySummaryCard(
          load: () async => {
            'lowStock': 0,
            'negativeStock': 0,
            'unmappedCount': 0,
            'procurement': {
              'calendarDay': {'total': '0.00'},
            },
          },
          onOpenInventory: () => opened = true,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('dashboard-open-inventory')));
    expect(opened, true);
    expect(find.byKey(const Key('inventory-summary-low')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
