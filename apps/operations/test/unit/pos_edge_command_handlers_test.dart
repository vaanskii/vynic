import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/noop_edge_command_handler.dart';
import 'package:vynic/core/services/edge/pos_edge_command_handlers.dart';

/// What this build can actually be asked to do.
///
/// The queue only refuses a command type it does not know to be idempotent; it
/// has no idea whether the terminal has a handler for one. A type declared in
/// the contract with nothing here to run it would be claimed, refused,
/// redelivered, and eventually recorded as failed after ten attempts — a
/// restaurant operation silently going nowhere. So the two lists are asserted
/// against each other rather than kept in step by hand.
void main() {
  final registry = EdgeCommandRegistry(<EdgeCommandHandler>[
    const NoopEdgeCommandHandler(),
    ...posEdgeCommandHandlers,
  ]);

  test('every type the contract declares has a handler', () {
    final missing = EdgeCommandTypes.all
        .where((type) => !registry.supports(type))
        .toList();

    expect(
      missing,
      isEmpty,
      reason:
          'these types would be claimed and then refused: ${missing.join(', ')}',
    );
  });

  test('no handler answers to a type the contract does not declare', () {
    final unknown = registry.supportedTypes
        .where((type) => !EdgeCommandTypes.all.contains(type))
        .toList();

    // Cloud would never send one, so such a handler is dead code that reads
    // like a supported operation.
    expect(unknown, isEmpty);
  });

  test('one handler per type', () {
    final types = <String>[
      const NoopEdgeCommandHandler().type,
      ...posEdgeCommandHandlers.map((handler) => handler.type),
    ];

    expect(types.toSet().length, types.length);
  });

  test('the restaurant work is all here, not just the probe', () {
    expect(posEdgeCommandHandlers, hasLength(17));
    expect(
      registry.supportedTypes,
      containsAll(<String>[
        EdgeCommandTypes.orderUpdate,
        EdgeCommandTypes.orderCancel,
        EdgeCommandTypes.orderStatusUpdate,
        EdgeCommandTypes.takeawayOrderUpsert,
        EdgeCommandTypes.dineInOrderUpsert,
        EdgeCommandTypes.orderCheckPrint,
        EdgeCommandTypes.reservationCreate,
        EdgeCommandTypes.reservationStatusUpdate,
        EdgeCommandTypes.reservationDelete,
        EdgeCommandTypes.reservationCheckPrint,
        EdgeCommandTypes.countedMenuPrint,
        EdgeCommandTypes.expenseCreate,
        EdgeCommandTypes.staffCreate,
        EdgeCommandTypes.staffPinUpdate,
        EdgeCommandTypes.staffRoleUpdate,
        EdgeCommandTypes.staffRename,
        EdgeCommandTypes.staffDelete,
      ]),
    );
  });
}
