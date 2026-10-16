import 'dart:ui' as ui;
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../edge/edge_device_credential_store.dart';
import 'print_job.dart';
import 'print_reconciliation.dart';
import '../../database/local_data_admission.dart';
import '../../database/repositories/print_job_repository.dart';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../models/receipt_header_layout.dart';
import '../database_service.dart';
import 'escpos_kitchen_renderer.dart';
import 'escpos_receipt_renderer.dart';
import 'escpos_report_renderer.dart';
import 'kitchen_print_filter.dart';
import 'print_queue.dart';
import 'printer_transport.dart';
import 'local_printer_catalog.dart';
import 'printer_destination.dart';
import 'printer_capability_profile.dart';

/// Durable, capability-configured printing over TCP or Windows RAW queues.
class PrinterService {
  static PrinterRoute? _route(PrinterRole role) {
    final matching = LocalPrinterCatalog.readRoutesForDispatch(role: role);
    if (matching.length > 1)
      throw StateError('Printer role has multiple destinations');
    return matching.isEmpty ? null : matching.single;
  }

  @visibleForTesting
  static Future<List<int>> Function()? renderBytesOverride;

  // Printer configuration (overridable via settings)
  static String get _kitchenPrinterIp => DatabaseService.getKitchenPrinterIp();
  static String get _receiptPrinterIp => DatabaseService.getReceiptPrinterIp();
  static int get _kitchenPrinterPort => DatabaseService.getKitchenPrinterPort();
  static int get _receiptPrinterPort => DatabaseService.getReceiptPrinterPort();

  // Persistent printer connections
  static ui.Image? _cachedReceiptLogo;
  static Rect? _cachedReceiptLogoContentRect;

  /// Reads the admin "show the service-fee row" receipt setting.
  ///
  /// Display only: the fee stays inside the printed total either way. Read
  /// here — the single choke point every receipt passes through — rather than
  /// at each of the ~13 call sites. Falls back to showing the row wherever the
  /// settings box is unavailable (e.g. the mobile app, which never
  /// initializes it), preserving today's behavior.
  static bool _shouldShowServiceFeeLine() {
    try {
      return DatabaseService.isReceiptServiceFeeLineVisible();
    } catch (e) {
      developer.log('Receipt service-fee display setting unavailable: $e');
      return true;
    }
  }

  /// The closing (fiscal) check's own switch. Defaults to hidden, which is how
  /// the closing check has always printed.
  static bool _shouldShowCloseReceiptServiceFeeLine() {
    try {
      return DatabaseService.isCloseReceiptServiceFeeLineVisible();
    } catch (e) {
      developer.log('Close-receipt service-fee setting unavailable: $e');
      return false;
    }
  }

  /// The venue's own logo, from the database.
  ///
  /// It used to come from `assets/black-logo.png`, bundled in the binary, so
  /// every venue printed the same mark on their checks. A venue that has not
  /// uploaded one gets no logo at all and the name is printed instead — which
  /// is the honest result, rather than someone else's brand.
  ///
  /// [clearReceiptLogoCache] must be called when the setting changes; the
  /// decoded image is held for the life of the process otherwise.
  static Future<ui.Image?> _loadReceiptLogoImage() async {
    if (_cachedReceiptLogo != null) {
      return _cachedReceiptLogo;
    }

    final stored = _venueLogoBytes();
    if (stored == null) return null;

    try {
      final codec = await ui.instantiateImageCodec(stored);
      final frame = await codec.getNextFrame();
      _cachedReceiptLogo = frame.image;
      _cachedReceiptLogoContentRect = null;
      return _cachedReceiptLogo;
    } catch (e) {
      developer.log('Stored receipt logo could not be decoded: $e');
      return null;
    }
  }

  static Uint8List? _venueLogoBytes() {
    try {
      return DatabaseService.getVenueLogoPng();
    } catch (e) {
      developer.log('Venue logo unavailable: $e');
      return null;
    }
  }

  /// Drops the decoded logo so the next receipt picks up a new upload.
  static void clearReceiptLogoCache() {
    _cachedReceiptLogo = null;
    _cachedReceiptLogoContentRect = null;
  }

