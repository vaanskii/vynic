import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/finance_correction_dialog.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/finance_correction_request.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import '../unit/mgr06_finance_correction_request_test.dart'
    show mgr06Original, mgr06Path, mgr06Period, mgr06Receipt;

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
  setUpAll(() async {
    final georgian = FontLoader('NotoSansGeorgian')
      ..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await georgian.load();
    await icons.load();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr06-widget-');
    Hive.init(dir.path);
    await AuthTokenService.init();
    await session('a');
    await FinanceCorrectionRequests.init();
  });
  tearDown(() async {
    FinanceCorrectionRequests.storageFault = null;
    ManagerAppPreferences.backendUrlOverride.value = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Map<String, dynamic> history({
    bool corrected = false,
    bool consumed = false,
  }) => {
    'periods': [
      {
        'id': mgr06Period,
        'staffId': 'synthetic',
        'periodMonth': '2026-09',
        'expected': '1500.00',
        'paid': corrected ? '0.00' : '120.34',
        'remaining': corrected ? '1500.00' : '1379.66',
        'payments': [
          {
            ...mgr06Original,
            'actorName': 'Synthetic historical actor',
            'canReverse': !corrected && !consumed,
            if (corrected) 'reversedById': 'correction-id',
            if (consumed)
              'correctionBlockedReason': 'ამ ციკლის რეზერვი გამოყენებულია.',
          },
          if (corrected)
            {
              ...mgr06Receipt({'id': 'correction-id', 'reason': 'Wrong entry'}),
              'actorName': 'Synthetic correcting actor',
              'canReverse': false,
            },
        ],
        'reserves': [],
        'accruals': [],
      },
    ],
  };
  Future<void> pump(
    WidgetTester tester,
    FinanceRead read,
    FinanceCorrectionSend send, {
    double width = 768,
    double scale = 1,
    GlobalKey? capture,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: FinanceHistoryScreen(
            title: 'სინთეტიკური ისტორია',
            path: 'staff/synthetic/history',
            read: read,
            correctionSend: send,
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool resume = false}) async {
    await tester.ensureVisible(
      find.widgetWithText(
        TextButton,
        resume ? 'იგივე მოთხოვნის გამეორება' : 'ჩანაწერის კორექტირება',
      ),
    );
    await tester.tap(
      find.widgetWithText(
        TextButton,
        resume ? 'იგივე მოთხოვნის გამეორება' : 'ჩანაწერის კორექტირება',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, {bool retry = false}) async {
    await tester.runAsync(() async {
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          retry ? 'იგივე მოთხოვნის გამეორება' : 'კორექტირების შენახვა',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'history + reason form fit width $width scale $scale and require valid reason',
        (tester) async {
          var calls = 0;
          final key = GlobalKey();
          await pump(
            tester,
            (_) async => history(),
            (path, body) async {
              calls++;
              return mgr06Receipt(body);
            },
            width: width,
            scale: scale,
            capture: key,
          );
          await open(tester);
          expect(find.byType(FinanceCorrectionDialog), findsOneWidget);
          expect(
            find.textContaining('რეალურ თანხას არ აბრუნებს'),
            findsOneWidget,
          );
          await send(tester);
          expect(calls, 0);
          expect(find.textContaining('მიზეზი აუცილებელია'), findsOneWidget);
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          addTearDown(tester.view.resetViewInsets);
          await tester.enterText(find.byType(TextField), 'Wrong entry');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final output = Platform.environment['MGR06_WIDGET_PROOF_DIR'];
          if (output != null)
            await tester.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/history-${width.toInt()}-${scale.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets(
    'lost committed response closes/reopens and resumes exact request after history already reversed',
    (tester) async {
      var calls = 0, corrected = false;
      Map<String, dynamic>? first;
      Future<Map<String, dynamic>> write(
        String path,
        Map<String, dynamic> body,
      ) async {
        calls++;
        expect(path, mgr06Path);
        if (calls == 1) {
          first = Map.from(body);
          corrected = true;
          throw const SocketException('Synthetic lost response');
        }
        expect(body, first);
        return mgr06Receipt(body);
      }

      await pump(tester, (_) async => history(corrected: corrected), write);
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Wrong entry');
      await send(tester);
      expect(find.textContaining('შედეგი არ დადასტურებულა'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.tap(find.widgetWithText(TextButton, 'დახურვა'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Hive.close();
        await AuthTokenService.init();
        await FinanceCorrectionRequests.init();
      });
      await pump(tester, (_) async => history(corrected: corrected), write);
      expect(find.textContaining('კორექტირებულია:'), findsOneWidget);
      await open(tester, resume: true);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Wrong entry',
      );
      await send(tester, retry: true);
      expect(calls, 2);
      expect(find.byType(FinanceCorrectionDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('კორექტირება Cloud-ში შენახულია'), findsOneWidget);
      expect(
        find.textContaining('კორექტირების სამუშაო თარიღი: 2026-10-07'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final phase in [
    'receiptPutAfter',
    'receiptFlushBefore',
    'receiptFlushAfter',
  ]) {
    testWidgets(
      'unconfirmed $phase receipt in RAM resumes after reversed history reopens',
      (tester) async {
        var calls = 0, corrected = false, replayBarriers = 0;
        Future<Map<String, dynamic>> write(
          String path,
          Map<String, dynamic> body,
        ) async {
          calls++;
          corrected = true;
          return mgr06Receipt(body);
        }

        FinanceCorrectionRequests.storageFault = (current) async {
          if (current == phase)
            throw const FileSystemException(
              'Synthetic receipt persistence fault',
            );
        };
        await pump(tester, (_) async => history(corrected: corrected), write);
        await open(tester);
        await tester.enterText(find.byType(TextField), 'Wrong entry');
        await send(tester);
        expect(find.textContaining('შედეგი არ დადასტურებულა'), findsOneWidget);
        expect(calls, 1);
        await tester.tap(find.widgetWithText(TextButton, 'დახურვა'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        FinanceCorrectionRequests.storageFault = (current) async {
          if (current == 'replayFlushBefore') replayBarriers++;
        };
        await pump(tester, (_) async => history(corrected: corrected), write);
        await open(tester, resume: true);
        await send(tester, retry: true);
        expect(calls, 1);
        expect(replayBarriers, 1);
        expect(find.text('კორექტირება Cloud-ში შენახულია'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final changed in ['principal', 'origin']) {
    testWidgets('displayed history cannot submit after $changed changes', (
      tester,
    ) async {
      var calls = 0;
      await pump(tester, (_) async => history(), (path, body) async {
        calls++;
        return mgr06Receipt(body);
      });
      await tester.runAsync(() async {
        if (changed == 'principal')
          await session('b');
        else
          ManagerAppPreferences.backendUrlOverride.value =
              'https://other.invalid';
      });
      await tester.tap(
        find.widgetWithText(TextButton, 'ჩანაწერის კორექტირება'),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(FinanceCorrectionDialog), findsNothing);
      expect(find.textContaining('სესია შეიცვალა'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('late history read completion from old session is refused', (
    tester,
  ) async {
    final release = Completer<Map<String, dynamic>>();
    tester.view.physicalSize = const Size(768, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceHistoryScreen(
          title: 'Synthetic',
          path: 'staff/synthetic/history',
          read: (_) => release.future,
        ),
      ),
    );
    await tester.runAsync(() async {
      await session('b');
      release.complete(history());
    });
    await tester.pumpAndSettle();
    expect(find.text('ვერ ჩაიტვირთა — თავიდან ცდა'), findsOneWidget);
    expect(find.textContaining('გადახდილი:'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'consumed reserve/no eligibility stays blocked and legacy history is read only',
    (tester) async {
      await pump(
        tester,
        (_) async => history(consumed: true),
        (path, body) async => throw StateError('must not send'),
      );
      expect(find.textContaining('რეზერვი გამოყენებულია'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'ჩანაწერის კორექტირება'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(
        tester,
        (_) async => {
          'entries': [
            {
              'description': 'Legacy',
              'amount': '10.00',
              'businessDate': '2026-09-15',
            },
          ],
        },
        (path, body) async => throw StateError('must not send'),
      );
      expect(find.textContaining('ძველი ჩანაწერები'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'ჩანაწერის კორექტირება'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
