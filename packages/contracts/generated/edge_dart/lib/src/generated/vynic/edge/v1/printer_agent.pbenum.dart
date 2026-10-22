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

import 'package:protobuf/protobuf.dart' as $pb;

class PrinterAgentLifecycle extends $pb.ProtobufEnum {
  static const PrinterAgentLifecycle PRINTER_AGENT_LIFECYCLE_UNSPECIFIED =
      PrinterAgentLifecycle._(
          0, _omitEnumNames ? '' : 'PRINTER_AGENT_LIFECYCLE_UNSPECIFIED');
  static const PrinterAgentLifecycle PRINTER_AGENT_NEW =
      PrinterAgentLifecycle._(1, _omitEnumNames ? '' : 'PRINTER_AGENT_NEW');
  static const PrinterAgentLifecycle PRINTER_AGENT_STARTING =
      PrinterAgentLifecycle._(
          2, _omitEnumNames ? '' : 'PRINTER_AGENT_STARTING');
  static const PrinterAgentLifecycle PRINTER_AGENT_RUNNING =
      PrinterAgentLifecycle._(3, _omitEnumNames ? '' : 'PRINTER_AGENT_RUNNING');
  static const PrinterAgentLifecycle PRINTER_AGENT_DRAINING =
      PrinterAgentLifecycle._(
          4, _omitEnumNames ? '' : 'PRINTER_AGENT_DRAINING');
  static const PrinterAgentLifecycle PRINTER_AGENT_STOPPED =
      PrinterAgentLifecycle._(5, _omitEnumNames ? '' : 'PRINTER_AGENT_STOPPED');
  static const PrinterAgentLifecycle PRINTER_AGENT_HELD =
      PrinterAgentLifecycle._(6, _omitEnumNames ? '' : 'PRINTER_AGENT_HELD');

  static const $core.List<PrinterAgentLifecycle> values =
      <PrinterAgentLifecycle>[
    PRINTER_AGENT_LIFECYCLE_UNSPECIFIED,
    PRINTER_AGENT_NEW,
    PRINTER_AGENT_STARTING,
    PRINTER_AGENT_RUNNING,
    PRINTER_AGENT_DRAINING,
    PRINTER_AGENT_STOPPED,
    PRINTER_AGENT_HELD,
  ];

  static final $core.List<PrinterAgentLifecycle?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static PrinterAgentLifecycle? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PrinterAgentLifecycle._(super.value, super.name);
}

class PrinterAgentPhysicalState extends $pb.ProtobufEnum {
  static const PrinterAgentPhysicalState PRINTER_AGENT_PHYSICAL_UNSPECIFIED =
      PrinterAgentPhysicalState._(
          0, _omitEnumNames ? '' : 'PRINTER_AGENT_PHYSICAL_UNSPECIFIED');
  static const PrinterAgentPhysicalState PRINTER_AGENT_PHYSICAL_HELD =
      PrinterAgentPhysicalState._(
          1, _omitEnumNames ? '' : 'PRINTER_AGENT_PHYSICAL_HELD');

  static const $core.List<PrinterAgentPhysicalState> values =
      <PrinterAgentPhysicalState>[
    PRINTER_AGENT_PHYSICAL_UNSPECIFIED,
    PRINTER_AGENT_PHYSICAL_HELD,
  ];

  static final $core.List<PrinterAgentPhysicalState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static PrinterAgentPhysicalState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PrinterAgentPhysicalState._(super.value, super.name);
}

class PrinterAgentAdmissionState extends $pb.ProtobufEnum {
  static const PrinterAgentAdmissionState PRINTER_AGENT_ADMISSION_UNSPECIFIED =
      PrinterAgentAdmissionState._(
          0, _omitEnumNames ? '' : 'PRINTER_AGENT_ADMISSION_UNSPECIFIED');
  static const PrinterAgentAdmissionState
      PRINTER_AGENT_ADMISSION_HELD_PROVISIONING = PrinterAgentAdmissionState._(
          1, _omitEnumNames ? '' : 'PRINTER_AGENT_ADMISSION_HELD_PROVISIONING');

  static const $core.List<PrinterAgentAdmissionState> values =
      <PrinterAgentAdmissionState>[
    PRINTER_AGENT_ADMISSION_UNSPECIFIED,
    PRINTER_AGENT_ADMISSION_HELD_PROVISIONING,
  ];

  static final $core.List<PrinterAgentAdmissionState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static PrinterAgentAdmissionState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PrinterAgentAdmissionState._(super.value, super.name);
}

class PrinterAgentHoldReason extends $pb.ProtobufEnum {
  static const PrinterAgentHoldReason PRINTER_AGENT_HOLD_UNSPECIFIED =
      PrinterAgentHoldReason._(
          0, _omitEnumNames ? '' : 'PRINTER_AGENT_HOLD_UNSPECIFIED');
  static const PrinterAgentHoldReason PRINTER_AGENT_PROVISIONING_UNQUALIFIED =
      PrinterAgentHoldReason._(
          1, _omitEnumNames ? '' : 'PRINTER_AGENT_PROVISIONING_UNQUALIFIED');
  static const PrinterAgentHoldReason
      PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING = PrinterAgentHoldReason._(
          2, _omitEnumNames ? '' : 'PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING');
  static const PrinterAgentHoldReason PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED =
      PrinterAgentHoldReason._(
          3, _omitEnumNames ? '' : 'PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED');
  static const PrinterAgentHoldReason PRINTER_AGENT_HOST_UNAVAILABLE =
      PrinterAgentHoldReason._(
          4, _omitEnumNames ? '' : 'PRINTER_AGENT_HOST_UNAVAILABLE');
  static const PrinterAgentHoldReason PRINTER_AGENT_RETAINED_QUEUE_HOLD =
      PrinterAgentHoldReason._(
          5, _omitEnumNames ? '' : 'PRINTER_AGENT_RETAINED_QUEUE_HOLD');

  static const $core.List<PrinterAgentHoldReason> values =
      <PrinterAgentHoldReason>[
    PRINTER_AGENT_HOLD_UNSPECIFIED,
    PRINTER_AGENT_PROVISIONING_UNQUALIFIED,
    PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING,
    PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED,
    PRINTER_AGENT_HOST_UNAVAILABLE,
    PRINTER_AGENT_RETAINED_QUEUE_HOLD,
  ];

  static final $core.List<PrinterAgentHoldReason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static PrinterAgentHoldReason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PrinterAgentHoldReason._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
