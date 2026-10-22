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
import 'package:vynic/apps/mobile_app/presentation/screens/admin_screen/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shared-report-owned-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    await AuthTokenService.saveToken(
      token:
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'shared-report'})))}.unsigned',
      username: 'Synthetic',
      role: 'MANAGER',
      expiresInSeconds: 3600,
      venueCode: 'synthetic',
    );
    ManagerEntitlements.apply({
      'features': [FeatureKeys.profitability],
    });
  });
  tearDown(() async {
    ManagerDataReads.clear();
    await Hive.close();
    await dir.delete(recursive: true);
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('missing history and recorded-name staff stay honest at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final day =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-07';
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> capture(String name) async {
        final out = Platform.environment['MANAGER_SHARED_RENDER_DIR'];
        if (out == null) return;
        await t.runAsync(() async {
          await Directory(out).create(recursive: true);
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$out/$name-${width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await http.runWithClient(
        () async {
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: managerMaterialTheme(ManagerDashboardAppearance.light),
                home: MobileAdminScreen(
                  user: User(
                    username: 'Synthetic',
                    pinCode: '',
                    role: 'manager',
                  ),
                  onLogout: () {},
                ),
              ),
            ),
          );
          await settle();
          await t.tap(find.text('ანგარიშები').first);
          await settle();
          await t.tap(find.text('თვიური გაყიდვები'));
          await settle();
          expect(
            find.textContaining('დღის გაყიდვების მონაცემები მიუწვდომელია'),
            findsOneWidget,
          );
          expect(
            find.textContaining('ჯამი მხოლოდ ხელმისაწვდომ დღეებს მოიცავს'),
            findsOneWidget,
          );
          expect(find.text('—'), findsWidgets);
          await capture('missing-daily-history');
          Navigator.of(
            t.element(
              find.textContaining('დღის გაყიდვების მონაცემები მიუწვდომელია'),
            ),
          ).pop();
          await settle();
          await t.tap(find.text('თანამშრომლების შედეგები'));
          await settle();
          expect(
            find.textContaining('მონაცემები შესაძლოა არასრული იყოს'),
            findsOneWidget,
          );
          expect(
            find.textContaining('შეკვეთის შემქმნელის ჩაწერილი სახელითაა'),
            findsOneWidget,
          );
          expect(find.textContaining('Recorded creator'), findsOneWidget);
          await capture('recorded-staff-partial');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          var closed = false;
          final closing = Hive.close().then((_) => closed = true);
          await settle();
          expect(closed, isTrue);
          await closing;
        },
        () => MockClient((request) async {
          final Object body;
          switch (request.url.path) {
            case '/mobile/sales-daily':
              body = [
                {
                  'date': day,
                  'available': false,
                  'totalRevenue': null,
                  'profit': null,
                },
              ];
            case '/mobile/sales-report':
              body = {
                'totalRevenue': 100,
                'orderCount': 1,
                'avgOrderValue': 100,
                'cashRevenue': 100,
                'cardRevenue': 0,
                'paymentBreakdown': {'cash': 100},
                'totalExpenses': 0,
                'profit': 100,
                'expenseBreakdown': [],
                'topItems': [],
                'topItemsByCategory': [],
                'staffAttribution': {'provenance': 'PARTIAL'},
                'byWaiter': [
                  {
                    'waiterName': 'Recorded creator',
                    'totalSales': 100,
                    'orderCount': 1,
                    'avgOrderValue': 100,
                  },
                ],
              };
            case '/mobile/restaurant-settings':
              body = {};
            default:
              body = [];
          }
          final now = DateTime.now().toUtc().toIso8601String();
          return http.Response(
            jsonEncode(body),
            200,
            headers: {
              'x-vynic-data-freshness': jsonEncode({
                'source': 'POS',
                'sourceUpdatedAt': now,
                'receivedAt': now,
                'completeness': request.url.path == '/mobile/sales-daily'
                    ? 'PARTIAL'
                    : 'KNOWN',
              }),
            },
          );
        }),
      );
    });
  }
}
