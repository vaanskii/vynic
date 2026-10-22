import 'package:flutter/material.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';

/// Shared presentation for money entry. Parsing, limits and persistence remain
/// with the workflow that owns the amount.
class PosAmountForm extends StatefulWidget {
  const PosAmountForm({
    super.key,
    required this.title,
    required this.description,
    required this.controller,
    required this.keypad,
    required this.parse,
    this.validate,
    this.clearLabel,
  });
  final String title;
  final String description;
  final TextEditingController controller;
  final Widget keypad;
  final double Function(String) parse;
  final String? Function(String)? validate;
  final String? clearLabel;

  @override
  State<PosAmountForm> createState() => _PosAmountFormState();
}

class _PosAmountFormState extends State<PosAmountForm> {
  String? _error;

  void _submit() {
    final error = widget.validate?.call(widget.controller.text);
    setState(() => _error = error);
    if (error == null)
      Navigator.of(context).pop(widget.parse(widget.controller.text));
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: widget.title,
    subtitle: widget.description,
    width: 460,
    onClose: () => Navigator.of(context).pop(),
    actions: [
      if (widget.clearLabel != null)
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: VynicFloorTokens.dangerText,
          ),
          onPressed: () => Navigator.of(context).pop(0.0),
          child: Text(widget.clearLabel!),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('გაუქმება'),
      ),
      FilledButton(onPressed: _submit, child: const Text('შენახვა')),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          keyboardType: PosInputSettings.useOnScreen(context)
              ? TextInputType.none
              : const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'თანხა',
            hintText: '0.00',
            suffixText: 'GEL',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 20),
        widget.keypad,
      ],
    ),
  );
}
