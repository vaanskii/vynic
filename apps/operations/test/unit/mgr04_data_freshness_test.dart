import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/data/repositories/dashboard_repository.dart';
import 'package:vynic/apps/mobile_app/data/services/dashboard_remote_service.dart';
import 'package:vynic/apps/mobile_app/presentation/controllers/dashboard_controller.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  Future<void> session(String principal) => AuthTokenService.saveToken(
    token:
        'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': principal})))}.unsigned',
    username: 'Synthetic',
    role: 'MANAGER',
    expiresInSeconds: 3600,
    venueCode: principal,
  );
  Map<String, dynamic> metrics(double revenue) => {
    'todayRevenue': revenue,
    'openTablesPayable': 45,
    'totalTables': 3,
    'snapshotAt': '2026-10-07T09:00:00Z',
  };
  http.Response response(
    Object body, {
    String sourceTime = '2026-10-07T09:00:00Z',
    String? completeness,
    int status = 200,
  }) => http.Response(
    jsonEncode(body),
    status,
    headers: {
      'x-vynic-data-freshness': jsonEncode({
        'source': 'POS',
        'sourceUpdatedAt': sourceTime,
        'receivedAt': sourceTime,
        'completeness': completeness ?? 'KNOWN',
      }),
    },
  );
  Future<T> run<T>(
    Future<T> Function() action,
    FutureOr<http.Response> Function(http.Request) handler,
  ) => http.runWithClient(
    action,
    () => MockClient((request) async => await handler(request)),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr04-read-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    ManagerDataReads.clear();
    await session('mgr04-a');
  });
  tearDown(() async {
    ManagerAppPreferences.backendUrlOverride.value = null;
    ManagerDataReads.clear();
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'warm cache/API down preserves source and fetch times and keeps API error',
    () async {
      await run(MobileApiService.getDashboard, (_) => response(metrics(120)));
      final previous = ManagerDataReads.statuses.value['dashboard']!;
      final cached = await run(
        MobileApiService.getDashboard,
        (_) => response({}, status: 503),
      );
      final status = ManagerDataReads.statuses.value['dashboard']!;
      expect(cached.todayRevenue, 120);
      expect(status.location, 'cache');
      expect(status.fetchedAt, previous.fetchedAt);
      expect(status.sourceUpdatedAt, previous.sourceUpdatedAt);
      expect(status.apiAvailable, isFalse);
      expect(MonitoringSocketService.apiError.value, isTrue);
      await run(MobileApiService.getTables, (_) => response([]));
      expect(MonitoringSocketService.apiError.value, isTrue);
    },
  );
  test(
    'API up/POS stopped has new fetch time but old source and limited operations',
    () async {
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      await run(
        MobileApiService.getDashboard,
        (_) => response(metrics(120), sourceTime: old),
      );
      final status = ManagerDataReads.statuses.value['dashboard']!;
      expect(status.apiAvailable, isTrue);
      expect(status.sourceUpdatedAt, DateTime.parse(old));
      expect(status.fetchedAt!.isAfter(status.sourceUpdatedAt!), isTrue);
      expect(status.limitedAt(DateTime.now()), isTrue);
    },
  );
  test(
    'offline network failure after store reopen retains durable cache envelope',
    () async {
      await run(MobileApiService.getDashboard, (_) => response(metrics(120)));
      final original = ManagerDataReads.statuses.value['dashboard']!;
      await Hive.box('mobile_manager_cache').close();
      await MobileCacheService.init();
      final value = await run(
        MobileApiService.getDashboard,
        (_) => throw const SocketException('Synthetic offline'),
      );
      expect(value.todayRevenue, 120);
      expect(
        ManagerDataReads.statuses.value['dashboard']!.fetchedAt,
        original.fetchedAt,
      );
      expect(
        ManagerDataReads.statuses.value['dashboard']!.apiAvailable,
        isFalse,
      );
    },
  );
  test('origin change cannot serve cache from previous API origin', () async {
    await run(MobileApiService.getDashboard, (_) => response(metrics(120)));
    ManagerAppPreferences.backendUrlOverride.value = 'http://127.0.0.1:54321';
    await expectLater(
      run(MobileApiService.getDashboard, (_) => response({}, status: 503)),
      throwsStateError,
    );
  });
  test(
    'simultaneous failed and successful report queries carry their own status',
    () async {
      final results = await run(
        () => Future.wait([
          MobileApiService.captureRead(
            'sales_report',
            () => MobileApiService.getSalesReport(
              period: 'month',
              month: '2026-09',
            ),
          ),
          MobileApiService.captureRead(
            'sales_report',
            () => MobileApiService.getSalesReport(period: 'today'),
          ),
        ]),
        (request) => request.url.queryParameters['period'] == 'month'
            ? response({}, status: 503)
            : response({'totalRevenue': 120}),
      );
      expect(results[0].data, isNull);
      expect(results[0].status.query, contains('month=2026-09'));
      expect(results[0].status.apiAvailable, isFalse);
      expect(results[1].status.apiAvailable, isTrue);
      expect(results[1].status.query, contains('period=today'));
      expect(ManagerDataReads.hasApiError, isTrue);
    },
  );
  test(
    'logged-out controller refresh cleans loading flag and can recover after login',
    () async {
      final controller = DashboardController(
        const DashboardRepository(DashboardRemoteService()),
      );
      await AuthTokenService.clearToken();
      await controller.loadAll();
      expect(controller.state.reads['dashboard']!.error, contains('სესია'));
      await session('mgr04-a');
      await run(
        controller.loadAll,
        (request) => request.url.path == '/mobile/dashboard'
            ? response(metrics(120))
            : const [
                '/mobile/sales-report',
                '/mobile/financials',
              ].contains(request.url.path)
            ? response({})
            : response([]),
      );
      expect(controller.state.metrics!.todayRevenue, 120);
      controller.dispose();
    },
  );
  for (final completeness in ['PARTIAL', 'LEGACY_FALLBACK']) {
    test(
      '$completeness ledger never becomes complete after cache fallback',
      () async {
        await run(
          MobileApiService.getDashboard,
          (_) =>
              response({...metrics(120), 'financialProvenance': completeness}),
        );
        await run(
          MobileApiService.getDashboard,
          (_) => response({}, status: 503),
        );
        expect(
          ManagerDataReads.statuses.value['dashboard']!.completeness,
          completeness,
        );
        expect(
          ManagerDataReads.statuses.value['dashboard']!.limitedAt(
            DateTime.now(),
          ),
          isTrue,
        );
      },
    );
  }
  test(
    'cold failed or incomplete response is unavailable, not zero metrics',
    () async {
      await expectLater(
        run(MobileApiService.getDashboard, (_) => response({}, status: 503)),
        throwsStateError,
      );
      expect(
        ManagerDataReads.statuses.value['dashboard']!.location,
        'unavailable',
      );
      await expectLater(
        run(MobileApiService.getDashboard, (_) => response({})),
        throwsStateError,
      );
      expect(ManagerDataReads.statuses.value['dashboard']!.fetchedAt, isNull);
    },
  );
  test(
    'known zero remains a genuine value and model retains source time',
    () async {
      final value = await run(
        MobileApiService.getDashboard,
        (_) => response(metrics(0)),
      );
      expect(value.todayRevenue, 0);
      expect(
        ManagerDashboardMetrics.fromJson(value.toJson()).snapshotAt,
        '2026-10-07T09:00:00Z',
      );
    },
  );
  test(
    'legacy missing provenance never substitutes HTTP time for POS source',
    () async {
      await run(
        MobileApiService.getDashboard,
        (_) => http.Response(jsonEncode(metrics(120)), 200),
      );
      final status = ManagerDataReads.statuses.value['dashboard']!;
      expect(status.source, 'UNKNOWN');
      expect(status.sourceUpdatedAt, isNull);
      expect(status.limitedAt(DateTime.now()), isTrue);
    },
  );
  test('query cache isolates reservation dates', () async {
    await run(
      () => MobileApiService.getReservations(date: '2026-10-07'),
      (_) => response([
        {'id': 'day7'},
      ]),
    );
    await expectLater(
      run(
        () => MobileApiService.getReservations(date: '2026-10-08'),
        (_) => response({}, status: 503),
      ),
      throwsStateError,
    );
    final cached = await run(
      () => MobileApiService.getReservations(date: '2026-10-07'),
      (_) => response({}, status: 503),
    );
    expect(cached.single['id'], 'day7');
  });
  for (final change in ['principal', 'logout', 'token_refresh']) {
    test(
      'late $change read cannot write cache, registry or return old data',
      () async {
        final pending = Completer<http.Response>();
        final entered = Completer<void>();
        final oldScope = MobileApiService.tableRepairScope;
        final future = run(MobileApiService.getDashboard, (_) {
          entered.complete();
          return pending.future;
        });
        final expected = expectLater(future, throwsStateError);
        await entered.future;
        if (change == 'logout')
          await AuthTokenService.clearToken();
        else if (change == 'principal')
          await session('mgr04-b');
        else
          await AuthTokenService.saveToken(
            token:
                'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'mgr04-a', 'renewed': true})))}.unsigned',
            username: 'Synthetic',
            role: 'MANAGER',
            expiresInSeconds: 3600,
            venueCode: 'mgr04-a',
          );
        pending.complete(response(metrics(777)));
        await expected;
        expect(
          MobileCacheService.cachedRead(oldScope, '/mobile/dashboard'),
          isNull,
        );
        expect(ManagerDataReads.statuses.value, isEmpty);
      },
    );
  }
  test(
    'cache cannot cross principal or origin and 403 cannot expose it',
    () async {
      await run(MobileApiService.getDashboard, (_) => response(metrics(120)));
      await expectLater(
        run(MobileApiService.getDashboard, (_) => response({}, status: 403)),
        throwsStateError,
      );
      await session('mgr04-b');
      await expectLater(
        run(MobileApiService.getDashboard, (_) => response({}, status: 503)),
        throwsStateError,
      );
    },
  );
  test(
    'cache write failure exposes remote data and explicit persistence error',
    () async {
      await Hive.box('mobile_manager_cache').close();
      final value = await run(
        MobileApiService.getDashboard,
        (_) => response(metrics(120)),
      );
      expect(value.todayRevenue, 120);
      final status = ManagerDataReads.statuses.value['dashboard']!;
      expect(status.apiAvailable, isTrue);
      expect(status.error, contains('ქეში ვერ შეინახა'));
      await expectLater(
        run(MobileApiService.getDashboard, (_) => response({}, status: 503)),
        throwsStateError,
      );
    },
  );
  test(
    'one failed dashboard subrequest preserves history and other blocks refresh',
    () async {
      final controller = DashboardController(
        const DashboardRepository(DashboardRemoteService()),
      );
      Future<void> load(bool fail) => run(controller.loadAll, (request) {
        switch (request.url.path) {
          case '/mobile/dashboard':
            return response(metrics(fail ? 240 : 120));
          case '/mobile/financials':
          case '/mobile/sales-report':
          case '/mobile/product-analytics':
            return response({'topItems': []});
          case '/mobile/sales-daily':
            return fail
                ? response({}, status: 503)
                : response([
                    {'date': '2026-10-06', 'totalRevenue': 99},
                  ]);
          default:
            return response([]);
        }
      });
      await load(false);
      final previous = controller.state.reads['sales_daily']!.fetchedAt;
      await load(true);
      expect(controller.state.metrics!.todayRevenue, 240);
      expect(controller.state.salesDaily.single['totalRevenue'], 99);
      expect(controller.state.reads['sales_daily']!.fetchedAt, previous);
      expect(controller.state.reads['sales_daily']!.error, isNotNull);
      expect(controller.state.apiError, isTrue);
      controller.dispose();
    },
  );
  test(
    'new business day failure cannot display prior-day reservation pulse',
    () async {
      ManagerEntitlements.features.value = {FeatureKeys.managerReservations};
      addTearDown(ManagerEntitlements.clear);
      final controller = DashboardController(
        const DashboardRepository(DashboardRemoteService()),
      );
      Future<void> load(String day, bool fail) =>
          run(controller.loadAll, (request) {
            switch (request.url.path) {
              case '/mobile/dashboard':
                return response({...metrics(120), 'businessDate': day});
              case '/mobile/financials':
              case '/mobile/sales-report':
              case '/mobile/product-analytics':
                return response({'topItems': []});
              case '/mobile/reservations':
                expect(request.url.queryParameters['date'], day);
                return fail
                    ? response({}, status: 503)
                    : response([
                        {'id': 'old-day'},
                      ]);
              default:
                return response([]);
            }
          });
      await load('2026-10-07', false);
      expect(controller.state.todayReservations.single['id'], 'old-day');
      await load('2026-10-08', true);
      expect(controller.state.metrics!.businessDate, '2026-10-08');
      expect(controller.state.todayReservations, isEmpty);
      final status = controller.state.reads['reservations']!;
      expect(status.query, contains('date=2026-10-08'));
      expect(status.location, 'unavailable');
      expect(status.fetchedAt, isNull);
      expect(status.error, isNotNull);
      controller.dispose();
    },
  );
  test(
    'dashboard product quantities use the ledger for the displayed business date',
    () async {
      final paths = <Uri>[];
      final bundle = await run(
        const DashboardRemoteService().fetchDashboardBundle,
        (request) {
          paths.add(request.url);
          switch (request.url.path) {
            case '/mobile/dashboard':
              return response({...metrics(120), 'businessDate': '2026-10-06'});
            case '/mobile/product-analytics':
              return response({
                'byQuantity': [
                  {
                    'menuItemId': 'stable-menu',
                    'quantity': 7,
                    'revenue': '35.00',
                  },
                ],
                'byRevenue': [],
              });
            case '/mobile/financials':
              return response({});
            default:
              return response([]);
          }
        },
      );
      final product = paths.singleWhere(
        (uri) => uri.path == '/mobile/product-analytics',
      );
      expect(product.queryParameters, {
        'from': '2026-10-06',
        'to': '2026-10-06',
      });
      expect(
        paths
            .singleWhere((uri) => uri.path == '/mobile/staff-performance')
            .queryParameters,
        {'from': '2026-10-06', 'to': '2026-10-06'},
      );
      expect(paths.any((uri) => uri.path == '/mobile/sales-report'), isFalse);
      expect(bundle.productAnalytics!['byQuantity'][0]['quantity'], 7);
      expect(bundle.reads['product_analytics']!.apiAvailable, isTrue);
    },
  );
  test(
    'retiring abandoned page statuses preserves newer reads, other queries and session fencing',
    () {
      ManagerDataReads.activate('synthetic-scope');
      const old = ManagerReadStatus(
        key: 'sale_history',
        query: '/mobile/sales?cursor=old',
      );
      const other = ManagerReadStatus(key: 'tables', query: '/mobile/tables');
      ManagerDataReads.publish('synthetic-scope', old);
      ManagerDataReads.publish('synthetic-scope', other);
      const newer = ManagerReadStatus(
        key: 'sale_history',
        query: '/mobile/sales?cursor=new',
      );
      ManagerDataReads.publish('synthetic-scope', newer);
      ManagerDataReads.release('different-scope', [old, other]);
      expect(ManagerDataReads.statuses.value.values, contains(old));
      ManagerDataReads.release('synthetic-scope', [old]);
      expect(ManagerDataReads.statuses.value.values, isNot(contains(old)));
      expect(ManagerDataReads.statuses.value['sale_history'], same(newer));
      expect(ManagerDataReads.statuses.value.values, contains(other));
    },
  );
  for (final code in [401, 403]) {
    test(
      'dashboard access denial $code clears retained memory and recovers on a fresh read',
      () async {
        final controller = DashboardController(
          const DashboardRepository(DashboardRemoteService()),
        );
        Future<void> load(bool denied) => run(controller.loadAll, (request) {
          if (denied) return response({}, status: code);
          switch (request.url.path) {
            case '/mobile/dashboard':
              return response(metrics(120));
            case '/mobile/financials':
            case '/mobile/sales-report':
            case '/mobile/product-analytics':
              return response({'topItems': []});
            case '/mobile/sales-daily':
              return response([
                {'date': '2026-10-06', 'totalRevenue': 99},
              ]);
            default:
              return response([]);
          }
        });
        await load(false);
        expect(controller.state.metrics!.todayRevenue, 120);
        await load(true);
        expect(controller.state.metrics, isNull);
        expect(controller.state.financials, isNull);
        expect(controller.state.productAnalytics, isNull);
        expect(controller.state.salesDaily, isEmpty);
        expect(controller.state.reads['dashboard']!.httpStatus, code);
        expect(controller.state.reads['dashboard']!.location, 'unavailable');
        await load(false);
        expect(controller.state.metrics!.todayRevenue, 120);
        expect(controller.state.reads['dashboard']!.accessDenied, isFalse);
        controller.dispose();
      },
    );
  }
  test(
    'controller disposal during request never notifies or creates refresh timer',
    () async {
      final controller = DashboardController(
        const DashboardRepository(DashboardRemoteService()),
      );
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      final future = run(controller.initialize, (request) {
        if (!entered.isCompleted) entered.complete();
        return pending.future;
      });
      await entered.future;
      controller.dispose();
      pending.complete(response(metrics(120)));
      await future;
      expect(controller.state.firstLoadDone, isFalse);
    },
  );
}
