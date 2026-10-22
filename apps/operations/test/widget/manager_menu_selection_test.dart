import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';

const _menu = [
  {
    'id': 'food',
    'slug': 'food',
    'nameKa': 'კერძები',
    'nameEn': 'Food',
    'items': [
      {
        'id': 'first',
        'nameKa': 'ერთი სახელი',
        'nameEn': 'Shared name',
        'price': 10,
        'variants': [],
      },
      {
        'id': 'second',
        'nameKa': 'ერთი სახელი',
        'nameEn': 'Shared name',
        'price': 10,
        'variants': [],
      },
    ],
    'subcategories': [
      {
        'id': 'drinks',
        'slug': 'drinks',
        'nameKa': 'სასმელები',
        'nameEn': 'Drinks',
        'items': [
          {
            'id': 'drink',
            'nameKa': 'სასმელი',
            'nameEn': 'Drink',
            'price': 0,
            'variants': [
              {'id': 'small', 'size': 0.5, 'price': 5},
              {'id': 'large', 'size': 1, 'price': 8},
            ],
          },
        ],
      },
    ],
  },
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

MockClient _client({void Function(http.Request)? onWrite}) =>
    MockClient((request) async {
      expect(request.url.host, '127.0.0.1');
      if (request.method != 'GET') {
        expect(request.method, 'POST');
        expect(request.url.path, startsWith('/mobile/counted-menu/'));
        onWrite?.call(request);
        return http.Response(jsonEncode({'success': true}), 200);
      }
      final Object body = switch (request.url.path) {
        '/mobile/menu' => _menu,
        '/mobile/restaurant-settings' => {
          'serviceFeeAvailable': true,
          'serviceFeePercent': 10,
        },
        '/mobile/counted-menus' => [],
        _ => throw StateError('Unexpected synthetic read: ${request.url.path}'),
      };
      final now = DateTime.now().toUtc().toIso8601String();
      return http.Response(
        jsonEncode(body),
        200,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-vynic-data-freshness': jsonEncode({
            'source': 'CLOUD',
            'sourceUpdatedAt': now,
            'receivedAt': now,
            'completeness': 'KNOWN',
          }),
        },
      );
    });

