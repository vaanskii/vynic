import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/pos_input_settings_tile.dart';
import 'package:vynic/apps/windows_pos/widgets/login/login_desktop_view.dart';
import 'package:vynic/apps/windows_pos/widgets/time_entry_pad.dart';

Widget app(Widget child) => MaterialApp(
  builder: (_, child) => PosInputScope(child: child!),
  home: Scaffold(body: child),
);
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_input_test');
    Hive.init(dir.path);
    DatabaseCore.settingsBox = await Hive.openBox('input_settings');
    PosInputSettings.load();
  });
  tearDown(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    PosInputSettings.active = false;
    PosInputSettings.enabled.value = true;
    await dir.delete(recursive: true);
  });
  test(
    'defaults on, persists off across restart, leaves Manager preference alone',
    () async {
      expect(PosInputSettings.showKeyboard, isTrue);
      await PosInputSettings.save(false);
      await Hive.close();
      DatabaseCore.settingsBox = await Hive.openBox('input_settings');
      PosInputSettings.enabled.value = true;
      PosInputSettings.load();
      expect(PosInputSettings.showKeyboard, isFalse);
      PosInputSettings.active = false;
      expect(PosInputSettings.showKeyboard, isTrue);
    },
  );
  testWidgets(
    'settings toggle persists and ordinary fields react immediately',
    (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              const PosInputSettingsTile(),
              PosOnScreenTextField(
                controller: c,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ],
          ),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        for (var i = 0; i < 100 && PosInputSettings.enabled.value; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(PosInputSettings.enabled.value, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      await tester.enterText(find.byType(TextField), 'Physical keyboard');
      expect(c.text, 'Physical keyboard');
      expect(find.byType(PosKeyboard), findsNothing);
    },
  );
  testWidgets('one keypad handles touch delete clear decimal', (tester) async {
    var value = '';
    await tester.pumpWidget(
      app(
        PinPad(
          onDigitPressed: (d) => value += d,
          onClearPressed: () => value = '',
          onDeletePressed: () => value = value.substring(0, value.length - 1),
          showDecimalButton: true,
        ),
      ),
    );
    for (final c in ['1', '.', '2']) {
      await tester.tap(find.text(c));
    }
    expect(value, '1.2');
    await tester.tap(find.byTooltip('წაშლა'));
    expect(value, '1.');
    await tester.tap(find.byTooltip('გასუფთავება'));
    expect(value, '');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'hidden keypad receives physical digits and Enter without capturing other fields',
    (tester) async {
      PosInputSettings.enabled.value = false;
      var value = '';
      var submitted = false;
      final c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              PinPad(
                onDigitPressed: (d) => value += d,
                onClearPressed: () => value = '',
                onDeletePressed: () =>
                    value = value.substring(0, value.length - 1),
                onSubmit: () => submitted = true,
              ),
              TextField(controller: c),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(value, '1');
      expect(submitted, isTrue);
      await tester.enterText(find.byType(TextField), '23');
      expect(value, '1');
      expect(c.text, '23');
    },
  );
  testWidgets('login uses shared pad and hardware PIN with touch disabled', (
    tester,
  ) async {
    PosInputSettings.enabled.value = false;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pin = ValueNotifier('');
    addTearDown(pin.dispose);
    await tester.pumpWidget(
      app(
        LoginDesktopView(
          pin: pin,
          isLoading: false,
          now: DateTime(2026),
          workDate: DateTime(2026),
          onDigitPressed: (d) => pin.value += d,
          onClearPressed: () => pin.value = '',
          onDeletePressed: () => pin.value = '',
          onLoginPressed: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PinPad), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('1'));
    expect(pin.value, '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
    expect(pin.value, '14');
    expect(tester.takeException(), isNull);
  });
  testWidgets('embedded text keyboard delegates and replaces selected text', (
    tester,
  ) async {
    final c = TextEditingController(text: 'abc');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 740,
          height: 390,
          child: OnScreenKeyboard(
            controller: c,
            language: 'en',
            showHeader: false,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.tap(find.text('q'));
    expect(c.text, 'aq');
    expect(find.byType(PosKeyboard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('disabled text sheet offers editable input without touch keys', (
    tester,
  ) async {
    PosInputSettings.enabled.value = false;
    final c = TextEditingController();
    addTearDown(c.dispose);
    String? result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPosKeyboardInputSheet(
                context: context,
                controller: c,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(PosKeyboard), findsNothing);
    await tester.enterText(find.byType(TextField), 'Test');
    await tester.tap(find.text('შენახვა'));
    await tester.pumpAndSettle();
    expect(result, 'Test');
  });
  testWidgets(
    'numeric sheet preserves decimal constraints with physical input',
    (tester) async {
      PosInputSettings.enabled.value = false;
      String? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPosNumberKeyboardInputSheet(
                  context: context,
                  initialValue: '',
                  title: 'Amount',
                  allowDecimal: true,
                  maxDigits: 4,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(PinPad), findsOneWidget);
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.period,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ]) {
        await tester.sendKeyEvent(key, character: key.keyLabel);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, '1.23');
    },
  );
  testWidgets('time entry uses same hidden pad and validates hours/minutes', (
    tester,
  ) async {
    PosInputSettings.enabled.value = false;
    await tester.pumpWidget(app(const TimeEntryDialog()));
    await tester.pump();
    for (final c in ['2', '3', '5', '9']) {
      await tester.sendKeyEvent(
        LogicalKeyboardKey(0x30 + int.parse(c)),
        character: c,
      );
      await tester.pump();
    }
    expect(find.text('23:59'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shared pad supports intrinsic AlertDialog sizing', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AlertDialog(
          content: PinPad(
            onDigitPressed: (_) {},
            onClearPressed: () {},
            onDeletePressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PIN input disabled during validation ignores hardware and touch',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          PinPad(
            enabled: false,
            onDigitPressed: (_) => calls++,
            onClearPressed: () {},
            onDeletePressed: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.tap(find.text('1'));
      expect(calls, 0);
    },
  );
}
