import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/services/edge/operational_proof/client.dart';
import 'package:vynic/core/services/edge/operational_proof/domain.dart';
import 'package:vynic/core/services/edge/operational_proof/frame_store.dart';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';
ProofBinding _binding({
  int epoch = 41,
  int installation = 1,
  int venue = 2,
  int terminal = 3,
  String? grant,
}) => ProofBinding(
  installationId: _id(installation),
  venueId: _id(venue),
  terminalId: _id(terminal),
  epoch: epoch,
  grantFingerprint: grant ?? 'a' * 64,
  mode: operationalProofMode,
);

ProofKey _order([int id = 10]) => ProofKey(ProofEntityKind.order, _id(id));
ProofEntity _entity(
  int revision,
  String document, {
  ProofKey? key,
  bool tombstone = false,
}) => ProofEntity(
  key: key ?? _order(),
  revision: revision,
  tombstone: tombstone,
  document: utf8.encode(document),
);
ProofEffect _effect([int id = 500]) => ProofEffect(
  id: _id(id),
  kind: ProofEffectKind.print,
  payload: utf8.encode('SYNTHETIC FROZEN PRINT ONLY $id'),
);
ProofIntent _intent(
  ProofBinding binding, {
  int id = 100,
  int expected = 0,
  String document = '{"state":"own"}',
  List<int>? bytes,
}) => ProofIntent(
  binding: binding,
  requestId: _id(id),
  writes: [
    ProofWrite(
      key: _order(),
      expectedRevision: expected,
      tombstone: false,
      document: bytes ?? utf8.encode(document),
    ),
  ],
  effects: [_effect()],
  applicationData: utf8.encode('fixture correlation'),
);

