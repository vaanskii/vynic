import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/noop_edge_command_handler.dart';
import 'package:vynic/core/services/edge/pos_edge_command_handlers.dart';

/// What one poll did. Returned so tests can assert on it without timers.
class EdgePollSummary {
  const EdgePollSummary({
    required this.outcome,
    this.claimed = 0,
    this.executed = 0,
    this.skippedAlreadyDone = 0,
    this.skippedUnsupported = 0,
    this.acknowledged = 0,
  });

  final EdgeTransportOutcome outcome;
  final int claimed;

  /// Commands whose handler actually ran.
  final int executed;

  /// Redeliveries the local journal recognised as already finished.
  final int skippedAlreadyDone;

  /// Commands this build cannot run — unknown type or a newer contract.
  final int skippedUnsupported;
  final int acknowledged;
}

/// The one owner of Cloud → Edge polling.
///
/// A single timer in a single place. Screens do not poll, because a timer per
/// screen is how a POS ends up with six overlapping claim requests and no way
/// to reason about any of them.
///
/// Nothing here is on the path of taking an order. It starts after local
/// initialization, it never blocks startup, and every failure mode — no
/// credential, no network, a rejected credential, a handler that throws — ends
/// with the POS still working and this loop either backing off or standing
/// down.
class EdgeTransportService {
  EdgeTransportService({
    EdgeTransportClient? client,
    EdgeCommandRegistry? registry,
    this.idleInterval = const Duration(seconds: 10),
    this.drainInterval = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 5),
    Random? random,
  }) : _client = client ?? EdgeTransportClient(),
       _registry =
           registry ??
           EdgeCommandRegistry(const <EdgeCommandHandler>[
             NoopEdgeCommandHandler(),
             ...posEdgeCommandHandlers,
           ]),
       _random = random ?? Random();

  static EdgeTransportService? _instance;

  /// The app-wide instance. Created on first use.
  static EdgeTransportService instance() =>
      _instance ??= EdgeTransportService();

  @visibleForTesting
  static void overrideInstance(EdgeTransportService? service) {
    _instance = service;
  }

  final EdgeTransportClient _client;
  final EdgeCommandRegistry _registry;
  final Random _random;

  /// How long to wait when the last poll found nothing.
  ///
  /// Ten seconds rather than thirty since Step 6C, because what rides this
  /// transport stopped being a NOOP. A manager pressing "print check" is
  /// waiting for paper, and the interval is the floor on how long that takes.
  /// It is also the base of the backoff, so an offline restaurant still stops
  /// asking quickly — the cap is unchanged.
  final Duration idleInterval;

  /// How long to wait when the last poll found work — drain the queue promptly.
  final Duration drainInterval;

  /// The ceiling on backoff while Cloud is unreachable.
  final Duration maxBackoff;

  Timer? _timer;
  bool _running = false;
  bool _polling = false;
  int _consecutiveFailures = 0;
  bool _warnedUnauthorized = false;

  bool get isRunning => _running;

  /// Begins polling, if this installation has a Cloud identity.
  ///
  /// A POS with no credential is not an error and not a degraded state: it is
  /// every installation that has not been provisioned yet, and it must start
  /// and run exactly as it always did.
  Future<void> start() async {
    if (_running) return;
    if (!EdgeDeviceCredentialStore.isLoaded) {
      await EdgeDeviceCredentialStore.load();
    }
    if (!EdgeDeviceCredentialStore.hasCredential) {
      if (kDebugMode) {
        debugPrint(
          '[Edge] No device credential — cloud command polling stays off.',
        );
      }
      return;
    }

    await EdgeCommandJournal.open();
    _running = true;
    _consecutiveFailures = 0;
    _warnedUnauthorized = false;
    _schedule(drainInterval);
  }

  /// Stops polling. Safe to call when never started.
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await EdgeCommandJournal.close();
  }

  /// One claim → execute → acknowledge cycle.
  ///
  /// Re-entrant calls are refused rather than queued: two claims in flight would
  /// take two leases on the same work for no benefit.
  Future<EdgePollSummary> pollOnce() async {
    if (_polling) {
      return const EdgePollSummary(outcome: EdgeTransportOutcome.ok);
    }
    _polling = true;
    try {
      return await _poll();
    } catch (error) {
      // A bug in here must never reach the till.
      debugPrint('[Edge] Poll failed: $error');
      return const EdgePollSummary(outcome: EdgeTransportOutcome.serverError);
    } finally {
      _polling = false;
    }
  }

  Future<EdgePollSummary> _poll() async {
    final response = await _client.claim();
    if (!response.isOk) {
      if (response.outcome == EdgeTransportOutcome.unauthorized &&
          !_warnedUnauthorized) {
        _warnedUnauthorized = true;
        debugPrint(
          '[Edge] Cloud rejected this device credential — polling stands down. '
          'Re-provision the device to resume.',
        );
      }
      return EdgePollSummary(outcome: response.outcome);
    }

    var executed = 0;
    var alreadyDone = 0;
    var unsupported = 0;
    var acknowledged = 0;

    for (final command in response.commands) {
      final result = await _handle(command);
      switch (result.kind) {
        case _HandledKind.executed:
          executed += 1;
        case _HandledKind.alreadyDone:
          alreadyDone += 1;
        case _HandledKind.unsupported:
          unsupported += 1;
      }
      if (result.report == null) continue;

      final ack = await _client.acknowledge(result.report!);
      if (ack == EdgeTransportOutcome.ok) {
        acknowledged += 1;
      }
      // An acknowledgment lost to a dead connection is exactly what the journal
      // is for: Cloud will offer the command again and the journal will answer
      // for it without running anything twice.
    }

    return EdgePollSummary(
      outcome: EdgeTransportOutcome.ok,
      claimed: response.commands.length,
      executed: executed,
      skippedAlreadyDone: alreadyDone,
      skippedUnsupported: unsupported,
      acknowledged: acknowledged,
    );
  }

  Future<_Handled> _handle(EdgeCommandEnvelope command) async {
    // A newer contract than this build speaks. Cloud is asked to withhold these,
    // so reaching one means the fleet is mid-upgrade; say so rather than guess.
    if (!command.isSupportedVersion) {
      return _Handled(
        _HandledKind.unsupported,
        EdgeCommandResult.failed(
          command.commandId,
          code: 'unsupported_contract_version',
          detail: 'This POS speaks contract v$edgeCommandContractVersion',
        ),
      );
    }

    final handler = _registry.handlerFor(command.type);
    if (handler == null) {
      return _Handled(
        _HandledKind.unsupported,
        EdgeCommandResult.failed(
          command.commandId,
          code: 'unsupported_command_type',
          detail: 'No handler for ${command.type}',
        ),
      );
    }

    // The redelivery guard. A command this POS already finished is acknowledged
    // again with the outcome it had, and its side effect is not repeated.
    final previous = await EdgeCommandJournal.beginExecution(command);
    if (previous != null && previous.isTerminal) {
      return _Handled(
        _HandledKind.alreadyDone,
        previous.status == EdgeExecutionStatus.succeeded
            ? EdgeCommandResult.succeeded(
                command.commandId,
                code: 'already_executed',
              )
            : EdgeCommandResult.failed(
                command.commandId,
                code: previous.code ?? 'already_failed',
              ),
      );
    }

    // An execution this POS started and never finished. For a convergent
    // command, running it again is the right answer and the default. For one
    // whose side effect left the machine — a check that may or may not have
    // reached the printer — it is not: nobody knows what happened, and a second
    // check appearing silently is worse than a failure somebody can see.
    if (previous != null &&
        previous.status == EdgeExecutionStatus.interrupted &&
        EdgeCommandTypes.noRepeatAfterInterruption.contains(command.type)) {
      await EdgeCommandJournal.completeExecution(
        command.commandId,
        succeeded: false,
        code: 'interrupted_not_repeated',
      );
      return _Handled(
        _HandledKind.alreadyDone,
        EdgeCommandResult.failed(
          command.commandId,
          code: 'interrupted_not_repeated',
          detail:
              'This POS stopped while running ${command.type} and cannot tell '
              'whether it completed. Re-issue it deliberately if it did not.',
        ),
      );
    }

    try {
      final result = await handler.execute(command);
      final succeeded = result.status == EdgeCommandResultStatus.succeeded;
      await EdgeCommandJournal.completeExecution(
        command.commandId,
        succeeded: succeeded,
        code: result.code,
      );
      return _Handled(_HandledKind.executed, result);
    } catch (error) {
      await EdgeCommandJournal.completeExecution(
        command.commandId,
        succeeded: false,
        code: 'handler_threw',
      );
      return _Handled(
        _HandledKind.executed,
        EdgeCommandResult.failed(
          command.commandId,
          code: 'handler_threw',
          // The type, not the payload: a message may quote whatever it was given.
          detail: 'Handler for ${command.type} threw',
        ),
      );
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer(delay, () async {
      if (!_running) return;
      final summary = await pollOnce();
      _schedule(_nextDelay(summary));
    });
  }

  /// Drain fast while there is work, wait quietly when there is none, and back
  /// off when Cloud is not there — an offline restaurant must not spend its
  /// evening retrying every two seconds.
  Duration _nextDelay(EdgePollSummary summary) {
    switch (summary.outcome) {
      case EdgeTransportOutcome.ok:
        _consecutiveFailures = 0;
        return summary.claimed > 0 ? drainInterval : idleInterval;
      case EdgeTransportOutcome.unauthorized:
        _running = false;
        return idleInterval;
      case EdgeTransportOutcome.notProvisioned:
        _running = false;
        return idleInterval;
      case EdgeTransportOutcome.unreachable:
      case EdgeTransportOutcome.serverError:
        _consecutiveFailures = min(_consecutiveFailures + 1, 8);
        return _backoff();
    }
  }

  Duration _backoff() {
    final base = idleInterval.inMilliseconds * pow(2, _consecutiveFailures - 1);
    final capped = min(base.toDouble(), maxBackoff.inMilliseconds.toDouble());
    // Jitter so a restaurant's devices do not all retry on the same tick.
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return Duration(milliseconds: (capped * jitter).round());
  }
}

enum _HandledKind { executed, alreadyDone, unsupported }

class _Handled {
  const _Handled(this.kind, this.report);
  final _HandledKind kind;
  final EdgeCommandResult? report;
}