  /// What the top of a receipt says this venue is.
  ///
  /// Name, street and phone were three string literals in three renderers —
  /// „RESTAURANT VANKISI", „ალექსანდრე პუშკინის ქ. N51",
  /// „+995 599 98 93 76" — printed on the checks of every venue that installed
  /// this POS. Empty lines are dropped rather than printed blank.
  /// Where the mark and the words go at the top of the check.
  static ReceiptHeaderLayout receiptHeaderLayout() {
    try {
      return DatabaseService.getReceiptHeaderLayout();
    } catch (e) {
      developer.log('Receipt header layout unavailable: $e');
      return const ReceiptHeaderLayout();
    }
  }

  static ({String name, String address, String phone}) venueHeader() {
    try {
      return (
        name: DatabaseService.getVenueName(),
        address: DatabaseService.getVenueAddress(),
        phone: DatabaseService.getVenuePhone(),
      );
    } catch (e) {
      developer.log('Venue header unavailable: $e');
      return (name: '', address: '', phone: '');
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

  /// Start the durable worker. Accepted jobs keep their frozen destination.
  static Future<void> initialize({bool forceReconnect = false}) async {
    PrintQueue.start();
  }

  static void dispose() => PrintQueue.stop();

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
  /// True means the configured transport accepted the bytes; physical paper
  /// output still requires operator observation.
  static Future<bool> printKitchenCheck({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    String? jobId,
    String? requiresConfirmedOrderUuid,
    String? copyOf,
    String? copyReason,
    bool waitForDelivery = true,
    void Function(bool)? onComplete,
  }) => _printKitchenCheckLocal(
    items: List.of(items),
    addedItems: addedItems == null ? null : List.of(addedItems),
    removedItems: removedItems == null ? null : List.of(removedItems),
    tableNumber: tableNumber,
    orderNumber: orderNumber,
    waiterName: waiterName,
    createdAt: createdAt,
    jobId: jobId,
    requiresConfirmedOrderUuid: requiresConfirmedOrderUuid,
    copyOf: copyOf,
    copyReason: copyReason,
    waitForDelivery: waitForDelivery,
    onComplete: onComplete,
  );

  static Future<bool> _printKitchenCheckLocal({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    String? jobId,
    String? requiresConfirmedOrderUuid,
    String? copyOf,
    String? copyReason,
    required bool waitForDelivery,
    void Function(bool)? onComplete,
  }) async {
    try {
      final capturedVenue = EdgeDeviceCredentialStore.venueId;
      final route = _route(PrinterRole.kitchen);
      final host =
          route?.destination.host ??
          route?.destination.queueName ??
          _kitchenPrinterIp;
      final port = route == null
          ? _kitchenPrinterPort
          : route.destination.port ?? 0;
      // Validate printer IP configuration
      if (host.isEmpty) {
        developer.log('Error: Kitchen printer IP not configured in settings');
        onComplete?.call(false);
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
        onComplete?.call(true);
        return true; // No kitchen-bound work
      }

      // Generate ESC/POS commands for kitchen check
      final List<int> bytes = renderBytesOverride != null
          ? await renderBytesOverride!()
          : await EscposKitchenRenderer.generateBytes(
              items: kitchenItems,
              addedItems: kitchenAddedItems,
              removedItems: kitchenRemovedItems,
              tableNumber: tableNumber,
              orderNumber: orderNumber,
              waiterName: waiterName,
              createdAt: createdAt,
              resolveOperatorDisplayName: _resolveOperatorDisplayName,
              capabilityProfile: route?.capabilityProfile,
            );

      // Flush durable admission before transport
      final success = await _queueBytes(
        host,
        port,
        bytes,
        target: PrintQueueTarget.kitchen,
        route: route,
        venueId: capturedVenue,
        label: 'Kitchen / ${orderNumber ?? tableNumber ?? 'ticket'}',
        jobId: jobId,
        requiresConfirmedOrderUuid: requiresConfirmedOrderUuid,
        copyOf: copyOf,
        copyReason: copyReason,
        waitForDelivery: waitForDelivery,
        onComplete: onComplete,
      );

      return success;
    } catch (e) {
      developer.log('Kitchen print admission failed: $e');
      onComplete?.call(false);
      return false;
    }
  }

  /// Returns only after frozen bytes/destination are flushed to Hive.
  static Future<bool> printKitchenCheckInBackground({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    String? jobId,
    String? requiresConfirmedOrderUuid,
    String? initialOrderUuid,
    String? copyOf,
    String? copyReason,
    void Function(bool)? onComplete,
  }) => _admitKitchenBackground(
    initialOrderUuid: initialOrderUuid,
    items: List.of(items),
    addedItems: addedItems == null ? null : List.of(addedItems),
    removedItems: removedItems == null ? null : List.of(removedItems),
    tableNumber: tableNumber,
    orderNumber: orderNumber,
    waiterName: waiterName,
    createdAt: createdAt,
    jobId: jobId,
    requiresConfirmedOrderUuid: requiresConfirmedOrderUuid,
    copyOf: copyOf,
    copyReason: copyReason,
    onComplete: onComplete,
  );

  static Future<bool> _admitKitchenBackground({
    required List<String> items,
    List<String>? addedItems,
    List<String>? removedItems,
    String? tableNumber,
    String? orderNumber,
    String? waiterName,
    DateTime? createdAt,
    String? jobId,
    String? requiresConfirmedOrderUuid,
    String? initialOrderUuid,
    String? copyOf,
    String? copyReason,
    void Function(bool)? onComplete,
  }) => LocalDataAdmission.mutate(() async {
    if (initialOrderUuid != null) {
      if (jobId != null ||
          copyOf != null ||
          addedItems != null ||
          removedItems != null) {
        throw ArgumentError(
          'Initial kitchen identity cannot be used for copies or item changes',
        );
      }
      jobId = 'kitchen-initial-$initialOrderUuid';
      final existing = PrintJobRepository.read(jobId!);
      if (existing != null) {
        // This names one creation/confirmation event. Later Order, settings,
        // menu and clock changes cannot recreate its original paper payload.
        await PrintQueue.enqueue(existing, onComplete: onComplete);
        return true;
      }
    }
    return printKitchenCheck(
      items: items,
      addedItems: addedItems,
      removedItems: removedItems,
      tableNumber: tableNumber,
      orderNumber: orderNumber,
      waiterName: waiterName,
      createdAt: createdAt,
      jobId: jobId,
      requiresConfirmedOrderUuid: requiresConfirmedOrderUuid,
      copyOf: copyOf,
      copyReason: copyReason,
      waitForDelivery: false,
      onComplete: onComplete,
    );
  });

  /// Returns durable admission; the callback reports transport acceptance.
  static Future<bool> printReceiptInBackground({
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
    String? jobId,
    String? copyOf,
    String? copyReason,
    void Function(bool)? onComplete,
  }) => printReceipt(
    items: List.of(items),
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
    jobId: jobId,
    copyOf: copyOf,
    copyReason: copyReason,
    waitForDelivery: false,
    onComplete: onComplete,
  );

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
  /// Returns transport acceptance, which does not confirm physical paper output.
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
    String? jobId,
    String? copyOf,
    String? copyReason,
    bool waitForDelivery = true,
    void Function(bool)? onComplete,
  }) async {
    try {
      items = List.of(items);
      final capturedVenue = EdgeDeviceCredentialStore.venueId;
      final route = _route(PrinterRole.receipt);
      final host =
          route?.destination.host ??
          route?.destination.queueName ??
          _receiptPrinterIp;
      final port = route == null
          ? _receiptPrinterPort
          : route.destination.port ?? 0;
      // Validate printer IP configuration
      if (host.isEmpty) {
        developer.log('Error: Receipt printer IP not configured in settings');
        onComplete?.call(false);
        return false;
      }

      // Generate ESC/POS commands for receipt.
      // Display-only admin setting: hides the separate service-fee row while
      // leaving the printed total untouched.
      final List<int> bytes = renderBytesOverride != null
          ? await renderBytesOverride!()
          : await EscposReceiptRenderer.generateBytes(
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
              showServiceFeeLine: _shouldShowServiceFeeLine(),
              showCloseReceiptServiceFeeLine:
                  _shouldShowCloseReceiptServiceFeeLine(),
              loadReceiptLogoImage: _loadReceiptLogoImage,
              venue: venueHeader(),
              layout: receiptHeaderLayout(),
              getReceiptLogoContentRect: _getReceiptLogoContentRect,
              capabilityProfile: route?.capabilityProfile,
            );

      // Flush durable admission before transport
      final success = await _queueBytes(
        host,
        port,
        bytes,
        target: PrintQueueTarget.receipt,
        route: route,
        venueId: capturedVenue,
        label: 'Receipt / ${orderNumber ?? receiptType ?? 'ticket'}',
        jobId: jobId,
        copyOf: copyOf,
        copyReason: copyReason,
        waitForDelivery: waitForDelivery,
        onComplete: onComplete,
      );

      return success;
    } catch (e) {
      developer.log('Receipt print admission failed: $e');
      onComplete?.call(false);
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
      showServiceFeeLine: _shouldShowServiceFeeLine(),
      showCloseReceiptServiceFeeLine: _shouldShowCloseReceiptServiceFeeLine(),
      loadReceiptLogoImage: _loadReceiptLogoImage,
      venue: venueHeader(),
      layout: receiptHeaderLayout(),
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

  static Future<bool> _queueBytes(
    String host,
    int port,
    List<int> bytes, {
    required PrintQueueTarget target,
    PrinterRoute? route,
    required String? venueId,
    String? requiresConfirmedOrderUuid,
    required String label,
    String? jobId,
    String? copyOf,
    String? copyReason,
    bool waitForDelivery = true,
    void Function(bool)? onComplete,
  }) async {
    final completion = Completer<bool>();
    await LocalDataAdmission.mutate(() async {
      if ((copyOf == null) != (copyReason == null)) {
        throw ArgumentError('Copy source and reason must be supplied together');
      }
      final actor = copyReason == null
          ? null
          : target == PrintQueueTarget.kitchen
          ? PrintReconciliation.authorizeKitchenCopy()
          : PrintReconciliation.authorizeCopy(copyReason);
      await PrintQueue.enqueue(
        PrintJob.create(
          id: jobId ?? const Uuid().v4(),
          target: target,
          host: host,
          port: port,
          destination: route?.destination,
          printerId: route?.id,
          routeRevision: route?.revision,
          capabilityProfile: route?.capabilityProfile,
          label: label,
          bytes: bytes,
          venueId: venueId,
          requiresConfirmedOrderUuid: requiresConfirmedOrderUuid,
          copyOf: copyOf,
          copyActorId: actor?.username,
          copyReason: copyReason == null
              ? null
              : target == PrintQueueTarget.kitchen
              ? PrintReconciliation.kitchenCopyReason
              : copyReason.trim(),
        ),
        onComplete: (sent) {
          if (!completion.isCompleted) completion.complete(sent);
          onComplete?.call(sent);
        },
      );
    });
    return waitForDelivery ? completion.future : true;
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
      final capturedVenue = EdgeDeviceCredentialStore.venueId;
      final route = _route(PrinterRole.receipt);
      final host =
          route?.destination.host ??
          route?.destination.queueName ??
          _receiptPrinterIp;
      final port = route == null
          ? _receiptPrinterPort
          : route.destination.port ?? 0;
      // Validate printer IP configuration
      if (host.isEmpty) {
        developer.log('Error: Receipt printer IP not configured in settings');
        return false;
      }

      final profile =
          route?.capabilityProfile ??
          PrinterCapabilityProfile.genericEscposRaster(
            cutter: PrinterCutter.full,
          );
      if (!profile.hasImplementedRenderer) {
        throw UnsupportedError(
          'Printer command language has no implemented renderer',
        );
      }
      final List<int> bytes;
      if (renderBytesOverride != null) {
        final raster = await renderBytesOverride!();
        if (raster.isEmpty)
          throw StateError('Required report raster could not be rendered');
        bytes = [
          0x1b,
          0x40,
          ...raster,
          0x0a,
          0x0a,
          0x0a,
          0x0a,
          0x0a,
          0x0a,
          ...switch (profile.cutter) {
            PrinterCutter.none => <int>[],
            PrinterCutter.full => [0x1d, 0x56, 0],
            PrinterCutter.partial => [0x1d, 0x56, 1],
          },
        ];
      } else {
        bytes = await EscposReportRenderer.generateBytes(
          reportText: reportText,
          reportType: reportType,
          loadReceiptLogoImage: _loadReceiptLogoImage,
          venue: venueHeader(),
          getReceiptLogoContentRect: _getReceiptLogoContentRect,
          capabilityProfile: profile,
        );
      }

      // Send to receipt printer
      final success = await _queueBytes(
        host,
        port,
        bytes,
        target: PrintQueueTarget.receipt,
        route: route,
        venueId: capturedVenue,
        label: 'Report / $reportType',
      );

      return success;
    } catch (e) {
      developer.log('Error printing text report: $e');
      return false;
    }
  }
}
