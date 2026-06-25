import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/services/database_service.dart';

typedef ReservationAsyncAction = Future<void> Function(Reservation reservation);

class ReservationsManagementSection extends StatelessWidget {
  final List<Reservation> reservations;
  final DateTime normalizedToday;
  final DateTime? filterDate;
  final String statusFilter;
  final ValueChanged<DateTime?> onFilterDateChanged;
  final ValueChanged<String> onStatusFilterChanged;
  final VoidCallback? onCreateReservation;
  final bool canAssignTableToReservation;
  final bool canCancelReservation;
  final bool canDeleteReservation;
  final ReservationAsyncAction? onEditReservation;
  final ReservationAsyncAction? onViewPreOrder;
  final ReservationAsyncAction? onManagePreOrder;
  final ReservationAsyncAction? onSendKitchenCheck;
  final ReservationAsyncAction? onAssignTable;
  final ReservationAsyncAction? onAssignTableUnavailable;
  final ReservationAsyncAction? onCancelReservation;
  final ReservationAsyncAction? onDeleteReservation;
  final bool showCancelledTab;

  /// Reservation id to visually highlight (e.g. just arrived from mobile).
  final String? highlightReservationId;
  final String title;
  final String subtitle;
  final String createTitle;
  final String createDescription;
  final String createButtonLabel;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;
  final bool showHeader;

