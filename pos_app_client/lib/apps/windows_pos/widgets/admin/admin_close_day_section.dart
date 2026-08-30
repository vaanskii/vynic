import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/payment_utils.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

class AdminCloseDaySection extends StatefulWidget {
  const AdminCloseDaySection({
    super.key,
    required this.user,
    required this.onShowBusinessDateSelector,
    required this.formatDateTimeDisplay,
    this.onSetBusinessDateToToday,
  });

  final User user;
  final Future<void> Function() onShowBusinessDateSelector;
  final VoidCallback? onSetBusinessDateToToday;
  final String Function(DateTime) formatDateTimeDisplay;

  @override
  State<AdminCloseDaySection> createState() => _AdminCloseDaySectionState();
}

class _AdminCloseDaySectionState extends State<AdminCloseDaySection> {
  static const Color _primaryColor = AdminDesign.accentDark;
  static const Color _secondaryColor = AdminTones.infoText;
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = AdminDesign.border;
  static const Color _textPrimary = AdminDesign.text;
  static const Color _textMuted = AdminDesign.muted;

  @override
  Widget build(BuildContext context) {
    return _buildCloseDaySection();
  }

  Widget _buildCloseDaySection() {
    final allOrders = DatabaseService.getAllOrders();
    final closedOrders = allOrders.where((o) => o.status == 'closed').toList();
    final totalRevenue = closedOrders.fold<double>(
      0,
      (sum, order) => sum + order.totalAmount,
    );
    final openTableOrders = _getTodayOpenTableOrders();
    final summary = _computeDaySummary();
    final readiness = _computeReadiness(openTableOrders);

    return LayoutBuilder(
      builder: (context, viewport) {
        final isWide = viewport.maxWidth >= 900;

        final statsCard = Card(
          margin: EdgeInsets.zero,
          color: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'დღის სტატისტიკა',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.receipt_long,
                        label: 'დახურული შეკვეთები',
                        value: '${closedOrders.length}',
                        color: _primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.attach_money,
                        label: 'მთლიანი შემოსავალი',
                        value: '₾${totalRevenue.toStringAsFixed(2)}',
                        color: AdminTones.successText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'დღის დახურვა',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            if (isWide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildBusinessDateManagementCard()),
                    const SizedBox(width: 16),
                    Expanded(child: statsCard),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBusinessDateManagementCard(),
                  const SizedBox(height: 12),
                  statsCard,
                ],
              ),
            const SizedBox(height: 12),
            if (isWide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _buildDaySummaryCard(summary)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildReadinessCard(readiness)),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDaySummaryCard(summary),
                  const SizedBox(height: 12),
                  _buildReadinessCard(readiness),
                ],
              ),
            const SizedBox(height: 12),
            // The last row absorbs whatever height is left, so a wide POS
            // screen ends on a full card instead of a band of empty page.
            if (isWide)
              Expanded(
                child: _buildActionsAndOpenTablesSection(
                  openTableOrders,
                  isWide,
                ),
              )
            else
              _buildActionsAndOpenTablesSection(openTableOrders, isWide),
          ],
        );

        const padding = EdgeInsets.fromLTRB(22, 18, 22, 12);

        if (!isWide) {
          return SingleChildScrollView(
            padding: padding,
            child: SizedBox(width: double.infinity, child: content),
          );
        }

        // Fill the viewport when the content is shorter than it, scroll when
        // it is taller. IntrinsicHeight is what gives the [Expanded] above a
        // bounded height to divide.
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (viewport.maxHeight - padding.vertical).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: IntrinsicHeight(
              child: SizedBox(width: double.infinity, child: content),
            ),
          ),
        );
      },
    );
  }

  // ── Day summary ────────────────────────────────────────────────────────────

  /// The day's takings, split by payment method.
  ///
  /// Counts a sale the same way [DatabaseService.getDailySalesTotal] does —
  /// fiscal, not cancelled, not restored back to an open order — so the split
  /// adds up to the total shown beside it. Records the total leaves out are
  /// not dropped silently: they come back as [_DaySummary.nonFiscalTotal] and
  /// [_DaySummary.excludedCount] and get their own line on the card.
  _DaySummary _computeDaySummary() {
    final businessDate = DatabaseService.getCurrentDate();
    final dateKey = businessDate.toIso8601String().split('T')[0];
    final rawSales = DatabaseService.getSalesForDate(dateKey);

    var cash = 0.0;
    var cardTbc = 0.0;
    var cardBog = 0.0;
    var other = 0.0;
    final cashOrders = <int>{};
    final cardTbcOrders = <int>{};
    final cardBogOrders = <int>{};
    final otherOrders = <int>{};

    var discountTotal = 0.0;
    var advanceTotal = 0.0;
    var serviceFeeOrders = 0;
    var nonFiscalTotal = 0.0;
    var nonFiscalCount = 0;
    var excludedCount = 0;
    var activeCount = 0;

    for (final sale in rawSales) {
      final isCancelled = sale['isCancelled'] == true;
      final isRestored = sale['restoredToOrder'] == true;
      if (isCancelled || isRestored) {
        excludedCount++;
        continue;
      }

      if (!_isFiscalSale(sale)) {
        nonFiscalCount++;
        nonFiscalTotal += (sale['totalAmount'] as num?)?.toDouble() ?? 0.0;
        continue;
      }

      activeCount++;
      discountTotal += (sale['discountAmount'] as num?)?.toDouble() ?? 0.0;
      advanceTotal += (sale['advanceAmount'] as num?)?.toDouble() ?? 0.0;
      if (sale['includeServiceFee'] == true) serviceFeeOrders++;

      final orderId = sale['orderId'] as int?;
      final breakdown = PaymentUtils.extractBreakdown(sale);
      breakdown.forEach((methodKey, amount) {
        switch (PaymentUtils.normalizeMethodKey(methodKey)) {
          case PaymentUtils.methodCardTbc:
          case PaymentUtils.methodCardLegacy:
            cardTbc += amount;
            if (orderId != null) cardTbcOrders.add(orderId);
            break;
          case PaymentUtils.methodCardBog:
            cardBog += amount;
            if (orderId != null) cardBogOrders.add(orderId);
            break;
          case PaymentUtils.methodCash:
            cash += amount;
            if (orderId != null) cashOrders.add(orderId);
            break;
          default:
            other += amount;
            if (orderId != null) otherOrders.add(orderId);
            break;
        }
      });
    }

    return _DaySummary(
      businessDate: businessDate,
      fiscalTotal: DatabaseService.getDailySalesTotal(),
      saleCount: activeCount,
      cash: cash,
      cardTbc: cardTbc,
      cardBog: cardBog,
      other: other,
      cashCount: cashOrders.length,
      cardTbcCount: cardTbcOrders.length,
      cardBogCount: cardBogOrders.length,
      otherCount: otherOrders.length,
      discountTotal: discountTotal,
      advanceTotal: advanceTotal,
      serviceFeeOrders: serviceFeeOrders,
      nonFiscalTotal: nonFiscalTotal,
      nonFiscalCount: nonFiscalCount,
      excludedCount: excludedCount,
    );
  }

  Widget _buildDaySummaryCard(_DaySummary s) {
    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.summarize_outlined,
                  size: 20,
                  color: _primaryColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'დღის შეჯამება',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  DatabaseService.getGeorgianFormattedDate(s.businessDate),
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₾${s.fiscalTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${s.saleCount} გაყიდვა · საშუალო ჩეკი '
                      '₾${s.averageCheck.toStringAsFixed(2)}',
                      style: const TextStyle(color: _textMuted, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildPaymentShareBar(s),
            const SizedBox(height: 14),
            _buildPaymentRow(
              'ნაღდი',
              s.cash,
              s.cashCount,
              s.paymentTotal,
              AdminTones.successText,
            ),
            _buildPaymentRow(
              'ბარათი TBC',
              s.cardTbc,
              s.cardTbcCount,
              s.paymentTotal,
              _primaryColor,
            ),
            _buildPaymentRow(
              'ბარათი BOG',
              s.cardBog,
              s.cardBogCount,
              s.paymentTotal,
              AdminTones.warningText,
            ),
            if (s.other > 0)
              _buildPaymentRow(
                'სხვა',
                s.other,
                s.otherCount,
                s.paymentTotal,
                _secondaryColor,
              ),
            const SizedBox(height: 4),
            const Divider(height: 18, color: _borderColor),
            _buildSummaryLine(
              'ფასდაკლება',
              '₾${s.discountTotal.toStringAsFixed(2)}',
            ),
            _buildSummaryLine(
              'ავანსი',
              '₾${s.advanceTotal.toStringAsFixed(2)}',
            ),
            _buildSummaryLine(
              'მომსახურების საფასურით',
              '${s.serviceFeeOrders} შეკვეთა',
            ),
            if (s.nonFiscalCount > 0)
              _buildSummaryLine(
                'არაფისკალური (ჯამში არ შედის)',
                '${s.nonFiscalCount} · ₾${s.nonFiscalTotal.toStringAsFixed(2)}',
                valueColor: AdminTones.warningText,
              ),
            if (s.excludedCount > 0)
              _buildSummaryLine(
                'გაუქმებული / დაბრუნებული',
                '${s.excludedCount} ჩანაწერი',
                valueColor: AdminTones.dangerText,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentShareBar(_DaySummary s) {
    final total = s.paymentTotal;
    final segments = <(double, Color)>[
      (s.cash, AdminTones.successText),
      (s.cardTbc, _primaryColor),
      (s.cardBog, AdminTones.warningText),
      (s.other, _secondaryColor),
    ].where((segment) => segment.$1 > 0).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: total <= 0 || segments.isEmpty
            ? Container(color: AdminTones.neutralFill)
            : Row(
                children: [
                  for (final segment in segments)
                    Expanded(
                      flex: (segment.$1 / total * 1000).round().clamp(1, 1000),
                      child: Container(color: segment.$2),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPaymentRow(
    String label,
    double amount,
    int count,
    double total,
    Color color,
  ) {
    final share = total > 0 ? amount / total * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 46,
            child: Text(
              '${share.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              '₾${amount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryLine(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _textMuted, fontSize: 12.5),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Pre-close readiness ────────────────────────────────────────────────────

  /// What would block [_confirmCloseDay], checked live and without changing
  /// anything.
  ///
  /// Mirrors the close flow's own checks (steps 1 and 2) so the answer here is
  /// the answer you get when you press the button. One deliberate difference:
  /// the close flow calls `releaseStaleReservedTables()` before counting
  /// reserved tables and this does not — a read on a rebuild must not mutate
  /// the floor — so the reserved-table count is an upper bound and its row
  /// says so.
  List<_ReadinessItem> _computeReadiness(List<Order> openTableOrders) {
    final businessDate = DatabaseService.getCurrentDate();
    final dateKey = businessDate.toIso8601String().split('T')[0];

    final openOrders = DatabaseService.getAllOrders().where((order) {
      final status = order.status.toLowerCase();
      if (status == 'closed' || status == 'cancelled') return false;
      return order.createdAt.toIso8601String().split('T')[0] == dateKey;
    }).toList();
    final openOrderIds = openOrders.map((o) => o.orderId).toSet();
    final openTakeAwayOrders = openOrders.where(_isTakeAwayOrder).toList();

    final openTakeAwayReservations =
        DatabaseService.getTakeAwayReservationsForDate(businessDate).where((r) {
          final status = r.status.toLowerCase();
          return status != 'completed' && status != 'cancelled';
        }).toList();

    final reservedTables = DatabaseService.getAllTables().where((table) {
      if (!table.isReserved) return false;
      final orderId = table.activeOrderId;
      if (orderId != null && openOrderIds.contains(orderId)) return false;
      if (orderId == null && table.reservationId == null) return false;
      return true;
    }).toList();

    return [
      _ReadinessItem(
        icon: Icons.table_restaurant,
        title: 'ღია მაგიდები',
        blockingDetail:
            '${openTableOrders.length} შეკვეთა ჯერ კიდევ აქტიურია — '
            'დახურეთ ან გააუქმეთ',
        clearDetail: 'ყველა მაგიდა დახურულია',
        count: openTableOrders.length,
        onOpen: openTableOrders.isEmpty
            ? null
            : () => _showOpenTablesModal(openTableOrders),
      ),
      _ReadinessItem(
        icon: Icons.shopping_bag_outlined,
        title: 'გატანის შეკვეთები',
        blockingDetail: '${openTakeAwayOrders.length} შეკვეთა დაუხურავია',
        clearDetail: 'გატანის ღია შეკვეთა არ არის',
        count: openTakeAwayOrders.length,
      ),
      _ReadinessItem(
        icon: Icons.assignment_outlined,
        title: 'გატანის რეზერვაციები',
        blockingDetail:
            '${openTakeAwayReservations.length} რეზერვაცია დასრულებული არ არის',
        clearDetail: 'ყველა რეზერვაცია დასრულებულია',
        count: openTakeAwayReservations.length,
      ),
      _ReadinessItem(
        icon: Icons.event_seat,
        title: 'დარეზერვებული მაგიდები',
        blockingDetail:
            '${reservedTables.length} მაგიდა რეზერვაციაშია — '
            'ვადაგასულები დახურვისას ავტომატურად თავისუფლდება',
        clearDetail: 'დაკავებული რეზერვაცია არ არის',
        count: reservedTables.length,
      ),
    ];
  }

  Widget _buildReadinessCard(List<_ReadinessItem> items) {
    final blocking = items.where((item) => item.count > 0).length;
    final ready = blocking == 0;

    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready
                      ? Icons.check_circle_outline
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: ready
                      ? AdminTones.successText
                      : AdminTones.warningText,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'დახურვის მზადყოფნა',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh, size: 18),
                  color: _textMuted,
                  tooltip: 'განახლება',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ready
                  ? 'ყველა შემოწმება გავლილია — დღის დახურვა შესაძლებელია.'
                  : '$blocking შემოწმება ხელს უშლის დახურვას.',
              style: TextStyle(
                color: ready ? AdminTones.successText : AdminTones.warningText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in items) _buildReadinessRow(item),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessRow(_ReadinessItem item) {
    final blocking = item.count > 0;
    final tone = blocking ? AdminTones.warning : AdminTones.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: tone.fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 17, color: tone.text),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blocking ? item.blockingDetail : item.clearDetail,
                    style: const TextStyle(color: _textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              blocking ? Icons.remove_circle_outline : Icons.check_rounded,
              size: 16,
              color: tone.text,
            ),
            if (item.onOpen != null) ...[
              const SizedBox(width: 4),
              SizedBox(
                height: 28,
                child: TextButton(
                  onPressed: item.onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: _primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'ნახვა',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// [isWide] comes from the section's own LayoutBuilder rather than a nested
  /// one. A LayoutBuilder here would sit inside the [IntrinsicHeight] that
  /// stretches this row, and intrinsic dimensions cannot be measured through a
  /// LayoutBuilder — the tab threw on every wide screen when it did.
  Widget _buildActionsAndOpenTablesSection(
    List<Order> openOrders,
    bool isWide,
  ) {
    final actionsCard = _buildActionsCard();
    final openTablesCard = _buildOpenTablesAccessCard(openOrders);

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: actionsCard),
          const SizedBox(width: 12),
          Expanded(child: openTablesCard),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [actionsCard, const SizedBox(height: 12), openTablesCard],
    );
  }

  Widget _buildBusinessDateManagementCard() {
    final currentBusinessDate = DatabaseService.getCurrentDate();
    final now = DateTime.now();

    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'მიმდინარე სამუშაო დღე',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'თარიღი: ${DatabaseService.getGeorgianFormattedDate(currentBusinessDate)}',
              style: const TextStyle(color: _textMuted, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              'მოწყობილობის დრო: ${widget.formatDateTimeDisplay(now)}',
              style: const TextStyle(color: _textMuted, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              'დამახსოვრებული ბიზნეს თარიღი: ${widget.formatDateTimeDisplay(currentBusinessDate)}',
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    unawaited(widget.onShowBusinessDateSelector());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTones.infoBorder,
                    foregroundColor: _textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.history_toggle_off),
                  label: const Text('სხვა თარიღის არჩევა'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onSetBusinessDateToToday,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _secondaryColor,
                    side: const BorderSide(color: _secondaryColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.today),
                  label: const Text('მიმდინარე დღე'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'ოპერაციები',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'რეკომენდებული რიგი: Z რეპორტი → დღის დახურვა. პრობლემისას გამოიყენეთ აღდგენის ღილაკები.',
              style: TextStyle(color: _textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 260,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _printZReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.print, size: 18),
                label: const Text(
                  'Z რეპორტი',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 260,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _confirmCloseDay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _secondaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.lock_clock, size: 18),
                label: const Text(
                  'დღის დახურვა',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textMuted, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  bool _isTakeAwayOrder(Order order) {
    final floorLabel = order.floor.toLowerCase();
    if (floorLabel == 'takeaway' ||
        floorLabel == 'take-away' ||
        floorLabel.contains('take away')) {
      return true;
    }
    return order.tableNumbers.any((table) {
      final normalized = table.toLowerCase();
      return normalized.startsWith('ta-') || normalized.contains('take away');
    });
  }

  bool _isFiscalSale(Map<String, dynamic> sale) {
    final isFiscal = sale['isFiscal'];
    if (isFiscal is bool) {
      return isFiscal;
    }
    return true;
  }

  List<Order> _getTodayOpenTableOrders() {
    final currentDateKey = DatabaseService.getCurrentDate()
        .toIso8601String()
        .split('T')[0];
    final allOrders = DatabaseService.getAllOrders();

    final openOrders = allOrders.where((order) {
      final status = order.status.toLowerCase();
      if (status == 'closed' || status == 'cancelled') {
        return false;
      }

      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      if (orderDateKey != currentDateKey) {
        return false;
      }

      if (_isTakeAwayOrder(order)) {
        return false;
      }

      return order.tableNumbers.any((table) => table.trim().isNotEmpty);
    }).toList();

    openOrders.sort((a, b) => a.orderId.compareTo(b.orderId));
    return openOrders;
  }

  Future<bool> _deleteOrderPermanently(int orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminDesign.text,
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: AdminDesign.danger, size: 30),
            SizedBox(width: 12),
            Text('შეკვეთის წაშლა', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'შეკვეთა #$orderId წაიშლება და მაგიდები გათავისუფლდება. მოქმედება შეუქცევადია.',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminDesign.danger,
            ),
            child: const Text(
              'დასტური',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return false;
    }

    final success = await DatabaseService.deleteOrderAndCleanup(
      orderId: orderId,
      deletedBy: widget.user.username,
    );

    if (!mounted) return false;

    if (success) {
      unawaited(
        showSuccessToast(
          context,
          'შეკვეთა #$orderId წაიშალა და მაგიდები გათავისუფლდა',
        ),
      );
      setState(() {});
      return true;
    } else {
      unawaited(
        showErrorToast(context, 'შეკვეთის წაშლა ვერ მოხერხდა. სცადეთ თავიდან.'),
      );
      return false;
    }
  }

  Widget _buildOpenTablesAccessCard(List<Order> openOrders) {
    final total = openOrders.length;

    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AdminTones.warningText,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ღია მაგიდები',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        total == 0
                            ? 'მოთხოვნები არ არის'
                            : 'აქტიური შეკვეთები: $total',
                        style: const TextStyle(color: _textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    total == 0
                        ? 'ყველა მაგიდა დახურულია.'
                        : 'აღმოჩენილია $total ღია შეკვეთა მაგიდებზე.',
                    style: const TextStyle(color: _textMuted, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: total == 0
                        ? null
                        : () => _showOpenTablesModal(openOrders),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: AdminTones.infoBorder),
                      backgroundColor: AdminTones.infoFill,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text(
                      'ნახვა',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOpenTablesModal(List<Order> openOrders) async {
    final modalOrders = List<Order>.from(openOrders);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: _borderColor),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.table_restaurant,
                    color: AdminTones.warningText,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ღია მაგიდები (${modalOrders.length})',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 720,
                child: modalOrders.isEmpty
                    ? const Text(
                        'ღია მაგიდები არ მოიძებნა.',
                        style: TextStyle(color: _textMuted, fontSize: 14),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: modalOrders
                              .map(
                                (order) => _buildOpenOrderRow(
                                  order,
                                  onDelete: () async {
                                    final deleted =
                                        await _deleteOrderPermanently(
                                          order.orderId,
                                        );
                                    if (!deleted || !mounted) {
                                      return;
                                    }

                                    setModalState(() {
                                      modalOrders.removeWhere(
                                        (entry) =>
                                            entry.orderId == order.orderId,
                                      );
                                    });
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'დახურვა',
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOpenOrderRow(
    Order order, {
    required Future<void> Function() onDelete,
  }) {
    final tables = order.tableNumbers.isEmpty
        ? '—'
        : order.tableNumbers.join(', ');
    final createdTime =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: AdminTones.warningFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTones.warningFill),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.table_restaurant,
            color: AdminTones.warningText,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'შეკვეთა #${order.orderId} • სტატუსი: ${order.status}',
                  style: const TextStyle(
                    color: AdminTones.warningText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'მაგიდა: $tables • დრო: $createdTime',
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: () {
                unawaited(onDelete());
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminDesign.danger,
                side: const BorderSide(color: VynicFloorTokens.dangerBorder),
                backgroundColor: VynicFloorTokens.dangerFill,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'წაშლა',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printZReport() async {
    try {
      final currentDate = DatabaseService.getCurrentDate();
      final georgianDate = DatabaseService.getGeorgianFormattedDate(
        currentDate,
      );
      final dailyTotal = DatabaseService.getDailySalesTotal();
      final dateString = currentDate.toIso8601String().split('T')[0];
      final rawSales = DatabaseService.getSalesForDate(dateString);
      final sales = rawSales.where(_isFiscalSale).toList();
      final allOrders = DatabaseService.getAllOrders();
      final closedOrders = allOrders
          .where((o) => o.status == 'closed')
          .toList();

      final StringBuffer report = StringBuffer();
      report.writeln('╔═══════════════════════════════════╗');
      report.writeln('║             Z რეპორტი             ║');
      report.writeln('║      დღის დახურვის ანგარიში      ║');
      report.writeln('╚═══════════════════════════════════╝');
      report.writeln();
      report.writeln('თარიღი: $georgianDate');
      report.writeln(
        'დრო: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      );
      report.writeln('-----------------------------------');
      report.writeln();
      report.writeln('დღიური გაყიდვების შეჯამება');
      report.writeln('===================================');
      report.writeln('გაყიდვების ჯამი: ₾${dailyTotal.toStringAsFixed(2)}');
      report.writeln('შეკვეთების რაოდენობა: ${sales.length}');
      report.writeln('დახურული შეკვეთები: ${closedOrders.length}');
      report.writeln();

      double cardTbcTotal = 0;
      double cardBogTotal = 0;
      double cashTotal = 0;
      double otherTotal = 0;
      final cardTbcOrders = <int>{};
      final cardBogOrders = <int>{};
      final cashOrders = <int>{};
      final otherOrders = <int>{};

      for (final sale in sales) {
        final orderId = sale['orderId'] as int?;
        final breakdown = PaymentUtils.extractBreakdown(sale);
        if (breakdown.isEmpty) continue;

        breakdown.forEach((methodKey, amount) {
          final normalized = PaymentUtils.normalizeMethodKey(methodKey);
          switch (normalized) {
            case PaymentUtils.methodCardTbc:
              cardTbcTotal += amount;
              if (orderId != null) cardTbcOrders.add(orderId);
              break;
            case PaymentUtils.methodCardBog:
              cardBogTotal += amount;
              if (orderId != null) cardBogOrders.add(orderId);
              break;
            case PaymentUtils.methodCardLegacy:
              cardTbcTotal += amount;
              if (orderId != null) cardTbcOrders.add(orderId);
              break;
            case PaymentUtils.methodCash:
              cashTotal += amount;
              if (orderId != null) cashOrders.add(orderId);
              break;
            case PaymentUtils.methodOther:
              otherTotal += amount;
              if (orderId != null) otherOrders.add(orderId);
              break;
          }
        });
      }

      final cardTbcCount = cardTbcOrders.length;
      final cardBogCount = cardBogOrders.length;
      final cashCount = cashOrders.length;
      final otherCount = otherOrders.length;
      final totalCardCount = cardTbcCount + cardBogCount;
      final totalCardAmount = cardTbcTotal + cardBogTotal;

      report.writeln('გადახდების განაწილება');
      report.writeln('===================================');
      report.writeln();
      report.writeln('TBC ბარათი:');
      report.writeln('  რაოდენობა: $cardTbcCount');
      report.writeln('  თანხა: ₾${cardTbcTotal.toStringAsFixed(2)}');
      report.writeln();
      report.writeln('BOG ბარათი:');
      report.writeln('  რაოდენობა: $cardBogCount');
      report.writeln('  თანხა: ₾${cardBogTotal.toStringAsFixed(2)}');
      report.writeln();
      report.writeln('ბარათით გადახდების რაოდენობა: $totalCardCount');
      report.writeln(
        'ბარათით გადახდების თანხა: ₾${totalCardAmount.toStringAsFixed(2)}',
      );
      report.writeln();
      report.writeln('-----------------------------------');
      report.writeln();
      report.writeln('ნაღდი გადახდები:');
      report.writeln('  რაოდენობა: $cashCount');
      report.writeln('  თანხა: ₾${cashTotal.toStringAsFixed(2)}');
      report.writeln();
      if (otherCount > 0 || otherTotal > 0) {
        report.writeln('სხვა გადახდები:');
        report.writeln('  რაოდენობა: $otherCount');
        report.writeln('  თანხა: ₾${otherTotal.toStringAsFixed(2)}');
        report.writeln();
      }
      report.writeln('===================================');
      report.writeln('სრული ჯამი: ₾${dailyTotal.toStringAsFixed(2)}');
      report.writeln('===================================');
      report.writeln();

      report.writeln('გაყიდვების დეტალები');
      report.writeln('-----------------------------------');
      for (int i = 0; i < sales.length && i < 20; i++) {
        final sale = sales[i];
        final tableNumbers = (sale['tableNumbers'] as List).join(', ');
        final paymentMethod = PaymentUtils.formatPaymentDisplay(sale);
        final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
        report.writeln('შეკვეთა ${i + 1}:');
        report.writeln('  მაგიდები: $tableNumbers');
        report.writeln('  გადახდა: $paymentMethod');
        report.writeln('  თანხა: ₾${total.toStringAsFixed(2)}');
        report.writeln();
      }

      if (sales.length > 20) {
        report.writeln('... და კიდევ ${sales.length - 20} შეკვეთა');
        report.writeln();
      }

      report.writeln('===================================');
      report.writeln('* Z ანგარიში');

      final success = await PrinterService.printTextReport(
        report.toString(),
        reportType: 'Z REPORT',
      );

      if (mounted) {
        if (success) {
          unawaited(showSuccessToast(context, 'Z რეპორტი წარმატებით დაიბეჭდა'));
        } else {
          unawaited(showErrorToast(context, 'Z რეპორტის ბეჭდვა ვერ მოხერხდა'));
        }
      }
    } catch (e) {
      if (mounted) {
        unawaited(showErrorToast(context, 'Z რეპორტის ბეჭდვის შეცდომა: $e'));
      }
    }
  }

  Future<void> _confirmCloseDay() async {
    if (!mounted) return;

    final currentBusinessDate = DatabaseService.getCurrentDate();
    final operatedDates = DatabaseService.getOperatedBusinessDates();
    if (operatedDates.isNotEmpty) {
      final lastOperated = operatedDates.last;
      final currentOnly = DateTime(
        currentBusinessDate.year,
        currentBusinessDate.month,
        currentBusinessDate.day,
      );
      final lastOnly = DateTime(
        lastOperated.year,
        lastOperated.month,
        lastOperated.day,
      );

      // Prevent closing a manually backdated day (older than last operated day).
      if (currentOnly.isBefore(lastOnly)) {
        await _showBackdatedCloseBlockedDialog(currentOnly, lastOnly);
        return;
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      builder: (dialogContext) {
        // phase: 0=confirm, 1=loading, 2=blocked
        int phase = 0;
        int step = 0;
        List<_BlockReason> blockReasons = [];
        const loadingSteps = [
          'მონაცემების წაკითხვა...',
          'შეკვეთების შემოწმება...',
          'მაგიდების გათავისუფლება...',
          'გაყიდვების შენახვა...',
          'შემდეგ დღეზე გადასვლა...',
        ];

        return StatefulBuilder(
          builder: (ctx, setS) {
            void runClose() {
              setS(() {
                phase = 1;
                step = 0;
              });

              Future<void> doWork() async {
                // ── Step 0: read data ──
                if (ctx.mounted) setS(() => step = 0);
                await Future.delayed(const Duration(milliseconds: 450));

                final currentDate = DatabaseService.getCurrentDate();
                final currentDateKey = currentDate.toIso8601String().split(
                  'T',
                )[0];
                final allOrders = DatabaseService.getAllOrders();
                final openOrders = allOrders.where((order) {
                  final status = order.status.toLowerCase();
                  if (status == 'closed' || status == 'cancelled') return false;
                  return order.createdAt.toIso8601String().split('T')[0] ==
                      currentDateKey;
                }).toList();
                final openOrderIds = openOrders.map((o) => o.orderId).toSet();

                // ── Step 1: check open orders ──
                if (ctx.mounted) setS(() => step = 1);
                await Future.delayed(const Duration(milliseconds: 450));

                final openTableOrders = openOrders.where((order) {
                  if (_isTakeAwayOrder(order)) return false;
                  return order.tableNumbers.any((t) => t.trim().isNotEmpty);
                }).toList();
                final openTakeAwayOrders = openOrders
                    .where(_isTakeAwayOrder)
                    .toList();

                if (openTableOrders.isNotEmpty ||
                    openTakeAwayOrders.isNotEmpty) {
                  await Future.delayed(const Duration(milliseconds: 300));
                  final reasons = <_BlockReason>[];
                  if (openTableOrders.isNotEmpty) {
                    reasons.add(
                      _BlockReason(
                        Icons.table_restaurant,
                        'ღია მაგიდები',
                        '${openTableOrders.length} შეკვეთა ჯერ კიდევ აქტიურია',
                      ),
                    );
                  }
                  if (openTakeAwayOrders.isNotEmpty) {
                    reasons.add(
                      _BlockReason(
                        Icons.shopping_bag_outlined,
                        'გატანის შეკვეთები',
                        '${openTakeAwayOrders.length} შეკვეთა დაუხურავია',
                      ),
                    );
                  }
                  if (ctx.mounted) {
                    setS(() {
                      blockReasons = reasons;
                      phase = 2;
                    });
                  }
                  return;
                }

                // ── Step 2: release stale tables & check reservations ──
                if (ctx.mounted) setS(() => step = 2);
                await Future.delayed(const Duration(milliseconds: 450));

                await DatabaseService.releaseStaleReservedTables();

                final openTakeAwayReservations =
                    DatabaseService.getTakeAwayReservationsForDate(
                      currentDate,
                    ).where((r) {
                      final s = r.status.toLowerCase();
                      return s != 'completed' && s != 'cancelled';
                    }).toList();
                final reservedTables = DatabaseService.getAllTables().where((
                  table,
                ) {
                  if (!table.isReserved) return false;
                  final oid = table.activeOrderId;
                  if (oid != null && openOrderIds.contains(oid)) return false;
                  if (oid == null && table.reservationId == null) return false;
                  return true;
                }).toList();

                if (openTakeAwayReservations.isNotEmpty ||
                    reservedTables.isNotEmpty) {
                  await Future.delayed(const Duration(milliseconds: 300));
                  final reasons = <_BlockReason>[];
                  if (openTakeAwayReservations.isNotEmpty) {
                    reasons.add(
                      _BlockReason(
                        Icons.assignment_outlined,
                        'გატანის რეზერვაციები',
                        '${openTakeAwayReservations.length} რეზერვაცია დასრულებული არ არის',
                      ),
                    );
                  }
                  if (reservedTables.isNotEmpty) {
                    reasons.add(
                      _BlockReason(
                        Icons.event_seat,
                        'დარეზერვებული მაგიდები',
                        '${reservedTables.length} მაგიდა რეზერვაციაშია',
                      ),
                    );
                  }
                  if (ctx.mounted) {
                    setS(() {
                      blockReasons = reasons;
                      phase = 2;
                    });
                  }
                  return;
                }

                // ── Step 3: save sales / close ──
                if (ctx.mounted) setS(() => step = 3);
                final closeFuture = DatabaseService.closeDay();
                await Future.delayed(const Duration(milliseconds: 500));

                // ── Step 4: advance day ──
                if (ctx.mounted) setS(() => step = 4);
                await Future.delayed(const Duration(milliseconds: 400));

                final closingSuccess = await closeFuture;

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  if (closingSuccess) {
                    // Immediately push new business date to backend so mobile
                    // dashboard switches to the new day without waiting for
                    // the 2-minute periodic sync timer.
                    unawaited(ManagerSyncService.syncToManagerApp());
                    setState(() {});
                    await _showCurrentBusinessDateDialog();
                  } else {
                    unawaited(
                      showErrorToast(
                        context,
                        'დღის დახურვა შეუძლებელია!\nდახურეთ ყველა აქტიური ჩანაწერი',
                      ),
                    );
                  }
                }
              }

              unawaited(doWork());
            }

            // ── Blocked view (phase 2) ──
            if (phase == 2) {
              return Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 8,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFEA580C,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.block_rounded,
                                color: AdminTones.warningText,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'დახურვა შეუძლებელია',
                                    style: TextStyle(
                                      color: AdminDesign.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'გთხოვთ გადაწყვიტოთ შემდეგი პრობლემები',
                                    style: TextStyle(
                                      color: AdminDesign.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AdminTones.warningFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AdminTones.warningBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'დახურვის ხელშეშლის მიზეზები:',
                                style: TextStyle(
                                  color: AdminTones.warningText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...blockReasons.map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        r.icon,
                                        size: 18,
                                        color: AdminTones.warningText,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.title,
                                              style: const TextStyle(
                                                color: AdminDesign.text,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              r.detail,
                                              style: const TextStyle(
                                                color: AdminDesign.muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminDesign.accentDark,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: const Text('დახურვა'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ── Loading view (phase 1) ──
            if (phase == 1) {
              return Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 8,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 48,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E3A8A,
                            ).withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AdminDesign.accentDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'დახურვა მიმდინარეობს...',
                          style: TextStyle(
                            color: AdminDesign.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'გთხოვთ დაელოდოთ',
                          style: TextStyle(
                            color: AdminDesign.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (step + 1) / loadingSteps.length,
                            minHeight: 6,
                            backgroundColor: AdminDesign.border,
                            color: AdminDesign.accentDark,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...loadingSteps.asMap().entries.map((e) {
                          final i = e.key;
                          final label = e.value;
                          final isDone = i < step;
                          final isCurrent = i == step;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDone
                                        ? AdminTones.successText
                                        : isCurrent
                                        ? const Color(
                                            0xFF1E3A8A,
                                          ).withValues(alpha: 0.12)
                                        : AdminDesign.panelSoft,
                                    border: isCurrent
                                        ? Border.all(
                                            color: AdminDesign.accentDark,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: isDone
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : isCurrent
                                      ? const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AdminDesign.accentDark,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: isDone
                                        ? AdminTones.successText
                                        : isCurrent
                                        ? AdminDesign.text
                                        : VynicFloorTokens.textFaint,
                                    fontSize: 13,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ── Confirmation view ──
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1E3A8A,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.lock_clock,
                              color: AdminDesign.accentDark,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'დღის დახურვა',
                                  style: TextStyle(
                                    color: AdminDesign.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'გთხოვთ, დაადასტუროთ მოქმედება',
                                  style: TextStyle(
                                    color: AdminDesign.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: VynicFloorTokens.textFaint,
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AdminDesign.panelSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AdminDesign.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ეს მოქმედება:',
                              style: TextStyle(
                                color: AdminDesign.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildActionPoint(
                              Icons.table_restaurant_outlined,
                              'ყველა მაგიდა გათავისუფლდება',
                            ),
                            _buildActionPoint(
                              Icons.save_outlined,
                              'გაყიდვების ჩანაწერები შეინახება',
                            ),
                            _buildActionPoint(
                              Icons.skip_next_outlined,
                              'სისტემა გადაინაცვლებს შემდეგ სამუშაო დღეზე',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AdminTones.warningFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminTones.warningBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: AdminTones.warningText,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'ეს ქმედება შეუქცევადია. Z-რეპორტის ბეჭდვა გირჩევნია.',
                                style: TextStyle(
                                  color: AdminTones.warningText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AdminDesign.muted,
                                side: const BorderSide(
                                  color: VynicFloorTokens.textFaint,
                                ),
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('გაუქმება'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: runClose,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AdminDesign.accentDark,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.lock_clock, size: 16),
                              label: const Text('დახურვა'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showBackdatedCloseBlockedDialog(
    DateTime currentDate,
    DateTime lastOperatedDate,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFEA580C,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: AdminTones.warningText,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'დღის დახურვა დაბლოკილია',
                          style: TextStyle(
                            color: AdminDesign.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'ამ თარიღზე დახურვა შეუძლებელია, რადგან უკვე არსებობს უფრო ახალი დახურული დღე.',
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'მიმდინარე თარიღი: ${DatabaseService.getGeorgianFormattedDate(currentDate)}\nბოლო ოპერირებული თარიღი: ${DatabaseService.getGeorgianFormattedDate(lastOperatedDate)}',
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'შეცვალეთ ბიზნეს თარიღი ბოლო ოპერირებულ დღეზე ან მიმდინარე დღეზე და შემდეგ სცადეთ ისევ.',
                    style: TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminDesign.accentDark,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('გასაგებია'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCurrentBusinessDateDialog() async {
    if (!mounted) return;

    final currentDate = DatabaseService.getCurrentDate();
    final georgianDate = DatabaseService.getGeorgianFormattedDate(currentDate);
    final numericDate =
        '${currentDate.day.toString().padLeft(2, '0')}.${currentDate.month.toString().padLeft(2, '0')}.${currentDate.year}';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _borderColor),
          ),
          title: const Row(
            children: [
              Icon(Icons.calendar_today, color: _primaryColor, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'დღე წარმატებით დაიხურა',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'მიმდინარე ბიზნესის თარიღია:',
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                georgianDate,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                numericDate,
                style: const TextStyle(color: _primaryColor, fontSize: 14),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('დახურვა'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionPoint(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AdminDesign.accentDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AdminDesign.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockReason {
  const _BlockReason(this.icon, this.title, this.detail);
  final IconData icon;
  final String title;
  final String detail;
}

/// One line of the day-summary card's payment split, plus the figures the
/// total deliberately leaves out.
class _DaySummary {
  const _DaySummary({
    required this.businessDate,
    required this.fiscalTotal,
    required this.saleCount,
    required this.cash,
    required this.cardTbc,
    required this.cardBog,
    required this.other,
    required this.cashCount,
    required this.cardTbcCount,
    required this.cardBogCount,
    required this.otherCount,
    required this.discountTotal,
    required this.advanceTotal,
    required this.serviceFeeOrders,
    required this.nonFiscalTotal,
    required this.nonFiscalCount,
    required this.excludedCount,
  });

  final DateTime businessDate;

  /// The stored daily total — fiscal, not cancelled, not restored.
  final double fiscalTotal;
  final int saleCount;

  final double cash;
  final double cardTbc;
  final double cardBog;
  final double other;

  final int cashCount;
  final int cardTbcCount;
  final int cardBogCount;
  final int otherCount;

  final double discountTotal;
  final double advanceTotal;
  final int serviceFeeOrders;

  /// Non-fiscal takings. Real money, but outside [fiscalTotal] by design.
  final double nonFiscalTotal;
  final int nonFiscalCount;

  /// Cancelled or restored-to-order records, excluded from every figure above.
  final int excludedCount;

  /// The split's own sum. Used for the share bar and the per-method
  /// percentages, so a rounding gap against [fiscalTotal] cannot push a
  /// percentage past 100.
  double get paymentTotal => cash + cardTbc + cardBog + other;

  double get averageCheck => saleCount == 0 ? 0 : fiscalTotal / saleCount;
}

/// One check on the pre-close readiness card.
class _ReadinessItem {
  const _ReadinessItem({
    required this.icon,
    required this.title,
    required this.blockingDetail,
    required this.clearDetail,
    required this.count,
    this.onOpen,
  });

  final IconData icon;
  final String title;

  /// Shown when [count] is above zero, i.e. this check would block the close.
  final String blockingDetail;
  final String clearDetail;
  final int count;

  /// Optional jump to wherever the blockage is fixed.
  final VoidCallback? onOpen;
}
