import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/operational_proof/client.dart';
import 'package:vynic/core/services/edge/operational_proof/domain.dart';
import 'package:vynic/core/services/edge/operational_proof/frame_store.dart';
import 'package:vynic/core/services/edge/operational_proof/intent_adapter.dart';
import 'package:vynic/core/services/edge/operational_proof/ordinary_planner.dart';
import 'package:vynic/core/services/edge/operational_proof/planning_view.dart';

String _id(int number) =>
    '00000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}';
ProofKey _key(ProofEntityKind kind, int number) => ProofKey(kind, _id(number));
final _control = _key(ProofEntityKind.operationalControl, 1),
    _day = _key(ProofEntityKind.day, 2),
    _policy = _key(ProofEntityKind.operationalPolicy, 3),
    _actor = _key(ProofEntityKind.staff, 4),
    _approver = _key(ProofEntityKind.staff, 5),
    _table7 = _key(ProofEntityKind.table, 10),
    _table8 = _key(ProofEntityKind.table, 11),
    _booking = _key(ProofEntityKind.reservation, 50),
    _package = _key(ProofEntityKind.package, 60);

class _Fixture {
  _Fixture({
    this.request = 100,
    this.terminal = 3,
    this.newId = 20,
    this.rate = .2,
    this.approval = false,
    List<ProofEntity>? rows,
    int? cursor,
    List<OperationalIdentity> extraIdentities = const [],
  }) {
    binding = ProofBinding(
      installationId: _id(901),
      venueId: _id(902),
      terminalId: _id(terminal),
      epoch: 41,
      grantFingerprint: 'a' * 64,
      mode: operationalProofMode,
    );
    orderKey = _key(ProofEntityKind.order, newId);
    reportKey = _key(ProofEntityKind.auditReport, newId + 10);
    saleKey = _key(ProofEntityKind.sale, 40);
    identities = OperationalIdentityResolver(
      identities: [
        ...extraIdentities,
        OperationalIdentity(
          key: _control,
          store: 'operationalControl',
          legacyKey: 'venue-control',
        ),
        OperationalIdentity(
          key: _day,
          store: 'businessDays',
          legacyKey: '2026-10-06',
        ),
        OperationalIdentity(
          key: _policy,
          store: 'operationalPolicy',
          legacyKey: 'admitted-policy',
        ),
        OperationalIdentity(
          key: _actor,
          store: 'staff',
          legacyKey: 'waiter',
          legacyId: 'waiter',
        ),
        OperationalIdentity(
          key: _approver,
          store: 'staff',
          legacyKey: 'manager',
          legacyId: 'manager',
        ),
        OperationalIdentity(
          key: _table7,
          store: 'tables',
          legacyKey: 17,
          tableRef: 'first/7',
        ),
        OperationalIdentity(
          key: _table8,
          store: 'tables',
          legacyKey: 18,
          tableRef: 'first/8',
        ),
        OperationalIdentity(
          key: orderKey,
          store: 'orders',
          legacyKey: 900,
          orderNumber: 1,
          legacyId: orderKey.id,
        ),
        OperationalIdentity(
          key: reportKey,
          store: 'auditReport',
          legacyKey: AuditRepository.buildAuditReportKey(1),
        ),
        OperationalIdentity(
          key: saleKey,
          store: 'sales',
          legacyKey: '${_id(request)}:cancelled-sale',
          legacyId: saleKey.id,
        ),
        OperationalIdentity(
          key: _booking,
          store: 'reservation',
          legacyKey: 777,
          legacyId: 'legacy-booking',
        ),
        OperationalIdentity(
          key: _package,
          store: 'packages',
          legacyKey: 'legacy-package',
          legacyId: 'legacy-package',
        ),
      ],
      auditEffectIds: {
        '${_id(request)}:created': _id(request + 1000),
        '${_id(request)}:reservation': _id(request + 2000),
      },
    );
    entities =
        rows ??
        [
          entity(_control, {
            'lastOrderId': 0,
            'currentDayId': _day.id,
            'phase': 'operational',
            'recoveryGeneration': 0,
          }),
          entity(_day, {'date': '2026-10-06', 'status': 'open'}),
          entity(_policy, {
            'serviceFeeRate': rate,
            'defaultIncludeServiceFee': true,
            'cancelRequiresApproval': approval,
            'menuRevision': 7,
            'menuFingerprint': 'b' * 64,
            'inventoryRevision': 4,
            'runtimeFingerprint': 'c' * 64,
          }),
          entity(_actor, {
            'username': 'waiter',
            'enabled': true,
            'permissions': ['create', 'move', 'cancel'],
          }),
          entity(_approver, {
            'username': 'manager',
            'enabled': true,
            'permissions': ['approveCancel'],
          }),
          entity(
            _table7,
            OrderTableMutationRepository.tableImage(
              TableModel(tableNumber: '7', floor: 'first'),
            ),
          ),
          entity(
            _table8,
            OrderTableMutationRepository.tableImage(
              TableModel(tableNumber: '8', floor: 'first'),
            ),
          ),
        ];
    view = OperationalPlanningView(
      binding: binding,
      cursor: cursor ?? 1,
      context: OperationalPlanningContext(
        requestId: _id(request),
        actorId: 'waiter',
        actorName: 'Waiter Example',
        occurredAt: DateTime.utc(2026, 10, 6, 12, request - 100),
        source: AuditSource.pos,
      ),
      identities: identities,
      controlKey: _control,
      dayKey: _day,
      policyKey: _policy,
      actorKey: _actor,
      entities: entities,
      retainedEffectIds: {},
    );
  }
  final int request, terminal, newId;
  final double rate;
  final bool approval;
  late ProofBinding binding;
  late ProofKey orderKey, reportKey, saleKey;
  late List<ProofEntity> entities;
  late OperationalIdentityResolver identities;
  late OperationalPlanningView view;
  ProofEntity entity(
    ProofKey key,
    Map<String, dynamic> body, {
    int revision = 1,
  }) => ProofEntity(
    key: key,
    revision: revision,
    tombstone: false,
    document: OperationalPlanningView.encodeDocument(
      binding: binding,
      key: key,
      business: body,
    ),
  );
  OperationalCreateCommand command({bool takeaway = false}) =>
      OperationalCreateCommand(
        orderKey: orderKey,
        floor: takeaway ? 'takeaway' : 'first',
        tables: takeaway ? [] : ['7'],
        items: [
          {
            'lineUuid': _id(70),
            'itemKey': 'synthetic',
            'itemName': 'Frozen fixture',
            'unitPrice': 2.5,
            'quantity': 4,
            'total': 10.01,
            'comment': 'frozen',
            'menuItemId': 'menu-fixture',
            'variantId': 'variant-fixture',
          },
        ],
        menuRevision: 7,
        menuFingerprint: 'b' * 64,
        customerName: 'Synthetic guest',
        customerPhone: '-',
        pickupTime: '12:30',
      );
  Map<String, dynamic> business(ProofWrite write) => Map<String, dynamic>.from(
    jsonDecode(utf8.decode(write.document))['business'],
  );
  List<ProofEntity> applied(OperationalAdaptedPlan plan) {
    final map = {for (final row in entities) row.key.value: row};
    for (final write in plan.intent.writes)
      map[write.key.value] = ProofEntity(
        key: write.key,
        revision: write.expectedRevision + 1,
        tombstone: write.tombstone,
        document: write.document,
      );
    return map.values.toList();
  }

