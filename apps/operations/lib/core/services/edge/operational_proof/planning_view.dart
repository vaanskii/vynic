import 'dart:convert';

import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/table_ref.dart';

import 'domain.dart';

enum OperationalPlanningFailureCode {
  unsupported,
  missingDependency,
  ambiguousIdentity,
  invalidPlan,
  staleView,
  ownershipConflict,
  recoveryRequired,
  capacity,
}

class OperationalPlanningFailure extends StateError {
  OperationalPlanningFailure(this.code, String message) : super(message);
  final OperationalPlanningFailureCode code;
}

void planningRequire(
  bool condition,
  OperationalPlanningFailureCode code,
  String detail,
) {
  if (!condition) throw OperationalPlanningFailure(code, detail);
}

dynamic _freeze(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, value) => MapEntry(key as String, _freeze(value))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

Map<String, dynamic> planningFreeze(Map<String, dynamic> value) =>
    _freeze(jsonDecode(jsonEncode(value))) as Map<String, dynamic>;

void planningOrderImageInputs(Map<String, dynamic> image) {
  planningRequire(
    image['orderUuid'] is String &&
        proofUuid(image['orderUuid']) &&
        image['createdAt'] is String &&
        DateTime.tryParse(image['createdAt']) != null &&
        image['items'] is List &&
        image['packageItems'] is List,
    OperationalPlanningFailureCode.invalidPlan,
    'Order lacks frozen UUID/time/line collections',
  );
  for (final field in ['updatedAt', 'closedAt'])
    planningRequire(
      image[field] == null ||
          image[field] is String && DateTime.tryParse(image[field]) != null,
      OperationalPlanningFailureCode.invalidPlan,
      'Invalid frozen Order time',
    );
  final ids = <String>{};
  for (final line in [
    ...image['items'] as List,
    ...image['packageItems'] as List,
  ])
    planningRequire(
      line is Map &&
          line['lineUuid'] is String &&
          proofUuid(line['lineUuid']) &&
          ids.add(line['lineUuid']),
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Missing or repeated frozen line identity',
    );
}

/// These are supplied bootstrap identities, never derived from Hive positions,
/// table labels, a numeric order number, a wall clock or an implicit UUID factory.
class OperationalIdentity {
  OperationalIdentity({
    required this.key,
    required this.store,
    required this.legacyKey,
    this.orderNumber,
    this.tableRef,
    this.legacyId,
  }) {
    planningRequire(
      legacyKey is int ||
          legacyKey is String && (legacyKey as String).isNotEmpty,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Legacy key must be an explicit integer or nonempty string',
    );
    planningRequire(
      orderNumber == null ||
          key.kind == ProofEntityKind.order && orderNumber! > 0,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Numeric order identity',
    );
    planningRequire(
      tableRef == null ||
          key.kind == ProofEntityKind.table &&
              TableRef.tryDecode(tableRef!)?.encode() == tableRef,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Physical table identity',
    );
    planningRequire(
      legacyId == null || legacyId!.isNotEmpty,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Legacy business identity',
    );
  }
  final ProofKey key;
  final String store;
  final Object legacyKey;
  final int? orderNumber;
  final String? tableRef, legacyId;
}

