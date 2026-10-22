import 'dart:async';
import 'dart:convert';

import 'domain.dart';
import 'frame_store.dart';

class ProofEffectReceipt {
  ProofEffectReceipt({
    required this.effect,
    required this.sequence,
    required this.requestId,
    required this.terminalId,
    this.originInstallationId = '',
    this.printReceipt,
  }) {
    proofInteger(sequence, positive: true);
    proofRequire(
      proofUuid(requestId) && proofUuid(terminalId),
      'effect receipt identity',
    );
    proofRequire(
      originInstallationId.isEmpty || proofUuid(originInstallationId),
      'effect producer origin',
    );
    if (printReceipt != null) {
      proofRequire(proofUuid(originInstallationId), 'queued effect origin');
      printReceipt!.verify(effect);
    }
  }
  final ProofEffect effect;
  final int sequence;
  final String requestId, terminalId;
  final String originInstallationId;
  final ProofPrintReceipt? printReceipt;
  Map<String, dynamic> toFrame() => {
    'effect': effect.toFrame(),
    'sequence': '$sequence',
    'requestId': requestId,
    'terminalId': terminalId,
    if (originInstallationId.isNotEmpty)
      'originInstallationId': originInstallationId,
    if (printReceipt != null) 'printReceipt': printReceipt!.toFrame(),
  };
  factory ProofEffectReceipt.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'effect',
      'sequence',
      'requestId',
      'terminalId',
      if (raw is Map && raw.containsKey('originInstallationId'))
        'originInstallationId',
      if (raw is Map && raw.containsKey('printReceipt')) 'printReceipt',
    });
    return ProofEffectReceipt(
      effect: ProofEffect.fromFrame(b['effect']),
      sequence: proofDecimal(b['sequence']),
      requestId: b['requestId'],
      terminalId: b['terminalId'],
      originInstallationId: b['originInstallationId'] ?? '',
      printReceipt: b['printReceipt'] == null
          ? null
          : ProofPrintReceipt.fromFrame(b['printReceipt']),
    );
  }
}

class _EventReceipt {
  _EventReceipt(
    this.sequence,
    this.requestId,
    this.terminalId,
    this.fingerprint,
  );
  final int sequence;
  final String requestId, terminalId, fingerprint;
  Map<String, dynamic> toFrame() => {
    'sequence': '$sequence',
    'requestId': requestId,
    'terminalId': terminalId,
    'fingerprint': fingerprint,
  };
  factory _EventReceipt.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'sequence',
      'requestId',
      'terminalId',
      'fingerprint',
    });
    final receipt = _EventReceipt(
      proofDecimal(b['sequence']),
      b['requestId'],
      b['terminalId'],
      b['fingerprint'],
    );
    proofRequire(
      proofUuid(receipt.requestId) &&
          proofUuid(receipt.terminalId) &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(receipt.fingerprint),
      'event receipt',
    );
    return receipt;
  }
}

/// Compact identity receipts survive replacement of the displayed last result,
/// including conflicts which never appear in the event stream.
class _SettledReceipt {
  _SettledReceipt({
    required this.requestId,
    required this.intentFingerprint,
    required this.resultFingerprint,
    required this.outcome,
    required this.headSequence,
    this.eventSequence,
    this.eventFingerprint,
  });
  final String requestId, intentFingerprint, resultFingerprint;
  final ProofOutcome outcome;
  final int headSequence;
  final int? eventSequence;
  final String? eventFingerprint;

  factory _SettledReceipt.fromResult(ProofIntent intent, ProofResult result) =>
      _SettledReceipt(
        requestId: intent.requestId,
        intentFingerprint: intent.fingerprint,
        resultFingerprint: result.fingerprint,
        outcome: result.outcome,
        headSequence: result.headSequence,
        eventSequence: result.event?.sequence,
        eventFingerprint: result.event?.fingerprint,
      );

  Map<String, dynamic> toFrame() => {
    'requestId': requestId,
    'intentFingerprint': intentFingerprint,
    'resultFingerprint': resultFingerprint,
    'outcome': outcome.name,
    'headSequence': '$headSequence',
    'eventSequence': eventSequence == null ? null : '$eventSequence',
    'eventFingerprint': eventFingerprint,
  };

