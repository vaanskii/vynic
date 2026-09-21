// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/orders_tables.proto.

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

@$core.Deprecated('Use projectionEntityDescriptor instead')
const ProjectionEntity$json = {
  '1': 'ProjectionEntity',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.ProjectionEntity.Kind',
      '10': 'kind'
    },
    {'1': 'id', '3': 2, '4': 1, '5': 9, '10': 'id'},
    {'1': 'revision', '3': 3, '4': 1, '5': 4, '10': 'revision'},
    {'1': 'tombstone', '3': 4, '4': 1, '5': 8, '10': 'tombstone'},
    {'1': 'document', '3': 5, '4': 1, '5': 12, '10': 'document'},
  ],
  '4': [ProjectionEntity_Kind$json],
};

@$core.Deprecated('Use projectionEntityDescriptor instead')
const ProjectionEntity_Kind$json = {
  '1': 'Kind',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'ORDER', '2': 1},
    {'1': 'TABLE', '2': 2},
  ],
};

/// Descriptor for `ProjectionEntity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List projectionEntityDescriptor = $convert.base64Decode(
    'ChBQcm9qZWN0aW9uRW50aXR5EjgKBGtpbmQYASABKA4yJC52eW5pYy5lZGdlLnYxLlByb2plY3'
    'Rpb25FbnRpdHkuS2luZFIEa2luZBIOCgJpZBgCIAEoCVICaWQSGgoIcmV2aXNpb24YAyABKARS'
    'CHJldmlzaW9uEhwKCXRvbWJzdG9uZRgEIAEoCFIJdG9tYnN0b25lEhoKCGRvY3VtZW50GAUgAS'
    'gMUghkb2N1bWVudCItCgRLaW5kEg8KC1VOU1BFQ0lGSUVEEAASCQoFT1JERVIQARIJCgVUQUJM'
    'RRAC');

@$core.Deprecated('Use entityChangeDescriptor instead')
const EntityChange$json = {
  '1': 'EntityChange',
  '2': [
    {
      '1': 'entity',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.ProjectionEntity',
      '10': 'entity'
    },
    {
      '1': 'expected_revision',
      '3': 2,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
  ],
};

/// Descriptor for `EntityChange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List entityChangeDescriptor = $convert.base64Decode(
    'CgxFbnRpdHlDaGFuZ2USNwoGZW50aXR5GAEgASgLMh8udnluaWMuZWRnZS52MS5Qcm9qZWN0aW'
    '9uRW50aXR5UgZlbnRpdHkSKwoRZXhwZWN0ZWRfcmV2aXNpb24YAiABKARSEGV4cGVjdGVkUmV2'
    'aXNpb24=');

@$core.Deprecated('Use commitIntentDescriptor instead')
const CommitIntent$json = {
  '1': 'CommitIntent',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.AuthenticatedRequest',
      '10': 'auth'
    },
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'authority_epoch', '3': 3, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {
      '1': 'changes',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.EntityChange',
      '10': 'changes'
    },
  ],
};

/// Descriptor for `CommitIntent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitIntentDescriptor = $convert.base64Decode(
    'CgxDb21taXRJbnRlbnQSNwoEYXV0aBgBIAEoCzIjLnZ5bmljLmVkZ2UudjEuQXV0aGVudGljYX'
    'RlZFJlcXVlc3RSBGF1dGgSHQoKcmVxdWVzdF9pZBgCIAEoCVIJcmVxdWVzdElkEicKD2F1dGhv'
    'cml0eV9lcG9jaBgDIAEoBFIOYXV0aG9yaXR5RXBvY2gSNQoHY2hhbmdlcxgEIAMoCzIbLnZ5bm'
    'ljLmVkZ2UudjEuRW50aXR5Q2hhbmdlUgdjaGFuZ2Vz');

@$core.Deprecated('Use committedEventDescriptor instead')
const CommittedEvent$json = {
  '1': 'CommittedEvent',
  '2': [
    {'1': 'sequence', '3': 1, '4': 1, '5': 4, '10': 'sequence'},
    {'1': 'authority_epoch', '3': 2, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'terminal_id', '3': 4, '4': 1, '5': 9, '10': 'terminalId'},
    {
      '1': 'entities',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProjectionEntity',
      '10': 'entities'
    },
  ],
};

/// Descriptor for `CommittedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List committedEventDescriptor = $convert.base64Decode(
    'Cg5Db21taXR0ZWRFdmVudBIaCghzZXF1ZW5jZRgBIAEoBFIIc2VxdWVuY2USJwoPYXV0aG9yaX'
    'R5X2Vwb2NoGAIgASgEUg5hdXRob3JpdHlFcG9jaBIdCgpyZXF1ZXN0X2lkGAMgASgJUglyZXF1'
    'ZXN0SWQSHwoLdGVybWluYWxfaWQYBCABKAlSCnRlcm1pbmFsSWQSOwoIZW50aXRpZXMYBSADKA'
    'syHy52eW5pYy5lZGdlLnYxLlByb2plY3Rpb25FbnRpdHlSCGVudGl0aWVz');

@$core.Deprecated('Use commitResultDescriptor instead')
const CommitResult$json = {
  '1': 'CommitResult',
  '2': [
    {
      '1': 'outcome',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.CommitResult.Outcome',
      '10': 'outcome'
    },
    {
      '1': 'event',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.CommittedEvent',
      '10': 'event'
    },
    {
      '1': 'current',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProjectionEntity',
      '10': 'current'
    },
    {'1': 'authority_epoch', '3': 4, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'head_sequence', '3': 5, '4': 1, '5': 4, '10': 'headSequence'},
  ],
  '4': [CommitResult_Outcome$json],
};