class OperationalIdentityResolver {
  OperationalIdentityResolver({
    required List<OperationalIdentity> identities,
    required Map<String, String> auditEffectIds,
  }) : auditEffectIds = Map.unmodifiable(auditEffectIds) {
    planningRequire(
      identities.length <= ProofBounds.entities + ProofBounds.writes &&
          auditEffectIds.length <= ProofBounds.requestEffects,
      OperationalPlanningFailureCode.capacity,
      'Frozen identity capacity',
    );
    for (final row in identities) {
      planningRequire(
        row.store == storeFor(row.key.kind),
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Legacy store does not identify the canonical kind',
      );
      _insert(_keys, row.key.value, row);
      _insert(_legacy, _legacyIndex(row.store, row.legacyKey), row);
      if (row.orderNumber != null) _insert(_orders, '${row.orderNumber}', row);
      if (row.tableRef != null) _insert(_tables, row.tableRef!, row);
      if (row.legacyId != null)
        _insert(_names, '${row.key.kind.name}/${row.legacyId}', row);
    }
    final effects = <String>{};
    for (final entry in this.auditEffectIds.entries) {
      planningRequire(
        entry.key.isNotEmpty &&
            entry.key.length <= 256 &&
            proofUuid(entry.value) &&
            effects.add(entry.value),
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Immutable audit identity missing or reused',
      );
    }
  }
  final Map<String, OperationalIdentity> _keys = {},
      _legacy = {},
      _orders = {},
      _tables = {},
      _names = {};
  final Map<String, String> auditEffectIds;
  static String storeFor(ProofEntityKind kind) => switch (kind) {
    ProofEntityKind.order => 'orders',
    ProofEntityKind.table => 'tables',
    ProofEntityKind.reservation => 'reservation',
    ProofEntityKind.package => 'packages',
    ProofEntityKind.sale => 'sales',
    ProofEntityKind.day => 'businessDays',
    ProofEntityKind.operationalControl => 'operationalControl',
    ProofEntityKind.auditReport => 'auditReport',
    ProofEntityKind.closure => 'closures',
    ProofEntityKind.advance => 'advances',
    ProofEntityKind.expense => 'expenses',
    ProofEntityKind.staff => 'staff',
    ProofEntityKind.operationalPolicy => 'operationalPolicy',
  };
  static String _legacyIndex(String store, Object key) =>
      '$store/${jsonEncode(key)}';
  static void _insert(
    Map<String, OperationalIdentity> map,
    String key,
    OperationalIdentity row,
  ) {
    planningRequire(
      !map.containsKey(key),
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Duplicate canonical, legacy or business identity: $key',
    );
    map[key] = row;
  }

  static OperationalIdentity _require(
    Map<String, OperationalIdentity> map,
    String key,
  ) {
    final row = map[key];
    if (row == null)
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.missingDependency,
        'Unresolved stable identity: $key',
      );
    return row;
  }

  OperationalIdentity identity(ProofKey key) => _require(_keys, key.value);
  OperationalIdentity legacy(String store, Object key) =>
      _require(_legacy, _legacyIndex(store, key));
  OperationalIdentity order(int number) => _require(_orders, '$number');
  OperationalIdentity table(String ref) => _require(_tables, ref);
  OperationalIdentity named(ProofEntityKind kind, String id) =>
      _require(_names, '${kind.name}/$id');
  String effect(String legacyId) {
    final id = auditEffectIds[legacyId];
    if (id == null)
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.missingDependency,
        'Unresolved immutable audit: $legacyId',
      );
    return id;
  }
}

class OperationalPlanningContext {
  OperationalPlanningContext({
    required this.requestId,
    required this.actorId,
    required this.actorName,
    required this.occurredAt,
    required this.source,
  }) {
    planningRequire(
      proofUuid(requestId) &&
          actorId.isNotEmpty &&
          actorId == actorId.trim() &&
          actorName.isNotEmpty &&
          actorName == actorName.trim() &&
          occurredAt.microsecondsSinceEpoch % 1000 == 0,
      OperationalPlanningFailureCode.invalidPlan,
      'Request, actor and millisecond time must already be frozen',
    );
  }
  final String requestId, actorId, actorName;
  final DateTime occurredAt;
  final AuditSource source;
}

