import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:flutter/material.dart';

class ReceiptLanguagePickerDialog extends StatelessWidget {
  const ReceiptLanguagePickerDialog({super.key});

  static Future<String?> show(
    BuildContext context, {
    bool barrierDismissible = false,
  }) {
    return showPosModal<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => const ReceiptLanguagePickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: 'აირჩიეთ ქვითრის ენა',
    width: 460,
    onClose: () => Navigator.pop(context),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('უკან დაბრუნება'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, 'ka'),
          icon: const Icon(Icons.language_rounded),
          label: const Text('ქართული'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, 'en'),
          icon: const Icon(Icons.translate_rounded),
          label: const Text('English'),
        ),
      ],
    ),
  );
}
