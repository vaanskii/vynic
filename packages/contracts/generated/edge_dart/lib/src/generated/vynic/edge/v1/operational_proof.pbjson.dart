// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/operational_proof.proto.

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

@$core.Deprecated('Use proofLimitsDescriptor instead')
const ProofLimits$json = {
  '1': 'ProofLimits',
  '2': [
    {
      '1': 'max_request_bytes',
      '3': 1,
      '4': 1,
      '5': 13,
      '10': 'maxRequestBytes'
    },
    {
      '1': 'max_document_bytes',
      '3': 2,
      '4': 1,
      '5': 13,
      '10': 'maxDocumentBytes'
    },
    {'1': 'max_effect_bytes', '3': 3, '4': 1, '5': 13, '10': 'maxEffectBytes'},
    {
      '1': 'max_application_bytes',
      '3': 4,
      '4': 1,
      '5': 13,
      '10': 'maxApplicationBytes'
    },
    {'1': 'max_result_bytes', '3': 5, '4': 1, '5': 13, '10': 'maxResultBytes'},
    {
      '1': 'max_snapshot_bytes',
      '3': 6,
      '4': 1,
      '5': 13,
      '10': 'maxSnapshotBytes'
    },
    {'1': 'max_replay_bytes', '3': 7, '4': 1, '5': 13, '10': 'maxReplayBytes'},
    {'1': 'max_writes', '3': 8, '4': 1, '5': 13, '10': 'maxWrites'},
    {'1': 'max_reads', '3': 9, '4': 1, '5': 13, '10': 'maxReads'},
    {
      '1': 'max_request_effects',
      '3': 10,
      '4': 1,
      '5': 13,
      '10': 'maxRequestEffects'
    },
    {
      '1': 'max_replay_events',
      '3': 11,
      '4': 1,
      '5': 13,
      '10': 'maxReplayEvents'
    },
    {'1': 'max_entities', '3': 12, '4': 1, '5': 13, '10': 'maxEntities'},
    {
      '1': 'max_retained_requests',
      '3': 13,
      '4': 1,
      '5': 13,
      '10': 'maxRetainedRequests'
    },
    {
      '1': 'max_retained_events',
      '3': 14,
      '4': 1,
      '5': 13,
      '10': 'maxRetainedEvents'
    },
    {
      '1': 'max_retained_effects',
      '3': 15,
      '4': 1,
      '5': 13,
      '10': 'maxRetainedEffects'
    },
    {'1': 'max_event_bytes', '3': 16, '4': 1, '5': 13, '10': 'maxEventBytes'},
    {'1': 'max_state_bytes', '3': 17, '4': 1, '5': 13, '10': 'maxStateBytes'},
    {
      '1': 'max_journal_bytes',
      '3': 18,
      '4': 1,
      '5': 13,
      '10': 'maxJournalBytes'
    },
  ],
};

/// Descriptor for `ProofLimits`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofLimitsDescriptor = $convert.base64Decode(
    'CgtQcm9vZkxpbWl0cxIqChFtYXhfcmVxdWVzdF9ieXRlcxgBIAEoDVIPbWF4UmVxdWVzdEJ5dG'
    'VzEiwKEm1heF9kb2N1bWVudF9ieXRlcxgCIAEoDVIQbWF4RG9jdW1lbnRCeXRlcxIoChBtYXhf'
    'ZWZmZWN0X2J5dGVzGAMgASgNUg5tYXhFZmZlY3RCeXRlcxIyChVtYXhfYXBwbGljYXRpb25fYn'
    'l0ZXMYBCABKA1SE21heEFwcGxpY2F0aW9uQnl0ZXMSKAoQbWF4X3Jlc3VsdF9ieXRlcxgFIAEo'
    'DVIObWF4UmVzdWx0Qnl0ZXMSLAoSbWF4X3NuYXBzaG90X2J5dGVzGAYgASgNUhBtYXhTbmFwc2'
    'hvdEJ5dGVzEigKEG1heF9yZXBsYXlfYnl0ZXMYByABKA1SDm1heFJlcGxheUJ5dGVzEh0KCm1h'
    'eF93cml0ZXMYCCABKA1SCW1heFdyaXRlcxIbCgltYXhfcmVhZHMYCSABKA1SCG1heFJlYWRzEi'
    '4KE21heF9yZXF1ZXN0X2VmZmVjdHMYCiABKA1SEW1heFJlcXVlc3RFZmZlY3RzEioKEW1heF9y'
    'ZXBsYXlfZXZlbnRzGAsgASgNUg9tYXhSZXBsYXlFdmVudHMSIQoMbWF4X2VudGl0aWVzGAwgAS'
    'gNUgttYXhFbnRpdGllcxIyChVtYXhfcmV0YWluZWRfcmVxdWVzdHMYDSABKA1SE21heFJldGFp'
    'bmVkUmVxdWVzdHMSLgoTbWF4X3JldGFpbmVkX2V2ZW50cxgOIAEoDVIRbWF4UmV0YWluZWRFdm'
    'VudHMSMAoUbWF4X3JldGFpbmVkX2VmZmVjdHMYDyABKA1SEm1heFJldGFpbmVkRWZmZWN0cxIm'
    'Cg9tYXhfZXZlbnRfYnl0ZXMYECABKA1SDW1heEV2ZW50Qnl0ZXMSJgoPbWF4X3N0YXRlX2J5dG'
    'VzGBEgASgNUg1tYXhTdGF0ZUJ5dGVzEioKEW1heF9qb3VybmFsX2J5dGVzGBIgASgNUg9tYXhK'
    'b3VybmFsQnl0ZXM=');

