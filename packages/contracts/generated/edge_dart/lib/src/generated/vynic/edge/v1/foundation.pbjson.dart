// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/foundation.proto.

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

@$core.Deprecated('Use protocolDescriptor instead')
const Protocol$json = {
  '1': 'Protocol',
  '2': [
    {'1': 'major', '3': 1, '4': 1, '5': 13, '10': 'major'},
    {'1': 'minor', '3': 2, '4': 1, '5': 13, '10': 'minor'},
    {
      '1': 'required_capabilities',
      '3': 3,
      '4': 3,
      '5': 9,
      '10': 'requiredCapabilities'
    },
  ],
};

/// Descriptor for `Protocol`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List protocolDescriptor = $convert.base64Decode(
    'CghQcm90b2NvbBIUCgVtYWpvchgBIAEoDVIFbWFqb3ISFAoFbWlub3IYAiABKA1SBW1pbm9yEj'
    'MKFXJlcXVpcmVkX2NhcGFiaWxpdGllcxgDIAMoCVIUcmVxdWlyZWRDYXBhYmlsaXRpZXM=');

@$core.Deprecated('Use scopeDescriptor instead')
const Scope$json = {
  '1': 'Scope',
  '2': [
    {'1': 'venue_id', '3': 1, '4': 1, '5': 9, '10': 'venueId'},
    {'1': 'installation_id', '3': 2, '4': 1, '5': 9, '10': 'installationId'},
    {
      '1': 'protocol',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.Protocol',
      '10': 'protocol'
    },
  ],
};

/// Descriptor for `Scope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List scopeDescriptor = $convert.base64Decode(
    'CgVTY29wZRIZCgh2ZW51ZV9pZBgBIAEoCVIHdmVudWVJZBInCg9pbnN0YWxsYXRpb25faWQYAi'
    'ABKAlSDmluc3RhbGxhdGlvbklkEjMKCHByb3RvY29sGAMgASgLMhcudnluaWMuZWRnZS52MS5Q'
    'cm90b2NvbFIIcHJvdG9jb2w=');

@$core.Deprecated('Use pairRequestDescriptor instead')
const PairRequest$json = {
  '1': 'PairRequest',
  '2': [
    {
      '1': 'scope',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.Scope',
      '10': 'scope'
    },
    {'1': 'ticket', '3': 2, '4': 1, '5': 9, '10': 'ticket'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'terminal_id', '3': 4, '4': 1, '5': 9, '10': 'terminalId'},
    {'1': 'terminal_secret', '3': 5, '4': 1, '5': 9, '10': 'terminalSecret'},
    {'1': 'display_name', '3': 6, '4': 1, '5': 9, '10': 'displayName'},
  ],
};

/// Descriptor for `PairRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairRequestDescriptor = $convert.base64Decode(
    'CgtQYWlyUmVxdWVzdBIqCgVzY29wZRgBIAEoCzIULnZ5bmljLmVkZ2UudjEuU2NvcGVSBXNjb3'
    'BlEhYKBnRpY2tldBgCIAEoCVIGdGlja2V0Eh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJ'
    'ZBIfCgt0ZXJtaW5hbF9pZBgEIAEoCVIKdGVybWluYWxJZBInCg90ZXJtaW5hbF9zZWNyZXQYBS'
    'ABKAlSDnRlcm1pbmFsU2VjcmV0EiEKDGRpc3BsYXlfbmFtZRgGIAEoCVILZGlzcGxheU5hbWU=');

@$core.Deprecated('Use pairResponseDescriptor instead')
const PairResponse$json = {
  '1': 'PairResponse',
  '2': [
    {'1': 'terminal_id', '3': 1, '4': 1, '5': 9, '10': 'terminalId'},
    {'1': 'installation_id', '3': 2, '4': 1, '5': 9, '10': 'installationId'},
    {'1': 'venue_id', '3': 3, '4': 1, '5': 9, '10': 'venueId'},
  ],
};

/// Descriptor for `PairResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairResponseDescriptor = $convert.base64Decode(
    'CgxQYWlyUmVzcG9uc2USHwoLdGVybWluYWxfaWQYASABKAlSCnRlcm1pbmFsSWQSJwoPaW5zdG'
    'FsbGF0aW9uX2lkGAIgASgJUg5pbnN0YWxsYXRpb25JZBIZCgh2ZW51ZV9pZBgDIAEoCVIHdmVu'
    'dWVJZA==');

