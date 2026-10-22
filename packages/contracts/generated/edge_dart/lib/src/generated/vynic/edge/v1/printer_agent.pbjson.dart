// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/printer_agent.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use printerAgentLifecycleDescriptor instead')
const PrinterAgentLifecycle$json = {
  '1': 'PrinterAgentLifecycle',
  '2': [
    {'1': 'PRINTER_AGENT_LIFECYCLE_UNSPECIFIED', '2': 0},
    {'1': 'PRINTER_AGENT_NEW', '2': 1},
    {'1': 'PRINTER_AGENT_STARTING', '2': 2},
    {'1': 'PRINTER_AGENT_RUNNING', '2': 3},
    {'1': 'PRINTER_AGENT_DRAINING', '2': 4},
    {'1': 'PRINTER_AGENT_STOPPED', '2': 5},
    {'1': 'PRINTER_AGENT_HELD', '2': 6},
  ],
};

/// Descriptor for `PrinterAgentLifecycle`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List printerAgentLifecycleDescriptor = $convert.base64Decode(
    'ChVQcmludGVyQWdlbnRMaWZlY3ljbGUSJwojUFJJTlRFUl9BR0VOVF9MSUZFQ1lDTEVfVU5TUE'
    'VDSUZJRUQQABIVChFQUklOVEVSX0FHRU5UX05FVxABEhoKFlBSSU5URVJfQUdFTlRfU1RBUlRJ'
    'TkcQAhIZChVQUklOVEVSX0FHRU5UX1JVTk5JTkcQAxIaChZQUklOVEVSX0FHRU5UX0RSQUlOSU'
    '5HEAQSGQoVUFJJTlRFUl9BR0VOVF9TVE9QUEVEEAUSFgoSUFJJTlRFUl9BR0VOVF9IRUxEEAY=');

@$core.Deprecated('Use printerAgentPhysicalStateDescriptor instead')
const PrinterAgentPhysicalState$json = {
  '1': 'PrinterAgentPhysicalState',
  '2': [
    {'1': 'PRINTER_AGENT_PHYSICAL_UNSPECIFIED', '2': 0},
    {'1': 'PRINTER_AGENT_PHYSICAL_HELD', '2': 1},
  ],
};

/// Descriptor for `PrinterAgentPhysicalState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List printerAgentPhysicalStateDescriptor =
    $convert.base64Decode(
        'ChlQcmludGVyQWdlbnRQaHlzaWNhbFN0YXRlEiYKIlBSSU5URVJfQUdFTlRfUEhZU0lDQUxfVU'
        '5TUEVDSUZJRUQQABIfChtQUklOVEVSX0FHRU5UX1BIWVNJQ0FMX0hFTEQQAQ==');

@$core.Deprecated('Use printerAgentAdmissionStateDescriptor instead')
const PrinterAgentAdmissionState$json = {
  '1': 'PrinterAgentAdmissionState',
  '2': [
    {'1': 'PRINTER_AGENT_ADMISSION_UNSPECIFIED', '2': 0},
    {'1': 'PRINTER_AGENT_ADMISSION_HELD_PROVISIONING', '2': 1},
  ],
};

/// Descriptor for `PrinterAgentAdmissionState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List printerAgentAdmissionStateDescriptor =
    $convert.base64Decode(
        'ChpQcmludGVyQWdlbnRBZG1pc3Npb25TdGF0ZRInCiNQUklOVEVSX0FHRU5UX0FETUlTU0lPTl'
        '9VTlNQRUNJRklFRBAAEi0KKVBSSU5URVJfQUdFTlRfQURNSVNTSU9OX0hFTERfUFJPVklTSU9O'
        'SU5HEAE=');

@$core.Deprecated('Use printerAgentHoldReasonDescriptor instead')
const PrinterAgentHoldReason$json = {
  '1': 'PrinterAgentHoldReason',
  '2': [
    {'1': 'PRINTER_AGENT_HOLD_UNSPECIFIED', '2': 0},
    {'1': 'PRINTER_AGENT_PROVISIONING_UNQUALIFIED', '2': 1},
    {'1': 'PRINTER_AGENT_PHYSICAL_ACTIVATION_PENDING', '2': 2},
    {'1': 'PRINTER_AGENT_SHARED_FENCE_UNQUALIFIED', '2': 3},
    {'1': 'PRINTER_AGENT_HOST_UNAVAILABLE', '2': 4},
    {'1': 'PRINTER_AGENT_RETAINED_QUEUE_HOLD', '2': 5},
  ],
};

