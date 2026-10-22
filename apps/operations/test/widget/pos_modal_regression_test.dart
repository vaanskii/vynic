import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/menu_item_form.dart';
import 'package:vynic/apps/windows_pos/widgets/admin_verification_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/comment_input_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/time_entry_pad.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Pos03Fixture fixture;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vynic_modal_regression_',
    );
    fixture = Pos03Fixture();
    await fixture.open(directory.path);
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-15T00:00:00.000',
      'defaultLanguage': 'ka',
    });
    PosInputSettings.active = true;
    PosInputSettings.enabled.value = false;
  });
  tearDown(() async {
    PosInputSettings.active = false;
    PosInputSettings.keyboardHeight.value = 0;
    await fixture.close();
    await directory.delete(recursive: true);
  });
  Finder field(String text) => find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.labelText == text || w.decoration?.hintText == text),
  );
  Future<void> host(
    WidgetTester tester,
    WidgetBuilder form, {
    Size size = const Size(1024, 768),
    void Function(dynamic)? result,
    double textScale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: PosLocaleHost(child: PosInputScope(child: child!)),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => result?.call(
                  await showPosModal<dynamic>(
                    context: context,
                    barrierDismissible: false,
                    builder: form,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // The route must open even when no callback is needed.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  ReservationCreationSheet reservation() => ReservationCreationSheet(
    initialDate: DateTime(2026, 10, 17),
    initialTime: const TimeOfDay(hour: 18, minute: 30),
    initialGuests: 2,
  );

  testWidgets(
    'dirty reservation protects Escape, system back, repeated close and cancel',
    (tester) async {
      var returns = 0;
      await host(tester, (_) => reservation(), result: (_) => returns++);
      await tester.enterText(field('სახელი და გვარი'), 'ნინო');
      for (var i = 0; i < 3; i++) {
        if (i == 0) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else if (i == 1) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('გაუქმება'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final center = tester.getCenter(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byWidgetPredicate(
                  (w) => w is Material && w.type == MaterialType.card,
                ),
              )
              .first,
        );
        expect(
          center.dy,
          closeTo(384, 2),
          reason:
              'Discard confirmation is centered, independent of form alignment.',
        );
        await tester.tap(find.text('გაგრძელება'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field('სახელი და გვარი')).controller!.text,
          'ნინო',
        );
      }
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('დახურვა'));
      await tester.pumpAndSettle();
      expect(returns, 1);
      expect(DatabaseCore.reservationBox!.values, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reservation validation remains inline and invalid submit keeps draft',
    (tester) async {
      await host(tester, (_) => reservation(), result: (_) {});
      await tester.tap(find.text('რეზერვაციის შექმნა'));
      await tester.pumpAndSettle();
      expect(find.text('გთხოვთ შეიყვანოთ სტუმრის სახელი'), findsOneWidget);
      expect(find.byType(ReservationCreationSheet), findsOneWidget);
      await tester.enterText(field('სახელი და გვარი'), 'ნინო');
      await tester.enterText(field('სტუმრების რაოდენობა'), '0');
      await tester.tap(find.text('რეზერვაციის შექმნა'));
      await tester.pumpAndSettle();
      expect(
        find.text('გთხოვთ მიუთითოთ სტუმრების სწორი რაოდენობა'),
        findsOneWidget,
      );
      expect(DatabaseCore.reservationBox!.values, isEmpty);
    },
  );

  testWidgets(
    'confirmation centers in the usable viewport without double keyboard insets',
    (tester) async {
      PosInputSettings.keyboardHeight.value = 300;
      await host(
        tester,
        (_) => const AlertDialog(
          title: Text('დახურვის დადასტურება'),
          content: Text('ცვლილებები არ არის შენახული.'),
        ),
        result: (_) {},
      );
      expect(
        tester
            .getCenter(
              find
                  .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byWidgetPredicate(
                      (w) => w is Material && w.type == MaterialType.card,
                    ),
                  )
                  .first,
            )
            .dy,
        closeTo((768 - 300) / 2, 2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long Georgian form and actions fit 1024 at 150 percent text size',
    (tester) async {
      await host(tester, (_) => reservation(), result: (_) {}, textScale: 1.5);
      await tester.ensureVisible(field('შენიშვნები'));
      await tester.pumpAndSettle();
      expect(find.text('რეზერვაციის შექმნა').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(800, 600),
    const Size(1024, 768),
    const Size(1366, 768),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'reservation $size keyboard keeps title fixed, caret visible, then restores layout',
      (tester) async {
        PosInputSettings.enabled.value = true;
        await host(tester, (_) => reservation(), size: size, result: (_) {});
        final title = find.text('ახალი რეზერვაცია');
        final initialTop = tester.getTopLeft(title).dy;
        final original = tester.getRect(
          find.byKey(const Key('reservation-compact-form')),
        );
        for (final name in [
          'სახელი და გვარი',
          'შენიშვნები',
          'სახელი და გვარი',
        ]) {
          final input = field(name);
          await tester.ensureVisible(input);
          await tester.pumpAndSettle();
          await tester.tap(input);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(PosKeyboard), findsOneWidget);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(title).dy, closeTo(initialTop, .1));
          final editable = find.descendant(
            of: input,
            matching: find.byType(EditableText),
          );
          final state = tester.state<EditableTextState>(editable);
          expect(state.widget.focusNode.hasFocus, isTrue);
          expect(state.widget.showCursor, isTrue);
          final blink = state.cursorCurrentlyVisible;
          await tester.pump(const Duration(milliseconds: 500));
          expect(state.cursorCurrentlyVisible, !blink);
          await tester.tap(
            find.descendant(
              of: find.byType(PosKeyboard),
              matching: find.text('ქ'),
            ),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(state.widget.focusNode.hasFocus, isTrue);
          final caret = state.renderEditable.getLocalRectForCaret(
            state.widget.controller.selection.extent,
          );
          final caretBottom = state.renderEditable
              .localToGlobal(caret.bottomRight)
              .dy;
          expect(
            caretBottom,
            lessThan(tester.getTopLeft(find.byType(PosKeyboard)).dy),
          );
          await tester.tap(
            find.descendant(
              of: find.byType(PosKeyboard),
              matching: find.byTooltip('დახურვა'),
            ),
          );
          await tester.pumpAndSettle();
          expect(PosInputSettings.keyboardHeight.value, 0);
          expect(
            tester.getRect(find.byKey(const Key('reservation-compact-form'))),
            original,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'numeric dock keeps the real field focus and leading zero; Escape restores form',
    (tester) async {
      PosInputSettings.enabled.value = true;
      await host(tester, (_) => reservation(), result: (_) {});
      await tester.tap(field('ტელეფონი'));
      await tester.pumpAndSettle();
      final editable = find.descendant(
        of: field('ტელეფონი'),
        matching: find.byType(EditableText),
      );
      await tester.tap(
        find.descendant(of: find.byType(PinPad), matching: find.text('0')),
      );
      await tester.pump();
      expect(
        tester.state<EditableTextState>(editable).widget.focusNode.hasFocus,
        isTrue,
      );
      expect(tester.widget<TextField>(field('ტელეფონი')).controller!.text, '0');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ReservationCreationSheet), findsOneWidget);
      expect(PosInputSettings.keyboardHeight.value, 0);
    },
  );

  testWidgets(
    'PIN repeated cancel and bad attempts never authorize; hardware Enter validates',
    (tester) async {
      for (var attempt = 0; attempt < 3; attempt++) {
        dynamic result;
        await host(
          tester,
          (_) => const AdminVerificationDialog(),
          result: (value) => result = value,
        );
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('არასწორი ადმინ PIN კოდი'), findsOneWidget);
        expect(result, isNull);
        await tester.tap(find.text('გაუქმება'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'time picker validates hardware input and recovers after deleting the colon',
    (tester) async {
      String? result;
      await host(
        tester,
        (_) => const TimeEntryDialog(),
        result: (value) => result = value as String?,
      );
      for (final digit in ['1', '8']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: digit);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3, character: '3');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: '0');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, '18:30');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comment required input stays inline; tab reaches field and cancel returns null',
    (tester) async {
      await host(
        tester,
        (_) => const CommentInputDialog(title: 'მიზეზი'),
        result: (_) {},
      );
      await tester.tap(find.text('დადასტურება'));
      await tester.pumpAndSettle();
      expect(find.text('გთხოვთ შეიყვანოთ კომენტარი'), findsOneWidget);
      await tester.tap(field('მიზეზი'));
      await tester.enterText(field('მიზეზი'), 'საცდელი');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentInputDialog), findsNothing);
    },
  );

  testWidgets(
    'shared menu form validates, retains failed save, submits once and preserves amounts',
    (tester) async {
      var saves = 0;
      final pending = Completer<bool>();
      await host(
        tester,
        (_) => MenuItemForm(
          defaultSendToKitchen: true,
          onAddVariant: (_, __) {},
          onSave: (en, ka, price, variants, kitchen) {
            saves++;
            expect(en, 'Sample');
            expect(ka, 'საცდელი');
            expect(price, 12.5);
            expect(variants, isNull);
            expect(kitchen, isTrue);
            return pending.future;
          },
        ),
        result: (_) {},
      );
      await tester.tap(find.text('დამატება'));
      await tester.pumpAndSettle();
      expect(find.text('შეიყვანეთ სახელი ორივე ენაზე'), findsOneWidget);
      expect(saves, 0);
      await tester.enterText(field('სახელი (ინგლისური)'), 'Sample');
      await tester.enterText(field('სახელი (ქართული)'), 'საცდელი');
      await tester.enterText(field('ფასი (₾)'), '12');
      await tester.tap(find.byTooltip('+0.50 ₾'));
      await tester.pump();
      await tester.tap(find.text('დამატება'));
      await tester.pump();
      await tester.tap(find.text('დამატება'));
      await tester.pump();
      expect(saves, 1);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('პროდუქტი ვერ შეინახა'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('სახელი (ქართული)')).controller!.text,
        'საცდელი',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['cancel', 'empty', 'delete', 'save']) {
    testWidgets('shared menu comment preserves $action semantics', (
      tester,
    ) async {
      dynamic result = 'pending';
      await host(
        tester,
        (_) => const CommentInputDialog.menuItem(
          itemName: 'იმერული ხაჭაპური',
          initialComment: 'არსებული კომენტარი',
        ),
        result: (value) => result = value,
      );
      expect(find.text('არსებული კომენტარი'), findsOneWidget);
      if (action == 'empty' || action == 'save') {
        await tester.enterText(
          field('კომენტარი'),
          action == 'empty' ? '  ' : '  ხახვის გარეშე  ',
        );
      }
      await tester.tap(
        find.text(switch (action) {
          'cancel' => 'გაუქმება',
          'delete' => 'წაშლა',
          _ => 'შენახვა',
        }),
      );
      await tester.pumpAndSettle();
      expect(result, switch (action) {
        'delete' => '',
        'save' => 'ხახვის გარეშე',
        _ => null,
      });
      expect(find.byType(CommentInputDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
