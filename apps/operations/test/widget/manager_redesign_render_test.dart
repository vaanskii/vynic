// Real Manager widgets, synthetic records served only on this test's loopback port.
// Optional PNG output is widget-renderer evidence, not a native-device capture.
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_data_status.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_tab_keep_alive.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_operations_panel.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/dashboard_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/create_takeaway_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/notifications_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/live_status_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/staff_performance_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/reservation_create_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_counted_menus_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_glass_nav_bar.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/manager_app/table_repair_request.dart';
import '../fixtures/manager_redesign_fixture.dart';
import '../fixtures/manager_parity_surfaces.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/manager_counting_screen.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_modal.dart';
import 'manager_financial_ledger_test.dart' as ledger;
import 'finance_planning_test.dart' as planning;
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/core/models/manager_venue_selection.dart';

import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';

final manager = User(username: 'ნინო', pinCode: '0000', role: 'manager');
const navItems = [
  ManagerNavItem(label: 'დაფა', icon: Icons.dashboard_outlined),
  ManagerNavItem(label: 'მაგიდები', icon: Icons.table_restaurant_outlined),
  ManagerNavItem(
    label: 'ფინანსები',
    icon: Icons.account_balance_wallet_outlined,
  ),
  ManagerNavItem(label: 'მარაგები', icon: Icons.inventory_2_outlined),
  ManagerNavItem(label: 'რეზერვაციები', icon: Icons.event_note_outlined),
  ManagerNavItem(label: 'მართვა', icon: Icons.tune),
];