/// Descriptor for `PrinterAgentHoldReason`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List printerAgentHoldReasonDescriptor = $convert.base64Decode(
    'ChZQcmludGVyQWdlbnRIb2xkUmVhc29uEiIKHlBSSU5URVJfQUdFTlRfSE9MRF9VTlNQRUNJRk'
    'lFRBAAEioKJlBSSU5URVJfQUdFTlRfUFJPVklTSU9OSU5HX1VOUVVBTElGSUVEEAESLQopUFJJ'
    'TlRFUl9BR0VOVF9QSFlTSUNBTF9BQ1RJVkFUSU9OX1BFTkRJTkcQAhIqCiZQUklOVEVSX0FHRU'
    '5UX1NIQVJFRF9GRU5DRV9VTlFVQUxJRklFRBADEiIKHlBSSU5URVJfQUdFTlRfSE9TVF9VTkFW'
    'QUlMQUJMRRAEEiUKIVBSSU5URVJfQUdFTlRfUkVUQUlORURfUVVFVUVfSE9MRBAF');

@$core.Deprecated('Use printerAgentAuthDescriptor instead')
const PrinterAgentAuth$json = {
  '1': 'PrinterAgentAuth',
  '2': [
    {'1': 'host_id', '3': 1, '4': 1, '5': 9, '10': 'hostId'},
    {'1': 'client_id', '3': 2, '4': 1, '5': 9, '10': 'clientId'},
    {'1': 'protocol_major', '3': 3, '4': 1, '5': 13, '10': 'protocolMajor'},
    {'1': 'protocol_minor', '3': 4, '4': 1, '5': 13, '10': 'protocolMinor'},
    {'1': 'reader_version', '3': 5, '4': 1, '5': 13, '10': 'readerVersion'},
    {
      '1': 'required_capabilities',
      '3': 6,
      '4': 3,
      '5': 9,
      '10': 'requiredCapabilities'
    },
  ],
};

/// Descriptor for `PrinterAgentAuth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentAuthDescriptor = $convert.base64Decode(
    'ChBQcmludGVyQWdlbnRBdXRoEhcKB2hvc3RfaWQYASABKAlSBmhvc3RJZBIbCgljbGllbnRfaW'
    'QYAiABKAlSCGNsaWVudElkEiUKDnByb3RvY29sX21ham9yGAMgASgNUg1wcm90b2NvbE1ham9y'
    'EiUKDnByb3RvY29sX21pbm9yGAQgASgNUg1wcm90b2NvbE1pbm9yEiUKDnJlYWRlcl92ZXJzaW'
    '9uGAUgASgNUg1yZWFkZXJWZXJzaW9uEjMKFXJlcXVpcmVkX2NhcGFiaWxpdGllcxgGIAMoCVIU'
    'cmVxdWlyZWRDYXBhYmlsaXRpZXM=');

