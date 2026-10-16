import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/widgets/pos_text.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/widgets/pin_button.dart';

class TimeEntryDialog extends StatefulWidget {
  final String initialTime;

  const TimeEntryDialog({super.key, this.initialTime = ''});

  @override
  State<TimeEntryDialog> createState() => _TimeEntryDialogState();
}

class _TimeEntryDialogState extends State<TimeEntryDialog> {
  String _timeInput = '';

  @override
  void initState() {
    super.initState();
    _timeInput = widget.initialTime;
  }

  void _onDigitPressed(String digit) {
    final digits = _timeInput.replaceAll(':', '') + digit;
    if (digits.length > 4) return;
    if (digits.length >= 2 && int.parse(digits.substring(0, 2)) > 23) return;
    if (digits.length >= 3 && int.parse(digits[2]) > 5) return;
    setState(
      () => _timeInput = digits.length >= 2
          ? '${digits.substring(0, 2)}:${digits.substring(2)}'
          : digits,
    );
  }

  void _onClearPressed() {
    setState(() {
      _timeInput = '';
    });
  }

  void _onDeletePressed() {
    if (_timeInput.isNotEmpty) {
      String newText = _timeInput.substring(0, _timeInput.length - 1);
      // If we deleted the char after colon, we are left with "HH:".
      // If we delete colon, we get "HH".
      // Logic handles itself mostly, but if we are at "12:", deleting ':' gives "12".
      setState(() {
        _timeInput = newText;
      });
    }
  }

  bool _isValidTime() {
    if (_timeInput.length != 5) return false;
    final parts = _timeInput.split(':');
    if (parts.length != 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
  }

  void _confirm() {
    if (_isValidTime()) Navigator.of(context).pop(_timeInput);
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    width: 420,
    title: 'დროის შეყვანა',
    onClose: () => Navigator.pop(context),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const PosText('გაუქმება'),
      ),
      ElevatedButton(
        onPressed: _isValidTime() ? _confirm : null,
        child: const PosText('დადასტურება'),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VynicFloorTokens.metricFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VynicFloorTokens.panelBorder),
          ),
          child: Text(
            _timeInput.isEmpty ? 'HH:MM' : _timeInput,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 320,
          child: PinPad(
            onDigitPressed: _onDigitPressed,
            onClearPressed: _onClearPressed,
            onDeletePressed: _onDeletePressed,
            onSubmit: _confirm,
          ),
        ),
      ],
    ),
  );
}
