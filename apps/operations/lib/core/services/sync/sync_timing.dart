import 'package:flutter/foundation.dart';

/// Where one POS → Cloud sync spends its time.
///
/// A normal sync is reported as taking ten to fifteen seconds, and there are
/// four very different places that could go: waiting to start, building the
/// payload, the network, and the backend's own work. Counting them separately
/// is the whole point — a summary that only says `total` cannot tell a slow
/// database from a scheduler that has not fired yet.
///
/// Durations come from [Stopwatch], never from wall-clock arithmetic: the POS
/// runs with a developer-settable business date and the operator's clock can
/// move, so a subtraction of two `DateTime.now()` readings is not a duration.
///
/// One completed sync prints one line. Phase names are fixed labels and byte
/// counts are sizes, so nothing here carries payload contents.
class SyncTiming {
  SyncTiming._(this._triggerDelayMicros);

  /// The process's monotonic reference. Started once, read for every mark.
  static final Stopwatch _clock = Stopwatch()..start();

  /// A monotonic reading, for callers that need to remember "when" — the age
  /// of the oldest unpushed change, say — without touching the wall clock.
  static int nowMicros() => _clock.elapsedMicroseconds;

  /// Begins a measurement. [pendingSinceMicros] is a reading from
  /// [nowMicros] taken when the work first became due, if that is known.
  static SyncTiming begin({int? pendingSinceMicros}) {
    return SyncTiming._(
      pendingSinceMicros == null ? null : nowMicros() - pendingSinceMicros,
    );
  }

  final int? _triggerDelayMicros;
  final Stopwatch _segment = Stopwatch()..start();
  final List<(String, int)> _phases = <(String, int)>[];

  /// Which phases count towards the reported build cost.
  static const Set<String> _buildPhases = <String>{
    'orders',
    'tables',
    'sales',
    'reports',
    'menu',
    'staff',
    'quick',
    'payload',
  };

  /// Closes the phase that just finished and names it.
  ///
  /// Sequential rather than nested on purpose: the sync path is one long
  /// straight line, so a mark per finished step reads at the call site and
  /// adds nothing to the parts being measured.
  void mark(String phase) {
    _phases.add((phase, _segment.elapsedMicroseconds));
    _segment
      ..reset()
      ..start();
  }

  /// The size of what was sent. A byte count, not a body.
  int? payloadBytes;

  /// Prints the one-line summary for [source] — `POS` here, `Backend` for the
  /// line the server prints for the same request.
  void log(String source) {
    final build = _phases
        .where((phase) => _buildPhases.contains(phase.$1))
        .fold<int>(0, (sum, phase) => sum + phase.$2);
    final breakdown = _phases
        .where((phase) => _buildPhases.contains(phase.$1))
        .map((phase) => '${phase.$1}=${_ms(phase.$2)}')
        .join(' ');
    final tail = _phases
        .where((phase) => !_buildPhases.contains(phase.$1))
        .map((phase) => '${phase.$1}=${_ms(phase.$2)}ms')
        .join(' ');
    final total =
        (_triggerDelayMicros ?? 0) +
        _phases.fold<int>(0, (sum, phase) => sum + phase.$2);

    final trigger = _triggerDelayMicros == null
        ? 'trigger=n/a'
        : 'trigger=${_ms(_triggerDelayMicros)}ms';
    final size = payloadBytes == null
        ? ''
        : ' payload=${(payloadBytes! / 1024).round()}kB';

    debugPrint(
      '[SyncTiming][$source] $trigger '
      'build=${_ms(build)}ms($breakdown) '
      '$tail total=${_ms(total)}ms$size',
    );
  }

  static String _ms(int micros) => (micros / 1000).round().toString();
}
