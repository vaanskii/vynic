import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/sync/connection_status_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/services/sync/sync_timing.dart';

/// What the sync timing instrumentation is allowed to do.
///
/// It exists to attribute the ten to fifteen seconds an ordinary sync appears
/// to take, so the one thing it must not do is change what a sync does. These
/// cover the measurement itself and the one place it touched control flow: the
/// marker that records a local change as unpushed.
void main() {
  test('a reading of the monotonic source never goes backwards', () {
    final first = SyncTiming.nowMicros();
    final second = SyncTiming.nowMicros();
    expect(second, greaterThanOrEqualTo(first));
  });

  test('an unknown trigger is reported as unknown, not as zero', () {
    final lines = <String>[];
    final timing = SyncTiming.begin();
    timing.mark('orders');
    _capture(lines, () => timing.log('Test'));

    expect(lines.single, contains('trigger=n/a'));
  });

  test('a known trigger delay is reported and counted in the total', () {
    final lines = <String>[];
    // A change that became due one measurable moment ago.
    final pendingSince = SyncTiming.nowMicros() - 8000 * 1000;
    final timing = SyncTiming.begin(pendingSinceMicros: pendingSince);
    timing.mark('orders');
    timing.mark('http');
    _capture(lines, () => timing.log('Test'));

    final line = lines.single;
    expect(line, contains('[SyncTiming][Test]'));
    // The wait dominates the total, which is the distinction the summary is
    // for: a sync that took eight seconds to start, not eight to run.
    final trigger = _fieldMs(line, 'trigger');
    final total = _fieldMs(line, 'total');
    expect(trigger, greaterThanOrEqualTo(7900));
    expect(total, greaterThanOrEqualTo(trigger));
    expect(total - trigger, lessThan(1000));
  });

  test('build phases are summed and named, other phases stand alone', () {
    final lines = <String>[];
    final timing = SyncTiming.begin();
    for (final phase in const [
      'orders',
      'tables',
      'sales',
      'reports',
      'menu',
      'staff',
      'quick',
      'expenses',
      'reservations',
      'payload',
    ]) {
      timing.mark(phase);
    }
    timing.mark('encode');
    timing.mark('http');
    timing.mark('audit');
    timing.payloadBytes = 412 * 1024;
    _capture(lines, () => timing.log('POS'));

    final line = lines.single;
    for (final phase in const ['orders', 'tables', 'sales', 'menu']) {
      expect(line, contains('$phase='));
    }
    expect(line, contains('build='));
    expect(line, contains('encode='));
    expect(line, contains('http='));
    expect(line, contains('audit='));
    expect(line, contains('payload=412kB'));
  });

  test('a summary with nothing measured still prints one line', () {
    final lines = <String>[];
    _capture(lines, () => SyncTiming.begin().log('Empty'));
    expect(lines, hasLength(1));
  });

  test('the timing summary carries no payload contents', () {
    final lines = <String>[];
    final timing = SyncTiming.begin(pendingSinceMicros: SyncTiming.nowMicros());
    timing.mark('orders');
    timing.payloadBytes = 1024;
    _capture(lines, () => timing.log('POS'));

    // Only fixed labels, digits and units — nothing read out of the payload.
    expect(
      RegExp(
        r'^\[SyncTiming\]\[POS\][a-zA-Z0-9=()/ .]*$',
      ).hasMatch(lines.single),
      isTrue,
      reason: lines.single,
    );
  });

  group('recording a local change as unpushed', () {
    setUp(() {
      ConnectionStatusService.hasPendingLocalChanges.value = false;
      ManagerSyncService.dispose();
    });

    test('a POS edit still marks pending rather than pushing', () {
      // The instrumented marker wraps the pending flag; it must not have
      // become a push, and it must not have stopped marking.
      ManagerSyncService.syncToManagerAppDebounced();
      expect(ConnectionStatusService.hasPendingLocalChanges.value, isTrue);
    });

    test('a realtime-eligible edit still marks pending', () {
      ManagerSyncService.syncRealtimeToManagerAppDebounced();
      expect(ConnectionStatusService.hasPendingLocalChanges.value, isTrue);
    });
  });
}

/// Collects `debugPrint` output produced by [body].
void _capture(List<String> into, void Function() body) {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) into.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = original;
  }
}

int _fieldMs(String line, String field) {
  final match = RegExp('$field=(\\d+)ms').firstMatch(line);
  expect(match, isNotNull, reason: 'no $field in: $line');
  return int.parse(match!.group(1)!);
}
