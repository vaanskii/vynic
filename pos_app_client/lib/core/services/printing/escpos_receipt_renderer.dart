import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import 'escpos_bitmap.dart';

typedef LoadReceiptLogoImage = Future<ui.Image?> Function();
typedef GetReceiptLogoContentRect = Future<Rect> Function(ui.Image image);

/// Renders customer receipts into ESC/POS bytes and PNG previews.
class EscposReceiptRenderer {
  const EscposReceiptRenderer._();

  /// Generate ESC/POS byte commands for customer receipt.
  static Future<List<int>> generateBytes({
    required List<String> items,
    required double total,
    double? subtotal,
    double? serviceFee,
    bool includeServiceFee = false,
    String? tableNumber,
    String? orderNumber,
    String? paymentMethod,
    String? language = 'ka',
    double? packageSubtotal,
    double? additionalSubtotal,
    double? discountAmount,
    double? manualAdjustment,
    String? receiptType,
    required LoadReceiptLogoImage loadReceiptLogoImage,
    required GetReceiptLogoContentRect getReceiptLogoContentRect,
  }) async {
    List<int> bytes = [];

    // ESC/POS Commands
    const esc = 0x1B;
    const gs = 0x1D;

    // Initialize printer
    bytes.addAll([esc, 0x40]); // ESC @ - Initialize

    // Generate bitmap image of the receipt
    final imageBytes = await _generateReceiptImage(
      items: items,
      total: total,
      subtotal: subtotal,
      serviceFee: serviceFee,
      includeServiceFee: includeServiceFee,
      tableNumber: tableNumber,
      orderNumber: orderNumber,
      paymentMethod: paymentMethod,
      language: language,
      packageSubtotal: packageSubtotal,
      additionalSubtotal: additionalSubtotal,
      discountAmount: discountAmount,
      manualAdjustment: manualAdjustment,
      receiptType: receiptType,
      loadReceiptLogoImage: loadReceiptLogoImage,
      getReceiptLogoContentRect: getReceiptLogoContentRect,
    );

    if (imageBytes != null) {
      // Print the bitmap image
      bytes.addAll(imageBytes);
    }

    // Add spacing before paper cut
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 6 line feeds

    // Cut paper
    bytes.addAll([gs, 0x56, 0x00]); // GS V 0 - Full cut

    return bytes;
  }

  static Future<Uint8List?> generatePngBytes({
    required List<String> items,
    required double total,
    double? subtotal,
    double? serviceFee,
    bool includeServiceFee = false,
    String? tableNumber,
    String? orderNumber,
    String? paymentMethod,
    String? language = 'ka',
    double? packageSubtotal,
    double? additionalSubtotal,
    double? discountAmount,
    double? manualAdjustment,
    String? receiptType,
    required LoadReceiptLogoImage loadReceiptLogoImage,
    required GetReceiptLogoContentRect getReceiptLogoContentRect,
  }) async {
    try {
      final img = await _generateReceiptUiImage(
        items: items,
        total: total,
        subtotal: subtotal,
        serviceFee: serviceFee,
        includeServiceFee: includeServiceFee,
        tableNumber: tableNumber,
        orderNumber: orderNumber,
        paymentMethod: paymentMethod,
        language: language,
        packageSubtotal: packageSubtotal,
        additionalSubtotal: additionalSubtotal,
        discountAmount: discountAmount,
        manualAdjustment: manualAdjustment,
        receiptType: receiptType,
        loadReceiptLogoImage: loadReceiptLogoImage,
        getReceiptLogoContentRect: getReceiptLogoContentRect,
      );
      if (img == null) return null;

      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      developer.log('Error generating receipt PNG: $e');
      return null;
    }
  }

