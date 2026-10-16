import 'package:vynic/core/database/local_data_admission.dart';
import 'dart:async';
import '../../printing/print_identity_admission.dart';

/// One process-wide admission barrier. Only the Windows POS updater enables it.
/// Persisted open entities and durable Cloud outboxes are deliberately absent.
class UpdateReadiness {
  static bool enabled = false;
  static bool startupReady = false;
  static bool frozen = false;
  static String? failure;
  static final Map<Object, String> _active = {};
  static final List<String? Function()> recoveryChecks = [];
  static List<String> get activeOperations =>
      List.unmodifiable(_active.values.toSet());
  static String operationLabel(String operation) => switch (operation) {
    'collect' =>
      'მიმდინარეობს გადახდა — დაასრულეთ ან გააუქმეთ გადახდის ფანჯარა',
    'closeTable' || 'completeExistingSale' => 'მიმდინარეობს მაგიდის დახურვა',
    'closeDay' => 'მიმდინარეობს დღის დახურვა',
    'transferItems' => 'მიმდინარეობს პროდუქტების გადატანა',
    'cancelOrder' => 'მიმდინარეობს შეკვეთის გაუქმება',
    'Print transmission' => 'მიმდინარეობს პრინტერზე გაგზავნა',
    'Cloud command' => 'სრულდება სერვერიდან მიღებული ოპერაცია',
    'Hive write' || 'Hive model write' => 'მიმდინარეობს მონაცემების შენახვა',
    _ => 'მიმდინარეობს ლოკალური ოპერაცია',
  };

  static String? get blockedReason {
    if (PrintIdentityAdmission.activeSubmissions > 0) {
      return operationLabel('Print transmission');
    }
    if (LocalDataAdmission.failure != null) return 'საჭიროა ოპერაციის აღდგენა';
    if (LocalDataAdmission.exclusiveOperation == 'closeDay')
      return operationLabel('closeDay');
    if (LocalDataAdmission.exclusiveOperation == 'transferItems')
      return operationLabel('transferItems');
    if (LocalDataAdmission.blocked)
      return 'მიმდინარეობს სარეზერვო ასლის აღდგენა ან შექმნა';
    if (!startupReady) return 'პროგრამა ჯერ მზად არ არის';
    if (failure != null) return 'საჭიროა ოპერაციის აღდგენა';
    if (frozen) return 'განახლება მიმდინარეობს';
    if (_active.isNotEmpty) return operationLabel(_active.values.first);
    for (final check in recoveryChecks) {
      try {
        final reason = check();
        if (reason != null) return reason;
      } catch (_) {
        return 'მონაცემების მზადყოფნა ვერ შემოწმდა';
      }
    }
    return null;
  }

  static ({String status, String? reason}) evaluate() {
    final reason = blockedReason;
    return (status: reason == null ? 'READY' : 'BLOCKED', reason: reason);
  }

  static Future<T> track<T>(String operation, Future<T> Function() action) =>
      LocalDataAdmission.track(() async {
        if (!enabled) return action();
        if (frozen) throw StateError('POS update has frozen new operations');
        final token = Object();
        _active[token] = operation;
        try {
          return await action();
        } finally {
          _active.remove(token);
        }
      });

  /// Ordinary operational writes share one reentrant owner. Admission-only
  /// activities, such as an open payment dialog, continue to use [track].
  static Future<T> mutate<T>(String operation, Future<T> Function() action) =>
      LocalDataAdmission.mutate(() => track(operation, action));

  /// Acquires synchronously before any await, closing check/use races.
  static Future<String?> freeze(Future<void> Function() flushAndClose) async {
    final reason = blockedReason;
    if (reason != null) return reason;
    frozen = true;
    try {
      await flushAndClose();
      return null;
    } catch (e) {
      failure = e.toString();
      // Boxes may be partially closed: keep admission frozen until restart.
      return 'მონაცემების შენახვა ვერ დასრულდა';
    }
  }
}