@$core.Deprecated('Use proofStatusDescriptor instead')
const ProofStatus$json = {
  '1': 'ProofStatus',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 9, '10': 'mode'},
    {'1': 'venue_id', '3': 2, '4': 1, '5': 9, '10': 'venueId'},
    {'1': 'installation_id', '3': 3, '4': 1, '5': 9, '10': 'installationId'},
    {'1': 'authority_epoch', '3': 4, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'head_sequence', '3': 5, '4': 1, '5': 4, '10': 'headSequence'},
    {'1': 'grant_sha256', '3': 6, '4': 1, '5': 12, '10': 'grantSha256'},
    {
      '1': 'protocol',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.Protocol',
      '10': 'protocol'
    },
    {'1': 'capabilities', '3': 8, '4': 3, '5': 9, '10': 'capabilities'},
    {
      '1': 'limits',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.ProofLimits',
      '10': 'limits'
    },
    {
      '1': 'origin_installation_id',
      '3': 10,
      '4': 1,
      '5': 9,
      '10': 'originInstallationId'
    },
  ],
};

/// Descriptor for `ProofStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofStatusDescriptor = $convert.base64Decode(
    'CgtQcm9vZlN0YXR1cxISCgRtb2RlGAEgASgJUgRtb2RlEhkKCHZlbnVlX2lkGAIgASgJUgd2ZW'
    '51ZUlkEicKD2luc3RhbGxhdGlvbl9pZBgDIAEoCVIOaW5zdGFsbGF0aW9uSWQSJwoPYXV0aG9y'
    'aXR5X2Vwb2NoGAQgASgEUg5hdXRob3JpdHlFcG9jaBIjCg1oZWFkX3NlcXVlbmNlGAUgASgEUg'
    'xoZWFkU2VxdWVuY2USIQoMZ3JhbnRfc2hhMjU2GAYgASgMUgtncmFudFNoYTI1NhIzCghwcm90'
    'b2NvbBgHIAEoCzIXLnZ5bmljLmVkZ2UudjEuUHJvdG9jb2xSCHByb3RvY29sEiIKDGNhcGFiaW'
    'xpdGllcxgIIAMoCVIMY2FwYWJpbGl0aWVzEjIKBmxpbWl0cxgJIAEoCzIaLnZ5bmljLmVkZ2Uu'
    'djEuUHJvb2ZMaW1pdHNSBmxpbWl0cxI0ChZvcmlnaW5faW5zdGFsbGF0aW9uX2lkGAogASgJUh'
    'RvcmlnaW5JbnN0YWxsYXRpb25JZA==');

