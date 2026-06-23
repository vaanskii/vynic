import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import '../database_service.dart';
import 'escpos_bitmap.dart';

typedef ResolveOperatorDisplayName =
    String Function(String rawName, {required bool isEnglish});

/// Renders kitchen checks into ESC/POS bytes.
class EscposKitchenRenderer {
  const EscposKitchenRenderer._();

  /// Generate ESC/POS byte commands for kitchen check (Georgian language).
  static Future<List<int>> generateBytes({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    required ResolveOperatorDisplayName resolveOperatorDisplayName,
  }) async {
    List<int> bytes = [];

    // ESC/POS Commands
    const esc = 0x1B;
    const gs = 0x1D;

    // Initialize printer
    bytes.addAll([esc, 0x40]); // ESC @ - Initialize

    // Generate bitmap image of the kitchen check
    final imageBytes = await _generateImage(
      items: items,
      addedItems: addedItems,
      removedItems: removedItems,
      tableNumber: tableNumber,
      orderNumber: orderNumber,
      waiterName: waiterName,
      createdAt: createdAt,
      resolveOperatorDisplayName: resolveOperatorDisplayName,
    );

    if (imageBytes != null) {
      // Print the bitmap image
      bytes.addAll(imageBytes);
    }

    // Add generous spacing before paper cut to prevent bottom text cutoff.
    // Thermal printers need extra feed to ensure all content is visible above the tear line.
    bytes.addAll([
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
    ]); // 6 line feeds (increased from 3)

    // Cut paper
    bytes.addAll([gs, 0x56, 0x00]); // GS V 0 - Full cut

    return bytes;
  }

  /// Generate a 1-bit bitmap image of the kitchen check.
  static Future<List<int>?> _generateImage({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    required ResolveOperatorDisplayName resolveOperatorDisplayName,
  }) async {
    try {
      // Create a custom painter for the kitchen check
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Paper width: 80mm = ~576 pixels at 72 DPI
      const double width = 576;

      // Start with top margin for better appearance
      double currentY = 20; // Top margin (increased from 10)

      // Background - white (with extra height for margins)
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, width, 2000), bgPaint);

      // Disable antialiasing for sharper text on thermal printers
      final paint = Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none;
      canvas.saveLayer(null, paint);

      // Text painter helper that returns the rendered height
      double drawText(
        String text,
        double y, {
        double fontSize = 16,
        bool bold = false,
        bool center = false,
        double leftOffset = 10.0,
      }) {
        final effectiveMaxWidth = center ? width - 20 : width - leftOffset - 10;

        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'Roboto',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: effectiveMaxWidth);

        final double xPosition = center
            ? (width - textPainter.width) / 2
            : leftOffset;