  Map<String, dynamic> booking() => {
    'id': 'legacy-booking',
    'customerName': 'Synthetic booking',
    'customerPhone': '-',
    'tableNumbers': [7],
    'tableRefs': ['first/7'],
    'reservationDate': '2026-10-06T00:00:00.000Z',
    'reservationTime': '12:00',
    'numberOfGuests': 2,
    'notes': 'real advance booking',
    'createdAt': '2026-10-01T12:00:00.000Z',
    'createdBy': 'waiter',
    'status': 'in-progress',
    'preOrderItems': null,
    'isTakeAway': false,
    'linkedOrderId': 1,
  };
}

Map<String, dynamic> _journal(
  OperationalAdaptedPlan plan,
  void Function(Map<String, dynamic>) edit,
) {
  final body = OrderTransferIntent.cloneMap(plan.journal)..remove('digest');
  edit(body);
  body['fingerprint'] = PosBackupFormat.digest(body['request']);
  return OrderTableMutationIntent(body).toMap();
}

Matcher _fails(OperationalPlanningFailureCode code) => throwsA(
  isA<OperationalPlanningFailure>().having((e) => e.code, 'code', code),
);

class _MemoryFrame implements OperationalProofFrameStore {
  Map<String, dynamic>? frame;
  int writes = 0;
  @override
  Map<String, dynamic>? read() =>
      frame == null ? null : OrderTransferIntent.cloneMap(frame!);
  @override
  Future<void> writeAndFlush(Map<String, dynamic> value) async {
    writes++;
    frame = OrderTransferIntent.cloneMap(value);
  }
}

