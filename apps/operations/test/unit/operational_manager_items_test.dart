import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/edge/operational_proof/client.dart';
import 'package:vynic/core/services/edge/operational_proof/domain.dart';
import 'package:vynic/core/services/edge/operational_proof/frame_store.dart';
import 'package:vynic/core/services/edge/operational_proof/manager_items_adapter.dart';
import 'package:vynic/core/services/edge/operational_proof/manager_items_planner.dart';
import 'package:vynic/core/services/edge/operational_proof/planning_view.dart';
import 'package:vynic/core/services/notifications/manager_notification_inbox.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';

String _id(int n) =>
    '41000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
ProofKey _key(ProofEntityKind kind, int n) => ProofKey(kind, _id(n));
final _control = _key(ProofEntityKind.operationalControl, 1),
    _day = _key(ProofEntityKind.day, 2),
    _policy = _key(ProofEntityKind.operationalPolicy, 3),
    _manager = _key(ProofEntityKind.staff, 4),
    _waiter = _key(ProofEntityKind.staff, 5),
    _table = _key(ProofEntityKind.table, 10),
    _order = _key(ProofEntityKind.order, 20),
    _report = _key(ProofEntityKind.auditReport, 30),
    _package = _key(ProofEntityKind.package, 40),
    _advance = _key(ProofEntityKind.advance, 41);
final _opened = DateTime.utc(2026, 10, 6, 9),
    _when = DateTime.utc(2026, 10, 6, 12);

