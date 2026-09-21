// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/orders_tables.proto.

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

import 'orders_tables.pb.dart' as $0;

export 'orders_tables.pb.dart';

/// Phase 2A is a SHADOW projection only. No production authority is granted.
/// Flutter owns business validation; Edge owns compare-and-swap and durability.
@$pb.GrpcServiceName('vynic.edge.v1.OrdersTables')
class OrdersTablesClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  OrdersTablesClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.CommitResult> commit(
    $0.CommitIntent request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$commit, request, options: options);
  }

  $grpc.ResponseFuture<$0.ReplayPage> replay(
    $0.ReplayRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$replay, request, options: options);
  }

  $grpc.ResponseFuture<$0.ProjectionSnapshot> snapshot(
    $0.SnapshotRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$snapshot, request, options: options);
  }

  // method descriptors

  static final _$commit = $grpc.ClientMethod<$0.CommitIntent, $0.CommitResult>(
      '/vynic.edge.v1.OrdersTables/Commit',
      ($0.CommitIntent value) => value.writeToBuffer(),
      $0.CommitResult.fromBuffer);
  static final _$replay = $grpc.ClientMethod<$0.ReplayRequest, $0.ReplayPage>(
      '/vynic.edge.v1.OrdersTables/Replay',
      ($0.ReplayRequest value) => value.writeToBuffer(),
      $0.ReplayPage.fromBuffer);
  static final _$snapshot =
      $grpc.ClientMethod<$0.SnapshotRequest, $0.ProjectionSnapshot>(
          '/vynic.edge.v1.OrdersTables/Snapshot',
          ($0.SnapshotRequest value) => value.writeToBuffer(),
          $0.ProjectionSnapshot.fromBuffer);
}

@$pb.GrpcServiceName('vynic.edge.v1.OrdersTables')
abstract class OrdersTablesServiceBase extends $grpc.Service {
  $core.String get $name => 'vynic.edge.v1.OrdersTables';

  OrdersTablesServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.CommitIntent, $0.CommitResult>(
        'Commit',
        commit_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CommitIntent.fromBuffer(value),
        ($0.CommitResult value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ReplayRequest, $0.ReplayPage>(
        'Replay',
        replay_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ReplayRequest.fromBuffer(value),
        ($0.ReplayPage value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SnapshotRequest, $0.ProjectionSnapshot>(
        'Snapshot',
        snapshot_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SnapshotRequest.fromBuffer(value),
        ($0.ProjectionSnapshot value) => value.writeToBuffer()));
  }

  $async.Future<$0.CommitResult> commit_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.CommitIntent> $request) async {
    return commit($call, await $request);
  }

  $async.Future<$0.CommitResult> commit(
      $grpc.ServiceCall call, $0.CommitIntent request);

  $async.Future<$0.ReplayPage> replay_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ReplayRequest> $request) async {
    return replay($call, await $request);
  }

  $async.Future<$0.ReplayPage> replay(
      $grpc.ServiceCall call, $0.ReplayRequest request);

  $async.Future<$0.ProjectionSnapshot> snapshot_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SnapshotRequest> $request) async {
    return snapshot($call, await $request);
  }

  $async.Future<$0.ProjectionSnapshot> snapshot(
      $grpc.ServiceCall call, $0.SnapshotRequest request);
}
