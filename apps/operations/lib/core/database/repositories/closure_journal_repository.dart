import 'package:uuid/uuid.dart';

import '../database_core.dart';

/// How far a closure got.
///
/// The phases are ordered and only ever move forward, so recovery can ask
/// "what still needs doing" rather than trying to guess from the wreckage.
enum ClosurePhase {
  /// The journal entry exists and states the money. Nothing else has been
  /// written yet.
  started,

  /// The sale record is in the sales box. This is the financially
  /// authoritative step — past here, the money is recorded.
  saleWritten,

  /// Order closed, tables freed, reservation completed, audit appended,
  /// daily total recomputed. Nothing left to do.
  completed;

  static ClosurePhase fromName(Object? raw) {
    final name = raw?.toString();
    for (final phase in ClosurePhase.values) {
      if (phase.name == name) return phase;
    }
    return ClosurePhase.started;
  }

  bool isAtLeast(ClosurePhase other) => index >= other.index;
}

/// One closure, as it happened.
class ClosureJournalEntry {
  const ClosureJournalEntry({
    required this.closureId,
    required this.orderId,
    required this.phase,
    required this.businessDate,
    required this.isFiscal,
    required this.grossSaleAmount,
    required this.advanceApplied,
    required this.collectedNow,
    required this.paymentMethod,
    required this.paymentBreakdown,
    required this.actorId,
    required this.startedAt,
    this.completedAt,
    this.saleRecordKey,
    this.advanceReceiptId,
    this.reversedAt,
    this.abandonedAt,
  });

  final String closureId;
  final int orderId;
  final ClosurePhase phase;
  final String businessDate;
  final bool isFiscal;
  final double grossSaleAmount;
  final double advanceApplied;
  final double collectedNow;
  final String paymentMethod;
  final Map<String, double> paymentBreakdown;
  final String actorId;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// Hive key of the sale this closure wrote. Null until [ClosurePhase.saleWritten].
  final Object? saleRecordKey;

  /// The advance receipt this closure consumed, if any.
  final String? advanceReceiptId;

  /// When the sale this closure wrote was restored back to an open table.
  ///
  /// A reversed closure is history: it stays in the journal so the lifecycle
  /// stays traceable, but it no longer blocks the order from being closed
  /// again — the re-close is a new closure with its own id.
  final DateTime? reversedAt;

  /// When recovery found this attempt had written no sale and dropped it.
  ///
  /// An abandoned attempt collected nothing, so the order it names is still
  /// open and must stay closeable — it is history, not this order's closure.
  final DateTime? abandonedAt;

  bool get isComplete => phase == ClosurePhase.completed;

  bool get isReversed => reversedAt != null;

  bool get isAbandoned => abandonedAt != null;

  /// Whether this entry still speaks for its order. A reversed or abandoned
  /// closure does not.
  bool get isLive => !isReversed && !isAbandoned;

