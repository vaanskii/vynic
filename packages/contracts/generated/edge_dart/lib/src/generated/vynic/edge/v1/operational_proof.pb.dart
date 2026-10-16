// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/operational_proof.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'foundation.pb.dart' as $0;
import 'operational_proof.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'operational_proof.pbenum.dart';

class ProofLimits extends $pb.GeneratedMessage {
  factory ProofLimits({
    $core.int? maxRequestBytes,
    $core.int? maxDocumentBytes,
    $core.int? maxEffectBytes,
    $core.int? maxApplicationBytes,
    $core.int? maxResultBytes,
    $core.int? maxSnapshotBytes,
    $core.int? maxReplayBytes,
    $core.int? maxWrites,
    $core.int? maxReads,
    $core.int? maxRequestEffects,
    $core.int? maxReplayEvents,
    $core.int? maxEntities,
    $core.int? maxRetainedRequests,
    $core.int? maxRetainedEvents,
    $core.int? maxRetainedEffects,
    $core.int? maxEventBytes,
    $core.int? maxStateBytes,
    $core.int? maxJournalBytes,
  }) {
    final result = create();
    if (maxRequestBytes != null) result.maxRequestBytes = maxRequestBytes;
    if (maxDocumentBytes != null) result.maxDocumentBytes = maxDocumentBytes;
    if (maxEffectBytes != null) result.maxEffectBytes = maxEffectBytes;
    if (maxApplicationBytes != null)
      result.maxApplicationBytes = maxApplicationBytes;
    if (maxResultBytes != null) result.maxResultBytes = maxResultBytes;
    if (maxSnapshotBytes != null) result.maxSnapshotBytes = maxSnapshotBytes;
    if (maxReplayBytes != null) result.maxReplayBytes = maxReplayBytes;
    if (maxWrites != null) result.maxWrites = maxWrites;
    if (maxReads != null) result.maxReads = maxReads;
    if (maxRequestEffects != null) result.maxRequestEffects = maxRequestEffects;
    if (maxReplayEvents != null) result.maxReplayEvents = maxReplayEvents;
    if (maxEntities != null) result.maxEntities = maxEntities;
    if (maxRetainedRequests != null)
      result.maxRetainedRequests = maxRetainedRequests;
    if (maxRetainedEvents != null) result.maxRetainedEvents = maxRetainedEvents;
    if (maxRetainedEffects != null)
      result.maxRetainedEffects = maxRetainedEffects;
    if (maxEventBytes != null) result.maxEventBytes = maxEventBytes;
    if (maxStateBytes != null) result.maxStateBytes = maxStateBytes;
    if (maxJournalBytes != null) result.maxJournalBytes = maxJournalBytes;
    return result;
  }

  ProofLimits._();

