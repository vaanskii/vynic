import 'package:vynic/apps/windows_pos/screens/login_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/login/login_desktop_view.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import 'package:vynic/apps/windows_pos/widgets/staff_lock_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/pos_quit_action.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_inventory_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_menu_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_staff_section.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';

Widget app(Widget body) => MaterialApp(
  theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
  builder: (_, child) => PosLocaleHost(
    child: PosInputScope(
      child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
    ),
  ),
  home: Scaffold(body: body),
);
void main() {
  late Directory temp;
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (!Hive.isAdapterRegistered(5))
      Hive.registerAdapter(MenuCategoryDBAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vynic-ux');
    Hive.init(temp.path);
    DatabaseCore.settingsBox = await Hive.openBox('settings');
    DatabaseCore.inventoryBox = await Hive.openBox('inventory');
    DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('menu');
    DatabaseCore.userBox = await Hive.openBox<User>('users');
    await DatabaseCore.menuBox!.add(
      MenuCategoryDB(
        slug: 'drinks',
        translationsEn: {'name': 'Drinks'},
        translationsKa: {'name': 'სასმელი'},
      ),
    );
    PosInputSettings.load();
  });
  tearDown(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    DatabaseCore.inventoryBox = null;
    DatabaseCore.menuBox = null;
    DatabaseCore.userBox = null;
    PosInputSettings.active = false;
    PosInputSettings.enabled.value = true;
    PosInputSettings.keyboardHeight.value = 0;
    await temp.delete(recursive: true);
  });
  Future<void> language(WidgetTester tester, String code) async {
    await tester.runAsync(() => SettingsRepository.setDefaultLanguage(code));
    await tester.pumpAndSettle();
  }

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final path = Platform.environment['VYNIC_DUMP_DIR'];
    if (path == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dimensions in [
    const Size(800, 600),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('home work date remains visible at $dimensions', (
      tester,
    ) async {
      size(tester, dimensions);
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topCenter,
            child: PosHomeUtilityBar(
              businessDate: DateTime(2026, 9, 21),
              activeLabel: 'მაგიდები',
              username: 'Giorgi',
              roleLabel: 'მენეჯერი',
              languageCode: 'KA',
              unreadCount: 0,
              density: PosUiDensity.compact,
              layoutClass: dimensions.width < 1100
                  ? PosLayoutClass.sm
                  : PosLayoutClass.lg,
              onNotificationTap: () {},
              onLockTap: () {},
              onLanguageTap: () {},
              fullscreenPosMode: true,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('home-work-date')), findsOneWidget);
      final rect = tester.getRect(find.byKey(const ValueKey('home-work-date')));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(dimensions.width));
      await language(tester, 'en');
      expect(find.text('Tables'), findsOneWidget);
      await shot(tester, 'home-${dimensions.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
    testWidgets('Vynic quit modal fits and refreshes language at $dimensions', (
      tester,
    ) async {
      size(tester, dimensions);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmPosQuit(context),
              child: const Text('Quit'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Quit'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('pos-quit-modal')), findsOneWidget);
      await language(tester, 'en');
      expect(
        find.text('Are you sure you want to close Vynic POS?'),
        findsOneWidget,
      );
      await language(tester, 'ka');
      expect(
        find.text('ნამდვილად გსურთ Vynic POS-ის დახურვა?'),
        findsOneWidget,
      );
      await shot(tester, 'quit-${dimensions.width.toInt()}');
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'lock PIN stays visible with optional input off; live digits and runtime labels',
    (tester) async {
      size(tester, const Size(1024, 768));
      PosInputSettings.enabled.value = false;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(staffLockRoute()),
              child: const Text('Lock'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();
      expect(find.byType(PinPad), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(find.text('შესვლა'), findsNothing);
      await language(tester, 'en');
      expect(find.text('Terminal locked'), findsOneWidget);
      expect(find.byTooltip('Backspace'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('Sign in'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  for (final dimensions in [
    const Size(800, 600),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    for (final form in ['Reservations', 'Menu', 'Inventory']) {
      testWidgets(
        '$form $dimensions edits the actual field live without Enter or duplicate preview',
        (tester) async {
          size(tester, dimensions);
          final surface = switch (form) {
            'Reservations' => const ReservationCreationSheet(),
            'Menu' => AdminMenuSection(
              user: User(
                username: 'manager',
                pinCode: '000000',
                role: 'manager',
              ),
            ),
            _ => const AdminInventorySection(),
          };
          await tester.pumpWidget(app(surface));
          await tester.pumpAndSettle();
          final shared = find.byType(PosOnScreenTextField).first;
          await tester.ensureVisible(shared);
          await tester.pumpAndSettle();
          final controller = tester
              .widget<PosOnScreenTextField>(shared)
              .controller;
          await tester.tap(
            find.descendant(of: shared, matching: find.byType(TextField)),
          );
          await tester.pumpAndSettle();
          expect(find.byType(PosKeyboard), findsOneWidget);
          expect(
            tester.getRect(shared).bottom,
            lessThanOrEqualTo(tester.getRect(find.byType(PosKeyboard)).top),
          );
          expect(find.text('შეიყვანეთ ტექსტი'), findsNothing);
          await tester.tap(find.text('ქ'));
          await tester.pump();
          expect(controller.text, 'ქ');
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: shared, matching: find.byType(TextField)),
                )
                .controller!
                .text,
            'ქ',
          );
          await shot(tester, '$form-${dimensions.width.toInt()}');
          await language(tester, 'en');
          expect(find.text('q'), findsOneWidget);
          await tester.tap(find.text('q'));
          await tester.pump();
          expect(controller.text, 'ქq');
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(controller.text, 'ქq');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  testWidgets(
    'login keeps a matching PIN visible until explicit confirmation',
    (tester) async {
      size(tester, const Size(1024, 768));
      PosInputSettings.enabled.value = false;
      await tester.runAsync(
        () => DatabaseCore.userBox!.add(
          User(username: 'test', pinCode: '1234', role: 'waiter'),
        ),
      );
      await tester.pumpWidget(app(const LoginScreen()));
      await tester.pumpAndSettle();
      final pad = find.byType(PinPad);
      await tester.ensureVisible(pad);
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(find.byType(LoginDesktopView), findsOneWidget);
      expect(
        tester
            .widget<LoginDesktopView>(find.byType(LoginDesktopView))
            .pin
            .value,
        '1234',
      );
      await language(tester, 'en');
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byTooltip('Clear'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'decimal and PIN modes update the real controller and preserve leading PIN zero',
    (tester) async {
      size(tester, const Size(800, 600));
      for (final mode in [PosInputMode.decimal, PosInputMode.pin]) {
        final controller = TextEditingController();
        final values = <String>[];
        await tester.pumpWidget(
          app(
            PosOnScreenTextField(
              controller: controller,
              mode: mode,
              decoration: const InputDecoration(labelText: 'Value'),
              onChanged: values.add,
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        for (final digit
            in mode == PosInputMode.pin ? ['0', '1'] : ['1', '.', '2']) {
          await tester.tap(find.text(digit));
          await tester.pump();
        }
        expect(controller.text, mode == PosInputMode.pin ? '01' : '1.2');
        expect(values.last, controller.text);
        expect(find.byType(TextField), findsOneWidget);
        if (mode == PosInputMode.pin)
          expect(
            tester.widget<TextField>(find.byType(TextField)).obscureText,
            isTrue,
          );
        await tester.tap(find.byTooltip('დახურვა'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
      }
    },
  );
  testWidgets(
    'staff PIN uses the same pad and immediate masked draft with keyboard off',
    (tester) async {
      size(tester, const Size(1024, 768));
      PosInputSettings.enabled.value = false;
      await tester.pumpWidget(
        app(
          AdminStaffSection(
            user: User(username: 'manager', pinCode: '000000', role: 'manager'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ახალი თანამშრომელი'));
      await tester.pumpAndSettle();
      final pin = find.text('------');
      await tester.ensureVisible(pin);
      await tester.tap(pin);
      await tester.pumpAndSettle();
      expect(find.byType(PinPad), findsOneWidget);
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(find.text('•—————'), findsOneWidget);
      await language(tester, 'en');
      expect(find.byTooltip('Clear'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
