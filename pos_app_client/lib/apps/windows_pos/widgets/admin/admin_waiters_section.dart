import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';

class AdminWaitersSection extends StatefulWidget {
  final User user;
  final TextEditingController usernameController;
  final VoidCallback onShowKeyboard;

  const AdminWaitersSection({
    super.key,
    required this.user,
    required this.usernameController,
    required this.onShowKeyboard,
  });

  @override
  State<AdminWaitersSection> createState() => _AdminWaitersSectionState();
}

class _AdminWaitersSectionState extends State<AdminWaitersSection> {
  String _pinCode = '';
  String _selectedRole = 'waiter';
  bool _isNameKeyboardVisible = false;

  // Theme constants copied from AdminScreen
  static const Color _primaryColor = Color(0xFF1E3A8A);
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF4F6FF);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    widget.usernameController.addListener(_updateState);
  }

  @override
  void dispose() {
    widget.usernameController.removeListener(_updateState);
    super.dispose();
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  void _showNameKeyboard() {
    setState(() {
      _isNameKeyboardVisible = true;
      widget.usernameController.selection = TextSelection.collapsed(
        offset: widget.usernameController.text.length,
      );
    });
  }

  void _hideNameKeyboard() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isNameKeyboardVisible = false;
    });
  }

  Future<void> _showPinDialog() async {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    String tempPin = _pinCode;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: _cardColor,
            insetPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _borderColor),
            ),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter PIN Code',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isMobile ? 16 : 24),

                  // PIN display
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Center(
                      child: Text(
                        tempPin.isEmpty ? '------' : tempPin.padRight(6, '-'),
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: isMobile ? 28 : 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: isMobile ? 8 : 12,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isMobile ? 16 : 24),

                  // PIN pad
                  SizedBox(
                    width: isMobile ? double.infinity : 300,
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.2,
                      children: [
                        for (int i = 1; i <= 9; i++)
                          PinButton(
                            number: i.toString(),
                            onPressed: () {
                              if (tempPin.length < 6) {
                                setDialogState(() {
                                  tempPin += i.toString();
                                });
                              }
                            },
                          ),
                        PinButton(
                          number: 'C',
                          onPressed: () {
                            setDialogState(() {
                              tempPin = '';
                            });
                          },
                          isSpecial: true,
                        ),
                        PinButton(
                          number: '0',
                          onPressed: () {
                            if (tempPin.length < 6) {
                              setDialogState(() {
                                tempPin += '0';
                              });
                            }
                          },
                        ),
                        PinButton(
                          number: '⌫',
                          onPressed: () {
                            if (tempPin.isNotEmpty) {
                              setDialogState(() {
                                tempPin = tempPin.substring(
                                  0,
                                  tempPin.length - 1,
                                );
                              });
                            }
                          },
                          isSpecial: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: tempPin.length == 6
                            ? () {
                                setState(() {
                                  _pinCode = tempPin;
                                });
                                Navigator.of(context).pop();
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _textMuted.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createWaiter() async {
    final username = widget.usernameController.text.trim();

    if (username.isEmpty) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Please enter a username'));
      return;
    }

    if (_pinCode.length != 6) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'PIN must be 6 digits'));
      return;
    }

    // Check if PIN already exists
    if (DatabaseService.isPinCodeExists(_pinCode)) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'This PIN code is already in use'));
      return;
    }

    // Create the user
    final success = await DatabaseService.addUser(
      username: username,
      pinCode: _pinCode,
      role: _selectedRole,
    );

    if (!mounted) return;

    if (success) {
      unawaited(
        showSuccessToast(
          context,
          '$_selectedRole "$username" created successfully',
        ),
      );

      // Clear form
      setState(() {
        widget.usernameController.clear();
        _pinCode = '';
        _selectedRole = 'waiter';
        _isNameKeyboardVisible = false;
      });
    } else {
      unawaited(showErrorToast(context, 'Failed to create user'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
        const keyboardHeight = 322.0;

        return Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 24,
                  isMobile ? 16 : 24,
                  isMobile ? 16 : 24,
                  (!isMobile && _isNameKeyboardVisible) ? keyboardHeight + (isMobile ? 16 : 24) : (isMobile ? 16 : 24),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ახალი მომხმარებლის შექმნა',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: isMobile ? 22 : 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: isMobile ? 24 : 32),

                      // Username input
                      Container(
                        padding: EdgeInsets.all(isMobile ? 16 : 24),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'მომხმარებლის სახელი',
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            isMobile
                                ? TextField(
                                    controller: widget.usernameController,
                                    readOnly: false,
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 16,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'სახელი',
                                      hintStyle: TextStyle(
                                        color: _textMuted.withValues(alpha: 0.6),
                                      ),
                                      filled: true,
                                      fillColor: _surfaceColor,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _borderColor,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _primaryColor,
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  )
                                : InkWell(
                                    onTap: _showNameKeyboard,
                                    borderRadius: BorderRadius.circular(12),
                                    child: IgnorePointer(
                                      child: TextField(
                                        controller: widget.usernameController,
                                        readOnly: true,
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontSize: 18,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'დააჭირეთ სახელის შესაყვანად',
                                          hintStyle: TextStyle(
                                            color: _textMuted.withValues(alpha: 0.6),
                                          ),
                                          filled: true,
                                          fillColor: _surfaceColor,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                              color: _borderColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                              color: _primaryColor,
                                              width: 1.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Role selection
                      Container(
                        padding: EdgeInsets.all(isMobile ? 16 : 24),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'როლი',
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedRole = 'waiter';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _selectedRole == 'waiter'
                                            ? _secondaryColor
                                            : _surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'ოფიციანტი',
                                          style: TextStyle(
                                            color: _selectedRole == 'waiter'
                                                ? Colors.white
                                                : _textMuted,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedRole = 'admin';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _selectedRole == 'admin'
                                            ? _secondaryColor
                                            : _surfaceColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'ადმინი',
                                          style: TextStyle(
                                            color: _selectedRole == 'admin'
                                                ? Colors.white
                                                : _textMuted,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // PIN input
                      Container(
                        padding: EdgeInsets.all(isMobile ? 16 : 24),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PIN კოდი (6 ციფრი)',
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            InkWell(
                              onTap: _showPinDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: _surfaceColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _pinCode.isEmpty
                                          ? '------'
                                          : _pinCode.padRight(6, '-'),
                                      style: TextStyle(
                                        color: _textPrimary,
                                        fontSize: isMobile ? 24 : 28,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: isMobile ? 8 : 10,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(
                                      Icons.dialpad,
                                      color: _primaryColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Create button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _createWaiter,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _secondaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.person_add, size: 24),
                          label: const Text(
                            'ოფიციანტის შექმნა',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!isMobile)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                left: 0,
                right: 0,
                bottom: _isNameKeyboardVisible ? 0 : -(keyboardHeight + 24),
                child: SizedBox(
                  height: keyboardHeight,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, top: 2),
                          child: IconButton(
                            onPressed: _hideNameKeyboard,
                            icon: const Icon(Icons.close, size: 20),
                            color: _textMuted,
                            tooltip: 'დახურვა',
                          ),
                        ),
                      ),
                      Expanded(
                        child: OnScreenKeyboard(
                          controller: widget.usernameController,
                          language: 'ka',
                          onClose: _hideNameKeyboard,
                          showHeader: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
