import 'dart:developer' as developer;

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/audit/money_audit.dart';

/// What recovery did to one interrupted closure.
enum ClosureRecoveryAction {
  /// The sale was already written; the remaining bookkeeping was finished.
  finished,

  /// Nothing financial had happened and the order is still open, so the
  /// attempt was abandoned and the table stays on the floor.
  abandoned,

  /// The journal entry refers to an order that no longer exists and no sale
  /// was written. Nothing to do but close the entry out.
  orphaned,

  /// The Sale exists, but required Order data was unavailable or a post-Sale
  /// effect failed. The journal stays pending for the next startup retry.
  deferred,
}

class ClosureRecoveryOutcome {
  const ClosureRecoveryOutcome({
    required this.closureId,
    required this.orderId,
    required this.action,
  });

  final String closureId;
  final int orderId;
  final ClosureRecoveryAction action;
}

/// Finishes closures that a crash interrupted.
///
/// A closure writes to six Hive boxes and Hive has no transaction across
/// them. `CloseTableTransaction` records its intent and phase in the closure
/// journal before and after each write, which turns "the POS died mid-close"
/// from an untraceable half-state into one of exactly two situations:
///
/// - **The sale exists.** The money is recorded; what may be missing is the
///   order status, the freed tables, the completed reservation, the audit
///   entry and the recomputed daily total. All of those are safe to redo, so
///   recovery finishes them.
/// - **The sale does not exist.** No money was recorded. The order is still
///   open and its table still occupied, which is the correct state for an
///   order that was never settled — the attempt is abandoned and the staff
///   close the table again.
///
/// Recovery never writes a second sale: it looks the closure up in the sales
/// box by `closureId`, which is the durable fact, rather than trusting the
/// journal phase that a crash may have failed to advance.
class ClosureRecoveryService {
  ClosureRecoveryService._();

  /// Runs at startup, after boxes are open and migrations have run.
  static Future<List<ClosureRecoveryOutcome>> recoverPending() async {
    final pending = ClosureJournalRepository.pending();
    if (pending.isEmpty) return const [];

    developer.log(
      'Found ${pending.length} interrupted closure(s) to recover',
      name: 'closure_recovery',
    );

    final outcomes = <ClosureRecoveryOutcome>[];
    for (final entry in pending) {
      outcomes.add(await _recoverOne(entry));
    }

    return outcomes;
  }

  static Future<ClosureRecoveryOutcome> _recoverOne(
    ClosureJournalEntry entry,
  ) async {
    // The sales box, not the journal phase, is the authority on whether the
    // money was recorded — the phase write is the thing a crash is most
    // likely to have lost.
    final saleKey = SalesRepository.findSaleKeyByClosureId(entry.closureId);

    Order? order;
    try {
      order = DatabaseCore.orderBox!.values.firstWhere(
        (o) => o.orderId == entry.orderId,
      );
    } catch (_) {
      order = null;
    }

    if (saleKey == null) {
      // No sale: nothing was collected as far as the records are concerned.
      // Leave the order open and drop the attempt.
      if (order != null) {
        order.closureId = null;
        await order.save();
      }
      await ClosureJournalRepository.write(
        entry.copyWith(
          phase: ClosurePhase.completed,
          completedAt: DateTime.now(),
          // Abandoned, not settled. The entry stays for the record but stops
          // speaking for its order, so the staff can close that table.
          abandonedAt: DateTime.now(),
        ),
      );
      await _audit(
        entry,
        order == null
            ? ClosureRecoveryAction.orphaned
            : ClosureRecoveryAction.abandoned,
      );
      return ClosureRecoveryOutcome(
        closureId: entry.closureId,
        orderId: entry.orderId,
        action: order == null
            ? ClosureRecoveryAction.orphaned
            : ClosureRecoveryAction.abandoned,
      );
    }

    // The Sale is recorded, but without the Order the typed report, physical
    // floor, and genuine linked Reservation cannot be completed honestly.
    // Keep the journal pending rather than claiming success.
    if (order == null) {
      developer.log(
        'Closure ${entry.closureId}: Sale exists but Order ${entry.orderId} '
        'is unavailable; post-Sale completion deferred',
        name: 'closure_recovery',
      );
      return ClosureRecoveryOutcome(
        closureId: entry.closureId,
        orderId: entry.orderId,
        action: ClosureRecoveryAction.deferred,
      );
    }

    // This is the same journaled routine used by a normal close after its Sale
    // write. It never creates or rewrites the Sale.
    final completed = await CloseTableTransaction.completeExistingSale(
      entry: entry,
      order: order,
      saleRecordKey: saleKey,
      closedByName: entry.actorName,
    );
    if (!completed) {
      return ClosureRecoveryOutcome(
        closureId: entry.closureId,
        orderId: entry.orderId,
        action: ClosureRecoveryAction.deferred,
      );
    }

    await _audit(
      ClosureJournalRepository.find(entry.closureId) ?? entry,
      ClosureRecoveryAction.finished,
    );

    return ClosureRecoveryOutcome(
      closureId: entry.closureId,
      orderId: entry.orderId,
      action: ClosureRecoveryAction.finished,
    );
  }

  static Future<void> _audit(
    ClosureJournalEntry entry,
    ClosureRecoveryAction action,
  ) async {
    await MoneyAudit.closureRecovered(
      actorId: entry.actorId.isEmpty ? 'system' : entry.actorId,
      closureId: entry.closureId,
      orderId: entry.orderId,
      businessDate: entry.businessDate,
      grossSaleAmount: entry.grossSaleAmount,
      action: action.name,
    );
  }
}