  factory _SettledReceipt.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'requestId',
      'intentFingerprint',
      'resultFingerprint',
      'outcome',
      'headSequence',
      'eventSequence',
      'eventFingerprint',
    });
    proofRequire(
      ProofOutcome.values.any((v) => v.name == b['outcome']),
      'settled outcome',
    );
    return _SettledReceipt(
      requestId: b['requestId'],
      intentFingerprint: b['intentFingerprint'],
      resultFingerprint: b['resultFingerprint'],
      outcome: ProofOutcome.values.byName(b['outcome']),
      headSequence: proofDecimal(b['headSequence']),
      eventSequence: b['eventSequence'] == null
          ? null
          : proofDecimal(b['eventSequence']),
      eventFingerprint: b['eventFingerprint'],
    );
  }
}

class _Frame {
  _Frame({
    required this.binding,
    this.cursor = 0,
    this.observedHead = 0,
    Map<String, ProofEntity>? entities,
    Map<String, ProofEffectReceipt>? effects,
    List<_EventReceipt>? events,
    Map<String, _SettledReceipt>? settled,
    this.pending,
    this.pendingObservedEvent,
    this.lastResult,
    this.lastIntentFingerprint,
  }) : entities = Map.of(entities ?? {}),
       effects = Map.of(effects ?? {}),
       events = List.of(events ?? []),
       settled = Map.of(settled ?? {});
  final ProofBinding binding;
  int cursor, observedHead;
  final Map<String, ProofEntity> entities;
  final Map<String, ProofEffectReceipt> effects;
  final List<_EventReceipt> events;
  final Map<String, _SettledReceipt> settled;
  ProofIntent? pending;
  ProofEvent? pendingObservedEvent;
  ProofResult? lastResult;
  String? lastIntentFingerprint;

  _Frame copy() => _Frame(
    binding: binding,
    cursor: cursor,
    observedHead: observedHead,
    entities: entities,
    effects: effects,
    events: events,
    settled: settled,
    pending: pending,
    pendingObservedEvent: pendingObservedEvent,
    lastResult: lastResult,
    lastIntentFingerprint: lastIntentFingerprint,
  );

  Map<String, dynamic> toFrame() {
    final body = <String, dynamic>{
      'formatVersion': 1,
      'binding': binding.toFrame(),
      'cursor': '$cursor',
      'observedHead': '$observedHead',
      'entities': entities.values.map((v) => v.toFrame()).toList(),
      'effects': effects.values.map((v) => v.toFrame()).toList(),
      'events': events.map((v) => v.toFrame()).toList(),
      'settled': settled.values.map((v) => v.toFrame()).toList(),
      'pending': pending?.toFrame(),
      'pendingObservedEvent': pendingObservedEvent?.toFrame(),
      'lastResult': lastResult?.toFrame(),
      'lastIntentFingerprint': lastIntentFingerprint,
    };
    body['integrity'] = proofFingerprint(body);
    return body;
  }