@$core.Deprecated('Use printerAgentPinsDescriptor instead')
const PrinterAgentPins$json = {
  '1': 'PrinterAgentPins',
  '2': [
    {'1': 'scope', '3': 1, '4': 1, '5': 9, '10': 'scope'},
    {'1': 'ownership_policy', '3': 2, '4': 1, '5': 9, '10': 'ownershipPolicy'},
    {'1': 'cluster_id', '3': 3, '4': 1, '5': 9, '10': 'clusterId'},
    {
      '1': 'membership_sha256',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'membershipSha256'
    },
    {'1': 'role', '3': 5, '4': 1, '5': 9, '10': 'role'},
    {'1': 'venue_id', '3': 6, '4': 1, '5': 9, '10': 'venueId'},
    {'1': 'installation_id', '3': 7, '4': 1, '5': 9, '10': 'installationId'},
    {'1': 'device_id', '3': 8, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'host_id', '3': 9, '4': 1, '5': 9, '10': 'hostId'},
    {'1': 'gateway_host_id', '3': 10, '4': 1, '5': 9, '10': 'gatewayHostId'},
    {'1': 'authority_epoch', '3': 11, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {
      '1': 'protocol_version',
      '3': 12,
      '4': 1,
      '5': 13,
      '10': 'protocolVersion'
    },
    {
      '1': 'helper_protocol_version',
      '3': 13,
      '4': 1,
      '5': 13,
      '10': 'helperProtocolVersion'
    },
    {
      '1': 'database_schema_version',
      '3': 14,
      '4': 1,
      '5': 13,
      '10': 'databaseSchemaVersion'
    },
    {
      '1': 'minimum_reader_version',
      '3': 15,
      '4': 1,
      '5': 13,
      '10': 'minimumReaderVersion'
    },
    {'1': 'route_revision', '3': 16, '4': 1, '5': 4, '10': 'routeRevision'},
    {'1': 'config_revision', '3': 17, '4': 1, '5': 4, '10': 'configRevision'},
    {
      '1': 'registry_revision',
      '3': 18,
      '4': 1,
      '5': 4,
      '10': 'registryRevision'
    },
    {'1': 'binding_revision', '3': 19, '4': 1, '5': 4, '10': 'bindingRevision'},
    {
      '1': 'capability_revision',
      '3': 20,
      '4': 1,
      '5': 4,
      '10': 'capabilityRevision'
    },
    {
      '1': 'capability_profile_sha256',
      '3': 21,
      '4': 1,
      '5': 9,
      '10': 'capabilityProfileSha256'
    },
    {
      '1': 'host_binary_sha256',
      '3': 22,
      '4': 1,
      '5': 9,
      '10': 'hostBinarySha256'
    },
    {
      '1': 'helper_binary_sha256',
      '3': 23,
      '4': 1,
      '5': 9,
      '10': 'helperBinarySha256'
    },
  ],
};

/// Descriptor for `PrinterAgentPins`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentPinsDescriptor = $convert.base64Decode(
    'ChBQcmludGVyQWdlbnRQaW5zEhQKBXNjb3BlGAEgASgJUgVzY29wZRIpChBvd25lcnNoaXBfcG'
    '9saWN5GAIgASgJUg9vd25lcnNoaXBQb2xpY3kSHQoKY2x1c3Rlcl9pZBgDIAEoCVIJY2x1c3Rl'
    'cklkEisKEW1lbWJlcnNoaXBfc2hhMjU2GAQgASgJUhBtZW1iZXJzaGlwU2hhMjU2EhIKBHJvbG'
    'UYBSABKAlSBHJvbGUSGQoIdmVudWVfaWQYBiABKAlSB3ZlbnVlSWQSJwoPaW5zdGFsbGF0aW9u'
    'X2lkGAcgASgJUg5pbnN0YWxsYXRpb25JZBIbCglkZXZpY2VfaWQYCCABKAlSCGRldmljZUlkEh'
    'cKB2hvc3RfaWQYCSABKAlSBmhvc3RJZBImCg9nYXRld2F5X2hvc3RfaWQYCiABKAlSDWdhdGV3'
    'YXlIb3N0SWQSJwoPYXV0aG9yaXR5X2Vwb2NoGAsgASgEUg5hdXRob3JpdHlFcG9jaBIpChBwcm'
    '90b2NvbF92ZXJzaW9uGAwgASgNUg9wcm90b2NvbFZlcnNpb24SNgoXaGVscGVyX3Byb3RvY29s'
    'X3ZlcnNpb24YDSABKA1SFWhlbHBlclByb3RvY29sVmVyc2lvbhI2ChdkYXRhYmFzZV9zY2hlbW'
    'FfdmVyc2lvbhgOIAEoDVIVZGF0YWJhc2VTY2hlbWFWZXJzaW9uEjQKFm1pbmltdW1fcmVhZGVy'
    'X3ZlcnNpb24YDyABKA1SFG1pbmltdW1SZWFkZXJWZXJzaW9uEiUKDnJvdXRlX3JldmlzaW9uGB'
    'AgASgEUg1yb3V0ZVJldmlzaW9uEicKD2NvbmZpZ19yZXZpc2lvbhgRIAEoBFIOY29uZmlnUmV2'
    'aXNpb24SKwoRcmVnaXN0cnlfcmV2aXNpb24YEiABKARSEHJlZ2lzdHJ5UmV2aXNpb24SKQoQYm'
    'luZGluZ19yZXZpc2lvbhgTIAEoBFIPYmluZGluZ1JldmlzaW9uEi8KE2NhcGFiaWxpdHlfcmV2'
    'aXNpb24YFCABKARSEmNhcGFiaWxpdHlSZXZpc2lvbhI6ChljYXBhYmlsaXR5X3Byb2ZpbGVfc2'
    'hhMjU2GBUgASgJUhdjYXBhYmlsaXR5UHJvZmlsZVNoYTI1NhIsChJob3N0X2JpbmFyeV9zaGEy'
    'NTYYFiABKAlSEGhvc3RCaW5hcnlTaGEyNTYSMAoUaGVscGVyX2JpbmFyeV9zaGEyNTYYFyABKA'
    'lSEmhlbHBlckJpbmFyeVNoYTI1Ng==');

