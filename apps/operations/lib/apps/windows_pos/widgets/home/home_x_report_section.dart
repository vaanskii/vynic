import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// The day's operational report.
///
/// Four figures across the top, then the takings broken down by waiter. The
/// old version wrapped each figure in its own tinted card — a different pastel
/// per tile — which made four equally important numbers look like four
/// unrelated things. They are one row of facts about one day, so they read as
/// one row.
class HomeXReportSection extends StatelessWidget {
  const HomeXReportSection({
    super.key,
    required this.dailySalesTotal,
    this.openedTablesAmount,
    required this.takeAwayCount,
    required this.activeWaitersCount,
    required this.waiterSummaries,
    this.closedTables = const [],
    this.soldItems = const [],
    required this.onPrintReport,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final double dailySalesTotal;
  final double? openedTablesAmount;
  final int takeAwayCount;
  final int activeWaitersCount;
  final List<Map<String, dynamic>> waiterSummaries;

  /// Every table closed today, newest first — with the times it was opened
  /// and paid, so the report says how the day actually ran and not only what
  /// it took.
  final List<XReportTableRow> closedTables;

  /// Everything sold today, rolled up by dish.
  final List<XReportSoldItem> soldItems;

  final VoidCallback onPrintReport;

  // Kept so every caller keeps compiling; the section draws from the shared
  // POS tokens now rather than from per-screen colours passed down.
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  static String _money(double value) => '${value.toStringAsFixed(2)} ₾';

  @override
  Widget build(BuildContext context) {
    final metrics = <PosMetricCard>[
      PosMetricCard(label: 'დღიური გაყიდვები', value: _money(dailySalesTotal)),
      if (openedTablesAmount != null)
        PosMetricCard(
          label: 'ღია მაგიდების თანხა',
          value: _money(openedTablesAmount!),
          // Money still on the floor, not yet taken — the one figure here
          // that is not settled.
          tone: VynicFloorTokens.occupiedValue,
        ),
      PosMetricCard(label: 'გატანები', value: '$takeAwayCount'),
      PosMetricCard(label: 'აქტიური ოფიციანტები', value: '$activeWaitersCount'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 860;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            narrow ? 14 : 20,
            16,
            narrow ? 14 : 20,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PosPageHeading(
                title: 'X ანგარიში',
                subtitle: 'მიმდინარე დღის ოპერატიული ანგარიში.',
                trailing: PosPrimaryButton(
                  label: 'ანგარიშის დაბეჭდვა',
                  icon: Icons.print_outlined,
                  onTap: onPrintReport,
                ),
              ),
              const SizedBox(height: 16),
              if (narrow)
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  metrics[i],
                ]
              else
                Row(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: metrics[i]),
                    ],
                  ],
                ),
              const SizedBox(height: 16),
              // The bill of the day and the kitchen's output are two views of
              // the same sales, so they sit side by side where there is room.
              if (narrow) ...[
                _ClosedTables(rows: closedTables),
                const SizedBox(height: 16),
                _SoldItems(items: soldItems),
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _ClosedTables(rows: closedTables),
                      ),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _SoldItems(items: soldItems)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              _WaiterSales(summaries: waiterSummaries),
            ],
          ),
        );
      },
    );
  }
}

/// Fiscal takings per waiter, ranked.
class _WaiterSales extends StatelessWidget {
  const _WaiterSales({required this.summaries});

  final List<Map<String, dynamic>> summaries;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const PosPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PosSectionLabel('ოფიციანტები'),
            SizedBox(height: 10),
            Text(
              'დღის ფისკალური გაყიდვები ჯერ არ არის',
              style: TextStyle(
                color: VynicFloorTokens.text,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'ჩამონათვალი გამოჩნდება პირველი გაფორმებული შეკვეთის შემდეგ.',
              style: TextStyle(
                color: VynicFloorTokens.textMuted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return PosPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PosSectionLabel('ოფიციანტების გაყიდვები'),
              const Spacer(),
              Text(
                '${summaries.length}',
                style: const TextStyle(
                  color: VynicFloorTokens.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < summaries.length; i++)
            _WaiterRow(rank: i + 1, summary: summaries[i], divided: i > 0),
        ],
      ),
    );
  }
}

class _WaiterRow extends StatelessWidget {
  const _WaiterRow({
    required this.rank,
    required this.summary,
    required this.divided,
  });

  final int rank;
  final Map<String, dynamic> summary;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final total = (summary['total'] as num?)?.toDouble() ?? 0;
    final orders = summary['orderCount'] ?? 0;