@$core.Deprecated('Use proofEntityDescriptor instead')
const ProofEntity$json = {
  '1': 'ProofEntity',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.ProofEntity.Kind',
      '10': 'kind'
    },
    {'1': 'id', '3': 2, '4': 1, '5': 9, '10': 'id'},
    {'1': 'revision', '3': 3, '4': 1, '5': 4, '10': 'revision'},
    {'1': 'tombstone', '3': 4, '4': 1, '5': 8, '10': 'tombstone'},
    {'1': 'document', '3': 5, '4': 1, '5': 12, '10': 'document'},
  ],
  '4': [ProofEntity_Kind$json],
};

@$core.Deprecated('Use proofEntityDescriptor instead')
const ProofEntity_Kind$json = {
  '1': 'Kind',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'ORDER', '2': 1},
    {'1': 'TABLE', '2': 2},
    {'1': 'RESERVATION', '2': 3},
    {'1': 'PACKAGE', '2': 4},
    {'1': 'SALE', '2': 5},
    {'1': 'DAY', '2': 6},
    {'1': 'OPERATIONAL_CONTROL', '2': 7},
    {'1': 'AUDIT_REPORT', '2': 8},
    {'1': 'CLOSURE', '2': 9},
    {'1': 'ADVANCE', '2': 10},
    {'1': 'EXPENSE', '2': 11},
    {'1': 'STAFF', '2': 12},
    {'1': 'OPERATIONAL_POLICY', '2': 13},
  ],
};

/// Descriptor for `ProofEntity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofEntityDescriptor = $convert.base64Decode(
    'CgtQcm9vZkVudGl0eRIzCgRraW5kGAEgASgOMh8udnluaWMuZWRnZS52MS5Qcm9vZkVudGl0eS'
    '5LaW5kUgRraW5kEg4KAmlkGAIgASgJUgJpZBIaCghyZXZpc2lvbhgDIAEoBFIIcmV2aXNpb24S'
    'HAoJdG9tYnN0b25lGAQgASgIUgl0b21ic3RvbmUSGgoIZG9jdW1lbnQYBSABKAxSCGRvY3VtZW'
    '50ItMBCgRLaW5kEg8KC1VOU1BFQ0lGSUVEEAASCQoFT1JERVIQARIJCgVUQUJMRRACEg8KC1JF'
    'U0VSVkFUSU9OEAMSCwoHUEFDS0FHRRAEEggKBFNBTEUQBRIHCgNEQVkQBhIXChNPUEVSQVRJT0'
    '5BTF9DT05UUk9MEAcSEAoMQVVESVRfUkVQT1JUEAgSCwoHQ0xPU1VSRRAJEgsKB0FEVkFOQ0UQ'
    'ChILCgdFWFBFTlNFEAsSCQoFU1RBRkYQDBIWChJPUEVSQVRJT05BTF9QT0xJQ1kQDQ==');

@$core.Deprecated('Use proofReadDescriptor instead')
const ProofRead$json = {
  '1': 'ProofRead',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.ProofEntity.Kind',
      '10': 'kind'
    },
    {'1': 'id', '3': 2, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {
      '1': 'expected_tombstone',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'expectedTombstone'
    },
  ],
};

/// Descriptor for `ProofRead`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofReadDescriptor = $convert.base64Decode(
    'CglQcm9vZlJlYWQSMwoEa2luZBgBIAEoDjIfLnZ5bmljLmVkZ2UudjEuUHJvb2ZFbnRpdHkuS2'
    'luZFIEa2luZBIOCgJpZBgCIAEoCVICaWQSKwoRZXhwZWN0ZWRfcmV2aXNpb24YAyABKARSEGV4'
    'cGVjdGVkUmV2aXNpb24SLQoSZXhwZWN0ZWRfdG9tYnN0b25lGAQgASgIUhFleHBlY3RlZFRvbW'
    'JzdG9uZQ==');

@$core.Deprecated('Use proofWriteDescriptor instead')
const ProofWrite$json = {
  '1': 'ProofWrite',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.ProofEntity.Kind',
      '10': 'kind'
    },
    {'1': 'id', '3': 2, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {'1': 'tombstone', '3': 4, '4': 1, '5': 8, '10': 'tombstone'},
    {'1': 'document', '3': 5, '4': 1, '5': 12, '10': 'document'},
  ],
};