@$core.Deprecated('Use printerAgentHealthRequestDescriptor instead')
const PrinterAgentHealthRequest$json = {
  '1': 'PrinterAgentHealthRequest',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.PrinterAgentAuth',
      '10': 'auth'
    },
  ],
};

/// Descriptor for `PrinterAgentHealthRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentHealthRequestDescriptor =
    $convert.base64Decode(
        'ChlQcmludGVyQWdlbnRIZWFsdGhSZXF1ZXN0EjMKBGF1dGgYASABKAsyHy52eW5pYy5lZGdlLn'
        'YxLlByaW50ZXJBZ2VudEF1dGhSBGF1dGg=');

@$core.Deprecated('Use printerAgentPrinterHoldDescriptor instead')
const PrinterAgentPrinterHold$json = {
  '1': 'PrinterAgentPrinterHold',
  '2': [
    {
      '1': 'physical_printer_id',
      '3': 1,
      '4': 1,
      '5': 9,
      '10': 'physicalPrinterId'
    },
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `PrinterAgentPrinterHold`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentPrinterHoldDescriptor =
    $convert.base64Decode(
        'ChdQcmludGVyQWdlbnRQcmludGVySG9sZBIuChNwaHlzaWNhbF9wcmludGVyX2lkGAEgASgJUh'
        'FwaHlzaWNhbFByaW50ZXJJZBIWCgZyZWFzb24YAiABKAlSBnJlYXNvbg==');

@$core.Deprecated('Use printerAgentHealthResponseDescriptor instead')
const PrinterAgentHealthResponse$json = {
  '1': 'PrinterAgentHealthResponse',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {
      '1': 'pins',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.PrinterAgentPins',
      '10': 'pins'
    },
    {'1': 'client_id', '3': 3, '4': 1, '5': 9, '10': 'clientId'},
    {
      '1': 'state',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.PrinterAgentLifecycle',
      '10': 'state'
    },
    {'1': 'software_ready', '3': 5, '4': 1, '5': 8, '10': 'softwareReady'},
    {
      '1': 'physical_state',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.PrinterAgentPhysicalState',
      '10': 'physicalState'
    },
    {
      '1': 'admission_state',
      '3': 7,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.PrinterAgentAdmissionState',
      '10': 'admissionState'
    },
    {
      '1': 'hold_reasons',
      '3': 8,
      '4': 3,
      '5': 14,
      '6': '.vynic.edge.v1.PrinterAgentHoldReason',
      '10': 'holdReasons'
    },
    {
      '1': 'printer_holds',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.PrinterAgentPrinterHold',
      '10': 'printerHolds'
    },
    {
      '1': 'active_admissions',
      '3': 10,
      '4': 1,
      '5': 4,
      '10': 'activeAdmissions'
    },
  ],
};

/// Descriptor for `PrinterAgentHealthResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentHealthResponseDescriptor = $convert.base64Decode(
    'ChpQcmludGVyQWdlbnRIZWFsdGhSZXNwb25zZRIpChBwcm90b2NvbF92ZXJzaW9uGAEgASgNUg'
    '9wcm90b2NvbFZlcnNpb24SMwoEcGlucxgCIAEoCzIfLnZ5bmljLmVkZ2UudjEuUHJpbnRlckFn'
    'ZW50UGluc1IEcGlucxIbCgljbGllbnRfaWQYAyABKAlSCGNsaWVudElkEjoKBXN0YXRlGAQgAS'
    'gOMiQudnluaWMuZWRnZS52MS5QcmludGVyQWdlbnRMaWZlY3ljbGVSBXN0YXRlEiUKDnNvZnR3'
    'YXJlX3JlYWR5GAUgASgIUg1zb2Z0d2FyZVJlYWR5Ek8KDnBoeXNpY2FsX3N0YXRlGAYgASgOMi'
    'gudnluaWMuZWRnZS52MS5QcmludGVyQWdlbnRQaHlzaWNhbFN0YXRlUg1waHlzaWNhbFN0YXRl'
    'ElIKD2FkbWlzc2lvbl9zdGF0ZRgHIAEoDjIpLnZ5bmljLmVkZ2UudjEuUHJpbnRlckFnZW50QW'
    'RtaXNzaW9uU3RhdGVSDmFkbWlzc2lvblN0YXRlEkgKDGhvbGRfcmVhc29ucxgIIAMoDjIlLnZ5'
    'bmljLmVkZ2UudjEuUHJpbnRlckFnZW50SG9sZFJlYXNvblILaG9sZFJlYXNvbnMSSwoNcHJpbn'
    'Rlcl9ob2xkcxgJIAMoCzImLnZ5bmljLmVkZ2UudjEuUHJpbnRlckFnZW50UHJpbnRlckhvbGRS'
    'DHByaW50ZXJIb2xkcxIrChFhY3RpdmVfYWRtaXNzaW9ucxgKIAEoBFIQYWN0aXZlQWRtaXNzaW'
    '9ucw==');

