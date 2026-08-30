import 'package:flutter/material.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/ui/vynic_status_tokens.dart';

/// The single canonical mapping from [TableOperationalStatus] to what a table
/// tile shows (icon + Georgian label + presentation tone), reused by every
/// table-tile render mode (SVG map, floor plan, button grid) so they can't
/// drift from each other.
///
/// Per docs/UI_PLAN.md §3's colorblind rule, status is never color alone —
/// [icon] and [label] carry the distinction between Occupied and Reserved,
/// which used to be visually identical (`isReserved` was true for both).
/// Free tiles intentionally render without a badge (see `table_selection_widget.dart`)
/// — [label]/[icon] are still defined here for completeness and testability.
@immutable
class TableStatusPresentation {
  const TableStatusPresentation({
    required this.status,
    required this.vynicState,
    required this.label,
    required this.icon,
  });

  final TableOperationalStatus status;
  final VynicOperationalState vynicState;
  final String label;
  final IconData icon;

  bool get isFree => status == TableOperationalStatus.free;
  bool get isBusy => !isFree;

  static const _free = TableStatusPresentation(
    status: TableOperationalStatus.free,
    vynicState: VynicOperationalState.free,
    label: 'თავისუფალია',
    icon: Icons.table_restaurant_outlined,
  );

  static const _occupied = TableStatusPresentation(
    status: TableOperationalStatus.occupied,
    vynicState: VynicOperationalState.occupied,
    label: 'დაკავებულია',
    icon: Icons.receipt_long,
  );

  static const _reserved = TableStatusPresentation(
    status: TableOperationalStatus.reserved,
    vynicState: VynicOperationalState.reserved,
    label: 'დაჯავშნილია',
    icon: Icons.event_available,
  );

  static TableStatusPresentation forStatus(TableOperationalStatus status) {
    switch (status) {
      case TableOperationalStatus.free:
        return _free;
      case TableOperationalStatus.occupied:
        return _occupied;
      case TableOperationalStatus.reserved:
        return _reserved;
    }
  }

  /// Convenience: resolve straight from a (possibly missing) [TableModel].
  /// A null table (not found in the current layout/cache) presents as free.
  static TableStatusPresentation of(TableModel? table) =>
      forStatus(table?.operationalStatus ?? TableOperationalStatus.free);
}
