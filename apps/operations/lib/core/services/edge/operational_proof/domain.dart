import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Local isolated domain objects and durable-frame encoding only. These are
/// neither generated messages nor a JSON/HTTP alternative to the canonical RPC.
const operationalProofMode = 'ISOLATED_PROOF';
const operationalProofCapability = 'operational.coordination.proof.v1';
const operationalProofPrintCapability = 'operational.print.queue.proof.v1';
const operationalProofPrintAdmission = 'vynic-print-queue.v1';
const proofMaxInt64 = 9223372036854775807;

class ProofBounds {
  static const requestBytes = 16 << 20;
  static const documentBytes = 1 << 20;
  static const effectBytes = 12 << 20;
  static const applicationBytes = 1 << 20;
  static const eventBytes = 18 << 20;
  static const resultBytes = 48 << 20;
  static const snapshotBytes = 48 << 20;
  static const replayBytes = 32 << 20;
  static const stateBytes = 32 << 20;
  static const frameBytes = 128 << 20;
  static const entities = 2048;
  static const events = 10000;
  static const effects = 20000;
  static const writes = 128;
  static const reads = 256;
  static const requestEffects = 128;
  static const replayEvents = 100;
  static const storeRequests = 10000;

  /// Expected proof-store admission limits. A later RPC adapter supplies these
  /// from authenticated status; no transport or authority defaults are inferred.
  static const storeLimits = <String, int>{
    'requestBytes': requestBytes,
    'documentBytes': documentBytes,
    'effectBytes': effectBytes,
    'applicationBytes': applicationBytes,
    'eventBytes': eventBytes,
    'resultBytes': resultBytes,
    'snapshotBytes': snapshotBytes,
    'replayBytes': replayBytes,
    'stateBytes': stateBytes,
    'journalBytes': frameBytes,
    'entities': entities,
    'requests': storeRequests,
    'events': events,
    'effects': effects,
    'writes': writes,
    'reads': reads,
    'requestEffects': requestEffects,
    'replayEvents': replayEvents,
  };
}

void proofRequire(bool condition, String detail) {
  if (!condition) throw FormatException('Invalid isolated proof: $detail');
}

bool proofUuid(String value) =>
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value) &&
    value != '00000000-0000-0000-0000-000000000000';

void proofInteger(int value, {bool positive = false}) => proofRequire(
  value >= (positive ? 1 : 0) && value <= proofMaxInt64,
  'signed 64-bit integer',
);

int proofDecimal(dynamic raw) {
  proofRequire(
    raw is String && RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw),
    'decimal integer encoding',
  );
  final value = int.tryParse(raw as String);
  proofRequire(value != null, 'integer overflow');
  proofInteger(value!);
  return value;
}

List<int> proofBytes(List<int> bytes, int maximum) {
  proofRequire(
    bytes.length <= maximum && bytes.every((v) => v >= 0 && v <= 255),
    'byte bounds',
  );
  return List<int>.unmodifiable(bytes);
}

List<int> proofDecodeBytes(dynamic value) {
  proofRequire(value is String, 'byte encoding');
  final bytes = base64Decode(value as String);
  proofRequire(base64Encode(bytes) == value, 'canonical byte encoding');
  return bytes;
}

Map<String, dynamic> proofMap(dynamic raw, Set<String> fields) {
  proofRequire(raw is Map, 'durable object');
  final body = Map<String, dynamic>.from(raw as Map);
  proofRequire(
    body.length == fields.length && body.keys.toSet().containsAll(fields),
    'durable object fields',
  );
  return body;
}