class _Fixture {
  _Fixture({
    this.request = 100,
    this.terminal = 90,
    this.rate = .2,
    this.custom,
    this.package = false,
    this.takeaway = false,
  }) {
    binding = ProofBinding(
      installationId: _id(901),
      venueId: _id(902),
      terminalId: _id(terminal),
      epoch: 41,
      grantFingerprint: 'a' * 64,
      mode: operationalProofMode,
    );
    identities = OperationalIdentityResolver(
      identities: [
        OperationalIdentity(
          key: _control,
          store: 'operationalControl',
          legacyKey: 'control',
        ),
        OperationalIdentity(
          key: _day,
          store: 'businessDays',
          legacyKey: '2026-10-06',
        ),
        OperationalIdentity(
          key: _policy,
          store: 'operationalPolicy',
          legacyKey: 'policy',
        ),
        OperationalIdentity(
          key: _manager,
          store: 'staff',
          legacyKey: 'manager',
          legacyId: 'manager',
        ),
        OperationalIdentity(
          key: _waiter,
          store: 'staff',
          legacyKey: 'waiter',
          legacyId: 'waiter',
        ),
        OperationalIdentity(
          key: _table,
          store: 'tables',
          legacyKey: 'physical',
          tableRef: 'first/7',
        ),
        OperationalIdentity(
          key: _order,
          store: 'orders',
          legacyKey: 700,
          orderNumber: 1,
          legacyId: _order.id,
        ),
        OperationalIdentity(
          key: _report,
          store: 'auditReport',
          legacyKey: 'audit_report_order_1',
        ),
        OperationalIdentity(
          key: _package,
          store: 'packages',
          legacyKey: 'package',
          legacyId: 'frozen-package',
        ),
        OperationalIdentity(
          key: _advance,
          store: 'advances',
          legacyKey: 'advance',
          legacyId: 'frozen-advance',
        ),
      ],
      auditEffectIds: {'${_id(request)}:manager-items': _id(request + 1000)},
    );
    OrderItem line(
      String key,
      int quantity,
      double price,
      double total,
      int id,
    ) => OrderItem(
      itemKey: key,
      itemName: 'Frozen $key',
      unitPrice: price,
      quantity: quantity,
      total: total,
      lineUuid: _id(id),
      comment: ' keep ',
      menuItemId: 'menu-$key',
      variantId: 'variant-$key',
    );
    final order = Order(
      orderId: 1,
      orderUuid: _order.id,
      tableNumbers: [takeaway ? 'TA-1' : '7'],
      floor: takeaway ? 'takeaway' : 'first',
      items: [line('a', 4, 2.505, 10.01, 70), line('b', 2, 1.17, 2.34, 71)],
      totalAmount: 0,
      createdAt: _opened,
      createdBy: 'waiter',
      openedByUserId: 'waiter',
      status: 'confirmed',
      updatedAt: _opened,
      includeServiceFee: !takeaway,
      discountAmount: .3,
      manualAdjustmentAmount: .2,
      advanceAmount: .7,
      advanceReceiptId: 'frozen-advance',
      advanceCollectedOn: '2026-10-05',
      customServiceFeePercentage: custom,
      packageId: package ? 'frozen-package' : null,
      packageName: package ? 'Purchased snapshot' : null,
      packagePrice: package ? 40 : 0,
      packageUnitPrice: package ? 20 : 0,
      packageGuestCount: package ? 2 : 0,
      packageItems: package ? [line('purchased', 2, 0, 0, 72)] : [],
      customerName: 'Frozen guest',
      customerPhone: '-',
      pickupTime: '12:30',
    );
    order.recalculateTotal(serviceFeeRate: rate);
    beforeOrder = OrderTableMutationRepository.image(order);
    final creation = AuditEvent(
      type: takeaway
          ? AuditEventType.createTakeaway
          : AuditEventType.createWalkIn,
      itemName: 'ORDER',
      previousQty: 0,
      newQty: 0,
      waiterId: 'waiter',
      waiterName: 'waiter',
      timestamp: _opened,
      sequence: 3,
      details: {
        'orderId': 1,
        'orderKind': package ? 'PACKAGE' : 'WALK_IN',
        'tableRefs': [takeaway ? 'takeaway/TA-1' : 'first/7'],
        'floor': order.floor,
        'source': 'POS',
        'actorId': 'waiter',
        if (package) 'packageId': 'frozen-package',
      },
    );
    final report = AuditReport(
      reportId: 'audit_report_order_1',
      orderId: 1,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
      openedById: 'waiter',
      openedByName: 'waiter',
      openedAt: _opened,
      status: AuditReportStatus.open,
      updatedAt: _opened,
      events: [
        creation,
        AuditEvent(
          type: AuditEventType.addItem,
          itemName: 'Frozen a',
          previousQty: 0,
          newQty: 4,
          waiterId: 'waiter',
          waiterName: 'waiter',
          timestamp: _opened,
          sequence: 9,
          details: {'menuItemId': 'menu-a', 'variantId': 'variant-a'},
        ),
        AuditEvent(
          type: AuditEventType.addItem,
          itemName: 'Frozen b',
          previousQty: 0,
          newQty: 2,
          waiterId: 'waiter',
          waiterName: 'waiter',
          timestamp: _opened,
          sequence: 12,
        ),
      ],
    );
    beforeReport = report.toMap();
    orderLinks = {
      '/orderId': [_order],
      '/createdBy': [_waiter],
      '/openedByUserId': [_waiter],
      '/advanceReceiptId': [_advance],
      if (!takeaway) '/tableNumbers': [_table],
      if (package) '/packageId': [_package],
    };
    reportLinks = {
      '/reportId': [_report],
      '/orderId': [_order],
      '/openedById': [_waiter],
      if (!takeaway) '/tableNumbers': [_table],
      '/events/0/waiterId': [_waiter],
      '/events/1/waiterId': [_waiter],
      '/events/2/waiterId': [_waiter],
      '/events/0/details/orderId': [_order],
      '/events/0/details/actorId': [_waiter],
      takeaway
          ? '/events/0/details/tableRefs/virtualOrder'
          : '/events/0/details/tableRefs': [
        takeaway ? _order : _table,
      ],
      if (package) '/events/0/details/packageId': [_package],
    };
    rows = [
      entity(
        _control,
        {
          'lastOrderId': 1,
          'currentDayId': _day.id,
          'phase': 'operational',
          'recoveryGeneration': 0,
        },
        links: {
          'currentDayId': [_day],
        },
      ),
      entity(_day, {'date': '2026-10-06', 'status': 'open'}),
      entity(_policy, {
        'serviceFeeRate': rate,
        'defaultIncludeServiceFee': true,
        'cancelRequiresApproval': false,
        'menuRevision': 7,
        'menuFingerprint': 'b' * 64,
        'inventoryRevision': 4,
        'runtimeFingerprint': 'c' * 64,
      }),
      entity(_manager, {
        'username': 'manager',
        'enabled': true,
        'permissions': [managerItemsPermission],
      }),
      entity(_waiter, {
        'username': 'waiter',
        'enabled': true,
        'permissions': [],
      }),
      if (!takeaway)
        entity(
          _table,
          OrderTableMutationRepository.tableImage(
            TableModel(
              tableNumber: '7',
              floor: 'first',
              isReserved: true,
              activeOrderId: 1,
              reservedAt: _opened,
              reservedBy: 'waiter',
            ),
          ),
          links: {
            '/activeOrderId': [_order],
            '/reservedBy': [_waiter],
          },
        ),
      entity(_order, beforeOrder, links: orderLinks),
      entity(_report, beforeReport, links: reportLinks),
      entity(_advance, {'amount': .7, 'businessDate': '2026-10-05'}),
      if (package)
        entity(_package, {
          'name': 'Current catalog changed',
          'pricePerPerson': 1000,
        }),
    ];
  }
  final int request, terminal;
  final double rate;
  final double? custom;
  final bool package, takeaway;
  late final ProofBinding binding;
  late final OperationalIdentityResolver identities;
  late final Map<String, dynamic> beforeOrder, beforeReport;
  late final Map<String, List<ProofKey>> orderLinks, reportLinks;
  late final List<ProofEntity> rows;
  ProofEntity entity(
    ProofKey key,
    Map<String, dynamic> business, {
    Map<String, List<ProofKey>> links = const {},
    int revision = 1,
  }) => ProofEntity(
    key: key,
    revision: revision,
    tombstone: false,
    document: OperationalPlanningView.encodeDocument(
      binding: binding,
      key: key,
      business: business,
      references: links,
    ),
  );
  OperationalPlanningView view({
    List<ProofEntity>? entities,
    int cursor = 1,
    AuditSource source = AuditSource.manager,
    Set<String> effects = const {},
    OperationalIdentityResolver? resolver,
  }) => OperationalPlanningView(
    binding: binding,
    cursor: cursor,
    context: OperationalPlanningContext(
      requestId: _id(request),
      actorId: 'manager',
      actorName: 'Manager Label',
      occurredAt: _when,
      source: source,
    ),
    identities: resolver ?? identities,
    controlKey: _control,
    dayKey: _day,
    policyKey: _policy,
    actorKey: _manager,
    entities: entities ?? rows,
    retainedEffectIds: effects,
  );
  OperationalManagerItemsCommand command({int a = 2, bool keepB = false}) =>
      OperationalManagerItemsCommand(
        orderKey: _order,
        menuRevision: 7,
        menuFingerprint: 'b' * 64,
        retainedItems: [
          OperationalRetainedItemQuantity(
            itemKey: 'a',
            lineUuid: _id(70),
            quantity: a,
          ),
          if (keepB)
            OperationalRetainedItemQuantity(
              itemKey: 'b',
              lineUuid: _id(71),
              quantity: 2,
            ),
        ],
      );
  OperationalManagerItemsDraft draft({
    OperationalPlanningView? projection,
    OperationalManagerItemsCommand? intent,
  }) => OperationalManagerItemsPlanner.draft(
    view: projection ?? view(),
    command: intent ?? command(),
  );
  OperationalManagerItemsPlan plan() =>
      OperationalManagerItemsAdapter.adapt(view: view(), draft: draft());
  List<ProofEntity> replacing(ProofKey key, ProofEntity replacement) => [
    for (final row in rows) row.key.value == key.value ? replacement : row,
  ];
}