  const ReservationsManagementSection({
    super.key,
    required this.reservations,
    required this.normalizedToday,
    required this.filterDate,
    required this.statusFilter,
    required this.onFilterDateChanged,
    required this.onStatusFilterChanged,
    this.onCreateReservation,
    this.canAssignTableToReservation = false,
    this.canCancelReservation = false,
    this.canDeleteReservation = false,
    this.onEditReservation,
    this.onViewPreOrder,
    this.onManagePreOrder,
    this.onSendKitchenCheck,
    this.onAssignTable,
    this.onAssignTableUnavailable,
    this.onCancelReservation,
    this.onDeleteReservation,
    this.showCancelledTab = true,
    this.highlightReservationId,
    this.title = 'რეზერვაციების მართვა',
    this.subtitle =
        'შექმენი და მართე რეზერვაციები, გადაინაცვლე შეკვეთასა და სამზარეულოს მომზადებას შორის.',
    this.createTitle = 'ახალი რეზერვაციის შექმნა',
    this.createDescription =
        'მოამზადე მაგიდები სტუმრებისთვის წინასწარ. დაამატე კომენტარები და სპეციალური მოთხოვნები.',
    this.createButtonLabel = 'რეზერვაციის დამატება',
    this.primaryColor = const Color(0xFF1E3A8A),
    this.secondaryColor = const Color(0xFF2563EB),
    this.textPrimary = const Color(0xFF1F2937),
    this.mutedText = const Color(0xFF475569),
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    bool hasStatus(Reservation reservation, String target) {
      final normalized = _normalizeReservationStatus(reservation.status);
      return normalized == target || normalized.startsWith('$target-');
    }

    bool isCancelled(Reservation reservation) {
      final normalized = _normalizeReservationStatus(reservation.status);
      return normalized.startsWith('cancelled') ||
          normalized.startsWith('canceled');
    }

    final reservationsForDate = filterDate == null
        ? reservations
        : reservations
              .where(
                (reservation) =>
                    _isSameReservationDate(reservation, filterDate!),
              )
              .toList();

    final confirmedReservations = reservationsForDate
        .where((reservation) => hasStatus(reservation, 'confirmed'))
        .toList();
    final cancelledReservations = reservationsForDate
        .where(isCancelled)
        .toList();
    final confirmed = confirmedReservations.length;
    final cancelled = cancelledReservations.length;

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Scrollbar(
      thumbVisibility: !isMobile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isMobile ? 16 : 24,
          isMobile ? 16 : 24,
          isMobile ? 16 : 24,
          96,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              _buildSectionTitle(
                icon: Icons.event_available,
                title: title,
                subtitle: subtitle,
                isMobile: isMobile,
              ),
              SizedBox(height: isMobile ? 16 : 20),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildMetricTile(
                  icon: Icons.check_circle_outline,
                  label: 'დადასტურებული',
                  value: confirmed.toString(),
                  backgroundColor: const Color(0xFFE0F2FE),
                  iconColor: primaryColor,
                  isMobile: isMobile,
                ),
                _buildMetricTile(
                  icon: Icons.cancel_outlined,
                  label: 'გაუქმებული',
                  value: cancelled.toString(),
                  backgroundColor: const Color(0xFFFFEBEE),
                  iconColor: const Color(0xFFB91C1C),
                  isMobile: isMobile,
                ),
                _buildMetricTile(
                  icon: Icons.people_outline,
                  label: 'სტუმრები',
                  value: reservationsForDate
                      .fold<int>(
                        0,
                        (total, reservation) =>
                            total + reservation.numberOfGuests,
                      )
                      .toString(),
                  backgroundColor: const Color(0xFFF5F3FF),
                  iconColor: secondaryColor,
                  isMobile: isMobile,
                ),
              ],
            ),
            if (onCreateReservation != null) ...[
              SizedBox(height: isMobile ? 16 : 24),
              _buildActionCard(
                icon: Icons.event_note_outlined,
                title: createTitle,
                description: createDescription,
                isMobile: isMobile,
                actions: [
                  _buildPrimaryActionButton(
                    label: createButtonLabel,
                    icon: Icons.add_circle_outline,
                    onPressed: onCreateReservation!,
                  ),
                ],
              ),
            ],
            SizedBox(height: isMobile ? 16 : 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: filterDate ?? normalizedToday,
                      firstDate: normalizedToday.subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: normalizedToday.add(const Duration(days: 365)),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            colorScheme: ColorScheme.light(
                              primary: secondaryColor,
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: textPrimary,
                            ),
                            dialogTheme: DialogThemeData(
                              backgroundColor: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked == null) {
                      return;
                    }
                    onFilterDateChanged(_normalizeDateOnly(picked));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textPrimary,
                    side: BorderSide(
                      color: primaryColor.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    filterDate == null
                        ? 'ყველა თარიღი'
                        : DatabaseService.getGeorgianFormattedDate(filterDate!),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => onFilterDateChanged(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: filterDate == null
                        ? primaryColor
                        : mutedText,
                    side: BorderSide(
                      color: (filterDate == null ? primaryColor : mutedText)
                          .withValues(alpha: 0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('ყველა'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (showCancelledTab) ...[
              Row(
                children: [
                  _buildReservationFilterButton(
                    label: 'დადასტურებული',
                    isActive: statusFilter == 'confirmed',
                    onTap: () => onStatusFilterChanged('confirmed'),
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(width: 10),
                  _buildReservationFilterButton(
                    label: 'გაუქმებული',
                    isActive: statusFilter == 'cancelled',
                    onTap: () => onStatusFilterChanged('cancelled'),
                    primaryColor: primaryColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Builder(
              builder: (context) {
                final filtered = !showCancelledTab
                    ? confirmedReservations
                    : statusFilter == 'cancelled'
                    ? cancelledReservations
                    : confirmedReservations;

                if (filtered.isEmpty) {
                  return _buildReservationEmptyState();
                }

                return Column(
                  children: filtered
                      .map(
                        (reservation) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _buildReservationListCard(
                            context,
                            reservation,
                            isMobile,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReservationListCard(
    BuildContext context,
    Reservation reservation,
    bool isMobile,
  ) {
    final statusColor = _reservationStatusColor(reservation.status);
    final statusLabel = _reservationStatusLabel(reservation.status);
    final isToday = _isSameDate(
      reservation.reservationDate,
      DatabaseService.getCurrentDate(),
    );
    final canAssignTable = canAssignTableToReservation && isToday;
    final customerName = reservation.customerName.trim().isEmpty
        ? 'რეზერვაცია'
        : reservation.customerName.trim();
    final customerPhone = reservation.customerPhone.trim();
    final notes = reservation.notes?.trim();
    final tableNumbers = reservation.tableNumbers;
    final hasTables = tableNumbers.isNotEmpty;
    final guestCount = reservation.numberOfGuests;
    final preOrderItems = reservation.preOrderItems ?? const [];
    final itemCount = preOrderItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final reservationDateLabel = DatabaseService.getGeorgianFormattedDate(
      reservation.reservationDate,
    );

    Widget buildManagePreOrderButton() {
      return OutlinedButton.icon(
        onPressed: onManagePreOrder == null
            ? null
            : () => onManagePreOrder!(reservation),
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          disabledForegroundColor: Colors.black26,
          side: BorderSide(color: primaryColor.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('მენიუს შეცვლა'),
      );
    }

    final isHighlighted =
        highlightReservationId != null &&
        reservation.id == highlightReservationId;
    const highlightColor = Color(0xFFF59E0B);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? highlightColor
              : primaryColor.withValues(alpha: 0.08),
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? highlightColor.withValues(alpha: 0.18)
                : primaryColor.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: mutedText),
                        const SizedBox(width: 6),
                        Text(
                          reservationDateLabel,
                          style: TextStyle(
                            color: mutedText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isToday) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: mutedText.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.schedule, size: 16, color: mutedText),
                          const SizedBox(width: 6),
                          Text(
                            reservation.reservationTime,
                            style: TextStyle(
                              color: mutedText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isToday) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 16, color: mutedText),
                          const SizedBox(width: 6),
                          Text(
                            reservation.reservationTime,
                            style: TextStyle(
                              color: mutedText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 16, color: mutedText),
                        const SizedBox(width: 6),
                        Text(
                          '$guestCount სტუმარი',
                          style: TextStyle(color: mutedText, fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.phone_outlined, size: 16, color: mutedText),
                        const SizedBox(width: 6),
                        Text(
                          customerPhone.isEmpty ? '-' : customerPhone,
                          style: TextStyle(color: mutedText, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 8 : 10,
                  vertical: isMobile ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                hasTables ? Icons.table_restaurant : Icons.event_available,
                size: 16,
                color: mutedText,
              ),
              const SizedBox(width: 6),
              Text(
                hasTables
                    ? 'სუფრები: ${tableNumbers.join(', ')}'
                    : 'სუფრები: -',
                style: TextStyle(color: mutedText, fontSize: 13),
              ),
              if (itemCount > 0) ...[
                const SizedBox(width: 12),
                Icon(Icons.restaurant_menu, size: 16, color: mutedText),
                const SizedBox(width: 6),
                Text(
                  'მენიუ: $itemCount',
                  style: TextStyle(color: mutedText, fontSize: 13),
                ),
              ],
            ],
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(notes, style: TextStyle(color: textPrimary, fontSize: 13)),
          ],
          if (!_isCancelledStatus(reservation.status)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (onEditReservation != null)
                  OutlinedButton.icon(
                    onPressed: () => onEditReservation!(reservation),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(
                        color: primaryColor.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('რეზერვაციის შეცვლა'),
                  ),
                if (onViewPreOrder != null)
                  OutlinedButton.icon(
                    onPressed: () => onViewPreOrder!(reservation),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(
                        color: primaryColor.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('მენიუს ნახვა'),
                  ),
                if (onManagePreOrder != null) buildManagePreOrderButton(),
                if (preOrderItems.isNotEmpty && onSendKitchenCheck != null)
                  OutlinedButton.icon(
                    onPressed: () => onSendKitchenCheck!(reservation),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(
                        color: primaryColor.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.local_dining_outlined, size: 18),
                    label: const Text('სამზარეულოში გაგზავნა'),
                  ),
                if (canAssignTableToReservation && onAssignTable != null)
                  OutlinedButton.icon(
                    onPressed: canAssignTable
                        ? () => onAssignTable!(reservation)
                        : (onAssignTableUnavailable == null
                              ? null
                              : () => onAssignTableUnavailable!(reservation)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: secondaryColor,
                      side: BorderSide(
                        color: secondaryColor.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.table_restaurant, size: 18),
                    label: const Text('სუფრაზე გადაყვანა'),
                  ),
                if (canCancelReservation &&
                    onCancelReservation != null &&
                    !_isCancelledStatus(reservation.status))
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showCancelConfirmation(context, reservation),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                      side: BorderSide(
                        color: Colors.blueGrey.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('გაუქმება'),
                  ),
                if (canDeleteReservation && onDeleteReservation != null)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showDeleteConfirmation(context, reservation),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: BorderSide(
                        color: const Color(0xFFB91C1C).withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('წაშლა'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  DateTime _normalizeDateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameReservationDate(Reservation reservation, DateTime targetDate) {
    final reservationDate = _normalizeDateOnly(reservation.reservationDate);
    return reservationDate.isAtSameMomentAs(_normalizeDateOnly(targetDate));
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isCancelledStatus(String status) {
    final normalized = _normalizeReservationStatus(status);
    return normalized.startsWith('cancelled') ||
        normalized.startsWith('canceled');
  }

  String _normalizeReservationStatus(String status) {
    return status.trim().toLowerCase().replaceAll('_', '-');
  }

  Color _reservationStatusColor(String status) {
    final normalized = _normalizeReservationStatus(status);
    if (normalized.startsWith('confirmed')) {
      return const Color(0xFF0F766E);
    }
    if (normalized.startsWith('cancelled') ||
        normalized.startsWith('canceled')) {
      return const Color(0xFFB91C1C);
    }
    return mutedText;
  }

  String _reservationStatusLabel(String status) {
    final normalized = _normalizeReservationStatus(status);
    if (normalized.startsWith('confirmed')) {
      return 'დადასტურებული';
    }
    if (normalized.startsWith('cancelled') ||
        normalized.startsWith('canceled')) {
      return 'გაუქმებული';
    }
    return status;
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: primaryColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF1F2937),
                  fontSize: isMobile ? 22 : 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: mutedText,
                  fontSize: isMobile ? 13 : 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color backgroundColor,
    required Color iconColor,
    required bool isMobile,
  }) {
    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> actions,
    required bool isMobile,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: secondaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF0F172A),
                        fontSize: isMobile ? 15 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 10, children: actions),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _buildReservationFilterButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color primaryColor,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? Colors.transparent
                  : primaryColor.withValues(alpha: 0.2),
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : primaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 48,
            color: mutedText.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 14),
          const Text(
            'რეზერვაციები არ მოიძებნა',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'შეცვალე ფილტრი ან დაამატე ახალი რეზერვაცია.',
            style: TextStyle(color: mutedText, fontSize: 13, height: 1.45),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelConfirmation(
    BuildContext context,
    Reservation reservation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'რეზერვაციის გაუქმება',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ გაუქმო ${reservation.customerName.trim().isEmpty ? "ეს რეზერვაცია" : reservation.customerName.trim()} აქ?',
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
            child: const Text('უარი'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('გაუქმება'),
          ),
        ],
      ),
    );

    if (confirmed == true && onCancelReservation != null) {
      await onCancelReservation!(reservation);
    }
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    Reservation reservation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'რეზერვაციის წაშლა',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ ამ რეზერვაციის სამუდამოდ წაშლა? ეს მოქმედება არ შეიძლება უკან დაბრუნდეს.',
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed == true && onDeleteReservation != null) {
      await onDeleteReservation!(reservation);
    }
  }
}
