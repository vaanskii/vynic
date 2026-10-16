// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/operational_proof.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'foundation.pb.dart' as $0;
import 'operational_proof.pb.dart' as $1;

export 'operational_proof.pb.dart';

/// Fixture-only proof contract, never a production activation token. Register
/// through a separate explicit harness after verified authority pinning. Normal
/// Foundation startup/capabilities/business_mutations_enabled remain unchanged.
/// Requires protocol 1.3 and operational.coordination.proof.v1. This floor is
/// separate from normal Foundation protocol 1.1. No auto-pinning,
/// epoch reset, promotion, takeover, or printer dispatch RPC exists.
@$pb.GrpcServiceName('vynic.edge.v1.OperationalProof')
class OperationalProofClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  OperationalProofClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$1.ProofStatus> status(
    $0.AuthenticatedRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$status, request, options: options);
  }

  $grpc.ResponseFuture<$1.ProofCommitResult> commit(
    $1.ProofCommitRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$commit, request, options: options);
  }

  $grpc.ResponseFuture<$1.ProofCommitResult> getResult(
    $1.ProofResultRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getResult, request, options: options);
  }

  $grpc.ResponseFuture<$1.ProofReplayPage> replay(
    $1.ProofReplayRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$replay, request, options: options);
  }

  $grpc.ResponseFuture<$1.ProofSnapshot> snapshot(
    $1.ProofSnapshotRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$snapshot, request, options: options);
  }

  // method descriptors

  static final _$status =
      $grpc.ClientMethod<$0.AuthenticatedRequest, $1.ProofStatus>(
          '/vynic.edge.v1.OperationalProof/Status',
          ($0.AuthenticatedRequest value) => value.writeToBuffer(),
          $1.ProofStatus.fromBuffer);
  static final _$commit =
      $grpc.ClientMethod<$1.ProofCommitRequest, $1.ProofCommitResult>(
          '/vynic.edge.v1.OperationalProof/Commit',
          ($1.ProofCommitRequest value) => value.writeToBuffer(),
          $1.ProofCommitResult.fromBuffer);
  static final _$getResult =
      $grpc.ClientMethod<$1.ProofResultRequest, $1.ProofCommitResult>(
          '/vynic.edge.v1.OperationalProof/GetResult',
          ($1.ProofResultRequest value) => value.writeToBuffer(),
          $1.ProofCommitResult.fromBuffer);
  static final _$replay =
      $grpc.ClientMethod<$1.ProofReplayRequest, $1.ProofReplayPage>(
          '/vynic.edge.v1.OperationalProof/Replay',
          ($1.ProofReplayRequest value) => value.writeToBuffer(),
          $1.ProofReplayPage.fromBuffer);
  static final _$snapshot =
      $grpc.ClientMethod<$1.ProofSnapshotRequest, $1.ProofSnapshot>(
          '/vynic.edge.v1.OperationalProof/Snapshot',
          ($1.ProofSnapshotRequest value) => value.writeToBuffer(),
          $1.ProofSnapshot.fromBuffer);
}

@$pb.GrpcServiceName('vynic.edge.v1.OperationalProof')
abstract class OperationalProofServiceBase extends $grpc.Service {
  $core.String get $name => 'vynic.edge.v1.OperationalProof';

  OperationalProofServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.AuthenticatedRequest, $1.ProofStatus>(
        'Status',
        status_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AuthenticatedRequest.fromBuffer(value),
        ($1.ProofStatus value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ProofCommitRequest, $1.ProofCommitResult>(
        'Commit',
        commit_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ProofCommitRequest.fromBuffer(value),
        ($1.ProofCommitResult value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ProofResultRequest, $1.ProofCommitResult>(
        'GetResult',
        getResult_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ProofResultRequest.fromBuffer(value),
        ($1.ProofCommitResult value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ProofReplayRequest, $1.ProofReplayPage>(
        'Replay',
        replay_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ProofReplayRequest.fromBuffer(value),
        ($1.ProofReplayPage value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ProofSnapshotRequest, $1.ProofSnapshot>(
        'Snapshot',
        snapshot_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ProofSnapshotRequest.fromBuffer(value),
        ($1.ProofSnapshot value) => value.writeToBuffer()));
  }

  $async.Future<$1.ProofStatus> status_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AuthenticatedRequest> $request) async {
    return status($call, await $request);
  }

  $async.Future<$1.ProofStatus> status(
      $grpc.ServiceCall call, $0.AuthenticatedRequest request);

  $async.Future<$1.ProofCommitResult> commit_Pre($grpc.ServiceCall $call,
      $async.Future<$1.ProofCommitRequest> $request) async {
    return commit($call, await $request);
  }

  $async.Future<$1.ProofCommitResult> commit(
      $grpc.ServiceCall call, $1.ProofCommitRequest request);

  $async.Future<$1.ProofCommitResult> getResult_Pre($grpc.ServiceCall $call,
      $async.Future<$1.ProofResultRequest> $request) async {
    return getResult($call, await $request);
  }

  $async.Future<$1.ProofCommitResult> getResult(
      $grpc.ServiceCall call, $1.ProofResultRequest request);

  $async.Future<$1.ProofReplayPage> replay_Pre($grpc.ServiceCall $call,
      $async.Future<$1.ProofReplayRequest> $request) async {
    return replay($call, await $request);
  }

  $async.Future<$1.ProofReplayPage> replay(
      $grpc.ServiceCall call, $1.ProofReplayRequest request);

  $async.Future<$1.ProofSnapshot> snapshot_Pre($grpc.ServiceCall $call,
      $async.Future<$1.ProofSnapshotRequest> $request) async {
    return snapshot($call, await $request);
  }

  $async.Future<$1.ProofSnapshot> snapshot(
      $grpc.ServiceCall call, $1.ProofSnapshotRequest request);
}