Map<String, dynamic> _business(ProofWrite write) => Map<String, dynamic>.from(
  jsonDecode(utf8.decode(write.document))['business'],
);
OperationalManagerItemsDraft _changed(
  OperationalManagerItemsDraft draft,
  void Function(Map<String, dynamic>) change,
) {
  final map = draft.toMap();
  change(map);
  return OperationalManagerItemsDraft.fromMap(map);
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

/// Scripted domain CAS only. This does not qualify actual Go/RPC/LAN operation.
class _Coordinator {
  _Coordinator(_Fixture fixture) {
    entities.addAll({for (final row in fixture.rows) row.key.value: row});
    events.add(
      ProofEvent(
        binding: fixture.binding,
        sequence: 1,
        requestId: _id(800),
        terminalId: _id(99),
        entities: fixture.rows,
      ),
    );
  }
  final entities = <String, ProofEntity>{},
      results = <String, ProofResult>{},
      requests = <String, ProofIntent>{};
  final events = <ProofEvent>[], effects = <ProofEffect>[], hashes = <String>[];
  int commits = 0;
  ProofEntity current(ProofKey key) =>
      entities[key.value] ??
      ProofEntity(key: key, revision: 0, tombstone: false, document: []);
  ProofResult commit(ProofIntent intent) {
    hashes.add(intent.fingerprint);
    if (results.containsKey(intent.requestId)) {
      expect(requests[intent.requestId]!.fingerprint, intent.fingerprint);
      return results[intent.requestId]!;
    }
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
    late ProofResult result;
    if (conflict) {
      final touched = {
        for (final r in intent.reads) r.key.value: r.key,
        for (final w in intent.writes) w.key.value: w.key,
      };
      result = ProofResult(
        binding: intent.binding,
        requestId: intent.requestId,
        terminalId: intent.binding.terminalId,
        outcome: ProofOutcome.conflict,
        headSequence: events.last.sequence,
        current: touched.values.map(current).toList(),
      );
    } else {
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
      commits++;
      result = ProofResult(
        binding: intent.binding,
        requestId: intent.requestId,
        terminalId: intent.binding.terminalId,
        outcome: ProofOutcome.committed,
        headSequence: event.sequence,
        event: event,
        applicationData: intent.applicationData,
      );
    }
    results[intent.requestId] = result;
    requests[intent.requestId] = intent;
    return result;
  }
}

class _Transport implements OperationalProofTransport {
  _Transport(this.server, this.binding);
  final _Coordinator server;
  final ProofBinding binding;
  bool loseAck = false, notFoundOnce = false;
  int calls = 0;
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
      throw const SocketException('scripted lost ACK');
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
        .map(
          (e) => ProofEvent(
            binding: binding,
            sequence: e.sequence,
            requestId: e.requestId,
            terminalId: e.terminalId,
            entities: e.entities,
            effects: e.effects,
          ),
        )
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
  group('pure retained Manager item replacement', () {
    int feeReads = 0, clockReads = 0;
    setUp(() {
      expect(DatabaseCore.orderBox, isNull);
      expect(DatabaseCore.tableBox, isNull);
      feeReads = 0;
      clockReads = 0;
      Order.serviceFeeRateResolver = () {
        feeReads++;
        throw StateError('No global fee');
      };
      Order.timestampResolver = () {
        clockReads++;
        throw StateError('No global clock');
      };
    });
    tearDown(() {
      expect(feeReads, 0);
      expect(clockReads, 0);
      Order.serviceFeeRateResolver = null;
      Order.timestampResolver = null;
    });
    test(
      'complete Order/report/control and exact audit use frozen policy with no global reads',
      () {
        final fixture = _Fixture(), plan = fixture.plan();
        expect(
          plan.intent.writes.map((w) => w.key.kind),
          unorderedEquals([
            ProofEntityKind.order,
            ProofEntityKind.auditReport,
            ProofEntityKind.operationalControl,
          ]),
        );
        final order = _business(
          plan.intent.writes.singleWhere((w) => w.key.value == _order.value),
        );
        expect(order['totalAmount'], 5.21);
        expect(order['items'].single['total'], 5.01);
        expect(order['items'].single['lineUuid'], _id(70));
        final control = _business(
          plan.intent.writes.singleWhere((w) => w.key.value == _control.value),
        );
        expect(control['lastOrderId'], 1);
        expect(
          plan.intent.writes.every((w) => w.expectedRevision == 1),
          isTrue,
        );
        final report = _business(
          plan.intent.writes.singleWhere((w) => w.key.value == _report.value),
        );
        expect(
          report['events'].take(3).toList(),
          fixture.beforeReport['events'],
        );
        expect(report['events'].skip(3).map((e) => e['sequence']).toList(), [
          13,
          14,
        ]);
        expect(report['events'].skip(3).map((e) => e['type']).toList(), [
          'REDUCE_QTY',
          'DELETE_ITEM',
        ]);
        expect(report['updatedAt'], _when.toIso8601String());
        final effect = jsonDecode(
          utf8.decode(plan.intent.effects.single.payload),
        );
        expect(effect['events'], report['events'].skip(3).toList());
        expect(effect.containsKey('action'), isFalse);
        expect(plan.intent.effects.single.kind, ProofEffectKind.audit);
        expect(
          plan.intent.reads.map((r) => r.key.value),
          containsAll([
            _control.value,
            _day.value,
            _policy.value,
            _manager.value,
            _waiter.value,
            _order.value,
            _report.value,
            _table.value,
            _advance.value,
          ]),
        );
      },
    );
    test('zero frozen fee and per-order override keep model precedence', () {
      final zero = _Fixture(rate: 0).plan(),
          custom = _Fixture(custom: 5).plan();
      double total(OperationalManagerItemsPlan p) => _business(
        p.intent.writes.singleWhere((w) => w.key.value == _order.value),
      )['totalAmount'];
      expect(total(zero), 4.21);
      expect(total(custom), 4.46);
    });
    test(
      'purchased package/advance are preserved and read; current package price cannot reprice history',
      () {
        final fixture = _Fixture(package: true), plan = fixture.plan();
        final after = _business(
          plan.intent.writes.singleWhere((w) => w.key.value == _order.value),
        );
        for (final field in [
          'packageId',
          'packageName',
          'packagePrice',
          'packageUnitPrice',
          'packageGuestCount',
          'packageItems',
          'advanceAmount',
          'advanceReceiptId',
          'discountAmount',
          'manualAdjustmentAmount',
          'customServiceFeePercentage',
          'status',
          'floor',
          'tableNumbers',
        ]) {
          expect(after[field], fixture.beforeOrder[field], reason: field);
        }
        expect(after['totalAmount'], 45.21);
        expect(
          plan.intent.reads.map((r) => r.key.value),
          containsAll([_package.value, _advance.value]),
        );
      },
    );
    test('takeaway has no physical Table writes or invented identities', () {
      final fixture = _Fixture(takeaway: true), plan = fixture.plan();
      expect(
        plan.intent.reads.any((r) => r.key.kind == ProofEntityKind.table),
        isFalse,
      );
      expect(
        plan.intent.writes.any((w) => w.key.kind == ProofEntityKind.table),
        isFalse,
      );
      expect(
        _business(
          plan.intent.writes.singleWhere((w) => w.key.value == _order.value),
        )['totalAmount'],
        4.21,
      );
    });
    test(
      'POS origin and disabled item authority cannot publish a Manager draft',
      () {
        final fixture = _Fixture(), draft = fixture.draft();
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: fixture.view(source: AuditSource.pos),
            draft: draft,
          ),
          _fails(OperationalPlanningFailureCode.unsupported),
        );
        final rows = fixture.replacing(
          _manager,
          fixture.entity(_manager, {
            'username': 'manager',
            'enabled': true,
            'permissions': [],
          }),
        );
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: fixture.view(entities: rows),
            draft: draft,
          ),
          _fails(OperationalPlanningFailureCode.unsupported),
        );
      },
    );
    test(
      'new keys, changed UUIDs, duplicate keys and no-op replacements are refused',
      () {
        final fixture = _Fixture();
        OperationalManagerItemsCommand command(String key, String uuid) =>
            OperationalManagerItemsCommand(
              orderKey: _order,
              menuRevision: 7,
              menuFingerprint: 'b' * 64,
              retainedItems: [
                OperationalRetainedItemQuantity(
                  itemKey: key,
                  lineUuid: uuid,
                  quantity: 2,
                ),
              ],
            );
        expect(
          () => fixture.draft(intent: command('new', _id(76))),
          _fails(OperationalPlanningFailureCode.unsupported),
        );
        expect(
          () => fixture.draft(intent: command('a', _id(76))),
          _fails(OperationalPlanningFailureCode.ambiguousIdentity),
        );
        expect(
          () => fixture.draft(intent: fixture.command(a: 4, keepB: true)),
          _fails(OperationalPlanningFailureCode.unsupported),
        );
        expect(
          () => OperationalManagerItemsCommand(
            orderKey: _order,
            menuRevision: 7,
            menuFingerprint: 'b' * 64,
            retainedItems: [
              OperationalRetainedItemQuantity(
                itemKey: 'a',
                lineUuid: _id(70),
                quantity: 2,
              ),
              OperationalRetainedItemQuantity(
                itemKey: 'a',
                lineUuid: _id(71),
                quantity: 1,
              ),
            ],
          ),
          _fails(OperationalPlanningFailureCode.ambiguousIdentity),
        );
      },
    );
    test(
      'all line removals preserve lifecycle and clamp balance through the existing model',
      () {
        final fixture = _Fixture(),
            command = OperationalManagerItemsCommand(
              orderKey: _order,
              menuRevision: 7,
              menuFingerprint: 'b' * 64,
              retainedItems: [],
            );
        final draft = fixture.draft(intent: command);
        final plan = OperationalManagerItemsAdapter.adapt(
          view: fixture.view(),
          draft: draft,
        );
        final after = _business(
          plan.intent.writes.singleWhere((w) => w.key.value == _order.value),
        );
        expect(after['items'], isEmpty);
        expect(after['status'], 'confirmed');
        expect(after['totalAmount'], 0);
        expect(
          plan.intent.writes.any((w) => w.key.kind == ProofEntityKind.sale),
          isFalse,
        );
      },
    );
    test(
      'arbitrary outcome, prefix, timestamp, extra command and status changes fail before frames or RPC',
      () async {
        final fixture = _Fixture(),
            draft = fixture.draft(),
            frame = _MemoryFrame();
        final transport = _Transport(_Coordinator(fixture), fixture.binding);
        final client = OperationalProofClient(
          binding: fixture.binding,
          store: frame,
          transport: transport,
        );
        await client.open();
        final flushedBefore = frame.read(), writesBefore = frame.writes;
        final changes = <void Function(Map<String, dynamic>)>[
          (m) => m['afterOrder']['items'][0]['unitPrice'] = 100,
          (m) => m['afterOrder']['totalAmount'] = 999,
          (m) => m['afterOrder']['status'] = 'closed',
          (m) => m['afterReport']['events'][0]['newQty'] = 99,
          (m) => m['afterReport']['updatedAt'] = _opened.toIso8601String(),
          (m) => m['command']['price'] = 100,
          (m) => m['command']['requiresPrint'] = false,
        ];
        for (final change in changes) {
          await expectLater(() async {
            final plan = OperationalManagerItemsAdapter.adapt(
              view: fixture.view(),
              draft: _changed(draft, change),
            );
            await client.prepare(plan.intent);
          }(), _fails(OperationalPlanningFailureCode.invalidPlan));
        }
        expect(frame.writes, writesBefore);
        expect(frame.read(), flushedBefore);
        expect(client.pending, isNull);
        expect(transport.calls, 0);
      },
    );
    test(
      'changed canonical links, missing package/advance and stale view cannot masquerade as original intent',
      () {
        final fixture = _Fixture(), draft = fixture.draft();
        final altered = {
          ...fixture.orderLinks,
          '/createdBy': [_manager],
        };
        final rows = fixture.replacing(
          _order,
          fixture.entity(_order, fixture.beforeOrder, links: altered),
        );
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: fixture.view(entities: rows),
            draft: draft,
          ),
          _fails(OperationalPlanningFailureCode.ambiguousIdentity),
        );
        final missing = fixture.rows
            .where((r) => r.key.value != _advance.value)
            .toList();
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: fixture.view(entities: missing),
            draft: draft,
          ),
          _fails(OperationalPlanningFailureCode.missingDependency),
        );
        final control = Map<String, dynamic>.from(
          fixture.view().business(_control),
        );
        final newer = fixture.replacing(
          _control,
          fixture.entity(
            _control,
            control,
            links: {
              'currentDayId': [_day],
            },
            revision: 2,
          ),
        );
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: fixture.view(entities: newer, cursor: 2),
            draft: draft,
          ),
          _fails(OperationalPlanningFailureCode.staleView),
        );
      },
    );
    test(
      'locked report, settled/legacy status and duplicate original key refuse repair shortcuts',
      () {
        final fixture = _Fixture();
        final locked = OrderTransferIntent.cloneMap(fixture.beforeReport)
          ..['locked'] = true;
        expect(
          () => fixture.draft(
            projection: fixture.view(
              entities: fixture.replacing(
                _report,
                fixture.entity(_report, locked, links: fixture.reportLinks),
              ),
            ),
          ),
          _fails(OperationalPlanningFailureCode.recoveryRequired),
        );
        for (final status in [
          'closed',
          'cancelled',
          'preparing',
          'served',
          'unknown',
        ]) {
          final image = OrderTransferIntent.cloneMap(fixture.beforeOrder)
            ..['status'] = status;
          expect(
            () => fixture.draft(
              projection: fixture.view(
                entities: fixture.replacing(
                  _order,
                  fixture.entity(_order, image, links: fixture.orderLinks),
                ),
              ),
            ),
            _fails(OperationalPlanningFailureCode.unsupported),
          );
        }
        final duplicate = OrderTransferIntent.cloneMap(fixture.beforeOrder);
        duplicate['items'][1]['itemKey'] = 'a';
        expect(
          () => fixture.draft(
            projection: fixture.view(
              entities: fixture.replacing(
                _order,
                fixture.entity(_order, duplicate, links: fixture.orderLinks),
              ),
            ),
          ),
          _fails(OperationalPlanningFailureCode.ambiguousIdentity),
        );
      },
    );
    test(
      'draft and request are deeply detached; retained effect IDs cannot be reused',
      () {
        final fixture = _Fixture(), draft = fixture.draft();
        final returned = draft.toMap();
        returned['afterOrder']['items'][0]['quantity'] = 999;
        expect(draft.body['afterOrder']['items'][0]['quantity'], 2);
        expect(
          () => draft.body['afterOrder']['items'][0]['quantity'] = 999,
          throwsUnsupportedError,
        );
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: fixture.view(effects: {_id(1100)}),
            draft: draft,
          ),
          _fails(OperationalPlanningFailureCode.staleView),
        );
      },
    );
    test(
      'complete scan capacity fails rather than dropping read dependencies',
      () {
        final fixture = _Fixture(),
            extras = <OperationalIdentity>[],
            rows = [...fixture.rows];
        for (var i = 0; i < ProofBounds.reads; i++) {
          final key = _key(ProofEntityKind.table, 5000 + i),
              label = '${100 + i}';
          extras.add(
            OperationalIdentity(
              key: key,
              store: 'tables',
              legacyKey: i + 1000,
              tableRef: 'first/$label',
            ),
          );
          rows.add(
            fixture.entity(
              key,
              OrderTableMutationRepository.tableImage(
                TableModel(tableNumber: label, floor: 'first'),
              ),
            ),
          );
        }
        final resolver = OperationalIdentityResolver(
          identities: [
            for (final row in fixture.rows)
              fixture.identities.identity(row.key),
            ...extras,
          ],
          auditEffectIds: fixture.identities.auditEffectIds,
        );
        final view = fixture.view(entities: rows, resolver: resolver);
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: view,
            draft: fixture.draft(projection: view),
          ),
          _fails(OperationalPlanningFailureCode.capacity),
        );
      },
    );
    test(
      'contradictory report UUID and extra canonical business identity cannot be trusted',
      () {
        final fixture = _Fixture();
        final wrongReport = OrderTransferIntent.cloneMap(fixture.beforeReport);
        wrongReport['events'][0]['details']['orderUuid'] = _manager.id;
        final view = fixture.view(
          entities: fixture.replacing(
            _report,
            fixture.entity(_report, wrongReport, links: fixture.reportLinks),
          ),
        );
        expect(
          () => OperationalManagerItemsAdapter.adapt(
            view: view,
            draft: fixture.draft(projection: view),
          ),
          _fails(OperationalPlanningFailureCode.ambiguousIdentity),
        );
        final extra = OrderTransferIntent.cloneMap(fixture.beforeOrder)
          ..['canonicalOwnerUuid'] = _manager.id;
        expect(
          () => fixture.draft(
            projection: fixture.view(
              entities: fixture.replacing(
                _order,
                fixture.entity(_order, extra, links: fixture.orderLinks),
              ),
            ),
          ),
          _fails(OperationalPlanningFailureCode.invalidPlan),
        );
      },
    );
    test(
      'audit sequence and quantity arithmetic overflow fail before publishing',
      () {
        final fixture = _Fixture();
        final overflow = OrderTransferIntent.cloneMap(fixture.beforeReport);
        overflow['events'][2]['sequence'] = proofMaxInt64 - 1;
        final view = fixture.view(
          entities: fixture.replacing(
            _report,
            fixture.entity(_report, overflow, links: fixture.reportLinks),
          ),
        );
        expect(
          () => fixture.draft(projection: view),
          _fails(OperationalPlanningFailureCode.capacity),
        );
        final order = OrderTransferIntent.cloneMap(fixture.beforeOrder);
        order['items'][0]['unitPrice'] = 1e300;
        final huge = fixture.view(
          entities: fixture.replacing(
            _order,
            fixture.entity(_order, order, links: fixture.orderLinks),
          ),
        );
        expect(
          () => fixture.draft(
            projection: huge,
            intent: fixture.command(a: proofMaxInt64),
          ),
          _fails(OperationalPlanningFailureCode.capacity),
        );
      },
    );
    test(
      'three isolated clients race original control/report/Order; losers emit nothing',
      () async {
        final fixtures = [
          for (var i = 0; i < 3; i++)
            _Fixture(request: 100 + i, terminal: 90 + i),
        ];
        final server = _Coordinator(fixtures.first),
            clients = <OperationalProofClient>[];
        for (final fixture in fixtures) {
          final client = OperationalProofClient(
            binding: fixture.binding,
            store: _MemoryFrame(),
            transport: _Transport(server, fixture.binding),
          );
          await client.open();
          await client.prepare(fixture.plan().intent);
          clients.add(client);
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
        expect(server.commits, 1);
        expect(server.effects, hasLength(1));
        expect(server.entities[_control.value]!.revision, 2);
        final report = jsonDecode(
          utf8.decode(server.entities[_report.value]!.document),
        )['business'];
        expect(report['events'], hasLength(5));
        for (final result in results.where(
          (r) => r.outcome == ProofOutcome.conflict,
        )) {
          expect(
            server.effects.any(
              (e) =>
                  e.id ==
                  _id(
                    int.parse(result.requestId.split('-').last, radix: 16) +
                        1000,
                  ),
            ),
            isFalse,
          );
        }
      },
    );
    test(
      'lost ACK and real isolated Hive reopen retain exact request/result/UUID/audit once',
      () async {
        final fixture = _Fixture(), server = _Coordinator(fixture);
        final dir = await Directory.systemTemp.createTemp(
          'manager_items_proof_',
        );
        Hive.init(dir.path);
        var box = await Hive.openBox(
          'isolated_operational_proof_manager_items',
        );
        try {
          final transport = _Transport(server, fixture.binding)..loseAck = true;
          final client = OperationalProofClient(
            binding: fixture.binding,
            store: HiveOperationalProofFrameStore(box),
            transport: transport,
          );
          await client.open();
          final plan = fixture.plan();
          await client.prepare(plan.intent);
          await expectLater(
            client.sendPending(),
            throwsA(isA<SocketException>()),
          );
          expect(client.pending!.fingerprint, plan.intent.fingerprint);
          expect(client.entity(_order)!.revision, 1);
          expect(client.effectReceipts, isEmpty);
          await box.close();
          box = await Hive.openBox('isolated_operational_proof_manager_items');
          final durable = HiveOperationalProofFrameStore(box).read()!;
          expect(
            ProofIntent.fromFrame(durable['pending']).fingerprint,
            plan.intent.fingerprint,
          );
          final retryTransport = _Transport(server, fixture.binding)
            ..notFoundOnce = true;
          final reopened = OperationalProofClient(
            binding: fixture.binding,
            store: HiveOperationalProofFrameStore(box),
            transport: retryTransport,
          );
          await reopened.open();
          final result = reopened.lastResult!;
          expect(result.fingerprint, server.results[_id(100)]!.fingerprint);
          expect(server.hashes, [
            plan.intent.fingerprint,
            plan.intent.fingerprint,
          ]);
          expect(server.commits, 1);
          expect(server.effects, hasLength(1));
          expect(reopened.effectReceipts, hasLength(1));
          expect(reopened.pending, isNull);
          final order = jsonDecode(
            utf8.decode(reopened.entity(_order)!.document),
          )['business'];
          expect(order['items'].single['lineUuid'], _id(70));
          expect(
            jsonDecode(
              utf8.decode(reopened.entity(_report)!.document),
            )['business']['events'],
            hasLength(5),
          );
        } finally {
          await box.close();
          await dir.delete(recursive: true);
        }
      },
    );
  });

  group('actual local Hive Manager ORDER_UPDATE parity', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('manager_items_legacy_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserAdapter());
      if (!Hive.isAdapterRegistered(2))
        Hive.registerAdapter(TableModelAdapter());
      if (!Hive.isAdapterRegistered(3))
        Hive.registerAdapter(OrderItemAdapter());
      if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
      DatabaseCore.settingsBox = await Hive.openBox('manager_items_settings');
      DatabaseCore.auditLogBox = await Hive.openBox('manager_items_audit');
      DatabaseCore.orderBox = await Hive.openBox<Order>('manager_items_orders');
      DatabaseCore.tableBox = await Hive.openBox<TableModel>(
        'manager_items_tables',
      );
      DatabaseCore.userBox = await Hive.openBox<User>('manager_items_staff');
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-06T00:00:00.000',
      );
      LocalDataAdmission.failure = null;
      UpdateReadiness.enabled = false;
      UpdateReadiness.failure = null;
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
      DatabaseCore.settingsBox = null;
      DatabaseCore.auditLogBox = null;
      DatabaseCore.orderBox = null;
      DatabaseCore.tableBox = null;
      DatabaseCore.userBox = null;
      Order.serviceFeeRateResolver = null;
      Order.timestampResolver = null;
      LocalDataAdmission.failure = null;
      UpdateReadiness.failure = null;
      ManagerNotificationInbox.resetSession();
    });
    for (final variant in [0, 1, 2]) {
      test(
        'real business/report parity variant $variant; legacy UUID/clock differences explicitly normalized',
        () async {
          final fixture = _Fixture(
                rate: variant == 0 ? 0 : .2,
                custom: variant == 1 ? 5 : null,
                package: variant == 2,
              ),
              plan = fixture.plan();
          await DatabaseCore.orderBox!.put(
            700,
            OrderTransferIntent.orderImage(fixture.beforeOrder),
          );
          final table = fixture.rows.singleWhere(
            (r) => r.key.value == _table.value,
          );
          await DatabaseCore.tableBox!.put(
            'physical',
            TableModel.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(utf8.decode(table.document))['business'],
              ),
            ),
          );
          await DatabaseCore.auditLogBox!.put(
            'audit_report_order_1',
            fixture.beforeReport,
          );
          Order.serviceFeeRateResolver = () => fixture.rate;
          final input = OrderTransferIntent.cloneMap(
            fixture.beforeOrder['items'][0],
          )..['quantity'] = 2;
          final outcome = await PosCommandApplier.updateOrder({
            'posOrderId': 1,
            'items': [input],
            'updatedBy': 'manager',
            'includeServiceFee': fixture.beforeOrder['includeServiceFee'],
          });
          expect(outcome.ok, isTrue);
          final actualOrder = OrderTableMutationRepository.image(
            DatabaseCore.orderBox!.get(700)!,
          );
          final expectedOrder = _business(
            plan.intent.writes.singleWhere((w) => w.key.value == _order.value),
          );
          // Legacy ingress regenerates UUIDs and reads several wall clocks. Those
          // fields require future authority capture; every other field is compared.
          expect(actualOrder['items'][0]['lineUuid'], isNot(_id(70)));
          actualOrder['items'][0]['lineUuid'] = _id(70);
          actualOrder['updatedAt'] = expectedOrder['updatedAt'];
          expect(actualOrder, expectedOrder);
          final actualReport = OrderTransferIntent.cloneMap(
            DatabaseCore.auditLogBox!.get('audit_report_order_1') as Map,
          );
          final expectedReport = _business(
            plan.intent.writes.singleWhere((w) => w.key.value == _report.value),
          );
          expect(
            actualReport['events'].take(3).toList(),
            fixture.beforeReport['events'],
          );
          for (var i = 3; i < actualReport['events'].length; i++) {
            actualReport['events'][i]['timestamp'] =
                expectedReport['events'][i]['timestamp'];
          }
          actualReport['updatedAt'] = expectedReport['updatedAt'];
          expect(actualReport, expectedReport);
          expect(
            DatabaseCore.auditLogBox!.keys.toList(),
            ['audit_report_order_1'],
            reason:
                'Same fee must not produce MoneyAudit or unrelated GlobalAudit',
          );
          expect(OrderTableMutationRepository.integrityReport(), isEmpty);
        },
      );
    }
  });
}