void main() {
  late Directory store;
  late HttpServer server;
  HttpOverrides? previousHttp;
  final unexpected = <String>[];
  late List<dynamic> drafts;
  bool matchedOrder = false;
  final writes = <Map<String, dynamic>>[];
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
    if (Platform.environment['MANAGER_APPROVED_DATA'] == '1')
      useApprovedDashboardFixture();
    store = await Directory.systemTemp.createTemp('vynic-manager-render-');
    Hive.init(store.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    await TableRepairRequests.init();
    await ManagerAppPreferences.init();
    await AuthTokenService.saveToken(
      token:
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'ui-fixture'})))}.unsigned',
      username: 'ნინო',
      role: 'MANAGER',
      expiresInSeconds: 3600,
      venueCode: 'ui-fixture',
    );
    ManagerEntitlements.apply({
      'profile': {
        'name': 'სინთეტიკური რესტორანი',
        'branchName': 'ცენტრი',
        'address': 'თბილისი, სატესტო ქუჩა 1',
      },
      'features': [
        FeatureKeys.managerApp,
        FeatureKeys.inventory,
        FeatureKeys.payroll,
        FeatureKeys.financialPlanning,
        FeatureKeys.profitability,
        FeatureKeys.managerReservations,
        FeatureKeys.advancedAudit,
      ],
    });
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _OwnedLoopbackHttp(server.port);
    ManagerAppPreferences.backendUrlOverride.value =
        'http://127.0.0.1:${server.port}';
    MonitoringSocketService.isConnected.value = true;
    MonitoringSocketService.apiError.value = false;
    matchedOrder = false;
    unexpected.clear();
    writes.clear();
    drafts = jsonDecode(jsonEncode(managerCounted)) as List;
    server.listen((request) async {
      Object? response;
      if (request.method == 'POST' &&
          request.uri.path.startsWith('/mobile/counted-menu/')) {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        writes.add({'path': request.uri.path, ...body});
        final id = request.uri.path.split('/')[3];
        if (id == 'save')
          drafts.add({
            'id': 'count-new',
            'createdAt': fixtureNow,
            ...body,
            'total': (body['subtotal'] as num) * 1.1,
            'serviceFeeRate': .1,
          });
        if (request.uri.path.endsWith('/update')) {
          final index = drafts.indexWhere((d) => d['id'] == id);
          drafts[index] = {
            ...drafts[index],
            ...body,
            'total': (body['subtotal'] as num) * 1.1,
          };
        }
        if (request.uri.path.endsWith('/delete'))
          drafts.removeWhere((d) => d['id'] == id);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'ok': true,
            'posDelivery': {'status': 'QUEUED'},
          }),
        );
        await request.response.close();
        return;
      }
      switch (request.uri.path) {
        case '/mobile/dashboard':
          response = managerDashboard;
        case '/mobile/financials':
          response = {
            'businessDate': fixtureDate,
            'procurement': {'businessDate': fixtureDate},
            'totalOutflows':
                Platform.environment['MANAGER_APPROVED_DATA'] == '1'
                ? '2180.00'
                : '1800.00',
            'differenceExact':
                Platform.environment['MANAGER_APPROVED_DATA'] == '1'
                ? '6270.00'
                : '6620.00',
          };
        case '/mobile/tables':
          response = managerTables;
        case '/mobile/takeaway-orders':
          response = <Object>[];
        case '/mobile/reservations':
          response = managerReservations;
        case '/mobile/sales':
          response = {
            'sales': [ledger.saleSummary()],
          };
        case '/mobile/users':
          response = managerUsers;
        case '/mobile/audit':
          response = managerAudits;
        case '/mobile/audit-log':
          response = managerActivity;
        case '/mobile/audit-log/facets':
          response = {'actions': <Object>[], 'entityTypes': <Object>[]};
        case '/mobile/product-analytics':
          response = {
            'byQuantity': [
              for (final item in managerReport['topItems'] as List)
                {...item as Map, 'quantity': item['qty']},
            ],
            'byRevenue': const [],
            'from': fixtureDate,
            'to': fixtureDate,
          };
        case '/mobile/sales-report':
          response = managerReport;
        case '/mobile/sales-daily':
          response = Platform.environment['MANAGER_APPROVED_DATA'] == '1'
              ? [
                  for (var i = 0; i < 7; i++)
                    {
                      'date': '2026-10-${10 + i}',
                      'totalRevenue': [
                        4800.0,
                        6900.0,
                        5800.0,
                        8200.0,
                        6600.0,
                        7491.0,
                        8450.0,
                      ][i],
                    },
                ]
              : [
                  for (var i = 0; i < 7; i++)
                    {
                      'date': DateTime.now()
                          .subtract(Duration(days: i))
                          .toIso8601String()
                          .substring(0, 10),
                      'totalRevenue': 8420.0 - i * 240,
                      'totalOrders': 64 - i,
                      'closedOrders': 63 - i,
                      'cancelledOrders': 1,
                      'totalExpenses': 1800.0,
                      'profit': 6620.0 - i * 240,
                      'paymentBreakdown': {
                        'cash': 2420.0,
                        'tbc': 6000.0 - i * 240,
                      },
                      'closedTables': [
                        {
                          'tableLabel': 'მაგიდა 1',
                          'orderId': 71,
                          'totalAmount': 72.0,
                          'paymentBreakdown': {'cash': 72.0},
                          'items': [
                            {
                              'itemName': 'იმერული ხაჭაპური',
                              'quantity': 3,
                              'price': 24.0,
                            },
                          ],
                        },
                      ],
                    },
                ];
        case '/mobile/staff-performance':
          response = [
            {'waiterName': 'ნინო', 'totalSales': 3200.0, 'orderCount': 24},
            {'waiterName': 'გიორგი', 'totalSales': 2800.0, 'orderCount': 20},
          ];
        case '/mobile/menu':
          response = managerMenu;
        case '/mobile/counted-menus':
          response = drafts;
        case '/mobile/restaurant-settings':
          response = {'serviceFeeAvailable': true, 'serviceFeePercent': 10};
        case '/mobile/finance/planning':
          response = managerPlanning;
        case '/mobile/inventory/overview':
          response = managerOverview;
        case '/mobile/inventory/stock-items':
          response = managerStocks;
        case '/mobile/inventory/suppliers':
          response = managerSuppliers;
        case '/mobile/inventory/receivings':
          response = {
            'receivings': [managerReceipt],
            'currentBusinessDate': fixtureDate,
          };
        case '/mobile/inventory/recipes':
          response = managerRecipeItems;
        case '/mobile/inventory/payables':
          response = {
            'businessDate': fixtureDate,
            'receivings': [managerReceipt],
          };
        default:
          if (request.uri.path.startsWith('/mobile/order/')) {
            if (matchedOrder) {
              final order = Order(
                orderId: 1046,
                orderUuid: 'f7000000-0000-4000-8000-000000001046',
                tableNumbers: ['4'],
                floor: 'main',
                status: 'confirmed',
                totalAmount: 286,
                includeServiceFee: true,
                createdAt: DateTime(2026, 10, 16, 17, 51),
                createdBy: 'ნინო',
                items: [
                  for (final row in [
                    ('ხინკალი ქალაქური', 20, 2.0),
                    ('იმერული ხაჭაპური', 2, 18.0),
                    ('ქათმის მწვადი', 4, 22.0),
                    ('საფერავი · ბოთლი', 2, 48.0),
                  ])
                    OrderItem(
                      itemKey: row.$1,
                      itemName: row.$1,
                      quantity: row.$2,
                      unitPrice: row.$3,
                      total: row.$2 * row.$3,
                    ),
                ],
              );
              response = {
                'editProjection': OrderEditProjection.build(
                  order,
                  effectiveServiceFeePercent: 10,
                ),
              };
            } else {
              response = {
                'orderId': 71,
                'tableNumbers': ['1'],
                'floor': 'main',
                'status': 'confirmed',
                'totalAmount': 72.0,
                'createdAt': fixtureNow,
                'createdBy': 'ნინო',
                'items': [
                  {
                    'itemName': 'იმერული ხაჭაპური',
                    'quantity': 3,
                    'unitPrice': 24.0,
                    'total': 72.0,
                  },
                ],
              };
            }
          } else {
            unexpected.add(request.uri.path);
            request.response.statusCode = 404;
            response = {'unexpectedFixtureEndpoint': request.uri.path};
          }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set(
        'x-vynic-data-freshness',
        jsonEncode({
          'source': 'fixture',
          'sourceUpdatedAt': fixtureNow,
          'receivedAt': fixtureNow,
          'completeness': 'KNOWN',
        }),
      );
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    HttpOverrides.global = previousHttp;
    ManagerAppPreferences.backendUrlOverride.value = null;
    ManagerEntitlements.clear();
    MonitoringSocketService.isConnected.value = false;
  });

  Future<void> pumpIO(WidgetTester tester) async {
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> closeStore(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    final done = Completer<void>();
    Hive.close().whenComplete(done.complete);
    for (var i = 0; i < 100 && !done.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(done.isCompleted, isTrue);
    await tester.runAsync(() => store.delete(recursive: true));
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final output = Platform.environment['MANAGER_RENDER_DIR'];
    if (output == null) return;
    await tester.pump();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(
    WidgetTester tester,
    Widget screen,
    GlobalKey key,
    GlobalKey<NavigatorState> nav, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: managerMaterialTheme(
          ManagerAppPreferences.dashboardAppearance.value,
        ),
        builder: (context, child) => RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
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
                Expanded(child: child!),
              ],
            ),
          ),
        ),
        home: ManagerThemeListener(child: screen),
      ),
    );
    await pumpIO(tester);
    await tester.pumpAndSettle();
  }

  Future<void> addItem(
    WidgetTester tester,
    String name, {
    String? variant,
  }) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
    if (variant != null) {
      await tester.tap(find.text(variant));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('დამატება  ×2'));
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 780.0, 1440.0]) {
    testWidgets('matched order detail and editor $width', (tester) async {
      tester.view.physicalSize = Size(width, width == 390 ? 844 : 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ManagerAppPreferences.dashboardAppearance.value =
          ManagerDashboardAppearance.light;
      matchedOrder = true;
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      try {
        await mount(
          tester,
          MobileOrderDetailScreen(
            user: manager,
            orderId: 1046,
            tableNumber: '4',
            floor: 'main',
          ),
          key,
          nav,
        );
        expect(find.text('286.00 ₾'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'order-matched-${width.toInt()}');
        final edit = find.text('შეკვეთის რედაქტირება');
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'order-editor-${width.toInt()}');
        await tester.enterText(
          find.byKey(const Key('order-menu-search')),
          'ხაჭაპური',
        );
        await tester.pumpAndSettle();
        expect(find.text('ქართული სალათი'), findsNothing);
        await tester.enterText(find.byKey(const Key('order-menu-search')), '');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('ნახვა'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'order-cart-${width.toInt()}');

        expect(writes, isEmpty);
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
  }

  testWidgets('dashboard scroll state survives responsive reparenting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    try {
      await mount(
        tester,
        ManagerTabKeepAlive(
          storageKey: const PageStorageKey<String>('manager_main_tab_0'),
          child: DashboardScreen(user: manager),
        ),
        key,
        GlobalKey<NavigatorState>(),
      );
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      for (final size in [
        const Size(780, 900),
        const Size(1920, 1080),
        const Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'resize after a saved scroll offset: $size',
        );
      }
    } finally {
      await closeStore(tester);
    }
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('count variants save edit confirm print delete $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      drafts.clear();
      try {
        await mount(tester, MobileCountedMenusScreen(user: manager), key, nav);
        await tester.tap(find.text('ახალი დათვლა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        await addItem(tester, 'იმერული ხაჭაპური');
        await tester.tap(find.text('სასმელები'));
        await tester.pumpAndSettle();
        await addItem(tester, 'საფერავი', variant: '750 ml');
        await capture(tester, key, 'calculation-selected-${width.toInt()}');
        await tester.tap(find.text('დათვლის ნახვა'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'calculation-cart-${width.toInt()}');
        await tester.tap(find.text('შენახვა'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'სატესტო საღამო');
        await tester.tap(find.widgetWithText(TextButton, 'შენახვა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(
          writes.where((w) => w['path'] == '/mobile/counted-menu/save'),
          hasLength(1),
        );
        final payload = writes.first;
        expect(payload['subtotal'], 128.0);
        expect(payload['includeServiceFee'], true);
        expect(
          (payload['items'] as List).last['itemName'],
          'საფერავი (750 ml)',
        );
        expect(find.text('სატესტო საღამო'), findsOneWidget);
        await tester.tap(find.text('რედაქტირება'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('დათვლის ნახვა'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('შენახვა'));
        await tester.pumpAndSettle();
        expect(find.text('სატესტო საღამო'), findsOneWidget);
        await tester.tap(find.text('დადასტურება'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(
          writes.where(
            (w) => w['path'] == '/mobile/counted-menu/count-new/update',
          ),
          hasLength(1),
        );
        await tester.tap(find.text('დადასტურება'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ReservationCreateScreen), findsOneWidget);
        expect(find.text('სატესტო საღამო'), findsOneWidget);
        await capture(tester, key, 'count-to-reservation-${width.toInt()}');
        nav.currentState!.pop();
        await pumpIO(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('ჩეკის ბეჭდვა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(
          writes.where(
            (w) => w['path'] == '/mobile/counted-menu/count-new/print',
          ),
          hasLength(1),
        );
        await tester.tap(find.text('წაშლა'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'წაშლა').last);
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(drafts, isEmpty);
        expect(tester.takeException(), isNull);
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
    testWidgets('adjacent reservation and walk-in entries $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      try {
        await mount(tester, StaffPerformanceScreen(user: manager), key, nav);
        final create = find.byKey(const Key('manager-new-reservation'));
        final walkin = find.byKey(const Key('manager-walk-in'));
        expect(create, findsOneWidget);
        expect(walkin, findsOneWidget);
        await tester.tap(create);
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ReservationCreateScreen), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'კლიენტის სახელი'),
          'ანა მაისურაძე',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'ტელეფონი'),
          '555000000',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomLeft(find.text('რეზერვაციის შექმნა')).dy,
          lessThan(700),
        );
        await capture(tester, key, 'reservation-keyboard-${width.toInt()}');
        tester.view.resetViewInsets();
        nav.currentState!.pop();
        await pumpIO(tester);
        await tester.pumpAndSettle();
        await tester.tap(walkin);
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MobileCalculatorScreen>(
                find.byType(MobileCalculatorScreen),
              )
              .selectionMode,
          isTrue,
        );
        await addItem(tester, 'იმერული ხაჭაპური');
        await tester.tap(find.text(width < 1000 ? 'ნახვა' : 'დათვლის ნახვა'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('დასრულება'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(find.text('აირჩიე მაგიდა'), findsOneWidget);
        await capture(tester, key, 'walk-in-table-picker-${width.toInt()}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(StaffPerformanceScreen), findsOneWidget);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
  }

  for (final width in [390.0, 780.0, 1440.0]) {
    testWidgets('navigation count saved and keyboard $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var count = 0;
      var selected = -1;
      try {
        await mount(
          tester,
          ManagerAdaptiveNavigation(
            body: const SizedBox.expand(),
            items: navItems,
            selectedIndex: 0,
            onTap: (index) => selected = index,
            username: 'ნინო',
            venueName: 'სინთეტიკური რესტორანი',
            onNotifications: () {},
            onCalculate: () => count++,
          ),
          GlobalKey(),
          GlobalKey<NavigatorState>(),
        );
        if (width < 700) {
          expect(find.byTooltip('დათვლა'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('manager-nav-მეტი')));
          await tester.pumpAndSettle();
          expect(find.text('დათვლა'), findsOneWidget);
          expect(find.text('შენახული მენიუები'), findsNothing);
          await tester.tap(find.text('დათვლა'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('manager-nav-მეტი')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('მარაგები'));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.byKey(const ValueKey('manager-count-menu')));
          await tester.pumpAndSettle();
          expect(find.byTooltip('შენახული მენიუები'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('manager-nav-მარაგები')));
          await tester.pumpAndSettle();
        }
        expect(count, 1);
        expect(selected, 3);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(count, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await closeStore(tester);
      }
    });
  }

  for (final width in [390.0, 1440.0]) {
    testWidgets('cached unavailable and pending state $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      try {
        await tester.runAsync(() async {
          await ManagerOperationRequests.init();
          final scope = MobileApiService.tableRepairScope;
          await Hive.box(ManagerOperationRequests.boxName).put(
            ManagerOperationRequests.key(scope, 'reservation_create'),
            {
              'scope': scope,
              'slot': 'reservation_create',
              'kind': 'reservation_create',
              'requestId': 'synthetic-pending-request',
              'createdAt': DateTime.now().millisecondsSinceEpoch,
              'body': {'customerName': 'ანა მაისურაძე'},
              'result': {
                'delivery': 'queued',
                'kind': 'reservation_create',
                'requestId': 'synthetic-pending-request',
              },
            },
          );
        });
        final old = DateTime.now().toUtc().subtract(
          const Duration(minutes: 18),
        );
        await mount(
          tester,
          Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'მონაცემები და POS მოთხოვნები',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ManagerDataStatusPanel(
                      reads: {
                        'tables': ManagerReadStatus(
                          key: 'tables',
                          location: 'cache',
                          source: 'POS',
                          completeness: 'KNOWN',
                          sourceUpdatedAt: old,
                          receivedAt: old,
                          fetchedAt: old,
                          error: 'კავშირი ვერ განახლდა',
                        ),
                      },
                      onRefresh: () {},
                    ),
                    const SizedBox(height: 20),
                    ManagerOperationsPanel(
                      scope: MobileApiService.tableRepairScope,
                      compact: false,
                    ),
                    const SizedBox(height: 20),
                    const ManagerDataUnavailable(label: 'გაყიდვების ისტორია'),
                  ],
                ),
              ),
            ),
          ),
          key,
          GlobalKey<NavigatorState>(),
        );
        await tester.tap(find.byTooltip('წყარო და დრო'));
        await tester.pumpAndSettle();
        expect(find.textContaining('მოთხოვნა რიგშია'), findsOneWidget);
        expect(find.textContaining('მონაცემები მიუწვდომელია'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'data-and-pending-state-${width.toInt()}');
        expect(writes, isEmpty);
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    testWidgets('unified Count retains new saved and back ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final phone = platform != TargetPlatform.macOS;
      tester.view.physicalSize = phone
          ? const Size(390, 844)
          : const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(
        top: phone ? 44 : 0,
        bottom: phone ? 34 : 0,
      );
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      try {
        await mount(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ManagerCountingScreen(user: manager),
                  ),
                ),
                child: const Text('გახსნა'),
              ),
            ),
          ),
          key,
          nav,
        );
        await tester.tap(find.text('გახსნა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        await addItem(tester, 'იმერული ხაჭაპური');
        await tester.tap(find.byKey(const ValueKey('count-tab-saved')));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(find.text('საოჯახო ვახშამი'), findsOneWidget);
        await capture(tester, key, 'count-saved-${platform.name}');
        await tester.tap(find.byKey(const ValueKey('count-tab-new')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(phone ? 'დათვლის ნახვა' : 'დათვლის ნახვა'));
        await tester.pumpAndSettle();
        expect(find.text('იმერული ხაჭაპური'), findsWidgets);
        await tester.tap(find.text('შენახვა'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'ერთიანი დათვლა');
        await tester.tap(find.widgetWithText(TextButton, 'შენახვა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ManagerCountingScreen), findsOneWidget);
        expect(find.text('ერთიანი დათვლა'), findsOneWidget);
        expect(writes.single['subtotal'], 48.0);
        await capture(tester, key, 'count-saved-after-save-${platform.name}');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ManagerCountingScreen), findsNothing);
        expect(tester.takeException(), isNull);
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final width in [390.0, 780.0, 834.0, 1440.0, 1728.0, 1920.0]) {
    testWidgets('nested Manager surfaces $width', (tester) async {
      tester.view.physicalSize = Size(
        width,
        width == 390
            ? 844
            : width == 834
            ? 1112
            : 900,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ManagerAppPreferences.dashboardAppearance.value =
          ManagerDashboardAppearance.light;
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      Future<void> check(String name) async {
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await capture(tester, key, '$name-${width.toInt()}');
      }

      try {
        for (final entry in parityPages().entries) {
          await tester.pumpWidget(const SizedBox.shrink());
          await mount(tester, entry.value, key, nav);
          await check(entry.key);
          if (entry.key == 'inventory-stock' ||
              entry.key == 'inventory-suppliers') {
            final add = find.byKey(const Key('inventory-add'));
            if (add.evaluate().isNotEmpty) {
              await tester.ensureVisible(add);
              await tester.tap(add);
            } else {
              await tester.tap(find.byTooltip('მოქმედებები').first);
              await tester.pumpAndSettle();
              await tester.tap(find.text('რედაქტირება'));
            }
            await check('${entry.key}-editor');
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
          if (entry.key == 'finance-history') {
            await tester.tap(find.text('ჩანაწერის კორექტირება'));
            await check('finance-correction');
            await tester.tap(find.text('დახურვა').last);
            await tester.pumpAndSettle();
          }
        }
        for (final entry in parityDialogs().entries) {
          await tester.pumpWidget(const SizedBox.shrink());
          await mount(
            tester,
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => entry.value,
                  ),
                  child: const Text('გახსნა'),
                ),
              ),
            ),
            key,
            nav,
          );
          await tester.tap(find.text('გახსნა'));
          await check(entry.key);
          final dialog = find
              .descendant(
                of: find.byType(Dialog).last,
                matching: find.byType(Material),
              )
              .first;
          expect(
            tester.getCenter(dialog).dx,
            closeTo(width / 2, 1),
            reason: '${entry.key} centered',
          );
          final fields = find.descendant(
            of: find.byType(ManagerFormDialog),
            matching: find.byType(EditableText),
          );
          if (width == 390 && fields.evaluate().isNotEmpty) {
            await tester.tap(fields.first);
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key} keyboard',
            );
            expect(
              tester.getBottomLeft(dialog).dy,
              lessThanOrEqualTo(544),
              reason: '${entry.key} stays above keyboard',
            );
            await capture(tester, key, '${entry.key}-keyboard-390');
            tester.view.resetViewInsets();
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.byType(Dialog),
            findsNothing,
            reason: '${entry.key} dismisses via Escape',
          );
        }
        expect(writes, isEmpty);
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
  }

  for (final spec in [
    (const Size(390, 844), ManagerDashboardAppearance.light, 1.0),
    (const Size(834, 1112), ManagerDashboardAppearance.light, 1.0),
    (const Size(780, 900), ManagerDashboardAppearance.light, 1.0),
    (const Size(1440, 900), ManagerDashboardAppearance.light, 1.0),
    (const Size(1728, 1117), ManagerDashboardAppearance.light, 1.0),
    (const Size(1920, 1080), ManagerDashboardAppearance.light, 1.0),
    (const Size(390, 844), ManagerDashboardAppearance.dark, 1.0),
    (const Size(1440, 1000), ManagerDashboardAppearance.dark, 1.0),
    (const Size(320, 900), ManagerDashboardAppearance.light, 1.3),
  ]) {
    final viewport = spec.$1;
    final suffix = spec.$2 == ManagerDashboardAppearance.dark
        ? '-dark'
        : spec.$3 > 1
        ? '-scaled'
        : '';
    testWidgets('real Manager surfaces ${viewport.width}$suffix', (
      tester,
    ) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ManagerAppPreferences.dashboardAppearance.value = spec.$2;
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      final screens = <String, Widget>{
        'dashboard': DashboardScreen(user: manager),
        'tables': LiveStatusScreen(user: manager),
        'reservations': StaffPerformanceScreen(user: manager),
        'financials': FinancialsScreen(
          user: manager,
          loadData: () async => ledger.fixture(sales: [ledger.saleSummary()]),
          loadSale: (_) async => ledger.saleDetail(),
        ),
        'inventory': const InventoryAdminTab(),
        'management': MobileAdminScreen(user: manager, onLogout: () {}),
        'calculation': ManagerCountingScreen(user: manager),
        'saved-menus': MobileCountedMenusScreen(user: manager),
        'login': const MobileLoginScreen(),
        'payroll': FinancePlanningScreen(read: (_) async => planning.payroll),
        'obligations': FinancePlanningScreen(
          obligations: true,
          read: (_) async => planning.obligations,
        ),
        'takeaway-create': CreateTakeawayScreen(user: manager),
        'notifications': NotificationsScreen(
          onEntryTap: (_) {},
          onClear: () {},
        ),
      };
      try {
        for (final entry in screens.entries) {
          final renderOnly = Platform.environment['MANAGER_RENDER_ONLY'];
          if (renderOnly != null && !renderOnly.split(',').contains(entry.key))
            continue;
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpIO(tester);
          final index = {
            'dashboard': 0,
            'tables': 1,
            'financials': 2,
            'inventory': 3,
            'reservations': 4,
            'management': 5,
          }[entry.key];
          final page = index == null
              ? entry.value
              : ManagerAdaptiveNavigation(
                  body: ManagerTabKeepAlive(
                    storageKey: PageStorageKey<String>(
                      'manager_main_tab_$index',
                    ),
                    child: entry.value,
                  ),
                  items: navItems,
                  selectedIndex: index,
                  onTap: (_) {},
                  username: 'ნინო',
                  venueName: 'სინთეტიკური რესტორანი',
                  onNotifications: () {},
                  onCalculate: () {},
                );
          await mount(tester, page, key, nav, scale: spec.$3);
          await pumpIO(tester);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: entry.key);
          if (entry.key == 'dashboard') {
            expect(find.text('მენიუს დათვლა'), findsNothing);
            expect(
              find.byKey(const ValueKey('manager-count-menu')),
              viewport.width < 700 ? findsNothing : findsOneWidget,
            );
            expect(
              find.byTooltip('დათვლა'),
              viewport.width < 700 ? findsNothing : findsOneWidget,
            );
          }
          await capture(
            tester,
            key,
            '${entry.key}-${viewport.width.toInt()}$suffix',
          );
          if (entry.key == 'tables' && viewport.width == 1440) {
            await tester.tap(find.text('01'));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              key,
              'order-inspector-${viewport.width.toInt()}$suffix',
            );
          }
          if (entry.key == 'management') {
            for (final tab in [
              'ანგარიშები',
              'ანგარიში',
              'პროდუქტები',
              'თანამშრომლები',
              'გაყიდვები',
              'აუდიტი',
              'აქტივობა',
              'გუნდი',
              'პარამეტრები',
            ]) {
              final parent = switch (tab) {
                'ანგარიშები' ||
                'ანგარიში' ||
                'გაყიდვები' ||
                'პროდუქტები' ||
                'თანამშრომლები' => 'ანგარიშები',
                'აქტივობა' => 'აუდიტი',
                _ => tab,
              };
              final topTab = find.byKey(ValueKey('manager-top-tab-$parent'));
              await tester.ensureVisible(topTab);
              await tester.tap(topTab);
              await pumpIO(tester);
              await pumpIO(tester);
              await tester.pumpAndSettle();
              final reportKind = const {
                'ანგარიში': 'დღის ანგარიში',
                'გაყიდვები': 'თვიური გაყიდვები',
                'პროდუქტები': 'პროდუქტების შედეგები',
                'თანამშრომლები': 'თანამშრომლების შედეგები',
              }[tab];
              if (reportKind != null) {
                await tester.tap(find.text(reportKind));
                await pumpIO(tester);
                await tester.pumpAndSettle();
              }
              if (tab == 'აუდიტი') {
                await tester.tap(find.byTooltip('აუდიტის სხვა ხედები'));
                await tester.pumpAndSettle();
                await tester.tap(find.text('ოპერაციული აუდიტი'));
                await pumpIO(tester);
                await tester.pumpAndSettle();
              }
              await pumpIO(tester);
              await pumpIO(tester);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: tab);
              await capture(
                tester,
                key,
                'management-${{'ანგარიშები': 'reports', 'პროდუქტები': 'products', 'თანამშრომლები': 'staff', 'ანგარიში': 'report', 'გუნდი': 'team', 'პარამეტრები': 'settings', 'გაყიდვები': 'sales', 'აუდიტი': 'audit', 'აქტივობა': 'activity'}[tab]}-${viewport.width.toInt()}$suffix',
              );
              Future<void> dialogShot(String name) async {
                await pumpIO(tester);
                await pumpIO(tester);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: name);
                expect(
                  find.byType(Dialog),
                  findsNWidgets(
                    (reportKind != null || tab == 'აუდიტი') ? 2 : 1,
                  ),
                  reason: name,
                );
                await capture(
                  tester,
                  key,
                  '$name-${viewport.width.toInt()}$suffix',
                );
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await pumpIO(tester);
                await tester.pumpAndSettle();
              }

              if (tab == 'გუნდი') {
                await tester.tap(find.text('თანამშრომლის დამატება'));
                await dialogShot('team-create');
                for (final action in [
                  'სახელის შეცვლა',
                  'PIN-ის შეცვლა',
                  'როლის შეცვლა',
                  'წაშლა',
                ]) {
                  await tester.tap(find.byTooltip('მოქმედებები').first);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                  await tester.tap(find.text(action));
                  await dialogShot(
                    'team-${{'სახელის შეცვლა': 'name', 'PIN-ის შეცვლა': 'pin', 'როლის შეცვლა': 'role', 'წაშლა': 'delete'}[action]}',
                  );
                }
              }
              if (tab == 'პარამეტრები') {
                await tester.tap(find.text('რესტორნის პროფილი'));
                await dialogShot('venue-profile');
                final connection = find.text('კავშირი');
                if (connection.evaluate().isNotEmpty) {
                  await tester.ensureVisible(connection);
                  await tester.tap(connection);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                  final backend = find.text('Backend');
                  await tester.ensureVisible(backend);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                  await tester.tap(backend);
                  await pumpIO(tester);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  await capture(
                    tester,
                    key,
                    'backend-setting-${viewport.width.toInt()}$suffix',
                  );
                  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                }
              }
              if (tab == 'გაყიდვები') {
                final header = find
                    .descendant(
                      of: find.byType(ExpansionTile).first,
                      matching: find.byType(ListTile),
                    )
                    .first;
                await tester.ensureVisible(header);
                await pumpIO(tester);
                await tester.pumpAndSettle();
                await tester.tap(header);
                await pumpIO(tester);
                await tester.pumpAndSettle();
                await tester.ensureVisible(find.text('მაგიდა: მაგიდა 1').first);
                await capture(
                  tester,
                  key,
                  'sales-day-${viewport.width.toInt()}$suffix',
                );
                await tester.tap(find.text('მაგიდა: მაგიდა 1').first);
                await dialogShot('sales-detail');
              }
              if (tab == 'აუდიტი') {
                if (find.text('დეტალები').evaluate().isEmpty) {
                  final header = find
                      .descendant(
                        of: find.byType(ExpansionTile).first,
                        matching: find.byType(ListTile),
                      )
                      .first;
                  await tester.ensureVisible(header);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                  await tester.tap(header);
                  await pumpIO(tester);
                  await tester.pumpAndSettle();
                }
                await tester.ensureVisible(find.text('დეტალები').first);
                await pumpIO(tester);
                await tester.pumpAndSettle();
                await tester.tap(find.text('დეტალები').first);
                await dialogShot('audit-timeline');
              }
              if (tab == 'აქტივობა') {
                await tester.tap(find.text('ფილტრები'));
                await dialogShot('activity-filters');
                await tester.tap(find.textContaining('იმერული ხაჭაპური').first);
                await pumpIO(tester);
                await tester.pumpAndSettle();
                await capture(
                  tester,
                  key,
                  'activity-detail-${viewport.width.toInt()}$suffix',
                );
                await tester.tap(find.text('ობიექტის ისტორია'));
                await pumpIO(tester);
                await tester.pumpAndSettle();
                await capture(
                  tester,
                  key,
                  'activity-subject-${viewport.width.toInt()}$suffix',
                );
                expect(tester.takeException(), isNull);
              }
              if (reportKind != null || tab == 'აუდიტი') {
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await pumpIO(tester);
                await tester.pumpAndSettle();
              }
            }
          }
          if (entry.key == 'login') {
            await tester.runAsync(
              () => ManagerAppPreferences.rememberVenue(
                ManagerVenueSelection(
                  id: 'fixture',
                  code: 'ui-fixture',
                  name: 'სინთეტიკური რესტორანი',
                  branchName: 'ცენტრი',
                  address: 'თბილისი, სატესტო ქუჩა 1',
                  origin: 'http://127.0.0.1:${server.port}',
                ),
              ),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await mount(
              tester,
              const MobileLoginScreen(),
              key,
              nav,
              scale: spec.$3,
            );
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              key,
              'login-pin-${viewport.width.toInt()}$suffix',
            );
          }
        }
        expect(unexpected, isEmpty);
      } finally {
        await closeStore(tester);
      }
    });
  }
}

class _OwnedLoopbackHttp extends HttpOverrides {
  _OwnedLoopbackHttp(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OnlyOwnedHttp(super.createHttpClient(context), port);
}

class _OnlyOwnedHttp implements HttpClient {
  _OnlyOwnedHttp(this.inner, this.port);
  final HttpClient inner;
  final int port;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (url.scheme != 'http' || url.host != '127.0.0.1' || url.port != port)
      throw StateError('Fixture forbids external HTTP: $url');
    return inner.openUrl(method, url);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected HTTP member ${invocation.memberName}');
}
