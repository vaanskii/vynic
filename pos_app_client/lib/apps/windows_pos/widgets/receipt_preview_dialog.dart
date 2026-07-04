import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:flutter/foundation.dart';

class ReceiptPreviewDialog extends StatelessWidget {
  const ReceiptPreviewDialog({super.key, required this.pngBytes});

  final Uint8List pngBytes;

  static Future<void> show(BuildContext context, Uint8List bytes) {
    return showDialog(
      context: context,
      builder: (context) => ReceiptPreviewDialog(pngBytes: bytes),
    );
  }

  static String _ensurePdfExtension(String path) {
    final trimmed = path.trim();
    if (trimmed.toLowerCase().endsWith('.pdf')) {
      return trimmed;
    }
    return '$trimmed.pdf';
  }

  Future<void> _shareAsPdf(BuildContext context) async {
    try {
      final doc = pw.Document();
      final image = pw.MemoryImage(pngBytes);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final tmpFile = File('${dir.path}/$fileName');
      final pdfBytes = await doc.save();
      await tmpFile.writeAsBytes(pdfBytes, flush: true);

      if (!context.mounted) return;

      final isWindows = defaultTargetPlatform == TargetPlatform.windows;

      if (isWindows) {
        final pickedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'შეინახეთ ქვითარი',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (pickedPath == null) return;

        final targetPath = _ensurePdfExtension(pickedPath);
        await File(targetPath).writeAsBytes(pdfBytes, flush: true);

        if (!context.mounted) return;
        showSuccessToast(context, 'ფაილი წარმატებით შეინახა');
      } else {
        await Share.shareXFiles([
          XFile(tmpFile.path),
        ], text: 'ქვითარი (Receipt)');
      }
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains('MissingPluginException')) {
          showErrorToast(
            context,
            'გთხოვთ გადატვირთოთ აპლიკაცია (Missing Plugin)',
          );
        } else {
          showErrorToast(context, 'შეცდომა: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ქვითრის ნახვა',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SingleChildScrollView(
                    child: Image.memory(
                      pngBytes,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                  ),
                  child: const Text('დახურვა'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _shareAsPdf(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('გაზიარება / PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
