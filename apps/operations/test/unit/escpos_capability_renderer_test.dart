import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as imglib;
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/receipt_header_layout.dart';
import 'package:vynic/core/services/printing/escpos_kitchen_renderer.dart';
import 'package:vynic/core/services/printing/escpos_receipt_renderer.dart';
import 'package:vynic/core/services/printing/escpos_report_renderer.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';

const _venue = (name: 'სატესტო რესტორანი', address: '', phone: '');
const _items = ['1x ხაჭაპური - ₾12.00', '2x სალათი - ₾8.00'];
const _reportText = 'SUMMARY\nOrders: 2\nGRAND TOTAL: 28.00';
const _feeds = [0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a];

class _Raster {
  const _Raster(this.widths, this.rows, this.suffix);
  final List<int> widths;
  final List<List<int>> rows;
  final List<int> suffix;
}

// Skip each complete bitmap payload rather than treating arbitrary raster
// bytes as commands. This distinguishes a real cut from ink with those bytes.
_Raster _decodeRaster(List<int> bytes, {bool initialized = true}) {
  var cursor = 0;
  if (initialized) {
    expect(bytes.take(2), [0x1b, 0x40]);
    cursor = 2;
  }
  final widths = <int>[];
  final rows = <List<int>>[];
  while (cursor + 8 <= bytes.length &&
      bytes[cursor] == 0x1d &&
      bytes[cursor + 1] == 0x76 &&
      bytes[cursor + 2] == 0x30) {
    expect(bytes[cursor + 3], 0);
    final widthBytes = bytes[cursor + 4] | (bytes[cursor + 5] << 8);
    final height = bytes[cursor + 6] | (bytes[cursor + 7] << 8);
    expect(widthBytes, greaterThan(0));
    expect(height, inInclusiveRange(1, 256));
    expect(cursor + 8 + widthBytes * height, lessThanOrEqualTo(bytes.length));
    widths.add(widthBytes * 8);
    cursor += 8;
    for (var row = 0; row < height; row++) {
      rows.add(bytes.sublist(cursor, cursor + widthBytes));
      cursor += widthBytes;
    }
  }
  expect(widths, isNotEmpty);
  expect(rows, isNotEmpty);
  return _Raster(widths, rows, bytes.sublist(cursor));
}

Future<List<int>> _kitchen(PrinterCapabilityProfile? profile) =>
    EscposKitchenRenderer.generateBytes(
      items: _items,
      tableNumber: 'TEST ONLY',
      waiterName: 'სატესტო ოპერატორი',
      createdAt: DateTime(2026, 10, 6, 12, 30),
      resolveOperatorDisplayName: (name, {required isEnglish}) => name,
      capabilityProfile: profile,
    );

Future<List<int>> _receipt(PrinterCapabilityProfile? profile) =>
    EscposReceiptRenderer.generateBytes(
      items: _items,
      total: 28,
      subtotal: 28,
      orderNumber: 'TEST ONLY',
      language: 'ka',
      loadReceiptLogoImage: () async => null,
      getReceiptLogoContentRect: (_) async => Rect.zero,
      venue: _venue,
      layout: const ReceiptHeaderLayout(),
      capabilityProfile: profile,
    );

