import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';

class ReceiptPdfGenerator {
  ReceiptPdfGenerator._();

  /// Same admin setting the ESC/POS receipts honor. Falls back to showing the
  /// row wherever the settings box is unavailable.
  static bool _resolveShowServiceFeeLine() {
    try {
      return DatabaseService.isReceiptServiceFeeLineVisible();
    } catch (_) {
      return true;
    }
  }

  /// Generates a PDF receipt for [order].
  ///
  /// [showServiceFeeLine] mirrors the POS receipts: when omitted it follows
  /// the admin "show the service-fee row" setting. Display only — the totals
  /// below are unaffected either way.
  static Future<File> generateOrderReceipt({
    required Order order,
    String language = 'ka',
    bool? showServiceFeeLine,
  }) async {
    final isEnglish = language == 'en';
    final showFeeRow = showServiceFeeLine ?? _resolveShowServiceFeeLine();
    final pdf = pw.Document();

    // Load fonts and logo
    final fontData = await rootBundle.load('assets/fonts/NotoSansGeorgian.ttf');
    final font = pw.Font.ttf(fontData);

    // The venue's own logo, from the database. It used to be
    // `assets/black-logo.png`, bundled in the binary, so every venue's PDF
    // receipt carried the same mark.
    final logoBytes = DatabaseService.getVenueLogoPng();
    final logoImage = logoBytes == null ? null : pw.MemoryImage(logoBytes);
    final venueName = DatabaseService.getVenueName();
    final venueAddress = DatabaseService.getVenueAddress();
    final venuePhone = DatabaseService.getVenuePhone();

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(now);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header: whatever the venue has filled in. A line it has not
              // set is skipped rather than printed blank.
              if (logoImage != null) ...[
                pw.Center(child: pw.Image(logoImage, width: 120, height: 60)),
                pw.SizedBox(height: 8),
              ],
              if (venueName.isNotEmpty)
                pw.Text(
                  venueName,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (venueAddress.isNotEmpty)
                pw.Text(venueAddress, style: const pw.TextStyle(fontSize: 9)),
              if (venuePhone.isNotEmpty)
                pw.Text(venuePhone, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 12),

              pw.Divider(thickness: 0.5),

              // Order Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Order #${order.orderId}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Table: ${order.tableNumbers.join(", ")}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Waiter: ${order.createdBy}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(dateStr, style: const pw.TextStyle(fontSize: 8)),
                ],
              ),

              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),

              // Items Table Header
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      isEnglish ? 'Item' : 'დასახელება',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      isEnglish ? 'Qty' : 'რაოდ.',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      isEnglish ? 'Price' : 'ფასი',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      isEnglish ? 'Total' : 'ჯამი',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.2),
              pw.SizedBox(height: 4),

              // Package (if any)
              if (order.packageId != null && order.packageId!.isNotEmpty) ...[
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(
                        order.packageName ?? 'Package',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 1,
                      child: pw.Text(
                        '${order.packageGuestCount}',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Expanded(
                      flex: 1,
                      child: pw.Text(
                        '${order.packageUnitPrice.toStringAsFixed(2)}',
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Expanded(
                      flex: 1,
                      child: pw.Text(
                        '${order.packagePrice.toStringAsFixed(2)}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
              ],

              // Additional Items
              ...order.items.where((item) => item.quantity > 0).map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          item.itemName,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          '${item.quantity}',
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          item.unitPrice.toStringAsFixed(2),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          item.total.toStringAsFixed(2),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),

              // Totals
              _buildTotalRow(
                isEnglish ? 'Subtotal' : 'ქვეჯამი',
                '${(order.getAdditionalItemsSubtotal() + order.packagePrice).toStringAsFixed(2)} GEL',
                fontSize: 9,
              ),

              if (showFeeRow &&
                  order.includeServiceFee &&
                  order.getServiceFee() > 0)
                _buildTotalRow(
                  '${isEnglish ? "Service" : "სერვისი"} (${(order.getEffectiveServiceFeePercentage()).toStringAsFixed(0)}%)',
                  '${order.getServiceFee().toStringAsFixed(2)} GEL',
                  fontSize: 9,
                ),

              if (order.discountAmount > 0)
                _buildTotalRow(
                  isEnglish ? 'Discount' : 'ფასდაკლება',
                  '-${order.discountAmount.toStringAsFixed(2)} GEL',
                  fontSize: 9,
                ),

              if (order.manualAdjustmentAmount != 0)
                _buildTotalRow(
                  isEnglish ? 'Adjustment' : 'კორექცია',
                  '${order.manualAdjustmentAmount > 0 ? "+" : ""}${order.manualAdjustmentAmount.toStringAsFixed(2)} GEL',
                  fontSize: 9,
                ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 4),

              _buildTotalRow(
                isEnglish ? 'TOTAL' : 'სულ',
                '${order.totalAmount.toStringAsFixed(2)} GEL',
                fontSize: 12,
                isBold: true,
              ),

              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text(
                  isEnglish
                      ? 'Thank you for visiting!'
                      : 'მადლობა სტუმრობისთვის!',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  isEnglish ? 'See you again!' : 'გელოდებით კვლავ!',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/receipt_${order.orderId}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildTotalRow(
    String label,
    String value, {
    required double fontSize,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
