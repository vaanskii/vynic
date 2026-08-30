import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/receipt_language_picker_dialog.dart';
import 'package:vynic/core/widgets/service_fee_adjust_dialog.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

typedef ReservationAction = Future<void> Function(Reservation reservation);

/// Home-screen reservations dashboard rendered in the same visual language as
/// the take-away section (header + metric grid + master/detail panes), instead
/// of the admin-panel list. Keeps the existing reservation actions and adds a
/// service-fee toggle and a receipt-print action for the pre-order.
class HomeReservationsSection extends StatefulWidget {
  const HomeReservationsSection({
    super.key,
    required this.user,
    required this.reservations,
    required this.onRefreshRequested,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
    this.canAssignTable = false,
    this.onEditReservation,
    this.onViewPreOrder,
    this.onManagePreOrder,
    this.onSendKitchenCheck,
    this.onAssignTable,
  });

  final User user;
  final List<Reservation> reservations;
  final Future<void> Function() onRefreshRequested;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;
  final bool canAssignTable;
  final ReservationAction? onEditReservation;
  final ReservationAction? onViewPreOrder;
  final ReservationAction? onManagePreOrder;
  final ReservationAction? onSendKitchenCheck;
  final ReservationAction? onAssignTable;

  @override
  State<HomeReservationsSection> createState() =>
      _HomeReservationsSectionState();
}

class _HomeReservationsSectionState extends State<HomeReservationsSection> {
  String? _selectedReservationId;

  /// Which pane a narrow window is showing: 0 = the queue, 1 = the selected
  /// booking. Wide windows show both and ignore this.
  int _narrowPane = 0;

  /// Per-reservation service-fee toggle and rate (UI/print only; reservations
  /// have no persistent service-fee field). Tap toggles on/off; long-press
  /// opens the adjust dialog to change the percentage.
  final Map<String, bool> _serviceFeeOn = {};
  final Map<String, double> _serviceFeeRate = {};

  // Shared POS tokens rather than this screen's own teal-and-slate set, so a
  // reservation looks the same here as it does on the floor and on an order.
  static const Color _accent = VynicFloorTokens.accentStrong;
  static const Color _success = VynicFloorTokens.accentText;
  static const Color _warning = VynicFloorTokens.occupiedValue;
  static const Color _danger = VynicFloorTokens.dangerText;
  static const Color _surface = VynicFloorTokens.panel;
  static const Color _surfaceAlt = VynicFloorTokens.metricFill;
  static const Color _outline = VynicFloorTokens.panelBorder;