/// A complete detached canonical projection at the operator's verified cursor.
/// Caller obtains this from the isolated client's committed state, once. It must
/// never refresh these revisions after the operator chooses an action. Control
/// CAS fences all collection scans; capacity is rejected, never truncated.
class OperationalPlanningView {
  OperationalPlanningView({
    required this.binding,
    required this.cursor,
    required this.context,
    required this.identities,
    required this.controlKey,
    required this.dayKey,
    required this.policyKey,
    required this.actorKey,
    required List<ProofEntity> entities,
    required Set<String> retainedEffectIds,
  }) : entities = List.unmodifiable(entities),
       retainedEffectIds = Set.unmodifiable(retainedEffectIds) {
    proofInteger(cursor);
    planningRequire(
      entities.length <= ProofBounds.entities,
      OperationalPlanningFailureCode.capacity,
      'Projection entity capacity',
    );
    planningRequire(
      retainedEffectIds.length <= ProofBounds.effects &&
          retainedEffectIds.every(proofUuid),
      OperationalPlanningFailureCode.capacity,
      'Retained immutable effect identities',
    );
    for (final entity in this.entities) {
      planningRequire(
        entity.revision > 0 &&
            entity.revision <= cursor &&
            !_entities.containsKey(entity.key.value),
        OperationalPlanningFailureCode.invalidPlan,
        'Canonical entity revision/identity',
      );
      identities.identity(entity.key);
      _entities[entity.key.value] = entity;
      if (!entity.tombstone) _business[entity.key.value] = _decode(entity);
    }
    planningRequire(
      controlKey.kind == ProofEntityKind.operationalControl &&
          dayKey.kind == ProofEntityKind.day &&
          policyKey.kind == ProofEntityKind.operationalPolicy &&
          actorKey.kind == ProofEntityKind.staff,
      OperationalPlanningFailureCode.invalidPlan,
      'Typed planning roots',
    );
    final c = business(controlKey),
        d = business(dayKey),
        p = business(policyKey),
        a = business(actorKey);
    planningRequire(
      c['lastOrderId'] is int &&
          c['lastOrderId'] >= 0 &&
          c['lastOrderId'] < proofMaxInt64 &&
          c['currentDayId'] == dayKey.id &&
          c['recoveryGeneration'] is int &&
          c['recoveryGeneration'] >= 0,
      OperationalPlanningFailureCode.invalidPlan,
      'Explicit canonical control',
    );
    planningRequire(
      c['phase'] == 'operational',
      OperationalPlanningFailureCode.recoveryRequired,
      'Shared control is not operational',
    );
    planningRequire(
      d['date'] is String &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d['date']) &&
          d['status'] == 'open',
      OperationalPlanningFailureCode.recoveryRequired,
      'Admitted open Day',
    );
    final rate = p['serviceFeeRate'];
    planningRequire(
      rate is num &&
          rate.isFinite &&
          rate >= 0 &&
          rate <= 1 &&
          p['defaultIncludeServiceFee'] is bool &&
          p['cancelRequiresApproval'] is bool &&
          p['menuRevision'] is int &&
          p['menuRevision'] >= 0 &&
          p['inventoryRevision'] is int &&
          p['inventoryRevision'] >= 0 &&
          p['menuFingerprint'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(p['menuFingerprint']) &&
          p['runtimeFingerprint'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(p['runtimeFingerprint']),
      OperationalPlanningFailureCode.missingDependency,
      'Explicit admitted policy/catalog inputs',
    );
    planningRequire(
      a['username'] == context.actorId &&
          a['enabled'] == true &&
          a['permissions'] is List &&
          identities.named(ProofEntityKind.staff, context.actorId).key.value ==
              actorKey.value,
      OperationalPlanningFailureCode.missingDependency,
      'Frozen actor authority',
    );
    planningRequire(
      entities.fold<int>(0, (n, e) => n + e.document.length) <=
          ProofBounds.stateBytes,
      OperationalPlanningFailureCode.capacity,
      'Projection byte capacity',
    );
  }
  final ProofBinding binding;
  final int cursor;
  final OperationalPlanningContext context;
  final OperationalIdentityResolver identities;
  final ProofKey controlKey, dayKey, policyKey, actorKey;
  final List<ProofEntity> entities;
  final Set<String> retainedEffectIds;
  final Map<String, ProofEntity> _entities = {};
  final Map<String, Map<String, dynamic>> _business = {};

  static List<int> encodeDocument({
    required ProofBinding binding,
    required ProofKey key,
    required Map<String, dynamic> business,
    Map<String, List<ProofKey>> references = const {},
  }) => utf8.encode(
    jsonEncode({
      'version': 1,
      'venueId': binding.venueId,
      'identity': key.toFrame(),
      'business': business,
      'references': {
        for (final field in references.keys.toList()..sort())
          field:
              (references[field]!.toList()
                    ..sort((a, b) => a.value.compareTo(b.value)))
                  .map((v) => v.toFrame())
                  .toList(),
      },
    }),
  );

  Map<String, dynamic> _decode(ProofEntity entity) {
    final envelope = proofMap(jsonDecode(utf8.decode(entity.document)), {
      'version',
      'venueId',
      'identity',
      'business',
      'references',
    });
    planningRequire(
      envelope['version'] == 1 &&
          envelope['venueId'] == binding.venueId &&
          ProofKey.fromFrame(envelope['identity']).value == entity.key.value &&
          envelope['business'] is Map &&
          envelope['references'] is Map,
      OperationalPlanningFailureCode.invalidPlan,
      'Canonical business envelope binding',
    );
    for (final raw in (envelope['references'] as Map).values) {
      for (final ref in proofList(raw, ProofKey.fromFrame))
        identities.identity(ref);
    }
    final business = Map<String, dynamic>.from(envelope['business']);
    if (entity.key.kind == ProofEntityKind.order)
      planningOrderImageInputs(business);
    return planningFreeze(business);
  }

  ProofEntity? entity(ProofKey key) => _entities[key.value];
  Map<String, dynamic> business(ProofKey key) {
    final value = _business[key.value];
    if (value == null)
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.missingDependency,
        'Live canonical dependency missing: ${key.value}',
      );
    return value;
  }

