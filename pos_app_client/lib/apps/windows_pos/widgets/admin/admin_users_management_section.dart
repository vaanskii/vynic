import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';

class AdminUsersManagementSection extends StatefulWidget {
  final User user;

  const AdminUsersManagementSection({super.key, required this.user});

  @override
  State<AdminUsersManagementSection> createState() =>
      _AdminUsersManagementSectionState();
}

class _AdminUsersManagementSectionState
    extends State<AdminUsersManagementSection> {
  // Theme constants copied from AdminScreen
  static const Color _primaryColor = Color(0xFF1E3A8A);
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF4F6FF);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final allUsers = DatabaseService.getAllUsers();
    final admins = allUsers.where((u) => u.isAdmin).toList();
    final waiters = allUsers.where((u) => !u.isAdmin).toList();

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'მომხმარებლების მართვა',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: isMobile ? 22 : 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: isMobile ? 24 : 32),

              // Admins Section
              Text(
                '👑 ადმინისტრატორები',
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...admins.map((user) => _buildUserCard(user, true, isMobile)),

              const SizedBox(height: 32),

              // Waiters Section
              Text(
                '👤 ოფიციანტები',
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...waiters.map((user) => _buildUserCard(user, false, isMobile)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(User user, bool isAdmin, bool isMobile) {
    final allUsers = DatabaseService.getAllUsers();
    final adminCount = allUsers.where((u) => u.isAdmin).length;

    return Card(
      color: _cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAdmin ? _secondaryColor : _borderColor,
          width: 2,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Row(
          children: [
            // User Icon
            Container(
              width: isMobile ? 48 : 60,
              height: isMobile ? 48 : 60,
              decoration: BoxDecoration(
                color: isAdmin ? _secondaryColor : _primaryColor,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.person,
                color: Colors.white,
                size: isMobile ? 24 : 32,
              ),
            ),
            SizedBox(width: isMobile ? 12 : 20),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        user.username,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: isMobile ? 16 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _secondaryColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ადმინი',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      const Icon(Icons.lock, color: _textMuted, size: 16),
                      Text(
                        'PIN: ',
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: isMobile ? 12 : 14,
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 8 : 12,
                          vertical: isMobile ? 2 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Text(
                          user.pinCode,
                          style: TextStyle(
                            color: _primaryColor,
                            fontSize: isMobile ? 14 : 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: isMobile ? 2 : 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action Buttons
            // Action Buttons
            if (isMobile)
              Column(
                children: [
                  IconButton(
                    onPressed: () => _showChangePinDialog(user),
                    icon: const Icon(Icons.edit, size: 20),
                    color: _secondaryColor,
                    tooltip: 'შეცვლა',
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  if (!isAdmin || adminCount > 1) ...[
                    const SizedBox(height: 8),
                    IconButton(
                      onPressed: () => _confirmDeleteUser(user),
                      icon: const Icon(Icons.delete, size: 20),
                      color: Colors.red,
                      tooltip: 'წაშლა',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              )
            else
              Column(
                children: [
                  // Change PIN Button
                  ElevatedButton.icon(
                    onPressed: () => _showChangePinDialog(user),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('შეცვლა'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _secondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Delete Button (only for non-admins or if not the last admin)
                  if (!isAdmin || adminCount > 1)
                    OutlinedButton.icon(
                      onPressed: () => _confirmDeleteUser(user),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('წაშლა'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePinDialog(User user) async {
    final newPin = await showDialog<String>(
      context: context,
      builder: (context) => _ChangePinDialog(user: user),
    );

    if (newPin == null || newPin.isEmpty || !mounted) {
      return;
    }

    user.pinCode = newPin;
    await user.save();
    if (!mounted) {
      return;
    }
    setState(() {});

    unawaited(
      showSuccessToast(context, 'PIN კოდი შეიცვალა ${user.username}-სთვის'),
    );
  }

  Future<void> _confirmDeleteUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          'მომხმარებლის წაშლა',
          style: TextStyle(color: _textPrimary),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ ${user.username}-ის წაშლა?',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await user.delete();
    if (!mounted) {
      return;
    }
    setState(() {});

    unawaited(
      showPosToast(
        context: context,
        message: '${user.username} წაიშალა',
        style: PosToastStyle.info,
      ),
    );
  }
}

class _ChangePinDialog extends StatefulWidget {
  final User user;

  const _ChangePinDialog({required this.user});

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
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

  void _onConfirm() {
    if (_enteredPin.length != 6) {
      setState(() {
        _errorMessage = 'PIN კოდი უნდა იყოს 6 ციფრი';
      });
      return;
    }

    // Check if PIN is already in use
    final allUsers = DatabaseService.getAllUsers();
    final pinExists = allUsers.any(
      (u) => u.pinCode == _enteredPin && u.username != widget.user.username,
    );

    if (pinExists) {
      setState(() {
        _errorMessage = 'ეს PIN კოდი უკვე გამოიყენება';
        _enteredPin = '';
      });
      return;
    }

    Navigator.of(context).pop(_enteredPin);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 24,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 420),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF4FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.lock_reset,
                    color: Color(0xFF2563EB),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'PIN კოდის შეცვლა',
                  style: TextStyle(
                    color: const Color(0xFF1F2937),
                    fontSize: isMobile ? 22 : 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.user.username,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                // PIN display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    6,
                    (index) => Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isMobile ? 3 : 6,
                      ),
                      width: isMobile ? 36 : 45,
                      height: isMobile ? 44 : 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: index < _enteredPin.length
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFE2E8F0),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          index < _enteredPin.length ? _enteredPin[index] : '',
                          style: TextStyle(
                            color: const Color(0xFF1D4ED8),
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
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
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 14,
                    ),
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
                        SizedBox(
                          width: isMobile ? 64 : 72,
                          height: isMobile ? 64 : 72,
                        ), // Empty space
                        const SizedBox(width: 12),
                        PinButton(
                          number: '0',
                          onPressed: () => _onNumberPressed('0'),
                        ),
                        const SizedBox(width: 12),
                        PinButton(
                          number: '⌫',
                          onPressed: _onBackspacePressed,
                          isSpecial: true,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'გაუქმება',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'დადასტურება',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
