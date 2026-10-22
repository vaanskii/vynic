import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import 'package:vynic/core/widgets/pos_text.dart';

/// Shared presentation only. Authentication and staff PIN policy stay with the
/// owner, including its minimum length, duplicate checks and submit behavior.
class PosPinForm extends StatelessWidget {
  const PosPinForm({
    super.key,
    required this.title,
    required this.value,
    required this.onDigit,
    required this.onDelete,
    required this.onClear,
    required this.onSubmit,
    required this.onCancel,
    this.submitEnabled = true,
    this.confirmLabel = 'დადასტურება',
    this.error,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final String value;
  final String? error;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete, onClear, onSubmit, onCancel;
  final bool submitEnabled;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: title,
    subtitle: subtitle,
    width: 420,
    onClose: onCancel,
    actions: [
      TextButton(onPressed: onCancel, child: const PosText('გაუქმება')),
      ElevatedButton(
        onPressed: submitEnabled ? onSubmit : null,
        child: PosText(confirmLabel),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'PIN',
          value: '${value.length} / 6',
          obscured: true,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: VynicFloorTokens.metricFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: VynicFloorTokens.panelBorder),
              ),
              child: Text(
                '•' * value.length + '—' * (6 - value.length).clamp(0, 6),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
              ),
            ),
          ),
        ),
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 16),
          PosFormError(error!),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: 320,
          child: PinPad(
            authentication: true,
            onDigitPressed: onDigit,
            onDeletePressed: onDelete,
            onClearPressed: onClear,
            onSubmit: submitEnabled ? onSubmit : null,
          ),
        ),
      ],
    ),
  );
}
