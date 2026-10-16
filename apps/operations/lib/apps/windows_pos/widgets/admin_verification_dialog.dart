import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'shared/pos_pin_form.dart';

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
  Widget build(BuildContext context) => PosPinForm(
    title: 'ადმინ ავტორიზაცია',
    subtitle: 'შეიყვანეთ ადმინის PIN კოდი',
    value: _enteredPin,
    error: _errorMessage,
    onDigit: _onNumberPressed,
    onDelete: _onBackspacePressed,
    onClear: () => setState(() {
      _enteredPin = '';
      _errorMessage = '';
    }),
    onSubmit: _verifyPin,
    submitEnabled: _enteredPin.length >= 4,
    onCancel: () => Navigator.of(context).pop(),
  );
}