/// Descriptor for `ProofWrite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofWriteDescriptor = $convert.base64Decode(
    'CgpQcm9vZldyaXRlEjMKBGtpbmQYASABKA4yHy52eW5pYy5lZGdlLnYxLlByb29mRW50aXR5Lk'
    'tpbmRSBGtpbmQSDgoCaWQYAiABKAlSAmlkEisKEWV4cGVjdGVkX3JldmlzaW9uGAMgASgEUhBl'
    'eHBlY3RlZFJldmlzaW9uEhwKCXRvbWJzdG9uZRgEIAEoCFIJdG9tYnN0b25lEhoKCGRvY3VtZW'
    '50GAUgASgMUghkb2N1bWVudA==');

@$core.Deprecated('Use proofEffectDescriptor instead')
const ProofEffect$json = {
  '1': 'ProofEffect',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.ProofEffect.Kind',
      '10': 'kind'
    },
    {'1': 'payload', '3': 3, '4': 1, '5': 12, '10': 'payload'},
  ],
  '4': [ProofEffect_Kind$json],
};

@$core.Deprecated('Use proofEffectDescriptor instead')
const ProofEffect_Kind$json = {
  '1': 'Kind',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'AUDIT', '2': 1},
    {'1': 'PRINT', '2': 2},
  ],
};

/// Descriptor for `ProofEffect`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofEffectDescriptor = $convert.base64Decode(
    'CgtQcm9vZkVmZmVjdBIOCgJpZBgBIAEoCVICaWQSMwoEa2luZBgCIAEoDjIfLnZ5bmljLmVkZ2'
    'UudjEuUHJvb2ZFZmZlY3QuS2luZFIEa2luZBIYCgdwYXlsb2FkGAMgASgMUgdwYXlsb2FkIi0K'
    'BEtpbmQSDwoLVU5TUEVDSUZJRUQQABIJCgVBVURJVBABEgkKBVBSSU5UEAI=');

@$core.Deprecated('Use proofCommitRequestDescriptor instead')
const ProofCommitRequest$json = {
  '1': 'ProofCommitRequest',
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
      '1': 'reads',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofRead',
      '10': 'reads'
    },
    {
      '1': 'writes',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofWrite',
      '10': 'writes'
    },
    {
      '1': 'effects',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEffect',
      '10': 'effects'
    },
    {'1': 'application_data', '3': 7, '4': 1, '5': 12, '10': 'applicationData'},
    {'1': 'print_admission', '3': 8, '4': 1, '5': 9, '10': 'printAdmission'},
    {
      '1': 'origin_installation_id',
      '3': 9,
      '4': 1,
      '5': 9,
      '10': 'originInstallationId'
    },
  ],
};

/// Descriptor for `ProofCommitRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofCommitRequestDescriptor = $convert.base64Decode(
    'ChJQcm9vZkNvbW1pdFJlcXVlc3QSNwoEYXV0aBgBIAEoCzIjLnZ5bmljLmVkZ2UudjEuQXV0aG'
    'VudGljYXRlZFJlcXVlc3RSBGF1dGgSHQoKcmVxdWVzdF9pZBgCIAEoCVIJcmVxdWVzdElkEicK'
    'D2F1dGhvcml0eV9lcG9jaBgDIAEoBFIOYXV0aG9yaXR5RXBvY2gSLgoFcmVhZHMYBCADKAsyGC'
    '52eW5pYy5lZGdlLnYxLlByb29mUmVhZFIFcmVhZHMSMQoGd3JpdGVzGAUgAygLMhkudnluaWMu'
    'ZWRnZS52MS5Qcm9vZldyaXRlUgZ3cml0ZXMSNAoHZWZmZWN0cxgGIAMoCzIaLnZ5bmljLmVkZ2'
    'UudjEuUHJvb2ZFZmZlY3RSB2VmZmVjdHMSKQoQYXBwbGljYXRpb25fZGF0YRgHIAEoDFIPYXBw'
    'bGljYXRpb25EYXRhEicKD3ByaW50X2FkbWlzc2lvbhgIIAEoCVIOcHJpbnRBZG1pc3Npb24SNA'
    'oWb3JpZ2luX2luc3RhbGxhdGlvbl9pZBgJIAEoCVIUb3JpZ2luSW5zdGFsbGF0aW9uSWQ=');