Future<List<int>> _report(PrinterCapabilityProfile? profile) =>
    EscposReportRenderer.generateBytes(
      reportText: _reportText,
      reportType: 'X',
      loadReceiptLogoImage: () async => null,
      getReceiptLogoContentRect: (_) async => Rect.zero,
      venue: _venue,
      capabilityProfile: profile,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveRoot;
  setUpAll(() async {
    hiveRoot = await Directory.systemTemp.createTemp('vynic-renderer-profile-');
    Hive.init(hiveRoot.path);
    DatabaseCore.settingsBox = await Hive.openBox('renderer-profile-settings');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-10-06T00:00:00.000',
    );
  });
  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    await hiveRoot.delete(recursive: true);
  });

  final renderers =
      <String, Future<List<int>> Function(PrinterCapabilityProfile?)>{
        'kitchen': _kitchen,
        'receipt': _receipt,
        'report': _report,
      };
  for (final renderer in renderers.entries) {
    test(
      '${renderer.key}: omitted profile preserves legacy 576-dot/full-cut bytes',
      () async {
        final legacy = await renderer.value(null);
        final explicit = await renderer.value(
          PrinterCapabilityProfile.genericEscposRaster(
            cutter: PrinterCutter.full,
          ),
        );
        expect(legacy, explicit);
        final raster = _decodeRaster(legacy);
        expect(raster.widths.every((width) => width == 576), isTrue);
        expect(raster.suffix, [..._feeds, 0x1d, 0x56, 0]);
      },
    );

    for (final width in [64, 384, 832, 2048]) {
      test(
        '${renderer.key}: actual $width-dot raster has ink and blank bottom margin',
        () async {
          final bytes = await renderer.value(
            PrinterCapabilityProfile.genericEscposRaster(
              paperWidthMm: 58,
              rasterWidthDots: width,
            ),
          );
          final raster = _decodeRaster(bytes);
          expect(raster.widths.every((actual) => actual == width), isTrue);
          expect(raster.rows.every((row) => row.length == width ~/ 8), isTrue);
          expect(
            raster.rows.any((row) => row.any((byte) => byte != 0)),
            isTrue,
          );
          for (final row in raster.rows.skip(raster.rows.length - 2)) {
            expect(row.every((byte) => byte == 0), isTrue);
          }
          expect(raster.suffix, _feeds);
        },
      );
    }

    test(
      '${renderer.key}: cutter changes only the trailing cut command',
      () async {
        final noCut = await renderer.value(
          PrinterCapabilityProfile.genericEscposRaster(
            rasterWidthDots: 384,
            cutter: PrinterCutter.none,
          ),
        );
        final fullCut = await renderer.value(
          PrinterCapabilityProfile.genericEscposRaster(
            rasterWidthDots: 384,
            cutter: PrinterCutter.full,
          ),
        );
        final partialCut = await renderer.value(
          PrinterCapabilityProfile.genericEscposRaster(
            rasterWidthDots: 384,
            cutter: PrinterCutter.partial,
          ),
        );
        expect(fullCut, [...noCut, 0x1d, 0x56, 0]);
        expect(partialCut, [...noCut, 0x1d, 0x56, 1]);
        expect(_decodeRaster(noCut).suffix, _feeds);
      },
    );

    test(
      '${renderer.key}: millimeters and optional beep do not rewrite the raster',
      () async {
        final quiet = await renderer.value(
          PrinterCapabilityProfile.genericEscposRaster(
            paperWidthMm: 58,
            rasterWidthDots: 384,
          ),
        );
        final otherDescription = await renderer.value(
          PrinterCapabilityProfile.genericEscposRaster(
            paperWidthMm: 80,
            rasterWidthDots: 384,
            beep: const PrinterBeepSettings(
              capability: PrinterBeepCapability.epsonEscA97Pattern,
              enabled: true,
            ),
          ),
        );
        expect(otherDescription, quiet);
      },
    );
  }

  test(
    'report raster helper stays raster-only at the selected width',
    () async {
      final profile = PrinterCapabilityProfile.genericEscposRaster(
        rasterWidthDots: 384,
        cutter: PrinterCutter.partial,
      );
      final raster = await EscposReportRenderer.generateImage(
        reportText: _reportText,
        reportType: 'X',
        loadReceiptLogoImage: () async => null,
        getReceiptLogoContentRect: (_) async => Rect.zero,
        venue: _venue,
        capabilityProfile: profile,
      );
      final decoded = _decodeRaster(raster!, initialized: false);
      expect(decoded.widths.every((width) => width == 384), isTrue);
      expect(decoded.suffix, isEmpty);
      expect(await _report(profile), [
        0x1b,
        0x40,
        ...raster,
        ..._feeds,
        0x1d,
        0x56,
        1,
      ]);
    },
  );

  test(
    'receipt PNG preview uses actual raster dots while preserving aspect ratio',
    () async {
      Future<imglib.Image> png(PrinterCapabilityProfile? profile) async {
        final bytes = await EscposReceiptRenderer.generatePngBytes(
          items: _items,
          total: 28,
          subtotal: 28,
          orderNumber: 'TEST ONLY',
          language: 'ka',
          loadReceiptLogoImage: () async => null,
          getReceiptLogoContentRect: (_) async => Rect.zero,
          venue: _venue,
          layout: const ReceiptHeaderLayout(),
          capabilityProfile: profile,
        );
        return imglib.decodePng(bytes!)!;
      }

      final legacy = await png(null);
      final narrow = await png(
        PrinterCapabilityProfile.genericEscposRaster(
          paperWidthMm: 80,
          rasterWidthDots: 384,
        ),
      );
      expect(legacy.width, 576);
      expect(narrow.width, 384);
      expect(narrow.height, closeTo(legacy.height * 384 / 576, 1));
    },
  );

  test(
    'unsupported language fails before any kitchen, logo, or report rendering callback',
    () async {
      final unsupported = PrinterCapabilityProfile(
        paperWidthMm: 80,
        rasterWidthDots: 576,
        language: PrinterCommandLanguage.windowsDriverRendered,
        cutter: PrinterCutter.none,
      );
      var operatorCalls = 0, logoCalls = 0;
      Future<ui.Image?> loadLogo() async {
        logoCalls++;
        return null;
      }

      Future<Rect> logoRect(ui.Image image) async => Rect.zero;
      final attempts = [
        EscposKitchenRenderer.generateBytes(
          items: _items,
          waiterName: 'synthetic',
          resolveOperatorDisplayName: (name, {required isEnglish}) {
            operatorCalls++;
            return name;
          },
          capabilityProfile: unsupported,
        ),
        EscposReceiptRenderer.generateBytes(
          items: _items,
          total: 28,
          loadReceiptLogoImage: loadLogo,
          getReceiptLogoContentRect: logoRect,
          venue: _venue,
          layout: const ReceiptHeaderLayout(),
          capabilityProfile: unsupported,
        ),
        EscposReceiptRenderer.generatePngBytes(
          items: _items,
          total: 28,
          loadReceiptLogoImage: loadLogo,
          getReceiptLogoContentRect: logoRect,
          venue: _venue,
          layout: const ReceiptHeaderLayout(),
          capabilityProfile: unsupported,
        ),
        EscposReportRenderer.generateImage(
          reportText: _reportText,
          reportType: 'X',
          loadReceiptLogoImage: loadLogo,
          getReceiptLogoContentRect: logoRect,
          venue: _venue,
          capabilityProfile: unsupported,
        ),
        EscposReportRenderer.generateBytes(
          reportText: _reportText,
          reportType: 'X',
          loadReceiptLogoImage: loadLogo,
          getReceiptLogoContentRect: logoRect,
          venue: _venue,
          capabilityProfile: unsupported,
        ),
      ];
      await Future.wait(
        attempts.map((future) => expectLater(future, throwsUnsupportedError)),
      );
      expect(operatorCalls, 0);
      expect(logoCalls, 0);
    },
  );
}
