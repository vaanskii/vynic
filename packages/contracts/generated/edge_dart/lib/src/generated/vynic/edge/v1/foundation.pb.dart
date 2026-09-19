// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/foundation.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Protocol extends $pb.GeneratedMessage {
  factory Protocol({
    $core.int? major,
    $core.int? minor,
    $core.Iterable<$core.String>? requiredCapabilities,
  }) {
    final result = create();
    if (major != null) result.major = major;
    if (minor != null) result.minor = minor;
    if (requiredCapabilities != null)
      result.requiredCapabilities.addAll(requiredCapabilities);
    return result;
  }

  Protocol._();

  factory Protocol.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Protocol.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Protocol',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'major', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'minor', fieldType: $pb.PbFieldType.OU3)
    ..pPS(3, _omitFieldNames ? '' : 'requiredCapabilities')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Protocol clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Protocol copyWith(void Function(Protocol) updates) =>
      super.copyWith((message) => updates(message as Protocol)) as Protocol;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Protocol create() => Protocol._();
  @$core.override
  Protocol createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Protocol getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Protocol>(create);
  static Protocol? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get major => $_getIZ(0);
  @$pb.TagNumber(1)
  set major($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMajor() => $_has(0);
  @$pb.TagNumber(1)
  void clearMajor() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get minor => $_getIZ(1);
  @$pb.TagNumber(2)
  set minor($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get requiredCapabilities => $_getList(2);
}

class Scope extends $pb.GeneratedMessage {
  factory Scope({
    $core.String? venueId,
    $core.String? installationId,
    Protocol? protocol,
  }) {
    final result = create();
    if (venueId != null) result.venueId = venueId;
    if (installationId != null) result.installationId = installationId;
    if (protocol != null) result.protocol = protocol;
    return result;
  }

  Scope._();

  factory Scope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Scope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Scope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'venueId')
    ..aOS(2, _omitFieldNames ? '' : 'installationId')
    ..aOM<Protocol>(3, _omitFieldNames ? '' : 'protocol',
        subBuilder: Protocol.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Scope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Scope copyWith(void Function(Scope) updates) =>
      super.copyWith((message) => updates(message as Scope)) as Scope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Scope create() => Scope._();
  @$core.override
  Scope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Scope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Scope>(create);
  static Scope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get venueId => $_getSZ(0);
  @$pb.TagNumber(1)
  set venueId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVenueId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVenueId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get installationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set installationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstallationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstallationId() => $_clearField(2);

  @$pb.TagNumber(3)
  Protocol get protocol => $_getN(2);
  @$pb.TagNumber(3)
  set protocol(Protocol value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocol() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocol() => $_clearField(3);
  @$pb.TagNumber(3)
  Protocol ensureProtocol() => $_ensure(2);
}

class PairRequest extends $pb.GeneratedMessage {
  factory PairRequest({
    Scope? scope,
    $core.String? ticket,
    $core.String? requestId,
    $core.String? terminalId,
    $core.String? terminalSecret,
    $core.String? displayName,
  }) {
    final result = create();
    if (scope != null) result.scope = scope;
    if (ticket != null) result.ticket = ticket;
    if (requestId != null) result.requestId = requestId;
    if (terminalId != null) result.terminalId = terminalId;
    if (terminalSecret != null) result.terminalSecret = terminalSecret;
    if (displayName != null) result.displayName = displayName;
    return result;
  }

  PairRequest._();

  factory PairRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PairRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<Scope>(1, _omitFieldNames ? '' : 'scope', subBuilder: Scope.create)
    ..aOS(2, _omitFieldNames ? '' : 'ticket')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aOS(4, _omitFieldNames ? '' : 'terminalId')
    ..aOS(5, _omitFieldNames ? '' : 'terminalSecret')
    ..aOS(6, _omitFieldNames ? '' : 'displayName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairRequest copyWith(void Function(PairRequest) updates) =>
      super.copyWith((message) => updates(message as PairRequest))
          as PairRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairRequest create() => PairRequest._();
  @$core.override
  PairRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PairRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairRequest>(create);
  static PairRequest? _defaultInstance;

  @$pb.TagNumber(1)
  Scope get scope => $_getN(0);
  @$pb.TagNumber(1)
  set scope(Scope value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasScope() => $_has(0);
  @$pb.TagNumber(1)
  void clearScope() => $_clearField(1);
  @$pb.TagNumber(1)
  Scope ensureScope() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get ticket => $_getSZ(1);
  @$pb.TagNumber(2)
  set ticket($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTicket() => $_has(1);
  @$pb.TagNumber(2)
  void clearTicket() => $_clearField(2);

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
  $core.String get terminalSecret => $_getSZ(4);
  @$pb.TagNumber(5)
  set terminalSecret($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTerminalSecret() => $_has(4);
  @$pb.TagNumber(5)
  void clearTerminalSecret() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get displayName => $_getSZ(5);
  @$pb.TagNumber(6)
  set displayName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDisplayName() => $_has(5);
  @$pb.TagNumber(6)
  void clearDisplayName() => $_clearField(6);
}

class PairResponse extends $pb.GeneratedMessage {
  factory PairResponse({
    $core.String? terminalId,
    $core.String? installationId,
    $core.String? venueId,
  }) {
    final result = create();
    if (terminalId != null) result.terminalId = terminalId;
    if (installationId != null) result.installationId = installationId;
    if (venueId != null) result.venueId = venueId;
    return result;
  }

  PairResponse._();

  factory PairResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PairResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'terminalId')
    ..aOS(2, _omitFieldNames ? '' : 'installationId')
    ..aOS(3, _omitFieldNames ? '' : 'venueId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairResponse copyWith(void Function(PairResponse) updates) =>
      super.copyWith((message) => updates(message as PairResponse))
          as PairResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairResponse create() => PairResponse._();
  @$core.override
  PairResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PairResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairResponse>(create);
  static PairResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get terminalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set terminalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTerminalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTerminalId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get installationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set installationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstallationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstallationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get venueId => $_getSZ(2);
  @$pb.TagNumber(3)
  set venueId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVenueId() => $_has(2);
  @$pb.TagNumber(3)
  void clearVenueId() => $_clearField(3);
}

class AuthenticatedRequest extends $pb.GeneratedMessage {
  factory AuthenticatedRequest({
    Scope? scope,
    $core.String? terminalId,
    $core.String? terminalSecret,
  }) {
    final result = create();
    if (scope != null) result.scope = scope;
    if (terminalId != null) result.terminalId = terminalId;
    if (terminalSecret != null) result.terminalSecret = terminalSecret;
    return result;
  }

  AuthenticatedRequest._();

  factory AuthenticatedRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AuthenticatedRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuthenticatedRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<Scope>(1, _omitFieldNames ? '' : 'scope', subBuilder: Scope.create)
    ..aOS(2, _omitFieldNames ? '' : 'terminalId')
    ..aOS(3, _omitFieldNames ? '' : 'terminalSecret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthenticatedRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthenticatedRequest copyWith(void Function(AuthenticatedRequest) updates) =>
      super.copyWith((message) => updates(message as AuthenticatedRequest))
          as AuthenticatedRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthenticatedRequest create() => AuthenticatedRequest._();
  @$core.override
  AuthenticatedRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AuthenticatedRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AuthenticatedRequest>(create);
  static AuthenticatedRequest? _defaultInstance;

  @$pb.TagNumber(1)
  Scope get scope => $_getN(0);
  @$pb.TagNumber(1)
  set scope(Scope value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasScope() => $_has(0);
  @$pb.TagNumber(1)
  void clearScope() => $_clearField(1);
  @$pb.TagNumber(1)
  Scope ensureScope() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get terminalId => $_getSZ(1);
  @$pb.TagNumber(2)
  set terminalId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTerminalId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTerminalId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get terminalSecret => $_getSZ(2);
  @$pb.TagNumber(3)
  set terminalSecret($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTerminalSecret() => $_has(2);
  @$pb.TagNumber(3)
  void clearTerminalSecret() => $_clearField(3);
}

class HandshakeRequest extends $pb.GeneratedMessage {
  factory HandshakeRequest({
    AuthenticatedRequest? auth,
    $core.String? sessionId,
    $core.String? clientVersion,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (sessionId != null) result.sessionId = sessionId;
    if (clientVersion != null) result.clientVersion = clientVersion;
    return result;
  }

  HandshakeRequest._();

  factory HandshakeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HandshakeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HandshakeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<AuthenticatedRequest>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: AuthenticatedRequest.create)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOS(3, _omitFieldNames ? '' : 'clientVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HandshakeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HandshakeRequest copyWith(void Function(HandshakeRequest) updates) =>
      super.copyWith((message) => updates(message as HandshakeRequest))
          as HandshakeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HandshakeRequest create() => HandshakeRequest._();
  @$core.override
  HandshakeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HandshakeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HandshakeRequest>(create);
  static HandshakeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  AuthenticatedRequest get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth(AuthenticatedRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  AuthenticatedRequest ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get clientVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set clientVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientVersion() => $_clearField(3);
}

class StatusResponse extends $pb.GeneratedMessage {
  factory StatusResponse({
    $core.String? installationId,
    $core.String? venueId,
    Protocol? protocol,
    $core.String? mode,
    $core.bool? businessMutationsEnabled,
    $core.int? schemaVersion,
    $core.String? bootId,
    $core.String? terminalId,
    $core.String? sessionId,
    $core.int? connectedStreams,
    $core.Iterable<$core.String>? capabilities,
  }) {
    final result = create();
    if (installationId != null) result.installationId = installationId;
    if (venueId != null) result.venueId = venueId;
    if (protocol != null) result.protocol = protocol;
    if (mode != null) result.mode = mode;
    if (businessMutationsEnabled != null)
      result.businessMutationsEnabled = businessMutationsEnabled;
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (bootId != null) result.bootId = bootId;
    if (terminalId != null) result.terminalId = terminalId;
    if (sessionId != null) result.sessionId = sessionId;
    if (connectedStreams != null) result.connectedStreams = connectedStreams;
    if (capabilities != null) result.capabilities.addAll(capabilities);
    return result;
  }

  StatusResponse._();

  factory StatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatusResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installationId')
    ..aOS(2, _omitFieldNames ? '' : 'venueId')
    ..aOM<Protocol>(3, _omitFieldNames ? '' : 'protocol',
        subBuilder: Protocol.create)
    ..aOS(4, _omitFieldNames ? '' : 'mode')
    ..aOB(5, _omitFieldNames ? '' : 'businessMutationsEnabled')
    ..aI(6, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(7, _omitFieldNames ? '' : 'bootId')
    ..aOS(8, _omitFieldNames ? '' : 'terminalId')
    ..aOS(9, _omitFieldNames ? '' : 'sessionId')
    ..aI(10, _omitFieldNames ? '' : 'connectedStreams',
        fieldType: $pb.PbFieldType.OU3)
    ..pPS(11, _omitFieldNames ? '' : 'capabilities')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusResponse copyWith(void Function(StatusResponse) updates) =>
      super.copyWith((message) => updates(message as StatusResponse))
          as StatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusResponse create() => StatusResponse._();
  @$core.override
  StatusResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatusResponse>(create);
  static StatusResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get venueId => $_getSZ(1);
  @$pb.TagNumber(2)
  set venueId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVenueId() => $_has(1);
  @$pb.TagNumber(2)
  void clearVenueId() => $_clearField(2);

  @$pb.TagNumber(3)
  Protocol get protocol => $_getN(2);
  @$pb.TagNumber(3)
  set protocol(Protocol value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocol() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocol() => $_clearField(3);
  @$pb.TagNumber(3)
  Protocol ensureProtocol() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get mode => $_getSZ(3);
  @$pb.TagNumber(4)
  set mode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearMode() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get businessMutationsEnabled => $_getBF(4);
  @$pb.TagNumber(5)
  set businessMutationsEnabled($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBusinessMutationsEnabled() => $_has(4);
  @$pb.TagNumber(5)
  void clearBusinessMutationsEnabled() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get schemaVersion => $_getIZ(5);
  @$pb.TagNumber(6)
  set schemaVersion($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSchemaVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearSchemaVersion() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get bootId => $_getSZ(6);
  @$pb.TagNumber(7)
  set bootId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBootId() => $_has(6);
  @$pb.TagNumber(7)
  void clearBootId() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get terminalId => $_getSZ(7);
  @$pb.TagNumber(8)
  set terminalId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTerminalId() => $_has(7);
  @$pb.TagNumber(8)
  void clearTerminalId() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get sessionId => $_getSZ(8);
  @$pb.TagNumber(9)
  set sessionId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSessionId() => $_has(8);
  @$pb.TagNumber(9)
  void clearSessionId() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get connectedStreams => $_getIZ(9);
  @$pb.TagNumber(10)
  set connectedStreams($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasConnectedStreams() => $_has(9);
  @$pb.TagNumber(10)
  void clearConnectedStreams() => $_clearField(10);

  @$pb.TagNumber(11)
  $pb.PbList<$core.String> get capabilities => $_getList(10);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