  factory _Frame.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'formatVersion',
      'binding',
      'cursor',
      'observedHead',
      'entities',
      'effects',
      'events',
      'settled',
      'pending',
      'pendingObservedEvent',
      'lastResult',
      'lastIntentFingerprint',
      'integrity',
    });
    final integrity = b.remove('integrity');
    proofRequire(
      b['formatVersion'] == 1 && integrity == proofFingerprint(b),
      'frame version/integrity',
    );
    final entities = proofList(b['entities'], ProofEntity.fromFrame);
    final effects = proofList(b['effects'], ProofEffectReceipt.fromFrame);
    final settled = proofList(b['settled'], _SettledReceipt.fromFrame);
    proofUnique(entities, (v) => v.key.value);
    proofUnique(effects, (v) => v.effect.id);
    proofUnique(settled, (v) => v.requestId);
    final frame = _Frame(
      binding: ProofBinding.fromFrame(b['binding']),
      cursor: proofDecimal(b['cursor']),
      observedHead: proofDecimal(b['observedHead']),
      entities: {for (final e in entities) e.key.value: e},
      effects: {for (final e in effects) e.effect.id: e},
      events: proofList(b['events'], _EventReceipt.fromFrame),
      settled: {for (final r in settled) r.requestId: r},
      pending: b['pending'] == null
          ? null
          : ProofIntent.fromFrame(b['pending']),
      pendingObservedEvent: b['pendingObservedEvent'] == null
          ? null
          : ProofEvent.fromFrame(b['pendingObservedEvent']),
      lastResult: b['lastResult'] == null
          ? null
          : ProofResult.fromFrame(b['lastResult']),
      lastIntentFingerprint: b['lastIntentFingerprint'],
    );
    frame.validate();
    return frame;
  }

  void validate() {
    proofInteger(cursor);
    proofInteger(observedHead);
    proofRequire(
      observedHead >= cursor &&
          events.length == cursor &&
          events.length <= ProofBounds.events,
      'contiguous retained event history',
    );
    proofRequire(
      entities.length <= ProofBounds.entities &&
          effects.length <= ProofBounds.effects &&
          entities.values.fold<int>(0, (n, e) => n + e.document.length) <=
              ProofBounds.stateBytes,
      'retained frame capacity',
    );
    proofRequire(
      entities.values.every((e) => e.revision > 0 && e.revision <= cursor),
      'committed entity revision',
    );
    final ids = <String>{};
    for (var i = 0; i < events.length; i++) {
      proofRequire(
        events[i].sequence == i + 1 && ids.add(events[i].requestId),
        'event receipt sequence/identity',
      );
    }
    final knownRequestIds = <String>{...ids, ...settled.keys};
    if (pending != null) knownRequestIds.add(pending!.requestId);
    proofRequire(
      settled.length <= ProofBounds.storeRequests &&
          knownRequestIds.length <= ProofBounds.storeRequests,
      'retained request capacity',
    );
    final fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');
    for (final receipt in settled.values) {
      proofRequire(
        proofUuid(receipt.requestId) &&
            fingerprintPattern.hasMatch(receipt.intentFingerprint) &&
            fingerprintPattern.hasMatch(receipt.resultFingerprint) &&
            receipt.headSequence <= cursor &&
            pending?.requestId != receipt.requestId,
        'settled request identity',
      );
      if (receipt.outcome == ProofOutcome.committed) {
        proofRequire(
          receipt.eventSequence != null &&
              receipt.eventSequence! > 0 &&
              receipt.eventSequence == receipt.headSequence &&
              receipt.eventSequence! <= cursor &&
              receipt.eventFingerprint != null,
          'settled committed event sequence',
        );
        final event = events[receipt.eventSequence! - 1];
        proofRequire(
          event.requestId == receipt.requestId &&
              event.terminalId == binding.terminalId &&
              event.fingerprint == receipt.eventFingerprint,
          'settled committed event receipt',
        );
      } else {
        proofRequire(
          receipt.eventSequence == null &&
              receipt.eventFingerprint == null &&
              !ids.contains(receipt.requestId),
          'settled conflict has no event',
        );
      }
    }
    for (final effect in effects.values) {
      proofRequire(effect.sequence <= cursor, 'effect cursor');
      final event = events[effect.sequence - 1];
      proofRequire(
        event.requestId == effect.requestId &&
            event.terminalId == effect.terminalId,
        'effect origin',
      );
    }
    if (pending != null) {
      proofRequire(
        pending!.binding.fingerprint == binding.fingerprint,
        'pending binding',
      );
    }
    if (pendingObservedEvent != null) {
      final e = pendingObservedEvent!;
      proofRequire(
        pending != null &&
            e.binding.fingerprint == binding.fingerprint &&
            e.requestId == pending!.requestId &&
            e.terminalId == binding.terminalId &&
            e.printAdmission == pending!.printAdmission &&
            e.originInstallationId == pending!.originInstallationId &&
            e.sequence <= cursor,
        'pending own event',
      );
      proofRequire(
        events[e.sequence - 1].fingerprint == e.fingerprint,
        'pending event receipt mismatch',
      );
    }
    proofRequire(
      (lastResult == null) == (lastIntentFingerprint == null),
      'result request receipt',
    );
    if (lastResult != null) {
      final receipt = settled[lastResult!.requestId];
      proofRequire(
        lastResult!.binding.fingerprint == binding.fingerprint &&
            lastResult!.terminalId == binding.terminalId &&
            lastResult!.headSequence <= cursor &&
            fingerprintPattern.hasMatch(lastIntentFingerprint!) &&
            receipt != null &&
            receipt.intentFingerprint == lastIntentFingerprint &&
            receipt.resultFingerprint == lastResult!.fingerprint,
        'durable result identity',
      );
    }
    proofRequire(
      utf8.encode(jsonEncode(toFrame())).length <= ProofBounds.frameBytes,
      'encoded frame bound',
    );
  }
}

