import 'dart:ui' as ui;
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import '../database_service.dart';
import 'escpos_kitchen_renderer.dart';
import 'escpos_receipt_renderer.dart';
import 'escpos_report_renderer.dart';
import 'kitchen_print_filter.dart';
import 'print_queue.dart';
import 'printer_transport.dart';
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
      final kitchenItems = KitchenPrintFilter.filterItems(items);
      final kitchenAddedItems = addedItems != null
          ? KitchenPrintFilter.filterItems(addedItems)
          : null;
      final kitchenRemovedItems = removedItems != null
          ? KitchenPrintFilter.filterItems(removedItems)
          : null;

      // If no kitchen items to print, skip
      if (kitchenItems.isEmpty &&
          (kitchenAddedItems?.isEmpty ?? true) &&
          (kitchenRemovedItems?.isEmpty ?? true)) {
        developer.log('ℹ️ No kitchen items to print (only drinks)');
        return true; // Not an error, just nothing to print
      }

      // Generate ESC/POS commands for kitchen check
      final List<int> bytes = await EscposKitchenRenderer.generateBytes(
        items: kitchenItems,
        addedItems: kitchenAddedItems,
        removedItems: kitchenRemovedItems,
        tableNumber: tableNumber,
        orderNumber: orderNumber,
        waiterName: waiterName,
        createdAt: createdAt,
        resolveOperatorDisplayName: _resolveOperatorDisplayName,
      );

      // Send to kitchen printer with retry logic
      final success = await _sendToPrinter(
        _kitchenPrinterIp,
        _kitchenPrinterPort,
        bytes,
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
    PrintQueue.enqueue(
      target: PrintQueueTarget.kitchen,
      debugLabel: 'background kitchen print for order $orderNumber',
      onComplete: onComplete,
      job: () async {
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
            developer.log(
              '❌ Kitchen check print failed for order $orderNumber',
            );
          }

          return success;
        } catch (e) {
          developer.log('❌ Kitchen print error: $e');
          return false;
        }
      },
    );
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
    PrintQueue.enqueue(
      target: PrintQueueTarget.receipt,
      debugLabel: 'background receipt print for order $orderNumber',
      onComplete: onComplete,
      job: () async {
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

          return success;
        } catch (e) {
          developer.log('❌ Receipt print error: $e');
          return false;
        }
      },
    );
  }

  /// Get the current number of pending print jobs
  /// Useful for debugging or showing queue status in UI
  static int getPendingPrintCount() {
    return PrintQueue.pendingCount;
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
      final List<int> bytes = await EscposReceiptRenderer.generateBytes(
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
        loadReceiptLogoImage: _loadReceiptLogoImage,
        getReceiptLogoContentRect: _getReceiptLogoContentRect,
      );

      // Send to receipt printer with retry logic
      final success = await _sendToPrinter(
        _receiptPrinterIp,
        _receiptPrinterPort,
        bytes,
        printerName: 'Receipt',
      );

      return success;
    } catch (e) {
      developer.log('Error printing receipt: $e');
      return false;
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
    return EscposReceiptRenderer.generatePngBytes(
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
      loadReceiptLogoImage: _loadReceiptLogoImage,
      getReceiptLogoContentRect: _getReceiptLogoContentRect,
    );
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
  static Future<bool> _sendToPrinter(
    String printerIp,
    int port,
    List<int> bytes, {
    String printerName = 'Printer',
  }) {
    return PrinterTransport.sendToPrinter(
      printerIp: printerIp,
      port: port,
      bytes: bytes,
      printerName: printerName,
      usePersistentConnection: _isInitialized,
    );
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
    final effectiveKitchenPort = kitchenPort ?? port ?? _kitchenPrinterPort;
    final effectiveReceiptPort = receiptPort ?? port ?? _receiptPrinterPort;
    final effectiveKitchenIp = (kitchenIp ?? _kitchenPrinterIp).trim();
    final effectiveReceiptIp = (receiptIp ?? _receiptPrinterIp).trim();

    return PrinterTransport.testConnections(
      kitchenIp: effectiveKitchenIp,
      receiptIp: effectiveReceiptIp,
      kitchenPort: effectiveKitchenPort,
      receiptPort: effectiveReceiptPort,
    );
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
      final imageBytes = await EscposReportRenderer.generateImage(
        reportText: reportText,
        reportType: reportType,
        loadReceiptLogoImage: _loadReceiptLogoImage,
        getReceiptLogoContentRect: _getReceiptLogoContentRect,
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
        _receiptPrinterIp,
        _printerPort,
        bytes,
        printerName: 'Receipt',
      );

      return success;
    } catch (e) {
      developer.log('Error printing text report: $e');
      return false;
    }
  }
}