@$core.Deprecated('Use proofPrintReceiptDescriptor instead')
const ProofPrintReceipt$json = {
  '1': 'ProofPrintReceipt',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 13, '10': 'version'},
    {'1': 'job_id', '3': 2, '4': 1, '5': 9, '10': 'jobId'},
    {'1': 'effect_id', '3': 3, '4': 1, '5': 9, '10': 'effectId'},
    {
      '1': 'physical_printer_id',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'physicalPrinterId'
    },
    {'1': 'sequence', '3': 5, '4': 1, '5': 4, '10': 'sequence'},
    {'1': 'admission_sha256', '3': 6, '4': 1, '5': 9, '10': 'admissionSha256'},
  ],
};

/// Descriptor for `ProofPrintReceipt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofPrintReceiptDescriptor = $convert.base64Decode(
    'ChFQcm9vZlByaW50UmVjZWlwdBIYCgd2ZXJzaW9uGAEgASgNUgd2ZXJzaW9uEhUKBmpvYl9pZB'
    'gCIAEoCVIFam9iSWQSGwoJZWZmZWN0X2lkGAMgASgJUghlZmZlY3RJZBIuChNwaHlzaWNhbF9w'
    'cmludGVyX2lkGAQgASgJUhFwaHlzaWNhbFByaW50ZXJJZBIaCghzZXF1ZW5jZRgFIAEoBFIIc2'
    'VxdWVuY2USKQoQYWRtaXNzaW9uX3NoYTI1NhgGIAEoCVIPYWRtaXNzaW9uU2hhMjU2');

@$core.Deprecated('Use proofEventDescriptor instead')
const ProofEvent$json = {
  '1': 'ProofEvent',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 9, '10': 'mode'},
    {'1': 'authority_epoch', '3': 2, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'sequence', '3': 3, '4': 1, '5': 4, '10': 'sequence'},
    {'1': 'request_id', '3': 4, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'terminal_id', '3': 5, '4': 1, '5': 9, '10': 'terminalId'},
    {
      '1': 'entities',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEntity',
      '10': 'entities'
    },
    {
      '1': 'effects',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEffect',
      '10': 'effects'
    },
    {'1': 'print_admission', '3': 8, '4': 1, '5': 9, '10': 'printAdmission'},
    {
      '1': 'origin_installation_id',
      '3': 9,
      '4': 1,
      '5': 9,
      '10': 'originInstallationId'
    },
    {
      '1': 'print_receipts',
      '3': 10,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofPrintReceipt',
      '10': 'printReceipts'
    },
  ],
};

/// Descriptor for `ProofEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofEventDescriptor = $convert.base64Decode(
    'CgpQcm9vZkV2ZW50EhIKBG1vZGUYASABKAlSBG1vZGUSJwoPYXV0aG9yaXR5X2Vwb2NoGAIgAS'
    'gEUg5hdXRob3JpdHlFcG9jaBIaCghzZXF1ZW5jZRgDIAEoBFIIc2VxdWVuY2USHQoKcmVxdWVz'
    'dF9pZBgEIAEoCVIJcmVxdWVzdElkEh8KC3Rlcm1pbmFsX2lkGAUgASgJUgp0ZXJtaW5hbElkEj'
    'YKCGVudGl0aWVzGAYgAygLMhoudnluaWMuZWRnZS52MS5Qcm9vZkVudGl0eVIIZW50aXRpZXMS'
    'NAoHZWZmZWN0cxgHIAMoCzIaLnZ5bmljLmVkZ2UudjEuUHJvb2ZFZmZlY3RSB2VmZmVjdHMSJw'
    'oPcHJpbnRfYWRtaXNzaW9uGAggASgJUg5wcmludEFkbWlzc2lvbhI0ChZvcmlnaW5faW5zdGFs'
    'bGF0aW9uX2lkGAkgASgJUhRvcmlnaW5JbnN0YWxsYXRpb25JZBJHCg5wcmludF9yZWNlaXB0cx'
    'gKIAMoCzIgLnZ5bmljLmVkZ2UudjEuUHJvb2ZQcmludFJlY2VpcHRSDXByaW50UmVjZWlwdHM=');

