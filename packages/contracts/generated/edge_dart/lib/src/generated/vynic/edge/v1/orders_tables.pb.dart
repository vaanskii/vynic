// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/orders_tables.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'foundation.pb.dart' as $1;
import 'orders_tables.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'orders_tables.pbenum.dart';

class ProjectionEntity extends $pb.GeneratedMessage {
  factory ProjectionEntity({
    ProjectionEntity_Kind? kind,
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

  ProjectionEntity._();

  factory ProjectionEntity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProjectionEntity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProjectionEntity',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aE<ProjectionEntity_Kind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ProjectionEntity_Kind.values)
    ..aOS(2, _omitFieldNames ? '' : 'id')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'tombstone')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'document', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProjectionEntity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProjectionEntity copyWith(void Function(ProjectionEntity) updates) =>
      super.copyWith((message) => updates(message as ProjectionEntity))
          as ProjectionEntity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProjectionEntity create() => ProjectionEntity._();
  @$core.override
  ProjectionEntity createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProjectionEntity getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProjectionEntity>(create);
  static ProjectionEntity? _defaultInstance;

  @$pb.TagNumber(1)
  ProjectionEntity_Kind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ProjectionEntity_Kind value) => $_setField(1, value);
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

class EntityChange extends $pb.GeneratedMessage {
  factory EntityChange({
    ProjectionEntity? entity,
    $fixnum.Int64? expectedRevision,
  }) {
    final result = create();
    if (entity != null) result.entity = entity;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    return result;
  }

  EntityChange._();

  factory EntityChange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EntityChange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EntityChange',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<ProjectionEntity>(1, _omitFieldNames ? '' : 'entity',
        subBuilder: ProjectionEntity.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EntityChange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EntityChange copyWith(void Function(EntityChange) updates) =>
      super.copyWith((message) => updates(message as EntityChange))
          as EntityChange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EntityChange create() => EntityChange._();
  @$core.override
  EntityChange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EntityChange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EntityChange>(create);
  static EntityChange? _defaultInstance;