/// Old proof frames omit admission metadata and preserve their fingerprints.
/// Queued requests retain the exact explicit discriminator through restart.
Map<String, dynamic> proofAdmissionMap(
  dynamic raw,
  Set<String> fields, {
  bool producer = false,
  bool receipts = false,
}) {
  final hasAdmission = raw is Map && raw.containsKey('printAdmission');
  final hasOrigin =
      producer && raw is Map && raw.containsKey('originInstallationId');
  final hasReceipts =
      receipts && raw is Map && raw.containsKey('printReceipts');
  final body = proofMap(raw, {
    ...fields,
    if (hasAdmission) 'printAdmission',
    if (hasOrigin) 'originInstallationId',
    if (hasReceipts) 'printReceipts',
  });
  if (hasAdmission) {
    proofRequire(
      body['printAdmission'] == operationalProofPrintAdmission,
      'exact immutable print admission',
    );
  }
  if (producer) {
    proofRequire(
      hasAdmission == hasOrigin && (!hasReceipts || hasAdmission),
      'admission origin fields',
    );
    if (hasOrigin)
      proofRequire(
        proofUuid(body['originInstallationId']),
        'producer origin UUID',
      );
  }
  return body;
}

void proofPrintAdmission(String value) => proofRequire(
  value.isEmpty || value == operationalProofPrintAdmission,
  'known print admission',
);

List<T> proofList<T>(dynamic raw, T Function(dynamic) decode) {
  proofRequire(raw is List, 'durable list');
  return (raw as List).map(decode).toList();
}

String proofFingerprint(Map<String, dynamic> frame) =>
    sha256.convert(utf8.encode(jsonEncode(frame))).toString();

void proofDocument(
  List<int> bytes, {
  required bool tombstone,
  required bool absent,
}) {
  if (tombstone || absent) {
    proofRequire(
      bytes.isEmpty && !(tombstone && absent),
      'absent/tombstone document',
    );
  } else {
    proofRequire(
      bytes.isNotEmpty && jsonDecode(utf8.decode(bytes)) is Map,
      'complete JSON object postimage',
    );
  }
}

class ProofBinding {
  ProofBinding({
    required this.installationId,
    required this.venueId,
    required this.terminalId,
    required this.epoch,
    required this.grantFingerprint,
    required this.mode,
    this.originInstallationId = '',
  }) {
    proofRequire(
      mode == operationalProofMode &&
          proofUuid(installationId) &&
          proofUuid(venueId) &&
          proofUuid(terminalId),
      'pinned proof identity',
    );
    proofInteger(epoch, positive: true);
    proofRequire(
      originInstallationId.isEmpty || proofUuid(originInstallationId),
      'pinned origin UUID',
    );
    proofRequire(
      RegExp(r'^[0-9a-f]{64}$').hasMatch(grantFingerprint),
      'grant fingerprint',
    );
  }
  final String installationId, venueId, terminalId, grantFingerprint, mode;
  final String originInstallationId;
  final int epoch;
  String get fingerprint => proofFingerprint(toFrame());
  Map<String, dynamic> toFrame() => {
    'installationId': installationId,
    'venueId': venueId,
    'terminalId': terminalId,
    'epoch': '$epoch',
    'grantFingerprint': grantFingerprint,
    'mode': mode,
    if (originInstallationId.isNotEmpty)
      'originInstallationId': originInstallationId,
  };
  factory ProofBinding.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'installationId',
      'venueId',
      'terminalId',
      'epoch',
      'grantFingerprint',
      'mode',
      if (raw is Map && raw.containsKey('originInstallationId'))
        'originInstallationId',
    });
    return ProofBinding(
      installationId: b['installationId'],
      venueId: b['venueId'],
      terminalId: b['terminalId'],
      epoch: proofDecimal(b['epoch']),
      grantFingerprint: b['grantFingerprint'],
      mode: b['mode'],
      originInstallationId: b['originInstallationId'] ?? '',
    );
  }
}

/// Explicit state in the isolated proof, independent of ordinary POS storage.
/// A future detached planner must CAS-write the Venue's stable operationalControl
/// row (lastOrderId, currentDayId and admitted operation/recovery phase) with every
/// shared mutation to serialize allocation and fence scanned dependencies.
/// Mutable auditReport state remains distinct from immutable AUDIT/PRINT effects.
enum ProofEntityKind {
  order,
  table,
  reservation,
  package,
  sale,
  day,
  operationalControl,
  auditReport,
  closure,
  advance,
  expense,
  staff,
  operationalPolicy,
}

