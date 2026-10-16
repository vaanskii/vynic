// This is a generated file - do not edit.
//
// Generated from vynic/edge/v1/printer_agent.proto.

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

import 'printer_agent.pb.dart' as $0;

export 'printer_agent.pb.dart';

/// Independent printer process infrastructure. This version holds all job
/// admission and physical dispatch; configuration is not production authority.
@$pb.GrpcServiceName('vynic.edge.v1.PrinterAgent')
class PrinterAgentClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  PrinterAgentClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.PrinterAgentHealthResponse> health(
    $0.PrinterAgentHealthRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$health, request, options: options);
  }

  $grpc.ResponseFuture<$0.PrinterAgentSubmissionResult> submitLocal(
    $0.PrinterAgentSubmitLocalRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$submitLocal, request, options: options);
  }

  $grpc.ResponseFuture<$0.PrinterAgentSubmissionResult> getLocalResult(
    $0.PrinterAgentGetLocalResultRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getLocalResult, request, options: options);
  }

  // method descriptors

  static final _$health = $grpc.ClientMethod<$0.PrinterAgentHealthRequest,
          $0.PrinterAgentHealthResponse>(
      '/vynic.edge.v1.PrinterAgent/Health',
      ($0.PrinterAgentHealthRequest value) => value.writeToBuffer(),
      $0.PrinterAgentHealthResponse.fromBuffer);
  static final _$submitLocal = $grpc.ClientMethod<
          $0.PrinterAgentSubmitLocalRequest, $0.PrinterAgentSubmissionResult>(
      '/vynic.edge.v1.PrinterAgent/SubmitLocal',
      ($0.PrinterAgentSubmitLocalRequest value) => value.writeToBuffer(),
      $0.PrinterAgentSubmissionResult.fromBuffer);
  static final _$getLocalResult = $grpc.ClientMethod<
          $0.PrinterAgentGetLocalResultRequest,
          $0.PrinterAgentSubmissionResult>(
      '/vynic.edge.v1.PrinterAgent/GetLocalResult',
      ($0.PrinterAgentGetLocalResultRequest value) => value.writeToBuffer(),
      $0.PrinterAgentSubmissionResult.fromBuffer);
}

@$pb.GrpcServiceName('vynic.edge.v1.PrinterAgent')
abstract class PrinterAgentServiceBase extends $grpc.Service {
  $core.String get $name => 'vynic.edge.v1.PrinterAgent';

  PrinterAgentServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.PrinterAgentHealthRequest,
            $0.PrinterAgentHealthResponse>(
        'Health',
        health_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.PrinterAgentHealthRequest.fromBuffer(value),
        ($0.PrinterAgentHealthResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PrinterAgentSubmitLocalRequest,
            $0.PrinterAgentSubmissionResult>(
        'SubmitLocal',
        submitLocal_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.PrinterAgentSubmitLocalRequest.fromBuffer(value),
        ($0.PrinterAgentSubmissionResult value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PrinterAgentGetLocalResultRequest,
            $0.PrinterAgentSubmissionResult>(
        'GetLocalResult',
        getLocalResult_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.PrinterAgentGetLocalResultRequest.fromBuffer(value),
        ($0.PrinterAgentSubmissionResult value) => value.writeToBuffer()));
  }

  $async.Future<$0.PrinterAgentHealthResponse> health_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.PrinterAgentHealthRequest> $request) async {
    return health($call, await $request);
  }

  $async.Future<$0.PrinterAgentHealthResponse> health(
      $grpc.ServiceCall call, $0.PrinterAgentHealthRequest request);

  $async.Future<$0.PrinterAgentSubmissionResult> submitLocal_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.PrinterAgentSubmitLocalRequest> $request) async {
    return submitLocal($call, await $request);
  }

  $async.Future<$0.PrinterAgentSubmissionResult> submitLocal(
      $grpc.ServiceCall call, $0.PrinterAgentSubmitLocalRequest request);

  $async.Future<$0.PrinterAgentSubmissionResult> getLocalResult_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.PrinterAgentGetLocalResultRequest> $request) async {
    return getLocalResult($call, await $request);
  }

  $async.Future<$0.PrinterAgentSubmissionResult> getLocalResult(
      $grpc.ServiceCall call, $0.PrinterAgentGetLocalResultRequest request);
}