  @$pb.TagNumber(1)
  ProjectionEntity get entity => $_getN(0);
  @$pb.TagNumber(1)
  set entity(ProjectionEntity value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEntity() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntity() => $_clearField(1);
  @$pb.TagNumber(1)
  ProjectionEntity ensureEntity() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get expectedRevision => $_getI64(1);
  @$pb.TagNumber(2)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExpectedRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpectedRevision() => $_clearField(2);
}

class CommitIntent extends $pb.GeneratedMessage {
  factory CommitIntent({
    $1.AuthenticatedRequest? auth,
    $core.String? requestId,
    $fixnum.Int64? authorityEpoch,
    $core.Iterable<EntityChange>? changes,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (requestId != null) result.requestId = requestId;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (changes != null) result.changes.addAll(changes);
    return result;
  }

  CommitIntent._();

  factory CommitIntent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommitIntent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommitIntent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$1.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $1.AuthenticatedRequest.create)
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<EntityChange>(4, _omitFieldNames ? '' : 'changes',
        subBuilder: EntityChange.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitIntent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitIntent copyWith(void Function(CommitIntent) updates) =>
      super.copyWith((message) => updates(message as CommitIntent))
          as CommitIntent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommitIntent create() => CommitIntent._();
  @$core.override
  CommitIntent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommitIntent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommitIntent>(create);
  static CommitIntent? _defaultInstance;

  @$pb.TagNumber(1)
  $1.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($1.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.AuthenticatedRequest ensureAuth() => $_ensure(0);

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
  $pb.PbList<EntityChange> get changes => $_getList(3);
}

class CommittedEvent extends $pb.GeneratedMessage {
  factory CommittedEvent({
    $fixnum.Int64? sequence,
    $fixnum.Int64? authorityEpoch,
    $core.String? requestId,
    $core.String? terminalId,
    $core.Iterable<ProjectionEntity>? entities,
  }) {
    final result = create();
    if (sequence != null) result.sequence = sequence;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (requestId != null) result.requestId = requestId;
    if (terminalId != null) result.terminalId = terminalId;
    if (entities != null) result.entities.addAll(entities);
    return result;
  }

  CommittedEvent._();

  factory CommittedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommittedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommittedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aOS(4, _omitFieldNames ? '' : 'terminalId')
    ..pPM<ProjectionEntity>(5, _omitFieldNames ? '' : 'entities',
        subBuilder: ProjectionEntity.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommittedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommittedEvent copyWith(void Function(CommittedEvent) updates) =>
      super.copyWith((message) => updates(message as CommittedEvent))
          as CommittedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommittedEvent create() => CommittedEvent._();
  @$core.override
  CommittedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommittedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommittedEvent>(create);
  static CommittedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sequence => $_getI64(0);
  @$pb.TagNumber(1)
  set sequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequence() => $_clearField(1);

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

  @$pb.TagNumber(4)
  $core.String get terminalId => $_getSZ(3);
  @$pb.TagNumber(4)
  set terminalId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTerminalId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTerminalId() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<ProjectionEntity> get entities => $_getList(4);
}

class CommitResult extends $pb.GeneratedMessage {
  factory CommitResult({
    CommitResult_Outcome? outcome,
    CommittedEvent? event,
    $core.Iterable<ProjectionEntity>? current,
    $fixnum.Int64? authorityEpoch,
    $fixnum.Int64? headSequence,
  }) {
    final result = create();
    if (outcome != null) result.outcome = outcome;
    if (event != null) result.event = event;
    if (current != null) result.current.addAll(current);
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (headSequence != null) result.headSequence = headSequence;
    return result;
  }

  CommitResult._();

  factory CommitResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommitResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommitResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aE<CommitResult_Outcome>(1, _omitFieldNames ? '' : 'outcome',
        enumValues: CommitResult_Outcome.values)
    ..aOM<CommittedEvent>(2, _omitFieldNames ? '' : 'event',
        subBuilder: CommittedEvent.create)
    ..pPM<ProjectionEntity>(3, _omitFieldNames ? '' : 'current',
        subBuilder: ProjectionEntity.create)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'headSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitResult copyWith(void Function(CommitResult) updates) =>
      super.copyWith((message) => updates(message as CommitResult))
          as CommitResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommitResult create() => CommitResult._();
  @$core.override
  CommitResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommitResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommitResult>(create);
  static CommitResult? _defaultInstance;

  @$pb.TagNumber(1)
  CommitResult_Outcome get outcome => $_getN(0);
  @$pb.TagNumber(1)
  set outcome(CommitResult_Outcome value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOutcome() => $_has(0);
  @$pb.TagNumber(1)
  void clearOutcome() => $_clearField(1);

  @$pb.TagNumber(2)
  CommittedEvent get event => $_getN(1);
  @$pb.TagNumber(2)
  set event(CommittedEvent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEvent() => $_has(1);
  @$pb.TagNumber(2)
  void clearEvent() => $_clearField(2);
  @$pb.TagNumber(2)
  CommittedEvent ensureEvent() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<ProjectionEntity> get current => $_getList(2);

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
}

class ReplayRequest extends $pb.GeneratedMessage {
  factory ReplayRequest({
    $1.AuthenticatedRequest? auth,
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

  ReplayRequest._();

  factory ReplayRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReplayRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReplayRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$1.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $1.AuthenticatedRequest.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'afterSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(4, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplayRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplayRequest copyWith(void Function(ReplayRequest) updates) =>
      super.copyWith((message) => updates(message as ReplayRequest))
          as ReplayRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReplayRequest create() => ReplayRequest._();
  @$core.override
  ReplayRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReplayRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReplayRequest>(create);
  static ReplayRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $1.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($1.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.AuthenticatedRequest ensureAuth() => $_ensure(0);

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

class ReplayPage extends $pb.GeneratedMessage {
  factory ReplayPage({
    $core.Iterable<CommittedEvent>? events,
    $fixnum.Int64? headSequence,
    $fixnum.Int64? authorityEpoch,
  }) {
    final result = create();
    if (events != null) result.events.addAll(events);
    if (headSequence != null) result.headSequence = headSequence;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    return result;
  }

  ReplayPage._();

  factory ReplayPage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReplayPage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReplayPage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..pPM<CommittedEvent>(1, _omitFieldNames ? '' : 'events',
        subBuilder: CommittedEvent.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'headSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplayPage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplayPage copyWith(void Function(ReplayPage) updates) =>
      super.copyWith((message) => updates(message as ReplayPage)) as ReplayPage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReplayPage create() => ReplayPage._();
  @$core.override
  ReplayPage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReplayPage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReplayPage>(create);
  static ReplayPage? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<CommittedEvent> get events => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get headSequence => $_getI64(1);
  @$pb.TagNumber(2)
  set headSequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeadSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeadSequence() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get authorityEpoch => $_getI64(2);
  @$pb.TagNumber(3)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAuthorityEpoch() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthorityEpoch() => $_clearField(3);
}

class SnapshotRequest extends $pb.GeneratedMessage {
  factory SnapshotRequest({
    $1.AuthenticatedRequest? auth,
    $fixnum.Int64? authorityEpoch,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    return result;
  }

  SnapshotRequest._();

  factory SnapshotRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SnapshotRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SnapshotRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<$1.AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: $1.AuthenticatedRequest.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SnapshotRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SnapshotRequest copyWith(void Function(SnapshotRequest) updates) =>
      super.copyWith((message) => updates(message as SnapshotRequest))
          as SnapshotRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SnapshotRequest create() => SnapshotRequest._();
  @$core.override
  SnapshotRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SnapshotRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SnapshotRequest>(create);
  static SnapshotRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $1.AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth($1.AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.AuthenticatedRequest ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get authorityEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthorityEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorityEpoch() => $_clearField(2);
}

class ProjectionSnapshot extends $pb.GeneratedMessage {
  factory ProjectionSnapshot({
    $core.Iterable<ProjectionEntity>? entities,
    $fixnum.Int64? sequence,
    $fixnum.Int64? authorityEpoch,
    $core.String? mode,
  }) {
    final result = create();
    if (entities != null) result.entities.addAll(entities);
    if (sequence != null) result.sequence = sequence;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (mode != null) result.mode = mode;
    return result;
  }

  ProjectionSnapshot._();

  factory ProjectionSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProjectionSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProjectionSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..pPM<ProjectionEntity>(1, _omitFieldNames ? '' : 'entities',
        subBuilder: ProjectionEntity.create)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'mode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProjectionSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProjectionSnapshot copyWith(void Function(ProjectionSnapshot) updates) =>
      super.copyWith((message) => updates(message as ProjectionSnapshot))
          as ProjectionSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProjectionSnapshot create() => ProjectionSnapshot._();
  @$core.override
  ProjectionSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProjectionSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProjectionSnapshot>(create);
  static ProjectionSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ProjectionEntity> get entities => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get authorityEpoch => $_getI64(2);
  @$pb.TagNumber(3)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAuthorityEpoch() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthorityEpoch() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get mode => $_getSZ(3);
  @$pb.TagNumber(4)
  set mode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearMode() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
