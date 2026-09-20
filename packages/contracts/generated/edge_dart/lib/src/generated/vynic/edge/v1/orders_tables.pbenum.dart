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

import 'package:protobuf/protobuf.dart' as $pb;

class ProjectionEntity_Kind extends $pb.ProtobufEnum {
  static const ProjectionEntity_Kind UNSPECIFIED =
      ProjectionEntity_Kind._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const ProjectionEntity_Kind ORDER =
      ProjectionEntity_Kind._(1, _omitEnumNames ? '' : 'ORDER');
  static const ProjectionEntity_Kind TABLE =
      ProjectionEntity_Kind._(2, _omitEnumNames ? '' : 'TABLE');

  static const $core.List<ProjectionEntity_Kind> values =
      <ProjectionEntity_Kind>[
    UNSPECIFIED,
    ORDER,
    TABLE,
  ];

  static final $core.List<ProjectionEntity_Kind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ProjectionEntity_Kind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ProjectionEntity_Kind._(super.value, super.name);
}

class CommitResult_Outcome extends $pb.ProtobufEnum {
  static const CommitResult_Outcome UNSPECIFIED =
      CommitResult_Outcome._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const CommitResult_Outcome COMMITTED =
      CommitResult_Outcome._(1, _omitEnumNames ? '' : 'COMMITTED');
  static const CommitResult_Outcome CONFLICT =
      CommitResult_Outcome._(2, _omitEnumNames ? '' : 'CONFLICT');

  static const $core.List<CommitResult_Outcome> values = <CommitResult_Outcome>[
    UNSPECIFIED,
    COMMITTED,
    CONFLICT,
  ];

  static final $core.List<CommitResult_Outcome?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static CommitResult_Outcome? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CommitResult_Outcome._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
