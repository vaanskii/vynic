import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/live_status_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/manager_app/table_repair_request.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

void main() {
  late Directory dir;
  late List<dynamic> tables;
  late HttpServer server;
  HttpOverrides? previousHttp;
  var tableCalls = 0, orderCalls = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr01-navigation-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    await TableRepairRequests.init();
    await AuthTokenService.saveToken(
      token:
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'mgr01-synthetic'})))}.unsigned',
      username: 'Synthetic',
      role: 'MANAGER',
      expiresInSeconds: 3600,
      venueCode: 'mgr01',
    );
    final path =
        Platform.environment['MGR01_HTTP_FIXTURE'] ??
        'test/fixtures/mgr01_table_layout.json';
    tables =
        (jsonDecode(File(path).readAsStringSync()) as Map)['tables'] as List;

    tableCalls = 0;
    orderCalls = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _OwnedLoopbackHttp(server.port);
    ManagerAppPreferences.backendUrlOverride.value =
        'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      Object response;
      final route = request.uri.path;
      if (route == '/mobile/tables') {
        tableCalls++;
        response = tables;
      } else if (route == '/mobile/takeaway-orders') {
        response = [];
      } else if (route == '/mobile/restaurant-settings') {
        response = {'serviceFeeAvailable': false};
      } else if (route == '/mobile/order/70') {
        orderCalls++;
        response = {
          'orderId': 70,
          'tableNumbers': ['10', '2'],
          'floor': 'first',
          'status': 'confirmed',
          'totalAmount': 45,
          'createdAt': '2026-10-07T10:00:00Z',
          'createdBy': 'Synthetic',
          'items': [],
        };
      } else {
        request.response.statusCode = 404;
        response = {'unexpectedFixtureEndpoint': route};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    ManagerAppPreferences.backendUrlOverride.value = null;
    HttpOverrides.global = previousHttp;
  });
  Future<void> pumpIO(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> closeStore(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final done = Completer<void>();
    Hive.close().whenComplete(done.complete);
    for (var i = 0; i < 100 && !done.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(done.isCompleted, isTrue);
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'real LiveStatus $width generic floors, merged order and repeated navigation have one refresh listener',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final nav = GlobalKey<NavigatorState>();
        final imageKey = GlobalKey();
        try {
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RepaintBoundary(
                          key: imageKey,
                          child: LiveStatusScreen(
                            user: User(
                              username: 'Synthetic',
                              pinCode: '000000',
                              role: 'manager',
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open tables'),
                  ),
                ),
              ),
            ),
          );
          for (var visit = 0; visit < 3; visit++) {
            await tester.tap(find.text('Open tables'));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(find.text('5 აქტიური • 7 სულ'), findsOneWidget);
            expect(find.text('Terrace'), findsOneWidget);
            expect(find.text('Terrace 1'), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('table-zone-first')));
            await tester.pumpAndSettle();
            expect(find.text('Main 2 · Main 10'), findsOneWidget);
            expect(find.text('45.00 ₾'), findsOneWidget);
            // A table tap navigates to the actual Manager order view; return retains
            // the configured physical rows and their original route identity.
            await tester.ensureVisible(find.text('Main 2 · Main 10'));
            await tester.tap(find.text('Main 2 · Main 10'));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(find.byType(MobileOrderDetailScreen), findsOneWidget);
            expect(orderCalls, visit + 1);
            expect(tester.takeException(), isNull);
            nav.currentState!.pop();
            await pumpIO(tester);
            await tester.pumpAndSettle();
            await tester.tap(find.text('ქართული დარბაზი'));
            await tester.pumpAndSettle();
            expect(find.text('ბაღის მაგიდა'), findsOneWidget);
            final oldCalls = tableCalls;
            MonitoringSocketService.updateCounter.value++;
            await pumpIO(tester);
            expect(tableCalls, oldCalls + 1);
            final beforeTimer = tableCalls;
            await tester.pump(const Duration(seconds: 30));
            await pumpIO(tester);
            expect(tableCalls, beforeTimer + 1);
            if (visit == 0 &&
                Platform.environment['MGR01_SCREENSHOT_DIR'] != null) {
              await tester.tap(find.byKey(const ValueKey('table-zone-first')));
              await tester.pumpAndSettle();
              final boundary =
                  imageKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${Platform.environment['MGR01_SCREENSHOT_DIR']}/mgr01-${width.toInt()}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(tester.takeException(), isNull);
            nav.currentState!.pop();
            await pumpIO(tester);
            await tester.pumpAndSettle();
            final disposedCalls = tableCalls;
            MonitoringSocketService.updateCounter.value++;
            await tester.pump(const Duration(seconds: 31));
            await pumpIO(tester);
            expect(tableCalls, disposedCalls);
          }
          final envelope = MobileCacheService.cachedRead(
            MobileApiService.tableRepairScope,
            '/mobile/tables',
          )!;
          final cached = (envelope['data'] as List)
              .map(
                (value) => TableModel.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ),
              )
              .toList();
          expect(cached.length, 7);
          expect(
            cached.any(
              (t) =>
                  t.floorLabel == 'ქართული დარბაზი' &&
                  t.tableNumber == 'Table Garden',
            ),
            isTrue,
          );
        } finally {
          await closeStore(tester);
        }
      },
    );
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
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected fixture HTTP member: ${invocation.memberName}',
  );
}