    return Container(
      decoration: divided
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: VynicFloorTokens.divider)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: VynicFloorTokens.sectionLabel,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${summary['username'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VynicFloorTokens.text,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$orders შეკვეთა',
            style: const TextStyle(
              color: VynicFloorTokens.textMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 104,
            child: Text(
              '${total.toStringAsFixed(2)} ₾',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: VynicFloorTokens.text,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _clock(DateTime? value) {
  if (value == null) return '—';
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// How long the table ran, from opened to paid.
String _span(DateTime? from, DateTime? to) {
  if (from == null || to == null) return '—';
  final minutes = to.difference(from).inMinutes;
  if (minutes < 0) return '—';
  if (minutes < 60) return '$minutes წთ';
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// An empty panel that says what would be here, rather than a blank box.
class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PosPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          PosSectionLabel(title),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: VynicFloorTokens.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Column caption inside a report panel.
class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.text, {this.width, this.align = TextAlign.right});

  final String text;
  final double? width;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: VynicFloorTokens.sectionLabel,
        fontSize: 11.5,
      ),
    );
    return width == null
        ? Expanded(child: label)
        : SizedBox(width: width, child: label);
  }
}

/// Every table closed today: who ran it, when it opened and closed, how long
/// it sat, how it paid and what it took.
class _ClosedTables extends StatelessWidget {
  const _ClosedTables({required this.rows});

  final List<XReportTableRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyPanel(
        title: 'დახურული მაგიდები',
        message: 'დღეს ჯერ არცერთი მაგიდა არ დახურულა.',
      );
    }

    return PosPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PosSectionLabel('დახურული მაგიდები'),
              const Spacer(),
              Text(
                '${rows.length}',
                style: const TextStyle(
                  color: VynicFloorTokens.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _ColumnLabel('მაგიდა', align: TextAlign.left),
              _ColumnLabel('გახსნა', width: 58),
              _ColumnLabel('დახურვა', width: 64),
              _ColumnLabel('ხანგრძ.', width: 62),
              _ColumnLabel('ჯამი', width: 88),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++)
            _ClosedTableRow(row: rows[i], divided: i > 0),
        ],
      ),
    );
  }
}

class _ClosedTableRow extends StatelessWidget {
  const _ClosedTableRow({required this.row, required this.divided});

  final XReportTableRow row;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    // A cancelled or non-fiscal closure still happened and still occupied the
    // table, so it stays on the list — greyed, and labelled for what it is.
    final struck = row.cancelled;
    final valueColor = struck
        ? VynicFloorTokens.textFaint
        : VynicFloorTokens.text;

    final meta = [
      if (row.waiter.isNotEmpty) row.waiter,
      '${row.itemCount} პოზიცია',
      if (row.payment.trim().isNotEmpty) row.payment.trim(),
      if (row.cancelled) 'გაუქმებული' else if (!row.fiscal) 'არაფისკალური',
    ].join(' · ');

    Widget cell(String text, double width) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: struck
                ? VynicFloorTokens.textFaint
                : VynicFloorTokens.textMuted,
            fontSize: 13,
          ),
        ),
      );
    }

    return Container(
      decoration: divided
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: VynicFloorTokens.divider)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.tables,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: struck ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicFloorTokens.textFaint,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          cell(_clock(row.openedAt), 58),
          cell(_clock(row.closedAt), 64),
          cell(_span(row.openedAt, row.closedAt), 62),
          SizedBox(
            width: 88,
            child: Text(
              '${row.total.toStringAsFixed(2)} ₾',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything that left the kitchen today, ranked by takings.
class _SoldItems extends StatelessWidget {
  const _SoldItems({required this.items});

  final List<XReportSoldItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyPanel(
        title: 'გაყიდული პროდუქტები',
        message: 'დღეს ჯერ არაფერი გაყიდულა.',
      );
    }

    final units = items.fold<int>(0, (sum, item) => sum + item.quantity);

    return PosPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PosSectionLabel('გაყიდული პროდუქტები'),
              const Spacer(),
              Text(
                '$units',
                style: const TextStyle(
                  color: VynicFloorTokens.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _ColumnLabel('დასახელება', align: TextAlign.left),
              _ColumnLabel('რაოდ.', width: 56),
              _ColumnLabel('ჯამი', width: 88),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++)
            Container(
              decoration: i > 0
                  ? const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: VynicFloorTokens.divider),
                      ),
                    )
                  : null,
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${items[i].quantity}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: Text(
                      '${items[i].total.toStringAsFixed(2)} ₾',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.textMuted,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
