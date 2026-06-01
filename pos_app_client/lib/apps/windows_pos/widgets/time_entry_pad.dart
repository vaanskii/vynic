import 'package:flutter/material.dart';
import 'pin_button.dart';

const Color _timeAccent = Color(0xFF2563EB);
const Color _timeSurface = Color(0xFFFFFFFF);
const Color _timeSurfaceAlt = Color(0xFFF8FAFC);
const Color _timeOutline = Color(0xFFE2E8F0);
const Color _timeText = Color(0xFF0F172A);
const Color _timeMuted = Color(0xFF64748B);

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
    if (_timeInput.length >= 5) return;

    String newText = _timeInput + digit;

    // Auto-insert colon
    if (newText.length == 2) {
      // Validate hours
      int hour = int.parse(newText);
      if (hour > 23) {
        // Invalid hour, don't add
        return;
      }
      newText += ':';
    } else if (newText.length == 1) {
      // First digit check (optional, but good for UX)
      // If > 2, it can only be 0-9 hours, so maybe auto-prepend 0?
      // But standard typing is fine.
    }

    // Validate minutes if length > 3
    if (newText.length > 3) {
      String minuteFirstDigit = newText[3];
      if (int.parse(minuteFirstDigit) > 5) {
        return; // Invalid minute start
      }
    }

    setState(() {
      _timeInput = newText;
    });
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _timeSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'დროის შეყვანა',
        style: TextStyle(
          color: _timeAccent,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _timeSurfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _timeOutline),
              ),
              child: Center(
                child: Text(
                  _timeInput.isEmpty ? 'HH:MM' : _timeInput,
                  style: TextStyle(
                    color: _timeInput.isEmpty ? _timeMuted : _timeText,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 340,
              child: PinPad(
                onDigitPressed: _onDigitPressed,
                onClearPressed: _onClearPressed,
                onDeletePressed: _onDeletePressed,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: _timeMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('გაუქმება', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isValidTime()
                      ? () => Navigator.of(context).pop(_timeInput)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _timeAccent,
                    disabledBackgroundColor: const Color(0xFFBFDBFE),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'დადასტურება',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: const [],
    );
  }
}
