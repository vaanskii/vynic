import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/finance_planning_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/financial_planning_card.dart';
import 'package:vynic/core/models/user.dart';
import 'manager_catalog_cost_test.dart' as qa;

final payroll = <String, dynamic>{
  'today': '2026-09-15',
  'businessDate': '2026-09-14',
  'periodMonth': '2026-09',
  'staff': [
    {
      'id': 'giorgi',
      'username': 'გიორგი გრძელი გვარით',
      'isActive': true,
      'compensation': [
        {
          'compensationType': 'MONTHLY_FIXED',
          'amount': '1500.00',
          'effectiveFrom': '2026-09-01',
          'isActive': true,
        },
      ],
      'period': {
        'id': 'p',
        'compensationType': 'MONTHLY_FIXED',
        'rate': '1500.00',
        'expected': '1500.00',
        'paid': '800.00',
        'remaining': '700.00',
        'overpaid': '0.00',
        'payments': [],
      },
    },
    {
      'id': 'nika',
      'username': 'ნიკა',
      'isActive': true,
      'compensation': [],
      'period': {
        'id': 'd',
        'compensationType': 'DAILY_FIXED',
        'rate': '60.00',
        'expected': '60.00',
        'paid': '0.00',
        'remaining': '60.00',
        'overpaid': '0.00',
        'accruals': [
          {'amount': '60.00', 'payableDate': '2026-09-03'},
        ],
      },
    },
  ],
};
final obligations = <String, dynamic>{
  'today': '2026-09-15',
  'businessDate': '2026-09-14',
  'periodMonth': '2026-09',
  'obligations': [
    {
      'id': 'rent',
      'name': 'ქირა',
      'type': 'RENT',
      'monthlyAmount': '3000.00',
      'dueDay': 30,
      'startsOn': '2026-09-01',
      'isActive': true,
    },
    {
      'id': 'bank',
      'name': 'საქართველოს ბანკი — სესხი',
      'type': 'BANK_LOAN',
      'monthlyAmount': '1500.00',
      'dueDay': 25,
      'startsOn': '2026-09-01',
      'isActive': true,
    },
  ],
  'cycles': [
    {
      'id': 'c',
      'obligationId': 'rent',
      'name': 'ქირა',
      'type': 'RENT',
      'targetAmount': '3000.00',
      'dueDate': '2026-09-30',
      'reservedAmount': '1800.00',
      'paidAmount': '0.00',
      'remainingToCover': '1200.00',
      'remainingToPay': '3000.00',
      'dailyRecommendedReserve': '75.00',
      'status': 'OPEN',
    },
    {
      'id': 'b',
      'obligationId': 'bank',
      'name': 'საქართველოს ბანკი — სესხი',
      'type': 'BANK_LOAN',
      'targetAmount': '1500.00',
      'dueDate': '2026-09-25',
      'reservedAmount': '500.00',
      'paidAmount': '0.00',
      'remainingToCover': '1000.00',
      'remainingToPay': '1500.00',
      'dailyRecommendedReserve': '90.91',
      'status': 'OPEN',
    },
  ],
};
final planning = <String, dynamic>{
  'payrollRemaining': '760.00',
  'obligationsRemaining': '4500.00',
  'dailyRecommendedReserve': '165.91',
  'recommendations': [
    {'name': 'ქირა', 'periodMonth': '2026-09', 'amount': '75.00'},
    {
      'name': 'საქართველოს ბანკი — სესხი',
      'periodMonth': '2026-09',
      'amount': '90.91',
    },
  ],
};
Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
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
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets(
      'Payroll detail, exact payment, rule and daily entry at $width',
      (t) async {
        qa.narrow(t, width: width, height: 900);
        final writes = <Map<String, dynamic>>[];
        final paths = <String>[];
        await t.pumpWidget(
          qa.app(
            FinancePlanningScreen(
              read: (_) async => payroll,
              write: (path, data, {bool update = false}) async {
                paths.add(path);
                writes.add(data);
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await tapVisible(t, find.text('გიორგი გრძელი გვარით'));
        expect(find.text('დარიცხული: 1500.00 ₾'), findsOneWidget);
        expect(find.text('გადახდილი: 800.00 ₾'), findsOneWidget);
        expect(t.takeException(), isNull);
        await qa.screenshot(t, 'payroll-$width');
        await tapVisible(t, find.text('გადახდის დაფიქსირება').first);
        await t.enterText(find.byKey(const Key('finance-amount')), '300.10');
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const Key('finance-businessDate')),
              )
              .controller!
              .text,
          '2026-09-14',
        );
        await qa.screenshot(t, 'payroll-payment-$width');
        expect(
          t.getSize(find.byKey(const Key('finance-save'))).height,
          greaterThanOrEqualTo(48),
        );
        await tapVisible(t, find.byKey(const Key('finance-save')));
        expect(paths.single, 'payroll/p/payments');
        expect(writes.single['amount'], '300.10');
        expect(writes.single['id'], isNotEmpty);
        await tapVisible(t, find.text('ხელფასის წესი').first);
        expect(find.textContaining('გახსნილი თვე უცვლელია'), findsOneWidget);
        expect(t.takeException(), isNull);
        await qa.screenshot(t, 'compensation-$width');
        await tapVisible(t, find.text('გაუქმება'));
        await tapVisible(t, find.text('ნიკა'));
        await tapVisible(t, find.text('დღიური თანამშრომლები'));
        expect(find.text('გიორგი გრძელი გვარით'), findsNothing);
        await tapVisible(t, find.byKey(const Key('worked-nika')));
        expect(paths.last, 'payroll/d/day');
        expect(writes.last['businessDate'], '2026-09-14');
        expect(writes.last['worked'], isTrue);
        expect(writes.last.containsKey('amount'), isFalse);
        await qa.screenshot(t, 'daily-sheet-$width');
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'Salary choices hide irrelevant fields and save each type at $width',
      (t) async {
        qa.narrow(t, width: width, height: 900);
        final writes = <Map<String, dynamic>>[];
        await t.pumpWidget(
          qa.app(
            FinancePlanningScreen(
              read: (_) async => payroll,
              write: (_, data, {bool update = false}) async {
                writes.add(data);
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await tapVisible(t, find.text('გიორგი გრძელი გვარით'));
        for (final type in ['MONTHLY_FIXED', 'DAILY_FIXED', 'MANUAL']) {
          await tapVisible(t, find.text('ხელფასის წესი').first);
          await tapVisible(t, find.byKey(Key('salary-type-$type')));
          if (type == 'MANUAL') {
            expect(find.byKey(const Key('finance-amount')), findsNothing);
            expect(find.text('ხელფასი გამოითვლება ხელით'), findsOneWidget);
          } else {
            expect(
              find.text(
                type == 'DAILY_FIXED'
                    ? 'დღიური განაკვეთი (₾ / დღე)'
                    : 'თვიური ხელფასი (₾)',
              ),
              findsOneWidget,
            );
            expect(
              find.text(
                type == 'DAILY_FIXED'
                    ? 'თვიური ხელფასი (₾)'
                    : 'დღიური განაკვეთი (₾ / დღე)',
              ),
              findsNothing,
            );
            await t.enterText(
              find.byKey(const Key('finance-amount')),
              type == 'DAILY_FIXED' ? '50.00' : '1500.00',
            );
          }
          await t.pumpAndSettle();
          await qa.screenshot(t, 'salary-$type-$width');
          await tapVisible(t, find.byKey(const Key('finance-save')));
          expect(writes.last['compensationType'], type);
          if (type == 'MANUAL') expect(writes.last['amount'], '0.00');
          expect(t.takeException(), isNull);
        }
      },
    );
    testWidgets(
      'Daily toggle, retry, reversal, date navigation and monthly separation at $width',
      (t) async {
        qa.narrow(t, width: width, height: 900);
        var worked = false;
        var fail = true;
        final writes = <Map<String, dynamic>>[];
        final reads = <String>[];
        await t.pumpWidget(
          qa.app(
            FinancePlanningScreen(
              read: (path) async {
                reads.add(path);
                return {
                  ...payroll,
                  'staff': [
                    financeRows(payroll['staff']).first,
                    {
                      ...financeRows(payroll['staff']).last,
                      'period': {
                        ...Map<String, dynamic>.from(
                          financeRows(payroll['staff']).last['period'],
                        ),
                        'workedDays': worked ? 12 : 11,
                        'expected': worked ? '600.00' : '550.00',
                        'paid': '400.00',
                        'remaining': worked ? '200.00' : '150.00',
                        'rate': '50.00',
                        'payableDays': [
                          {'businessDate': '2026-09-14', 'worked': worked},
                        ],
                      },
                    },
                  ],
                };
              },
              write: (_, data, {bool update = false}) async {
                writes.add({...data});
                worked =
                    data['worked']
                        as bool; // server saved even when response is lost
                if (fail) {
                  fail = false;
                  throw const SocketException('კავშირი გაწყდა');
                }
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await tapVisible(t, find.byKey(const Key('payroll-tab-1')));
        expect(find.text('გიორგი გრძელი გვარით'), findsNothing);
        expect(
          t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'შემდეგი სამუშაო დღე',
                ),
              )
              .onPressed,
          isNull,
        );
        await tapVisible(t, find.byKey(const Key('worked-nika')));
        expect(find.textContaining('კავშირი გაწყდა'), findsOneWidget);
        await tapVisible(t, find.text('თავიდან ცდა'));
        expect(writes[0]['id'], writes[1]['id']);
        expect(find.text('დარიცხული: 600.00 ₾'), findsOneWidget);
        expect(find.text('გადახდილი: 400.00 ₾'), findsOneWidget);
        expect(find.text('დარჩენილი: 200.00 ₾'), findsOneWidget);
        await qa.screenshot(t, 'daily-paid-$width');
        await tapVisible(t, find.byKey(const Key('worked-nika')));
        expect(writes.last['worked'], isFalse);
        expect(writes.last['businessDate'], '2026-09-14');
        expect(find.text('ნამუშევარი დღეები: 11'), findsOneWidget);
        await tapVisible(t, find.byTooltip('წინა სამუშაო დღე'));
        expect(find.textContaining('2026-09-13'), findsOneWidget);
        await tapVisible(t, find.byKey(const Key('payroll-tab-2')));
        expect(find.text('გიორგი გრძელი გვარით'), findsOneWidget);
        expect(find.text('ნიკა'), findsNothing);
        await tapVisible(t, find.byKey(const Key('payroll-tab-3')));
        expect(find.text('გადახდის დაფიქსირება'), findsNWidgets(2));
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('Obligations cards, reserve, payment and edit at $width', (
      t,
    ) async {
      qa.narrow(t, width: width, height: 900);
      final paths = <String>[];
      await t.pumpWidget(
        qa.app(
          FinancePlanningScreen(
            obligations: true,
            read: (_) async => obligations,
            write: (path, data, {bool update = false}) async {
              paths.add(path);
              expect(data['amount'], '100.00');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('დღიური მიზანი: 75.00 ₾'), findsOneWidget);
      expect(t.takeException(), isNull);
      await qa.screenshot(t, 'obligations-$width');
      await tapVisible(t, find.text('თანხის გადადება').first);
      expect(find.text('გადადებული თანხა ჯერ ხარჯი არ არის.'), findsOneWidget);
      expect(find.byKey(const Key('finance-paymentDate')), findsNothing);
      await t.enterText(find.byKey(const Key('finance-amount')), '100.00');
      await tapVisible(t, find.byKey(const Key('finance-save')));
      expect(paths.last, 'cycles/c/reserves');
      await tapVisible(t, find.text('გადახდის დაფიქსირება').first);
      expect(find.byKey(const Key('finance-paymentDate')), findsOneWidget);
      await t.enterText(find.byKey(const Key('finance-amount')), '100.00');
      await tapVisible(t, find.byKey(const Key('finance-save')));
      expect(paths.last, 'cycles/c/payments');
      await tapVisible(t, find.text('რედაქტირება').first);
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('finance-startsOn')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await qa.screenshot(t, 'obligation-edit-$width');
      expect(t.takeException(), isNull);
    });
    testWidgets('Dashboard planning fits and deep-links at $width', (t) async {
      qa.narrow(t, width: width, height: 900);
      final opened = <bool>[];
      await t.pumpWidget(
        qa.app(
          SingleChildScrollView(
            child: FinancialPlanningCard(
              load: () async => planning,
              onOpen: opened.add,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('დღეს გადასადები: 165.91 ₾'), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('planning-payrollRemaining')));
      await tapVisible(
        t,
        find.byKey(const Key('planning-obligationsRemaining')),
      );
      expect(opened, [false, true]);
      expect(t.takeException(), isNull);
      await qa.screenshot(t, 'planning-$width');
    });
  }
  testWidgets(
    'failed payment keeps input and retry ID; validation rejects excess precision',
    (t) async {
      qa.narrow(t);
      final ids = <dynamic>[];
      await t.pumpWidget(
        qa.app(
          FinancePlanningScreen(
            read: (_) async => payroll,
            write: (path, data, {bool update = false}) async {
              ids.add(data['id']);
              if (ids.length == 1)
                throw const SocketException('კავშირი გაწყდა');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.text('გიორგი გრძელი გვარით'));
      await tapVisible(t, find.text('გადახდის დაფიქსირება'));
      await t.enterText(find.byKey(const Key('finance-amount')), '1.001');
      await tapVisible(t, find.byKey(const Key('finance-save')));
      expect(ids, isEmpty);
      await t.enterText(find.byKey(const Key('finance-amount')), '0.10');
      await tapVisible(t, find.byKey(const Key('finance-save')));
      expect(find.textContaining('კავშირი გაწყდა'), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('finance-save')));
      expect(ids.length, 2);
      expect(ids[0], ids[1]);
      expect(find.byType(FinanceEntryDialog), findsNothing);
    },
  );
  testWidgets(
    'history shows period, payment date, actor and reserve consumption without editing',
    (t) async {
      qa.narrow(t, width: 360);
      await t.pumpWidget(
        qa.app(
          FinanceHistoryScreen(
            title: 'ქირა',
            path: 'history',
            read: (_) async => {
              'cycles': [
                {
                  'periodMonth': '2026-09',
                  'targetAmount': '3000.00',
                  'paidAmount': '500.00',
                  'remainingToPay': '2500.00',
                  'payments': [
                    {
                      'amount': '500.00',
                      'businessDate': '2026-09-14',
                      'paymentDate': '2026-09-15',
                      'actorName': 'გიორგი',
                      'reserveConsumed': '500.00',
                      'notes': 'ნაწილობრივი',
                    },
                  ],
                  'reserves': [
                    {
                      'amount': '600.00',
                      'businessDate': '2026-09-10',
                      'actorName': 'გიორგი',
                    },
                  ],
                },
              ],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('რეზერვიდან: 500.00 ₾'), findsOneWidget);
      expect(find.text('რედაქტირება'), findsNothing);
      expect(t.takeException(), isNull);
      await qa.screenshot(t, 'obligation-history-360');
    },
  );
  for (final section in [false, true]) {
    testWidgets(
      'Dashboard opens actual ${section ? 'obligations' : 'payroll'} destination',
      (t) async {
        qa.narrow(t);
        await t.pumpWidget(
          qa.app(FinancialPlanningCard(load: () async => planning)),
        );
        await t.pumpAndSettle();
        await tapVisible(
          t,
          find.byKey(
            Key(
              section
                  ? 'planning-obligationsRemaining'
                  : 'planning-payrollRemaining',
            ),
          ),
        );
        expect(
          t
              .widget<FinancePlanningScreen>(find.byType(FinancePlanningScreen))
              .obligations,
          section,
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'Financials opens actual ${section ? 'obligations' : 'payroll'} destination',
      (t) async {
        qa.narrow(t);
        await t.pumpWidget(
          qa.app(
            FinancialsScreen(
              user: User(username: 'M', pinCode: '0000', role: 'manager'),
              loadData: () async => {'revenue': 0.0, 'expenses': 0.0},
            ),
          ),
        );
        await t.pumpAndSettle();
        await tapVisible(
          t,
          find.byKey(
            Key(section ? 'financials-obligations' : 'financials-payroll'),
          ),
        );
        expect(
          t
              .widget<FinancePlanningScreen>(find.byType(FinancePlanningScreen))
              .obligations,
          section,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('loading, empty and failed refresh are explicit', (t) async {
    qa.narrow(t);
    bool fail = false;
    await t.pumpWidget(
      qa.app(
        FinancePlanningScreen(
          obligations: true,
          read: (_) async {
            if (fail) throw const SocketException('offline');
            return {...obligations, 'obligations': [], 'cycles': []};
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('ჯერ არ გაქვთ'), findsOneWidget);
    fail = true;
    await tapVisible(t, find.byTooltip('განახლება'));
    expect(find.text('თავიდან ცდა'), findsOneWidget);
    expect(find.text('ვალდებულების დამატება'), findsNothing);
    fail = false;
    await tapVisible(t, find.text('თავიდან ცდა'));
    expect(find.textContaining('ჯერ არ გაქვთ'), findsOneWidget);
  });
}