@$core.Deprecated('Use commitResultDescriptor instead')
const CommitResult_Outcome$json = {
  '1': 'Outcome',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'COMMITTED', '2': 1},
    {'1': 'CONFLICT', '2': 2},
  ],
};

/// Descriptor for `CommitResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitResultDescriptor = $convert.base64Decode(
    'CgxDb21taXRSZXN1bHQSPQoHb3V0Y29tZRgBIAEoDjIjLnZ5bmljLmVkZ2UudjEuQ29tbWl0Um'
    'VzdWx0Lk91dGNvbWVSB291dGNvbWUSMwoFZXZlbnQYAiABKAsyHS52eW5pYy5lZGdlLnYxLkNv'
    'bW1pdHRlZEV2ZW50UgVldmVudBI5CgdjdXJyZW50GAMgAygLMh8udnluaWMuZWRnZS52MS5Qcm'
    '9qZWN0aW9uRW50aXR5UgdjdXJyZW50EicKD2F1dGhvcml0eV9lcG9jaBgEIAEoBFIOYXV0aG9y'
    'aXR5RXBvY2gSIwoNaGVhZF9zZXF1ZW5jZRgFIAEoBFIMaGVhZFNlcXVlbmNlIjcKB091dGNvbW'
    'USDwoLVU5TUEVDSUZJRUQQABINCglDT01NSVRURUQQARIMCghDT05GTElDVBAC');

@$core.Deprecated('Use replayRequestDescriptor instead')
const ReplayRequest$json = {
  '1': 'ReplayRequest',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.AuthenticatedRequest',
      '10': 'auth'
    },
    {'1': 'authority_epoch', '3': 2, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'after_sequence', '3': 3, '4': 1, '5': 4, '10': 'afterSequence'},
    {'1': 'limit', '3': 4, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `ReplayRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List replayRequestDescriptor = $convert.base64Decode(
    'Cg1SZXBsYXlSZXF1ZXN0EjcKBGF1dGgYASABKAsyIy52eW5pYy5lZGdlLnYxLkF1dGhlbnRpY2'
    'F0ZWRSZXF1ZXN0UgRhdXRoEicKD2F1dGhvcml0eV9lcG9jaBgCIAEoBFIOYXV0aG9yaXR5RXBv'
    'Y2gSJQoOYWZ0ZXJfc2VxdWVuY2UYAyABKARSDWFmdGVyU2VxdWVuY2USFAoFbGltaXQYBCABKA'
    '1SBWxpbWl0');

@$core.Deprecated('Use replayPageDescriptor instead')
const ReplayPage$json = {
  '1': 'ReplayPage',
  '2': [
    {
      '1': 'events',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.CommittedEvent',
      '10': 'events'
    },
    {'1': 'head_sequence', '3': 2, '4': 1, '5': 4, '10': 'headSequence'},
    {'1': 'authority_epoch', '3': 3, '4': 1, '5': 4, '10': 'authorityEpoch'},
  ],
};

/// Descriptor for `ReplayPage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List replayPageDescriptor = $convert.base64Decode(
    'CgpSZXBsYXlQYWdlEjUKBmV2ZW50cxgBIAMoCzIdLnZ5bmljLmVkZ2UudjEuQ29tbWl0dGVkRX'
    'ZlbnRSBmV2ZW50cxIjCg1oZWFkX3NlcXVlbmNlGAIgASgEUgxoZWFkU2VxdWVuY2USJwoPYXV0'
    'aG9yaXR5X2Vwb2NoGAMgASgEUg5hdXRob3JpdHlFcG9jaA==');

@$core.Deprecated('Use snapshotRequestDescriptor instead')
const SnapshotRequest$json = {
  '1': 'SnapshotRequest',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.AuthenticatedRequest',
      '10': 'auth'
    },
    {'1': 'authority_epoch', '3': 2, '4': 1, '5': 4, '10': 'authorityEpoch'},
  ],
};

/// Descriptor for `SnapshotRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List snapshotRequestDescriptor = $convert.base64Decode(
    'Cg9TbmFwc2hvdFJlcXVlc3QSNwoEYXV0aBgBIAEoCzIjLnZ5bmljLmVkZ2UudjEuQXV0aGVudG'
    'ljYXRlZFJlcXVlc3RSBGF1dGgSJwoPYXV0aG9yaXR5X2Vwb2NoGAIgASgEUg5hdXRob3JpdHlF'
    'cG9jaA==');

@$core.Deprecated('Use projectionSnapshotDescriptor instead')
const ProjectionSnapshot$json = {
  '1': 'ProjectionSnapshot',
  '2': [
    {
      '1': 'entities',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProjectionEntity',
      '10': 'entities'
    },
    {'1': 'sequence', '3': 2, '4': 1, '5': 4, '10': 'sequence'},
    {'1': 'authority_epoch', '3': 3, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'mode', '3': 4, '4': 1, '5': 9, '10': 'mode'},
  ],
};

/// Descriptor for `ProjectionSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List projectionSnapshotDescriptor = $convert.base64Decode(
    'ChJQcm9qZWN0aW9uU25hcHNob3QSOwoIZW50aXRpZXMYASADKAsyHy52eW5pYy5lZGdlLnYxLl'
    'Byb2plY3Rpb25FbnRpdHlSCGVudGl0aWVzEhoKCHNlcXVlbmNlGAIgASgEUghzZXF1ZW5jZRIn'
    'Cg9hdXRob3JpdHlfZXBvY2gYAyABKARSDmF1dGhvcml0eUVwb2NoEhIKBG1vZGUYBCABKAlSBG'
    '1vZGU=');