enum ProofEffectKind { audit, print }

enum ProofOutcome { committed, conflict }

class ProofKey {
  ProofKey(this.kind, this.id) {
    proofRequire(proofUuid(id), 'entity UUID');
  }
  final ProofEntityKind kind;
  final String id;
  String get value => '${kind.name}/$id';
  Map<String, dynamic> toFrame() => {'kind': kind.name, 'id': id};
  factory ProofKey.fromFrame(dynamic raw) {
    final b = proofMap(raw, {'kind', 'id'});
    return ProofKey(ProofEntityKind.values.byName(b['kind']), b['id']);
  }
}

class ProofEntity {
  ProofEntity({
    required this.key,
    required this.revision,
    required this.tombstone,
    required List<int> document,
  }) : document = proofBytes(document, ProofBounds.documentBytes) {
    proofInteger(revision);
    proofDocument(this.document, tombstone: tombstone, absent: revision == 0);
  }
  final ProofKey key;
  final int revision;
  final bool tombstone;
  final List<int> document;
  Map<String, dynamic> toFrame() => {
    'key': key.toFrame(),
    'revision': '$revision',
    'tombstone': tombstone,
    'document': base64Encode(document),
  };
  factory ProofEntity.fromFrame(dynamic raw) {
    final b = proofMap(raw, {'key', 'revision', 'tombstone', 'document'});
    return ProofEntity(
      key: ProofKey.fromFrame(b['key']),
      revision: proofDecimal(b['revision']),
      tombstone: b['tombstone'],
      document: proofDecodeBytes(b['document']),
    );
  }
}

class ProofRead {
  ProofRead({
    required this.key,
    required this.expectedRevision,
    this.expectedTombstone = false,
  }) {
    proofInteger(expectedRevision);
    proofRequire(
      expectedRevision != 0 || !expectedTombstone,
      'absent read tombstone',
    );
  }
  final ProofKey key;
  final int expectedRevision;
  final bool expectedTombstone;
  Map<String, dynamic> toFrame() => {
    'key': key.toFrame(),
    'expectedRevision': '$expectedRevision',
    'expectedTombstone': expectedTombstone,
  };
  factory ProofRead.fromFrame(dynamic raw) {
    final b = proofMap(raw, {'key', 'expectedRevision', 'expectedTombstone'});
    return ProofRead(
      key: ProofKey.fromFrame(b['key']),
      expectedRevision: proofDecimal(b['expectedRevision']),
      expectedTombstone: b['expectedTombstone'],
    );
  }
}

class ProofWrite {
  ProofWrite({
    required this.key,
    required this.expectedRevision,
    required this.tombstone,
    required List<int> document,
  }) : document = proofBytes(document, ProofBounds.documentBytes) {
    proofInteger(expectedRevision);
    proofRequire(
      expectedRevision < proofMaxInt64 && (!tombstone || expectedRevision > 0),
      'write revision',
    );
    proofDocument(this.document, tombstone: tombstone, absent: false);
  }
  final ProofKey key;
  final int expectedRevision;
  final bool tombstone;
  final List<int> document;
  Map<String, dynamic> toFrame() => {
    'key': key.toFrame(),
    'expectedRevision': '$expectedRevision',
    'tombstone': tombstone,
    'document': base64Encode(document),
  };
  factory ProofWrite.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'key',
      'expectedRevision',
      'tombstone',
      'document',
    });
    return ProofWrite(
      key: ProofKey.fromFrame(b['key']),
      expectedRevision: proofDecimal(b['expectedRevision']),
      tombstone: b['tombstone'],
      document: proofDecodeBytes(b['document']),
    );
  }
}