  List<ProofEntity> kind(ProofEntityKind kind) =>
      List.unmodifiable(entities.where((e) => e.key.kind == kind));
  String get businessDate => business(dayKey)['date'];
  int get lastOrderId => business(controlKey)['lastOrderId'];
  double get serviceFeeRate =>
      (business(policyKey)['serviceFeeRate'] as num).toDouble();
  Map<String, dynamic> provenance() => {
    'mode': operationalProofMode,
    'binding': binding.fingerprint,
    'requestId': context.requestId,
    'cursor': '$cursor',
    'controlRevision': '${entity(controlKey)!.revision}',
    'dayRevision': '${entity(dayKey)!.revision}',
    'policyRevision': '${entity(policyKey)!.revision}',
    'actorRevision': '${entity(actorKey)!.revision}',
    'occurredAt': context.occurredAt.toIso8601String(),
    'menuRevision': business(policyKey)['menuRevision'],
    'menuFingerprint': business(policyKey)['menuFingerprint'],
  };
  void authorize(String operation) => planningRequire(
    (business(actorKey)['permissions'] as List).contains(operation),
    OperationalPlanningFailureCode.unsupported,
    'Actor lacks frozen $operation permission',
  );
}

class OperationalPlanningReads {
  OperationalPlanningReads(this.view) {
    read(view.controlKey);
    read(view.dayKey);
    read(view.policyKey);
    read(view.actorKey);
  }
  final OperationalPlanningView view;
  final Map<String, ProofRead> _reads = {};
  void read(ProofKey key, {bool allowAbsent = false}) {
    view.identities.identity(key);
    final entity = view.entity(key);
    planningRequire(
      allowAbsent || entity != null && !entity.tombstone,
      OperationalPlanningFailureCode.missingDependency,
      'Missing planning dependency: ${key.value}',
    );
    _reads[key.value] = ProofRead(
      key: key,
      expectedRevision: entity?.revision ?? 0,
      expectedTombstone: entity?.tombstone ?? false,
    );
  }

  Map<String, dynamic> business(ProofKey key) {
    read(key);
    return view.business(key);
  }

  List<ProofEntity> scan(ProofEntityKind kind) {
    final rows = view.kind(kind);
    for (final row in rows) read(row.key, allowAbsent: true);
    return rows.where((e) => !e.tombstone).toList();
  }

  List<ProofRead> get values => List.unmodifiable(_reads.values);
}