Future<void> _quantity(
  WidgetTester tester,
  Finder product,
  int quantity, {
  String? variant,
}) async {
  await tester.tap(product);
  await tester.pumpAndSettle();
  if (variant != null) {
    await tester.tap(find.widgetWithText(ChoiceChip, variant));
    await tester.pump();
  }
  // These are product quantities in a synthetic widget, never an auth PIN.
  for (final digit in quantity.toString().split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('დამატება  ×$quantity'));
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.text('ნახვა'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('დასრულება'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
  });
  late Directory privateDirectory;
  late WidgetTester testerForCleanup;
  setUp(() async {
    privateDirectory = await Directory.systemTemp.createTemp('menu-selection-');
    Hive.init(privateDirectory.path);
    await AuthTokenService.init();
    await MobileCacheService.init();
    await ManagerAppPreferences.init();
    await ManagerAppPreferences.setBackendUrlOverride('http://127.0.0.1:54123');
    await AuthTokenService.saveToken(
      token:
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'menu-selection'})))}.unsigned',
      username: 'Synthetic',
      role: 'MANAGER',
      expiresInSeconds: 3600,
      venueCode: 'synthetic',
    );
  });
  tearDown(() async {
    await testerForCleanup.runAsync(() async {
      ManagerDataReads.clear();
      ManagerAppPreferences.backendUrlOverride.value = null;
      await Hive.close().timeout(const Duration(seconds: 5));
      await privateDirectory.delete(recursive: true);
    });
  });

  Future<void> open(
    WidgetTester tester,
    MobileCalculatorScreen screen, {
    void Function(List<MenuSelectionLine>?)? onSelected,
  }) async {
    testerForCleanup = tester;
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final selected = await Navigator.of(context)
                    .push<List<MenuSelectionLine>>(
                      MaterialPageRoute(builder: (_) => screen),
                    );
                onSelected?.call(selected);
              },
              child: const Text('Open synthetic menu'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open synthetic menu'));
    await _settle(tester);
  }

  testWidgets(
    'mixed menu keeps direct products reachable and duplicate names distinct',
    (tester) async {
      List<MenuSelectionLine>? selected;
      await http.runWithClient(() async {
        await open(
          tester,
          const MobileCalculatorScreen(selectionMode: true),
          onSelected: (value) => selected = value,
        );
        expect(find.text('ერთი სახელი'), findsNWidgets(2));
        await _quantity(tester, find.text('ერთი სახელი').first, 2);
        await _quantity(tester, find.text('ერთი სახელი').last, 3);
        await tester.tap(find.text('სასმელები'));
        await tester.pumpAndSettle();
        expect(find.text('სასმელი'), findsOneWidget);
        await _quantity(tester, find.text('სასმელი'), 4, variant: '1.0 L');
        await _finish(tester);
        expect(selected, hasLength(3));
        expect(selected!.map((line) => line.key).toSet(), {
          'menu:first',
          'menu:second',
          'menu:drink/variant:large',
        });
        expect(selected!.map((line) => line.qty), [2, 3, 4]);
        expect(selected!.last.menuItemId, 'drink');
        expect(selected!.last.variantId, 'large');
        expect(selected!.last.unitPrice, 8);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      }, _client);
    },
  );

  testWidgets(
    'reopening preserves frozen identified and manual selection lines',
    (tester) async {
      const initial = [
        MenuSelectionLine(
          key: 'menu:drink/variant:large',
          itemName: 'ძველი სასმელი',
          unitPrice: 7,
          qty: 2,
          menuItemId: 'drink',
          variantId: 'large',
        ),
        MenuSelectionLine(
          key: 'manual:retained',
          itemName: 'შენახული კერძი',
          unitPrice: 11,
          qty: 3,
        ),
      ];
      List<MenuSelectionLine>? selected;
      await http.runWithClient(() async {
        await open(
          tester,
          const MobileCalculatorScreen(
            selectionMode: true,
            initialSelection: initial,
          ),
          onSelected: (value) => selected = value,
        );
        await tester.tap(find.text('ნახვა'));
        await tester.pumpAndSettle();
        expect(find.text('ძველი სასმელი'), findsOneWidget);
        expect(find.text('შენახული კერძი'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.add_rounded).last);
        await tester.pump();
        await tester.tap(find.text('დასრულება'));
        await tester.pumpAndSettle();
        expect(selected, hasLength(2));
        expect(
          selected!.map((line) => line.key),
          initial.map((line) => line.key),
        );
        expect(selected!.map((line) => line.unitPrice), [7, 11]);
        expect(selected!.map((line) => line.qty), [2, 4]);
        expect(selected!.first.menuItemId, 'drink');
        expect(selected!.first.variantId, 'large');
        expect(selected!.last.menuItemId, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      }, _client);
    },
  );

  testWidgets(
    'add-more uses the selected variant quantity instead of the first variant',
    (tester) async {
      List<MenuSelectionLine>? selected;
      await http.runWithClient(() async {
        await open(
          tester,
          const MobileCalculatorScreen(
            selectionMode: true,
            initialSelection: [
              MenuSelectionLine(
                key: 'menu:drink/variant:small',
                itemName: 'სასმელი (500 ml)',
                unitPrice: 5,
                qty: 2,
                menuItemId: 'drink',
                variantId: 'small',
              ),
              MenuSelectionLine(
                key: 'menu:drink/variant:large',
                itemName: 'სასმელი (1.0 L)',
                unitPrice: 8,
                qty: 4,
                menuItemId: 'drink',
                variantId: 'large',
              ),
            ],
          ),
          onSelected: (value) => selected = value,
        );
        await tester.tap(find.text('სასმელები'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add_rounded).first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, '1.0 L'));
        await tester.tap(find.text('1').last);
        await tester.pump();
        expect(find.text('დამატება  +1 → 5'), findsOneWidget);
        await tester.tap(find.text('დამატება  +1 → 5'));
        await tester.pumpAndSettle();
        await _finish(tester);
        expect(selected, hasLength(2));
        final quantities = {
          for (final line in selected!) line.variantId: line.qty,
        };
        expect(quantities, {'small': 2, 'large': 5});
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      }, _client);
    },
  );

  testWidgets('chosen counted-menu service fee survives save and edit reopen', (
    tester,
  ) async {
    final writes = <http.Request>[];
    var saved = 0;
    await http.runWithClient(() async {
      await open(
        tester,
        MobileCalculatorScreen(
          isCountMode: true,
          onSaved: () => saved++,
          initialSelection: const [
            MenuSelectionLine(
              key: 'menu:first',
              itemName: 'ერთი სახელი',
              unitPrice: 10,
              qty: 2,
              menuItemId: 'first',
            ),
          ],
        ),
      );
      await tester.tap(find.text('დათვლის ნახვა'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('სერვისი (10%)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '15%'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '15',
      );
      await tester.tap(find.text('დადასტურება'));
      await tester.pumpAndSettle();
      expect(find.text('სერვისი (15%)'), findsOneWidget);
      await tester.tap(find.text('შენახვა'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Synthetic count');
      await tester.tap(find.text('შენახვა'));
      await _settle(tester);
      expect(saved, 1);
      final created = jsonDecode(writes.single.body) as Map<String, dynamic>;
      expect(created['includeServiceFee'], isTrue);
      expect(created['serviceFeeRate'], 0.15);
      expect(created['subtotal'], 20);
      expect(created['items'], [
        {'itemName': 'ერთი სახელი', 'quantity': 2, 'unitPrice': 10.0},
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await open(
        tester,
        MobileCalculatorScreen(
          isCountMode: true,
          editDraftId: 'synthetic-draft',
          initialName: 'Synthetic count',
          initialCountItems: List<Map<String, dynamic>>.from(
            created['items'] as List,
          ),
          initialIncludeServiceFee: created['includeServiceFee'] as bool,
          initialServiceFeeRate: (created['serviceFeeRate'] as num).toDouble(),
          onSaved: () => saved++,
        ),
      );
      await tester.tap(find.text('დათვლის ნახვა'));
      await tester.pumpAndSettle();
      expect(find.text('სერვისი (15%)'), findsOneWidget);
      await tester.tap(find.text('შენახვა'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Synthetic count',
      );
      await tester.tap(find.text('დადასტურება'));
      await _settle(tester);
      expect(saved, 2);
      expect(
        writes.last.url.path,
        '/mobile/counted-menu/synthetic-draft/update',
      );
      final updated = jsonDecode(writes.last.body) as Map<String, dynamic>;
      expect(updated['serviceFeeRate'], 0.15);
      expect(updated['items'], created['items']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    }, () => _client(onWrite: writes.add));
  });
  testWidgets(
    'editing a legacy count retains unresolved and ambiguous frozen lines',
    (tester) async {
      final writes = <http.Request>[];
      const retained = [
        {
          'itemName': 'შენახული ძველი კერძი',
          'quantity': 2,
          'unitPrice': 19,
          'comment': 'Keep historical note',
        },
        {
          'itemName': 'ერთი სახელი',
          'quantity': 3,
          'unitPrice': 10,
          'comment': 'No identity guessed',
        },
      ];
      var saved = 0;
      await http.runWithClient(() async {
        await open(
          tester,
          MobileCalculatorScreen(
            isCountMode: true,
            editDraftId: 'legacy-count',
            initialName: 'Legacy',
            initialCountItems: retained,
            initialIncludeServiceFee: false,
            onSaved: () => saved++,
          ),
        );
        await tester.tap(find.text('დათვლის ნახვა'));
        await tester.pumpAndSettle();
        expect(find.text('შენახული ძველი კერძი'), findsOneWidget);
        await tester.tap(find.text('შენახვა'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('დადასტურება'));
        await _settle(tester);
        expect(saved, 1);
        final updated = jsonDecode(writes.single.body) as Map<String, dynamic>;
        expect(updated['subtotal'], 68);
        expect(updated['items'], retained);
        expect(updated['includeServiceFee'], isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      }, () => _client(onWrite: writes.add));
    },
  );
}
