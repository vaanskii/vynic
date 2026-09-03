/// The restaurant operations Cloud may ask this POS to perform.
///
/// Each handler is a thin adapter: read the envelope's payload, hand it to
/// [PosCommandApplier], turn the outcome into a command result. The behaviour
/// itself is not here, because the legacy LAN callback server reaches the same
/// operations and the two transports must not drift into different restaurant
/// behaviour depending on which network path a request took.
///
/// ## Why the reconciliation flags are on for this transport
///
/// The LAN server reports *delivery* — the backend outbox marks a row delivered
/// when a POST returns 2xx — so a 404 for an order that is already gone is
/// useful information there. This transport reports *execution*, at-least-once,
/// with the queue keeping a terminal failure terminal. A redelivery finding the
/// work already done must therefore say "done", not "missing": a false failure
/// here becomes a command an operator has to go and re-issue by hand.
///
/// So the handlers below ask the applier to treat an already-satisfied goal
/// state as success. That is the same idempotency the contract declares for
/// each type, applied at the boundary that needs it.
library;

import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

/// Base for a handler that maps one payload onto one applier operation.
abstract class _AppliedEdgeCommandHandler implements EdgeCommandHandler {
  const _AppliedEdgeCommandHandler();

  Future<PosCommandOutcome> apply(Map<String, dynamic> payload);

  @override
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command) async {
    final raw = command.payload;
    final payload = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final outcome = await apply(payload);
    if (outcome.ok) {
      return EdgeCommandResult.succeeded(command.commandId, code: outcome.code);
    }
    return EdgeCommandResult.failed(
      command.commandId,
      code: outcome.code,
      detail: outcome.detail,
    );
  }
}

// ── Orders ───────────────────────────────────────────────────────────────────

class OrderUpdateEdgeHandler extends _AppliedEdgeCommandHandler {
  const OrderUpdateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.orderUpdate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.updateOrder(p);
}

class OrderCancelEdgeHandler extends _AppliedEdgeCommandHandler {
  const OrderCancelEdgeHandler();
  @override
  String get type => EdgeCommandTypes.orderCancel;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.cancelOrder(p, treatMissingAsDone: true);
}

class OrderStatusUpdateEdgeHandler extends _AppliedEdgeCommandHandler {
  const OrderStatusUpdateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.orderStatusUpdate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.updateOrderStatus(p);
}

class TakeawayOrderUpsertEdgeHandler extends _AppliedEdgeCommandHandler {
  const TakeawayOrderUpsertEdgeHandler();
  @override
  String get type => EdgeCommandTypes.takeawayOrderUpsert;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.upsertTakeawayOrder(p);
}

class DineInOrderUpsertEdgeHandler extends _AppliedEdgeCommandHandler {
  const DineInOrderUpsertEdgeHandler();
  @override
  String get type => EdgeCommandTypes.dineInOrderUpsert;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.upsertDineInOrder(p);
}

// ── Printing ─────────────────────────────────────────────────────────────────

class OrderCheckPrintEdgeHandler extends _AppliedEdgeCommandHandler {
  const OrderCheckPrintEdgeHandler();
  @override
  String get type => EdgeCommandTypes.orderCheckPrint;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.printOrderCheck(p);
}

class ReservationCheckPrintEdgeHandler extends _AppliedEdgeCommandHandler {
  const ReservationCheckPrintEdgeHandler();
  @override
  String get type => EdgeCommandTypes.reservationCheckPrint;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.printReservationCheck(p);
}

class CountedMenuPrintEdgeHandler extends _AppliedEdgeCommandHandler {
  const CountedMenuPrintEdgeHandler();
  @override
  String get type => EdgeCommandTypes.countedMenuPrint;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.printCountedMenu(p);
}

// ── Reservations ─────────────────────────────────────────────────────────────

class ReservationCreateEdgeHandler extends _AppliedEdgeCommandHandler {
  const ReservationCreateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.reservationCreate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.createReservation(p);
}

class ReservationStatusUpdateEdgeHandler extends _AppliedEdgeCommandHandler {
  const ReservationStatusUpdateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.reservationStatusUpdate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.updateReservationStatus(p);
}

class ReservationDeleteEdgeHandler extends _AppliedEdgeCommandHandler {
  const ReservationDeleteEdgeHandler();
  @override
  String get type => EdgeCommandTypes.reservationDelete;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.deleteReservation(p);
}

// ── Expenses ─────────────────────────────────────────────────────────────────

class ExpenseCreateEdgeHandler extends _AppliedEdgeCommandHandler {
  const ExpenseCreateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.expenseCreate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.createExpense(p);
}

// ── Staff ────────────────────────────────────────────────────────────────────

class StaffCreateEdgeHandler extends _AppliedEdgeCommandHandler {
  const StaffCreateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.staffCreate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.createStaff(p, treatExistingAsDone: true);
}

class StaffPinUpdateEdgeHandler extends _AppliedEdgeCommandHandler {
  const StaffPinUpdateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.staffPinUpdate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.updateStaffPin(p);
}

class StaffRoleUpdateEdgeHandler extends _AppliedEdgeCommandHandler {
  const StaffRoleUpdateEdgeHandler();
  @override
  String get type => EdgeCommandTypes.staffRoleUpdate;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.updateStaffRole(p);
}

class StaffRenameEdgeHandler extends _AppliedEdgeCommandHandler {
  const StaffRenameEdgeHandler();
  @override
  String get type => EdgeCommandTypes.staffRename;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.renameStaff(p, treatRenamedAsDone: true);
}

class StaffDeleteEdgeHandler extends _AppliedEdgeCommandHandler {
  const StaffDeleteEdgeHandler();
  @override
  String get type => EdgeCommandTypes.staffDelete;
  @override
  Future<PosCommandOutcome> apply(Map<String, dynamic> p) =>
      PosCommandApplier.deleteStaff(p, treatMissingAsDone: true);
}

/// Every restaurant operation this build can execute on Cloud's behalf.
///
/// The list is asserted against the generated contract in tests: a type the
/// contract declares and this build cannot run would sit in the queue being
/// claimed, refused and redelivered until its attempts ran out.
const List<EdgeCommandHandler> posEdgeCommandHandlers = <EdgeCommandHandler>[
  OrderUpdateEdgeHandler(),
  OrderCancelEdgeHandler(),
  OrderStatusUpdateEdgeHandler(),
  TakeawayOrderUpsertEdgeHandler(),
  DineInOrderUpsertEdgeHandler(),
  OrderCheckPrintEdgeHandler(),
  ReservationCreateEdgeHandler(),
  ReservationStatusUpdateEdgeHandler(),
  ReservationDeleteEdgeHandler(),
  ReservationCheckPrintEdgeHandler(),
  CountedMenuPrintEdgeHandler(),
  ExpenseCreateEdgeHandler(),
  StaffCreateEdgeHandler(),
  StaffPinUpdateEdgeHandler(),
  StaffRoleUpdateEdgeHandler(),
  StaffRenameEdgeHandler(),
  StaffDeleteEdgeHandler(),
];