class ProofEffect {
  ProofEffect({
    required this.id,
    required this.kind,
    required List<int> payload,
  }) : payload = proofBytes(payload, ProofBounds.effectBytes) {
    proofRequire(proofUuid(id) && this.payload.isNotEmpty, 'frozen effect');
  }
  final String id;
  final ProofEffectKind kind;
  final List<int> payload;
  Map<String, dynamic> toFrame() => {
    'id': id,
    'kind': kind.name,
    'payload': base64Encode(payload),
  };
  factory ProofEffect.fromFrame(dynamic raw) {
    final b = proofMap(raw, {'id', 'kind', 'payload'});
    return ProofEffect(
      id: b['id'],
      kind: ProofEffectKind.values.byName(b['kind']),
      payload: proofDecodeBytes(b['payload']),
    );
  }
}

void proofUnique<T>(Iterable<T> values, String Function(T) key) => proofRequire(
  values.map(key).toSet().length == values.length,
  'duplicate identity',
);

class ProofIntent {
  ProofIntent({
    required this.binding,
    required this.requestId,
    List<ProofRead> reads = const [],
    required List<ProofWrite> writes,
    List<ProofEffect> effects = const [],
    List<int> applicationData = const [],
    this.printAdmission = '',
  }) : reads = List.unmodifiable(reads),
       writes = List.unmodifiable(writes),
       effects = List.unmodifiable(effects),
       applicationData = proofBytes(
         applicationData,
         ProofBounds.applicationBytes,
       ) {
    proofPrintAdmission(printAdmission);
    proofRequire(
      printAdmission.isEmpty || proofUuid(binding.originInstallationId),
      'queued intent pinned origin',
    );
    proofRequire(
      proofUuid(requestId) &&
          this.writes.isNotEmpty &&
          this.writes.length <= ProofBounds.writes &&
          this.reads.length <= ProofBounds.reads &&
          this.effects.length <= ProofBounds.requestEffects,
      'intent counts/identity',
    );
    proofUnique(this.reads, (v) => v.key.value);
    proofUnique(this.writes, (v) => v.key.value);
    proofUnique(this.effects, (v) => v.id);
    for (final read in this.reads) {
      for (final write in this.writes.where(
        (v) => v.key.value == read.key.value,
      )) {
        proofRequire(
          read.expectedRevision == write.expectedRevision &&
              !read.expectedTombstone,
          'inconsistent read/write dependency',
        );
      }
    }
    proofRequire(
      utf8.encode(jsonEncode(toFrame())).length <= ProofBounds.requestBytes,
      'encoded request bound',
    );
  }
  final ProofBinding binding;
  final String requestId;
  final List<ProofRead> reads;
  final List<ProofWrite> writes;
  final List<ProofEffect> effects;
  final List<int> applicationData;
  final String printAdmission;
  String get originInstallationId =>
      printAdmission.isEmpty ? '' : binding.originInstallationId;

  /// Local immutable identity only; a future generated transport owns wire hashing.
  String get fingerprint => proofFingerprint(toFrame());
  Map<String, dynamic> toFrame() => {
    'binding': binding.toFrame(),
    'requestId': requestId,
    'reads': reads.map((v) => v.toFrame()).toList(),
    'writes': writes.map((v) => v.toFrame()).toList(),
    'effects': effects.map((v) => v.toFrame()).toList(),
    'applicationData': base64Encode(applicationData),
    if (printAdmission.isNotEmpty) 'printAdmission': printAdmission,
  };
  factory ProofIntent.fromFrame(dynamic raw) {
    final b = proofAdmissionMap(raw, {
      'binding',
      'requestId',
      'reads',
      'writes',
      'effects',
      'applicationData',
    });
    return ProofIntent(
      binding: ProofBinding.fromFrame(b['binding']),
      requestId: b['requestId'],
      reads: proofList(b['reads'], ProofRead.fromFrame),
      writes: proofList(b['writes'], ProofWrite.fromFrame),
      effects: proofList(b['effects'], ProofEffect.fromFrame),
      applicationData: proofDecodeBytes(b['applicationData']),
      printAdmission: b['printAdmission'] ?? '',
    );
  }
}