@$core.Deprecated('Use printerAgentSubmitLocalRequestDescriptor instead')
const PrinterAgentSubmitLocalRequest$json = {
  '1': 'PrinterAgentSubmitLocalRequest',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.PrinterAgentAuth',
      '10': 'auth'
    },
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'job_id', '3': 3, '4': 1, '5': 9, '10': 'jobId'},
    {'1': 'frozen_envelope', '3': 4, '4': 1, '5': 12, '10': 'frozenEnvelope'},
    {'1': 'envelope_sha256', '3': 5, '4': 1, '5': 9, '10': 'envelopeSha256'},
  ],
};

/// Descriptor for `PrinterAgentSubmitLocalRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentSubmitLocalRequestDescriptor = $convert.base64Decode(
    'Ch5QcmludGVyQWdlbnRTdWJtaXRMb2NhbFJlcXVlc3QSMwoEYXV0aBgBIAEoCzIfLnZ5bmljLm'
    'VkZ2UudjEuUHJpbnRlckFnZW50QXV0aFIEYXV0aBIdCgpyZXF1ZXN0X2lkGAIgASgJUglyZXF1'
    'ZXN0SWQSFQoGam9iX2lkGAMgASgJUgVqb2JJZBInCg9mcm96ZW5fZW52ZWxvcGUYBCABKAxSDm'
    'Zyb3plbkVudmVsb3BlEicKD2VudmVsb3BlX3NoYTI1NhgFIAEoCVIOZW52ZWxvcGVTaGEyNTY=');

@$core.Deprecated('Use printerAgentGetLocalResultRequestDescriptor instead')
const PrinterAgentGetLocalResultRequest$json = {
  '1': 'PrinterAgentGetLocalResultRequest',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.PrinterAgentAuth',
      '10': 'auth'
    },
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'job_id', '3': 3, '4': 1, '5': 9, '10': 'jobId'},
    {'1': 'envelope_sha256', '3': 4, '4': 1, '5': 9, '10': 'envelopeSha256'},
  ],
};

/// Descriptor for `PrinterAgentGetLocalResultRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentGetLocalResultRequestDescriptor =
    $convert.base64Decode(
        'CiFQcmludGVyQWdlbnRHZXRMb2NhbFJlc3VsdFJlcXVlc3QSMwoEYXV0aBgBIAEoCzIfLnZ5bm'
        'ljLmVkZ2UudjEuUHJpbnRlckFnZW50QXV0aFIEYXV0aBIdCgpyZXF1ZXN0X2lkGAIgASgJUgly'
        'ZXF1ZXN0SWQSFQoGam9iX2lkGAMgASgJUgVqb2JJZBInCg9lbnZlbG9wZV9zaGEyNTYYBCABKA'
        'lSDmVudmVsb3BlU2hhMjU2');

@$core.Deprecated('Use printerAgentSubmissionResultDescriptor instead')
const PrinterAgentSubmissionResult$json = {
  '1': 'PrinterAgentSubmissionResult',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'job_id', '3': 2, '4': 1, '5': 9, '10': 'jobId'},
    {'1': 'envelope_sha256', '3': 3, '4': 1, '5': 9, '10': 'envelopeSha256'},
  ],
};

/// Descriptor for `PrinterAgentSubmissionResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List printerAgentSubmissionResultDescriptor =
    $convert.base64Decode(
        'ChxQcmludGVyQWdlbnRTdWJtaXNzaW9uUmVzdWx0Eh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcX'
        'Vlc3RJZBIVCgZqb2JfaWQYAiABKAlSBWpvYklkEicKD2VudmVsb3BlX3NoYTI1NhgDIAEoCVIO'
        'ZW52ZWxvcGVTaGEyNTY=');
