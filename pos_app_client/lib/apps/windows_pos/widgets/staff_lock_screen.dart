import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/auth/session_lock.dart';

/// Locks the terminal full-screen and requires a PIN to continue. There is NO
/// cancel and NO way to skip — the only exit is a valid staff PIN:
///   • the same person's PIN resumes their session,
///   • a different person's PIN switches the active user to them.
/// This is a lock, not a logout: returning needs only a PIN, not a full login.
///
/// The full-screen lock route. Pushed by `SessionLock`; the only way it pops is
/// a valid PIN, which returns the now-active [User].
Route<User> staffLockRoute() {
  return PageRouteBuilder<User>(
    opaque: true,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const _StaffLockScreen(),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _StaffLockScreen extends StatefulWidget {
  const _StaffLockScreen();

  @override
  State<_StaffLockScreen> createState() => _StaffLockScreenState();
}

class _StaffLockScreenState extends State<_StaffLockScreen> {
  static const _navy = Color(0xFF001F31);
  static const _accent = Color(0xFF63D5FF);

  String _pin = '';
  bool _error = false;

  void _addDigit(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length >= 4) _tryUnlock();
  }

  void _deleteDigit() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  void _tryUnlock() {
    final user = DatabaseService.authenticateByPin(_pin);
    if (user == null) {
      if (_pin.length >= 6) {
        setState(() {
          _error = true;
          _pin = '';
        });
      }
      return;
    }
    PosSession.switchTo(user);
    Navigator.of(context).pop(user);
  }

  @override
  Widget build(BuildContext context) {
    // Block back-button / system pop — the only way out is a valid PIN.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _navy,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: _accent, size: 46),
                const SizedBox(height: 14),
                const Text(
                  'ტერმინალი ჩაკეტილია',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'გასაგრძელებლად შეიყვანეთ PIN კოდი',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 26),
                _buildDots(),
                SizedBox(
                  height: 24,
                  child: _error
                      ? const Center(
                          child: Text(
                            'არასწორი PIN კოდი',
                            style: TextStyle(
                              color: Color(0xFFFF8A8A),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                _buildPad(),
                const SizedBox(height: 22),
                // The single full-logout entry point in the app. Logging out
                // only returns to the login screen (which itself needs a PIN),
                // so it never exposes data.
                TextButton.icon(
                  onPressed: SessionLock.logout,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF8A8A),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text(
                    'სრული გასვლა',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < _pin.length;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? _accent : Colors.transparent,
            border: Border.all(
              color: filled ? _accent : Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          for (var row = 0; row < 3; row++)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var col = 0; col < 3; col++)
                  _padButton(keys[row * 3 + col]),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 84, height: 84),
              _padButton('0'),
              _padButton('⌫', isDelete: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _padButton(String label, {bool isDelete = false}) {
    return Padding(
      padding: const EdgeInsets.all(7),
      child: InkWell(
        onTap: () => isDelete ? _deleteDigit() : _addDigit(label),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 70,
          height: 70,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
