import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/home_reservations_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

class AdminReservationsSection extends StatefulWidget {
  final User user;

  const AdminReservationsSection({super.key, required this.user});

  @override
  State<AdminReservationsSection> createState() =>
      _AdminReservationsSectionState();
}

class _AdminReservationsSectionState extends State<AdminReservationsSection> {
  static const Color _primaryColor = AdminDesign.accentDark;
  static const Color _secondaryColor = AdminDesign.accent;
  static const Color _textPrimary = AdminDesign.text;

  String _reservationStatusFilter = 'confirmed';
  DateTime? _reservationDateFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _supervisorCreateOnly => widget.user.isSupervisor;

  @override
  void initState() {
    super.initState();
    _reservationDateFilter = null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildReservationsSection();
  }

  Widget _buildSupervisorReservationsNotice() {
    const noticeBorder = Color(0xFFFCD34D);
    const noticeBg = Color(0xFFFFFBEB);
    const noticeTitle = Color(0xFF92400E);
    const noticeBody = Color(0xFFB45309);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: noticeBg,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: noticeBorder, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: noticeTitle, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'ზედამხედველის შეზღუდვები',
                  style: TextStyle(
                    color: noticeTitle,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'ამ განყოფილებში შეგიძლიათ მხოლოდ ახალი რეზერვაციის შექმნა.\n'
                  'რეზერვაციის წაშლა და გაუქმება მხოლოდ მენეჯერს შეუძლია.\n'
                  'არსებული რეზერვაციის შეცვლა, მენიუ და სუფრაზე გადაყვანა — მთავარი ეკრანის „რეზერვაცია“ ჩანართიდან.',
                  style: TextStyle(
                    color: noticeBody,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeStatus(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  Widget _buildReservationsSection() {
    final currentDate = DatabaseService.getCurrentDate();
    final normalizedToday = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );

    final filteredReservations =
        DatabaseService.getAllReservations().where((reservation) {
          if (reservation.isTakeAway) {
            return false;
          }
          if (reservation.notes != null &&
              reservation.notes!.startsWith('Order #')) {
            return false;
          }

          final normalizedStatus = _normalizeStatus(reservation.status);
          final isConfirmed = normalizedStatus.startsWith('confirmed');
          final isCancelled =
              normalizedStatus.startsWith('cancelled') ||
              normalizedStatus.startsWith('canceled');

          if (!isConfirmed && !isCancelled) {
            return false;
          }

          final reservationDateOnly = DateTime(
            reservation.reservationDate.year,
            reservation.reservationDate.month,
            reservation.reservationDate.day,
          );

          return !reservationDateOnly.isBefore(normalizedToday);
        }).toList()..sort((a, b) {
          final dateComparison = a.reservationDate.compareTo(b.reservationDate);
          if (dateComparison != 0) {
            return dateComparison;
          }
          return a.reservationTime.compareTo(b.reservationTime);
        });

    final confirmed = filteredReservations
        .where(
          (reservation) =>
              _normalizeStatus(reservation.status).startsWith('confirmed'),
        )
        .toList();
    final cancelled = filteredReservations.where((reservation) {
      final status = _normalizeStatus(reservation.status);
      return status.startsWith('cancelled') || status.startsWith('canceled');
    }).toList();
    final todayReservations = filteredReservations
        .where(
          (reservation) =>
              _isSameDay(reservation.reservationDate, normalizedToday),
        )
        .toList();
    final query = _searchQuery.trim().toLowerCase();
    final visibleReservations = filteredReservations.where((reservation) {
      final status = _normalizeStatus(reservation.status);
      final matchesStatus = _reservationStatusFilter == 'cancelled'
          ? status.startsWith('cancelled') || status.startsWith('canceled')
          : status.startsWith('confirmed');
      final matchesDate =
          _reservationDateFilter == null ||
          _isSameDay(reservation.reservationDate, _reservationDateFilter!);
      final matchesSearch =
          query.isEmpty ||
          reservation.customerName.toLowerCase().contains(query) ||
          reservation.customerPhone.toLowerCase().contains(query) ||
          reservation.tableNumbers.join(',').contains(query);
      return matchesStatus && matchesDate && matchesSearch;
    }).toList();
    final todayGuests = todayReservations.fold<int>(
      0,
      (sum, reservation) => sum + reservation.numberOfGuests,
    );
    final todayTables = todayReservations
        .expand((reservation) => reservation.tableNumbers)
        .toSet()
        .length;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 22,
                isMobile ? 16 : 18,
                isMobile ? 16 : 22,
                18,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeader(isMobile, filteredReservations.length),
                    if (_supervisorCreateOnly) ...[
                      const SizedBox(height: 14),
                      _buildSupervisorReservationsNotice(),
                    ],
                    const SizedBox(height: 16),
                    _buildKpiRow(
                      upcoming: filteredReservations.length,
                      confirmed: confirmed.length,
                      today: todayReservations.length,
                      cancelled: cancelled.length,
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showSidePanel = constraints.maxWidth >= 850;
                        final sidePanelWidth = constraints.maxWidth < 1120
                            ? 280.0
                            : 330.0;
                        if (!showSidePanel) {
                          return Column(
                            children: [
                              _buildReservationsTable(
                                visibleReservations,
                                compact: true,
                              ),
                              const SizedBox(height: 14),
                              _buildReservationSidePanel(
                                todayReservations,
                                todayGuests,
                                todayTables,
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildReservationsTable(
                                visibleReservations,
                              ),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: sidePanelWidth,
                              child: _buildReservationSidePanel(
                                todayReservations,
                                todayGuests,
                                todayTables,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomDock(),
        ],
      ),
    );
  }

  Widget _buildPageHeader(bool isMobile, int count) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AdminDesign.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AdminDesign.radius),
          ),
          child: const Icon(
            Icons.event_available_outlined,
            color: AdminDesign.accentDark,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'რეზერვაციები',
                style: TextStyle(
                  color: AdminDesign.text,
                  fontSize: isMobile ? 23 : 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'მართეთ ჯავშნები, სტუმრები და მაგიდების განაწილება.',
                style: TextStyle(color: AdminDesign.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (!isMobile)
          AdminStatusBadge(
            icon: Icons.calendar_month_outlined,
            label: '$count ჩანაწერი',
          ),
      ],
    );
  }

  Widget _buildKpiRow({
    required int upcoming,
    required int confirmed,
    required int today,
    required int cancelled,
  }) {
    final items = [
      _ReservationKpiData(
        label: 'მომავალი ჯავშნები',
        value: upcoming,
        icon: Icons.calendar_month_outlined,
        color: const Color(0xFF0F9D58),
      ),
      _ReservationKpiData(
        label: 'დადასტურებული',
        value: confirmed,
        icon: Icons.check_circle_outline,
        color: const Color(0xFF0369A1),
      ),
      _ReservationKpiData(
        label: 'დღეს',
        value: today,
        icon: Icons.schedule_outlined,
        color: const Color(0xFFEA580C),
      ),
      _ReservationKpiData(
        label: 'გაუქმებული',
        value: cancelled,
        icon: Icons.event_busy_outlined,
        color: const Color(0xFF7C3AED),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 4
            : constraints.maxWidth >= 460
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _ReservationKpiCard(data: item, compact: width < 230),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildReservationsTable(
    List<Reservation> reservations, {
    bool compact = false,
  }) {
    return Container(
      decoration: AdminDesign.panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 690;
                final title = const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: AdminDesign.text,
                      size: 21,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'რეზერვაციების სია',
                      style: TextStyle(
                        color: AdminDesign.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                );
                final controls = Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: PosOnScreenTextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          style: const TextStyle(
                            color: AdminDesign.text,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'ძებნა სახელით, ტელეფონით ან მაგიდით...',
                            hintStyle: const TextStyle(
                              color: AdminDesign.muted,
                              fontSize: 11,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AdminDesign.muted,
                              size: 19,
                            ),
                            filled: true,
                            fillColor: AdminDesign.panelSoft,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AdminDesign.radius,
                              ),
                              borderSide: const BorderSide(
                                color: AdminDesign.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AdminDesign.radius,
                              ),
                              borderSide: const BorderSide(
                                color: AdminDesign.border,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterButton(),
                  ],
                );
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 12), controls],
                  );
                }
                return Row(
                  children: [
                    title,
                    const SizedBox(width: 18),
                    Expanded(child: controls),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, color: AdminDesign.border),
          if (!compact) _buildReservationTableHeader(),
          if (reservations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    color: AdminDesign.muted,
                    size: 36,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'რეზერვაცია ვერ მოიძებნა',
                    style: TextStyle(color: AdminDesign.muted),
                  ),
                ],
              ),
            )
          else
            ...reservations.asMap().entries.map(
              (entry) => _buildReservationRow(
                entry.value,
                compact: compact,
                showDivider: entry.key < reservations.length - 1,
              ),
            ),
          if (reservations.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AdminDesign.panelSoft,
                border: Border(top: BorderSide(color: AdminDesign.border)),
              ),
              child: Text(
                '${reservations.length} ჩანაწერი',
                style: const TextStyle(
                  color: AdminDesign.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButton() {
    return PopupMenuButton<String>(
      tooltip: 'ფილტრი',
      onSelected: (value) async {
        if (value == 'date') {
          final picked = await showDatePicker(
            context: context,
            initialDate:
                _reservationDateFilter ?? DatabaseService.getCurrentDate(),
            firstDate: DatabaseService.getCurrentDate().subtract(
              const Duration(days: 365),
            ),
            lastDate: DatabaseService.getCurrentDate().add(
              const Duration(days: 730),
            ),
          );
          if (picked != null && mounted) {
            setState(() => _reservationDateFilter = picked);
          }
          return;
        }
        setState(() {
          if (value == 'all_dates') {
            _reservationDateFilter = null;
          } else {
            _reservationStatusFilter = value;
          }
        });
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'confirmed',
          checked: _reservationStatusFilter == 'confirmed',
          child: const Text('დადასტურებული'),
        ),
        CheckedPopupMenuItem(
          value: 'cancelled',
          checked: _reservationStatusFilter == 'cancelled',
          child: const Text('გაუქმებული'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'date', child: Text('თარიღის არჩევა')),
        const PopupMenuItem(value: 'all_dates', child: Text('ყველა თარიღი')),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          border: Border.all(color: AdminDesign.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_outlined, color: AdminDesign.text, size: 18),
            SizedBox(width: 7),
            Text(
              'ფილტრი',
              style: TextStyle(
                color: AdminDesign.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReservationTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: AdminDesign.panelSoft,
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Text('სტუმარი', style: _ReservationTableHeader.style),
          ),
          Expanded(
            flex: 5,
            child: Text('თარიღი / დრო', style: _ReservationTableHeader.style),
          ),
          Expanded(
            flex: 3,
            child: Text('მაგიდა', style: _ReservationTableHeader.style),
          ),
          Expanded(
            flex: 3,
            child: Text('სტუმრები', style: _ReservationTableHeader.style),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text('სტატუსი', style: _ReservationTableHeader.style),
          ),
          SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _buildReservationRow(
    Reservation reservation, {
    required bool compact,
    required bool showDivider,
  }) {
    final cancelled = _isCancelled(reservation);
    final statusColor = cancelled
        ? const Color(0xFFB91C1C)
        : const Color(0xFF047857);
    final statusLabel = cancelled ? 'გაუქმებული' : 'დადასტურებული';
    final tables = reservation.tableNumbers.isEmpty
        ? '-'
        : reservation.tableNumbers.join(', ');
    final dateLabel = DatabaseService.getGeorgianFormattedDate(
      reservation.reservationDate,
    );
    final actions = PopupMenuButton<String>(
      tooltip: 'მოქმედებები',
      icon: const Icon(Icons.more_vert, color: AdminDesign.text, size: 20),
      onSelected: (value) {
        if (value == 'cancel') {
          _confirmCancelReservation(reservation);
        } else {
          _confirmDeleteReservation(reservation);
        }
      },
      itemBuilder: (context) => [
        if (!cancelled && widget.user.canCancelReservations)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.close),
              title: Text('გაუქმება'),
            ),
          ),
        if (widget.user.canDeleteReservations)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline, color: AdminDesign.danger),
              title: Text('წაშლა', style: TextStyle(color: AdminDesign.danger)),
            ),
          ),
      ],
    );
    final decoration = BoxDecoration(
      border: showDivider
          ? const Border(bottom: BorderSide(color: AdminDesign.border))
          : null,
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: decoration,
        child: Row(
          children: [
            _reservationAvatar(reservation.customerName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reservation.customerName.trim().isEmpty
                        ? 'რეზერვაცია'
                        : reservation.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminDesign.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$dateLabel • ${reservation.reservationTime}',
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'მაგიდა: $tables • ${reservation.numberOfGuests} სტუმარი',
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            actions,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                _reservationAvatar(reservation.customerName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reservation.customerName.trim().isEmpty
                            ? 'რეზერვაცია'
                            : reservation.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AdminDesign.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (reservation.customerPhone.trim().isNotEmpty)
                        Text(
                          reservation.customerPhone,
                          style: const TextStyle(
                            color: AdminDesign.muted,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              '$dateLabel • ${reservation.reservationTime}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              tables,
              style: const TextStyle(color: AdminDesign.muted, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${reservation.numberOfGuests}',
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 42, child: actions),
        ],
      ),
    );
  }

  Widget _reservationAvatar(String name) {
    final trimmed = name.trim();
    final label = trimmed.isEmpty ? 'R' : trimmed.characters.first;
    return CircleAvatar(
      radius: 17,
      backgroundColor: AdminDesign.accent.withValues(alpha: 0.13),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AdminDesign.accentDark,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildReservationSidePanel(
    List<Reservation> todayReservations,
    int todayGuests,
    int todayTables,
  ) {
    final timeline = todayReservations.toList()
      ..sort((a, b) => a.reservationTime.compareTo(b.reservationTime));
    return Column(
      children: [
        Container(
          decoration: AdminDesign.panelDecoration(),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      color: AdminDesign.text,
                      size: 21,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'დღევანდელი',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AdminDesign.text,
                          fontSize: 15,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AdminDesign.border),
              if (timeline.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'დღეს რეზერვაციები არ არის',
                    style: TextStyle(color: AdminDesign.muted, fontSize: 12),
                  ),
                )
              else
                ...timeline.take(6).map(_buildTimelineRow),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AdminDesign.panelDecoration(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.bar_chart_outlined,
                    color: AdminDesign.text,
                    size: 21,
                  ),
                  SizedBox(width: 9),
                  Text(
                    'დღის დატვირთვა',
                    style: TextStyle(
                      color: AdminDesign.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildLoadRow(
                icon: Icons.people_outline,
                label: 'სტუმრები',
                value: '$todayGuests',
                color: const Color(0xFF0F9D58),
              ),
              const SizedBox(height: 10),
              _buildLoadRow(
                icon: Icons.table_restaurant_outlined,
                label: 'დაკავებული მაგიდები',
                value: '$todayTables',
                color: const Color(0xFFEA580C),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineRow(Reservation reservation) {
    final cancelled = _isCancelled(reservation);
    final color = cancelled ? const Color(0xFFB91C1C) : const Color(0xFF047857);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminDesign.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              reservation.reservationTime,
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reservation.customerName.trim().isEmpty
                      ? 'რეზერვაცია'
                      : reservation.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${reservation.tableNumbers.isEmpty ? '-' : reservation.tableNumbers.join(', ')} • ${reservation.numberOfGuests} სტუმარი',
                  style: const TextStyle(
                    color: AdminDesign.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AdminDesign.panelSoft,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: AdminDesign.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AdminDesign.muted, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 11, 22, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminDesign.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final action = ElevatedButton.icon(
            onPressed: widget.user.canCreateReservationsInAdmin
                ? _showReservationDialog
                : null,
            style: AdminDesign.primaryButtonStyle(),
            icon: const Icon(Icons.add_box_outlined, size: 19),
            label: const Text(
              'ახალი რეზერვაცია',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          );
          if (constraints.maxWidth < 560) {
            return SizedBox(width: double.infinity, child: action);
          }
          return Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AdminDesign.accentDark,
                size: 20,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'ყველა ცვლილება ინახება მოქმედების დასრულებისთანავე.',
                  style: TextStyle(color: AdminDesign.muted, fontSize: 12),
                ),
              ),
              action,
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmCancelReservation(Reservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('რეზერვაციის გაუქმება'),
        content: Text(
          'გსურთ ${reservation.customerName}-ის რეზერვაციის გაუქმება?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('დაბრუნება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminDesign.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('გაუქმება'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateReservationStatus(reservation, 'cancelled');
    }
  }

  Future<void> _confirmDeleteReservation(Reservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('რეზერვაციის წაშლა'),
        content: Text(
          'გსურთ ${reservation.customerName}-ის რეზერვაციის სამუდამოდ წაშლა?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('დაბრუნება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminDesign.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteReservation(reservation);
    }
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  bool _isCancelled(Reservation reservation) {
    final status = _normalizeStatus(reservation.status);
    return status.startsWith('cancelled') || status.startsWith('canceled');
  }

  Future<void> _showReservationDialog() async {
    String? initialName;
    String? initialPhone;
    String? initialNotes;
    DateTime? initialDate;
    TimeOfDay? initialTime;
    int? initialGuests;

    while (mounted) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Material(
            color: Colors.transparent,
            child: ReservationCreationSheet(
              initialName: initialName,
              initialPhone: initialPhone,
              initialNotes: initialNotes,
              initialDate: initialDate,
              initialTime: initialTime,
              initialGuests: initialGuests,
            ),
          );
        },
      );

      if (result == null) {
        return;
      }

      final selectedDate = result['date'] as DateTime?;
      final selectedTime = result['time'] as TimeOfDay?;
      if (selectedDate == null || selectedTime == null) {
        return;
      }

      final customerName = (result['customerName'] as String? ?? '').trim();
      final customerPhone = (result['customerPhone'] as String? ?? '').trim();
      final notesRaw = (result['notes'] as String?)?.trim();
      final guestCount =
          (result['numberOfGuests'] as int?) ?? (result['guests'] as int?) ?? 2;

      initialName = customerName;
      initialPhone = customerPhone;
      initialNotes = notesRaw;
      initialDate = selectedDate;
      initialTime = selectedTime;
      initialGuests = guestCount;

      final timeString =
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

      if (!mounted) {
        return;
      }

      final selectedItems = await Navigator.push<List<OrderItem>>(
        context,
        MaterialPageRoute(
          builder: (context) => MenuScreen(
            user: widget.user,
            selectedTables: const [],
            isPreOrderMode: true,
            reservationContext: ReservationContext(
              customerName: customerName,
              customerPhone: customerPhone,
              reservationDate: selectedDate,
              reservationTime: timeString,
              tableNumbers: const [],
              tableLabels: const [],
              numberOfGuests: guestCount,
              notes: (notesRaw == null || notesRaw.isEmpty) ? null : notesRaw,
            ),
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      if (selectedItems == null) {
        continue;
      }

      final tableNumbers = await HomeReservationTableAssignmentDialog.show(
        context: context,
        reservationDate: selectedDate,
        reservationTime: timeString,
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        textPrimary: _textPrimary,
      );
      if (!mounted || tableNumbers == null || tableNumbers.isEmpty) {
        continue;
      }

      final reservationId = await DatabaseService.createReservation(
        customerName: customerName,
        customerPhone: customerPhone,
        tableNumbers: tableNumbers,
        reservationDate: selectedDate,
        reservationTime: timeString,
        numberOfGuests: guestCount,
        notes: (notesRaw == null || notesRaw.isEmpty) ? null : notesRaw,
        createdBy: widget.user.username,
        status: 'confirmed',
      );

      await DatabaseService.updateReservationPreOrderItems(
        reservationId,
        selectedItems,
      );

      final createdReservation = Reservation(
        id: reservationId,
        customerName: customerName,
        customerPhone: customerPhone,
        tableNumbers: tableNumbers,
        reservationDate: selectedDate,
        reservationTime: timeString,
        numberOfGuests: guestCount,
        notes: (notesRaw == null || notesRaw.isEmpty) ? null : notesRaw,
        createdAt: DatabaseService.getCurrentDateTime(),
        createdBy: widget.user.username,
        status: 'confirmed',
        preOrderItems: selectedItems,
      );

      _sendReservationKitchenCheck(createdReservation);

      if (!mounted) {
        return;
      }

      unawaited(showSuccessToast(context, 'Reservation created successfully'));
      setState(() {});
      return;
    }
  }

  void _sendReservationKitchenCheck(Reservation reservation) {
    final kitchenItems = HomeReservationsHelper.buildKitchenCheckLines(
      reservation,
    );
    if (kitchenItems.isEmpty) {
      return;
    }

    final orderLabel = HomeReservationsHelper.buildKitchenOrderLabel(
      reservation,
    );
    final createdAt = HomeReservationsHelper.buildKitchenTime(reservation);

    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: reservation.tableNumbers.isNotEmpty
          ? reservation.tableNumbers.join(', ')
          : null,
      orderNumber: orderLabel,
      waiterName: widget.user.username,
      createdAt: createdAt,
      onComplete: (success) {
        if (!mounted) {
          return;
        }
        if (success) {
          unawaited(showSuccessToast(context, 'ჩეკი გაიგზავნა სამზარეულოში'));
        } else {
          unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
        }
      },
    );
  }

  Future<void> _updateReservationStatus(
    Reservation reservation,
    String newStatus,
  ) async {
    final currentDate = DatabaseService.getCurrentDate();
    final currentDateString = currentDate.toIso8601String().split('T')[0];
    final resDateString = reservation.reservationDate.toIso8601String().split(
      'T',
    )[0];
    final bool isTodayReservation = resDateString == currentDateString;

    if (newStatus == 'confirmed' &&
        isTodayReservation &&
        !widget.user.canManageReservationsOnHome) {
      if (mounted) {
        unawaited(
          showErrorToast(
            context,
            'დღევანდელი რეზერვაციის გააქტიურება მხოლოდ მენეჯერს ან ზედამხედველს შეუძლია.',
          ),
        );
      }
      return;
    }

    final previousStatus = reservation.status;
    await DatabaseService.updateReservationStatus(reservation.id, newStatus);

    if (newStatus == 'cancelled') {
      await DatabaseService.logAdminAction(
        actionType: 'reservation_cancelled',
        performedBy: widget.user.username,
        comment: 'Reservation cancelled via Admin panel',
        details: {
          'reservationId': reservation.id,
          'customerName': reservation.customerName,
          'reservationDate': reservation.reservationDate.toIso8601String(),
          'reservationTime': reservation.reservationTime,
          'tableNumbers': reservation.tableNumbers,
          'previousStatus': previousStatus,
          'newStatus': newStatus,
          'isTakeAway': reservation.isTakeAway,
          'linkedOrderId': reservation.linkedOrderId,
          'notes': reservation.notes,
          'performedByRole': widget.user.role,
        },
      );
    }

    if (mounted) {
      unawaited(showSuccessToast(context, 'Reservation $newStatus'));
    }

    setState(() {});
  }

  Future<void> _deleteReservation(Reservation reservation) async {
    // Confirmation is already handled by the reservations management section
    // before this callback fires, so we delete directly (no second dialog).
    await DatabaseService.deleteReservation(reservation.id);
    if (!mounted) return;
    setState(() {});
    unawaited(showSuccessToast(context, 'Reservation deleted'));
  }
}

class _ReservationKpiData {
  const _ReservationKpiData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _ReservationKpiCard extends StatelessWidget {
  const _ReservationKpiCard({required this.data, required this.compact});

  final _ReservationKpiData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: 12,
      ),
      decoration: AdminDesign.panelDecoration(),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, color: data.color, size: compact ? 21 : 25),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AdminDesign.muted,
                    fontSize: compact ? 10 : 11,
                  ),
                ),
                Text(
                  '${data.value}',
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
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

abstract final class _ReservationTableHeader {
  static const TextStyle style = TextStyle(
    color: AdminDesign.muted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}
