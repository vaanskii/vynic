import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_about_section.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('feed unavailable is a check failure, never an install offer', (
    tester,
  ) async {
    final updater = PosUpdater()
      ..configured = true
      ..state = {
        'status': 'FAILED',
        'current': '1.0.4',
        'version': '1.0.4',
        'reason':
            'Get "https://10.10.10.3:8443/pos/manifest.json": dial tcp: connectex: timeout',
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PosUpdateSettings(updater: updater)),
      ),
    );
    expect(find.text('განახლებების შემოწმება ვერ მოხერხდა'), findsOneWidget);
    expect(find.text('განახლება ვერ დასრულდა'), findsNothing);
    expect(find.text('განახლება ახლა'), findsNothing);
    expect(find.text('ხელახლა შემოწმება'), findsOneWidget);
    expect(find.text('1.0.4'), findsOneWidget);
    updater.dispose();
  });

  test(
    'lost Edge connection retains release state and prevents install until reconnection',
    () async {
      var online = false;
      final updater =
          PosUpdater(
              requestOverride: (_, _) async {
                if (!online) throw const SocketException('connection refused');
                return {
                  'status': 'READY_TO_INSTALL',
                  'current': '1.0.4',
                  'version': '1.0.5',
                };
              },
            )
            ..configured = true
            ..state = {
              'status': 'READY_TO_INSTALL',
              'current': '1.0.4',
              'version': '1.0.5',
            };
      await updater.refresh();
      expect(updater.state['status'], 'READY_TO_INSTALL');
      expect(updater.connectionIssue, isNotNull);
      expect(updater.hasStagedUpdate, isFalse);
      online = true;
      await updater.refresh();
      expect(updater.connectionIssue, isNull);
      expect(updater.hasStagedUpdate, isTrue);
      updater.dispose();
    },
  );

  testWidgets(
    'running version survives stale Edge state and rollback remains visible',
    (tester) async {
      final updater =
          PosUpdater(environmentOverride: {'VYNIC_POS_UPDATE_VERSION': '1.0.8'})
            ..configured = true
            ..state = {'status': 'UP_TO_DATE', 'current': '1.0.7'};
      addTearDown(updater.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosUpdateSettings(updater: updater)),
        ),
      );
      expect(find.text('1.0.8'), findsOneWidget);
      expect(find.text('1.0.7'), findsNothing);
      updater.state = {
        'status': 'CHECKING',
        'current': '',
        'lastOutcome': 'ROLLED_BACK',
      };
      updater.notifyListeners();
      await tester.pump();
      expect(find.text('1.0.8'), findsOneWidget);
      expect(find.textContaining('წინა ვერსია აღდგენილია'), findsOneWidget);
      updater.state = {
        'status': 'UP_TO_DATE',
        'current': '1.0.8',
        'lastOutcome': 'SUCCESS',
      };
      updater.notifyListeners();
      await tester.pump();
      expect(find.textContaining('წინა ვერსია აღდგენილია'), findsNothing);
      final restored = PosUpdater(
        environmentOverride: {'VYNIC_POS_UPDATE_VERSION': '1.0.7'},
      )..state = {'current': '1.0.8', 'status': 'RESTARTING'};
      expect(restored.currentVersion, '1.0.7');
      restored.dispose();
    },
  );

  testWidgets(
    'preparation and installation show progress while blocked explains no install',
    (tester) async {
      final u = PosUpdater()
        ..configured = true
        ..state = {
          'status': 'READY_TO_INSTALL',
          'current': '1.0.4',
          'version': '1.0.6',
        };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosUpdateSettings(updater: u)),
        ),
      );
      u.preparingInstall = true;
      u.installStage = 'ინახება მონაცემები';
      u.notifyListeners();
      await tester.pump();
      expect(find.text('ინახება მონაცემები'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      u.preparingInstall = false;
      u.installing = true;
      u.state = {...u.state, 'status': 'RESTARTING'};
      u.notifyListeners();
      await tester.pump();
      expect(find.text('POS თავიდან ირთვება'), findsOneWidget);
      u.installing = false;
      u.localBlock = 'მიმდინარეობს მაგიდის დახურვა';
      u.notifyListeners();
      await tester.pump();
      expect(find.textContaining('განახლება არ დაწყებულა'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      u.dispose();
    },
  );

  testWidgets(
    'About and update dialog render Georgian at desktop and narrow sizes',
    (tester) async {
      final updater = PosUpdater()
        ..configured = true
        ..state = {
          'status': 'READY_TO_INSTALL',
          'current': '1.0.4',
          'version': '1.0.5',
        };
      addTearDown(updater.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final (width, scale) in [
        for (final width in [1280.0, 1024.0, 600.0, 360.0])
          for (final scale in [1.0, 1.5]) (width, scale),
      ]) {
        final aboutShot = GlobalKey();
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: aboutShot,
              child: Scaffold(body: AdminAboutSection(updater: updater)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final content = tester.getRect(
          find.byKey(const ValueKey('pos-about-content')),
        );
        expect(content.center.dx, closeTo(width / 2, 1));
        expect(content.width, lessThanOrEqualTo(760));
        expect(find.text('პროგრამის შესახებ'), findsOneWidget);
        expect(find.text('1.0.4'), findsOneWidget);
        expect(find.text('1.0.5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['VYNIC_DUMP_DIR'];
        if (directory != null && scale == 1.0) {
          final boundary =
              aboutShot.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/about-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.physicalSize = const Size(1000, 780);
      final shotKey = GlobalKey();
      late BuildContext context;
      await tester.pumpWidget(
        RepaintBoundary(
          key: shotKey,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      final dialog = showPosUpdateDialog(context, updater: updater);
      await tester.pumpAndSettle();
      expect(find.text('განახლება ახლა'), findsOneWidget);
      expect(find.text('დაყენებული ვერსია'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final out = Platform.environment['VYNIC_DUMP_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final boundary =
              tester.renderObject(find.byKey(shotKey)) as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$out/update-dialog.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byTooltip('დახურვა'));
      await tester.pumpAndSettle();
      await dialog;
    },
  );
}