@$core.Deprecated('Use proofCommitResultDescriptor instead')
const ProofCommitResult$json = {
  '1': 'ProofCommitResult',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 9, '10': 'mode'},
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'terminal_id', '3': 3, '4': 1, '5': 9, '10': 'terminalId'},
    {
      '1': 'outcome',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.vynic.edge.v1.ProofCommitResult.Outcome',
      '10': 'outcome'
    },
    {'1': 'authority_epoch', '3': 5, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'head_sequence', '3': 6, '4': 1, '5': 4, '10': 'headSequence'},
    {
      '1': 'event',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEvent',
      '10': 'event'
    },
    {
      '1': 'current',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEntity',
      '10': 'current'
    },
    {'1': 'application_data', '3': 9, '4': 1, '5': 12, '10': 'applicationData'},
    {'1': 'print_admission', '3': 10, '4': 1, '5': 9, '10': 'printAdmission'},
    {
      '1': 'origin_installation_id',
      '3': 11,
      '4': 1,
      '5': 9,
      '10': 'originInstallationId'
    },
  ],
  '4': [ProofCommitResult_Outcome$json],
};

@$core.Deprecated('Use proofCommitResultDescriptor instead')
const ProofCommitResult_Outcome$json = {
  '1': 'Outcome',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'COMMITTED', '2': 1},
    {'1': 'CONFLICT', '2': 2},
  ],
};

/// Descriptor for `ProofCommitResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofCommitResultDescriptor = $convert.base64Decode(
    'ChFQcm9vZkNvbW1pdFJlc3VsdBISCgRtb2RlGAEgASgJUgRtb2RlEh0KCnJlcXVlc3RfaWQYAi'
    'ABKAlSCXJlcXVlc3RJZBIfCgt0ZXJtaW5hbF9pZBgDIAEoCVIKdGVybWluYWxJZBJCCgdvdXRj'
    'b21lGAQgASgOMigudnluaWMuZWRnZS52MS5Qcm9vZkNvbW1pdFJlc3VsdC5PdXRjb21lUgdvdX'
    'Rjb21lEicKD2F1dGhvcml0eV9lcG9jaBgFIAEoBFIOYXV0aG9yaXR5RXBvY2gSIwoNaGVhZF9z'
    'ZXF1ZW5jZRgGIAEoBFIMaGVhZFNlcXVlbmNlEi8KBWV2ZW50GAcgASgLMhkudnluaWMuZWRnZS'
    '52MS5Qcm9vZkV2ZW50UgVldmVudBI0CgdjdXJyZW50GAggAygLMhoudnluaWMuZWRnZS52MS5Q'
    'cm9vZkVudGl0eVIHY3VycmVudBIpChBhcHBsaWNhdGlvbl9kYXRhGAkgASgMUg9hcHBsaWNhdG'
    'lvbkRhdGESJwoPcHJpbnRfYWRtaXNzaW9uGAogASgJUg5wcmludEFkbWlzc2lvbhI0ChZvcmln'
    'aW5faW5zdGFsbGF0aW9uX2lkGAsgASgJUhRvcmlnaW5JbnN0YWxsYXRpb25JZCI3CgdPdXRjb2'
    '1lEg8KC1VOU1BFQ0lGSUVEEAASDQoJQ09NTUlUVEVEEAESDAoIQ09ORkxJQ1QQAg==');

@$core.Deprecated('Use proofResultRequestDescriptor instead')
const ProofResultRequest$json = {
  '1': 'ProofResultRequest',
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
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
  ],
};

/// Descriptor for `ProofResultRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofResultRequestDescriptor = $convert.base64Decode(
    'ChJQcm9vZlJlc3VsdFJlcXVlc3QSNwoEYXV0aBgBIAEoCzIjLnZ5bmljLmVkZ2UudjEuQXV0aG'
    'VudGljYXRlZFJlcXVlc3RSBGF1dGgSJwoPYXV0aG9yaXR5X2Vwb2NoGAIgASgEUg5hdXRob3Jp'
    'dHlFcG9jaBIdCgpyZXF1ZXN0X2lkGAMgASgJUglyZXF1ZXN0SWQ=');

