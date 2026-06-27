import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/screens/login_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/staff_lock_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos_session.dart';

/// Coordinates terminal locking for the Windows POS:
///   • idle auto-lock after [idleTimeout] of no interaction,
///   • the manual lock from the staff role button,
///   • the resume-vs-switch outcome after a PIN is entered.
///
/// A valid PIN by the SAME user resumes exactly where they were (the lock is an
/// overlay route). A DIFFERENT user switches: the nav stack is popped back to
/// the home screen and [resetToLanding] fires so HomeScreen returns to the
/// landing tab — the new person starts fresh, not mid-task.
class SessionLock {
  SessionLock._();

  /// Root navigator — also used for app-level dialogs in main.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Bumped when an unlock switched to a different user. HomeScreen listens and
  /// resets to the landing tab.
  static final ValueNotifier<int> resetToLanding = ValueNotifier<int>(0);

  /// Lock the terminal after this much inactivity. Adjustable at runtime.
  static Duration idleTimeout = const Duration(minutes: 5);

  static Timer? _idleTimer;
  static bool _armed = false;
  static bool _locked = false;

  /// Start watching for inactivity — call when a POS user enters the app.
  static void arm() {
    _armed = true;
    _restartIdleTimer();
  }

  /// Stop watching — call on logout.
  static void disarm() {
    _armed = false;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Any user interaction resets the idle countdown.
  static void recordActivity() {
    if (!_armed || _locked) return;
    _restartIdleTimer();
  }

  static void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (!_armed) return;
    _idleTimer = Timer(idleTimeout, () {
      if (_armed && !_locked) lock();
    });
  }

  /// Lock full-screen until a PIN is entered.
  static Future<void> lock() async {
    if (_locked) return;
    if (PosSession.user == null) return; // not logged in
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    _locked = true;
    _idleTimer?.cancel();
    final before = PosSession.user;

    final unlocked = await nav.push<User>(staffLockRoute());

    _locked = false;
    _restartIdleTimer();

    if (unlocked == null) return;
    final switched = before == null || unlocked.username != before.username;
    if (switched) {
      // Drop any half-open screen (e.g. an order the previous user was editing)
      // and send HomeScreen back to the landing tab.
      nav.popUntil((route) => route.isFirst);
      resetToLanding.value = resetToLanding.value + 1;
    }
  }

  /// Full logout — ends the session and returns to the login screen. This is the
  /// single logout entry point (from the lock screen); the home screen has none.
  static void logout() {
    disarm();
    PosSession.clear();
    final nav = navigatorKey.currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
