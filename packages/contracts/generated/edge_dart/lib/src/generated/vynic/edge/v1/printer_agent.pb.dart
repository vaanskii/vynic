// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/printer_agent.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'printer_agent.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'printer_agent.pbenum.dart';

class PrinterAgentAuth extends $pb.GeneratedMessage {
  factory PrinterAgentAuth({
    $core.String? hostId,
    $core.String? clientId,
    $core.int? protocolMajor,
    $core.int? protocolMinor,
    $core.int? readerVersion,
    $core.Iterable<$core.String>? requiredCapabilities,
  }) {
    final result = create();
    if (hostId != null) result.hostId = hostId;
    if (clientId != null) result.clientId = clientId;
    if (protocolMajor != null) result.protocolMajor = protocolMajor;
    if (protocolMinor != null) result.protocolMinor = protocolMinor;
    if (readerVersion != null) result.readerVersion = readerVersion;
    if (requiredCapabilities != null)
      result.requiredCapabilities.addAll(requiredCapabilities);
    return result;
  }

  PrinterAgentAuth._();

  factory PrinterAgentAuth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentAuth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentAuth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'hostId')
    ..aOS(2, _omitFieldNames ? '' : 'clientId')
    ..aI(3, _omitFieldNames ? '' : 'protocolMajor',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'protocolMinor',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'readerVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..pPS(6, _omitFieldNames ? '' : 'requiredCapabilities')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentAuth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentAuth copyWith(void Function(PrinterAgentAuth) updates) =>
      super.copyWith((message) => updates(message as PrinterAgentAuth))
          as PrinterAgentAuth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentAuth create() => PrinterAgentAuth._();
  @$core.override
  PrinterAgentAuth createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentAuth getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentAuth>(create);
  static PrinterAgentAuth? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get hostId => $_getSZ(0);
  @$pb.TagNumber(1)
  set hostId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHostId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHostId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get clientId => $_getSZ(1);
  @$pb.TagNumber(2)
  set clientId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClientId() => $_has(1);
  @$pb.TagNumber(2)
  void clearClientId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get protocolMajor => $_getIZ(2);
  @$pb.TagNumber(3)
  set protocolMajor($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocolMajor() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocolMajor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get protocolMinor => $_getIZ(3);
  @$pb.TagNumber(4)
  set protocolMinor($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProtocolMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearProtocolMinor() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get readerVersion => $_getIZ(4);
  @$pb.TagNumber(5)
  set readerVersion($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasReaderVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearReaderVersion() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get requiredCapabilities => $_getList(5);
}

class PrinterAgentPins extends $pb.GeneratedMessage {
  factory PrinterAgentPins({
    $core.String? scope,
    $core.String? ownershipPolicy,
    $core.String? clusterId,
    $core.String? membershipSha256,
    $core.String? role,
    $core.String? venueId,
    $core.String? installationId,
    $core.String? deviceId,
    $core.String? hostId,
    $core.String? gatewayHostId,
    $fixnum.Int64? authorityEpoch,
    $core.int? protocolVersion,
    $core.int? helperProtocolVersion,
    $core.int? databaseSchemaVersion,
    $core.int? minimumReaderVersion,
    $fixnum.Int64? routeRevision,
    $fixnum.Int64? configRevision,
    $fixnum.Int64? registryRevision,
    $fixnum.Int64? bindingRevision,
    $fixnum.Int64? capabilityRevision,
    $core.String? capabilityProfileSha256,
    $core.String? hostBinarySha256,
    $core.String? helperBinarySha256,
  }) {
    final result = create();
    if (scope != null) result.scope = scope;
    if (ownershipPolicy != null) result.ownershipPolicy = ownershipPolicy;
    if (clusterId != null) result.clusterId = clusterId;
    if (membershipSha256 != null) result.membershipSha256 = membershipSha256;
    if (role != null) result.role = role;
    if (venueId != null) result.venueId = venueId;
    if (installationId != null) result.installationId = installationId;
    if (deviceId != null) result.deviceId = deviceId;
    if (hostId != null) result.hostId = hostId;
    if (gatewayHostId != null) result.gatewayHostId = gatewayHostId;
    if (authorityEpoch != null) result.authorityEpoch = authorityEpoch;
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (helperProtocolVersion != null)
      result.helperProtocolVersion = helperProtocolVersion;
    if (databaseSchemaVersion != null)
      result.databaseSchemaVersion = databaseSchemaVersion;
    if (minimumReaderVersion != null)
      result.minimumReaderVersion = minimumReaderVersion;
    if (routeRevision != null) result.routeRevision = routeRevision;
    if (configRevision != null) result.configRevision = configRevision;
    if (registryRevision != null) result.registryRevision = registryRevision;
    if (bindingRevision != null) result.bindingRevision = bindingRevision;
    if (capabilityRevision != null)
      result.capabilityRevision = capabilityRevision;
    if (capabilityProfileSha256 != null)
      result.capabilityProfileSha256 = capabilityProfileSha256;
    if (hostBinarySha256 != null) result.hostBinarySha256 = hostBinarySha256;
    if (helperBinarySha256 != null)
      result.helperBinarySha256 = helperBinarySha256;
    return result;
  }

  PrinterAgentPins._();

  factory PrinterAgentPins.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentPins.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentPins',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'scope')
    ..aOS(2, _omitFieldNames ? '' : 'ownershipPolicy')
    ..aOS(3, _omitFieldNames ? '' : 'clusterId')
    ..aOS(4, _omitFieldNames ? '' : 'membershipSha256')
    ..aOS(5, _omitFieldNames ? '' : 'role')
    ..aOS(6, _omitFieldNames ? '' : 'venueId')
    ..aOS(7, _omitFieldNames ? '' : 'installationId')
    ..aOS(8, _omitFieldNames ? '' : 'deviceId')
    ..aOS(9, _omitFieldNames ? '' : 'hostId')
    ..aOS(10, _omitFieldNames ? '' : 'gatewayHostId')
    ..a<$fixnum.Int64>(
        11, _omitFieldNames ? '' : 'authorityEpoch', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(12, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(13, _omitFieldNames ? '' : 'helperProtocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(14, _omitFieldNames ? '' : 'databaseSchemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(15, _omitFieldNames ? '' : 'minimumReaderVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        16, _omitFieldNames ? '' : 'routeRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        17, _omitFieldNames ? '' : 'configRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        18, _omitFieldNames ? '' : 'registryRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        19, _omitFieldNames ? '' : 'bindingRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        20, _omitFieldNames ? '' : 'capabilityRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(21, _omitFieldNames ? '' : 'capabilityProfileSha256')
    ..aOS(22, _omitFieldNames ? '' : 'hostBinarySha256')
    ..aOS(23, _omitFieldNames ? '' : 'helperBinarySha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentPins clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentPins copyWith(void Function(PrinterAgentPins) updates) =>
      super.copyWith((message) => updates(message as PrinterAgentPins))
          as PrinterAgentPins;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentPins create() => PrinterAgentPins._();
  @$core.override
  PrinterAgentPins createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentPins getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentPins>(create);
  static PrinterAgentPins? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get scope => $_getSZ(0);
  @$pb.TagNumber(1)
  set scope($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasScope() => $_has(0);
  @$pb.TagNumber(1)
  void clearScope() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get ownershipPolicy => $_getSZ(1);
  @$pb.TagNumber(2)
  set ownershipPolicy($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOwnershipPolicy() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwnershipPolicy() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get clusterId => $_getSZ(2);
  @$pb.TagNumber(3)
  set clusterId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClusterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearClusterId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get membershipSha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set membershipSha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMembershipSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearMembershipSha256() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get role => $_getSZ(4);
  @$pb.TagNumber(5)
  set role($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRole() => $_has(4);
  @$pb.TagNumber(5)
  void clearRole() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get venueId => $_getSZ(5);
  @$pb.TagNumber(6)
  set venueId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasVenueId() => $_has(5);
  @$pb.TagNumber(6)
  void clearVenueId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get installationId => $_getSZ(6);
  @$pb.TagNumber(7)
  set installationId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasInstallationId() => $_has(6);
  @$pb.TagNumber(7)
  void clearInstallationId() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get deviceId => $_getSZ(7);
  @$pb.TagNumber(8)
  set deviceId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDeviceId() => $_has(7);
  @$pb.TagNumber(8)
  void clearDeviceId() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get hostId => $_getSZ(8);
  @$pb.TagNumber(9)
  set hostId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasHostId() => $_has(8);
  @$pb.TagNumber(9)
  void clearHostId() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get gatewayHostId => $_getSZ(9);
  @$pb.TagNumber(10)
  set gatewayHostId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasGatewayHostId() => $_has(9);
  @$pb.TagNumber(10)
  void clearGatewayHostId() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get authorityEpoch => $_getI64(10);
  @$pb.TagNumber(11)
  set authorityEpoch($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAuthorityEpoch() => $_has(10);
  @$pb.TagNumber(11)
  void clearAuthorityEpoch() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get protocolVersion => $_getIZ(11);
  @$pb.TagNumber(12)
  set protocolVersion($core.int value) => $_setUnsignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasProtocolVersion() => $_has(11);
  @$pb.TagNumber(12)
  void clearProtocolVersion() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get helperProtocolVersion => $_getIZ(12);
  @$pb.TagNumber(13)
  set helperProtocolVersion($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasHelperProtocolVersion() => $_has(12);
  @$pb.TagNumber(13)
  void clearHelperProtocolVersion() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get databaseSchemaVersion => $_getIZ(13);
  @$pb.TagNumber(14)
  set databaseSchemaVersion($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasDatabaseSchemaVersion() => $_has(13);
  @$pb.TagNumber(14)
  void clearDatabaseSchemaVersion() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get minimumReaderVersion => $_getIZ(14);
  @$pb.TagNumber(15)
  set minimumReaderVersion($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasMinimumReaderVersion() => $_has(14);
  @$pb.TagNumber(15)
  void clearMinimumReaderVersion() => $_clearField(15);

  @$pb.TagNumber(16)
  $fixnum.Int64 get routeRevision => $_getI64(15);
  @$pb.TagNumber(16)
  set routeRevision($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(16)
  $core.bool hasRouteRevision() => $_has(15);
  @$pb.TagNumber(16)
  void clearRouteRevision() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get configRevision => $_getI64(16);
  @$pb.TagNumber(17)
  set configRevision($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasConfigRevision() => $_has(16);
  @$pb.TagNumber(17)
  void clearConfigRevision() => $_clearField(17);

  @$pb.TagNumber(18)
  $fixnum.Int64 get registryRevision => $_getI64(17);
  @$pb.TagNumber(18)
  set registryRevision($fixnum.Int64 value) => $_setInt64(17, value);
  @$pb.TagNumber(18)
  $core.bool hasRegistryRevision() => $_has(17);
  @$pb.TagNumber(18)
  void clearRegistryRevision() => $_clearField(18);

  @$pb.TagNumber(19)
  $fixnum.Int64 get bindingRevision => $_getI64(18);
  @$pb.TagNumber(19)
  set bindingRevision($fixnum.Int64 value) => $_setInt64(18, value);
  @$pb.TagNumber(19)
  $core.bool hasBindingRevision() => $_has(18);
  @$pb.TagNumber(19)
  void clearBindingRevision() => $_clearField(19);

  @$pb.TagNumber(20)
  $fixnum.Int64 get capabilityRevision => $_getI64(19);
  @$pb.TagNumber(20)
  set capabilityRevision($fixnum.Int64 value) => $_setInt64(19, value);
  @$pb.TagNumber(20)
  $core.bool hasCapabilityRevision() => $_has(19);
  @$pb.TagNumber(20)
  void clearCapabilityRevision() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.String get capabilityProfileSha256 => $_getSZ(20);
  @$pb.TagNumber(21)
  set capabilityProfileSha256($core.String value) => $_setString(20, value);
  @$pb.TagNumber(21)
  $core.bool hasCapabilityProfileSha256() => $_has(20);
  @$pb.TagNumber(21)
  void clearCapabilityProfileSha256() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.String get hostBinarySha256 => $_getSZ(21);
  @$pb.TagNumber(22)
  set hostBinarySha256($core.String value) => $_setString(21, value);
  @$pb.TagNumber(22)
  $core.bool hasHostBinarySha256() => $_has(21);
  @$pb.TagNumber(22)
  void clearHostBinarySha256() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.String get helperBinarySha256 => $_getSZ(22);
  @$pb.TagNumber(23)
  set helperBinarySha256($core.String value) => $_setString(22, value);
  @$pb.TagNumber(23)
  $core.bool hasHelperBinarySha256() => $_has(22);
  @$pb.TagNumber(23)
  void clearHelperBinarySha256() => $_clearField(23);
}

class PrinterAgentHealthRequest extends $pb.GeneratedMessage {
  factory PrinterAgentHealthRequest({
    PrinterAgentAuth? auth,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    return result;
  }

  PrinterAgentHealthRequest._();

  factory PrinterAgentHealthRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentHealthRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentHealthRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<PrinterAgentAuth>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: PrinterAgentAuth.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentHealthRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentHealthRequest copyWith(
          void Function(PrinterAgentHealthRequest) updates) =>
      super.copyWith((message) => updates(message as PrinterAgentHealthRequest))
          as PrinterAgentHealthRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentHealthRequest create() => PrinterAgentHealthRequest._();
  @$core.override
  PrinterAgentHealthRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentHealthRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentHealthRequest>(create);
  static PrinterAgentHealthRequest? _defaultInstance;

  @$pb.TagNumber(1)
  PrinterAgentAuth get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth(PrinterAgentAuth value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  PrinterAgentAuth ensureAuth() => $_ensure(0);
}

class PrinterAgentPrinterHold extends $pb.GeneratedMessage {
  factory PrinterAgentPrinterHold({
    $core.String? physicalPrinterId,
    $core.String? reason,
  }) {
    final result = create();
    if (physicalPrinterId != null) result.physicalPrinterId = physicalPrinterId;
    if (reason != null) result.reason = reason;
    return result;
  }

  PrinterAgentPrinterHold._();

  factory PrinterAgentPrinterHold.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentPrinterHold.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentPrinterHold',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'physicalPrinterId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentPrinterHold clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentPrinterHold copyWith(
          void Function(PrinterAgentPrinterHold) updates) =>
      super.copyWith((message) => updates(message as PrinterAgentPrinterHold))
          as PrinterAgentPrinterHold;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentPrinterHold create() => PrinterAgentPrinterHold._();
  @$core.override
  PrinterAgentPrinterHold createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentPrinterHold getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentPrinterHold>(create);
  static PrinterAgentPrinterHold? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get physicalPrinterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set physicalPrinterId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhysicalPrinterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhysicalPrinterId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class PrinterAgentHealthResponse extends $pb.GeneratedMessage {
  factory PrinterAgentHealthResponse({
    $core.int? protocolVersion,
    PrinterAgentPins? pins,
    $core.String? clientId,
    PrinterAgentLifecycle? state,
    $core.bool? softwareReady,
    PrinterAgentPhysicalState? physicalState,
    PrinterAgentAdmissionState? admissionState,
    $core.Iterable<PrinterAgentHoldReason>? holdReasons,
    $core.Iterable<PrinterAgentPrinterHold>? printerHolds,
    $fixnum.Int64? activeAdmissions,
  }) {
    final result = create();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (pins != null) result.pins = pins;
    if (clientId != null) result.clientId = clientId;
    if (state != null) result.state = state;
    if (softwareReady != null) result.softwareReady = softwareReady;
    if (physicalState != null) result.physicalState = physicalState;
    if (admissionState != null) result.admissionState = admissionState;
    if (holdReasons != null) result.holdReasons.addAll(holdReasons);
    if (printerHolds != null) result.printerHolds.addAll(printerHolds);
    if (activeAdmissions != null) result.activeAdmissions = activeAdmissions;
    return result;
  }

  PrinterAgentHealthResponse._();

  factory PrinterAgentHealthResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentHealthResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentHealthResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<PrinterAgentPins>(2, _omitFieldNames ? '' : 'pins',
        subBuilder: PrinterAgentPins.create)
    ..aOS(3, _omitFieldNames ? '' : 'clientId')
    ..aE<PrinterAgentLifecycle>(4, _omitFieldNames ? '' : 'state',
        enumValues: PrinterAgentLifecycle.values)
    ..aOB(5, _omitFieldNames ? '' : 'softwareReady')
    ..aE<PrinterAgentPhysicalState>(6, _omitFieldNames ? '' : 'physicalState',
        enumValues: PrinterAgentPhysicalState.values)
    ..aE<PrinterAgentAdmissionState>(7, _omitFieldNames ? '' : 'admissionState',
        enumValues: PrinterAgentAdmissionState.values)
    ..pc<PrinterAgentHoldReason>(
        8, _omitFieldNames ? '' : 'holdReasons', $pb.PbFieldType.KE,
        valueOf: PrinterAgentHoldReason.valueOf,
        enumValues: PrinterAgentHoldReason.values,
        defaultEnumValue: PrinterAgentHoldReason.PRINTER_AGENT_HOLD_UNSPECIFIED)
    ..pPM<PrinterAgentPrinterHold>(9, _omitFieldNames ? '' : 'printerHolds',
        subBuilder: PrinterAgentPrinterHold.create)
    ..a<$fixnum.Int64>(
        10, _omitFieldNames ? '' : 'activeAdmissions', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentHealthResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentHealthResponse copyWith(
          void Function(PrinterAgentHealthResponse) updates) =>
      super.copyWith(
              (message) => updates(message as PrinterAgentHealthResponse))
          as PrinterAgentHealthResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentHealthResponse create() => PrinterAgentHealthResponse._();
  @$core.override
  PrinterAgentHealthResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentHealthResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentHealthResponse>(create);
  static PrinterAgentHealthResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  PrinterAgentPins get pins => $_getN(1);
  @$pb.TagNumber(2)
  set pins(PrinterAgentPins value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPins() => $_has(1);
  @$pb.TagNumber(2)
  void clearPins() => $_clearField(2);
  @$pb.TagNumber(2)
  PrinterAgentPins ensurePins() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get clientId => $_getSZ(2);
  @$pb.TagNumber(3)
  set clientId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientId() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientId() => $_clearField(3);

  @$pb.TagNumber(4)
  PrinterAgentLifecycle get state => $_getN(3);
  @$pb.TagNumber(4)
  set state(PrinterAgentLifecycle value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasState() => $_has(3);
  @$pb.TagNumber(4)
  void clearState() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get softwareReady => $_getBF(4);
  @$pb.TagNumber(5)
  set softwareReady($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSoftwareReady() => $_has(4);
  @$pb.TagNumber(5)
  void clearSoftwareReady() => $_clearField(5);

  @$pb.TagNumber(6)
  PrinterAgentPhysicalState get physicalState => $_getN(5);
  @$pb.TagNumber(6)
  set physicalState(PrinterAgentPhysicalState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPhysicalState() => $_has(5);
  @$pb.TagNumber(6)
  void clearPhysicalState() => $_clearField(6);

  @$pb.TagNumber(7)
  PrinterAgentAdmissionState get admissionState => $_getN(6);
  @$pb.TagNumber(7)
  set admissionState(PrinterAgentAdmissionState value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasAdmissionState() => $_has(6);
  @$pb.TagNumber(7)
  void clearAdmissionState() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<PrinterAgentHoldReason> get holdReasons => $_getList(7);

  @$pb.TagNumber(9)
  $pb.PbList<PrinterAgentPrinterHold> get printerHolds => $_getList(8);

  @$pb.TagNumber(10)
  $fixnum.Int64 get activeAdmissions => $_getI64(9);
  @$pb.TagNumber(10)
  set activeAdmissions($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasActiveAdmissions() => $_has(9);
  @$pb.TagNumber(10)
  void clearActiveAdmissions() => $_clearField(10);
}

class PrinterAgentSubmitLocalRequest extends $pb.GeneratedMessage {
  factory PrinterAgentSubmitLocalRequest({
    PrinterAgentAuth? auth,
    $core.String? requestId,
    $core.String? jobId,
    $core.List<$core.int>? frozenEnvelope,
    $core.String? envelopeSha256,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (requestId != null) result.requestId = requestId;
    if (jobId != null) result.jobId = jobId;
    if (frozenEnvelope != null) result.frozenEnvelope = frozenEnvelope;
    if (envelopeSha256 != null) result.envelopeSha256 = envelopeSha256;
    return result;
  }

  PrinterAgentSubmitLocalRequest._();

  factory PrinterAgentSubmitLocalRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentSubmitLocalRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentSubmitLocalRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<PrinterAgentAuth>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: PrinterAgentAuth.create)
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aOS(3, _omitFieldNames ? '' : 'jobId')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'frozenEnvelope', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'envelopeSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentSubmitLocalRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentSubmitLocalRequest copyWith(
          void Function(PrinterAgentSubmitLocalRequest) updates) =>
      super.copyWith(
              (message) => updates(message as PrinterAgentSubmitLocalRequest))
          as PrinterAgentSubmitLocalRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentSubmitLocalRequest create() =>
      PrinterAgentSubmitLocalRequest._();
  @$core.override
  PrinterAgentSubmitLocalRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentSubmitLocalRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentSubmitLocalRequest>(create);
  static PrinterAgentSubmitLocalRequest? _defaultInstance;

  @$pb.TagNumber(1)
  PrinterAgentAuth get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth(PrinterAgentAuth value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  PrinterAgentAuth ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get jobId => $_getSZ(2);
  @$pb.TagNumber(3)
  set jobId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasJobId() => $_has(2);
  @$pb.TagNumber(3)
  void clearJobId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get frozenEnvelope => $_getN(3);
  @$pb.TagNumber(4)
  set frozenEnvelope($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFrozenEnvelope() => $_has(3);
  @$pb.TagNumber(4)
  void clearFrozenEnvelope() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get envelopeSha256 => $_getSZ(4);
  @$pb.TagNumber(5)
  set envelopeSha256($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEnvelopeSha256() => $_has(4);
  @$pb.TagNumber(5)
  void clearEnvelopeSha256() => $_clearField(5);
}

class PrinterAgentGetLocalResultRequest extends $pb.GeneratedMessage {
  factory PrinterAgentGetLocalResultRequest({
    PrinterAgentAuth? auth,
    $core.String? requestId,
    $core.String? jobId,
    $core.String? envelopeSha256,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (requestId != null) result.requestId = requestId;
    if (jobId != null) result.jobId = jobId;
    if (envelopeSha256 != null) result.envelopeSha256 = envelopeSha256;
    return result;
  }

  PrinterAgentGetLocalResultRequest._();

  factory PrinterAgentGetLocalResultRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentGetLocalResultRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentGetLocalResultRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOM<PrinterAgentAuth>(1, _omitFieldNames ? '' : 'auth',
        subBuilder: PrinterAgentAuth.create)
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aOS(3, _omitFieldNames ? '' : 'jobId')
    ..aOS(4, _omitFieldNames ? '' : 'envelopeSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentGetLocalResultRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentGetLocalResultRequest copyWith(
          void Function(PrinterAgentGetLocalResultRequest) updates) =>
      super.copyWith((message) =>
              updates(message as PrinterAgentGetLocalResultRequest))
          as PrinterAgentGetLocalResultRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentGetLocalResultRequest create() =>
      PrinterAgentGetLocalResultRequest._();
  @$core.override
  PrinterAgentGetLocalResultRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentGetLocalResultRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentGetLocalResultRequest>(
          create);
  static PrinterAgentGetLocalResultRequest? _defaultInstance;

  @$pb.TagNumber(1)
  PrinterAgentAuth get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth(PrinterAgentAuth value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  PrinterAgentAuth ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get jobId => $_getSZ(2);
  @$pb.TagNumber(3)
  set jobId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasJobId() => $_has(2);
  @$pb.TagNumber(3)
  void clearJobId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get envelopeSha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set envelopeSha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEnvelopeSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearEnvelopeSha256() => $_clearField(4);
}

/// No successful result is produced in this version. Both local methods return
/// FAILED_PRECONDITION HELD_PROVISIONING after authenticated strict validation.
class PrinterAgentSubmissionResult extends $pb.GeneratedMessage {
  factory PrinterAgentSubmissionResult({
    $core.String? requestId,
    $core.String? jobId,
    $core.String? envelopeSha256,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (jobId != null) result.jobId = jobId;
    if (envelopeSha256 != null) result.envelopeSha256 = envelopeSha256;
    return result;
  }

  PrinterAgentSubmissionResult._();

  factory PrinterAgentSubmissionResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrinterAgentSubmissionResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrinterAgentSubmissionResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vynic.edge.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'jobId')
    ..aOS(3, _omitFieldNames ? '' : 'envelopeSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentSubmissionResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrinterAgentSubmissionResult copyWith(
          void Function(PrinterAgentSubmissionResult) updates) =>
      super.copyWith(
              (message) => updates(message as PrinterAgentSubmissionResult))
          as PrinterAgentSubmissionResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrinterAgentSubmissionResult create() =>
      PrinterAgentSubmissionResult._();
  @$core.override
  PrinterAgentSubmissionResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrinterAgentSubmissionResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrinterAgentSubmissionResult>(create);
  static PrinterAgentSubmissionResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get jobId => $_getSZ(1);
  @$pb.TagNumber(2)
  set jobId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasJobId() => $_has(1);
  @$pb.TagNumber(2)
  void clearJobId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get envelopeSha256 => $_getSZ(2);
  @$pb.TagNumber(3)
  set envelopeSha256($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnvelopeSha256() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnvelopeSha256() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
