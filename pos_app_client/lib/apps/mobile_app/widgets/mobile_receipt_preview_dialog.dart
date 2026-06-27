import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart'
    show getSaveLocation, FileSaveLocation, XTypeGroup;
import 'package:vynic/core/widgets/manager_toast.dart';

class MobileReceiptPreviewDialog extends StatelessWidget {
  final Uint8List pngBytes;
  final String title;

  const MobileReceiptPreviewDialog({
    super.key,
    required this.pngBytes,
    this.title = 'ქვითრის ნახვა',
  });

  static Future<void> show(BuildContext context, Uint8List bytes, {String title = 'ქვითრის ნახვა'}) {
    return showDialog(
      context: context,
      builder: (context) => MobileReceiptPreviewDialog(pngBytes: bytes, title: title),
    );
  }

  /// Render the receipt PNG into a single-page roll80 PDF.
  Future<Uint8List> _buildPdfBytes() async {
    final doc = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    return doc.save();
  }

  /// A filesystem-safe base name derived from the receipt title, falling back
  /// to a generic name. Keeps Georgian letters/digits, collapses everything
  /// else to underscores.
  String _safeFileName() {
    final base = title.trim().isEmpty ? 'receipt' : title.trim();
    final cleaned = base
        .replaceAll(RegExp(r'[^\wႠ-ჿ]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${cleaned.isEmpty ? 'receipt' : cleaned}_$stamp.pdf';
  }

  Future<void> _shareAsPdf(BuildContext context) async {
    try {
      // Capture the share button's position before any async gap. On macOS and
      // iPad the share sheet is a popover that *requires* an anchor rect via
      // sharePositionOrigin — omitting it throws and the share fails.
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      final bytes = await _buildPdfBytes();

      // getTemporaryDirectory() only returns a *path* — on sandboxed macOS/iOS
      // the directory may not exist on disk yet, so writeAsBytes throws
      // PathNotFoundException. Create it (recursively) before writing.
      final baseDir = await getTemporaryDirectory();
      final dir = Directory('${baseDir.path}/receipts');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/${_safeFileName()}');
      await file.writeAsBytes(bytes, flush: true);

      if (context.mounted) {
        Navigator.pop(context); // Close loading
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: 'ქვითარი (Receipt)',
          sharePositionOrigin: sharePositionOrigin,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ManagerToast.showSnackBar(context, 'შეცდომა: $e', isError: true);
      }
    }
  }

  /// Save the receipt PDF for manual workflows (e.g. dragging into WhatsApp Web
  /// on Mac). On desktop a native "save as" dialog lets the user pick the
  /// location — this is also what grants the sandboxed macOS app write access.
  /// On mobile (no save dialog) it writes silently to the app Documents dir,
  /// which is visible via the Files app and always writable.
  Future<void> _downloadPdf(BuildContext context) async {
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    try {
      final fileName = _safeFileName();

      if (isDesktop) {
        // Build first, then prompt — the native dialog must not be covered by a
        // loading overlay.
        final bytes = await _buildPdfBytes();
        final FileSaveLocation? location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PDF', extensions: ['pdf']),
          ],
        );
        if (location == null) return; // user cancelled
        await File(location.path).writeAsBytes(bytes, flush: true);
        if (context.mounted) {
          ManagerToast.showSnackBar(context, 'შენახულია');
        }
        return;
      }

      // Mobile: silent save to the app's Documents dir.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );
      final bytes = await _buildPdfBytes();
      final dir = await getApplicationDocumentsDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ManagerToast.showSnackBar(context, 'შენახულია: $fileName');
      }
    } catch (e) {
      if (context.mounted) {
        if (!isDesktop) Navigator.pop(context); // Close loading
        ManagerToast.showSnackBar(context, 'შეცდომა: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: const Color(0xFFF1F5F9),
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            Builder(
              builder: (context) => TextButton.icon(
                onPressed: () => _downloadPdf(context),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text('ჩამოტვირთვა',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            Builder(
              builder: (context) => TextButton.icon(
                onPressed: () => _shareAsPdf(context),
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                label: const Text('გაზიარება',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Image.memory(
                pngBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
