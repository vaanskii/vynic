import 'dart:io';
import 'dart:ui' as ui;
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'database_service.dart';
import 'printer_connection.dart';

/// Service for printing to POS printers over raw TCP sockets
/// Supports kitchen checks and customer receipts with persistent connections
class PrinterService {
  // Printer configuration (overridable via settings)
  static String get _kitchenPrinterIp => DatabaseService.getKitchenPrinterIp();
  static String get _receiptPrinterIp => DatabaseService.getReceiptPrinterIp();
  static int get _kitchenPrinterPort => DatabaseService.getKitchenPrinterPort();
  static int get _receiptPrinterPort => DatabaseService.getReceiptPrinterPort();
  static int get _printerPort => DatabaseService.getPrinterPort();

  // Connection retry configuration (used for fallback)
  static const int _maxRetries = 2;
  static const Duration _connectionTimeout = Duration(seconds: 5);

  // Background print queue - prevents UI blocking and handles multiple print jobs
  static final List<Future<void>> _printQueue = [];
  static bool _isPrintQueueProcessing = false;

  // Persistent printer connections
  static bool _isInitialized = false;
  static const String _receiptLogoAssetPath = 'assets/black-logo.png';
  static ui.Image? _cachedReceiptLogo;
  static Rect? _cachedReceiptLogoContentRect;

  static Future<ui.Image?> _loadReceiptLogoImage() async {
    if (_cachedReceiptLogo != null) {
      return _cachedReceiptLogo;
    }

    try {
      final data = await rootBundle.load(_receiptLogoAssetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cachedReceiptLogo = frame.image;
      _cachedReceiptLogoContentRect = null;
      return _cachedReceiptLogo;
    } catch (e) {
      developer.log('Receipt logo not available at $_receiptLogoAssetPath: $e');
      return null;
    }
  }

  static Future<Rect> _getReceiptLogoContentRect(ui.Image image) async {
    if (_cachedReceiptLogoContentRect != null) {
      return _cachedReceiptLogoContentRect!;
    }

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        final fullRect = Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
        _cachedReceiptLogoContentRect = fullRect;
        return fullRect;
      }

      final bytes = data.buffer.asUint8List();
      final width = image.width;
      final height = image.height;

      int minX = width;
      int minY = height;
      int maxX = -1;
      int maxY = -1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final index = (y * width + x) * 4;
          final r = bytes[index];
          final g = bytes[index + 1];
          final b = bytes[index + 2];
          final a = bytes[index + 3];

          // Keep only real logo ink (black/dark pixels), ignore white/near-white background.
          final bool isInk = a > 12 && (r < 242 || g < 242 || b < 242);
          if (!isInk) {
            continue;
          }

          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }

