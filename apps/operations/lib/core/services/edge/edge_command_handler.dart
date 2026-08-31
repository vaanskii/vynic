import 'package:vynic/core/contracts/edge_command.dart';

/// Something the POS knows how to do on Cloud's behalf.
///
/// Handlers own the business behaviour; the transport owns delivery. Keeping
/// them apart is what stops the polling loop from growing a switch statement
/// that reaches into printers, menus and tables.
abstract class EdgeCommandHandler {
  /// The command type from the generated contract this handler answers to.
  String get type;

  /// Runs the command locally.
  ///
  /// Should not throw: a handler that fails is expected to say so through a
  /// failed result, which Cloud records with its reason. The transport still
  /// guards against a throw, because a handler that does will not be allowed to
  /// stop the POS.
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command);
}

/// The command types this build can execute.
class EdgeCommandRegistry {
  EdgeCommandRegistry(List<EdgeCommandHandler> handlers)
    : _handlers = <String, EdgeCommandHandler>{
        for (final handler in handlers) handler.type: handler,
      };

  final Map<String, EdgeCommandHandler> _handlers;

  EdgeCommandHandler? handlerFor(String type) => _handlers[type];

  bool supports(String type) => _handlers.containsKey(type);

  Set<String> get supportedTypes => _handlers.keys.toSet();
}