  factory ProofLimits.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofLimits.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofLimits',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'maxRequestBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'maxDocumentBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'maxEffectBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'maxApplicationBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'maxResultBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'maxSnapshotBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'maxReplayBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'maxWrites', fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'maxReads', fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'maxRequestEffects',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(11, _omitFieldNames ? '' : 'maxReplayEvents',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(12, _omitFieldNames ? '' : 'maxEntities',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(13, _omitFieldNames ? '' : 'maxRetainedRequests',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(14, _omitFieldNames ? '' : 'maxRetainedEvents',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(15, _omitFieldNames ? '' : 'maxRetainedEffects',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(16, _omitFieldNames ? '' : 'maxEventBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(17, _omitFieldNames ? '' : 'maxStateBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(18, _omitFieldNames ? '' : 'maxJournalBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofLimits clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofLimits copyWith(void Function(ProofLimits) updates) =>
      super.copyWith((message) => updates(message as ProofLimits))
          as ProofLimits;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofLimits create() => ProofLimits._();
  @$core.override
  ProofLimits createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofLimits getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofLimits>(create);
  static ProofLimits? _defaultInstance;

  /// Byte bounds describe store-encoded JSON (including byte-field base64), not
  /// protobuf wire length. Server validation remains authoritative. Configure
  /// bounded gRPC request/result overhead separately in the isolated harness.
  @$pb.TagNumber(1)
  $core.int get maxRequestBytes => $_getIZ(0);
  @$pb.TagNumber(1)
  set maxRequestBytes($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMaxRequestBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxRequestBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxDocumentBytes => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxDocumentBytes($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaxDocumentBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxDocumentBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxEffectBytes => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxEffectBytes($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxEffectBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxEffectBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxApplicationBytes => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxApplicationBytes($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxApplicationBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxApplicationBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxResultBytes => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxResultBytes($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxResultBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxResultBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get maxSnapshotBytes => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxSnapshotBytes($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxSnapshotBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxSnapshotBytes() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get maxReplayBytes => $_getIZ(6);
  @$pb.TagNumber(7)
  set maxReplayBytes($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMaxReplayBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearMaxReplayBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get maxWrites => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxWrites($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxWrites() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxWrites() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get maxReads => $_getIZ(8);
  @$pb.TagNumber(9)
  set maxReads($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasMaxReads() => $_has(8);
  @$pb.TagNumber(9)
  void clearMaxReads() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get maxRequestEffects => $_getIZ(9);
  @$pb.TagNumber(10)
  set maxRequestEffects($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMaxRequestEffects() => $_has(9);
  @$pb.TagNumber(10)
  void clearMaxRequestEffects() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get maxReplayEvents => $_getIZ(10);
  @$pb.TagNumber(11)
  set maxReplayEvents($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasMaxReplayEvents() => $_has(10);
  @$pb.TagNumber(11)
  void clearMaxReplayEvents() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get maxEntities => $_getIZ(11);
  @$pb.TagNumber(12)
  set maxEntities($core.int value) => $_setUnsignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasMaxEntities() => $_has(11);
  @$pb.TagNumber(12)
  void clearMaxEntities() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get maxRetainedRequests => $_getIZ(12);
  @$pb.TagNumber(13)
  set maxRetainedRequests($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasMaxRetainedRequests() => $_has(12);
  @$pb.TagNumber(13)
  void clearMaxRetainedRequests() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get maxRetainedEvents => $_getIZ(13);
  @$pb.TagNumber(14)
  set maxRetainedEvents($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasMaxRetainedEvents() => $_has(13);
  @$pb.TagNumber(14)
  void clearMaxRetainedEvents() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get maxRetainedEffects => $_getIZ(14);
  @$pb.TagNumber(15)
  set maxRetainedEffects($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasMaxRetainedEffects() => $_has(14);
  @$pb.TagNumber(15)
  void clearMaxRetainedEffects() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get maxEventBytes => $_getIZ(15);
  @$pb.TagNumber(16)
  set maxEventBytes($core.int value) => $_setUnsignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasMaxEventBytes() => $_has(15);
  @$pb.TagNumber(16)
  void clearMaxEventBytes() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get maxStateBytes => $_getIZ(16);
  @$pb.TagNumber(17)
  set maxStateBytes($core.int value) => $_setUnsignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasMaxStateBytes() => $_has(16);
  @$pb.TagNumber(17)
  void clearMaxStateBytes() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.int get maxJournalBytes => $_getIZ(17);
  @$pb.TagNumber(18)
  set maxJournalBytes($core.int value) => $_setUnsignedInt32(17, value);
  @$pb.TagNumber(18)
  $core.bool hasMaxJournalBytes() => $_has(17);
  @$pb.TagNumber(18)
  void clearMaxJournalBytes() => $_clearField(18);
}

class ProofStatus extends $pb.GeneratedMessage {
  factory ProofStatus({
    $core.String? mode,
    $core.String? venueId,
    $core.String? installationId,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? headSequence,
    $core.List<$core.int>? grantSha256,
    $0.Protocol? protocol,
    $core.Iterable<$core.String>? capabilities,
    ProofLimits? limits,
    $core.String? originInstallationId,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (venueId != null) result.venueId = venueId;
    if (installationId != null) result.installationId = installationId;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (headSequence != null) result.headSequence = headSequence;
    if (grantSha256 != null) result.grantSha256 = grantSha256;
    if (protocol != null) result.protocol = protocol;
    if (capabilities != null) result.capabilities.addAll(capabilities);
    if (limits != null) result.limits = limits;
    if (originInstallationId != null)
      result.originInstallationId = originInstallationId;
    return result;
  }

  ProofStatus._();

  factory ProofStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mode')
    ..aOS(2, _omitFieldNames ? '' : 'venueId')
    ..aOS(3, _omitFieldNames ? '' : 'installationId')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'headSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'grantSha256', $pb.PbFieldType.OY)
    ..aOM<$0.Protocol>(7, _omitFieldNames ? '' : 'protocol',
        subBuilder: $0.Protocol.create)
    ..pPS(8, _omitFieldNames ? '' : 'capabilities')
    ..aOM<ProofLimits>(9, _omitFieldNames ? '' : 'limits',
        subBuilder: ProofLimits.create)
    ..aOS(10, _omitFieldNames ? '' : 'originInstallationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofStatus copyWith(void Function(ProofStatus) updates) =>
      super.copyWith((message) => updates(message as ProofStatus))
          as ProofStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofStatus create() => ProofStatus._();
  @$core.override
  ProofStatus createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofStatus>(create);
  static ProofStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mode => $_getSZ(0);
  @$pb.TagNumber(1)
  set mode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get venueId => $_getSZ(1);
  @$pb.TagNumber(2)
  set venueId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVenueId() => $_has(1);
  @$pb.TagNumber(2)
  void clearVenueId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get installationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set installationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInstallationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearInstallationId() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get authorityEpoch => $_getI64(3);
  @$pb.TagNumber(4)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAuthorityEpoch() => $_has(3);
  @$pb.TagNumber(4)
  void clearAuthorityEpoch() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get headSequence => $_getI64(4);
  @$pb.TagNumber(5)
  set headSequence($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeadSequence() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeadSequence() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get grantSha256 => $_getN(5);
  @$pb.TagNumber(6)
  set grantSha256($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGrantSha256() => $_has(5);
  @$pb.TagNumber(6)
  void clearGrantSha256() => $_clearField(6);

  @$pb.TagNumber(7)
  $0.Protocol get protocol => $_getN(6);
  @$pb.TagNumber(7)
  set protocol($0.Protocol value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasProtocol() => $_has(6);
  @$pb.TagNumber(7)
  void clearProtocol() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.Protocol ensureProtocol() => $_ensure(6);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get capabilities => $_getList(7);

  @$pb.TagNumber(9)
  ProofLimits get limits => $_getN(8);
  @$pb.TagNumber(9)
  set limits(ProofLimits value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasLimits() => $_has(8);
  @$pb.TagNumber(9)
  void clearLimits() => $_clearField(9);
  @$pb.TagNumber(9)
  ProofLimits ensureLimits() => $_ensure(8);

  /// Fresh certificate identity, checked against signed local registration.
  @$pb.TagNumber(10)
  $core.String get originInstallationId => $_getSZ(9);
  @$pb.TagNumber(10)
  set originInstallationId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasOriginInstallationId() => $_has(9);
  @$pb.TagNumber(10)
  void clearOriginInstallationId() => $_clearField(10);
}

class ProofEntity extends $pb.GeneratedMessage {
  factory ProofEntity({
    ProofEntity_Kind? kind,
    $core.String? id,
    $fixnum.Int64? revision,
    $core.bool? tombstone,
    $core.List<$core.int>? document,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (id != null) result.id = id;
    if (revision != null) result.revision = revision;
    if (tombstone != null) result.tombstone = tombstone;
    if (document != null) result.document = document;
    return result;
  }

  ProofEntity._();

  factory ProofEntity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofEntity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofEntity',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aE<ProofEntity_Kind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ProofEntity_Kind.values)
    ..aOS(2, _omitFieldNames ? '' : 'id')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'tombstone')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'document', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofEntity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofEntity copyWith(void Function(ProofEntity) updates) =>
      super.copyWith((message) => updates(message as ProofEntity))
          as ProofEntity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofEntity create() => ProofEntity._();
  @$core.override
  ProofEntity createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofEntity getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofEntity>(create);
  static ProofEntity? _defaultInstance;

  @$pb.TagNumber(1)
  ProofEntity_Kind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ProofEntity_Kind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get id => $_getSZ(1);
  @$pb.TagNumber(2)
  set id($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasId() => $_has(1);
  @$pb.TagNumber(2)
  void clearId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get revision => $_getI64(2);
  @$pb.TagNumber(3)
  set revision($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get tombstone => $_getBF(3);
  @$pb.TagNumber(4)
  set tombstone($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTombstone() => $_has(3);
  @$pb.TagNumber(4)
  void clearTombstone() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get document => $_getN(4);
  @$pb.TagNumber(5)
  set document($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDocument() => $_has(4);
  @$pb.TagNumber(5)
  void clearDocument() => $_clearField(5);
}

class ProofRead extends $pb.GeneratedMessage {
  factory ProofRead({
    ProofEntity_Kind? kind,
    $core.String? id,
    $fixnum.Int64? expectedRevision,
    $core.bool? expectedTombstone,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (id != null) result.id = id;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (expectedTombstone != null) result.expectedTombstone = expectedTombstone;
    return result;
  }

  ProofRead._();

  factory ProofRead.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofRead.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofRead',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aE<ProofEntity_Kind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ProofEntity_Kind.values)
    ..aOS(2, _omitFieldNames ? '' : 'id')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'expectedTombstone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofRead clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofRead copyWith(void Function(ProofRead) updates) =>
      super.copyWith((message) => updates(message as ProofRead)) as ProofRead;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofRead create() => ProofRead._();
  @$core.override
  ProofRead createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofRead getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProofRead>(create);
  static ProofRead? _defaultInstance;

  @$pb.TagNumber(1)
  ProofEntity_Kind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ProofEntity_Kind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get id => $_getSZ(1);
  @$pb.TagNumber(2)
  set id($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasId() => $_has(1);
  @$pb.TagNumber(2)
  void clearId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expectedRevision => $_getI64(2);
  @$pb.TagNumber(3)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get expectedTombstone => $_getBF(3);
  @$pb.TagNumber(4)
  set expectedTombstone($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpectedTombstone() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedTombstone() => $_clearField(4);
}

class ProofWrite extends $pb.GeneratedMessage {
  factory ProofWrite({
    ProofEntity_Kind? kind,
    $core.String? id,
    $fixnum.Int64? expectedRevision,
    $core.bool? tombstone,
    $core.List<$core.int>? document,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (id != null) result.id = id;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (tombstone != null) result.tombstone = tombstone;
    if (document != null) result.document = document;
    return result;
  }

  ProofWrite._();

  factory ProofWrite.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofWrite.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofWrite',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aE<ProofEntity_Kind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ProofEntity_Kind.values)
    ..aOS(2, _omitFieldNames ? '' : 'id')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'tombstone')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'document', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofWrite clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofWrite copyWith(void Function(ProofWrite) updates) =>
      super.copyWith((message) => updates(message as ProofWrite)) as ProofWrite;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofWrite create() => ProofWrite._();
  @$core.override
  ProofWrite createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofWrite getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofWrite>(create);
  static ProofWrite? _defaultInstance;

  @$pb.TagNumber(1)
  ProofEntity_Kind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ProofEntity_Kind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get id => $_getSZ(1);
  @$pb.TagNumber(2)
  set id($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasId() => $_has(1);
  @$pb.TagNumber(2)
  void clearId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expectedRevision => $_getI64(2);
  @$pb.TagNumber(3)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get tombstone => $_getBF(3);
  @$pb.TagNumber(4)
  set tombstone($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTombstone() => $_has(3);
  @$pb.TagNumber(4)
  void clearTombstone() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get document => $_getN(4);
  @$pb.TagNumber(5)
  set document($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDocument() => $_has(4);
  @$pb.TagNumber(5)
  void clearDocument() => $_clearField(5);
}

class ProofEffect extends $pb.GeneratedMessage {
  factory ProofEffect({
    $core.String? id,
    ProofEffect_Kind? kind,
    $core.List<$core.int>? payload,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (kind != null) result.kind = kind;
    if (payload != null) result.payload = payload;
    return result;
  }

  ProofEffect._();

  factory ProofEffect.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofEffect.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofEffect',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<ProofEffect_Kind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: ProofEffect_Kind.values)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofEffect clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofEffect copyWith(void Function(ProofEffect) updates) =>
      super.copyWith((message) => updates(message as ProofEffect))
          as ProofEffect;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofEffect create() => ProofEffect._();
  @$core.override
  ProofEffect createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofEffect getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofEffect>(create);
  static ProofEffect? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  ProofEffect_Kind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(ProofEffect_Kind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get payload => $_getN(2);
  @$pb.TagNumber(3)
  set payload($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPayload() => $_has(2);
  @$pb.TagNumber(3)
  void clearPayload() => $_clearField(3);
}

class ProofCommitRequest extends $pb.GeneratedMessage {
  factory ProofCommitRequest({
    $0.AuthenticatedRequest? auth,
    $core.String? requestId,
    $fixnum.Int64? authorityEpoch,
    $core.Iterable<ProofRead>? reads,
    $core.Iterable<ProofWrite>? writes,
    $core.Iterable<ProofEffect>? effects,
    $core.List<$core.int>? applicationData,
    $core.String? printAdmission,
    $core.String? originInstallationId,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (requestId != null) result.requestId = requestId;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (reads != null) result.reads.addAll(reads);
    if (writes != null) result.writes.addAll(writes);
    if (effects != null) result.effects.addAll(effects);
    if (applicationData != null) result.applicationData = applicationData;
    if (printAdmission != null) result.printAdmission = printAdmission;
    if (originInstallationId != null)
      result.originInstallationId = originInstallationId;
    return result;
  }

  ProofCommitRequest._();

  factory ProofCommitRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofCommitRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofCommitRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$0.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $0.AuthenticatedRequest.create)
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<ProofRead>(4, _omitFieldNames ? '' : 'reads',
        subBuilder: ProofRead.create)
    ..pPM<ProofWrite>(5, _omitFieldNames ? '' : 'writes',
        subBuilder: ProofWrite.create)
    ..pPM<ProofEffect>(6, _omitFieldNames ? '' : 'effects',
        subBuilder: ProofEffect.create)
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'applicationData', $pb.PbFieldType.OY)
    ..aOS(8, _omitFieldNames ? '' : 'printAdmission')
    ..aOS(9, _omitFieldNames ? '' : 'originInstallationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofCommitRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofCommitRequest copyWith(void Function(ProofCommitRequest) updates) =>
      super.copyWith((message) => updates(message as ProofCommitRequest))
          as ProofCommitRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofCommitRequest create() => ProofCommitRequest._();
  @$core.override
  ProofCommitRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofCommitRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofCommitRequest>(create);
  static ProofCommitRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($0.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.AuthenticatedRequest ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get authorityEpoch => $_getI64(2);
  @$pb.TagNumber(3)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAuthorityEpoch() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthorityEpoch() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<ProofRead> get reads => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<ProofWrite> get writes => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<ProofEffect> get effects => $_getList(5);

  @$pb.TagNumber(7)
  $core.List<$core.int> get applicationData => $_getN(6);
  @$pb.TagNumber(7)
  set applicationData($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasApplicationData() => $_has(6);
  @$pb.TagNumber(7)
  void clearApplicationData() => $_clearField(7);

  /// Empty retains inert opaque proof receipts. Exact vynic-print-queue.v1
  /// requires operational.print.queue.proof.v1 and strict versioned admission
  /// of every PRINT in the same durable commit. This is immutable request data,
  /// not a production or physical-dispatch grant.
  @$pb.TagNumber(8)
  $core.String get printAdmission => $_getSZ(7);
  @$pb.TagNumber(8)
  set printAdmission($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPrintAdmission() => $_has(7);
  @$pb.TagNumber(8)
  void clearPrintAdmission() => $_clearField(8);

  /// Queued origin must match the verified four-UUID proof certificate and its
  /// local immutable signed registration. Empty for old inert proof requests.
  @$pb.TagNumber(9)
  $core.String get originInstallationId => $_getSZ(8);
  @$pb.TagNumber(9)
  set originInstallationId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOriginInstallationId() => $_has(8);
  @$pb.TagNumber(9)
  void clearOriginInstallationId() => $_clearField(9);
}

class ProofPrintReceipt extends $pb.GeneratedMessage {
  factory ProofPrintReceipt({
    $core.int? version,
    $core.String? jobId,
    $core.String? effectId,
    $core.String? physicalPrinterId,
    $fixnum.Int64? sequence,
    $core.String? admissionSha256,
  }) {
    final result = create();
    if (version != null) result.version = version;
    if (jobId != null) result.jobId = jobId;
    if (effectId != null) result.effectId = effectId;
    if (physicalPrinterId != null) result.physicalPrinterId = physicalPrinterId;
    if (sequence != null) result.sequence = sequence;
    if (admissionSha256 != null) result.admissionSha256 = admissionSha256;
    return result;
  }

  ProofPrintReceipt._();

  factory ProofPrintReceipt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofPrintReceipt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofPrintReceipt',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'jobId')
    ..aOS(3, _omitFieldNames ? '' : 'effectId')
    ..aOS(4, _omitFieldNames ? '' : 'physicalPrinterId')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(6, _omitFieldNames ? '' : 'admissionSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofPrintReceipt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofPrintReceipt copyWith(void Function(ProofPrintReceipt) updates) =>
      super.copyWith((message) => updates(message as ProofPrintReceipt))
          as ProofPrintReceipt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofPrintReceipt create() => ProofPrintReceipt._();
  @$core.override
  ProofPrintReceipt createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofPrintReceipt getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofPrintReceipt>(create);
  static ProofPrintReceipt? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get jobId => $_getSZ(1);
  @$pb.TagNumber(2)
  set jobId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasJobId() => $_has(1);
  @$pb.TagNumber(2)
  void clearJobId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get effectId => $_getSZ(2);
  @$pb.TagNumber(3)
  set effectId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEffectId() => $_has(2);
  @$pb.TagNumber(3)
  void clearEffectId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get physicalPrinterId => $_getSZ(3);
  @$pb.TagNumber(4)
  set physicalPrinterId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPhysicalPrinterId() => $_has(3);
  @$pb.TagNumber(4)
  void clearPhysicalPrinterId() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sequence => $_getI64(4);
  @$pb.TagNumber(5)
  set sequence($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSequence() => $_has(4);
  @$pb.TagNumber(5)
  void clearSequence() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get admissionSha256 => $_getSZ(5);
  @$pb.TagNumber(6)
  set admissionSha256($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAdmissionSha256() => $_has(5);
  @$pb.TagNumber(6)
  void clearAdmissionSha256() => $_clearField(6);
}

class ProofEvent extends $pb.GeneratedMessage {
  factory ProofEvent({
    $core.String? mode,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? sequence,
    $core.String? requestId,
    $core.String? terminalId,
    $core.Iterable<ProofEntity>? entities,
    $core.Iterable<ProofEffect>? effects,
    $core.String? printAdmission,
    $core.String? originInstallationId,
    $core.Iterable<ProofPrintReceipt>? printReceipts,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (sequence != null) result.sequence = sequence;
    if (requestId != null) result.requestId = requestId;
    if (terminalId != null) result.terminalId = terminalId;
    if (entities != null) result.entities.addAll(entities);
    if (effects != null) result.effects.addAll(effects);
    if (printAdmission != null) result.printAdmission = printAdmission;
    if (originInstallationId != null)
      result.originInstallationId = originInstallationId;
    if (printReceipts != null) result.printReceipts.addAll(printReceipts);
    return result;
  }

  ProofEvent._();

  factory ProofEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mode')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'requestId')
    ..aOS(5, _omitFieldNames ? '' : 'terminalId')
    ..pPM<ProofEntity>(6, _omitFieldNames ? '' : 'entities',
        subBuilder: ProofEntity.create)
    ..pPM<ProofEffect>(7, _omitFieldNames ? '' : 'effects',
        subBuilder: ProofEffect.create)
    ..aOS(8, _omitFieldNames ? '' : 'printAdmission')
    ..aOS(9, _omitFieldNames ? '' : 'originInstallationId')
    ..pPM<ProofPrintReceipt>(10, _omitFieldNames ? '' : 'printReceipts',
        subBuilder: ProofPrintReceipt.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofEvent copyWith(void Function(ProofEvent) updates) =>
      super.copyWith((message) => updates(message as ProofEvent)) as ProofEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofEvent create() => ProofEvent._();
  @$core.override
  ProofEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofEvent>(create);
  static ProofEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mode => $_getSZ(0);
  @$pb.TagNumber(1)
  set mode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get authorityEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthorityEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorityEpoch() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sequence => $_getI64(2);
  @$pb.TagNumber(3)
  set sequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get requestId => $_getSZ(3);
  @$pb.TagNumber(4)
  set requestId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRequestId() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequestId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get terminalId => $_getSZ(4);
  @$pb.TagNumber(5)
  set terminalId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTerminalId() => $_has(4);
  @$pb.TagNumber(5)
  void clearTerminalId() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<ProofEntity> get entities => $_getList(5);

  @$pb.TagNumber(7)
  $pb.PbList<ProofEffect> get effects => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get printAdmission => $_getSZ(7);
  @$pb.TagNumber(8)
  set printAdmission($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPrintAdmission() => $_has(7);
  @$pb.TagNumber(8)
  void clearPrintAdmission() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get originInstallationId => $_getSZ(8);
  @$pb.TagNumber(9)
  set originInstallationId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOriginInstallationId() => $_has(8);
  @$pb.TagNumber(9)
  void clearOriginInstallationId() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<ProofPrintReceipt> get printReceipts => $_getList(9);
}

class ProofCommitResult extends $pb.GeneratedMessage {
  factory ProofCommitResult({
    $core.String? mode,
    $core.String? requestId,
    $core.String? terminalId,
    ProofCommitResult_Outcome? outcome,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? headSequence,
    ProofEvent? event,
    $core.Iterable<ProofEntity>? current,
    $core.List<$core.int>? applicationData,
    $core.String? printAdmission,
    $core.String? originInstallationId,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (requestId != null) result.requestId = requestId;
    if (terminalId != null) result.terminalId = terminalId;
    if (outcome != null) result.outcome = outcome;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (headSequence != null) result.headSequence = headSequence;
    if (event != null) result.event = event;
    if (current != null) result.current.addAll(current);
    if (applicationData != null) result.applicationData = applicationData;
    if (printAdmission != null) result.printAdmission = printAdmission;
    if (originInstallationId != null)
      result.originInstallationId = originInstallationId;
    return result;
  }

  ProofCommitResult._();

  factory ProofCommitResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofCommitResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofCommitResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mode')
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aOS(3, _omitFieldNames ? '' : 'terminalId')
    ..aE<ProofCommitResult_Outcome>(4, _omitFieldNames ? '' : 'outcome',
        enumValues: ProofCommitResult_Outcome.values)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'headSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<ProofEvent>(7, _omitFieldNames ? '' : 'event',
        subBuilder: ProofEvent.create)
    ..pPM<ProofEntity>(8, _omitFieldNames ? '' : 'current',
        subBuilder: ProofEntity.create)
    ..a<$core.List<$core.int>>(
        9, _omitFieldNames ? '' : 'applicationData', $pb.PbFieldType.OY)
    ..aOS(10, _omitFieldNames ? '' : 'printAdmission')
    ..aOS(11, _omitFieldNames ? '' : 'originInstallationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofCommitResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofCommitResult copyWith(void Function(ProofCommitResult) updates) =>
      super.copyWith((message) => updates(message as ProofCommitResult))
          as ProofCommitResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofCommitResult create() => ProofCommitResult._();
  @$core.override
  ProofCommitResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofCommitResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofCommitResult>(create);
  static ProofCommitResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mode => $_getSZ(0);
  @$pb.TagNumber(1)
  set mode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get terminalId => $_getSZ(2);
  @$pb.TagNumber(3)
  set terminalId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTerminalId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTerminalId() => $_clearField(3);

  @$pb.TagNumber(4)
  ProofCommitResult_Outcome get outcome => $_getN(3);
  @$pb.TagNumber(4)
  set outcome(ProofCommitResult_Outcome value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOutcome() => $_has(3);
  @$pb.TagNumber(4)
  void clearOutcome() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get authorityEpoch => $_getI64(4);
  @$pb.TagNumber(5)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAuthorityEpoch() => $_has(4);
  @$pb.TagNumber(5)
  void clearAuthorityEpoch() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get headSequence => $_getI64(5);
  @$pb.TagNumber(6)
  set headSequence($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeadSequence() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeadSequence() => $_clearField(6);

  @$pb.TagNumber(7)
  ProofEvent get event => $_getN(6);
  @$pb.TagNumber(7)
  set event(ProofEvent value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasEvent() => $_has(6);
  @$pb.TagNumber(7)
  void clearEvent() => $_clearField(7);
  @$pb.TagNumber(7)
  ProofEvent ensureEvent() => $_ensure(6);

  @$pb.TagNumber(8)
  $pb.PbList<ProofEntity> get current => $_getList(7);

  @$pb.TagNumber(9)
  $core.List<$core.int> get applicationData => $_getN(8);
  @$pb.TagNumber(9)
  set applicationData($core.List<$core.int> value) => $_setBytes(8, value);
  @$pb.TagNumber(9)
  $core.bool hasApplicationData() => $_has(8);
  @$pb.TagNumber(9)
  void clearApplicationData() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get printAdmission => $_getSZ(9);
  @$pb.TagNumber(10)
  set printAdmission($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasPrintAdmission() => $_has(9);
  @$pb.TagNumber(10)
  void clearPrintAdmission() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get originInstallationId => $_getSZ(10);
  @$pb.TagNumber(11)
  set originInstallationId($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasOriginInstallationId() => $_has(10);
  @$pb.TagNumber(11)
  void clearOriginInstallationId() => $_clearField(11);
}

class ProofResultRequest extends $pb.GeneratedMessage {
  factory ProofResultRequest({
    $0.AuthenticatedRequest? auth,
    $fixnum.Int64? authorityEpoch,
    $core.String? requestId,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (requestId != null) result.requestId = requestId;
    return result;
  }

  ProofResultRequest._();

  factory ProofResultRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofResultRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofResultRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$0.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $0.AuthenticatedRequest.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofResultRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofResultRequest copyWith(void Function(ProofResultRequest) updates) =>
      super.copyWith((message) => updates(message as ProofResultRequest))
          as ProofResultRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofResultRequest create() => ProofResultRequest._();
  @$core.override
  ProofResultRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofResultRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofResultRequest>(create);
  static ProofResultRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($0.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.AuthenticatedRequest ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get authorityEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthorityEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorityEpoch() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);
}

class ProofReplayRequest extends $pb.GeneratedMessage {
  factory ProofReplayRequest({
    $0.AuthenticatedRequest? auth,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? afterSequence,
    $core.int? limit,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (afterSequence != null) result.afterSequence = afterSequence;
    if (limit != null) result.limit = limit;
    return result;
  }

  ProofReplayRequest._();

  factory ProofReplayRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofReplayRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofReplayRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$0.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $0.AuthenticatedRequest.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'afterSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(4, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofReplayRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofReplayRequest copyWith(void Function(ProofReplayRequest) updates) =>
      super.copyWith((message) => updates(message as ProofReplayRequest))
          as ProofReplayRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofReplayRequest create() => ProofReplayRequest._();
  @$core.override
  ProofReplayRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofReplayRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofReplayRequest>(create);
  static ProofReplayRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($0.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.AuthenticatedRequest ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get authorityEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthorityEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorityEpoch() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get afterSequence => $_getI64(2);
  @$pb.TagNumber(3)
  set afterSequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAfterSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearAfterSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get limit => $_getIZ(3);
  @$pb.TagNumber(4)
  set limit($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLimit() => $_has(3);
  @$pb.TagNumber(4)
  void clearLimit() => $_clearField(4);
}

class ProofReplayPage extends $pb.GeneratedMessage {
  factory ProofReplayPage({
    $core.String? mode,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? afterSequence,
    $fixnum.Int64? headSequence,
    $fixnum.Int64? nextSequence,
    $core.Iterable<ProofEvent>? events,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (afterSequence != null) result.afterSequence = afterSequence;
    if (headSequence != null) result.headSequence = headSequence;
    if (nextSequence != null) result.nextSequence = nextSequence;
    if (events != null) result.events.addAll(events);
    return result;
  }

  ProofReplayPage._();

  factory ProofReplayPage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofReplayPage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofReplayPage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mode')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'afterSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'headSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'nextSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<ProofEvent>(6, _omitFieldNames ? '' : 'events',
        subBuilder: ProofEvent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofReplayPage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofReplayPage copyWith(void Function(ProofReplayPage) updates) =>
      super.copyWith((message) => updates(message as ProofReplayPage))
          as ProofReplayPage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofReplayPage create() => ProofReplayPage._();
  @$core.override
  ProofReplayPage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofReplayPage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofReplayPage>(create);
  static ProofReplayPage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mode => $_getSZ(0);
  @$pb.TagNumber(1)
  set mode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get authorityEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthorityEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorityEpoch() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get afterSequence => $_getI64(2);
  @$pb.TagNumber(3)
  set afterSequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAfterSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearAfterSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get headSequence => $_getI64(3);
  @$pb.TagNumber(4)
  set headSequence($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeadSequence() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeadSequence() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get nextSequence => $_getI64(4);
  @$pb.TagNumber(5)
  set nextSequence($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNextSequence() => $_has(4);
  @$pb.TagNumber(5)
  void clearNextSequence() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<ProofEvent> get events => $_getList(5);
}

class ProofSnapshotRequest extends $pb.GeneratedMessage {
  factory ProofSnapshotRequest({
    $0.AuthenticatedRequest? auth,
    $fixnum.Int64? authorityEpoch,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    return result;
  }

  ProofSnapshotRequest._();

  factory ProofSnapshotRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofSnapshotRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofSnapshotRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$0.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $0.AuthenticatedRequest.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofSnapshotRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofSnapshotRequest copyWith(void Function(ProofSnapshotRequest) updates) =>
      super.copyWith((message) => updates(message as ProofSnapshotRequest))
          as ProofSnapshotRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofSnapshotRequest create() => ProofSnapshotRequest._();
  @$core.override
  ProofSnapshotRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofSnapshotRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofSnapshotRequest>(create);
  static ProofSnapshotRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($0.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.AuthenticatedRequest ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get authorityEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthorityEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorityEpoch() => $_clearField(2);
}

class ProofSnapshot extends $pb.GeneratedMessage {
  factory ProofSnapshot({
    $core.String? mode,
    $core.String? venueId,
    $core.String? installationId,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? sequence,
    $core.Iterable<ProofEntity>? entities,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (venueId != null) result.venueId = venueId;
    if (installationId != null) result.installationId = installationId;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (sequence != null) result.sequence = sequence;
    if (entities != null) result.entities.addAll(entities);
    return result;
  }

  ProofSnapshot._();

  factory ProofSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProofSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProofSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mode')
    ..aOS(2, _omitFieldNames ? '' : 'venueId')
    ..aOS(3, _omitFieldNames ? '' : 'installationId')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<ProofEntity>(6, _omitFieldNames ? '' : 'entities',
        subBuilder: ProofEntity.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProofSnapshot copyWith(void Function(ProofSnapshot) updates) =>
      super.copyWith((message) => updates(message as ProofSnapshot))
          as ProofSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofSnapshot create() => ProofSnapshot._();
  @$core.override
  ProofSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProofSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProofSnapshot>(create);
  static ProofSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mode => $_getSZ(0);
  @$pb.TagNumber(1)
  set mode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get venueId => $_getSZ(1);
  @$pb.TagNumber(2)
  set venueId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVenueId() => $_has(1);
  @$pb.TagNumber(2)
  void clearVenueId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get installationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set installationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInstallationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearInstallationId() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get authorityEpoch => $_getI64(3);
  @$pb.TagNumber(4)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAuthorityEpoch() => $_has(3);
  @$pb.TagNumber(4)
  void clearAuthorityEpoch() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sequence => $_getI64(4);
  @$pb.TagNumber(5)
  set sequence($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSequence() => $_has(4);
  @$pb.TagNumber(5)
  void clearSequence() => $_clearField(5);

  /// This checkpoint has entities only, no effects. A client retaining effect
  /// receipts bootstraps through replay from zero and verifies this snapshot;
  /// it must not jump its replay cursor here and silently skip frozen effects.
  @$pb.TagNumber(6)
  $pb.PbList<ProofEntity> get entities => $_getList(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