      Rect result;
      if (maxX < minX || maxY < minY) {
        result = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      } else {
        const int pad = 1;
        final left = (minX - pad).clamp(0, width - 1);
        final top = (minY - pad).clamp(0, height - 1);
        final right = (maxX + pad).clamp(0, width - 1);
        final bottom = (maxY + pad).clamp(0, height - 1);
        result = Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          (right + 1).toDouble(),
          (bottom + 1).toDouble(),
        );
      }

      _cachedReceiptLogoContentRect = result;
      return result;
    } catch (e) {
      developer.log('Unable to trim receipt logo margins: $e');
      final fullRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      _cachedReceiptLogoContentRect = fullRect;
      return fullRect;
    }
  }

  /// Initialize persistent printer connections
  /// Call this once during app startup for best performance
  static Future<void> initialize({bool forceReconnect = false}) async {
    if (_isInitialized && !forceReconnect) {
      developer.log('⚠️ PrinterService already initialized');
      return;
    }

    if (forceReconnect && _isInitialized) {
      PrinterConnectionManager.instance.dispose();
      _isInitialized = false;
    }

    final kitchenIp = _kitchenPrinterIp;
    final receiptIp = _receiptPrinterIp;
    final kitchenPort = _kitchenPrinterPort;
    final receiptPort = _receiptPrinterPort;

    if (kitchenIp.isEmpty && receiptIp.isEmpty) {
      developer.log(
        '⚠️ PrinterService skipped initialization: no printer IP configured',
      );
      return;
    }

    try {
      await PrinterConnectionManager.instance.initialize(
        kitchenIp: kitchenIp,
        receiptIp: receiptIp,
        kitchenPort: kitchenPort,
        receiptPort: receiptPort,
      );
      _isInitialized = true;
      developer.log('✅ PrinterService initialized with persistent connections');
    } catch (e) {
      developer.log('⚠️ PrinterService initialization failed: $e');
      // Don't throw - we can still use fallback method
    }
  }

  /// Dispose printer connections
  /// Call this when shutting down the app
  static void dispose() {
    PrinterConnectionManager.instance.dispose();
    _isInitialized = false;
  }

  // Drink/bar category keywords that should NOT go to kitchen (bar items only)
  static List<String> get _barCategoryKeywords =>
      DatabaseService.kitchenExcludedCategoryKeywords;

  /// Check if an item is a drink/bar item (should not go to kitchen)
  static bool _isDrinkItem(String itemName) {
    try {
      final decision = _resolveKitchenRoutingFromMenu(itemName);
      if (decision != null) {
        return !decision;
      }
    } catch (e) {
      developer.log('Error checking if item is drink: $e');
    }

    // Fall back to keyword-based detection for items missing from the menu cache
    return _matchesDrinkKeyword(itemName);
  }

  // Uses the stored menu configuration to determine if the item should go to kitchen.
  static bool? _resolveKitchenRoutingFromMenu(String itemName) {
    final normalizedName = itemName.trim().toLowerCase();
    if (normalizedName.isEmpty) {
      return null;
    }

    final categories = DatabaseService.getAllMenuCategories();
    for (final category in categories) {
      final bool? directMatch = _matchItemsForRouting(
        category.items,
        normalizedName,
        category.sendToKitchen,
      );
      if (directMatch != null) {
        return directMatch;
      }

      if (category.subcategories != null) {
        for (final subcategory in category.subcategories!) {
          final bool? subMatch = _matchItemsForRouting(
            subcategory.items,
            normalizedName,
            category.sendToKitchen,
          );
          if (subMatch != null) {
            return subMatch;
          }
        }
      }
    }

    return null;
  }

  static bool? _matchItemsForRouting(
    List<dynamic>? items,
    String normalizedName,
    bool categorySendsToKitchen,
  ) {
    if (items == null || items.isEmpty) {
      return null;
    }

    for (final item in items) {
      final itemNameKa = item.getName('ka').trim().toLowerCase();
      final itemNameEn = item.getName('en').trim().toLowerCase();

      if (_nameMatches(normalizedName, itemNameKa) ||
          _nameMatches(normalizedName, itemNameEn)) {
        final bool itemSends = (item.sendToKitchen as bool?) ?? true;
        return categorySendsToKitchen && itemSends;
      }
    }

    return null;
  }

  static bool _nameMatches(String normalizedName, String candidate) {
    if (candidate.isEmpty) {
      return false;
    }
    return normalizedName == candidate ||
        normalizedName.startsWith('$candidate ') ||
        normalizedName.startsWith('$candidate-') ||
        normalizedName.startsWith('$candidate(');
  }

  static bool _matchesDrinkKeyword(String itemName) {
    final normalized = itemName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _barCategoryKeywords.any(
      (keyword) => normalized.contains(keyword.toLowerCase()),
    );
  }

  /// Filter out drinks from items list (kitchen only needs food)
  static List<String> _filterKitchenItems(List<String> items) {
    return items.where((item) {
      // Extract item name from format "2x ItemName" or "ItemName"
      final namePart = item.contains('x ')
          ? item.substring(item.indexOf('x ') + 2)
          : item;
      return !_isDrinkItem(namePart);
    }).toList();
  }

  /// Print a kitchen check with order items (Georgian language)
  ///
  /// [items] List of items to print (e.g., ["2x Burger", "1x Fries"])
  /// [addedItems] Items that were added (for order modifications)
  /// [removedItems] Items that were removed (for order modifications)
  /// [tableNumber] Optional table number to display
  /// [orderNumber] Optional order number to display
  /// [waiterName] Waiter/Admin username who created the order
  /// [createdAt] Time when order was created
  ///
  /// Returns true if print was successful, false otherwise
  static Future<bool> printKitchenCheck({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
  }) async {
    return _printKitchenCheckLocal(
      items: items,
      addedItems: addedItems,
      removedItems: removedItems,
      tableNumber: tableNumber,
      orderNumber: orderNumber,
      waiterName: waiterName,
      createdAt: createdAt,
    );
  }

  static Future<bool> _printKitchenCheckLocal({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
  }) async {
    try {
      // Validate printer IP configuration
      if (_kitchenPrinterIp.isEmpty) {
        developer.log('Error: Kitchen printer IP not configured in settings');
        return false;
      }

      // Filter out drinks - they don't go to kitchen
      final kitchenItems = _filterKitchenItems(items);
      final kitchenAddedItems = addedItems != null
          ? _filterKitchenItems(addedItems)
          : null;
      final kitchenRemovedItems = removedItems != null
          ? _filterKitchenItems(removedItems)
          : null;

      // If no kitchen items to print, skip
      if (kitchenItems.isEmpty &&
          (kitchenAddedItems?.isEmpty ?? true) &&
          (kitchenRemovedItems?.isEmpty ?? true)) {
        developer.log('ℹ️ No kitchen items to print (only drinks)');
        return true; // Not an error, just nothing to print
      }

      // Generate ESC/POS commands for kitchen check
      final List<int> bytes = await _generateKitchenCheckBytes(
        items: kitchenItems,
        addedItems: kitchenAddedItems,
        removedItems: kitchenRemovedItems,
        tableNumber: tableNumber,
        orderNumber: orderNumber,
        waiterName: waiterName,
        createdAt: createdAt,
      );

      // Send to kitchen printer with retry logic
      final success = await _sendToPrinter(
        printerIp: _kitchenPrinterIp,
        port: _kitchenPrinterPort,
        bytes: bytes,
        printerName: 'Kitchen',
      );

      return success;
    } catch (e) {
      developer.log('Error printing kitchen check: $e');
      return false;
    }
  }

  /// Print a kitchen check in the background (non-blocking)
  ///
  /// This method returns immediately without waiting for the print to complete.
  /// Perfect for restaurant POS where you want instant UI response.
  ///
  /// The print job is queued and executed in a detached Future, so:
  /// - UI never freezes
  /// - No loading dialogs needed
  /// - Multiple prints are handled in order
  ///
  /// [items] List of items to print (e.g., ["2x Burger", "1x Fries"])
  /// [addedItems] Items that were added (for order modifications)
  /// [removedItems] Items that were removed (for order modifications)
  /// [tableNumber] Optional table number to display
  /// [orderNumber] Optional order number to display
  /// [waiterName] Waiter/Admin username who created the order
  /// [createdAt] Time when order was created
  /// [onComplete] Optional callback when print finishes (success or failure)
  static void printKitchenCheckInBackground({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    Function(bool success)? onComplete,
  }) {
    // Create a detached Future that doesn't block the caller
    final printJob = Future(() async {
      try {
        developer.log(
          '🖨️ Starting background kitchen print for order $orderNumber',
        );

        final success = await printKitchenCheck(
          items: items,
          addedItems: addedItems,
          removedItems: removedItems,
          tableNumber: tableNumber,
          orderNumber: orderNumber,
          waiterName: waiterName,
          createdAt: createdAt,
        );

        if (success) {
          developer.log(
            '✅ Kitchen check printed successfully for order $orderNumber',
          );
        } else {
          developer.log('❌ Kitchen check print failed for order $orderNumber');
        }

        // Call completion callback if provided
        onComplete?.call(success);

        return success;
      } catch (e) {
        developer.log('❌ Kitchen print error: $e');
        onComplete?.call(false);
        return false;
      }
    });

    // Add to queue for tracking (optional - helps with debugging)
    _printQueue.add(printJob);

    // Clean up completed jobs from queue
    _cleanupPrintQueue();
  }

  /// Print a receipt in the background (non-blocking)
  ///
  /// Similar to printKitchenCheckInBackground, but for customer receipts.
  /// Returns immediately without blocking UI.
  ///
  /// [items] List of items to print (e.g., ["Burger - 15.00", "Fries - 5.00"])
  /// [total] Total amount to display
  /// [subtotal] Subtotal before service fee
  /// [serviceFee] Service fee amount (10%)
  /// [includeServiceFee] Whether service fee is included
  /// [tableNumber] Optional table number to display
  /// [orderNumber] Optional order number to display
  /// [paymentMethod] Optional payment method (e.g., "Cash", "Card")
  /// [language] Language code ('ka' for Georgian, 'en' for English, defaults to 'ka')
  /// [onComplete] Optional callback when print finishes (success or failure)
  static void printReceiptInBackground({
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
    Function(bool success)? onComplete,
  }) {
    final printJob = Future(() async {
      try {
        developer.log(
          '🖨️ Starting background receipt print for order $orderNumber in language: $language',
        );

        final success = await printReceipt(
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
        );

        if (success) {
          developer.log(
            '✅ Receipt printed successfully for order $orderNumber',
          );
        } else {
          developer.log('❌ Receipt print failed for order $orderNumber');
        }

        onComplete?.call(success);
        return success;
      } catch (e) {
        developer.log('❌ Receipt print error: $e');
        onComplete?.call(false);
        return false;
      }
    });

    _printQueue.add(printJob);
    _cleanupPrintQueue();
  }

  /// Clean up completed print jobs from queue
  /// Keeps queue size manageable and prevents memory leaks
  static void _cleanupPrintQueue() {
    if (_isPrintQueueProcessing) return;

    _isPrintQueueProcessing = true;

    Future(() async {
      // Remove completed jobs
      _printQueue.removeWhere((job) {
        // Check if Future is complete by checking if it has a value/error
        bool isComplete = false;
        job.then((_) => isComplete = true).catchError((_) => isComplete = true);
        return isComplete;
      });

      _isPrintQueueProcessing = false;

      developer.log('📋 Print queue status: ${_printQueue.length} active jobs');
    });
  }

  /// Get the current number of pending print jobs
  /// Useful for debugging or showing queue status in UI
  static int getPendingPrintCount() {
    return _printQueue.length;
  }

  /// Print a customer receipt with items and total
  ///
  /// [items] List of items to print (e.g., ["Burger - 15.00", "Fries - 5.00"])
  /// [total] Total amount to display
  /// [subtotal] Subtotal before service fee
  /// [serviceFee] Service fee amount (10%)
  /// [includeServiceFee] Whether service fee is included
  /// [tableNumber] Optional table number to display
  /// [orderNumber] Optional order number to display
  /// [paymentMethod] Optional payment method (e.g., "Cash", "Card")
  /// [language] Language code ('ka' for Georgian, 'en' for English, defaults to 'ka')
  ///
  /// Returns true if print was successful, false otherwise
  static Future<bool> printReceipt({
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
  }) async {
    try {
      // Validate printer IP configuration
      if (_receiptPrinterIp.isEmpty) {
        developer.log('Error: Receipt printer IP not configured in settings');
        return false;
      }

      // Generate ESC/POS commands for receipt
      final List<int> bytes = await _generateReceiptBytes(
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
      );

      // Send to receipt printer with retry logic
      final success = await _sendToPrinter(
        printerIp: _receiptPrinterIp,
        port: _receiptPrinterPort,
        bytes: bytes,
        printerName: 'Receipt',
      );

      return success;
    } catch (e) {
      developer.log('Error printing receipt: $e');
      return false;
    }
  }

  /// Generate ESC/POS byte commands for kitchen check (Georgian language)
  ///
  /// Creates a lightweight bitmap image and prints it
  /// Optimized for fast printing with minimal data transfer
  static Future<List<int>> _generateKitchenCheckBytes({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
  }) async {
    List<int> bytes = [];

    // ESC/POS Commands
    const ESC = 0x1B;
    const GS = 0x1D;

    // Initialize printer
    bytes.addAll([ESC, 0x40]); // ESC @ - Initialize

    // Generate bitmap image of the kitchen check
    final imageBytes = await _generateKitchenCheckImage(
      items: items,
      addedItems: addedItems,
      removedItems: removedItems,
      tableNumber: tableNumber,
      orderNumber: orderNumber,
      waiterName: waiterName,
      createdAt: createdAt,
    );

    if (imageBytes != null) {
      // Print the bitmap image
      bytes.addAll(imageBytes);
    }

    // ✅ FIX: Add generous spacing before paper cut to prevent bottom text cutoff
    // Thermal printers need extra feed to ensure all content is visible above the tear line
    bytes.addAll([
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
    ]); // 6 line feeds (increased from 3)

    // Cut paper
    bytes.addAll([GS, 0x56, 0x00]); // GS V 0 - Full cut

    return bytes;
  }

  /// Generate a 1-bit bitmap image of the kitchen check
  /// ⚡ Optimized for minimal bytes and fast transmission
  static Future<List<int>?> _generateKitchenCheckImage({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
  }) async {
    try {
      // Create a custom painter for the kitchen check
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Paper width: 80mm = ~576 pixels at 72 DPI
      const double width = 576;

      // ✅ FIX: Start with top margin for better appearance
      double currentY = 20; // Top margin (increased from 10)

      // Background - white (with extra height for margins)
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, width, 2000), bgPaint);

      // 💡 OPTIMIZATION: Disable antialiasing for sharper text on thermal printers
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
        final operatorName = _resolveOperatorDisplayName(
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

      // ✅ FIX: Add generous bottom margin to prevent text cutoff
      // Thermal printers cut immediately after content ends
      currentY += 80; // Extra blank space before cut (increased from 20)

      // ✅ FIX: Ensure minimum height to avoid paper feed issues
      const double minHeight = 300; // Minimum receipt height
      final double finalHeight = currentY < minHeight ? minHeight : currentY;

      // Restore canvas layer
      canvas.restore();

      // Finish the picture with proper height
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), finalHeight.toInt());

      // ⚡ OPTIMIZATION: Skip PNG encode/decode - use raw RGBA directly
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
      return _convertToESCPOSBitmap(gray);
    } catch (e) {
      developer.log('Error generating kitchen check image: $e');
      return null;
    }
  }

  /// Convert image to ESC/POS bitmap format (1-bit)
  /// ⚡ Uses GS v 0 raster bitmap for line-by-line printing (no horizontal splitting)
  static List<int> _convertToESCPOSBitmap(imglib.Image image) {
    List<int> bytes = [];

    const GS = 0x1D;

    // Use GS v 0 command for printing raster bitmap.
    // For reliability on some printers, split long images into chunks.
    // GS v 0 m xL xH yL yH d1...dk

    final width = image.width;
    final height = image.height;

    // Width must be multiple of 8
    final widthBytes = (width + 7) ~/ 8;

    // Many 80mm thermal printers cut or ignore the tail of very tall raster
    // payloads, so chunk image height into safe slices.
    const int maxChunkHeight = 256;

    for (int startY = 0; startY < height; startY += maxChunkHeight) {
      final int chunkHeight = (startY + maxChunkHeight <= height)
          ? maxChunkHeight
          : height - startY;

      // GS v 0 command - raster bitmap mode
      bytes.addAll([GS, 0x76, 0x30, 0x00]); // GS v 0 m (m=0 normal)

      // Width in bytes (xL xH)
      bytes.add(widthBytes & 0xFF);
      bytes.add((widthBytes >> 8) & 0xFF);

      // Chunk height in dots (yL yH)
      bytes.add(chunkHeight & 0xFF);
      bytes.add((chunkHeight >> 8) & 0xFF);

      // Convert only this chunk to 1-bit bitmap data
      for (int y = startY; y < startY + chunkHeight; y++) {
        for (int x = 0; x < widthBytes; x++) {
          int byte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final int px = x * 8 + bit;
            if (px < width) {
              final pixel = image.getPixel(px, y);
              final r = pixel.r.toInt();
              final g = pixel.g.toInt();
              final b = pixel.b.toInt();
              final luminance = (0.299 * r + 0.587 * g + 0.114 * b).toInt();

              // Threshold: darker than 128 is printed black.
              if (luminance < 128) {
                byte |= (1 << (7 - bit));
              }
            }
          }
          bytes.add(byte);
        }
      }
    }

    return bytes;
  }

  /// Generate ESC/POS byte commands for customer receipt
  ///
  /// Creates a lightweight bitmap image and prints it (supports Georgian text)
  static Future<List<int>> _generateReceiptBytes({
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
  }) async {
    List<int> bytes = [];

    // ESC/POS Commands
    const ESC = 0x1B;
    const GS = 0x1D;

    // Initialize printer
    bytes.addAll([ESC, 0x40]); // ESC @ - Initialize

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
    );

    if (imageBytes != null) {
      // Print the bitmap image
      bytes.addAll(imageBytes);
    }

    // Add spacing before paper cut
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 6 line feeds

    // Cut paper
    bytes.addAll([GS, 0x56, 0x00]); // GS V 0 - Full cut

    return bytes;
  }

  /// Generate a 1-bit bitmap image of the receipt
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

      final logoImage = await _loadReceiptLogoImage();
      if (logoImage != null) {
        // Fit into requested bounds without cropping.
        const maxLogoWidth = 384.0;
        const maxLogoHeight = 120.0;
        final srcRect = await _getReceiptLogoContentRect(logoImage);
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
      return _convertToESCPOSBitmap(gray);
    } catch (e) {
      developer.log('Error generating receipt image: $e');
      return null;
    }
  }

  static Future<Uint8List?> generateReceiptPngBytes({
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
      );
      if (img == null) return null;

      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      developer.log('Error generating receipt PNG: $e');
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

  static String _resolveOperatorDisplayName(
    String rawName, {
    required bool isEnglish,
  }) {
    final normalizedName = rawName.trim();
    if (normalizedName.isEmpty || normalizedName == '-') {
      return '-';
    }

    if (_isAdminOperatorName(normalizedName)) {
      return isEnglish ? 'System' : 'სისტემა';
    }

    return normalizedName;
  }

  static bool _isAdminOperatorName(String rawName) {
    final normalized = rawName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final users = DatabaseService.getAllUsers();
      final isKnownAdmin = users.any((user) {
        return user.isAdmin && user.username.trim().toLowerCase() == normalized;
      });
      if (isKnownAdmin) {
        return true;
      }
    } catch (_) {
      // Fall back to alias-based detection when users are unavailable.
    }

    const adminAliases = {
      'admin',
      'administrator',
      'superadmin',
      'ადმინი',
      'ადმინისტრატორი',
    };

    if (adminAliases.contains(normalized)) {
      return true;
    }

    return normalized.startsWith('admin ') || normalized.startsWith('ადმინ ');
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

  /// Send byte data to printer via persistent connection or fallback to raw TCP
  ///
  /// [printerIp] IP address of the printer
  /// [port] Port number (typically 9100 for ESC/POS)
  /// [bytes] ESC/POS command bytes to send
  /// [printerName] Name for logging purposes
  ///
  /// First attempts to use persistent connection for instant printing
  /// Falls back to traditional connection method if persistent connection fails
  /// Returns true if successful, false otherwise
  static Future<bool> _sendToPrinter({
    required String printerIp,
    required int port,
    required List<int> bytes,
    required String printerName,
  }) async {
    // Try persistent connection first (instant, no handshake delay)
    if (_isInitialized) {
      final manager = PrinterConnectionManager.instance;
      PrinterConnection? connection;

      // Get the appropriate printer connection
      if (printerName == 'Kitchen') {
        connection = manager.kitchenPrinter;
      } else if (printerName == 'Receipt') {
        connection = manager.receiptPrinter;
      }

      // Attempt to send via persistent connection
      if (connection != null) {
        developer.log(
          '[$printerName Printer] Using persistent connection to $printerIp:$port',
        );
        final success = await connection.send(Uint8List.fromList(bytes));
        if (success) {
          return true;
        }
        developer.log(
          '⚠️ [$printerName Printer] Persistent connection failed, falling back to traditional method',
        );
      }
    }

    // Fallback: Traditional connection method with retry logic
    developer.log('[$printerName Printer] Using fallback connection method');
    int attempt = 0;

    // Retry loop - attempt up to maxRetries + 1 times
    while (attempt <= _maxRetries) {
      Socket? socket;

      try {
        // Establish raw TCP socket connection to printer
        socket = await Socket.connect(
          printerIp,
          port,
          timeout: _connectionTimeout,
        );

        developer.log('[$printerName Printer] Connected successfully');

        // Send ESC/POS command bytes to printer
        socket.add(bytes);

        // Ensure all data is sent before closing
        await socket.flush();

        developer.log(
          '[$printerName Printer] Data sent successfully (${bytes.length} bytes)',
        );

        // Close the socket connection
        await socket.close();

        // Print successful
        return true;
      } on SocketException catch (e) {
        // Network-related errors (connection refused, timeout, etc.)
        developer.log(
          '[$printerName Printer] Socket error on attempt ${attempt + 1}: ${e.message}',
        );

        // Close socket if it was opened
        try {
          await socket?.close();
        } catch (_) {}
      } catch (e) {
        // Any other unexpected errors (including timeouts)
        developer.log(
          '[$printerName Printer] Error on attempt ${attempt + 1}: $e',
        );

        // Close socket if it was opened
        try {
          await socket?.close();
        } catch (_) {}
      }

      // Increment attempt counter
      attempt++;

      // Wait before retrying (exponential backoff)
      if (attempt <= _maxRetries) {
        final waitTime = Duration(milliseconds: 500 * attempt);
        developer.log(
          '[$printerName Printer] Waiting ${waitTime.inMilliseconds}ms before retry...',
        );
        await Future.delayed(waitTime);
      }
    }

    // All retry attempts failed
    developer.log(
      '[$printerName Printer] Failed after ${_maxRetries + 1} attempts',
    );
    return false;
  }

  /// Test connection to both printers
  ///
  /// Useful for diagnostic purposes
  /// Returns a map with connection status for each printer
  static Future<Map<String, bool>> testConnections({
    String? kitchenIp,
    String? receiptIp,
    int? port,
    int? kitchenPort,
    int? receiptPort,
  }) async {
    final results = <String, bool>{};
    final effectiveKitchenPort = kitchenPort ?? port ?? _kitchenPrinterPort;
    final effectiveReceiptPort = receiptPort ?? port ?? _receiptPrinterPort;
    final effectiveKitchenIp = (kitchenIp ?? _kitchenPrinterIp).trim();
    final effectiveReceiptIp = (receiptIp ?? _receiptPrinterIp).trim();

    if (effectiveKitchenIp.isEmpty) {
      results['kitchen'] = false;
    } else {
      Socket? kitchenSocket;
      try {
        kitchenSocket = await Socket.connect(
          effectiveKitchenIp,
          effectiveKitchenPort,
          timeout: _connectionTimeout,
        );
        results['kitchen'] = true;
        await kitchenSocket.close();
      } catch (e) {
        developer.log('Kitchen printer connection test failed: $e');
        results['kitchen'] = false;
      }
    }

    if (effectiveReceiptIp.isEmpty) {
      results['receipt'] = false;
    } else {
      Socket? receiptSocket;
      try {
        receiptSocket = await Socket.connect(
          effectiveReceiptIp,
          effectiveReceiptPort,
          timeout: _connectionTimeout,
        );
        results['receipt'] = true;
        await receiptSocket.close();
      } catch (e) {
        developer.log('Receipt printer connection test failed: $e');
        results['receipt'] = false;
      }
    }

    return results;
  }

  /// Print raw text report (X Report, Z Report, etc.) as bitmap image
  static Future<bool> printTextReport(
    String reportText, {
    String reportType = 'X REPORT',
  }) async {
    try {
      // Validate printer IP configuration
      if (_receiptPrinterIp.isEmpty) {
        developer.log('Error: Receipt printer IP not configured in settings');
        return false;
      }

      // Generate ESC/POS commands for text report
      final List<int> bytes = [];

      // ESC/POS Commands
      const ESC = 0x1B;
      const GS = 0x1D;

      // Initialize printer
      bytes.addAll([ESC, 0x40]); // ESC @ - Initialize

      // Generate bitmap image of the report
      final imageBytes = await _generateReportImage(
        reportText: reportText,
        reportType: reportType,
      );

      if (imageBytes != null) {
        // Print the bitmap image
        bytes.addAll(imageBytes);
      }

      // Add extra line feeds and cut
      bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // Extra line feeds
      bytes.addAll([GS, 0x56, 0x00]); // GS V 0 - Full cut

      // Send to receipt printer
      final success = await _sendToPrinter(
        printerIp: _receiptPrinterIp,
        port: _printerPort,
        bytes: bytes,
        printerName: 'Receipt',
      );

      return success;
    } catch (e) {
      developer.log('Error printing text report: $e');
      return false;
    }
  }

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

  /// Generate a 1-bit bitmap image of the report
  static Future<List<int>?> _generateReportImage({
    required String reportText,
    required String reportType,
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

      final logoImage = await _loadReceiptLogoImage();
      if (logoImage != null) {
        const maxLogoWidth = 360.0;
        const maxLogoHeight = 108.0;
        final srcRect = await _getReceiptLogoContentRect(logoImage);
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
      return _convertToESCPOSBitmap(gray);
    } catch (e) {
      developer.log('Error generating report image: $e');
      return null;
    }
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
