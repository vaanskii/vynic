import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/order_editor_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/widgets/service_fee_adjust_dialog.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/order_edit_request.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import '../unit/mgr05_order_edit_request_test.dart' show mgr05Projection;

void main() {
  late Directory dir;
  late HttpServer server;
  HttpOverrides? previousHttp;
  final sent = <Map<String, dynamic>>[];
  var orderCalls = 0, status = 'QUEUED';
  var legacyOnly = false, legacyMutations = 0;
  var servedProjection = mgr05Projection();
  Completer<void>? holdOrderGet;
  final postPaths = <String>[];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr05-editor-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await OrderEditRequests.init();
    await AuthTokenService.saveToken(
      token:
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'mgr05-synthetic'})))}.unsigned',
      username: 'Synthetic',
      role: 'MANAGER',
      expiresInSeconds: 3600,
      venueCode: 'mgr05',
    );
    sent.clear();
    orderCalls = 0;
    status = 'QUEUED';
    servedProjection = mgr05Projection();
    legacyOnly = false;
    legacyMutations = 0;
    holdOrderGet = null;
    postPaths.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _OwnedLoopbackHttp(server.port);
    ManagerAppPreferences.backendUrlOverride.value =
        'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      Object response;
      if (request.method == 'POST') postPaths.add(request.uri.path);
      if (request.uri.path == '/mobile/order/1' && request.method == 'GET') {
        orderCalls++;
        if (holdOrderGet != null) await holdOrderGet!.future;
        response = {'editProjection': servedProjection};
      } else if (request.uri.path == '/mobile/restaurant-settings')
        response = {'serviceFeeAvailable': true, 'serviceFeePercent': 10};
      else if (request.uri.path == '/mobile/tables')
        response = [];
      else if (request.uri.path == '/mobile/order/1' &&
          request.method == 'POST') {
        legacyMutations++;
        response = {'success': true};
      } else if (request.uri.path == '/mobile/menu')
        response = [];
      else if (request.uri.path == '/mobile/order/1/edit-request' &&
          request.method == 'POST') {
        sent.add(
          Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()),
          ),
        );
        request.response.statusCode = 202;
        final result = OrderEditProjection.read(servedProjection);
        result.items = [
          for (final raw in sent.last['items'])
            OrderItem.fromJson(Map<String, dynamic>.from(raw)),
        ];
        result.includeServiceFee = sent.last['includeServiceFee'];
        result.customServiceFeePercentage =
            (sent.last['customServiceFeePercentage'] as num?)?.toDouble();
        result.recalculateTotal(serviceFeeRate: 0.1);
        if (status == 'SUCCEEDED')
          servedProjection = OrderEditProjection.build(
            result,
            effectiveServiceFeePercent: 10,
          );
        if (legacyOnly) request.response.statusCode = 404;
        response = legacyOnly
            ? {'message': 'Cannot POST /mobile/order/1/edit-request'}
            : {
                'success': status == 'SUCCEEDED',
                'accepted': status != 'FAILED',
                'editProjection': OrderEditProjection.build(
                  result,
                  effectiveServiceFeePercent: 10,
                ),
                'posDelivery': {
                  'transport': 'edge',
                  'status': status,
                  'commandId': 'synthetic-command',
                  'code': status == 'FAILED' ? 'stale_order' : null,
                },
              };
      } else {
        request.response.statusCode = 404;
        response = {'unexpected': request.uri.path};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    HttpOverrides.global = previousHttp;
    ManagerAppPreferences.backendUrlOverride.value = null;
  });
  Future<void> pumpIO(WidgetTester t) async {
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> cleanup(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    final closed = Completer<void>();
    Hive.close().whenComplete(closed.complete);
    for (var i = 0; i < 100 && !closed.isCompleted; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(closed.isCompleted, isTrue);
    await t.runAsync(() => dir.delete(recursive: true));
  }

  for (final width in [320.0, 1024.0])
    testWidgets(
      'actual editor $width retains pending draft through repeated navigation and accurate POS result',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final nav = GlobalKey<NavigatorState>();
        try {
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderEditorScreen(
                          user: User(
                            username: 'Synthetic',
                            pinCode: '000000',
                            role: 'manager',
                          ),
                          orderId: 1,
                          tableNumber: '7',
                          floor: 'first',
                        ),
                      ),
                    ),
                    child: const Text('Open editor'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open editor'));
          await pumpIO(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.shopping_cart_outlined).first);
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.add_rounded).first);
          await tester.pumpAndSettle();
          final beforeRemote = orderCalls;
          MonitoringSocketService.updateCounter.value++;
          await pumpIO(tester);
          expect(orderCalls, beforeRemote); // unsent draft is retained
          await tester.tap(find.text('შენახვა'));
          await pumpIO(tester);
          await tester.pumpAndSettle();
          expect(sent.length, 1);
          expect(
            find.text('რიგშია — POS-ს შეკვეთა ჯერ არ შეუცვლია'),
            findsOneWidget,
          );
          expect(find.byType(OrderEditorScreen), findsOneWidget);
          final id = sent.single['requestId'];
          expect(
            sent.single['items'][0]['lineUuid'],
            'c5000000-0000-4000-8000-000000000011',
          );
          for (var visit = 0; visit < 2; visit++) {
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            nav.currentState!.pop();
            await pumpIO(tester);
            await tester.pumpAndSettle();
            final disposed = orderCalls;
            MonitoringSocketService.updateCounter.value++;
            await pumpIO(tester);
            expect(orderCalls, disposed);
            await tester.tap(find.text('Open editor'));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(
              find.text('რიგშია — POS-ს შეკვეთა ჯერ არ შეუცვლია'),
              findsOneWidget,
            );
            if (visit == 1) status = 'SUCCEEDED';
            await tester.tap(find.text('შედეგის გადამოწმება'));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(sent.last['requestId'], id);
            expect(sent.last['items'][0]['quantity'], 2);
            expect(tester.takeException(), isNull);
          }
          expect(find.byType(OrderEditorScreen), findsNothing);
          expect(sent.length, 3);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await cleanup(tester);
        }
      },
    );
  Future<GlobalKey<NavigatorState>> openScreen(
    WidgetTester tester, {
    bool detail = false,
  }) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => detail
                      ? MobileOrderDetailScreen(
                          user: User(
                            username: 'Synthetic',
                            pinCode: '000000',
                            role: 'manager',
                          ),
                          orderId: 1,
                        )
                      : OrderEditorScreen(
                          user: User(
                            username: 'Synthetic',
                            pinCode: '000000',
                            role: 'manager',
                          ),
                          orderId: 1,
                          tableNumber: '7',
                          floor: 'first',
                        ),
                ),
              ),
              child: const Text('Open owned screen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open owned screen'));
    await pumpIO(tester);
    if (holdOrderGet == null) await tester.pumpAndSettle();
    return nav;
  }

  Future<void> changeSession(WidgetTester tester) async {
    await tester.runAsync(
      () => AuthTokenService.saveToken(
        token:
            'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'different-synthetic'})))}.unsigned',
        username: 'Other',
        role: 'MANAGER',
        expiresInSeconds: 3600,
        venueCode: 'other-synthetic',
      ),
    );
  }

  for (final width in [320.0, 1024.0])
    for (final outcome in ['QUEUED', 'FAILED', 'UNAVAILABLE', 'UNKNOWN'])
      testWidgets(
        'detail fee $outcome at $width retains actual POS state and frozen delivery on reopen',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          status = outcome;
          try {
            final nav = await openScreen(tester, detail: true);
            await tester.ensureVisible(find.byType(Switch));
            await tester.tap(find.byType(Switch));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(sent, hasLength(1));
            final original = Map<String, dynamic>.from(sent.single);
            expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
            expect(
              tester.widget<Switch>(find.byType(Switch)).onChanged,
              isNull,
            );
            expect(
              find.byKey(const ValueKey('manager-order-detail-edit-status')),
              findsOneWidget,
            );
            expect(find.text('სერვისის საფასური ჩართულია'), findsNothing);
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            nav.currentState!.pop();
            await pumpIO(tester);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Open owned screen'));
            await pumpIO(tester);
            await tester.pumpAndSettle();
            expect(
              tester.widget<Switch>(find.byType(Switch)).onChanged,
              isNull,
            );
            if (outcome != 'FAILED') {
              status = 'SUCCEEDED';
              await tester.ensureVisible(find.text('შედეგის გადამოწმება'));
              await tester.tap(find.text('შედეგის გადამოწმება'));
              await pumpIO(tester);
              await tester.pumpAndSettle();
              expect(sent.last, original);
              expect(find.text('შეკვეთა შეინახა POS-მა'), findsOneWidget);
              expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
            } else
              expect(find.text('შედეგის გადამოწმება'), findsNothing);
            expect(legacyMutations, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            await cleanup(tester);
          }
        },
      );
  testWidgets('fee dialog cannot send displayed order after session changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await openScreen(tester, detail: true);
      await tester.ensureVisible(find.byIcon(Icons.tune_rounded));
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(ServiceFeeAdjustDialog),
              matching: find.byType(Switch),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await changeSession(tester);
      await tester.tap(find.text('დადასტურება'));
      await pumpIO(tester);
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      MonitoringSocketService.updateCounter.value++;
      await pumpIO(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('სესია შეიცვალა — გახსენით შეკვეთა თავიდან'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await cleanup(tester);
    }
  });
  for (final detail in [false, true])
    testWidgets(
      'HTTP load completion cannot expose editable order in a changed session, detail=$detail',
      (tester) async {
        holdOrderGet = Completer<void>();
        try {
          await openScreen(tester, detail: detail);
          expect(orderCalls, greaterThan(0));
          await changeSession(tester);
          holdOrderGet!.complete();
          await pumpIO(tester);
          await tester.pumpAndSettle();
          expect(
            find.text('სესია შეიცვალა — გახსენით შეკვეთა თავიდან'),
            findsOneWidget,
          );
          expect(sent, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          if (!holdOrderGet!.isCompleted) holdOrderGet!.complete();
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await cleanup(tester);
        }
      },
    );
  testWidgets(
    'retained editor retry cannot enter old Cloud blind replacement route',
    (tester) async {
      try {
        await openScreen(tester);
        await tester.tap(find.byIcon(Icons.shopping_cart_outlined).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add_rounded).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('შენახვა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        legacyOnly = true;
        await tester.tap(find.text('შედეგის გადამოწმება'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(sent, hasLength(2));
        expect(sent.last, sent.first);
        expect(postPaths, [
          '/mobile/order/1/edit-request',
          '/mobile/order/1/edit-request',
        ]);
        expect(legacyMutations, 0);
        expect(find.byType(OrderEditorScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await cleanup(tester);
      }
    },
  );
  testWidgets(
    'editor discard write failure stays visible and preserves frozen draft',
    (tester) async {
      status = 'FAILED';
      try {
        await openScreen(tester);
        await tester.tap(find.byIcon(Icons.shopping_cart_outlined).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add_rounded).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('შენახვა'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        final scope = MobileApiService.tableRepairScope;
        final original = OrderEditRequests.read(scope, 1)!;
        OrderEditRequests.wrapBoxForTest((box) => _FailDiscardBox(box));
        await tester.tap(find.text('განახლება და მონახაზის გაუქმება'));
        await pumpIO(tester);
        await tester.pumpAndSettle();
        expect(
          find.text('მონახაზის გაუქმება ვერ მოხერხდა — სცადეთ ხელახლა'),
          findsOneWidget,
        );
        expect(OrderEditRequests.read(scope, 1), original);
        expect(OrderEditRequests.draft(scope, 1)!.items.single.quantity, 2);
        expect(
          find.byKey(const ValueKey('manager-order-edit-status')),
          findsOneWidget,
        );
        expect(sent, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await cleanup(tester);
      }
    },
  );
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

class _FailDiscardBox implements Box {
  _FailDiscardBox(this.inner);
  final Box inner;
  @override
  bool get isOpen => inner.isOpen;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) => inner.put(key, value);
  @override
  Future<void> flush() => inner.flush();
  @override
  Future<void> delete(dynamic key) =>
      throw StateError('Owned synthetic Hive delete failure');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected fixture Box member: ${invocation.memberName}',
  );
}
