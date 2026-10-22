// Real reference/production widgets. Fixtures are synthetic and local only.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import '../fixtures/manager_reference_preview/forms.dart' as reference;
import '../fixtures/manager_reference_preview/design.dart' as design;
import '../fixtures/manager_reference_preview/main.dart' as preview;
import 'finance_planning_test.dart' as fixture;

import '../fixtures/manager_approved_reference_data.dart';
import 'inventory_test_actions.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/models/receiving.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    ManagerAppPreferences.dashboardAppearance.value =
        ManagerDashboardAppearance.light;
  });
  Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
    final output = Platform.environment['MANAGER_RENDER_DIR'];
    if (output == null) return;
    await t.runAsync(() async {
      await Directory(output).create(recursive: true);
      final shot =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      shot.dispose();
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    for (final kind in ['receiving', 'receipt', 'recipe']) {
      testWidgets('matched form $kind ${size.width}', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        ManagerEntitlements.apply({
          'features': [FeatureKeys.profitability],
        });
        for (final approved in [true, false]) {
          final key = GlobalKey();
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: approved
                    ? design.previewTheme()
                    : managerMaterialTheme(ManagerDashboardAppearance.light),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      child: const Text('სინთეტიკური შედარება'),
                      onPressed: () => approved
                          ? reference.openPreviewDialog(context, kind)
                          : showDialog<void>(
                              context: context,
                              builder: (_) => switch (kind) {
                                'receiving' => ReceivingEditorDialog(
                                  suppliers: [approvedSupplier],
                                  stockItems: approvedStocks,
                                  businessDate: '2026-10-16',
                                  receiving: Receiving.fromJson({
                                    ...approvedReceiptJson,
                                    'status': 'DRAFT',
                                    'lines': [
                                      (approvedReceiptJson['lines'] as List)
                                          .first,
                                    ],
                                  }),
                                  save: (_) async {},
                                ),
                                'receipt' => ReceivingDetailDialog(
                                  receivingId: approvedReceipt.id,
                                  load: () async => approvedReceipt,
                                  onEditDraft: (_) async {},
                                ),
                                _ => RecipeEditorDialog(
                                  menuItemId: 'khachapuri',
                                  menuItemName: 'იმერული ხაჭაპური',
                                  menuGroup: 'FOOD',
                                  stockItems: approvedStocks,
                                  load: () async => approvedRecipe,
                                  save: (_) async {},
                                  disable: (_) async {},
                                ),
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('სინთეტიკური შედარება'));
          await t.pumpAndSettle();
          if (!approved && kind == 'receiving') {
            await openReceivingOptions(t);
            await t.tap(find.byKey(const Key('receiving-price-0-base')));
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('receiving-line-cost-0')),
              '18.50',
            );
            final options = find.byKey(
              const PageStorageKey('receiving-line-options-0'),
            );
            await t.tap(
              find
                  .descendant(of: options, matching: find.byType(ListTile))
                  .first,
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await t.ensureVisible(find.text('1  პროდუქტები'));
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull);
          await capture(
            t,
            key,
            '$kind-${approved ? 'approved' : 'production'}-${size.width.toInt()}',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
        }
      });
    }
    for (final kind in ['payroll', 'obligations']) {
      testWidgets('nested reference and production $kind ${size.width}', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        for (final approved in [true, false]) {
          final key = GlobalKey();
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: approved
                    ? design.previewTheme()
                    : managerMaterialTheme(ManagerDashboardAppearance.light),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => approved
                          ? reference.openPreviewDialog(context, kind)
                          : showManagerFinancePlanning(
                              context,
                              obligations: kind == 'obligations',
                              read: (_) async => kind == 'obligations'
                                  ? approvedObligations
                                  : fixture.payroll,
                            ),
                      child: const Text('Open synthetic fixture'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Open synthetic fixture'));
          await t.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          expect(t.takeException(), isNull);
          await capture(
            t,
            key,
            '$kind-${approved ? 'approved' : 'production'}-${size.width.toInt()}',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
        }
      });
    }
    for (final page in [4, 5]) {
      testWidgets('approved section $page ${size.width}', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: preview.ManagerPreview(initialPage: page),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(
          t,
          key,
          '${page == 4 ? 'inventory' : 'management-team'}-approved-${size.width.toInt()}',
        );
        if (page == 5) {
          for (final tab in ['ანგარიშები', 'აუდიტი']) {
            await t.ensureVisible(find.text(tab));
            await t.tap(find.text(tab));
            await t.pumpAndSettle();
            await capture(
              t,
              key,
              'management-${tab == 'ანგარიშები' ? 'reports' : 'activity'}-approved-${size.width.toInt()}',
            );
          }
          final settings = find.text('პარამეტრები');
          await t.ensureVisible(settings);
          await t.tap(settings);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await capture(
            t,
            key,
            'management-settings-approved-${size.width.toInt()}',
          );
        }
      });
    }
  }
}