  /// Generate a 1-bit bitmap image of the receipt.
  static Future<ui.Image?> _generateReceiptUiImage({
    required List<String> items,
    required double total,
    double? subtotal,
    double? serviceFee,
    bool includeServiceFee = false,
    String? tableNumber,
    String? orderNumber,
    String? paymentMethod,
    String? language = 'ka',
    double? packageSubtotal,
    double? additionalSubtotal,
    double? discountAmount,
    double? manualAdjustment,
    String? receiptType,
    required LoadReceiptLogoImage loadReceiptLogoImage,
    required GetReceiptLogoContentRect getReceiptLogoContentRect,
  }) async {
    try {
      // Create a custom painter for the receipt
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Paper width: 80mm = ~576 pixels at 72 DPI
      const double width = 576;

      // Add top padding in header.
      double currentY = 28;

      final parsedRows = _parseReceiptItemRows(items);
      final isEnglish = (language ?? 'ka').toLowerCase() == 'en';
      final resolvedReceiptType = _resolveReceiptType(
        receiptType: receiptType,
        paymentMethod: paymentMethod,
        items: items,
      );
      final bool isCloseTableReceipt = resolvedReceiptType == 'close_table';
      final bool isMenuCountReceipt = resolvedReceiptType == 'menu_count';
      final bool isTakeAwayReceipt = _isTakeAwayTableLabel(tableNumber);
      final bool hasPaymentMethod =
          isCloseTableReceipt &&
          _resolvePaymentMethodLabel(
                paymentMethod: paymentMethod,
                items: items,
                isEnglish: isEnglish,
              ) !=
              null;

      final double estimatedHeight =
          560 + (parsedRows.length * 42) + (hasPaymentMethod ? 40 : 0) + 170;

      final double backgroundHeight = estimatedHeight < 2000
          ? 2000
          : estimatedHeight + 120;

      // Background - white
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, width, backgroundHeight), bgPaint);

