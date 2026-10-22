import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_data_status.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'manager_financial_ledger_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('financial-sync-owned-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    await AuthTokenService.saveToken(
      token:
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'financial-sync'})))}.unsigned',
      username: 'Synthetic',
      role: 'MANAGER',
      expiresInSeconds: 3600,
      venueCode: 'synthetic',
    );
  });
  tearDown(() async {
    ManagerDataReads.clear();
    await Hive.close().timeout(const Duration(seconds: 5));
    await dir.delete(recursive: true);
  });
  testWidgets(
    'financial API contract pins rollover, aggregates page status, rejects denied memory and recovers',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var failPage = false, deny = false;
      var firstCursor = 'page-2';
      var legacyDayContract = false;
      final requests = <Uri>[];
      final now = DateTime.now().toUtc().toIso8601String();
      http.Response response(
        Object body, {
        bool partial = false,
        int status = 200,
      }) => http.Response(
        jsonEncode(body),
        status,
        headers: {
          'x-vynic-data-freshness': jsonEncode({
            'source': 'POS',
            'sourceUpdatedAt': now,
            'receivedAt': now,
            'completeness': partial ? 'PARTIAL' : 'KNOWN',
          }),
        },
      );
      Future<void> settle() async {
        for (var i = 0; i < 35; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> more() async {
        final button = find.text('მეტის ნახვა');
        await tester.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(button);
        await tester.pump();
        await tester.tap(button);
        await settle();
      }

      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: FinancialsScreen(
                user: User(username: 'Synthetic', pinCode: '', role: 'manager'),
              ),
            ),
          );
          await settle();
          expect(find.text('მონაცემები განახლებულია'), findsOneWidget);
          final scoped = requests.where(
            (uri) => const [
              '/mobile/financial-summary',
              '/mobile/sales',
              '/mobile/product-analytics',
              '/mobile/sale-staff-analytics',
            ].contains(uri.path),
          );
          expect(scoped, hasLength(4));
          for (final uri in scoped) {
            expect(uri.queryParameters['from'], '2026-09-04');
            expect(uri.queryParameters['to'], '2026-09-04');
          }
          await more();
          expect(requests.last.queryParameters['from'], '2026-09-04');
          expect(find.text('მონაცემები შეზღუდულია'), findsOneWidget);
          expect(find.text('Synthetic partial page'), findsOneWidget);
          failPage = true;
          tester
              .widget<ManagerDataBoundary>(find.byType(ManagerDataBoundary))
              .onRefresh!();
          await settle();
          expect(find.text('მონაცემები განახლებულია'), findsOneWidget);
          await more();
          expect(
            find.text('განახლება ვერ მოხერხდა · მონაცემები შეზღუდულია'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('sale-cached-page')),
            findsOneWidget,
          );
          deny = true;
          tester
              .widget<ManagerDataBoundary>(find.byType(ManagerDataBoundary))
              .onRefresh!();
          await settle();
          expect(find.byKey(const ValueKey('sale-cached-page')), findsNothing);
          expect(find.text('სერვერთან კავშირი ვერ დამყარდა'), findsOneWidget);
          deny = false;
          tester
              .widget<ManagerDataBoundary>(find.byType(ManagerDataBoundary))
              .onRefresh!();
          await settle();
          expect(find.text('მონაცემები განახლებულია'), findsOneWidget);
          legacyDayContract = true;
          tester
              .widget<ManagerDataBoundary>(find.byType(ManagerDataBoundary))
              .onRefresh!();
          await settle();
          expect(find.text('მონაცემები განახლებულია'), findsOneWidget);
          expect(
            requests
                .where((uri) => uri.path == '/mobile/financial-summary')
                .last
                .queryParameters['from'],
            '2026-09-04',
          );
          // This page has never been cached: the failed attempted query must
          // also retire when the view successfully refreshes.
          firstCursor = 'uncached-page';
          tester
              .widget<ManagerDataBoundary>(find.byType(ManagerDataBoundary))
              .onRefresh!();
          await settle();
          await more();
          expect(
            find.text('განახლება ვერ მოხერხდა · მონაცემები შეზღუდულია'),
            findsOneWidget,
          );
          tester
              .widget<ManagerDataBoundary>(find.byType(ManagerDataBoundary))
              .onRefresh!();
          await settle();
          expect(find.text('მონაცემები განახლებულია'), findsOneWidget);
          expect(MonitoringSocketService.apiError.value, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          var closed = false;
          final closing = Hive.close().then((_) => closed = true);
          await settle();
          expect(closed, isTrue);
          await closing;
        },
        () => MockClient((request) async {
          requests.add(request.url);
          if (deny) return response({}, status: 403);
          final range = {
            'from': request.url.queryParameters['from'] ?? '2026-09-05',
            'to': request.url.queryParameters['to'] ?? '2026-09-05',
          };
          switch (request.url.path) {
            case '/mobile/financials':
              return response({
                ...fixtures.fixture(),
                if (!legacyDayContract) 'businessDate': '2026-09-04',
                'procurement': {'businessDate': '2026-09-04'},
              });
            case '/mobile/financial-summary':
              return response({
                ...range,
                'revenue': '100.00',
                'provenance': 'LEDGER_COMPLETE',
              });
            case '/mobile/sales':
              if (request.url.queryParameters['cursor'] != null) {
                if (failPage) return response({}, status: 503);
                return response({
                  ...range,
                  'provenance': 'PARTIAL',
                  'warning': 'Synthetic partial page',
                  'sales': [
                    {...fixtures.saleSummary(), 'id': 'cached-page'},
                  ],
                }, partial: true);
              }
              return response({
                ...range,
                'provenance': 'LEDGER_COMPLETE',
                'sales': [fixtures.saleSummary()],
                'nextCursor': firstCursor,
              });
            case '/mobile/product-analytics':
              return response({
                ...range,
                'byRevenue': [],
                'provenance': 'LEDGER_COMPLETE',
              });
            case '/mobile/sale-staff-analytics':
              return response({
                ...range,
                'staff': [],
                'provenance': 'LEDGER_COMPLETE',
              });
            default:
              throw StateError('Unexpected fixture URL ${request.url.path}');
          }
        }),
      );
    },
  );
}
