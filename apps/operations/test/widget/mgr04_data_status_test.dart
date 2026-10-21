import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_data_status.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/dashboard_screen.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final georgian = FontLoader('NotoSansGeorgian')
      ..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await georgian.load();
    await icons.load();
  });
  final theme = managerMaterialTheme(ManagerDashboardAppearance.light);
  final now = DateTime.now().toUtc();
  ManagerReadStatus status({
    String location = 'api',
    String completeness = 'KNOWN',
    bool api = true,
  }) => ManagerReadStatus(
    key: 'dashboard',
    location: location,
    source: 'POS',
    completeness: completeness,
    apiAvailable: api,
    sourceUpdatedAt: now.subtract(const Duration(hours: 2)),
    receivedAt: now.subtract(const Duration(hours: 2)),
    fetchedAt: now,
    error: api ? null : 'API მიუწვდომელია — მონაცემები ვერ განახლდა.',
  );
  setUp(() => ManagerDataReads.clear());
  for (final width in [360.0, 640.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'source details/cache age and limited operations fit width $width scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: ManagerDataStatusPanel(
                    reads: {'dashboard': status(location: 'cache', api: false)},
                  ),
                ),
              ),
            ),
          );
          expect(
            find.text('განახლება ვერ მოხერხდა · მონაცემები შეზღუდულია'),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('წყარო და დრო'));
          await tester.pump();
          expect(find.textContaining('დაფა: ქეში'), findsOneWidget);
          expect(find.textContaining(now.toIso8601String()), findsOneWidget);
          expect(find.textContaining('POS წყაროს დრო'), findsOneWidget);
          expect(find.textContaining('მხოლოდ POS-ის პასუხით'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets(
    'API up with stale POS and partial ledger remains visibly limited',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: ManagerDataStatusPanel(
                reads: {'dashboard': status(completeness: 'PARTIAL')},
              ),
            ),
          ),
        ),
      );
      expect(find.text('მონაცემები შეზღუდულია'), findsOneWidget);
      expect(find.text('მონაცემები განახლებულია'), findsNothing);
      expect(find.textContaining('განახლება ვერ მოხერხდა'), findsNothing);
      await tester.tap(find.byTooltip('წყარო და დრო'));
      await tester.pump();
      expect(find.textContaining('სისრულე: არასრული'), findsOneWidget);
      final output = Platform.environment['MGR04_WIDGET_PROOF_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/partial-source-status.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'visible read status cannot be replaced by background other query',
    (tester) async {
      ManagerDataReads.activate('scope');
      final shown = status(location: 'cache', api: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ManagerDataBoundary(
              reads: {'dashboard': shown},
              blocks: const {'dashboard'},
              child: const Text('Retained 120'),
            ),
          ),
        ),
      );
      ManagerDataReads.publish(
        'scope',
        ManagerReadStatus(
          key: 'dashboard',
          source: 'CLOUD',
          completeness: 'KNOWN',
          fetchedAt: now,
          location: 'api',
          apiAvailable: true,
        ),
      );
      await tester.pump();
      expect(
        find.text('განახლება ვერ მოხერხდა · მონაცემები შეზღუდულია'),
        findsOneWidget,
      );
      expect(find.text('მონაცემები განახლებულია'), findsNothing);
      expect(find.text('Retained 120'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('only current complete data uses the updated banner', (
    tester,
  ) async {
    final fresh = DateTime.now().toUtc();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ManagerDataStatusPanel(
            reads: {
              'dashboard': ManagerReadStatus(
                key: 'dashboard',
                location: 'api',
                source: 'POS',
                completeness: 'KNOWN',
                apiAvailable: true,
                sourceUpdatedAt: fresh,
                receivedAt: fresh,
                fetchedAt: fresh,
              ),
            },
          ),
        ),
      ),
    );
    expect(find.text('მონაცემები განახლებულია'), findsOneWidget);
    expect(find.textContaining('მონაცემები შეზღუდულია'), findsNothing);
    await tester.tap(find.byTooltip('წყარო და დრო'));
    await tester.pump();
    expect(find.textContaining('POS წყაროს დრო'), findsOneWidget);
    expect(find.textContaining('სისრულე: სრული'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'resume triggers explicit refresh and disposal removes observer',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ManagerDataBoundary(
              blocks: const {'dashboard'},
              onRefresh: () => calls++,
              child: const Text('Data'),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 1);
    },
  );
  testWidgets(
    'unavailable is distinct from empty/zero and feature-disabled is hidden',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                ManagerDataSection(
                  block: 'tables',
                  status: ManagerReadStatus(key: 'tables'),
                  child: Text('0 tables'),
                ),
                ManagerDataSection(
                  block: 'reservations',
                  status: ManagerReadStatus(
                    key: 'reservations',
                    completeness: 'DISABLED',
                  ),
                  child: Text('0 reservations'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('0 tables'), findsNothing);
      expect(find.text('0 reservations'), findsNothing);
      expect(find.textContaining('მონაცემები მიუწვდომელია'), findsOneWidget);
    },
  );
  testWidgets(
    'cold dashboard HTTP failures render unavailable instead of revenue zero',
    (tester) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('vynic-mgr04-widget-'),
      );
      await tester.runAsync(() async {
        Hive.init(dir!.path);
        await AuthTokenService.init();
        await MobileCacheService.init();
        await AuthTokenService.saveToken(
          token:
              'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'mgr04-widget'})))}.unsigned',
          username: 'Synthetic',
          role: 'MANAGER',
          expiresInSeconds: 3600,
          venueCode: 'mgr04-widget',
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: DashboardScreen(
              user: User(username: 'Synthetic', pinCode: '', role: 'manager'),
            ),
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        expect(
          find.textContaining('დაფა: მონაცემები მიუწვდომელია'),
          findsOneWidget,
        );
        expect(
          find.text('განახლება ვერ მოხერხდა · მონაცემები შეზღუდულია'),
          findsOneWidget,
        );
        expect(find.text('მონაცემები განახლებულია'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 503)));
      await tester.runAsync(() async {
        await Hive.close();
        await dir!.delete(recursive: true);
      });
    },
  );
}