  ClosureJournalEntry copyWith({
    ClosurePhase? phase,
    Object? saleRecordKey,
    DateTime? completedAt,
    DateTime? reversedAt,
    DateTime? abandonedAt,
  }) {
    return ClosureJournalEntry(
      closureId: closureId,
      orderId: orderId,
      phase: phase ?? this.phase,
      businessDate: businessDate,
      isFiscal: isFiscal,
      grossSaleAmount: grossSaleAmount,
      advanceApplied: advanceApplied,
      collectedNow: collectedNow,
      paymentMethod: paymentMethod,
      paymentBreakdown: paymentBreakdown,
      actorId: actorId,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      saleRecordKey: saleRecordKey ?? this.saleRecordKey,
      advanceReceiptId: advanceReceiptId,
      reversedAt: reversedAt ?? this.reversedAt,
      abandonedAt: abandonedAt ?? this.abandonedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'closureId': closureId,
    'orderId': orderId,
    'phase': phase.name,
    'businessDate': businessDate,
    'isFiscal': isFiscal,
    'grossSaleAmount': grossSaleAmount,
    'advanceApplied': advanceApplied,
    'collectedNow': collectedNow,
    'paymentMethod': paymentMethod,
    'paymentBreakdown': paymentBreakdown,
    'actorId': actorId,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (saleRecordKey != null) 'saleRecordKey': saleRecordKey,
    if (advanceReceiptId != null) 'advanceReceiptId': advanceReceiptId,
    if (reversedAt != null) 'reversedAt': reversedAt!.toIso8601String(),
    if (abandonedAt != null) 'abandonedAt': abandonedAt!.toIso8601String(),
  };

  factory ClosureJournalEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawBreakdown = map['paymentBreakdown'];
    return ClosureJournalEntry(
      closureId: map['closureId'].toString(),
      orderId: (map['orderId'] as num?)?.toInt() ?? 0,
      phase: ClosurePhase.fromName(map['phase']),
      businessDate: (map['businessDate'] as String?) ?? '',
      isFiscal: map['isFiscal'] != false,
      grossSaleAmount: (map['grossSaleAmount'] as num?)?.toDouble() ?? 0.0,
      advanceApplied: (map['advanceApplied'] as num?)?.toDouble() ?? 0.0,
      collectedNow: (map['collectedNow'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (map['paymentMethod'] as String?) ?? '',
      paymentBreakdown: rawBreakdown is Map
          ? rawBreakdown.map(
              (key, value) =>
                  MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0.0),
            )
          : <String, double>{},
      actorId: (map['actorId'] as String?) ?? '',
      startedAt:
          DateTime.tryParse((map['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: DateTime.tryParse((map['completedAt'] as String?) ?? ''),
      saleRecordKey: map['saleRecordKey'],
      advanceReceiptId: map['advanceReceiptId']?.toString(),
      reversedAt: DateTime.tryParse((map['reversedAt'] as String?) ?? ''),
      abandonedAt: DateTime.tryParse((map['abandonedAt'] as String?) ?? ''),
    );
  }
}

/// The durable record of closures in flight.
///
/// Hive gives no cross-box transaction. A close touches the order box, the
/// sales box, the table box, the reservation box and settings, and a process
/// killed between any two of them used to leave the floor and the sales
/// history disagreeing with no way to tell which had happened. Pretending
/// those writes are atomic would be a lie; instead this journal records the
/// intent before the first write and the phase after each one, so an
/// interrupted closure is a known state rather than wreckage.
///
/// Stored as plain maps, like the sales and expense boxes, so it needs no
/// type adapter and cannot break on a schema change.
class ClosureJournalRepository {
  ClosureJournalRepository._();

  static const Uuid _uuid = Uuid();

  static String newClosureId() => _uuid.v4();

  static ClosureJournalEntry? find(String closureId) {
    final raw = DatabaseCore.closureJournalBox?.get(closureId);
    if (raw is! Map) return null;
    return ClosureJournalEntry.fromMap(raw);
  }

  /// The live closure recorded for [orderId], if any.
  ///
  /// Used by the close flow to refuse a second closure of an order that has
  /// already been settled, even when the caller lost the closure id.
  ///
  /// Reversed and abandoned closures are skipped. A sale restored to the
  /// table is meant to be closed again, and an attempt that recovery found
  /// had written no sale never settled anything — neither may stand in the
  /// way of a real close.
  static ClosureJournalEntry? findByOrderId(int orderId) {
    final box = DatabaseCore.closureJournalBox;
    if (box == null) return null;
    ClosureJournalEntry? newest;
    for (final raw in box.values) {
      if (raw is! Map) continue;
      if ((raw['orderId'] as num?)?.toInt() != orderId) continue;
      final entry = ClosureJournalEntry.fromMap(raw);
      if (!entry.isLive) continue;
      if (newest == null || entry.startedAt.isAfter(newest.startedAt)) {
        newest = entry;
      }
    }
    return newest;
  }

  /// Marks a closure as undone by a restore-to-table.
  static Future<void> markReversed(String closureId) async {
    final entry = find(closureId);
    if (entry == null || entry.isReversed) return;
    await write(entry.copyWith(reversedAt: DateTime.now()));
  }

  static Future<void> write(ClosureJournalEntry entry) async {
    await DatabaseCore.closureJournalBox?.put(entry.closureId, entry.toMap());
  }

  static Future<ClosureJournalEntry> advance(
    ClosureJournalEntry entry, {
    required ClosurePhase phase,
    Object? saleRecordKey,
    DateTime? completedAt,
  }) async {
    final next = entry.copyWith(
      phase: phase,
      saleRecordKey: saleRecordKey,
      completedAt: completedAt,
    );
    await write(next);
    return next;
  }

  /// Closures that started and never finished.
  ///
  /// Ordered oldest first so recovery replays them in the order they were
  /// attempted.
  static List<ClosureJournalEntry> pending() {
    final box = DatabaseCore.closureJournalBox;
    if (box == null) return const [];
    final entries = <ClosureJournalEntry>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      final entry = ClosureJournalEntry.fromMap(raw);
      if (!entry.isComplete && entry.isLive) entries.add(entry);
    }
    entries.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return entries;
  }

  static List<ClosureJournalEntry> all() {
    final box = DatabaseCore.closureJournalBox;
    if (box == null) return const [];
    return [
      for (final raw in box.values)
        if (raw is Map) ClosureJournalEntry.fromMap(raw),
    ];
  }
}
