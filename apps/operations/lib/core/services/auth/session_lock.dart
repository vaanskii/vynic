import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';

typedef PosLockRouteBuilder = Route<User> Function();

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
  static PosLockRouteBuilder? _lockRouteBuilder;
  static WidgetBuilder? _loginBuilder;

  /// Bumped when an unlock switched to a different user. HomeScreen listens and
  /// resets to the landing tab.
  static final ValueNotifier<int> resetToLanding = ValueNotifier<int>(0);

  /// Lock the terminal after this much inactivity. Adjustable at runtime.
  static Duration idleTimeout = const Duration(minutes: 5);

  static Timer? _idleTimer;
  static bool _armed = false;
  static bool _locked = false;

  static void configureRoutes({
    required PosLockRouteBuilder lockRouteBuilder,
    required WidgetBuilder loginBuilder,
  }) {
    _lockRouteBuilder = lockRouteBuilder;
    _loginBuilder = loginBuilder;
  }

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
    final lockRouteBuilder = _lockRouteBuilder;
    if (lockRouteBuilder == null) {
      throw StateError('SessionLock lock route is not configured.');
    }

    _locked = true;
    _idleTimer?.cancel();
    final before = PosSession.user;

    final unlocked = await nav.push<User>(lockRouteBuilder());

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
    final loginBuilder = _loginBuilder;
    if (loginBuilder == null) {
      throw StateError('SessionLock login route is not configured.');
    }
    nav?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: loginBuilder),
      (route) => false,
    );
  }
}