/// Isolated proof only. Caller owns one dedicated frame store/client and its
/// authenticated transport. There is no production startup, projection box,
/// printer worker, authority election, mutable rebase or wire adapter here.
class OperationalProofClient {
  OperationalProofClient({
    required this.store,
    required this.transport,
    required this.binding,
  });
  final OperationalProofFrameStore store;
  final OperationalProofTransport transport;
  final ProofBinding binding;
  _Frame? _frame;
  Future<void> _tail = Future.value();
  bool _healthy = false, _reopenRequired = false, _busy = false;
  String? failure;
  bool get ready =>
      _healthy &&
      !_busy &&
      !_reopenRequired &&
      pending == null &&
      _frame?.cursor == _frame?.observedHead;
  int get cursor => _frame?.cursor ?? 0;
  ProofIntent? get pending => _frame?.pending;
  ProofEvent? get pendingObservedEvent => _frame?.pendingObservedEvent;
  ProofResult? get lastResult => _frame?.lastResult;
  List<ProofEntity> get entities =>
      List.unmodifiable(_frame?.entities.values ?? <ProofEntity>[]);
  List<ProofEffectReceipt> get effectReceipts =>
      List.unmodifiable(_frame?.effects.values ?? <ProofEffectReceipt>[]);
  ProofEntity? entity(ProofKey key) => _frame?.entities[key.value];