@$core.Deprecated('Use authenticatedRequestDescriptor instead')
const AuthenticatedRequest$json = {
  '1': 'AuthenticatedRequest',
  '2': [
    {
      '1': 'scope',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.Scope',
      '10': 'scope'
    },
    {'1': 'terminal_id', '3': 2, '4': 1, '5': 9, '10': 'terminalId'},
    {'1': 'terminal_secret', '3': 3, '4': 1, '5': 9, '10': 'terminalSecret'},
  ],
};

/// Descriptor for `AuthenticatedRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authenticatedRequestDescriptor = $convert.base64Decode(
    'ChRBdXRoZW50aWNhdGVkUmVxdWVzdBIqCgVzY29wZRgBIAEoCzIULnZ5bmljLmVkZ2UudjEuU2'
    'NvcGVSBXNjb3BlEh8KC3Rlcm1pbmFsX2lkGAIgASgJUgp0ZXJtaW5hbElkEicKD3Rlcm1pbmFs'
    'X3NlY3JldBgDIAEoCVIOdGVybWluYWxTZWNyZXQ=');

@$core.Deprecated('Use handshakeRequestDescriptor instead')
const HandshakeRequest$json = {
  '1': 'HandshakeRequest',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.AuthenticatedRequest',
      '10': 'auth'
    },
    {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'client_version', '3': 3, '4': 1, '5': 9, '10': 'clientVersion'},
  ],
};

/// Descriptor for `HandshakeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List handshakeRequestDescriptor = $convert.base64Decode(
    'ChBIYW5kc2hha2VSZXF1ZXN0EjcKBGF1dGgYASABKAsyIy52eW5pYy5lZGdlLnYxLkF1dGhlbn'
    'RpY2F0ZWRSZXF1ZXN0UgRhdXRoEh0KCnNlc3Npb25faWQYAiABKAlSCXNlc3Npb25JZBIlCg5j'
    'bGllbnRfdmVyc2lvbhgDIAEoCVINY2xpZW50VmVyc2lvbg==');

@$core.Deprecated('Use statusResponseDescriptor instead')
const StatusResponse$json = {
  '1': 'StatusResponse',
  '2': [
    {'1': 'installation_id', '3': 1, '4': 1, '5': 9, '10': 'installationId'},
    {'1': 'venue_id', '3': 2, '4': 1, '5': 9, '10': 'venueId'},
    {
      '1': 'protocol',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.Protocol',
      '10': 'protocol'
    },
    {'1': 'mode', '3': 4, '4': 1, '5': 9, '10': 'mode'},
    {
      '1': 'business_mutations_enabled',
      '3': 5,
      '4': 1,
      '5': 8,
      '10': 'businessMutationsEnabled'
    },
    {'1': 'schema_version', '3': 6, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'boot_id', '3': 7, '4': 1, '5': 9, '10': 'bootId'},
    {'1': 'terminal_id', '3': 8, '4': 1, '5': 9, '10': 'terminalId'},
    {'1': 'session_id', '3': 9, '4': 1, '5': 9, '10': 'sessionId'},
    {
      '1': 'connected_streams',
      '3': 10,
      '4': 1,
      '5': 13,
      '10': 'connectedStreams'
    },
    {'1': 'capabilities', '3': 11, '4': 3, '5': 9, '10': 'capabilities'},
  ],
};

/// Descriptor for `StatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusResponseDescriptor = $convert.base64Decode(
    'Cg5TdGF0dXNSZXNwb25zZRInCg9pbnN0YWxsYXRpb25faWQYASABKAlSDmluc3RhbGxhdGlvbk'
    'lkEhkKCHZlbnVlX2lkGAIgASgJUgd2ZW51ZUlkEjMKCHByb3RvY29sGAMgASgLMhcudnluaWMu'
    'ZWRnZS52MS5Qcm90b2NvbFIIcHJvdG9jb2wSEgoEbW9kZRgEIAEoCVIEbW9kZRI8ChpidXNpbm'
    'Vzc19tdXRhdGlvbnNfZW5hYmxlZBgFIAEoCFIYYnVzaW5lc3NNdXRhdGlvbnNFbmFibGVkEiUK'
    'DnNjaGVtYV92ZXJzaW9uGAYgASgNUg1zY2hlbWFWZXJzaW9uEhcKB2Jvb3RfaWQYByABKAlSBm'
    'Jvb3RJZBIfCgt0ZXJtaW5hbF9pZBgIIAEoCVIKdGVybWluYWxJZBIdCgpzZXNzaW9uX2lkGAkg'
    'ASgJUglzZXNzaW9uSWQSKwoRY29ubmVjdGVkX3N0cmVhbXMYCiABKA1SEGNvbm5lY3RlZFN0cm'
    'VhbXMSIgoMY2FwYWJpbGl0aWVzGAsgAygJUgxjYXBhYmlsaXRpZXM=');