  @override
  Widget build(BuildContext context) {
    final ordered = [...widget.reservations]
      ..sort((a, b) {
        final dateCmp = a.reservationDate.compareTo(b.reservationDate);
        if (dateCmp != 0) return dateCmp;
        final timeCmp = a.reservationTime.compareTo(b.reservationTime);
        if (timeCmp != 0) return timeCmp;
        return a.createdAt.compareTo(b.createdAt);
      });

    final today = DatabaseService.getCurrentDate();
    final todayCount = ordered.where((r) => _isSameDate(r, today)).length;
    final guestCount = ordered.fold<int>(0, (s, r) => s + r.numberOfGuests);
    final preOrderValue = ordered.fold<double>(
      0,
      (s, r) => s + _preOrderSubtotal(r),
    );

    Reservation? selected;
    if (ordered.isNotEmpty) {
      selected = ordered.firstWhere(
        (r) => r.id == _selectedReservationId,
        orElse: () => ordered.first,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final platformMobile =
            !kIsWeb && (Platform.isAndroid || Platform.isIOS);
        // Only a genuine phone/tablet gets the single-pane layout. Desktop
        // windows are never laid out below PosScaledSurface.designSize, so
        // the three-column layout always has the room it needs and never has
        // to fold anything away.
        final isCompact = platformMobile;

        if (isCompact) {
          // Two panes, one at a time, each filling the height. Stacking them
          // in a scroll pushed the detail below the fold, so tapping a
          // booking appeared to do nothing.
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(compact: true),
                const SizedBox(height: 12),
                _buildMetricGrid(
                  total: ordered.length,
                  todayCount: todayCount,
                  guestCount: guestCount,
                  preOrderValue: preOrderValue,
                  compact: true,
                ),
                const SizedBox(height: 12),
                if (ordered.isEmpty)
                  Expanded(child: _buildEmptyState())
                else ...[
                  PosPaneSwitch(
                    labels: const ['სია', 'დეტალები'],
                    selectedIndex: _narrowPane,
                    onSelected: (index) => setState(() => _narrowPane = index),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _narrowPane == 0
                        ? _buildQueuePanel(
                            reservations: ordered,
                            selected: selected,
                            compact: true,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildDetailPanel(
                                  reservation: selected,
                                  compact: true,
                                  footerActions: false,
                                ),
                              ),
                              if (selected != null) ...[
                                const SizedBox(height: 12),
                                _buildActionRail(selected),
                              ],
                            ],
                          ),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(compact: false),
              const SizedBox(height: 16),
              _buildMetricGrid(
                total: ordered.length,
                todayCount: todayCount,
                guestCount: guestCount,
                preOrderValue: preOrderValue,
                compact: false,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ordered.isEmpty
                    ? _buildEmptyState()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            // The rail takes a column of its own, so the
                            // queue gives up its wider setting to pay for it.
                            width: constraints.maxWidth < 1400 ? 330 : 380,
                            child: _buildQueuePanel(
                              reservations: ordered,
                              selected: selected,
                              compact: false,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildDetailPanel(
                              reservation: selected,
                              compact: false,
                              footerActions: false,
                            ),
                          ),
                          // What you can do with the selected booking gets its
                          // own rail, the way it does on an order. As a footer
                          // Wrap the same eight buttons reflowed into two or
                          // three ragged rows and their order changed with the
                          // window width, so nothing sat where you last left
                          // it. Below 1180 there is no room for a third
                          // column, so the footer comes back.
                          if (selected != null) ...[
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 250,
                              child: _buildActionRail(selected),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────── Header & metrics ─────────────────────────

  Widget _buildHeader({required bool compact}) {
    return const PosPageHeading(
      title: 'რეზერვაციები',
      subtitle: 'დაჯავშნული სუფრების მართვა და წინასწარი შეკვეთები.',
    );
  }

  Widget _buildMetricGrid({
    required int total,
    required int todayCount,
    required int guestCount,
    required double preOrderValue,
    required bool compact,
  }) {
    final metrics = [
      _ResMetric(
        icon: Icons.event_available_outlined,
        label: 'რეზერვაციები',
        value: '$total',
        helper: 'სულ',
        color: VynicFloorTokens.text,
      ),
      _ResMetric(
        icon: Icons.today_outlined,
        label: 'დღევანდელი',
        value: '$todayCount',
        helper: 'დღეს',
        color: VynicFloorTokens.text,
      ),
      _ResMetric(
        icon: Icons.groups_outlined,
        label: 'სტუმრები',
        value: '$guestCount',
        helper: 'სულ',
        color: VynicFloorTokens.text,
      ),
      _ResMetric(
        icon: Icons.restaurant_menu_outlined,
        label: 'წინასწარი შეკვეთა',
        value: '₾${preOrderValue.toStringAsFixed(2)}',
        helper: 'ჯამური',
        color: VynicFloorTokens.text,
      ),
    ];

    if (compact) {
      // Two across rather than four stacked: four full-width cards ate most
      // of a 700px-tall window before the panes below them got any height.
      return Column(
        children: [
          for (var row = 0; row < (metrics.length + 1) ~/ 2; row++) ...[
            if (row > 0) const SizedBox(height: 10),
            // IntrinsicHeight, not a stretched Row: this sits in a
            // Column with no height budget, and stretch needs a
            // bounded cross axis.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < 2; column++) ...[
                    if (column > 0) const SizedBox(width: 10),
                    Expanded(
                      child: row * 2 + column < metrics.length
                          ? _buildMetricCard(
                              metrics[row * 2 + column],
                              compact: true,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: metrics
          .map(
            (m) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: m == metrics.last ? 0 : 12),
                child: _buildMetricCard(m, compact: false),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMetricCard(_ResMetric metric, {required bool compact}) {
    return PosMetricCard(label: metric.label, value: metric.value);
  }

  Widget _buildQueuePanel({
    required List<Reservation> reservations,
    required Reservation? selected,
    required bool compact,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'დაჯავშნები (${reservations.length})',
                    style: TextStyle(
                      color: widget.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.swap_vert, color: widget.mutedText, size: 20),
              ],
            ),
          ),
          const Divider(height: 1, color: _outline),
          // One scrolling list in both layouts. The compact branch used to
          // render every card in a plain Column, which only worked while the
          // whole section sat inside an outer scroll view; in a
          // height-bounded pane it overflowed.
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: reservations.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = reservations[index];
                return _buildQueueCard(
                  reservation: r,
                  selected: r.id == selected?.id,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard({
    required Reservation reservation,
    required bool selected,
  }) {
    final statusColor = _statusColor(reservation.status);
    final statusLabel = _statusLabel(reservation.status);
    final itemCount = _itemCount(reservation);
    final total = _preOrderSubtotal(reservation);
    final name = _customerName(reservation);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _selectedReservationId = reservation.id;
        // On a narrow window, picking one is a request to see it.
        _narrowPane = 1;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.08) : _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _accent : _outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${reservation.numberOfGuests} სტუმარი',
                        style: TextStyle(
                          color: widget.textPrimary.withValues(alpha: 0.78),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₾${total.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: widget.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _buildStatusChip(statusLabel, statusColor),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule, size: 15, color: widget.mutedText),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${_formatDate(reservation.reservationDate)}, ${reservation.reservationTime}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: widget.mutedText, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.restaurant_menu_outlined,
                  size: 15,
                  color: widget.mutedText,
                ),
                const SizedBox(width: 5),
                Text(
                  '$itemCount პოზიცია',
                  style: TextStyle(color: widget.mutedText, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Detail pane ─────────────────────────

  Widget _buildDetailPanel({
    required Reservation? reservation,
    required bool compact,
    bool footerActions = true,
  }) {
    if (reservation == null) {
      return _buildEmptyState();
    }

    final statusColor = _statusColor(reservation.status);
    final statusLabel = _statusLabel(reservation.status);
    final items = reservation.preOrderItems ?? const <OrderItem>[];
    final subtotal = _preOrderSubtotal(reservation);
    final phone = reservation.customerPhone.trim();
    final notes = reservation.notes?.trim();
    final tableLabel = ReservationTableAvailability.tableNumbersLabel(
      reservation,
      placeholder: 'სუფრა არ არის',
    );

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18, compact ? 16 : 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _customerName(reservation),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.textPrimary,
                                fontSize: compact ? 20 : 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildStatusChip(statusLabel, statusColor),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.event_outlined,
                            color: widget.mutedText,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_formatDate(reservation.reservationDate)}, ${reservation.reservationTime}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.mutedText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _outline),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact)
                    Column(
                      children: [
                        _buildInfoBlock(
                          icon: Icons.person_outline,
                          title: _customerName(reservation),
                          subtitle: phone.isEmpty ? 'ტელეფონი არ არის' : phone,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoBlock(
                          icon: Icons.groups_outlined,
                          title: '${reservation.numberOfGuests} სტუმარი',
                          subtitle: 'სუფრა: $tableLabel',
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoBlock(
                            icon: Icons.person_outline,
                            title: _customerName(reservation),
                            subtitle: phone.isEmpty
                                ? 'ტელეფონი არ არის'
                                : phone,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildInfoBlock(
                            icon: Icons.groups_outlined,
                            title: '${reservation.numberOfGuests} სტუმარი',
                            subtitle: 'სუფრა: $tableLabel',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildInfoBlock(
                            icon: Icons.restaurant_menu_outlined,
                            title: 'პროდუქტები',
                            subtitle: '${_itemCount(reservation)} პოზიცია',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  _buildItemsTable(items),
                  const SizedBox(height: 14),
                  if (compact) ...[
                    _buildNotesBox(notes),
                    const SizedBox(height: 12),
                    _buildSummaryBox(reservation, subtotal),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildNotesBox(notes)),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _buildSummaryBox(reservation, subtotal),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          // Wide layouts move these into the rail beside the panel; anything
          // narrower has no room for a third column, so they stay as a footer.
          if (footerActions) ...[
            const Divider(height: 1, color: _outline),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _buildActions(reservation),
            ),
          ],
        ],
      ),
    );
  }

  /// The selected booking's actions, grouped by what they touch — the same
  /// shape as the order detail screen's right-hand rail.
  Widget _buildActionRail(Reservation reservation) {
    final hasPreOrder = (reservation.preOrderItems ?? const []).isNotEmpty;
    final serviceAvailable = DatabaseService.isServiceFeeAvailable();
    final serviceOn = _isServiceOn(reservation);

    final booking = <Widget>[
      if (widget.onEditReservation != null)
        PosActionButton(
          label: 'რეზერვაციის შეცვლა',
          icon: Icons.edit_outlined,
          expand: true,
          onTap: () => widget.onEditReservation!(reservation),
        ),
      if (widget.canAssignTable && widget.onAssignTable != null)
        PosActionButton(
          label: 'სუფრაზე გადაყვანა',
          icon: Icons.table_restaurant_outlined,
          tone: PosActionTone.caution,
          expand: true,
          onTap: () => widget.onAssignTable!(reservation),
        ),
    ];

    final preOrder = <Widget>[
      if (widget.onManagePreOrder != null)
        PosActionButton(
          label: 'მენიუს შეცვლა',
          icon: Icons.restaurant_menu,
          expand: true,
          onTap: () => widget.onManagePreOrder!(reservation),
        ),
      if (widget.onViewPreOrder != null)
        PosActionButton(
          label: 'მენიუს ნახვა',
          icon: Icons.visibility_outlined,
          expand: true,
          onTap: () => widget.onViewPreOrder!(reservation),
        ),
      if (serviceAvailable)
        PosActionButton(
          label: serviceOn
              ? 'სერვისი ${(_serviceRateFor(reservation) * 100).toStringAsFixed(_serviceRateFor(reservation) * 100 % 1 == 0 ? 0 : 1)}%'
              : 'სერვისი',
          icon: serviceOn ? Icons.room_service : Icons.room_service_outlined,
          tone: PosActionTone.money,
          expand: true,
          onTap: () => _toggleServiceFee(reservation),
          // Press and hold is the only way into the rate configuration.
          onLongPress: () => _openServiceFeeConfig(reservation),
          trailing: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: serviceOn
                    ? VynicFloorTokens.occupiedDot
                    : VynicFloorTokens.freeDot,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
    ];

    final kitchen = <Widget>[
      if (widget.onSendKitchenCheck != null)
        PosActionButton(
          label: 'სამზარეულოში გაგზავნა',
          icon: Icons.outbox_outlined,
          expand: true,
          onTap: hasPreOrder
              ? () => widget.onSendKitchenCheck!(reservation)
              : null,
        ),
      PosActionButton(
        label: 'ჩეკის ბეჭდვა',
        icon: Icons.receipt_long_outlined,
        expand: true,
        onTap: hasPreOrder ? () => _printReservationReceipt(reservation) : null,
      ),
    ];

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (booking.isNotEmpty)
            _RailGroup(title: 'რეზერვაცია', children: booking),
          if (preOrder.isNotEmpty)
            _RailGroup(title: 'მენიუ', children: preOrder),
          if (kitchen.isNotEmpty)
            _RailGroup(title: 'ბეჭდვა', children: kitchen),
        ],
      ),
    );
  }

  Widget _buildActions(Reservation reservation) {
    final hasPreOrder = (reservation.preOrderItems ?? const []).isNotEmpty;
    final serviceAvailable = DatabaseService.isServiceFeeAvailable();
    final serviceOn = _isServiceOn(reservation);

    final buttons = <Widget>[
      if (widget.onEditReservation != null)
        _actionButton(
          icon: Icons.edit_outlined,
          label: 'რეზერვაციის შეცვლა',
          primary: true,
          onTap: () => widget.onEditReservation!(reservation),
        ),
      if (widget.onManagePreOrder != null)
        _actionButton(
          icon: Icons.restaurant_menu,
          label: 'მენიუს შეცვლა',
          onTap: () => widget.onManagePreOrder!(reservation),
        ),
      if (widget.onViewPreOrder != null)
        _actionButton(
          icon: Icons.visibility_outlined,
          label: 'მენიუს ნახვა',
          onTap: () => widget.onViewPreOrder!(reservation),
        ),
      if (widget.canAssignTable && widget.onAssignTable != null)
        _actionButton(
          icon: Icons.table_restaurant_outlined,
          label: 'სუფრაზე გადაყვანა',
          onTap: () => widget.onAssignTable!(reservation),
        ),
      if (hasPreOrder && widget.onSendKitchenCheck != null)
        _actionButton(
          icon: Icons.outbox_outlined,
          label: 'სამზარეულოში გაგზავნა',
          onTap: () => widget.onSendKitchenCheck!(reservation),
        ),
      if (serviceAvailable)
        Tooltip(
          message: 'შეხება — ჩართვა/გამორთვა · ხანგრძლივი დაჭერა — შეცვლა',
          child: GestureDetector(
            onLongPress: () => _openServiceFeeConfig(reservation),
            child: _actionButton(
              icon: serviceOn
                  ? Icons.room_service
                  : Icons.room_service_outlined,
              label: serviceOn
                  ? 'სერვისი ${(_serviceRateFor(reservation) * 100).toStringAsFixed(_serviceRateFor(reservation) * 100 % 1 == 0 ? 0 : 1)}%'
                  : 'სერვისი',
              color: serviceOn ? _success : null,
              onTap: () => _toggleServiceFee(reservation),
            ),
          ),
        ),
      _actionButton(
        icon: Icons.receipt_long_outlined,
        label: 'ჩეკის ბეჭდვა',
        primary: true,
        onTap: hasPreOrder ? () => _printReservationReceipt(reservation) : null,
      ),
    ];

    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    Color? color,
  }) {
    return PosActionButton(
      label: label,
      icon: icon,
      onTap: onTap,
      // „primary" used to mean a filled teal button, and there were two of
      // them competing in the same Wrap. Both are money-shaped actions, so
      // they take the money tint and nothing on this row is filled.
      tone: primary || color != null
          ? PosActionTone.money
          : PosActionTone.neutral,
    );
  }

  Widget _buildItemsTable(List<OrderItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: _outline)),
            ),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildTableHeader('პროდუქტი')),
                Expanded(flex: 2, child: _buildTableHeader('რაოდენობა')),
                Expanded(flex: 2, child: _buildTableHeader('ფასი')),
                Expanded(flex: 2, child: _buildTableHeader('ჯამი')),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'წინასწარი შეკვეთა ჯერ არ არის',
                style: TextStyle(color: widget.mutedText, fontSize: 15),
              ),
            )
          else
            ...items.map(
              (item) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE8EDF4))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((item.comment ?? '').trim().isNotEmpty)
                            Text(
                              item.comment!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.mutedText,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${item.quantity}',
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₾${item.unitPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₾${item.total.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesBox(String? notes) {
    final hasNotes = notes != null && notes.isNotEmpty;
    return Container(
      height: 86,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      alignment: Alignment.topLeft,
      child: Text(
        hasNotes ? notes : 'შენიშვნა...',
        style: TextStyle(
          color: hasNotes
              ? widget.textPrimary
              : widget.mutedText.withValues(alpha: 0.75),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildSummaryBox(Reservation reservation, double subtotal) {
    final serviceOn =
        _isServiceOn(reservation) && DatabaseService.isServiceFeeAvailable();
    final rate = _serviceRateFor(reservation);
    final serviceFee = serviceOn
        ? double.parse((subtotal * rate).toStringAsFixed(2))
        : 0.0;
    final total = subtotal + serviceFee;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5F9),
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          _summaryRow('ქვეჯამი', subtotal, muted: true),
          if (serviceOn) ...[
            const SizedBox(height: 6),
            _summaryRow(
              'სერვისი (${(rate * 100).toStringAsFixed(rate * 100 % 1 == 0 ? 0 : 1)}%)',
              serviceFee,
              muted: true,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'სულ',
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '₾${total.toStringAsFixed(2)}',
                style: TextStyle(
                  color: widget.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool muted = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: muted ? widget.mutedText : widget.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '₾${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: widget.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBlock({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, color: widget.textPrimary.withValues(alpha: 0.78), size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: widget.mutedText, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    if (color == _danger) return PosStatusPill.alert(label);
    if (color == _success) return PosStatusPill.done(label);
    if (color == _warning) return PosStatusPill.active(label);
    return PosStatusPill.booked(label);
  }

  Widget _buildTableHeader(String label) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: widget.mutedText,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 48,
            color: widget.mutedText.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text(
            'რეზერვაციები არ არის',
            style: TextStyle(
              color: widget.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'დადასტურებული დაჯავშნები აქ გამოჩნდება',
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Actions: service & print ─────────────────────────

  bool _isServiceOn(Reservation reservation) =>
      _serviceFeeOn[reservation.id] ?? false;

  double _serviceRateFor(Reservation reservation) =>
      _serviceFeeRate[reservation.id] ?? DatabaseService.getServiceFeeRate();

  void _toggleServiceFee(Reservation reservation) {
    if (!DatabaseService.isServiceFeeAvailable()) {
      unawaited(showErrorToast(context, 'სერვისის საფასური მიუწვდომელია'));
      return;
    }
    setState(() {
      _serviceFeeOn[reservation.id] = !_isServiceOn(reservation);
    });
  }

  /// Long-press on the service button: change the service-fee percentage and
  /// include flag for this reservation (same dialog as the counted menu).
  Future<void> _openServiceFeeConfig(Reservation reservation) async {
    if (!DatabaseService.isServiceFeeAvailable()) {
      unawaited(showErrorToast(context, 'სერვისის საფასური მიუწვდომელია'));
      return;
    }
    final defaultPercent = DatabaseService.getServiceFeePercentage();
    final initialPercent = (_serviceRateFor(reservation) * 100).clamp(
      0.0,
      100.0,
    );

    final result = await showDialog<ServiceFeeAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ServiceFeeAdjustDialog(
        initialIncludeServiceFee: _isServiceOn(reservation),
        initialPercentage: initialPercent,
        defaultPercentage: defaultPercent,
      ),
    );
    if (result == null || !mounted) {
      return;
    }

    final normalizedPercent = double.parse(
      result.percentage.clamp(0.0, 100.0).toStringAsFixed(2),
    );
    setState(() {
      _serviceFeeOn[reservation.id] = result.includeServiceFee;
      _serviceFeeRate[reservation.id] = normalizedPercent / 100;
    });
    unawaited(showSuccessToast(context, 'სერვისის პარამეტრები განახლდა'));
  }

  Future<void> _printReservationReceipt(Reservation reservation) async {
    final items = reservation.preOrderItems ?? const <OrderItem>[];
    if (items.isEmpty) {
      unawaited(
        showErrorToast(context, 'ჩეკის დასაბეჭდად ჩანაწერები არ მოიძებნა'),
      );
      return;
    }

    final language = await ReceiptLanguagePickerDialog.show(context);
    if (language == null || !mounted) {
      return;
    }
    final isEnglish = language == 'en';

    final lines = <String>['---'];
    for (final item in items) {
      lines.add(
        '${item.quantity}x ${item.itemName} - ${item.total.toStringAsFixed(2)} GEL',
      );
      final comment = item.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        lines.add('  ⮑ $comment');
      }
    }

    final subtotal = _preOrderSubtotal(reservation);
    final includeService =
        DatabaseService.isServiceFeeAvailable() &&
        _isServiceOn(reservation) &&
        subtotal > 0;
    final rate = _serviceRateFor(reservation);
    final serviceFee = includeService
        ? double.parse((subtotal * rate).toStringAsFixed(2))
        : 0.0;
    final total = includeService ? subtotal + serviceFee : subtotal;

    final tableRefs = ReservationTableAvailability.tableRefsOf(reservation);
    final tableLabel = tableRefs.isEmpty
        ? null
        : tableRefs.map((ref) => ref.tableNumber).join(', ');

    PrinterService.printReceiptInBackground(
      items: lines,
      total: total,
      subtotal: subtotal,
      serviceFee: includeService ? serviceFee : null,
      includeServiceFee: includeService,
      tableNumber: tableLabel,
      language: language,
      receiptType: 'reservation',
      onComplete: (success) {
        if (!mounted) return;
        if (success) {
          unawaited(
            showSuccessToast(
              context,
              isEnglish ? 'Receipt printed' : 'ჩეკი დაიბეჭდა',
            ),
          );
        } else {
          unawaited(
            showErrorToast(
              context,
              isEnglish ? 'Printer unavailable' : 'პრინტერი მიუწვდომელია',
            ),
          );
        }
      },
    );
  }

  // ───────────────────────── Helpers ─────────────────────────

  double _preOrderSubtotal(Reservation reservation) {
    final items = reservation.preOrderItems ?? const <OrderItem>[];
    return items.fold<double>(0, (sum, item) => sum + item.total);
  }

  int _itemCount(Reservation reservation) {
    final items = reservation.preOrderItems ?? const <OrderItem>[];
    return items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  String _customerName(Reservation reservation) {
    final name = reservation.customerName.trim();
    return name.isEmpty ? 'რეზერვაცია' : name;
  }

  bool _isSameDate(Reservation reservation, DateTime other) {
    final d = reservation.reservationDate;
    return d.year == other.year && d.month == other.month && d.day == other.day;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return _accent;
      case 'completed':
        return _success;
      case 'cancelled':
      case 'canceled':
        return _danger;
      default:
        return _warning;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return 'დადასტურებული';
      case 'completed':
        return 'დასრულებული';
      case 'cancelled':
      case 'canceled':
        return 'გაუქმებული';
      case 'pending':
        return 'მოლოდინში';
      default:
        return 'მოლოდინში';
    }
  }
}

class _ResMetric {
  const _ResMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;
}

/// One titled block of rail buttons.
class _RailGroup extends StatelessWidget {
  const _RailGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: PosSectionLabel(title),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}