/// Immutable queue admission truth. This is never a paper-delivery receipt or
/// a permission to execute an effect. It survives replay, lost ACK and restart.
class ProofPrintReceipt {
  ProofPrintReceipt({
    required this.version,
    required this.jobId,
    required this.effectId,
    required this.physicalPrinterId,
    required this.sequence,
    required this.admissionSha256,
  }) {
    proofRequire(
      version == 1 &&
          proofUuid(jobId) &&
          proofUuid(effectId) &&
          proofUuid(physicalPrinterId) &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(admissionSha256),
      'queue receipt identity',
    );
    proofInteger(sequence, positive: true);
  }
  final int version, sequence;
  final String jobId, effectId, physicalPrinterId, admissionSha256;
  Map<String, dynamic> toFrame() => {
    'version': version,
    'jobId': jobId,
    'effectId': effectId,
    'physicalPrinterId': physicalPrinterId,
    'sequence': '$sequence',
    'admissionSha256': admissionSha256,
  };
  factory ProofPrintReceipt.fromFrame(dynamic raw) {
    final b = proofMap(raw, {
      'version',
      'jobId',
      'effectId',
      'physicalPrinterId',
      'sequence',
      'admissionSha256',
    });
    return ProofPrintReceipt(
      version: b['version'],
      jobId: b['jobId'],
      effectId: b['effectId'],
      physicalPrinterId: b['physicalPrinterId'],
      sequence: proofDecimal(b['sequence']),
      admissionSha256: b['admissionSha256'],
    );
  }
  void verify(ProofEffect effect) {
    proofRequire(
      effect.kind == ProofEffectKind.print &&
          effect.id == effectId &&
          sha256.convert(effect.payload).toString() == admissionSha256,
      'receipt frozen PRINT digest',
    );
    final body = jsonDecode(utf8.decode(effect.payload));
    proofRequire(
      body is Map &&
          body['version'] == 1 &&
          body['jobId'] == jobId &&
          body['effectId'] == effectId &&
          body['physicalPrinterId'] == physicalPrinterId,
      'receipt frozen job identity',
    );
  }
}

class ProofEvent {
  ProofEvent({
    required this.binding,
    required this.sequence,
    required this.requestId,
    required this.terminalId,
    required List<ProofEntity> entities,
    List<ProofEffect> effects = const [],
    this.printAdmission = '',
    this.originInstallationId = '',
    List<ProofPrintReceipt> printReceipts = const [],
  }) : entities = List.unmodifiable(entities),
       effects = List.unmodifiable(effects),
       printReceipts = List.unmodifiable(printReceipts) {
    proofPrintAdmission(printAdmission);
    proofInteger(sequence, positive: true);
    proofRequire(
      proofUuid(requestId) &&
          proofUuid(terminalId) &&
          this.entities.isNotEmpty &&
          this.entities.length <= ProofBounds.writes &&
          this.effects.length <= ProofBounds.requestEffects,
      'event shape/counts',
    );
    proofUnique(this.entities, (v) => v.key.value);
    proofUnique(this.effects, (v) => v.id);
    proofRequire(
      printAdmission.isEmpty
          ? originInstallationId.isEmpty && this.printReceipts.isEmpty
          : proofUuid(originInstallationId),
      'event admission origin',
    );
    proofUnique(this.printReceipts, (v) => v.effectId);
    proofUnique(this.printReceipts, (v) => v.jobId);
    if (printAdmission.isNotEmpty) {
      final prints = this.effects
          .where((e) => e.kind == ProofEffectKind.print)
          .toList();
      proofRequire(
        prints.length == this.printReceipts.length,
        'complete queue receipts',
      );
      for (final effect in prints) {
        final matches = this.printReceipts
            .where((r) => r.effectId == effect.id)
            .toList();
        proofRequire(matches.length == 1, 'PRINT receipt linkage');
        matches.single.verify(effect);
        final body = jsonDecode(utf8.decode(effect.payload)) as Map;
        proofRequire(
          body['requestId'] == requestId &&
              body['terminalId'] == terminalId &&
              body['venueId'] == binding.venueId &&
              body['installationId'] == binding.installationId &&
              body['authorityEpoch'] == binding.epoch &&
              body['originInstallationId'] == originInstallationId,
          'frozen print producer scope',
        );
      }
    }
    proofRequire(
      this.entities.every((v) => v.revision > 0),
      'committed revision zero',
    );
    proofRequire(
      utf8.encode(jsonEncode(toFrame())).length <= ProofBounds.eventBytes,
      'encoded event bound',
    );
  }
  final ProofBinding binding;
  final int sequence;
  final String requestId, terminalId;
  final List<ProofEntity> entities;
  final List<ProofEffect> effects;
  final String printAdmission;
  final String originInstallationId;
  final List<ProofPrintReceipt> printReceipts;
  String get fingerprint => proofFingerprint(toFrame());
  Map<String, dynamic> toFrame() => {
    'binding': binding.toFrame(),
    'sequence': '$sequence',
    'requestId': requestId,
    'terminalId': terminalId,
    'entities': entities.map((v) => v.toFrame()).toList(),
    'effects': effects.map((v) => v.toFrame()).toList(),
    if (printAdmission.isNotEmpty) 'printAdmission': printAdmission,
    if (originInstallationId.isNotEmpty)
      'originInstallationId': originInstallationId,
    if (printReceipts.isNotEmpty)
      'printReceipts': printReceipts.map((r) => r.toFrame()).toList(),
  };
  factory ProofEvent.fromFrame(dynamic raw) {
    final b = proofAdmissionMap(
      raw,
      {'binding', 'sequence', 'requestId', 'terminalId', 'entities', 'effects'},
      producer: true,
      receipts: true,
    );
    return ProofEvent(
      binding: ProofBinding.fromFrame(b['binding']),
      sequence: proofDecimal(b['sequence']),
      requestId: b['requestId'],
      terminalId: b['terminalId'],
      entities: proofList(b['entities'], ProofEntity.fromFrame),
      effects: proofList(b['effects'], ProofEffect.fromFrame),
      printAdmission: b['printAdmission'] ?? '',
      originInstallationId: b['originInstallationId'] ?? '',
      printReceipts: b['printReceipts'] == null
          ? const []
          : proofList(b['printReceipts'], ProofPrintReceipt.fromFrame),
    );
  }
}