/// CAS is synthetic here. It deliberately retains exact successes/conflicts and
/// atomically publishes all writes/effects; it is not a Go/RPC/LAN qualification.
class _ScriptedCoordinator {
  _ScriptedCoordinator(List<ProofEntity> seed, ProofBinding binding) {
    entities.addAll({for (final e in seed) e.key.value: e});
    events.add(
      ProofEvent(
        binding: binding,
        sequence: 1,
        requestId: _id(800),
        terminalId: _id(99),
        entities: seed,
      ),
    );
  }
  final entities = <String, ProofEntity>{},
      results = <String, ProofResult>{},
      requests = <String, ProofIntent>{};
  final events = <ProofEvent>[], effects = <ProofEffect>[];
  final attempts = <String>[];
  int logicalCommits = 0;
  ProofEntity current(ProofKey key) =>
      entities[key.value] ??
      ProofEntity(key: key, revision: 0, tombstone: false, document: []);
  ProofResult commit(ProofIntent intent) {
    attempts.add(intent.fingerprint);
    if (results.containsKey(intent.requestId)) {
      expect(requests[intent.requestId]!.fingerprint, intent.fingerprint);
      return results[intent.requestId]!;
    }
    final touched = {
      for (final r in intent.reads) r.key.value: r.key,
      for (final w in intent.writes) w.key.value: w.key,
    };
    final conflict =
        intent.reads.any(
          (r) =>
              current(r.key).revision != r.expectedRevision ||
              current(r.key).tombstone != r.expectedTombstone,
        ) ||
        intent.writes.any(
          (w) =>
              current(w.key).revision != w.expectedRevision ||
              current(w.key).tombstone,
        );
    final result = conflict
        ? ProofResult(
            binding: intent.binding,
            requestId: intent.requestId,
            terminalId: intent.binding.terminalId,
            outcome: ProofOutcome.conflict,
            headSequence: events.last.sequence,
            current: touched.values.map(current).toList(),
          )
        : _publish(intent);
    results[intent.requestId] = result;
    requests[intent.requestId] = intent;
    return result;
  }

  ProofResult _publish(ProofIntent intent) {
    final rows = [
      for (final w in intent.writes)
        ProofEntity(
          key: w.key,
          revision: w.expectedRevision + 1,
          tombstone: w.tombstone,
          document: w.document,
        ),
    ];
    final event = ProofEvent(
      binding: intent.binding,
      sequence: events.last.sequence + 1,
      requestId: intent.requestId,
      terminalId: intent.binding.terminalId,
      entities: rows,
      effects: intent.effects,
    );
    for (final row in rows) entities[row.key.value] = row;
    effects.addAll(event.effects);
    events.add(event);
    logicalCommits++;
    return ProofResult(
      binding: intent.binding,
      requestId: intent.requestId,
      terminalId: intent.binding.terminalId,
      outcome: ProofOutcome.committed,
      headSequence: event.sequence,
      event: event,
      applicationData: intent.applicationData,
    );
  }
}

class _Transport implements OperationalProofTransport {
  _Transport(this.server, this.binding);
  final _ScriptedCoordinator server;
  final ProofBinding binding;
  bool loseAck = false, notFoundOnce = false;
  int calls = 0;
  ProofEvent event(ProofEvent old) => ProofEvent(
    binding: binding,
    sequence: old.sequence,
    requestId: old.requestId,
    terminalId: old.terminalId,
    entities: old.entities,
    effects: old.effects,
  );
  @override
  Future<ProofStatus> status() async => ProofStatus(
    binding: binding,
    head: server.events.last.sequence,
    protocolMajor: 1,
    protocolMinor: 3,
    capabilities: [operationalProofCapability],
    limits: ProofBounds.storeLimits,
  );
  @override
  Future<ProofResult> commit(ProofIntent intent) async {
    calls++;
    final result = server.commit(intent);
    if (loseAck) {
      loseAck = false;
      throw const SocketException('synthetic ACK lost');
    }
    return result;
  }

  @override
  Future<ProofResultLookup> getResult({
    required String requestId,
    required int epoch,
  }) async {
    if (notFoundOnce) {
      notFoundOnce = false;
      return const ProofResultLookup.notFound();
    }
    final result = server.results[requestId];
    return result == null
        ? const ProofResultLookup.notFound()
        : ProofResultLookup.found(result);
  }

  @override
  Future<ProofReplayPage> replay({
    required int epoch,
    required int after,
    required int limit,
  }) async {
    final page = server.events
        .where((e) => e.sequence > after)
        .take(limit)
        .map(event)
        .toList();
    return ProofReplayPage(
      binding: binding,
      after: after,
      head: server.events.last.sequence,
      next: page.isEmpty ? after : page.last.sequence,
      events: page,
    );
  }

  @override
  Future<ProofSnapshot> snapshot({required int epoch}) async => ProofSnapshot(
    binding: binding,
    sequence: server.events.last.sequence,
    entities: server.entities.values.toList(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    expect(DatabaseCore.orderBox, isNull);
    expect(DatabaseCore.tableBox, isNull);
    expect(DatabaseCore.settingsBox, isNull);
    expect(DatabaseCore.salesBox, isNull);
    expect(DatabaseCore.auditLogBox, isNull);
    expect(DatabaseCore.reservationBox, isNull);
    Order.serviceFeeRateResolver = () =>
        throw StateError('Detached plans must never use global fee');
    Order.timestampResolver = () =>
        throw StateError('Detached plans must never use global clock');
  });
  tearDown(() {
    Order.serviceFeeRateResolver = null;
    Order.timestampResolver = null;
  });

