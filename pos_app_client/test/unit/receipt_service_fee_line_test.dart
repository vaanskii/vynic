import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/services/printing/escpos_receipt_renderer.dart';

/// Tests for the admin "hide the service-fee row on receipts" setting.
///
/// The setting is display-only: the fee stays inside the printed total. These
/// tests pin that down at three levels — the render predicate, the actual
/// rendered pixels, and the persisted setting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldShowServiceFeeLine predicate', () {
    // Paths that print a fee line today: client, take_away, reservation,
    // menu_count (order_detail _printReceipt, home_reservations_section,
    // home_calculator_page, admin reprint #7b, pos_ingest_server).
    test('shows the row by default when a fee is included', () {
      expect(
        EscposReceiptRenderer.shouldShowServiceFeeLine(
          isCloseTableReceipt: false,
          includeServiceFee: true,
          showServiceFeeLine: true,
        ),
        isTrue,
      );
    });

    test('hides the row when the setting is on', () {
      expect(
        EscposReceiptRenderer.shouldShowServiceFeeLine(
          isCloseTableReceipt: false,
          includeServiceFee: true,
          showServiceFeeLine: false,
        ),
        isFalse,
      );
    });

    test('stays hidden when the order carries no service fee', () {
      for (final show in [true, false]) {
        expect(
          EscposReceiptRenderer.shouldShowServiceFeeLine(
            isCloseTableReceipt: false,
            includeServiceFee: false,
            showServiceFeeLine: show,
          ),
          isFalse,
          reason: 'no fee to show (showServiceFeeLine=$show)',
        );
      }
    });

    test('the customer switch never reaches the closing check', () {
      // Dine-in close, take-away close, split tender and admin reprint #7a all
      // resolve to close_table. They are a different document with their own
      // switch, so „ჩეკზე ასახვა" must not move them.
      for (final show in [true, false]) {
        for (final include in [true, false]) {
          expect(
            EscposReceiptRenderer.shouldShowServiceFeeLine(
              isCloseTableReceipt: true,
              includeServiceFee: include,
              showServiceFeeLine: show,
            ),
            isFalse,
            reason: 'close_table (show=$show, include=$include)',
          );
        }
      }
    });

    test('the closing check has its own switch, defaulting to hidden', () {
      // Unchanged behaviour when the new setting is left alone: the closing
      // check does not print the row, because its total already includes the
      // fee.
      expect(
        EscposReceiptRenderer.shouldShowServiceFeeLine(
          isCloseTableReceipt: true,
          includeServiceFee: true,
          showServiceFeeLine: true,
        ),
        isFalse,
      );

      // Turned on, it prints — independently of the customer-receipt switch.
      for (final customerSwitch in [true, false]) {
        expect(
          EscposReceiptRenderer.shouldShowServiceFeeLine(
            isCloseTableReceipt: true,
            includeServiceFee: true,
            showServiceFeeLine: customerSwitch,
            showCloseReceiptServiceFeeLine: true,
          ),
          isTrue,
          reason: 'customer switch = $customerSwitch must not matter',
        );
      }
    });

    test('no fee charged still means no row on the closing check', () {
      expect(
        EscposReceiptRenderer.shouldShowServiceFeeLine(
          isCloseTableReceipt: true,
          includeServiceFee: false,
          showServiceFeeLine: true,
          showCloseReceiptServiceFeeLine: true,
        ),
        isFalse,
      );
    });

    test('the closing switch never reaches the customer receipt', () {
      expect(
        EscposReceiptRenderer.shouldShowServiceFeeLine(
          isCloseTableReceipt: false,
          includeServiceFee: true,
          showServiceFeeLine: false,
          showCloseReceiptServiceFeeLine: true,
        ),
        isFalse,
      );
    });
  });

  // These render the real receipt and compare PNG bytes.
  //
  // Caveat worth knowing: flutter_test's default font draws every glyph as an
  // identical box, so two totals with the same number of characters ("110.00"
  // vs "100.00") render pixel-identically. Amounts below are therefore chosen
  // to differ in length where the assertion is about the total's value.
  // Structural differences (a row present vs absent) are always detectable.
  group('rendered receipt', () {
    Future<ui.Image?> noLogo() async => null;
    Future<Rect> noLogoRect(ui.Image image) async => Rect.zero;

    /// Renders a receipt whose total (110.00) includes a 10.00 service fee.
    Future<List<int>?> render({
      required String receiptType,
      required bool includeServiceFee,
      required bool showServiceFeeLine,
      double total = 110.0,
    }) async {
      final bytes = await EscposReceiptRenderer.generatePngBytes(
        items: const ['1x Item - ₾100.00'],
        total: total,
        subtotal: 100.0,
        serviceFee: 10.0,
        includeServiceFee: includeServiceFee,
        orderNumber: '1',
        tableNumber: 'Table 1',
        language: 'en',
        receiptType: receiptType,
        showServiceFeeLine: showServiceFeeLine,
        loadReceiptLogoImage: noLogo,
        getReceiptLogoContentRect: noLogoRect,
      );
      return bytes;
    }

    test('client receipt: toggling the setting changes the output', () async {
      final shown = await render(
        receiptType: 'client',
        includeServiceFee: true,
        showServiceFeeLine: true,
      );
      final hidden = await render(
        receiptType: 'client',
        includeServiceFee: true,
        showServiceFeeLine: false,
      );
      expect(shown, isNotNull);
      expect(hidden, isNotNull);
      expect(
        shown,
        isNot(equals(hidden)),
        reason: 'the fee row should be present in one and absent in the other',
      );
    });

    test(
      'hiding the row is NOT the same as dropping the fee from the total',
      () async {
        // The regression this setting must never cause. Both receipts omit the
        // fee row; they differ only in whether the fee sits inside the total
        // (1000.00 vs 100.00 — lengths differ, so the difference is visible).
        // If hiding the row also dropped the fee, these would match.
        final feeInTotalButRowHidden =
            await EscposReceiptRenderer.generatePngBytes(
              items: const ['1x Item - 100.00'],
              total: 1000.0,
              subtotal: 100.0,
              serviceFee: 900.0,
              includeServiceFee: true,
              orderNumber: '1',
              tableNumber: 'Table 1',
              language: 'en',
              receiptType: 'client',
              showServiceFeeLine: false,
              loadReceiptLogoImage: noLogo,
              getReceiptLogoContentRect: noLogoRect,
            );
        final feeExcludedFromTotal =
            await EscposReceiptRenderer.generatePngBytes(
              items: const ['1x Item - 100.00'],
              total: 100.0,
              subtotal: 100.0,
              serviceFee: 900.0,
              includeServiceFee: false,
              orderNumber: '1',
              tableNumber: 'Table 1',
              language: 'en',
              receiptType: 'client',
              showServiceFeeLine: false,
              loadReceiptLogoImage: noLogo,
              getReceiptLogoContentRect: noLogoRect,
            );
        expect(feeInTotalButRowHidden, isNotNull);
        expect(feeExcludedFromTotal, isNotNull);
        expect(
          feeInTotalButRowHidden,
          isNot(equals(feeExcludedFromTotal)),
          reason:
              'the printed total must still include the fee when the row is '
              'hidden',
        );
      },
    );

    test('the toggle is inert when no service fee is included', () async {
      // Nothing to hide — the flag must not perturb the output at all.
      final on = await render(
        receiptType: 'client',
        includeServiceFee: false,
        showServiceFeeLine: true,
        total: 100.0,
      );
      final off = await render(
        receiptType: 'client',
        includeServiceFee: false,
        showServiceFeeLine: false,
        total: 100.0,
      );
      expect(on, isNotNull);
      expect(on, equals(off));
    });

    test('close-table receipt is byte-identical either way', () async {
      final on = await render(
        receiptType: 'close_table',
        includeServiceFee: true,
        showServiceFeeLine: true,
      );
      final off = await render(
        receiptType: 'close_table',
        includeServiceFee: true,
        showServiceFeeLine: false,
      );
      expect(on, isNotNull);
      expect(
        on,
        equals(off),
        reason: 'close_table never renders the row, so the toggle is inert',
      );
    });

    test('the closing check prints the row once its switch is on', () async {
      final off = await EscposReceiptRenderer.generatePngBytes(
        items: const ['1x Item - 100.00'],
        total: 110.0,
        subtotal: 100.0,
        serviceFee: 10.0,
        includeServiceFee: true,
        orderNumber: '1',
        tableNumber: 'Table 1',
        language: 'en',
        receiptType: 'close_table',
        showServiceFeeLine: true,
        loadReceiptLogoImage: noLogo,
        getReceiptLogoContentRect: noLogoRect,
      );
      final on = await EscposReceiptRenderer.generatePngBytes(
        items: const ['1x Item - 100.00'],
        total: 110.0,
        subtotal: 100.0,
        serviceFee: 10.0,
        includeServiceFee: true,
        orderNumber: '1',
        tableNumber: 'Table 1',
        language: 'en',
        receiptType: 'close_table',
        showServiceFeeLine: true,
        showCloseReceiptServiceFeeLine: true,
        loadReceiptLogoImage: noLogo,
        getReceiptLogoContentRect: noLogoRect,
      );
      expect(off, isNotNull);
      expect(on, isNotNull);
      expect(
        on,
        isNot(equals(off)),
        reason: 'the row should appear only when the closing switch is on',
      );
    });

    test('menu_count receipt honours the setting', () async {
      final shown = await render(
        receiptType: 'menu_count',
        includeServiceFee: true,
        showServiceFeeLine: true,
      );
      final hidden = await render(
        receiptType: 'menu_count',
        includeServiceFee: true,
        showServiceFeeLine: false,
      );
      expect(shown, isNot(equals(hidden)));
    });
  });

  group('setting persistence', () {
    late Directory tempDir;
    late Box settingsBox;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('vynic_receipt_setting');
      Hive.init(tempDir.path);
    });

    setUp(() async {
      settingsBox = await Hive.openBox('settings_receipt_test');
      DatabaseCore.settingsBox = settingsBox;
    });

    tearDown(() async {
      DatabaseCore.settingsBox = null;
      await Hive.deleteBoxFromDisk('settings_receipt_test');
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    test('the closing switch defaults to hidden and round-trips', () async {
      // Existing terminals must not suddenly start printing the row on their
      // closing checks.
      expect(
        settingsBox.containsKey('closeReceiptShowServiceFeeLine'),
        isFalse,
      );
      expect(SettingsRepository.isCloseReceiptServiceFeeLineVisible(), isFalse);

      await SettingsRepository.setCloseReceiptServiceFeeLineVisible(true);
      expect(SettingsRepository.isCloseReceiptServiceFeeLineVisible(), isTrue);

      // And it is a genuinely separate key from the customer-receipt one.
      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isTrue);
      await SettingsRepository.setReceiptServiceFeeLineVisible(false);
      expect(SettingsRepository.isCloseReceiptServiceFeeLineVisible(), isTrue);
    });

    test('defaults to visible for existing installs (key absent)', () {
      expect(settingsBox.containsKey('receiptShowServiceFeeLine'), isFalse);
      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isTrue);
    });

    test('persists and round-trips', () async {
      await SettingsRepository.setReceiptServiceFeeLineVisible(false);
      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isFalse);
      expect(settingsBox.get('receiptShowServiceFeeLine'), isFalse);

      await SettingsRepository.setReceiptServiceFeeLineVisible(true);
      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isTrue);
      expect(settingsBox.get('receiptShowServiceFeeLine'), isTrue);
    });

    test('honours the superseded inverted key when the new one is absent', () {
      // A terminal that toggled the setting before the rename kept
      // `receiptHideServiceFeeLine: true` — that must still mean "hidden".
      settingsBox.put('receiptHideServiceFeeLine', true);
      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isFalse);

      settingsBox.put('receiptHideServiceFeeLine', false);
      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isTrue);
    });

    test('a new write wins over the superseded key', () async {
      await settingsBox.put('receiptHideServiceFeeLine', true); // legacy hidden
      await SettingsRepository.setReceiptServiceFeeLineVisible(true);

      expect(SettingsRepository.isReceiptServiceFeeLineVisible(), isTrue);
      expect(settingsBox.containsKey('receiptHideServiceFeeLine'), isFalse);
    });

    test('does not disturb the service-fee rate settings', () async {
      await settingsBox.put('serviceFeePercent', 12.0);
      await settingsBox.put('serviceFeeEnabled', true);

      await SettingsRepository.setReceiptServiceFeeLineVisible(false);

      expect(SettingsRepository.getServiceFeePercentage(), 12.0);
      expect(SettingsRepository.getServiceFeeRate(), closeTo(0.12, 1e-9));
      expect(SettingsRepository.isServiceFeeEnabledByDefault(), isTrue);
    });
  });
}