class ProofResult {
  ProofResult({
    required this.binding,
    required this.requestId,
    required this.terminalId,
    required this.outcome,
    required this.headSequence,
    this.event,
    List<ProofEntity> current = const [],
    List<int> applicationData = const [],
    this.printAdmission = '',
    this.originInstallationId = '',
  }) : current = List.unmodifiable(current),
       applicationData = proofBytes(
         applicationData,
         ProofBounds.applicationBytes,
       ) {
    proofPrintAdmission(printAdmission);
    proofRequire(
      printAdmission.isEmpty
          ? originInstallationId.isEmpty
          : proofUuid(originInstallationId),
      'result admission origin',
    );
    proofInteger(headSequence);
    proofRequire(
      proofUuid(requestId) && proofUuid(terminalId),
      'result identity',
    );
    proofUnique(this.current, (v) => v.key.value);
    proofRequire(
      outcome == ProofOutcome.committed
          ? event != null &&
                current.isEmpty &&
                headSequence == event!.sequence &&
                printAdmission == event!.printAdmission &&
                originInstallationId == event!.originInstallationId
          : event == null &&
                current.isNotEmpty &&
                current.length <= ProofBounds.reads + ProofBounds.writes &&
                this.applicationData.isEmpty,
      'canonical result shape',
    );
    proofRequire(
      utf8.encode(jsonEncode(toFrame())).length <= ProofBounds.resultBytes,
      'encoded result bound',
    );
  }
  final ProofBinding binding;
  final String requestId, terminalId;
  final ProofOutcome outcome;
  final int headSequence;
  final ProofEvent? event;
  final List<ProofEntity> current;
  final List<int> applicationData;
  final String printAdmission;
  final String originInstallationId;
  String get fingerprint => proofFingerprint(toFrame());
  Map<String, dynamic> toFrame() => {
    'binding': binding.toFrame(),
    'requestId': requestId,
    'terminalId': terminalId,
    'outcome': outcome.name,
    'headSequence': '$headSequence',
    'event': event?.toFrame(),
    'current': current.map((v) => v.toFrame()).toList(),
    'applicationData': base64Encode(applicationData),
    if (printAdmission.isNotEmpty) 'printAdmission': printAdmission,
    if (originInstallationId.isNotEmpty)
      'originInstallationId': originInstallationId,
  };
  factory ProofResult.fromFrame(dynamic raw) {
    final b = proofAdmissionMap(raw, {
      'binding',
      'requestId',
      'terminalId',
      'outcome',
      'headSequence',
      'event',
      'current',
      'applicationData',
    }, producer: true);
    return ProofResult(
      binding: ProofBinding.fromFrame(b['binding']),
      requestId: b['requestId'],
      terminalId: b['terminalId'],
      outcome: ProofOutcome.values.byName(b['outcome']),
      headSequence: proofDecimal(b['headSequence']),
      event: b['event'] == null ? null : ProofEvent.fromFrame(b['event']),
      current: proofList(b['current'], ProofEntity.fromFrame),
      applicationData: proofDecodeBytes(b['applicationData']),
      printAdmission: b['printAdmission'] ?? '',
      originInstallationId: b['originInstallationId'] ?? '',
    );
  }
}