/// The underlying Box is real temporary Hive. Only put/flush interception is
/// synthetic; no operational boxes, update workers, transport or printer exist.
class _ControlledBox implements Box<dynamic> {
  _ControlledBox(this.inner);
  final Box<dynamic> inner;
  final trace = <String>[];
  int puts = 0, flushes = 0;
  int? failPutAt, failFlushAt;
  String? nameOverride;
  Future<void> Function()? beforeFlush;
  final flushedFrames = <Map<String, dynamic>>[];
  @override
  String get name => nameOverride ?? inner.name;
  @override
  bool get isOpen => inner.isOpen;
  @override
  Iterable<dynamic> get keys => inner.keys;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    puts++;
    trace.add('put:$puts');
    if (puts == failPutAt) throw StateError('synthetic proof put failure');
    await inner.put(key, value);
  }

  @override
  Future<void> flush() async {
    flushes++;
    trace.add('flush:$flushes:before');
    await beforeFlush?.call();
    if (flushes == failFlushAt)
      throw StateError('synthetic proof flush failure');
    await inner.flush();
    trace.add('flush:$flushes:after');
    flushedFrames.add(
      Map<String, dynamic>.from(
        jsonDecode(inner.get(HiveOperationalProofFrameStore.frameKey)),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedTransport implements OperationalProofTransport {
  _ScriptedTransport(this.binding);
  final ProofBinding binding;
  final events = <ProofEvent>[];
  final results = <String, ProofResult>{};
  final requests = <ProofIntent>[];
  final replayAfter = <int>[];
  bool unavailable = false, loseNextAck = false, forceNotFound = false;
  int statusCalls = 0, snapshotCalls = 0, logicalOutcomes = 0;
  Future<ProofResult> Function(ProofIntent)? commitReply;
  ProofStatus? statusReply;
  ProofReplayPage Function(int after)? replayReply;
  ProofSnapshot Function()? snapshotReply;
  void Function(ProofIntent)? beforeCommit;
  int get head => events.isEmpty ? 0 : events.last.sequence;

  void external({
    int revision = 1,
    String document = '{"state":"external"}',
    ProofKey? key,
    int effect = 600,
    bool tombstone = false,
  }) {
    events.add(
      ProofEvent(
        binding: binding,
        sequence: head + 1,
        requestId: _id(200 + head),
        terminalId: _id(4),
        entities: [_entity(revision, document, key: key, tombstone: tombstone)],
        effects: [_effect(effect)],
      ),
    );
  }

  @override
  Future<ProofStatus> status() async {
    statusCalls++;
    if (unavailable)
      throw const SocketException('synthetic coordinator unavailable');
    return statusReply ??
        ProofStatus(
          binding: binding,
          head: head,
          protocolMajor: 1,
          protocolMinor: 3,
          capabilities: [operationalProofCapability],
          limits: ProofBounds.storeLimits,
        );
  }

  @override
  Future<ProofResultLookup> getResult({
    required String requestId,
    required int epoch,
  }) async {
    if (unavailable)
      throw const SocketException('synthetic coordinator unavailable');
    expect(epoch, binding.epoch);
    final result = results[requestId];
    return forceNotFound || result == null
        ? const ProofResultLookup.notFound()
        : ProofResultLookup.found(result);
  }

  @override
  Future<ProofResult> commit(ProofIntent intent) async {
    if (unavailable)
      throw const SocketException('synthetic coordinator unavailable');
    requests.add(intent);
    beforeCommit?.call(intent);
    var result = results[intent.requestId];
    if (result == null) {
      if (commitReply != null) {
        result = await commitReply!(intent);
      } else {
        final event = ProofEvent(
          binding: binding,
          sequence: head + 1,
          requestId: intent.requestId,
          terminalId: binding.terminalId,
          entities: [
            for (final w in intent.writes)
              ProofEntity(
                key: w.key,
                revision: w.expectedRevision + 1,
                tombstone: w.tombstone,
                document: w.document,
              ),
          ],
          effects: intent.effects,
        );
        events.add(event);
        result = ProofResult(
          binding: binding,
          requestId: intent.requestId,
          terminalId: binding.terminalId,
          outcome: ProofOutcome.committed,
          headSequence: event.sequence,
          event: event,
          applicationData: intent.applicationData,
        );
      }
      logicalOutcomes++;
      results[intent.requestId] = result;
    }
    if (loseNextAck) {
      loseNextAck = false;
      throw TimeoutException('synthetic ACK lost after durable server outcome');
    }
    return result;
  }

  @override
  Future<ProofReplayPage> replay({
    required int epoch,
    required int after,
    required int limit,
  }) async {
    if (unavailable)
      throw const SocketException('synthetic coordinator unavailable');
    expect(epoch, binding.epoch);
    replayAfter.add(after);
    if (replayReply != null) return replayReply!(after);
    final page = events.where((e) => e.sequence > after).take(limit).toList();
    return ProofReplayPage(
      binding: binding,
      after: after,
      head: head,
      next: page.isEmpty ? after : page.last.sequence,
      events: page,
    );
  }

  @override
  Future<ProofSnapshot> snapshot({required int epoch}) async {
    snapshotCalls++;
    if (unavailable)
      throw const SocketException('synthetic coordinator unavailable');
    if (snapshotReply != null) return snapshotReply!();
    final projection = <String, ProofEntity>{};
    for (final event in events) {
      for (final e in event.entities) {
        projection[e.key.value] = e;
      }
    }
    return ProofSnapshot(
      binding: binding,
      sequence: head,
      entities: projection.values.toList(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Box<dynamic> hive;
  late _ControlledBox box;
  late HiveOperationalProofFrameStore store;
  late ProofBinding binding;
  late _ScriptedTransport transport;
  late OperationalProofClient client;

  Future<void> reopen() async {
    await hive.close();
    hive = await Hive.openBox<dynamic>('isolated_operational_proof_fixture');
    box = _ControlledBox(hive);
    store = HiveOperationalProofFrameStore(box);
    client = OperationalProofClient(
      store: store,
      transport: transport,
      binding: binding,
    );
    await client.open();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_operational_proof_');
    Hive.init(root.path);
    hive = await Hive.openBox<dynamic>('isolated_operational_proof_fixture');
    box = _ControlledBox(hive);
    store = HiveOperationalProofFrameStore(box);
    binding = _binding();
    transport = _ScriptedTransport(binding);
    client = OperationalProofClient(
      store: store,
      transport: transport,
      binding: binding,
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'real Hive flush precedes transport and prepare has no optimistic projection',
    () async {
      await client.open();
      final bytes = utf8.encode('{"state":"immutable"}');
      final intent = _intent(binding, bytes: bytes);
      final fingerprint = intent.fingerprint;
      final entered = Completer<void>(), release = Completer<void>();
      box.beforeFlush = () async {
        entered.complete();
        await release.future;
      };
      final preparing = client.prepare(intent);
      await entered.future;
      final sending = client.sendPending();
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests, isEmpty);
      expect(client.pending, isNull);
      expect(client.ready, false);
      expect(client.entities, isEmpty);
      bytes[0] = 0;
      expect(intent.fingerprint, fingerprint);
      expect(() => intent.writes.first.document[0] = 0, throwsUnsupportedError);
      transport.beforeCommit = (saved) {
        expect(box.trace.last, endsWith(':after'));
        expect(
          ProofIntent.fromFrame(store.read()!['pending']).fingerprint,
          fingerprint,
        );
        expect(saved.fingerprint, fingerprint);
      };
      box.beforeFlush = null;
      release.complete();
      await preparing;
      await sending;
      expect(client.cursor, 1);
      expect(client.ready, true);
      expect(
        client.effectReceipts.single.effect.payload,
        intent.effects.single.payload,
      );
      expect(jsonEncode(store.read()), isNot(contains('credential')));
      expect(jsonEncode(store.read()), isNot(contains('terminalSecret')));
    },
  );

  test(
    'lost ACK and reopen retain exact request and never duplicate effects',
    () async {
      await client.open();
      final intent = _intent(binding);
      await client.prepare(intent);
      transport.loseNextAck = true;
      await expectLater(client.sendPending(), throwsA(isA<TimeoutException>()));
      expect(client.pending!.fingerprint, intent.fingerprint);
      expect(client.ready, false);
      expect(client.cursor, 0);
      expect(client.entities, isEmpty);
      transport.forceNotFound = true;
      await reopen();
      expect(transport.requests.map((v) => v.fingerprint), [
        intent.fingerprint,
        intent.fingerprint,
      ]);
      expect(transport.logicalOutcomes, 1);
      expect(client.cursor, 1);
      expect(client.pending, isNull);
      expect(client.effectReceipts, hasLength(1));
      expect(client.lastResult!.requestId, intent.requestId);
      expect(client.ready, true);
    },
  );

  test(
    'preceding foreign event flushes before own ACK without jumping sequence',
    () async {
      transport.external();
      await client.open();
      final intent = _intent(binding, expected: 1);
      await client.prepare(intent);
      expect(
        utf8.decode(client.entity(_order())!.document),
        '{"state":"external"}',
      );
      transport.beforeCommit = (_) {
        if (transport.head == 1)
          transport.external(
            key: ProofKey(ProofEntityKind.table, _id(20)),
            effect: 601,
          );
      };
      await client.sendPending();
      expect(client.cursor, 3);
      expect(client.entity(_order())!.revision, 2);
      expect(client.effectReceipts.map((v) => v.sequence), [1, 2, 3]);
      expect(box.flushedFrames.map((v) => v['cursor']), [
        '0',
        '1',
        '1',
        '2',
        '3',
        '3',
      ]);
      expect(client.lastResult!.event!.sequence, 3);
    },
  );

  test(
    'observed own event survives reopen and historical ACK never rewinds newer state',
    () async {
      await client.open();
      final intent = _intent(binding);
      await client.prepare(intent);
      transport.loseNextAck = true;
      await expectLater(client.sendPending(), throwsA(isA<TimeoutException>()));
      await client.catchUp();
      expect(client.pendingObservedEvent!.sequence, 1);
      transport.external(
        revision: 2,
        document: '{"state":"newer"}',
        effect: 601,
      );
      await client.catchUp();
      final observed = client.pendingObservedEvent!.fingerprint;
      expect(store.read()!['pendingObservedEvent'], isNotNull);
      await reopen();
      expect(client.pending, isNull);
      expect(client.lastResult!.event!.fingerprint, observed);
      expect(client.lastResult!.headSequence, 1);
      expect(client.cursor, 2);
      expect(
        utf8.decode(client.entity(_order())!.document),
        '{"state":"newer"}',
      );
      expect(client.effectReceipts, hasLength(2));
      expect(transport.logicalOutcomes, 1);
    },
  );

  test(
    'historical conflict is durable diagnostic data and never silently rebases',
    () async {
      transport.external();
      await client.open();
      final intent = _intent(binding, expected: 0);
      await client.prepare(intent);
      transport.commitReply = (saved) async => ProofResult(
        binding: binding,
        requestId: saved.requestId,
        terminalId: binding.terminalId,
        outcome: ProofOutcome.conflict,
        headSequence: 1,
        current: [_entity(1, '{"state":"external"}')],
      );
      transport.loseNextAck = true;
      await expectLater(client.sendPending(), throwsA(isA<TimeoutException>()));
      final exact = transport.results[intent.requestId]!.fingerprint;
      transport.external(
        revision: 2,
        document: '{"state":"newer"}',
        effect: 601,
      );
      await client.catchUp();
      await reopen();
      expect(client.lastResult!.fingerprint, exact);
      expect(client.lastResult!.outcome, ProofOutcome.conflict);
      expect(client.lastResult!.headSequence, 1);
      expect(client.lastResult!.current.single.revision, 1);
      expect(client.entity(_order())!.revision, 2);
      expect(
        utf8.decode(client.entity(_order())!.document),
        '{"state":"newer"}',
      );
      final explicit = _intent(binding, id: 101, expected: 0);
      await client.prepare(explicit);
      expect(client.pending!.writes.single.expectedRevision, 0);
      await expectLater(
        client.prepare(_intent(binding, id: 102, expected: 2)),
        throwsStateError,
      );
      expect(client.pending!.fingerprint, explicit.fingerprint);
    },
  );

  test(
    'settled conflict ID survives a later result and reopen before changed retry',
    () async {
      transport.external();
      await client.open();
      final conflicted = _intent(binding, id: 100, expected: 0);
      await client.prepare(conflicted);
      transport.commitReply = (saved) async => ProofResult(
        binding: binding,
        requestId: saved.requestId,
        terminalId: binding.terminalId,
        outcome: ProofOutcome.conflict,
        headSequence: 1,
        current: [_entity(1, '{"state":"external"}')],
      );
      await client.sendPending();
      transport.commitReply = null;
      await client.prepare(_intent(binding, id: 101, expected: 1));
      await client.sendPending();
      expect(client.lastResult!.requestId, _id(101));
      await reopen();
      final durableBefore = proofFingerprint(store.read()!);
      final writesBefore = box.puts;
      final callsBefore = transport.requests.length;
      expect((store.read()!['settled'] as List), hasLength(2));
      await expectLater(
        client.prepare(
          _intent(
            binding,
            id: 100,
            expected: 2,
            document: '{"state":"changed old conflict"}',
          ),
        ),
        throwsStateError,
      );
      await expectLater(client.prepare(conflicted), throwsStateError);
      expect(proofFingerprint(store.read()!), durableBefore);
      expect(box.puts, writesBefore);
      expect(transport.requests.length, callsBefore);
      expect(client.pending, isNull);
      expect(client.ready, true);
    },
  );

  test(
    'forged historical ACK at reached sequence must match exact observed event',
    () async {
      await client.open();
      final intent = _intent(binding);
      await client.prepare(intent);
      transport.loseNextAck = true;
      await expectLater(client.sendPending(), throwsA(isA<TimeoutException>()));
      await client.catchUp();
      final original = transport.results[intent.requestId]!;
      transport.external(
        key: ProofKey(ProofEntityKind.table, _id(20)),
        effect: 601,
      );
      await client.catchUp();
      final fake = ProofEvent(
        binding: binding,
        sequence: 2,
        requestId: intent.requestId,
        terminalId: binding.terminalId,
        entities: original.event!.entities,
        effects: original.event!.effects,
      );
      transport.results[intent.requestId] = ProofResult(
        binding: binding,
        requestId: intent.requestId,
        terminalId: binding.terminalId,
        outcome: ProofOutcome.committed,
        headSequence: 2,
        event: fake,
        applicationData: intent.applicationData,
      );
      await expectLater(client.reconcile(), throwsStateError);
      expect(client.cursor, 2);
      expect(client.pendingObservedEvent!.sequence, 1);
      expect(client.pending!.fingerprint, intent.fingerprint);
      expect(client.ready, false);
      expect(client.effectReceipts, hasLength(2));
    },
  );

  test(
    'snapshot verification bootstraps through replay zero and retains every effect',
    () async {
      transport.external();
      await client.open();
      expect(transport.replayAfter, [0]);
      expect(transport.snapshotCalls, 0);
      expect(client.effectReceipts.single.effect.payload, _effect(600).payload);
      transport.external(
        key: ProofKey(ProofEntityKind.table, _id(20)),
        effect: 601,
      );
      await client.verifySnapshot();
      expect(client.cursor, 2);
      expect(client.effectReceipts, hasLength(2));
      expect(transport.replayAfter, [0, 1]);
      expect(transport.snapshotCalls, 1);
      expect(client.ready, true);
    },
  );

  test(
    'snapshot refuses unresolved replacement without calling transport',
    () async {
      await client.open();
      final intent = _intent(binding);
      await client.prepare(intent);
      await expectLater(client.verifySnapshot(), throwsStateError);
      expect(transport.snapshotCalls, 0);
      expect(client.pending!.fingerprint, intent.fingerprint);
      expect(client.cursor, 0);
      expect(client.entities, isEmpty);
    },
  );

  test(
    'backward snapshot refuses rewind and preserves retained effects',
    () async {
      transport.external();
      await client.open();
      transport.snapshotReply = () =>
          ProofSnapshot(binding: binding, sequence: 0, entities: []);
      await expectLater(client.verifySnapshot(), throwsStateError);
      expect(client.cursor, 1);
      expect(client.effectReceipts, hasLength(1));
      expect(client.ready, false);
    },
  );

  for (final changed in [
    'installation',
    'venue',
    'terminal',
    'epoch',
    'grant',
    'protocol',
    'capability',
    'limits',
  ]) {
    test(
      'status refuses changed $changed without granting write readiness',
      () async {
        final foreign = _binding(
          installation: changed == 'installation' ? 90 : 1,
          venue: changed == 'venue' ? 90 : 2,
          terminal: changed == 'terminal' ? 90 : 3,
          epoch: changed == 'epoch' ? 42 : 41,
          grant: changed == 'grant' ? 'b' * 64 : null,
        );
        transport.statusReply = ProofStatus(
          binding: foreign,
          head: 0,
          protocolMajor: 1,
          protocolMinor: changed == 'protocol' ? 2 : 3,
          capabilities: changed == 'capability'
              ? []
              : [operationalProofCapability],
          limits: changed == 'limits' ? {} : ProofBounds.storeLimits,
        );
        await expectLater(client.open(), throwsStateError);
        expect(client.ready, false);
        expect(transport.requests, isEmpty);
        expect(hive.get(HiveOperationalProofFrameStore.frameKey), isNull);
      },
    );
  }

  test(
    'foreign result terminal is refused before any projection or effect',
    () async {
      await client.open();
      final intent = _intent(binding);
      await client.prepare(intent);
      transport.commitReply = (saved) async => ProofResult(
        binding: binding,
        requestId: saved.requestId,
        terminalId: _id(90),
        outcome: ProofOutcome.conflict,
        headSequence: 0,
        current: [
          ProofEntity(
            key: _order(),
            revision: 0,
            tombstone: false,
            document: [],
          ),
        ],
      );
      await expectLater(client.sendPending(), throwsStateError);
      expect(client.cursor, 0);
      expect(client.entities, isEmpty);
      expect(client.effectReceipts, isEmpty);
      expect(client.pending!.fingerprint, intent.fingerprint);
      expect(client.ready, false);
    },
  );

  for (final gap in ['empty', 'sequence', 'next', 'head']) {
    test('replay $gap fails closed without partial cursor advance', () async {
      transport.external();
      final original = transport.events.single;
      transport.replayReply = (after) => ProofReplayPage(
        binding: binding,
        after: after,
        head: gap == 'head' ? 0 : 1,
        next: gap == 'next'
            ? 0
            : gap == 'empty'
            ? after
            : gap == 'sequence'
            ? 2
            : 1,
        events: gap == 'empty'
            ? []
            : [
                gap == 'sequence'
                    ? ProofEvent(
                        binding: binding,
                        sequence: 2,
                        requestId: original.requestId,
                        terminalId: original.terminalId,
                        entities: original.entities,
                        effects: original.effects,
                      )
                    : original,
              ],
      );
      await expectLater(client.open(), throwsStateError);
      expect(client.cursor, 0);
      expect(client.entities, isEmpty);
      expect(client.effectReceipts, isEmpty);
      expect(client.ready, false);
    });
  }

  test(
    'malformed later revision cannot erase an earlier flushed whole event',
    () async {
      transport.external();
      transport.external(revision: 3, effect: 601);
      await expectLater(client.open(), throwsStateError);
      expect(client.cursor, 1);
      expect(client.entity(_order())!.revision, 1);
      expect(client.effectReceipts, hasLength(1));
      expect(store.read()!['cursor'], '1');
      expect(client.ready, false);
    },
  );

  for (final stage in ['put', 'flush']) {
    test('prepare $stage failure prevents send and requires reopen', () async {
      await client.open();
      if (stage == 'put')
        box.failPutAt = 2;
      else
        box.failFlushAt = 2;
      await expectLater(client.prepare(_intent(binding)), throwsStateError);
      expect(client.pending, isNull);
      expect(client.entities, isEmpty);
      expect(client.ready, false);
      await expectLater(client.sendPending(), throwsStateError);
      expect(transport.requests, isEmpty);
    });
    test(
      'result $stage failure retains committed receipt without false local ACK',
      () async {
        await client.open();
        final intent = _intent(binding);
        await client.prepare(intent);
        if (stage == 'put')
          box.failPutAt = 4;
        else
          box.failFlushAt = 4;
        await expectLater(client.sendPending(), throwsStateError);
        expect(client.cursor, 1);
        expect(client.pending!.fingerprint, intent.fingerprint);
        expect(client.pendingObservedEvent!.sequence, 1);
        expect(client.lastResult, isNull);
        expect(client.effectReceipts, hasLength(1));
        expect(client.ready, false);
        await expectLater(client.reconcile(), throwsStateError);
        await reopen();
        expect(client.lastResult!.requestId, intent.requestId);
        expect(client.pending, isNull);
        expect(client.effectReceipts, hasLength(1));
        expect(transport.logicalOutcomes, 1);
        expect(client.ready, true);
      },
    );
    test(
      'event $stage failure never publishes an uncertain in-memory projection',
      () async {
        await client.open();
        final intent = _intent(binding);
        await client.prepare(intent);
        if (stage == 'put')
          box.failPutAt = 3;
        else
          box.failFlushAt = 3;
        await expectLater(client.sendPending(), throwsStateError);
        expect(client.cursor, 0);
        expect(client.entities, isEmpty);
        expect(client.effectReceipts, isEmpty);
        expect(client.pending!.fingerprint, intent.fingerprint);
        expect(client.ready, false);
        await reopen();
        expect(client.cursor, 1);
        expect(client.effectReceipts, hasLength(1));
        expect(client.pending, isNull);
        expect(client.ready, true);
      },
    );
  }

  test(
    'unavailable coordinator preserves cache and blocks newly authored work',
    () async {
      transport.external();
      await client.open();
      final before = client.entities.map((e) => e.toFrame()).toList();
      transport.unavailable = true;
      await expectLater(client.catchUp(), throwsA(isA<SocketException>()));
      await expectLater(
        client.prepare(_intent(binding, expected: 1)),
        throwsStateError,
      );
      expect(client.entities.map((e) => e.toFrame()).toList(), before);
      expect(client.effectReceipts, hasLength(1));
      expect(client.pending, isNull);
      expect(client.ready, false);
      transport.unavailable = false;
      await client.reconcile();
      expect(client.ready, true);
    },
  );

  test(
    'dedicated frame refuses normal box identity and malformed saved state without reseeding',
    () async {
      box.nameOverride = 'meta';
      expect(() => HiveOperationalProofFrameStore(box), throwsStateError);
      box.nameOverride = null;
      await client.open();
      final corrupted = store.read()!
        ..['credential'] = 'synthetic forbidden field';
      final raw = jsonEncode(corrupted);
      await hive.put(HiveOperationalProofFrameStore.frameKey, raw);
      final other = OperationalProofClient(
        store: store,
        transport: transport,
        binding: binding,
      );
      await expectLater(other.open(), throwsFormatException);
      expect(hive.get(HiveOperationalProofFrameStore.frameKey), raw);
      expect(other.ready, false);
    },
  );

  for (final kind in ProofEntityKind.values) {
    test('explicit ${kind.name} entity roundtrips with its typed key', () {
      final entity = ProofEntity(
        key: ProofKey(kind, _id(700 + kind.index)),
        revision: 19,
        tombstone: false,
        document: utf8.encode('{"kind":"${kind.name}","complete":true}'),
      );
      final restored = ProofEntity.fromFrame(
        jsonDecode(jsonEncode(entity.toFrame())),
      );
      expect(restored.key.kind, kind);
      expect(restored.key.id, entity.key.id);
      expect(restored.revision, 19);
      expect(restored.tombstone, false);
      expect(restored.document, entity.document);
      expect(restored.toFrame(), entity.toFrame());
    });
  }

  test(
    'domain bounds, tombstones, duplicates and int64 persistence are strict',
    () {
      expect(
        () => ProofBinding(
          installationId: _id(1),
          venueId: _id(2),
          terminalId: _id(3),
          epoch: 41,
          grantFingerprint: 'a' * 64,
          mode: 'PRODUCTION',
        ),
        throwsFormatException,
      );
      final maximum = _binding(epoch: proofMaxInt64);
      expect(maximum.toFrame()['epoch'], '9223372036854775807');
      expect(ProofBinding.fromFrame(maximum.toFrame()).epoch, proofMaxInt64);
      expect(
        () => ProofBinding.fromFrame({
          ...maximum.toFrame(),
          'epoch': '9223372036854775808',
        }),
        throwsFormatException,
      );
      expect(
        () => ProofEntity(
          key: _order(),
          revision: 1,
          tombstone: true,
          document: utf8.encode('{}'),
        ),
        throwsFormatException,
      );
      expect(
        () => ProofRead(
          key: _order(),
          expectedRevision: 0,
          expectedTombstone: true,
        ),
        throwsFormatException,
      );
      expect(
        () => ProofWrite(
          key: _order(),
          expectedRevision: proofMaxInt64,
          tombstone: false,
          document: utf8.encode('{}'),
        ),
        throwsFormatException,
      );
      expect(
        () => ProofEffect(
          id: _id(500),
          kind: ProofEffectKind.print,
          payload: List.filled(ProofBounds.effectBytes + 1, 0),
        ),
        throwsFormatException,
      );
      final write = ProofWrite(
        key: _order(),
        expectedRevision: 0,
        tombstone: false,
        document: utf8.encode('{}'),
      );
      expect(
        () => ProofIntent(
          binding: binding,
          requestId: _id(100),
          writes: [write, write],
        ),
        throwsFormatException,
      );
      expect(
        () => ProofIntent(
          binding: binding,
          requestId: _id(100),
          writes: [write],
          effects: [_effect(), _effect()],
        ),
        throwsFormatException,
      );
    },
  );
}