        textPainter.paint(canvas, Offset(xPosition, y));
        return textPainter.height;
      }

      const double itemFontSize = 34;
      const double commentFontSize = 32;

      void drawKitchenItem(String itemText) {
        final parts = itemText.split('\n');
        final String mainLine = parts.first.trim();
        final double mainHeight = drawText(
          mainLine,
          currentY,
          fontSize: itemFontSize,
          bold: true,
        );
        currentY += mainHeight + 12;

        for (int i = 1; i < parts.length; i++) {
          final String commentLine = parts[i].trimLeft();
          if (commentLine.isEmpty) {
            continue;
          }
          final double commentHeight = drawText(
            commentLine,
            currentY,
            fontSize: commentFontSize,
            bold: true,
            leftOffset: 36,
          );
          currentY += commentHeight + 8;
        }

        currentY += 10;
      }

      void drawRemovedKitchenItem(String itemText) {
        final parts = itemText.split('\n');
        for (int i = 0; i < parts.length; i++) {
          final String line = (i == 0 ? parts[i].trim() : parts[i].trimLeft());
          if (line.isEmpty) {
            continue;
          }

          final double fontSize = i == 0 ? itemFontSize : commentFontSize;
          final double leftOffset = i == 0 ? 10.0 : 36.0;

          final textPainter = TextPainter(
            text: TextSpan(
              text: line,
              style: TextStyle(
                color: Colors.black,
                fontSize: fontSize,
                decoration: TextDecoration.lineThrough,
                decorationThickness: 2,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(maxWidth: width - leftOffset - 10);
          textPainter.paint(canvas, Offset(leftOffset, currentY));
          currentY += textPainter.height + 8;
        }

        currentY += 10;
      }

      // Table number - emphasized
      if (tableNumber != null) {
        final double height = drawText(
          'მაგიდა: $tableNumber',
          currentY,
          fontSize: 36,
          bold: true,
        );
        currentY += height + 16;
      }

      // Waiter name
      if (waiterName != null) {
        final operatorName = resolveOperatorDisplayName(
          waiterName,
          isEnglish: false,
        );
        final double height = drawText(
          'ოფიციანტი: $operatorName',
          currentY,
          fontSize: 32,
          bold: true,
        );
        currentY += height + 12;
      }

      // Order number (used for reservation ready time)
      if (orderNumber != null) {
        final double height = drawText(
          orderNumber,
          currentY,
          fontSize: 26,
          bold: true,
        );
        currentY += height + 14;
      }

      // Time
      if (createdAt != null) {
        final dateString = DatabaseService.getGeorgianFormattedDate(createdAt);
        final double dateHeight = drawText(
          'თარიღი: $dateString',
          currentY,
          fontSize: 30,
          bold: true,
        );
        currentY += dateHeight + 6;

        final timeString =
            '${createdAt.hour.toString().padLeft(2, '0')}:'
            '${createdAt.minute.toString().padLeft(2, '0')}:'
            '${createdAt.second.toString().padLeft(2, '0')}';
        final double height = drawText(
          'დრო: $timeString',
          currentY,
          fontSize: 32,
          bold: true,
        );
        currentY += height + 10;
      }

      // Separator line
      final linePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(10, currentY),
        Offset(width - 10, currentY),
        linePaint,
      );
      currentY += 15;

      // Check if this is a modification (has added or removed items)
      final isModification =
          (addedItems != null && addedItems.isNotEmpty) ||
          (removedItems != null && removedItems.isNotEmpty);

      // If modification, show removed items first
      if (removedItems != null && removedItems.isNotEmpty) {
        final double headingHeight = drawText(
          'გაუქმდა:',
          currentY,
          fontSize: 28,
          bold: true,
        );
        currentY += headingHeight + 16;

        for (final item in removedItems) {
          drawRemovedKitchenItem(item);
        }
        currentY += 6; // Extra space between sections
      }

      // If modification, show added items
      if (addedItems != null && addedItems.isNotEmpty) {
        final double headingHeight = drawText(
          'დაემატა:',
          currentY,
          fontSize: 28,
          bold: true,
        );
        currentY += headingHeight + 16;

        for (final item in addedItems) {
          drawKitchenItem(item);
        }
        currentY += 6; // Extra space
      }

      // If NOT a modification, show all items normally
      if (!isModification && items.isNotEmpty) {
        for (final item in items) {
          drawKitchenItem(item);
        }
      }

      // Add generous bottom margin to prevent text cutoff.
      // Thermal printers cut immediately after content ends.
      currentY += 80; // Extra blank space before cut (increased from 20)

      // Ensure minimum height to avoid paper feed issues
      const double minHeight = 300; // Minimum receipt height
      final double finalHeight = currentY < minHeight ? minHeight : currentY;

      // Restore canvas layer
      canvas.restore();

      // Finish the picture with proper height
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), finalHeight.toInt());

      // Skip PNG encode/decode - use raw RGBA directly
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) return null;

      // Convert raw RGBA bytes to imglib.Image (2-3x faster than PNG roundtrip)
      final buffer = byteData.buffer.asUint8List();
      final decodedImage = imglib.Image.fromBytes(
        width: img.width,
        height: img.height,
        bytes: buffer.buffer,
        format: imglib.Format.uint8,
        numChannels: 4,
      );

      // Convert to grayscale for better contrast on thermal printers
      final gray = imglib.grayscale(decodedImage);

      // Generate ESC/POS bitmap commands using line-by-line raster mode
      return EscposBitmap.convert(gray);
    } catch (e) {
      developer.log('Error generating kitchen check image: $e');
      return null;
    }
  }
}