class ProofReplayPage {
  ProofReplayPage({
    required this.binding,
    required this.after,
    required this.head,
    required this.next,
    required List<ProofEvent> events,
  }) : events = List.unmodifiable(events) {
    for (final v in [after, head, next]) {
      proofInteger(v);
    }
    proofRequire(
      this.events.length <= ProofBounds.replayEvents &&
          utf8.encode(jsonEncode(toFrame())).length <= ProofBounds.replayBytes,
      'replay page bound',
    );
  }
  final ProofBinding binding;
  final int after, head, next;
  final List<ProofEvent> events;
  Map<String, dynamic> toFrame() => {
    'binding': binding.toFrame(),
    'after': '$after',
    'head': '$head',
    'next': '$next',
    'events': events.map((v) => v.toFrame()).toList(),
  };
}

class ProofSnapshot {
  ProofSnapshot({
    required this.binding,
    required this.sequence,
    required List<ProofEntity> entities,
  }) : entities = List.unmodifiable(entities) {
    proofInteger(sequence);
    proofUnique(this.entities, (v) => v.key.value);
    proofRequire(
      this.entities.length <= ProofBounds.entities &&
          this.entities.every((v) => v.revision > 0) &&
          utf8.encode(jsonEncode(toFrame())).length <=
              ProofBounds.snapshotBytes,
      'snapshot bounds',
    );
  }
  final ProofBinding binding;
  final int sequence;
  final List<ProofEntity> entities;
  Map<String, dynamic> toFrame() => {
    'binding': binding.toFrame(),
    'sequence': '$sequence',
    'entities': entities.map((v) => v.toFrame()).toList(),
  };
}

class ProofStatus {
  ProofStatus({
    required this.binding,
    required this.head,
    required this.protocolMajor,
    required this.protocolMinor,
    required List<String> capabilities,
    required Map<String, int> limits,
  }) : capabilities = List.unmodifiable(capabilities),
       limits = Map.unmodifiable(limits) {
    proofInteger(head);
  }
  final ProofBinding binding;
  final int head, protocolMajor, protocolMinor;
  final List<String> capabilities;
  final Map<String, int> limits;
}

class ProofResultLookup {
  const ProofResultLookup.notFound() : result = null, found = false;
  const ProofResultLookup.found(ProofResult value)
    : result = value,
      found = true;
  final bool found;
  final ProofResult? result;
}

abstract interface class OperationalProofTransport {
  Future<ProofStatus> status();
  Future<ProofResult> commit(ProofIntent intent);
  Future<ProofResultLookup> getResult({
    required String requestId,
    required int epoch,
  });
  Future<ProofReplayPage> replay({
    required int epoch,
    required int after,
    required int limit,
  });
  Future<ProofSnapshot> snapshot({required int epoch});
}
