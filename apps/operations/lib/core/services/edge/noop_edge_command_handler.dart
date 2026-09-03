import 'package:flutter/foundation.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';

/// The command that does nothing.
///
/// It exists so the whole path — claim, execute, journal, acknowledge — can be
/// exercised against a real restaurant install without performing restaurant
/// work. Every other command type waits until its own handler can absorb being
/// delivered twice.
class NoopEdgeCommandHandler implements EdgeCommandHandler {
  const NoopEdgeCommandHandler();

  @override
  String get type => EdgeCommandTypes.noop;

  @override
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command) async {
    // Debug only, and only the id — a payload may carry anything later.
    if (kDebugMode) {
      debugPrint('[Edge] NOOP ${command.commandId} (attempt ${command.attempt})');
    }
    return EdgeCommandResult.succeeded(command.commandId);
  }
}
