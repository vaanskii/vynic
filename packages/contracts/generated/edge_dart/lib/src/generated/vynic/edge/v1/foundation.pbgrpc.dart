// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/foundation.proto.

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

export 'foundation.pb.dart';

/// Infrastructure only. No business mutation or command execution methods.
@$pb.GrpcServiceName('vynic.edge.v1.Foundation')
class FoundationClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  FoundationClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.PairResponse> pair(
    $0.PairRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$pair, request, options: options);
  }

  $grpc.ResponseFuture<$0.StatusResponse> handshake(
    $0.HandshakeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$handshake, request, options: options);
  }

  $grpc.ResponseFuture<$0.StatusResponse> status(
    $0.AuthenticatedRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$status, request, options: options);
  }

  $grpc.ResponseStream<$0.StatusResponse> watchStatus(
    $0.AuthenticatedRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchStatus, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$pair = $grpc.ClientMethod<$0.PairRequest, $0.PairResponse>(
      '/vynic.edge.v1.Foundation/Pair',
      ($0.PairRequest value) => value.writeToBuffer(),
      $0.PairResponse.fromBuffer);
  static final _$handshake =
      $grpc.ClientMethod<$0.HandshakeRequest, $0.StatusResponse>(
          '/vynic.edge.v1.Foundation/Handshake',
          ($0.HandshakeRequest value) => value.writeToBuffer(),
          $0.StatusResponse.fromBuffer);
  static final _$status =
      $grpc.ClientMethod<$0.AuthenticatedRequest, $0.StatusResponse>(
          '/vynic.edge.v1.Foundation/Status',
          ($0.AuthenticatedRequest value) => value.writeToBuffer(),
          $0.StatusResponse.fromBuffer);
  static final _$watchStatus =
      $grpc.ClientMethod<$0.AuthenticatedRequest, $0.StatusResponse>(
          '/vynic.edge.v1.Foundation/WatchStatus',
          ($0.AuthenticatedRequest value) => value.writeToBuffer(),
          $0.StatusResponse.fromBuffer);
}

@$pb.GrpcServiceName('vynic.edge.v1.Foundation')
abstract class FoundationServiceBase extends $grpc.Service {
  $core.String get $name => 'vynic.edge.v1.Foundation';

  FoundationServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.PairRequest, $0.PairResponse>(
        'Pair',
        pair_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PairRequest.fromBuffer(value),
        ($0.PairResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.HandshakeRequest, $0.StatusResponse>(
        'Handshake',
        handshake_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.HandshakeRequest.fromBuffer(value),
        ($0.StatusResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AuthenticatedRequest, $0.StatusResponse>(
        'Status',
        status_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AuthenticatedRequest.fromBuffer(value),
        ($0.StatusResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AuthenticatedRequest, $0.StatusResponse>(
        'WatchStatus',
        watchStatus_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.AuthenticatedRequest.fromBuffer(value),
        ($0.StatusResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.PairResponse> pair_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.PairRequest> $request) async {
    return pair($call, await $request);
  }

  $async.Future<$0.PairResponse> pair(
      $grpc.ServiceCall call, $0.PairRequest request);

  $async.Future<$0.StatusResponse> handshake_Pre($grpc.ServiceCall $call,
      $async.Future<$0.HandshakeRequest> $request) async {
    return handshake($call, await $request);
  }

  $async.Future<$0.StatusResponse> handshake(
      $grpc.ServiceCall call, $0.HandshakeRequest request);

  $async.Future<$0.StatusResponse> status_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AuthenticatedRequest> $request) async {
    return status($call, await $request);
  }

  $async.Future<$0.StatusResponse> status(
      $grpc.ServiceCall call, $0.AuthenticatedRequest request);

  $async.Stream<$0.StatusResponse> watchStatus_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AuthenticatedRequest> $request) async* {
    yield* watchStatus($call, await $request);
  }

  $async.Stream<$0.StatusResponse> watchStatus(
      $grpc.ServiceCall call, $0.AuthenticatedRequest request);
}
