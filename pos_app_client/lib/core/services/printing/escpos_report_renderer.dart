import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../database_service.dart';
import 'escpos_bitmap.dart';

/// Renders X/Z text reports into ESC/POS raster bytes.
class EscposReportRenderer {
  const EscposReportRenderer._();

  static String _resolveReportTypeKa(String reportType) {
    final normalized = reportType.trim().toUpperCase();
    if (normalized.contains('Z')) {
      return 'Z რეპორტი';
    }
    return 'X რეპორტი';
  }

  static String _localizeReportLineKa(String line) {
    var value = line;
    const replacements = <MapEntry<String, String>>[
      MapEntry('GRAND TOTAL', 'სრული ჯამი'),
      MapEntry('TOTAL', 'ჯამი'),
      MapEntry('SUMMARY', 'შეჯამება'),
      MapEntry('BREAKDOWN', 'განაწილება'),
      MapEntry('DETAILS', 'დეტალები'),
      MapEntry('REPORT', 'რეპორტი'),
      MapEntry('Date:', 'თარიღი:'),
      MapEntry('Time:', 'დრო:'),
      MapEntry('Orders', 'შეკვეთები'),
      MapEntry('Order', 'შეკვეთა'),
      MapEntry('Amount', 'თანხა'),
      MapEntry('Count', 'რაოდენობა'),
      MapEntry('Cash', 'ნაღდი'),
      MapEntry('Card', 'ბარათი'),
      MapEntry('Other', 'სხვა'),
    ];

    for (final entry in replacements) {
      value = value.replaceAll(entry.key, entry.value);
    }
    return value;
  }

  /// Generate a 1-bit bitmap image of the report.
  static Future<List<int>?> generateImage({
    required String reportText,
    required String reportType,
    required Future<ui.Image?> Function() loadReceiptLogoImage,
    required Future<Rect> Function(ui.Image image) getReceiptLogoContentRect,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const double width = 576;
      double currentY = 28;

      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, width, 3600), bgPaint);

      final reportTypeKa = _resolveReportTypeKa(reportType);

      void drawText(
        String text,
        double y, {
        double fontSize = 22,
        bool bold = false,
        bool center = false,
        double maxWidth = width - 40,
      }) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: maxWidth);

        final xPosition = center ? (width - textPainter.width) / 2 : 20.0;

        textPainter.paint(canvas, Offset(xPosition, y));
      }

      void drawLine(double y) {
        final linePaint = Paint()
          ..color = Colors.black
          ..strokeWidth = 1;
        canvas.drawLine(Offset(20, y), Offset(width - 20, y), linePaint);
      }

      final logoImage = await loadReceiptLogoImage();
      if (logoImage != null) {
        const maxLogoWidth = 360.0;
        const maxLogoHeight = 108.0;
        final srcRect = await getReceiptLogoContentRect(logoImage);
        final sourceWidth = srcRect.width;
        final sourceHeight = srcRect.height;
        final scale = sourceWidth <= 0 || sourceHeight <= 0
            ? 1.0
            : (maxLogoWidth / sourceWidth < maxLogoHeight / sourceHeight
                  ? maxLogoWidth / sourceWidth
                  : maxLogoHeight / sourceHeight);
        final logoWidth = sourceWidth * scale;
        final logoHeight = sourceHeight * scale;

        final logoLeft = (width - logoWidth) / 2;
        final dstRect = Rect.fromLTWH(
          logoLeft,
          currentY + 8,
          logoWidth,
          logoHeight,
        );
        final logoPaint = Paint()
          ..isAntiAlias = false
          ..filterQuality = FilterQuality.none
          ..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn);
        canvas.drawImageRect(logoImage, srcRect, dstRect, logoPaint);
        currentY += logoHeight + 20;
      }

      drawText('RESTAURANT VANKISI', currentY, fontSize: 30, center: true);
      currentY += 38;

      drawLine(currentY);
      currentY += 14;

      // High-contrast badge for report type (X/Z) to make it unmistakable.
      final badgeRect = Rect.fromLTWH(70, currentY, width - 140, 56);
      final badgePaint = Paint()..color = Colors.black;
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(10)),
        badgePaint,
      );
      final badgeTextPainter = TextPainter(
        text: TextSpan(
          text: reportTypeKa,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: badgeRect.width - 20);
      badgeTextPainter.paint(
        canvas,
        Offset(
          badgeRect.left + (badgeRect.width - badgeTextPainter.width) / 2,
          badgeRect.top + (badgeRect.height - badgeTextPainter.height) / 2,
        ),
      );
      currentY += 72;

      drawText(
        'თარიღი: ${DatabaseService.getGeorgianFormattedDate(DatabaseService.getCurrentDate())}',
        currentY,
        fontSize: 20,
        center: true,
      );
      currentY += 30;

      drawLine(currentY);
      currentY += 18;

      final lines = reportText.split('\n');
      for (String line in lines) {
        line = _localizeReportLineKa(line).trim();
        if (line.isEmpty) {
          currentY += 10;
          continue;
        }

        if (line.contains('═') ||
            line.contains('║') ||
            line.contains('╔') ||
            line.contains('╚')) {
          continue;
        }

        if (line.startsWith('---') || line.startsWith('===')) {
          drawLine(currentY);
          currentY += 15;
          continue;
        }

        final isSectionHeader =
            line.contains('შეჯამება') ||
            line.contains('განაწილება') ||
            line.contains('დეტალები') ||
            (line.endsWith(':') && !line.startsWith('  '));

        final isTotalLine =
            line.contains('სრული ჯამი') || line.contains('საერთო ჯამი');

        final fontSize = isTotalLine
            ? 30.0
            : (isSectionHeader ? 26.0 : (line.startsWith('*') ? 18.0 : 22.0));
        final shouldCenter =
            isSectionHeader || isTotalLine || line.startsWith('*');

        drawText(
          line,
          currentY,
          fontSize: fontSize,
          bold: isSectionHeader || isTotalLine,
          center: shouldCenter,
        );
        currentY += fontSize + (isSectionHeader ? 12 : 10);
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), (currentY + 52).toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) {
        return null;
      }

      final decodedImage = imglib.Image.fromBytes(
        width: img.width,
        height: img.height,
        bytes: byteData.buffer,
        format: imglib.Format.uint8,
        numChannels: 4,
      );

      final gray = imglib.grayscale(decodedImage);
      return EscposBitmap.convert(gray);
    } catch (e) {
      developer.log('Error generating report image: $e');
      return null;
    }
  }
}