  Future<T> _serial<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await previous;
      _busy = true;
      try {
        return await action();
      } finally {
        _busy = false;
        done.complete();
      }
    }();
  }

  void _guard() {
    if (_reopenRequired)
      throw StateError('Isolated proof requires reopen: $failure');
    if (_frame == null) throw StateError('Isolated proof client is unopened');
  }

  Never _refuse(String detail) {
    _healthy = false;
    _reopenRequired = true;
    failure = detail;
    throw StateError('Isolated proof refused: $detail');
  }

  void _sameBinding(ProofBinding candidate) {
    if (candidate.fingerprint != binding.fingerprint)
      _refuse('proof binding changed');
  }

  Future<T> _network<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      _healthy = false;
      failure = 'Proof transport unavailable or refused: $error';
      rethrow;
    }
  }

  Future<void> _save(_Frame next) async {
    try {
      next.validate();
      await store.writeAndFlush(next.toFrame());
      _frame = next;
    } catch (error) {
      _healthy = false;
      _reopenRequired = true;
      failure = 'Proof frame persistence/validation failed: $error';
      rethrow;
    }
  }

  Future<ProofStatus> _status() async {
    final status = await _network(transport.status);
    _sameBinding(status.binding);
    if (status.protocolMajor != 1 ||
        status.protocolMinor != 3 ||
        !status.capabilities.contains(operationalProofCapability) ||
        (binding.originInstallationId.isNotEmpty &&
            !status.capabilities.contains(operationalProofPrintCapability)) ||
        status.limits.length != ProofBounds.storeLimits.length ||
        ProofBounds.storeLimits.entries.any(
          (e) => status.limits[e.key] != e.value,
        ) ||
        status.head < cursor ||
        status.head < _frame!.observedHead) {
      _refuse('incompatible proof status, limits or backward head');
    }
    return status;
  }

  Future<void> open() => _serial(() async {
    if (_frame != null)
      throw StateError(
        'Proof client already opened; reconcile or construct a new instance',
      );
    try {
      final stored = store.read();
      _frame = stored == null
          ? _Frame(binding: binding)
          : _Frame.fromFrame(stored);
      _sameBinding(_frame!.binding);
      await _reconcile();
    } catch (error) {
      _healthy = false;
      failure ??= 'Proof open failed: $error';
      rethrow;
    }
  });

  Future<void> reconcile() => _serial(() async {
    _guard();
    await _reconcile();
  });

  Future<void> _reconcile() async {
    final status = await _status();
    // Initial history always comes from zero; snapshots have no effect history.
    if (store.read() == null) await _save(_frame!.copy());
    await _catchUp(status.head);
    if (pending != null) {
      final lookup = await _network(
        () => transport.getResult(
          requestId: pending!.requestId,
          epoch: binding.epoch,
        ),
      );
      if (lookup.found) {
        if (lookup.result == null) _refuse('found lookup has no typed result');
        await _accept(lookup.result!);
      } else {
        if (lookup.result != null)
          _refuse('not-found lookup contains a result');
        await _commitPending();
      }
    }
    _healthy = true;
    failure = null;
  }

  Future<void> prepare(ProofIntent intent) => _serial(() async {
    _guard();
    _sameBinding(intent.binding);
    if (pending != null) {
      if (pending!.fingerprint != intent.fingerprint)
        throw StateError(
          'One immutable unresolved proof intent is already retained',
        );
      return;
    }
    if (!_healthy || _frame!.cursor != _frame!.observedHead)
      throw StateError(
        'Proof coordinator must reconcile before preparing shared work',
      );
    if (_frame!.settled.containsKey(intent.requestId) ||
        _frame!.events.any((e) => e.requestId == intent.requestId)) {
      throw StateError('Proof request identity already has a durable outcome');
    }
    if ({
          ..._frame!.events.map((e) => e.requestId),
          ..._frame!.settled.keys,
        }.length >=
        ProofBounds.storeRequests) {
      throw StateError('Isolated proof retained request capacity exhausted');
    }
    final next = _frame!.copy()..pending = intent;
    await _save(next); // No optimistic entity/effect changes.
  });

  Future<ProofResult> sendPending() => _serial(() async {
    _guard();
    if (!_healthy)
      throw StateError(
        'Reconcile the proof transport before retrying retained work',
      );
    return _commitPending();
  });

  Future<ProofResult> _commitPending() async {
    final intent = pending;
    if (intent == null) throw StateError('No durable proof intent');
    final result = await _network(() => transport.commit(intent));
    await _accept(result);
    return result;
  }

  Future<void> catchUp() => _serial(() async {
    _guard();
    final status = await _status();
    await _catchUp(status.head);
    _healthy = true;
    failure = null;
  });

  Future<void> _catchUp(int target) async {
    var observedHead = _frame!.observedHead;
    while (cursor < target) {
      final after = cursor;
      final page = await _network(
        () => transport.replay(
          epoch: binding.epoch,
          after: after,
          limit: ProofBounds.replayEvents,
        ),
      );
      _sameBinding(page.binding);
      if (page.after != after ||
          page.head < target ||
          page.head < observedHead ||
          page.next > page.head ||
          page.events.isEmpty ||
          page.next != page.events.last.sequence) {
        _refuse('replay head/cursor/gap mismatch');
      }
      observedHead = page.head;
      var expected = after + 1;
      for (final event in page.events) {
        _sameBinding(event.binding);
        if (event.sequence != expected++ || event.sequence > page.head)
          _refuse('noncontiguous replay');
      }
      for (final event in page.events.takeWhile((e) => e.sequence <= target)) {
        await _apply(event, observedHead);
      }
    }
  }

  Future<void> _apply(ProofEvent event, int observedHead) async {
    if (event.sequence != cursor + 1 ||
        _frame!.events.any((e) => e.requestId == event.requestId) ||
        _frame!.settled.containsKey(event.requestId)) {
      _refuse('event sequence or request identity reused');
    }
    final next = _frame!.copy();
    for (final entity in event.entities) {
      final previous = next.entities[entity.key.value];
      if (previous?.tombstone == true ||
          entity.revision != (previous?.revision ?? 0) + 1 ||
          (previous == null && entity.tombstone))
        _refuse('entity revision gap or tombstone resurrection');
      next.entities[entity.key.value] = entity;
    }
    for (final effect in event.effects) {
      if (next.effects.containsKey(effect.id))
        _refuse('effect identity reused by another event');
      next.effects[effect.id] = ProofEffectReceipt(
        effect: effect,
        sequence: event.sequence,
        requestId: event.requestId,
        terminalId: event.terminalId,
        originInstallationId: event.originInstallationId,
        printReceipt: event.printReceipts
            .where((r) => r.effectId == effect.id)
            .firstOrNull,
      );
    }
    if (pending?.requestId == event.requestId) {
      if (event.terminalId != binding.terminalId)
        _refuse('pending request belongs to another terminal');
      _ownEvent(event, pending!);
      next.pendingObservedEvent = event;
    }
    next.events.add(
      _EventReceipt(
        event.sequence,
        event.requestId,
        event.terminalId,
        event.fingerprint,
      ),
    );
    next.cursor = event.sequence;
    next.observedHead = observedHead;
    await _save(
      next,
    ); // Whole event, postimages, effects and cursor flush together.
  }

  void _ownEvent(ProofEvent event, ProofIntent intent) {
    _sameBinding(event.binding);
    if (event.requestId != intent.requestId ||
        event.terminalId != binding.terminalId ||
        event.printAdmission != intent.printAdmission ||
        event.originInstallationId != intent.originInstallationId ||
        event.entities.length != intent.writes.length ||
        event.effects.length != intent.effects.length) {
      _refuse('own event identity/postimage count mismatch');
    }
    final expected = {
      for (final w in intent.writes)
        w.key.value: ProofEntity(
          key: w.key,
          revision: w.expectedRevision + 1,
          tombstone: w.tombstone,
          document: w.document,
        ),
    };
    for (final e in event.entities) {
      final wanted = expected[e.key.value];
      if (wanted == null ||
          proofFingerprint(wanted.toFrame()) != proofFingerprint(e.toFrame())) {
        _refuse('own event changed frozen postimage/revision');
      }
    }
    if (jsonEncode(event.effects.map((e) => e.toFrame()).toList()) !=
        jsonEncode(intent.effects.map((e) => e.toFrame()).toList()))
      _refuse('own event changed frozen effects');
  }

  Future<void> _accept(ProofResult result) async {
    final intent = pending;
    if (intent == null) _refuse('result without a retained intent');
    _sameBinding(result.binding);
    if (result.requestId != intent.requestId ||
        result.terminalId != binding.terminalId ||
        result.printAdmission != intent.printAdmission ||
        result.originInstallationId != intent.originInstallationId) {
      _refuse('result request/terminal changed');
    }
    if (result.outcome == ProofOutcome.committed) {
      final event = result.event!;
      _ownEvent(event, intent);
      if (base64Encode(result.applicationData) !=
          base64Encode(intent.applicationData)) {
        _refuse('result application data changed');
      }
      await _catchUp(event.sequence);
      final observed = pendingObservedEvent;
      if (observed == null || observed.fingerprint != event.fingerprint) {
        _refuse('ACK does not match exact durably observed own event');
      }
    } else {
      if (pendingObservedEvent != null)
        _refuse('conflict contradicts an observed committed own event');
      final touched = {
        ...intent.reads.map((v) => v.key.value),
        ...intent.writes.map((v) => v.key.value),
      };
      if (result.current.length != touched.length ||
          !result.current.every((e) => touched.contains(e.key.value))) {
        _refuse('conflict omitted/changed dependency preimages');
      }
      await _catchUp(result.headSequence);
      if (pendingObservedEvent != null)
        _refuse('conflict replay contains committed own event');
      // Historical preimages are diagnostics. They never enter the projection.
    }
    final next = _frame!.copy()
      ..lastResult = result
      ..lastIntentFingerprint = intent.fingerprint
      ..pending = null
      ..pendingObservedEvent = null;
    next.settled[intent.requestId] = _SettledReceipt.fromResult(intent, result);
    await _save(next);
  }

  Future<void> verifySnapshot() => _serial(() async {
    _guard();
    if (!_healthy || pending != null)
      throw StateError(
        'Resolve retained proof work before snapshot verification',
      );
    final snapshot = await _network(
      () => transport.snapshot(epoch: binding.epoch),
    );
    _sameBinding(snapshot.binding);
    if (snapshot.sequence < cursor) _refuse('backward snapshot');
    await _catchUp(snapshot.sequence);
    final actual = {
      for (final e in entities) e.key.value: proofFingerprint(e.toFrame()),
    };
    if (snapshot.entities.length != actual.length ||
        snapshot.entities.any(
          (e) => actual[e.key.value] != proofFingerprint(e.toFrame()),
        )) {
      _refuse('snapshot differs from replayed committed projection');
    }
    // No cursor jump, entity replacement, effect loss or authority admission.
  });
}
