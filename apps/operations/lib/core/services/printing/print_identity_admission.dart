/// A native spool call can outlive the Dart timeout. Keep ownership stable
/// until its ORIGINAL platform future settles, never until a timeout/reprint.
/// The single Dart isolate acquires both kinds of admission synchronously.
abstract final class PrintIdentityAdmission {
  static final Set<Object> _submissions = {};
  static bool _transition = false;
  static int get activeSubmissions => _submissions.length;
  static bool get identityTransitionActive => _transition;

  static Object beginSubmission({bool Function()? maySubmit}) {
    if (_transition || (maySubmit != null && !maySubmit())) {
      throw StateError('Printer ownership is changing or no longer matches');
    }
    final token = Object();
    _submissions.add(token);
    return token;
  }

  static void finishSubmission(Object token) {
    if (!_submissions.remove(token))
      throw StateError('Unknown print submission admission');
  }

  static Future<T> changeIdentity<T>(Future<T> Function() action) async {
    if (_transition || _submissions.isNotEmpty) {
      throw StateError(
        'Printer submission is still active; Device identity cannot change',
      );
    }
    _transition = true;
    try {
      return await action();
    } finally {
      _transition = false;
    }
  }
}
