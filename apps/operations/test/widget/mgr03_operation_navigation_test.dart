import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/apps/mobile_app/presentation/screens/create_takeaway_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/reservation_create_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/reservation_detail_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_operations_panel.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import '../unit/mgr05_order_edit_request_test.dart' show mgr05Projection;
import '../unit/mgr03_operation_request_test.dart' show mgr03Body;

void main() {
  late Directory dir;
  late HttpServer server;
  HttpOverrides? previousHttp;
  late String scope;
  final requests = <Map<String, dynamic>>[];
  final saved = <String, Map<String, dynamic>>{};
  var delivery = 'QUEUED', httpStatus = 202;
  String? code;
  Completer<void>? hold;
  final user = User(
    username: 'Synthetic manager',
    pinCode: '000000',
    role: 'manager',
  );
  Future<void> authenticate(String subject) => AuthTokenService.saveToken(
    token:
        'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': subject})))}.unsigned',
    username: 'Synthetic manager',
    role: 'MANAGER',
    expiresInSeconds: 3600,
    venueCode: 'mgr03',
  );
  Map<String, dynamic> response(Map q) => {
    'requestId': q['requestId'],
    'kind': q['kind'],
    'success': delivery == 'SUCCEEDED',
    'accepted': delivery != 'UNAVAILABLE',
    ...(q['kind'].startsWith('reservation_')
        ? {'id': 'assigned-booking'}
        : {'posOrderId': 90001}),
    'posDelivery': {
      'transport': 'edge',
      'status': delivery,
      'commandId': delivery == 'UNAVAILABLE' ? null : 'synthetic-command',
      'code': code,
    },
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr03-widget-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await ManagerOperationRequests.init();
    await authenticate('own-staff');
    delivery = 'QUEUED';
    httpStatus = 202;
    code = null;
    hold = null;
    requests.clear();
    saved.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _OwnedLoopbackHttp(server.port);
    ManagerAppPreferences.backendUrlOverride.value =
        'http://127.0.0.1:${server.port}';
    scope = MobileApiService.tableRepairScope;
    server.listen((request) async {
      Object raw;
      if (request.uri.path.startsWith('/mobile/operation-requests/')) {
        final Map<String, dynamic> q;
        if (request.method == 'POST') {
          q = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()),
          );
          q['kind'] = request.uri.path.split('/').last;
          saved[q['requestId']] = q;
        } else {
          q = saved[request.uri.path.split('/').last]!;
        }
        requests.add({...q, 'method': request.method});
        if (hold != null) await hold!.future;
        request.response.statusCode = httpStatus;
        raw = httpStatus == 202
            ? response(q)
            : {
                'message': httpStatus == 404
                    ? 'Cannot POST ${request.uri.path}'
                    : 'synthetic rejection',
              };
      } else if (request.uri.path == '/mobile/menu')
        raw = [
          {
            'items': [
              {'nameKa': 'Synthetic dish', 'price': 10},
            ],
          },
        ];
      else if (request.uri.path == '/mobile/tables')
        raw = [
          {'tableNumber': '9', 'floor': 'second', 'isReserved': false},
        ];
      else if (request.uri.path == '/mobile/reservations')
        raw = [];
      else if (request.uri.path == '/mobile/order/1')
        raw = {'editProjection': mgr05Projection()};
      else if (request.uri.path == '/mobile/restaurant-settings')
        raw = {'serviceFeeAvailable': true, 'serviceFeePercent': 10};
      else if (request.uri.path.endsWith('/print-check'))
        raw = {
          'posDelivery': {'transport': 'edge', 'status': delivery},
        };
      else {
        request.response.statusCode = 404;
        raw = {'unexpected': request.uri.path};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(raw));
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
    await t.pump(const Duration(seconds: 5));
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
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  Future<void> retained(
    String kind,
    Map<String, dynamic> body, {
    String? slot,
  }) async {
    await ManagerOperationRequests.submit(
      scope: scope,
      slot: slot ?? kind,
      kind: kind,
      body: body,
      currentSession: () => true,
      exchange: (q, _) async {
        saved[q['requestId']] = q;
        return http.Response(jsonEncode(response(q)), 202);
      },
    );
  }

  Future<GlobalKey<NavigatorState>> open(
    WidgetTester t,
    Widget screen, {
    double width = 320,
    void Function(bool?)? result,
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                final r = await Navigator.of(
                  c,
                ).push<bool>(MaterialPageRoute(builder: (_) => screen));
                result?.call(r);
              },
              child: const Text('Open operation'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open operation'));
    await pumpIO(t);
    return nav;
  }

  const reservationBody = <String, dynamic>{
    'customerName': 'Retained synthetic guest',
    'customerPhone': 'synthetic',
    'numberOfGuests': 2,
    'reservationDate': '2026-10-02',
    'reservationTime': '18:00',
    'tableNumbers': [19],
    'notes': 'Frozen guest notes',
    'preOrderItems': [],
  };
  for (final width in [320.0, 1024.0]) {
    for (final kind in ['takeaway_create', 'reservation_create']) {
      testWidgets(
        '$kind at $width reopens frozen draft, keeps QUEUED route, and pops only after POS success',
        (t) async {
          await t.runAsync(
            () => retained(
              kind,
              kind == 'takeaway_create' ? mgr03Body : reservationBody,
            ),
          );
          bool? result;
          try {
            await open(
              t,
              kind == 'takeaway_create'
                  ? CreateTakeawayScreen(user: user)
                  : ReservationCreateScreen(
                      user: user,
                      initialDate: DateTime(2026, 10, 7),
                    ),
              width: width,
              result: (v) => result = v,
            );
            expect(
              find.byType(
                kind == 'takeaway_create'
                    ? CreateTakeawayScreen
                    : ReservationCreateScreen,
              ),
              findsOneWidget,
            );
            expect(find.textContaining('POS მოთხოვნები'), findsOneWidget);
            final name = kind == 'takeaway_create'
                ? 'Synthetic guest'
                : 'Retained synthetic guest';
            expect(find.widgetWithText(TextField, name), findsOneWidget);
            final button = find.textContaining(
              kind == 'takeaway_create'
                  ? 'შეკვეთის შექმნა'
                  : 'რეზერვაციის შექმნა',
            );
            await t.scrollUntilVisible(
              button,
              250,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await t.tap(button);
            await pumpIO(t);
            expect(result, isNull);
            expect(requests.single['method'], 'GET');
            expect(
              requests.single['body'],
              kind == 'takeaway_create' ? mgr03Body : reservationBody,
            );
            expect(t.takeException(), isNull);
            delivery = 'SUCCEEDED';
            await t.pump(const Duration(seconds: 5));
            await t.pumpAndSettle();
            await t.ensureVisible(button);
            await t.tap(button);
            await pumpIO(t);
            expect(result, isTrue);
            expect(find.text('Open operation'), findsOneWidget);
            expect(t.takeException(), isNull);
          } finally {
            await cleanup(t);
          }
        },
      );
    }
    testWidgets(
      'pending panel at $width keeps known booking reference through lost status, blocks dismissal, and shows actual failed outcome',
      (t) async {
        await t.runAsync(() => retained('reservation_create', reservationBody));
        try {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ManagerOperationsPanel(scope: scope, compact: false),
                ),
              ),
            ),
          );
          await pumpIO(t);
          expect(find.text('POS ნომერი: assigned-booking'), findsOneWidget);
          expect(find.text('ჩანაწერის დახურვა'), findsNothing);
          httpStatus = 503;
          await t.tap(find.text('შედეგის შემოწმება'));
          await pumpIO(t);
          expect(find.text('POS ნომერი: assigned-booking'), findsOneWidget);
          expect(find.textContaining('შედეგი უცნობია'), findsOneWidget);
          expect(find.text('ჩანაწერის დახურვა'), findsNothing);
          httpStatus = 202;
          delivery = 'FAILED';
          code = 'manager_operation_outcome_unknown';
          await t.tap(find.text('შედეგის შემოწმება'));
          await pumpIO(t);
          expect(find.textContaining('შედეგი გაურკვეველია'), findsOneWidget);
          expect(find.text('ჩანაწერის დახურვა'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await cleanup(t);
        }
      },
    );
  }
  testWidgets(
    'fresh takeaway form creates an identical completed order with a new UUID',
    (t) async {
      try {
        final nav = await open(
          t,
          CreateTakeawayScreen(user: user),
          width: 1024,
        );
        final pickup = t
            .widget<TextField>(find.byType(TextField).at(1))
            .controller!
            .text;
        final body = {...mgr03Body, 'pickupTime': pickup};
        delivery = 'SUCCEEDED';
        await t.runAsync(() => retained('takeaway_create', body));
        final previous = ManagerOperationRequests.read(
          scope,
          'takeaway_create',
        )!['requestId'];
        nav.currentState!.pop();
        await t.pumpAndSettle();
        await t.tap(find.text('Open operation'));
        await pumpIO(t);
        expect(
          t.widget<TextField>(find.byType(TextField).first).controller!.text,
          isEmpty,
        );
        await t.enterText(find.byType(TextField).first, 'Synthetic guest');
        final menu = find.widgetWithText(ListTile, 'Synthetic dish');
        await t.scrollUntilVisible(
          menu,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final add = find.descendant(of: menu, matching: find.byIcon(Icons.add));
        await t.tap(add);
        await t.pump();
        delivery = 'QUEUED';
        await t.tap(find.textContaining('შეკვეთის შექმნა'));
        await pumpIO(t);
        expect(requests, hasLength(1));
        expect(requests.single['method'], 'POST');
        expect(requests.single['requestId'], isNot(previous));
        expect(requests.single['body'], body);
        expect(nav.currentState!.canPop(), isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'fresh reservation form creates an identical completed booking with a new UUID',
    (t) async {
      try {
        final screen = ReservationCreateScreen(
          user: user,
          initialName: 'Synthetic guest',
          initialDate: DateTime(2026, 10, 7),
        );
        final nav = await open(t, screen, width: 1024);
        final time = t
            .widgetList<Text>(find.byType(Text))
            .map((v) => v.data ?? '')
            .firstWhere((v) => RegExp(r'^\d{2}:\d{2}$').hasMatch(v));
        final body = {
          ...reservationBody,
          'customerName': 'Synthetic guest',
          'reservationDate': '2026-10-07',
          'reservationTime': time,
          'notes': '',
        };
        delivery = 'SUCCEEDED';
        await t.runAsync(() => retained('reservation_create', body));
        final previous = ManagerOperationRequests.read(
          scope,
          'reservation_create',
        )!['requestId'];
        nav.currentState!.pop();
        await t.pumpAndSettle();
        await t.tap(find.text('Open operation'));
        await pumpIO(t);
        await t.enterText(find.byType(TextField).at(1), 'synthetic');
        final button = find.text('რეზერვაციის შექმნა');
        await t.scrollUntilVisible(
          button,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.tap(button);
        await pumpIO(t);
        await t.tap(find.textContaining(' • 9'));
        await t.pump();
        delivery = 'QUEUED';
        await t.tap(find.text('დადასტურება'));
        await pumpIO(t);
        expect(requests, hasLength(1));
        expect(requests.single['method'], 'POST');
        expect(requests.single['requestId'], isNot(previous));
        expect(requests.single['body'], body);
        expect(nav.currentState!.canPop(), isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'reservation status action keeps detail open while queued and uses same UUID for POS completion',
    (t) async {
      try {
        final screen = ReservationDetailScreen(
          row: {
            'id': 'booking',
            'customerName': 'Synthetic booking',
            'status': 'pending',
            'reservationDate': '2026-10-01',
            'reservationTime': '18:00',
            'tableNumbers': [7],
          },
          operationScope: scope,
          onUpdateStatus: (id, status) =>
              MobileApiService.updateReservationStatus(
                reservationId: id,
                status: status,
                expectedScope: scope,
              ),
          onDelete: (id) =>
              MobileApiService.deleteReservation(id, expectedScope: scope),
        );
        bool? result;
        await open(t, screen, result: (v) => result = v);
        expect(find.text('დასრულება'), findsNothing);
        await t.ensureVisible(find.text('დადასტურება'));
        await t.tap(find.text('დადასტურება'));
        await pumpIO(t);
        expect(result, isNull);
        expect(requests.single['method'], 'POST');
        final id = requests.single['requestId'];
        expect(find.byType(ReservationDetailScreen), findsOneWidget);
        delivery = 'SUCCEEDED';
        await t.tap(find.text('დადასტურება'));
        await pumpIO(t);
        await t.pump(const Duration(seconds: 3));
        await t.pumpAndSettle();
        expect(result, isTrue);
        expect(requests.last['method'], 'GET');
        expect(requests.last['requestId'], id);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets('Order cancellation has no premature pop or mutation success', (
    t,
  ) async {
    try {
      bool? popped;
      await open(
        t,
        MobileOrderDetailScreen(user: user, orderId: 1),
        result: (v) => popped = v,
      );
      final cancel = find.byIcon(Icons.delete_outline_rounded);
      await t.ensureVisible(cancel);
      await t.tap(cancel);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ElevatedButton, 'გაუქმება'));
      await pumpIO(t);
      expect(popped, isNull);
      expect(requests.single['kind'], 'order_cancel');
      expect(find.byType(MobileOrderDetailScreen), findsOneWidget);
      expect(find.textContaining('POS-ს ჯერ არ შეუსრულებია'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets(
    'reservation response after session replacement cannot close old screen or report success',
    (t) async {
      await t.runAsync(() => retained('reservation_create', reservationBody));
      delivery = 'SUCCEEDED';
      hold = Completer<void>();
      try {
        bool? result;
        await open(
          t,
          ReservationCreateScreen(
            user: user,
            initialDate: DateTime(2026, 10, 7),
          ),
          result: (v) => result = v,
        );
        final button = find.text('რეზერვაციის შექმნა');
        await t.scrollUntilVisible(
          button,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.tap(button);
        await pumpIO(t);
        expect(requests, hasLength(1));
        await t.runAsync(() => authenticate('other-staff'));
        hold!.complete();
        await pumpIO(t);
        expect(result, isNull);
        expect(find.text('POS-მა შეასრულა მოთხოვნა'), findsNothing);
        expect(
          ManagerOperationRequests.all(MobileApiService.tableRepairScope),
          isEmpty,
        );
        expect(
          ManagerOperationRequests.read(scope, 'reservation_create'),
          isNotNull,
        );
        expect(t.takeException(), isNull);
      } finally {
        if (!hold!.isCompleted) hold!.complete();
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'null originating scope disables a later-session screen without sending a request',
    (t) async {
      try {
        await t.pumpWidget(
          const MaterialApp(
            home: ManagerOperationBoundary(
              scope: null,
              child: Text('Unsafe old form'),
            ),
          ),
        );
        await pumpIO(t);
        expect(find.text('Unsafe old form'), findsNothing);
        expect(find.textContaining('სესია ვერ დადასტურდა'), findsOneWidget);
        expect(requests, isEmpty);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'reservation print FAILED shows explicit error rather than printed success',
    (t) async {
      delivery = 'FAILED';
      try {
        await open(
          t,
          ReservationDetailScreen(
            row: {'id': 'booking', 'status': 'pending'},
            operationScope: scope,
            onUpdateStatus: (id, s) => MobileApiService.updateReservationStatus(
              reservationId: id,
              status: s,
              expectedScope: scope,
            ),
            onDelete: (id) =>
                MobileApiService.deleteReservation(id, expectedScope: scope),
          ),
        );
        await t.ensureVisible(find.textContaining('ჩეკის ბეჭდვა'));
        await t.tap(find.textContaining('ჩეკის ბეჭდვა'));
        await pumpIO(t);
        expect(
          find.text('POS-მა ბეჭდვის მოთხოვნა ვერ შეასრულა'),
          findsOneWidget,
        );
        expect(find.text('ჩეკი გაიგზავნა სამზარეულოში'), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
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