  test(
    'create preserves frozen totals and all legacy effects with control, report and canonical references',
    () {
      final f = _Fixture(),
          plan = OrdinaryOperationalPlanner.create(f.view, f.command());
      final decoded = OrderTableMutationIntent.decode(
        plan.journal,
        serviceFeeRate: f.rate,
      );
      expect(decoded.kind, 'create');
      expect(plan.outcome.orderNumber, 1);
      expect(plan.outcome.orderId, f.orderKey.id);
      expect(plan.outcome.order['totalAmount'], 12.01);
      expect(plan.outcome.order['items'][0]['total'], 10.01);
      expect(plan.intent.writes.map((w) => w.key.kind).toSet(), {
        ProofEntityKind.order,
        ProofEntityKind.table,
        ProofEntityKind.auditReport,
        ProofEntityKind.operationalControl,
      });
      expect(plan.intent.effects.single.kind, ProofEffectKind.audit);
      expect(
        f.business(
          plan.intent.writes.singleWhere((w) => w.key.value == _control.value),
        )['lastOrderId'],
        1,
      );
      final table = jsonDecode(
        utf8.decode(
          plan.intent.writes
              .singleWhere((w) => w.key.value == _table7.value)
              .document,
        ),
      );
      expect(table['references']['/activeOrderId'].single['id'], f.orderKey.id);
      expect(table['references']['/reservedBy'].single['id'], _actor.id);
      expect(
        plan.intent.reads
            .singleWhere((r) => r.key.value == _control.value)
            .expectedRevision,
        1,
      );
      expect(
        jsonDecode(utf8.decode(plan.intent.applicationData))['type'],
        'ORDINARY_ORDER_MUTATION',
      );
      expect(
        () => plan.outcome.order['items'][0]['total'] = 0,
        throwsUnsupportedError,
      );
      expect(f.view.business(_control)['lastOrderId'], 0);
    },
  );
  test(
    'takeaway keeps no fee and virtual table label binds only to Order through create/cancel',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(
            f.view,
            f.command(takeaway: true),
          );
      expect(create.outcome.order['includeServiceFee'], false);
      expect(create.outcome.order['openedByUserId'], isNull);
      expect(create.outcome.order['totalAmount'], 10.01);
      expect(create.journal['request'].containsKey('includeServiceFee'), false);
      expect(
        create.intent.writes.where((w) => w.key.kind == ProofEntityKind.table),
        isEmpty,
      );
      final c = _Fixture(request: 101, rows: f.applied(create), cursor: 2);
      final cancel = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
      );
      expect(
        cancel.intent.writes.where((w) => w.key.kind == ProofEntityKind.table),
        isEmpty,
      );
      expect(
        cancel.intent.writes
            .singleWhere((w) => w.key.kind == ProofEntityKind.sale)
            .tombstone,
        false,
      );
      OrderTableMutationIntent.decode(cancel.journal, serviceFeeRate: c.rate);
    },
  );
  test(
    'physical move retains business values, moves complete ownership and CAS-writes control without allocating',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final m = _Fixture(request: 101, rows: f.applied(create), cursor: 2);
      final move = OrdinaryOperationalPlanner.move(
        m.view,
        orderKey: m.orderKey,
        floor: 'first',
        tables: ['8'],
      );
      OrderTableMutationIntent.decode(move.journal, serviceFeeRate: m.rate);
      expect(
        move.outcome.order['totalAmount'],
        create.outcome.order['totalAmount'],
      );
      expect(move.outcome.order['tableNumbers'], ['8']);
      expect(
        move.intent.writes.where((w) => w.key.kind == ProofEntityKind.table),
        hasLength(2),
      );
      final control = move.intent.writes.singleWhere(
        (w) => w.key.kind == ProofEntityKind.operationalControl,
      );
      expect(control.expectedRevision, 2);
      expect(m.business(control)['lastOrderId'], 1);
      expect(move.intent.effects, isEmpty);
    },
  );
  for (final rate in [0.0, .2]) {
    test(
      'fee-bearing cancellation and decode use explicit frozen rate $rate with no global boxes',
      () {
        final f = _Fixture(rate: rate),
            create = OrdinaryOperationalPlanner.create(f.view, f.command());
        final c = _Fixture(
          request: 101,
          rate: rate,
          rows: f.applied(create),
          cursor: 2,
        );
        final cancel = OrdinaryOperationalPlanner.cancel(
          c.view,
          orderKey: c.orderKey,
          reason: ' operator reason ',
        );
        OrderTableMutationIntent.decode(cancel.journal, serviceFeeRate: rate);
        final sale = c.business(
          cancel.intent.writes.singleWhere(
            (w) => w.key.kind == ProofEntityKind.sale,
          ),
        );
        expect(sale['collectedNow'], 0);
        expect(sale['isFiscal'], false);
        expect(sale['finalTransaction']['serviceFee'], rate == 0 ? 0 : 2.0);
        expect(sale['totalAmount'], create.outcome.order['totalAmount']);
        expect(cancel.outcome.order['status'], 'cancelled');
        expect(cancel.intent.writes.every((w) => !w.tombstone), true);
        expect(
          c.business(
            cancel.intent.writes.singleWhere(
              (w) => w.key.value == c.reportKey.value,
            ),
          )['locked'],
          true,
        );
      },
    );
  }
  test(
    'linked real booking cancellation keeps Sale, Reservation, report and immutable booking audit',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final rows = f.applied(create)..add(f.entity(_booking, f.booking()));
      final c = _Fixture(request: 101, rows: rows, cursor: 2);
      final cancel = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
        reason: 'Synthetic cancel',
      );
      OrderTableMutationIntent.decode(cancel.journal, serviceFeeRate: c.rate);
      final reservation = cancel.intent.writes.singleWhere(
        (w) => w.key.kind == ProofEntityKind.reservation,
      );
      expect(c.business(reservation)['status'], 'cancelled');
      expect(c.business(reservation)['linkedOrderId'], 1);
      expect(cancel.intent.effects, hasLength(1));
      expect(cancel.intent.effects.single.id, _id(2101));
      final audit = jsonDecode(
        utf8.decode(cancel.intent.effects.single.payload),
      );
      expect(audit['business']['id'], '${_id(101)}:reservation');
      expect(audit['references']['/entityId'].single['id'], _booking.id);
      expect(
        cancel.intent.reads.any(
          (r) => r.key.value == _booking.value && r.expectedRevision == 1,
        ),
        true,
      );
    },
  );
  test(
    'existing cancelled Sale is retained unchanged and legacy prefix refuses fenced recovery',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final c0 = _Fixture(request: 101, rows: f.applied(create), cursor: 2);
      final cancelled = OrdinaryOperationalPlanner.cancel(
        c0.view,
        orderKey: c0.orderKey,
      );
      final sale = cancelled.intent.writes.singleWhere(
        (w) => w.key.kind == ProofEntityKind.sale,
      );
      final rows = f.applied(create)
        ..add(
          ProofEntity(
            key: sale.key,
            revision: 1,
            tombstone: false,
            document: sale.document,
          ),
        );
      final c = _Fixture(request: 101, rows: rows, cursor: 2);
      final retry = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
      );
      final retained = retry.intent.writes.singleWhere(
        (w) => w.key.kind == ProofEntityKind.sale,
      );
      expect(c.business(retained), c0.business(sale));
      expect(retained.expectedRevision, 1);
      final locked = cancelled.intent.writes.singleWhere(
        (w) => w.key.kind == ProofEntityKind.auditReport,
      );
      final prefix = rows.where((e) => e.key.value != locked.key.value).toList()
        ..add(
          ProofEntity(
            key: locked.key,
            revision: 2,
            tombstone: false,
            document: locked.document,
          ),
        );
      final recovery = _Fixture(request: 101, rows: prefix, cursor: 2);
      expect(
        () => OrdinaryOperationalPlanner.cancel(
          recovery.view,
          orderKey: recovery.orderKey,
        ),
        _fails(OperationalPlanningFailureCode.recoveryRequired),
      );
    },
  );
  test(
    'policy approver is independently enforced by adapter and its revision remains a dependency',
    () {
      final f = _Fixture(approval: true),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final c = _Fixture(
        request: 101,
        approval: true,
        rows: f.applied(create),
        cursor: 2,
      );
      expect(
        () => OrdinaryOperationalPlanner.cancel(c.view, orderKey: c.orderKey),
        _fails(OperationalPlanningFailureCode.unsupported),
      );
      final allowed = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
        approvedBy: 'manager',
      );
      expect(
        allowed.intent.reads.any((r) => r.key.value == _approver.value),
        true,
      );
      final policyBody = Map<String, dynamic>.of(c.view.business(_policy))
        ..['cancelRequiresApproval'] = false;
      final permissiveRows =
          c.entities.where((e) => e.key.value != _policy.value).toList()
            ..add(c.entity(_policy, policyBody));
      final permissive = _Fixture(
        request: 101,
        rows: permissiveRows,
        cursor: 2,
      );
      final noApproval = OrdinaryOperationalPlanner.cancel(
        permissive.view,
        orderKey: permissive.orderKey,
      );
      final forged = _journal(noApproval, (raw) {
        raw['request']['proofPlanning'] = c.view.provenance();
      });
      expect(
        () => OperationalIntentAdapter.adapt(view: c.view, journal: forged),
        _fails(OperationalPlanningFailureCode.unsupported),
      );
    },
  );
  test(
    'unknown stores/settings/financial subtypes and missing references fail before frame or transport',
    () async {
      final f = _Fixture(),
          plan = OrdinaryOperationalPlanner.create(f.view, f.command());
      final server = _ScriptedCoordinator(f.entities, f.binding),
          transport = _Transport(server, f.binding),
          store = _MemoryFrame();
      final client = OperationalProofClient(
        store: store,
        transport: transport,
        binding: f.binding,
      );
      await client.open();
      final writes = store.writes;
      for (final unknown in ['unmapped', 'settings', 'sales']) {
        final bad = _journal(plan, (body) {
          (body['effects'] as List).add({
            'store': unknown,
            'key': unknown == 'settings' ? 'currentDate' : 'x',
            'before': null,
            'after': unknown == 'sales'
                ? {'recordType': 'advance'}
                : {'value': 1},
          });
        });
        expect(
          () => OperationalIntentAdapter.adapt(view: f.view, journal: bad),
          _fails(OperationalPlanningFailureCode.unsupported),
        );
      }
      expect(store.writes, writes);
      expect(transport.calls, 0);
      expect(client.pending, isNull);
      final badStaff = _journal(plan, (body) {
        for (final e in body['effects'])
          if (e['store'] == 'tables')
            e['after']['reservedBy'] = 'missing-staff';
      });
      expect(
        () => OperationalIntentAdapter.adapt(view: f.view, journal: badStaff),
        _fails(OperationalPlanningFailureCode.missingDependency),
      );
      expect(store.writes, writes);
      expect(transport.calls, 0);
    },
  );
  test(
    'adapter refuses old total under new frozen fee even if caller rewrites provenance',
    () {
      final f = _Fixture(),
          plan = OrdinaryOperationalPlanner.create(f.view, f.command());
      final body = Map<String, dynamic>.of(f.view.business(_policy))
        ..['serviceFeeRate'] = .3;
      final rows =
          f.entities.where((e) => e.key.value != _policy.value).toList()
            ..add(f.entity(_policy, body));
      final changed = _Fixture(rows: rows);
      final forged = _journal(plan, (raw) {
        raw['request']['proofPlanning'] = changed.view.provenance();
      });
      expect(
        () =>
            OperationalIntentAdapter.adapt(view: changed.view, journal: forged),
        _fails(OperationalPlanningFailureCode.staleView),
      );
    },
  );
  test(
    'view and resolver refuse ambiguous identities, missing policy and recovery phase',
    () {
      expect(
        () => OperationalIdentityResolver(
          identities: [
            OperationalIdentity(
              key: _table7,
              store: 'tables',
              legacyKey: 17,
              tableRef: 'first/7',
            ),
            OperationalIdentity(
              key: _table8,
              store: 'tables',
              legacyKey: 18,
              tableRef: 'first/7',
            ),
          ],
          auditEffectIds: {},
        ),
        _fails(OperationalPlanningFailureCode.ambiguousIdentity),
      );
      final f = _Fixture();
      expect(
        () => _Fixture(
          rows: f.entities.where((e) => e.key.value != _policy.value).toList(),
        ),
        _fails(OperationalPlanningFailureCode.missingDependency),
      );
      final control = Map<String, dynamic>.of(f.view.business(_control))
        ..['phase'] = 'recovery';
      expect(
        () => _Fixture(
          rows: f.entities.where((e) => e.key.value != _control.value).toList()
            ..add(f.entity(_control, control)),
        ),
        _fails(OperationalPlanningFailureCode.recoveryRequired),
      );
    },
  );
  test(
    'adapter refuses omitted linked booking effects even when legacy journal remains valid',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final c = _Fixture(
        request: 101,
        rows: f.applied(create)..add(f.entity(_booking, f.booking())),
        cursor: 2,
      );
      final complete = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
      );
      final omitted = _journal(complete, (raw) {
        (raw['effects'] as List).removeWhere(
          (e) => e['store'] == 'reservation' || e['store'] == 'auditEvent',
        );
      });
      OrderTableMutationIntent.decode(omitted, serviceFeeRate: c.rate);
      expect(
        () => OperationalIntentAdapter.adapt(view: c.view, journal: omitted),
        _fails(OperationalPlanningFailureCode.ownershipConflict),
      );
    },
  );
  test(
    'adapter counts already-cancelled real booking before checking ambiguous Order linkage',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final rows = f.applied(create)..add(f.entity(_booking, f.booking()));
      final c = _Fixture(request: 101, rows: rows, cursor: 2);
      final complete = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
      );
      final second = _key(ProofEntityKind.reservation, 51);
      final cancelled = Map<String, dynamic>.of(f.booking())
        ..['id'] = 'legacy-second-booking'
        ..['status'] = 'cancelled';
      final ambiguous = _Fixture(
        request: 101,
        rows: [...rows, f.entity(second, cancelled)],
        cursor: 2,
        extraIdentities: [
          OperationalIdentity(
            key: second,
            store: 'reservation',
            legacyKey: 778,
            legacyId: 'legacy-second-booking',
          ),
        ],
      );
      final journal = _journal(complete, (body) {
        body['request']['proofPlanning'] = ambiguous.view.provenance();
      });
      OrderTableMutationIntent.decode(journal, serviceFeeRate: ambiguous.rate);
      expect(
        () => OperationalIntentAdapter.adapt(
          view: ambiguous.view,
          journal: journal,
        ),
        _fails(OperationalPlanningFailureCode.ownershipConflict),
      );
    },
  );

  test(
    'adapter refuses a new cancelled Sale when frozen view already contains cancellation history',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final c0 = _Fixture(request: 101, rows: f.applied(create), cursor: 2);
      final fresh = OrdinaryOperationalPlanner.cancel(
        c0.view,
        orderKey: c0.orderKey,
      );
      final sale = fresh.intent.writes.singleWhere(
        (w) => w.key.kind == ProofEntityKind.sale,
      );
      final rows = f.applied(create)
        ..add(
          ProofEntity(
            key: sale.key,
            revision: 1,
            tombstone: false,
            document: sale.document,
          ),
        );
      final c = _Fixture(request: 101, rows: rows, cursor: 2);
      expect(
        () => OperationalIntentAdapter.adapt(
          view: c.view,
          journal: fresh.journal,
        ),
        _fails(OperationalPlanningFailureCode.staleView),
      );
    },
  );
  test(
    'adapter rejects duplicate line IDs and unfrozen audit timestamp without invoking generated defaults',
    () {
      final f = _Fixture(),
          plan = OrdinaryOperationalPlanner.create(f.view, f.command());
      final duplicate = _journal(plan, (body) {
        final order = (body['effects'] as List).singleWhere(
          (e) => e['store'] == 'orders',
        )['after'];
        (order['items'] as List).add(
          OrderTransferIntent.cloneMap(order['items'][0]),
        );
        body['outcome']['order'] = OrderTransferIntent.cloneMap(order);
      });
      expect(
        () => OperationalIntentAdapter.adapt(view: f.view, journal: duplicate),
        _fails(OperationalPlanningFailureCode.ambiguousIdentity),
      );
      final shifted = _journal(plan, (body) {
        for (final e in body['effects'])
          if (e['store'] == 'auditEvent')
            e['after']['createdAt'] = '2026-10-06T12:01:00.000Z';
      });
      expect(
        () => OperationalIntentAdapter.adapt(view: f.view, journal: shifted),
        _fails(OperationalPlanningFailureCode.invalidPlan),
      );
    },
  );
  test(
    'fresh view refuses old operator provenance and never changes original immutable request',
    () {
      final f = _Fixture(),
          plan = OrdinaryOperationalPlanner.create(f.view, f.command());
      final exact = plan.intent.fingerprint;
      final rows =
          f.entities.where((e) => e.key.value != _policy.value).toList()..add(
            f.entity(_policy, Map.of(f.view.business(_policy)), revision: 2),
          );
      final changed = _Fixture(rows: rows, cursor: 2);
      expect(
        () => OperationalIntentAdapter.adapt(
          view: changed.view,
          journal: plan.journal,
        ),
        _fails(OperationalPlanningFailureCode.staleView),
      );
      expect(plan.intent.fingerprint, exact);
      expect(
        plan.intent.reads
            .singleWhere((r) => r.key.value == _policy.value)
            .expectedRevision,
        1,
      );
    },
  );
  test(
    'all scanned dependencies exceeding read bound reject complete plan without truncation',
    () {
      final f = _Fixture(),
          extra = <OperationalIdentity>[],
          rows = List<ProofEntity>.of(f.entities);
      for (var i = 0; i < 260; i++) {
        final key = _key(ProofEntityKind.table, 9000 + i), label = '${100 + i}';
        extra.add(
          OperationalIdentity(
            key: key,
            store: 'tables',
            legacyKey: 1000 + i,
            tableRef: 'first/$label',
          ),
        );
        rows.add(
          f.entity(
            key,
            OrderTableMutationRepository.tableImage(
              TableModel(tableNumber: label, floor: 'first'),
            ),
          ),
        );
      }
      final large = _Fixture(rows: rows, cursor: 3, extraIdentities: extra);
      expect(
        () => OrdinaryOperationalPlanner.create(large.view, large.command()),
        _fails(OperationalPlanningFailureCode.capacity),
      );
      expect(large.view.business(_control)['lastOrderId'], 0);
    },
  );
  test(
    'cancellation preserves purchased package image and binds current package only as a dependency',
    () {
      final f = _Fixture(),
          create = OrdinaryOperationalPlanner.create(f.view, f.command());
      final order = OrderTransferIntent.orderImage(create.outcome.order)
        ..packageId = 'legacy-package'
        ..packageName = 'Frozen purchased'
        ..packagePrice = 50;
      order.recalculateTotal(serviceFeeRate: f.rate);
      final orderEntity = f.entity(
        f.orderKey,
        OrderTableMutationRepository.image(order),
        revision: 1,
      );
      final rows =
          f
              .applied(create)
              .where((e) => e.key.value != f.orderKey.value)
              .toList()
            ..add(orderEntity)
            ..add(
              f.entity(_package, {
                'packageId': 'legacy-package',
                'name': 'Different current definition',
                'description': null,
                'items': [],
                'pricePerPerson': 10000,
                'isActive': true,
                'createdAt': '2026-10-01T12:00:00.000Z',
                'createdBy': 'waiter',
                'servingSize': 1,
                'allowedTables': ['first/7'],
              }),
            );
      final c = _Fixture(request: 101, rows: rows, cursor: 2);
      final plan = OrdinaryOperationalPlanner.cancel(
        c.view,
        orderKey: c.orderKey,
      );
      expect(plan.outcome.order['packagePrice'], 50);
      expect(plan.outcome.order['totalAmount'], 62.01);
      expect(
        plan.intent.reads.any(
          (r) => r.key.value == _package.value && r.expectedRevision == 1,
        ),
        true,
      );
      final missing = _Fixture(
        request: 101,
        rows: rows.where((e) => e.key.value != _package.value).toList(),
        cursor: 2,
      );
      expect(
        () => OrdinaryOperationalPlanner.cancel(
          missing.view,
          orderKey: missing.orderKey,
        ),
        _fails(OperationalPlanningFailureCode.missingDependency),
      );
    },
  );

  test(
    'three isolated clients contend on one control/number/table and stale losers publish no own rows/effects',
    () async {
      final fixtures = [
        for (var i = 0; i < 3; i++)
          _Fixture(request: 100 + i, terminal: 3 + i, newId: 20 + i),
      ];
      final server = _ScriptedCoordinator(
        fixtures.first.entities,
        fixtures.first.binding,
      );
      final clients = <OperationalProofClient>[],
          plans = <OperationalAdaptedPlan>[];
      for (final f in fixtures) {
        final client = OperationalProofClient(
          store: _MemoryFrame(),
          transport: _Transport(server, f.binding),
          binding: f.binding,
        );
        await client.open();
        clients.add(client);
        final plan = OrdinaryOperationalPlanner.create(f.view, f.command());
        plans.add(plan);
        await client.prepare(plan.intent);
      }
      final results = await Future.wait(clients.map((c) => c.sendPending()));
      expect(
        results.where((r) => r.outcome == ProofOutcome.committed),
        hasLength(1),
      );
      expect(
        results.where((r) => r.outcome == ProofOutcome.conflict),
        hasLength(2),
      );
      expect(server.logicalCommits, 1);
      expect(server.effects, hasLength(1));
      expect(
        server.entities.values.where(
          (e) => e.key.kind == ProofEntityKind.order,
        ),
        hasLength(1),
      );
      expect(
        server.entities.values.where(
          (e) => e.key.kind == ProofEntityKind.auditReport,
        ),
        hasLength(1),
      );
      expect(server.current(_control).revision, 2);
      for (var i = 0; i < clients.length; i++) {
        expect(clients[i].pending, isNull);
        expect(clients[i].ready, true);
        if (results[i].outcome == ProofOutcome.conflict)
          expect(clients[i].entity(fixtures[i].orderKey), isNull);
      }
    },
  );
  test(
    'lost ACK real isolated Hive reopen retains exact complete intent/result and one audit effect',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'detached_operational_proof_',
      );
      Hive.init(dir.path);
      Box<dynamic>? box;
      try {
        final f = _Fixture(),
            server = _ScriptedCoordinator(f.entities, f.binding),
            transport = _Transport(server, f.binding);
        box = await Hive.openBox<dynamic>('isolated_operational_proof_planner');
        final client = OperationalProofClient(
          store: HiveOperationalProofFrameStore(box),
          transport: transport,
          binding: f.binding,
        );
        await client.open();
        final plan = OrdinaryOperationalPlanner.create(f.view, f.command());
        await client.prepare(plan.intent);
        transport.loseAck = true;
        await expectLater(
          client.sendPending(),
          throwsA(isA<SocketException>()),
        );
        expect(client.pending!.fingerprint, plan.intent.fingerprint);
        expect(
          client.entities.where((e) => e.key.kind == ProofEntityKind.order),
          isEmpty,
        );
        final exact = server.results[plan.intent.requestId]!.fingerprint;
        await box.close();
        box = await Hive.openBox<dynamic>('isolated_operational_proof_planner');
        transport.notFoundOnce = true;
        final reopened = OperationalProofClient(
          store: HiveOperationalProofFrameStore(box),
          transport: transport,
          binding: f.binding,
        );
        await reopened.open();
        expect(reopened.lastResult!.fingerprint, exact);
        expect(reopened.pending, isNull);
        expect(server.attempts, [
          plan.intent.fingerprint,
          plan.intent.fingerprint,
        ]);
        expect(server.logicalCommits, 1);
        expect(reopened.effectReceipts, hasLength(1));
        expect(
          reopened.effectReceipts.single.effect.id,
          plan.intent.effects.single.id,
        );
        expect(
          jsonDecode(utf8.decode(reopened.lastResult!.applicationData)),
          plan.outcome.toMap(),
        );
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
