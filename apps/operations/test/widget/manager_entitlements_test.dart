import 'dart:io';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_inventory_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_glass_nav_bar.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';

void main() {
  tearDown(ManagerEntitlements.clear);
  testWidgets(
    'POS optional inspection responds to cached projection without Cloud',
    (tester) async {
      final directory = await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'phase2-pos-features',
        );
        Hive.init(directory.path);
        DatabaseCore.inventoryBox = await Hive.openBox('phase2-features');
        return directory;
      });
      addTearDown(() async {
        await Hive.close();
        DatabaseCore.inventoryBox = null;
        await directory!.delete(recursive: true);
      });
      await tester.runAsync(
        () => InventoryRepository.replaceCatalog({
          'features': [FeatureKeys.inventory],
          'stockItems': [],
          'suppliers': [],
          'recipes': [],
        }),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminInventorySection())),
      );
      expect(find.byKey(const Key('pos-inventory')), findsOneWidget);
      await tester.runAsync(
        () => InventoryRepository.replaceCatalog({
          'features': [],
          'stockItems': [],
          'suppliers': [],
          'recipes': [],
        }),
      );
      await tester.pump();
      expect(find.byKey(const Key('pos-inventory')), findsNothing);
      expect(InventoryRepository.getRecipes(), isEmpty);
      await tester.runAsync(
        () => InventoryRepository.replaceCatalog({
          'features': [FeatureKeys.inventory],
          'stockItems': [],
          'suppliers': [],
          'recipes': [],
        }),
      );
      await tester.pump();
      expect(find.byKey(const Key('pos-inventory')), findsOneWidget);
    },
  );
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('Module navigation hides and returns on refresh at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = PageController();
      addTearDown(pages.dispose);
      ManagerEntitlements.apply({
        'features': [
          FeatureKeys.managerApp,
          FeatureKeys.inventory,
          FeatureKeys.managerReservations,
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: ManagerEntitlements.features,
              builder: (context, features, _) {
                final items = [
                  for (final index in ManagerEntitlements.destinations)
                    ManagerAppShell.navItems[index],
                ];
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: ManagerGlassNavBar(
                    pageController: pages,
                    selectedIndex: 0,
                    itemCount: items.length,
                    items: items,
                    onTap: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('მარაგები'), findsOneWidget);
      expect(find.byTooltip('რეზერვაციები'), findsOneWidget);
      ManagerEntitlements.apply({
        'features': [FeatureKeys.managerApp],
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('მარაგები'), findsNothing);
      expect(find.byTooltip('რეზერვაციები'), findsNothing);
      expect(find.byTooltip('მართვა'), findsOneWidget);
      expect(tester.takeException(), isNull);
      ManagerEntitlements.apply({
        'features': [FeatureKeys.managerApp, FeatureKeys.inventory],
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('მარაგები'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