@$core.Deprecated('Use proofReplayRequestDescriptor instead')
const ProofReplayRequest$json = {
  '1': 'ProofReplayRequest',
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

/// Descriptor for `ProofReplayRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofReplayRequestDescriptor = $convert.base64Decode(
    'ChJQcm9vZlJlcGxheVJlcXVlc3QSNwoEYXV0aBgBIAEoCzIjLnZ5bmljLmVkZ2UudjEuQXV0aG'
    'VudGljYXRlZFJlcXVlc3RSBGF1dGgSJwoPYXV0aG9yaXR5X2Vwb2NoGAIgASgEUg5hdXRob3Jp'
    'dHlFcG9jaBIlCg5hZnRlcl9zZXF1ZW5jZRgDIAEoBFINYWZ0ZXJTZXF1ZW5jZRIUCgVsaW1pdB'
    'gEIAEoDVIFbGltaXQ=');

@$core.Deprecated('Use proofReplayPageDescriptor instead')
const ProofReplayPage$json = {
  '1': 'ProofReplayPage',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 9, '10': 'mode'},
    {'1': 'authority_epoch', '3': 2, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'after_sequence', '3': 3, '4': 1, '5': 4, '10': 'afterSequence'},
    {'1': 'head_sequence', '3': 4, '4': 1, '5': 4, '10': 'headSequence'},
    {'1': 'next_sequence', '3': 5, '4': 1, '5': 4, '10': 'nextSequence'},
    {
      '1': 'events',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEvent',
      '10': 'events'
    },
  ],
};

/// Descriptor for `ProofReplayPage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofReplayPageDescriptor = $convert.base64Decode(
    'Cg9Qcm9vZlJlcGxheVBhZ2USEgoEbW9kZRgBIAEoCVIEbW9kZRInCg9hdXRob3JpdHlfZXBvY2'
    'gYAiABKARSDmF1dGhvcml0eUVwb2NoEiUKDmFmdGVyX3NlcXVlbmNlGAMgASgEUg1hZnRlclNl'
    'cXVlbmNlEiMKDWhlYWRfc2VxdWVuY2UYBCABKARSDGhlYWRTZXF1ZW5jZRIjCg1uZXh0X3NlcX'
    'VlbmNlGAUgASgEUgxuZXh0U2VxdWVuY2USMQoGZXZlbnRzGAYgAygLMhkudnluaWMuZWRnZS52'
    'MS5Qcm9vZkV2ZW50UgZldmVudHM=');

@$core.Deprecated('Use proofSnapshotRequestDescriptor instead')
const ProofSnapshotRequest$json = {
  '1': 'ProofSnapshotRequest',
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

/// Descriptor for `ProofSnapshotRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofSnapshotRequestDescriptor = $convert.base64Decode(
    'ChRQcm9vZlNuYXBzaG90UmVxdWVzdBI3CgRhdXRoGAEgASgLMiMudnluaWMuZWRnZS52MS5BdX'
    'RoZW50aWNhdGVkUmVxdWVzdFIEYXV0aBInCg9hdXRob3JpdHlfZXBvY2gYAiABKARSDmF1dGhv'
    'cml0eUVwb2No');

@$core.Deprecated('Use proofSnapshotDescriptor instead')
const ProofSnapshot$json = {
  '1': 'ProofSnapshot',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 9, '10': 'mode'},
    {'1': 'venue_id', '3': 2, '4': 1, '5': 9, '10': 'venueId'},
    {'1': 'installation_id', '3': 3, '4': 1, '5': 9, '10': 'installationId'},
    {'1': 'authority_epoch', '3': 4, '4': 1, '5': 4, '10': 'authorityEpoch'},
    {'1': 'sequence', '3': 5, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'entities',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.vynic.edge.v1.ProofEntity',
      '10': 'entities'
    },
  ],
};

/// Descriptor for `ProofSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofSnapshotDescriptor = $convert.base64Decode(
    'Cg1Qcm9vZlNuYXBzaG90EhIKBG1vZGUYASABKAlSBG1vZGUSGQoIdmVudWVfaWQYAiABKAlSB3'
    'ZlbnVlSWQSJwoPaW5zdGFsbGF0aW9uX2lkGAMgASgJUg5pbnN0YWxsYXRpb25JZBInCg9hdXRo'
    'b3JpdHlfZXBvY2gYBCABKARSDmF1dGhvcml0eUVwb2NoEhoKCHNlcXVlbmNlGAUgASgEUghzZX'
    'F1ZW5jZRI2CghlbnRpdGllcxgGIAMoCzIaLnZ5bmljLmVkZ2UudjEuUHJvb2ZFbnRpdHlSCGVu'
    'dGl0aWVz');
