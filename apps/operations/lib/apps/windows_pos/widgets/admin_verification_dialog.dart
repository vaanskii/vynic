import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/widgets/pin_button.dart';

class AdminVerificationDialog extends StatefulWidget {
  const AdminVerificationDialog({super.key});

  @override
  State<AdminVerificationDialog> createState() =>
      _AdminVerificationDialogState();
}

class _AdminVerificationDialogState extends State<AdminVerificationDialog> {
  String _enteredPin = '';
  String _errorMessage = '';

  void _onNumberPressed(String number) {
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += number;
        _errorMessage = '';
      });

      // Auto-verify when 6 digits entered
      if (_enteredPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = '';
      });
    }
  }

  void _verifyPin() async {
    final users = DatabaseService.getAllUsers();
    User? matchingAdmin;
    for (final user in users) {
      if (user.isAdmin && user.pinCode == _enteredPin) {
        matchingAdmin = user;
        break;
      }
    }

    if (matchingAdmin != null) {
      if (mounted) {
        Navigator.of(context).pop(matchingAdmin);
      }
    } else {
      setState(() {
        _errorMessage = 'არასწორი ადმინ PIN კოდი';
        _enteredPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2B2B2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFFC0AD7B), size: 48),
            const SizedBox(height: 16),
            const Text(
              'ადმინ ავტორიზაცია',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'შეიყვანეთ ადმინის PIN კოდი',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            // PIN display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 45,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a1a),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: index < _enteredPin.length
                          ? const Color(0xFFC0AD7B)
                          : const Color(0xFF444444),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      index < _enteredPin.length ? '●' : '',
                      style: const TextStyle(
                        color: Color(0xFFC0AD7B),
                        fontSize: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
            const SizedBox(height: 24),
            // PIN pad
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PinButton(
                      number: '1',
                      onPressed: () => _onNumberPressed('1'),
                    ),
                    const SizedBox(width: 12),
                    PinButton(
                      number: '2',
                      onPressed: () => _onNumberPressed('2'),
                    ),
                    const SizedBox(width: 12),
                    PinButton(
                      number: '3',
                      onPressed: () => _onNumberPressed('3'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PinButton(
                      number: '4',
                      onPressed: () => _onNumberPressed('4'),
                    ),
                    const SizedBox(width: 12),
                    PinButton(
                      number: '5',
                      onPressed: () => _onNumberPressed('5'),
                    ),
                    const SizedBox(width: 12),
                    PinButton(
                      number: '6',
                      onPressed: () => _onNumberPressed('6'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PinButton(
                      number: '7',
                      onPressed: () => _onNumberPressed('7'),
                    ),
                    const SizedBox(width: 12),
                    PinButton(
                      number: '8',
                      onPressed: () => _onNumberPressed('8'),
                    ),
                    const SizedBox(width: 12),
                    PinButton(
                      number: '9',
                      onPressed: () => _onNumberPressed('9'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 72, height: 72), // Empty space
                    const SizedBox(width: 12),
                    PinButton(
                      number: '0',
                      onPressed: () => _onNumberPressed('0'),
                    ),
                    const SizedBox(width: 12),
                    // Backspace button
                    Material(
                      color: const Color(0xFF1a1a1a),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _onBackspacePressed,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF444444),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.backspace_outlined,
                            color: Colors.white70,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'გაუქმება',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
