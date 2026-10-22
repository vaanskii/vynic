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

import 'package:protobuf/protobuf.dart' as $pb;

class ProofEntity_Kind extends $pb.ProtobufEnum {
  static const ProofEntity_Kind UNSPECIFIED =
      ProofEntity_Kind._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const ProofEntity_Kind ORDER =
      ProofEntity_Kind._(1, _omitEnumNames ? '' : 'ORDER');
  static const ProofEntity_Kind TABLE =
      ProofEntity_Kind._(2, _omitEnumNames ? '' : 'TABLE');
  static const ProofEntity_Kind RESERVATION =
      ProofEntity_Kind._(3, _omitEnumNames ? '' : 'RESERVATION');
  static const ProofEntity_Kind PACKAGE =
      ProofEntity_Kind._(4, _omitEnumNames ? '' : 'PACKAGE');
  static const ProofEntity_Kind SALE =
      ProofEntity_Kind._(5, _omitEnumNames ? '' : 'SALE');
  static const ProofEntity_Kind DAY =
      ProofEntity_Kind._(6, _omitEnumNames ? '' : 'DAY');

  /// Planned Venue-owned control record with a stable planner-supplied UUID:
  /// global lastOrderId/currentDayId and admitted phase. The store preserves
  /// opaque postimages; it neither plans these fields nor derives their IDs.
  static const ProofEntity_Kind OPERATIONAL_CONTROL =
      ProofEntity_Kind._(7, _omitEnumNames ? '' : 'OPERATIONAL_CONTROL');
  static const ProofEntity_Kind AUDIT_REPORT =
      ProofEntity_Kind._(8, _omitEnumNames ? '' : 'AUDIT_REPORT');
  static const ProofEntity_Kind CLOSURE =
      ProofEntity_Kind._(9, _omitEnumNames ? '' : 'CLOSURE');
  static const ProofEntity_Kind ADVANCE =
      ProofEntity_Kind._(10, _omitEnumNames ? '' : 'ADVANCE');
  static const ProofEntity_Kind EXPENSE =
      ProofEntity_Kind._(11, _omitEnumNames ? '' : 'EXPENSE');
  static const ProofEntity_Kind STAFF =
      ProofEntity_Kind._(12, _omitEnumNames ? '' : 'STAFF');
  static const ProofEntity_Kind OPERATIONAL_POLICY =
      ProofEntity_Kind._(13, _omitEnumNames ? '' : 'OPERATIONAL_POLICY');

  static const $core.List<ProofEntity_Kind> values = <ProofEntity_Kind>[
    UNSPECIFIED,
    ORDER,
    TABLE,
    RESERVATION,
    PACKAGE,
    SALE,
    DAY,
    OPERATIONAL_CONTROL,
    AUDIT_REPORT,
    CLOSURE,
    ADVANCE,
    EXPENSE,
    STAFF,
    OPERATIONAL_POLICY,
  ];

  static final $core.List<ProofEntity_Kind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 13);
  static ProofEntity_Kind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ProofEntity_Kind._(super.value, super.name);
}

class ProofEffect_Kind extends $pb.ProtobufEnum {
  static const ProofEffect_Kind UNSPECIFIED =
      ProofEffect_Kind._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const ProofEffect_Kind AUDIT =
      ProofEffect_Kind._(1, _omitEnumNames ? '' : 'AUDIT');
  static const ProofEffect_Kind PRINT =
      ProofEffect_Kind._(2, _omitEnumNames ? '' : 'PRINT');

  static const $core.List<ProofEffect_Kind> values = <ProofEffect_Kind>[
    UNSPECIFIED,
    AUDIT,
    PRINT,
  ];

  static final $core.List<ProofEffect_Kind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ProofEffect_Kind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ProofEffect_Kind._(super.value, super.name);
}

class ProofCommitResult_Outcome extends $pb.ProtobufEnum {
  static const ProofCommitResult_Outcome UNSPECIFIED =
      ProofCommitResult_Outcome._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const ProofCommitResult_Outcome COMMITTED =
      ProofCommitResult_Outcome._(1, _omitEnumNames ? '' : 'COMMITTED');
  static const ProofCommitResult_Outcome CONFLICT =
      ProofCommitResult_Outcome._(2, _omitEnumNames ? '' : 'CONFLICT');

  static const $core.List<ProofCommitResult_Outcome> values =
      <ProofCommitResult_Outcome>[
    UNSPECIFIED,
    COMMITTED,
    CONFLICT,
  ];

  static final $core.List<ProofCommitResult_Outcome?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ProofCommitResult_Outcome? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ProofCommitResult_Outcome._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
