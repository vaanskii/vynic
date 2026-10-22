// Production-gated authentication presentation, with no authentication request.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/models/manager_venue_selection.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/sync/api_config.dart';

void main() {
  late Directory directory;
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
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('manager-login-preview-');
    Hive.init(directory.path);
    await ManagerAppPreferences.init();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  for (final width in [390.0, 834.0, 1440.0]) {
    testWidgets('production login and PIN at $width', (tester) async {
      tester.view.physicalSize = Size(
        width,
        width == 834
            ? 1112
            : width == 390
            ? 844
            : 1000,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      for (final mode in ['link', 'pin']) {
        if (mode == 'pin')
          await tester.runAsync(
            () => ManagerAppPreferences.rememberVenue(
              ManagerVenueSelection(
                id: 'synthetic',
                code: 'synthetic',
                name: 'მთვარე',
                branchName: 'სინთეტიკური ფილიალი',
                address: 'თბილისი · სატესტო მისამართი',
                origin: ApiConfig.baseUrl,
              ),
            ),
          );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            theme: managerMaterialTheme(ManagerDashboardAppearance.light),
            home: RepaintBoundary(
              key: key,
              child: Column(
                children: [
                  Material(
                    color: const Color(0xFF30283E),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          'სინთეტიკური სატესტო მონაცემები · Flutter UI',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: MobileLoginScreen()),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!ApiConfig.allowDeveloperOverride)
          expect(find.text('სერვერი'), findsNothing);
        if (mode == 'pin') {
          expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
          // Hardware keyboard and delete change only the local PIN display.
          await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
          await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.label == 'PIN: 1 ციფრი შეყვანილია',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('C'));
          await tester.pumpAndSettle();
        }
        final output = Platform.environment['MANAGER_RENDER_DIR'];
        if (output != null)
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/production-login-$mode-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
