import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/user.dart';

/// Holds the currently active POS staff member for the duration of a shift.
///
/// Quick-switch updates [activeUser] in place (after a PIN confirmation) so the
/// app attributes orders/actions to whoever is operating *right now* without a
/// full logout → login cycle. Screens read [user] (or listen to [activeUser])
/// instead of caching the login-time user, so a switch flows everywhere the
/// next time a screen reads it.
class PosSession {
  PosSession._();

  /// The active staff member, or null before login / after a full logout.
  static final ValueNotifier<User?> activeUser = ValueNotifier<User?>(null);

  static User? get user => activeUser.value;

  /// Set the active user at login.
  static void start(User user) => activeUser.value = user;

  /// Flip the active user after a successful quick-switch PIN check.
  static void switchTo(User user) => activeUser.value = user;

  /// Clear on full logout.
  static void clear() => activeUser.value = null;
}