      // Text painter helper
      void drawText(
        String text,
        double y, {
        double fontSize = 16,
        bool bold = false,
        bool center = false,
        double maxWidth = width - 20,
        String fontFamily = 'Roboto',
      }) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontFamily: fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: maxWidth);

        final xPosition = center ? (width - textPainter.width) / 2 : 4.0;

        textPainter.paint(canvas, Offset(xPosition, y));
      }

      double drawCenteredLine(
        String text,
        double y, {
        double fontSize = 24,
        bool bold = false,
      }) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        painter.layout(maxWidth: width);
        painter.paint(canvas, Offset((width - painter.width) / 2, y));
        return painter.height;
      }

      // Centered content block with side padding (not full width).
      const double contentWidth = 520;
      final double contentLeft = (width - contentWidth) / 2;

      double drawLabelValueLine(
        String label,
        String value,
        double y, {
        double fontSize = 24,
        bool bold = false,
      }) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        final valuePainter = TextPainter(
          text: TextSpan(
            text: value,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        valuePainter.layout(maxWidth: contentWidth * 0.42);
        final valueX = contentLeft + contentWidth - valuePainter.width;

        labelPainter.layout(maxWidth: valueX - contentLeft - 8);

        labelPainter.paint(canvas, Offset(contentLeft, y));
        valuePainter.paint(canvas, Offset(valueX, y));

        return labelPainter.height > valuePainter.height
            ? labelPainter.height
            : valuePainter.height;
      }

      double drawItemColumnsLine(
        String name,
        String qty,
        String price,
        double y, {
        bool bold = false,
      }) {
        const double qtyColumnWidth = 90;
        const double priceColumnWidth = 170;
        const double colGap = 10;

        final priceRight = contentLeft + contentWidth;
        final priceLeft = priceRight - priceColumnWidth;
        final qtyRight = priceLeft - colGap;
        final qtyLeft = qtyRight - qtyColumnWidth;
        final nameRight = qtyLeft - colGap;

        final namePainter = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: nameRight - contentLeft);

        final qtyPainter = TextPainter(
          text: TextSpan(
            text: qty,
            style: TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: qtyColumnWidth);

        final pricePainter = TextPainter(
          text: TextSpan(
            text: price,
            style: TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'NotoSansGeorgian',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: priceColumnWidth);

        namePainter.paint(canvas, Offset(contentLeft, y));
        qtyPainter.paint(canvas, Offset(qtyRight - qtyPainter.width, y));
        pricePainter.paint(canvas, Offset(priceRight - pricePainter.width, y));

        double maxH = namePainter.height;
        if (qtyPainter.height > maxH) {
          maxH = qtyPainter.height;
        }
        if (pricePainter.height > maxH) {
          maxH = pricePainter.height;
        }
        return maxH;
      }

      final logoImage = await loadReceiptLogoImage();
      if (logoImage != null) {
        // Fit into requested bounds without cropping.
        const maxLogoWidth = 384.0;
        const maxLogoHeight = 120.0;
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
        final logoTop = currentY;
        final dstRect = Rect.fromLTWH(logoLeft, logoTop, logoWidth, logoHeight);
        final logoPaint = Paint()
          ..isAntiAlias = false
          ..filterQuality = FilterQuality.none
          // Force solid black logo regardless of source colors.
          ..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn);

        canvas.drawImageRect(logoImage, srcRect, dstRect, logoPaint);
        currentY += logoHeight + 18;

        drawText(
          'RESTAURANT VANKISI',
          currentY,
          fontSize: 36,
          bold: false,
          center: true,
        );
        currentY += 42;
      } else {
        // Fallback if custom logo asset is missing.
        drawText(
          'RESTAURANT VANKISI',
          currentY,
          fontSize: 36,
          bold: false,
          center: true,
        );
        currentY += 44;
      }

      drawText(
        isEnglish ? 'Aleksandre Pushkini ST N51' : 'ალექსანდრე პუშკინის ქ. N51',
        currentY,
        fontSize: 22,
        bold: false,
        center: true,
      );
      currentY += 34;

      drawText(
        '+995 599 98 93 76',
        currentY,
        fontSize: 22,
        bold: false,
        center: true,
      );
      currentY += 34;

      // Body/footer layout with bilingual labels and fixed-width alignment.
      final now = DateTime.now();
      final dateString =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      final packageAmount = packageSubtotal ?? 0.0;
      final baseAdditionalAmount = additionalSubtotal ?? subtotal ?? 0.0;
      final serviceFeeAmount = includeServiceFee ? (serviceFee ?? 0.0) : 0.0;
      final discountValue = discountAmount ?? 0.0;
      final manualAdjustmentValue = manualAdjustment ?? 0.0;

      final hasBreakdownData =
          packageSubtotal != null ||
          additionalSubtotal != null ||
          subtotal != null ||
          serviceFee != null ||
          discountAmount != null ||
          manualAdjustment != null;

      double? computedTotal;
      if (hasBreakdownData) {
        final rawTotal =
            packageAmount +
            baseAdditionalAmount +
            serviceFeeAmount -
            discountValue +
            manualAdjustmentValue;
        if (rawTotal > 0) {
          computedTotal = double.parse(rawTotal.toStringAsFixed(2));
        }
      }

      final providedTotal = double.parse(total.toStringAsFixed(2));
      // For close-table receipts, the passed total is the remaining payable
      // amount and must not be recomputed from subtotals.
      final effectiveTotal = isCloseTableReceipt
          ? providedTotal
          : (computedTotal != null &&
                    (providedTotal - computedTotal).abs() > 0.01
                ? computedTotal
                : providedTotal);

      final tableValue = (tableNumber ?? '').trim().isEmpty
          ? '-'
          : tableNumber!.trim();
      final paymentValue = _resolvePaymentMethodLabel(
        paymentMethod: paymentMethod,
        items: items,
        isEnglish: isEnglish,
      );

      currentY += drawCenteredLine(
        isCloseTableReceipt
            ? (isEnglish ? 'CLOSE TABLE RECEIPT' : 'მაგიდის დახურვის ქვითარი')
            : (isEnglish ? 'RECEIPT' : 'ქვითარი'),
        currentY,
        bold: true,
      );
      currentY += 24;

      if (!isMenuCountReceipt) {
        if (!isTakeAwayReceipt && tableValue != '-') {
          currentY += drawLabelValueLine(
            isEnglish ? 'Table' : 'მაგიდა',
            tableValue,
            currentY,
          );
          currentY += 12;
        }
      }
      currentY += drawLabelValueLine(
        isEnglish ? 'Date' : 'თარიღი',
        dateString,
        currentY,
      );
      currentY += 24;

      currentY += drawItemColumnsLine(
        isEnglish ? 'ITEM NAME' : 'დასახელება',
        'QTY',
        isEnglish ? 'PRICE' : 'ფასი',
        currentY,
        bold: true,
      );
      currentY += 20;

      final hasPackageItems =
          (packageSubtotal ?? 0) > 0 ||
          parsedRows.any(
            (row) => !row.isSection && row.sectionType == 'package',
          );
      final hasAdditionalItems =
          (additionalSubtotal ?? 0) > 0 ||
          parsedRows.any(
            (row) => !row.isSection && row.sectionType == 'additional',
          );

      bool packageTotalShown = false;
      bool additionalLabelShown = false;

      for (final row in parsedRows) {
        if (row.isSection) {
          if (hasPackageItems && row.sectionType == 'additional') {
            if (!packageTotalShown &&
                packageSubtotal != null &&
                packageSubtotal > 0) {
              currentY += drawLabelValueLine(
                isEnglish ? 'Package Total' : 'პაკეტის ჯამი',
                '${packageSubtotal.toStringAsFixed(2)} GEL',
                currentY,
                bold: true,
              );
              currentY += 16;
              packageTotalShown = true;
            }

            if (!additionalLabelShown) {
              currentY += drawCenteredLine(
                isEnglish ? 'ADDITIONAL' : 'დამატება',
                currentY,
                bold: true,
              );
              currentY += 14;
              additionalLabelShown = true;
            }
          }
          continue;
        }

        if (hasPackageItems &&
            row.sectionType == 'additional' &&
            !additionalLabelShown) {
          if (!packageTotalShown &&
              packageSubtotal != null &&
              packageSubtotal > 0) {
            currentY += drawLabelValueLine(
              isEnglish ? 'Package Total' : 'პაკეტის ჯამი',
              '${packageSubtotal.toStringAsFixed(2)} GEL',
              currentY,
              bold: true,
            );
            currentY += 16;
            packageTotalShown = true;
          }

          currentY += drawCenteredLine(
            isEnglish ? 'ADDITIONAL' : 'დამატება',
            currentY,
            bold: true,
          );
          currentY += 14;
          additionalLabelShown = true;
        }

        currentY += drawItemColumnsLine(
          row.name,
          row.qty ?? '',
          row.price ?? '',
          currentY,
        );
        currentY += 10;
      }
      currentY += 20;

      if (hasPackageItems &&
          !packageTotalShown &&
          packageSubtotal != null &&
          packageSubtotal > 0) {
        currentY += drawLabelValueLine(
          isEnglish ? 'Package Total' : 'პაკეტის ჯამი',
          '${packageSubtotal.toStringAsFixed(2)} GEL',
          currentY,
          bold: true,
        );
        currentY += 12;
      }

      if (hasPackageItems &&
          hasAdditionalItems &&
          additionalSubtotal != null &&
          additionalSubtotal > 0) {
        currentY += drawLabelValueLine(
          isEnglish ? 'Additional Items Total' : 'დამატებითი ჯამი',
          '${additionalSubtotal.toStringAsFixed(2)} GEL',
          currentY,
          bold: true,
        );
        currentY += 12;
      }

      if (!isCloseTableReceipt && includeServiceFee) {
        final serviceFeeLabel = isEnglish
            ? 'Service Fee Included'
            : 'სერვისის საფასური დამატებულია';
        final serviceFeeValue = (serviceFee != null && serviceFee > 0)
            ? '+${serviceFee.toStringAsFixed(2)} GEL'
            : '';

        if (serviceFeeValue.isNotEmpty) {
          currentY += drawLabelValueLine(
            serviceFeeLabel,
            serviceFeeValue,
            currentY,
          );
        } else {
          currentY += drawCenteredLine(serviceFeeLabel, currentY, fontSize: 22);
        }
        currentY += 18;
      }

      final hasAdvancePayment = !isCloseTableReceipt && discountValue > 0.0;
      if (hasAdvancePayment) {
        final grossTotal = effectiveTotal + discountValue;
        currentY += drawLabelValueLine(
          isEnglish ? 'TOTAL' : 'სულ',
          '${grossTotal.toStringAsFixed(2)} GEL',
          currentY,
          fontSize: 28,
          bold: true,
        );
        currentY += 12;

        currentY += drawLabelValueLine(
          isEnglish ? 'Advance Payment' : 'ავანსი',
          '${discountValue.toStringAsFixed(2)} GEL',
          currentY,
          fontSize: 26,
          bold: true,
        );
        currentY += 12;

        currentY += drawLabelValueLine(
          isEnglish ? 'Remaining' : 'დარჩენილი',
          '${effectiveTotal.toStringAsFixed(2)} GEL',
          currentY,
          fontSize: 30,
          bold: true,
        );
        currentY += 18;
      } else {
        currentY += drawLabelValueLine(
          isEnglish ? 'TOTAL' : 'სულ',
          '${effectiveTotal.toStringAsFixed(2)} GEL',
          currentY,
          fontSize: 30,
          bold: true,
        );
        currentY += 18;
      }

      if (isCloseTableReceipt && paymentValue != null) {
        currentY += drawLabelValueLine(
          isEnglish ? 'Payment Method' : 'გადახდის მეთოდი',
          paymentValue,
          currentY,
        );
        currentY += 18;
      }

      currentY += 18;
      if (isMenuCountReceipt) {
        currentY += drawCenteredLine('გვესტუმრეთ არ ინანებთ!', currentY);
      } else {
        currentY += drawCenteredLine(
          isEnglish ? 'Thank you for visiting!' : 'მადლობა სტუმრობისთვის!',
          currentY,
        );
        currentY += 10;
        currentY += drawCenteredLine(
          isEnglish ? 'See you again!' : 'გელოდებით კვლავ!',
          currentY,
        );
      }

      currentY += 36;

      currentY += 46;

      // Minimum height
      const double minHeight = 300;
      final double finalHeight = currentY < minHeight ? minHeight : currentY;

      // Finish the picture
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), finalHeight.toInt());
      return img;
    } catch (e) {
      developer.log('Error generating receipt ui.Image: $e');
      return null;
    }
  }

  static Future<List<int>?> _generateReceiptImage({
    required List<String> items,
    required double total,
    double? subtotal,
    double? serviceFee,
    bool includeServiceFee = false,
    String? tableNumber,
    String? orderNumber,
    String? paymentMethod,
    String? language = 'ka',
    double? packageSubtotal,
    double? additionalSubtotal,
    double? discountAmount,
    double? manualAdjustment,
    String? receiptType,
    required LoadReceiptLogoImage loadReceiptLogoImage,
    required GetReceiptLogoContentRect getReceiptLogoContentRect,
  }) async {
    try {
      final img = await _generateReceiptUiImage(
        items: items,
        total: total,
        subtotal: subtotal,
        serviceFee: serviceFee,
        includeServiceFee: includeServiceFee,
        tableNumber: tableNumber,
        orderNumber: orderNumber,
        paymentMethod: paymentMethod,
        language: language,
        packageSubtotal: packageSubtotal,
        additionalSubtotal: additionalSubtotal,
        discountAmount: discountAmount,
        manualAdjustment: manualAdjustment,
        receiptType: receiptType,
        loadReceiptLogoImage: loadReceiptLogoImage,
        getReceiptLogoContentRect: getReceiptLogoContentRect,
      );
      if (img == null) return null;

      // Convert to raw RGBA
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) return null;

      // Convert to grayscale image
      final buffer = byteData.buffer.asUint8List();

      for (int i = 0; i < buffer.length; i += 4) {
        if (buffer[i + 3] == 0) {
          buffer[i] = 0xFF;
          buffer[i + 1] = 0xFF;
          buffer[i + 2] = 0xFF;
          buffer[i + 3] = 0xFF;
        }
      }

      final decodedImage = imglib.Image.fromBytes(
        width: img.width,
        height: img.height,
        bytes: buffer.buffer,
        format: imglib.Format.uint8,
        numChannels: 4,
      );

      final gray = imglib.grayscale(decodedImage);

      // Generate ESC/POS bitmap commands
      return EscposBitmap.convert(gray);
    } catch (e) {
      developer.log('Error generating receipt image: $e');
      return null;
    }
  }

  static String _resolveReceiptType({
    String? receiptType,
    String? paymentMethod,
    required List<String> items,
  }) {
    final normalizedType = receiptType?.trim().toLowerCase();
    if (normalizedType == 'client' ||
        normalizedType == 'close_table' ||
        normalizedType == 'menu_count' ||
        normalizedType == 'take_away') {
      return normalizedType!;
    }

    if (paymentMethod != null && paymentMethod.trim().isNotEmpty) {
      return 'close_table';
    }

    for (final line in items) {
      final normalized = line.toLowerCase();
      if (normalized.contains('გადახდა') || normalized.contains('payment')) {
        return 'close_table';
      }
    }
    return 'client';
  }

  static String? _resolvePaymentMethodLabel({
    String? paymentMethod,
    required List<String> items,
    required bool isEnglish,
  }) {
    final normalizedPayment = paymentMethod?.trim().toLowerCase();
    if (normalizedPayment == 'split') {
      final hasBog = items.any((line) => line.toLowerCase().contains('bog'));
      final hasTbc = items.any((line) => line.toLowerCase().contains('tbc'));
      final hasCash = items.any(
        (line) => line.toLowerCase().contains('cash') || line.contains('ნაღდი'),
      );

      final cardPart = hasBog
          ? (isEnglish ? 'Card (BOG)' : 'ბარათი (BOG)')
          : hasTbc
          ? (isEnglish ? 'Card (TBC)' : 'ბარათი (TBC)')
          : (isEnglish ? 'Card' : 'ბარათი');
      final cashPart = isEnglish ? 'Cash' : 'ნაღდი';

      if (hasCash) {
        return isEnglish
            ? 'Split ($cashPart + $cardPart)'
            : 'გაყოფილი ($cashPart + $cardPart)';
      }
      return isEnglish ? 'Split' : 'გაყოფილი';
    }

    final direct = _normalizePaymentMethod(paymentMethod, isEnglish: isEnglish);
    if (direct != null) {
      return direct;
    }

    final methods = <String>{};
    for (final line in items) {
      final normalized = line.toLowerCase();
      if (line.contains('ბანკი') || normalized.contains('bank')) {
        methods.add(isEnglish ? 'Bank' : 'ბანკი');
      }
      if (line.contains('ნაღდი') || normalized.contains('cash')) {
        methods.add(isEnglish ? 'Cash' : 'ნაღდი');
      }
      if (line.contains('ბარათი') || normalized.contains('card')) {
        methods.add(isEnglish ? 'Card' : 'ბარათი');
      }
    }

    if (methods.isEmpty) {
      return null;
    }
    return methods.join(' + ');
  }

  static String? _normalizePaymentMethod(
    String? value, {
    required bool isEnglish,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'cash':
      case 'ნაღდი':
        return isEnglish ? 'Cash' : 'ნაღდი';
      case 'card-tbc':
      case 'card_tbc':
      case 'tbc':
        return isEnglish ? 'Card (TBC)' : 'ბარათი (TBC)';
      case 'card-bog':
      case 'card_bog':
      case 'bog':
        return isEnglish ? 'Card (BOG)' : 'ბარათი (BOG)';
      case 'card':
      case 'ბარათი':
        return isEnglish ? 'Card' : 'ბარათი';
      case 'bank':
      case 'bank_transfer':
      case 'ბანკი':
        return isEnglish ? 'Card' : 'ბარათი';
      case 'split':
        return isEnglish ? 'Split' : 'გაყოფილი';
      case 'non-fiscal':
      case 'non_fiscal':
        return isEnglish ? 'Non-Fiscal' : 'არაფისკალური';
      default:
        return _stripAmountFromPaymentLabel(value.trim());
    }
  }

  static String _stripAmountFromPaymentLabel(String value) {
    var result = value;
    result = result.replaceAll(RegExp(r'₾\s*\d+(?:\.\d+)?'), '');
    result = result.replaceAll(
      RegExp(r'\d+(?:\.\d+)?\s*GEL', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return result;
  }

  static List<_ReceiptItemRow> _parseReceiptItemRows(List<String> items) {
    final List<_ReceiptItemRow> rows = [];
    final pricedRegex = RegExp(
      r'^(\d+(?:\.\d+)?)x?\s+(.+?)\s*[-–]\s*(?:₾|gel)?\s*(\d+(?:\.\d{1,2})?)\s*(?:gel|₾)?$',
      caseSensitive: false,
    );
    final qtyRegex = RegExp(r'^(\d+(?:\.\d+)?)x?\s+(.+)$');
    String? activeSectionName;
    String activeSectionType = 'other';

    for (final raw in items) {
      final parts = raw.split('\n');
      if (parts.isEmpty) {
        continue;
      }

      final main = parts.first.trim();
      if (main == '---') {
        if (activeSectionType == 'package') {
          activeSectionType = 'additional';
        }
        continue;
      }
      if (_isMetadataOrPaymentLine(main)) {
        continue;
      }
      if (main.isEmpty) {
        continue;
      }

      if (main.startsWith('[') && main.endsWith(']') && main.length > 2) {
        activeSectionName = main.substring(1, main.length - 1).trim();
        activeSectionType = _resolveReceiptSectionType(activeSectionName);
        rows.add(
          _ReceiptItemRow(
            name: activeSectionName,
            isSection: true,
            sectionType: activeSectionType,
          ),
        );
      } else {
        final pricedMatch = pricedRegex.firstMatch(main);
        if (pricedMatch != null) {
          final parsedName = (pricedMatch.group(2) ?? '').trim();
          final bool isPackageSummary =
              activeSectionName != null &&
              _looksLikePackageSummaryItem(parsedName, activeSectionName);
          if (!isPackageSummary) {
            rows.add(
              _ReceiptItemRow(
                name: parsedName,
                qty: _formatQty(pricedMatch.group(1) ?? ''),
                price: _formatPrice(pricedMatch.group(3) ?? ''),
                sectionType: activeSectionType,
              ),
            );
          }
        } else {
          final qtyMatch = qtyRegex.firstMatch(main);
          if (qtyMatch != null) {
            rows.add(
              _ReceiptItemRow(
                name: (qtyMatch.group(2) ?? '').trim(),
                qty: _formatQty(qtyMatch.group(1) ?? ''),
                sectionType: activeSectionType,
              ),
            );
          } else {
            rows.add(
              _ReceiptItemRow(name: main, sectionType: activeSectionType),
            );
          }
        }
      }

      for (int i = 1; i < parts.length; i++) {
        final detail = parts[i].trimLeft();
        if (detail.isEmpty || _isMetadataOrPaymentLine(detail)) {
          continue;
        }
        final cleanDetail = detail.replaceFirst(RegExp(r'^⮑\s*'), '').trim();
        final detailPricedMatch = pricedRegex.firstMatch(cleanDetail);
        if (detailPricedMatch != null) {
          rows.add(
            _ReceiptItemRow(
              name: (detailPricedMatch.group(2) ?? '').trim(),
              qty: _formatQty(detailPricedMatch.group(1) ?? ''),
              price: _formatPrice(detailPricedMatch.group(3) ?? ''),
              sectionType: activeSectionType,
            ),
          );
          continue;
        }

        final detailQtyMatch = qtyRegex.firstMatch(cleanDetail);
        if (detailQtyMatch != null) {
          rows.add(
            _ReceiptItemRow(
              name: (detailQtyMatch.group(2) ?? '').trim(),
              qty: _formatQty(detailQtyMatch.group(1) ?? ''),
              sectionType: activeSectionType,
            ),
          );
          continue;
        }

        rows.add(
          _ReceiptItemRow(name: cleanDetail, sectionType: activeSectionType),
        );
      }
    }

    return rows;
  }

  static bool _looksLikePackageSummaryItem(
    String itemName,
    String sectionName,
  ) {
    final name = itemName.toLowerCase().trim();
    final section = sectionName.toLowerCase().trim();

    if (name.isEmpty || section.isEmpty) {
      return false;
    }

    if (name == section || name.contains(section) || section.contains(name)) {
      return true;
    }

    return name.contains('package') || name.contains('პაკეტ');
  }

  static String _resolveReceiptSectionType(String sectionName) {
    final normalized = sectionName.toLowerCase();
    if (normalized.contains('additional') || normalized.contains('დამატ')) {
      return 'additional';
    }
    if (normalized.contains('package') || normalized.contains('პაკეტ')) {
      return 'package';
    }
    return 'other';
  }

  static bool _isTakeAwayTableLabel(String? tableNumber) {
    final raw = (tableNumber ?? '').trim().toLowerCase();
    if (raw.isEmpty) {
      return false;
    }

    if (raw == 'takeaway' ||
        raw == 'take-away' ||
        raw.contains('take away') ||
        raw.contains('take-away')) {
      return true;
    }

    final parts = raw.split(',');
    for (final part in parts) {
      final normalized = part.trim();
      final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalized.startsWith('ta-') ||
          normalized == 'ta' ||
          normalized.startsWith('ta ') ||
          normalized.startsWith('ta_') ||
          compact.startsWith('ta') ||
          normalized.contains('take away') ||
          normalized.contains('take-away')) {
        return true;
      }
    }

    return false;
  }

  static bool _isMetadataOrPaymentLine(String line) {
    if (line.isEmpty || line == '---') {
      return true;
    }

    final normalized = line.toLowerCase();
    return line.startsWith('Order #') ||
        normalized.startsWith('სუფრა:') ||
        normalized.startsWith('table:') ||
        normalized.startsWith('date:') ||
        normalized.startsWith('დახურვა:') ||
        normalized.startsWith('გადახდა:') ||
        normalized.startsWith('payment:') ||
        normalized.startsWith('ოფიციანტი:') ||
        normalized.startsWith('waiter:') ||
        line.startsWith('•');
  }

  static String _formatQty(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final rounded = parsed.roundToDouble();
    if ((parsed - rounded).abs() < 0.001) {
      return rounded.toInt().toString();
    }
    return parsed.toStringAsFixed(2);
  }

  static String _formatPrice(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return parsed.toStringAsFixed(2);
  }
}

class _ReceiptItemRow {
  const _ReceiptItemRow({
    required this.name,
    this.qty,
    this.price,
    this.isSection = false,
    this.sectionType = 'other',
  });

  final String name;
  final String? qty;
  final String? price;
  final bool isSection;
  final String sectionType;
}
