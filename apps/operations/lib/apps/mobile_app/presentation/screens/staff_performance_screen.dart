import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/reservation_create_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/reservation_detail_screen.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

({Color color, String label}) _statusMeta(String status) {
  final s = status.toLowerCase();
  if (s.startsWith('confirmed'))
    return (color: MobileGlassTheme.good, label: 'დადასტურებული');
  if (s.startsWith('completed'))
    return (color: MobileGlassTheme.good, label: 'დასრულებული');
  if (s.startsWith('cancelled') || s.startsWith('canceled')) {
    return (color: MobileGlassTheme.bad, label: 'გაუქმებული');
  }
  return (color: MobileGlassTheme.warn, label: 'მოლოდინში');
}

class StaffPerformanceScreen extends StatefulWidget {
  final User user;
  const StaffPerformanceScreen({super.key, required this.user});

  @override
  State<StaffPerformanceScreen> createState() => _StaffPerformanceScreenState();
}

class _StaffPerformanceScreenState extends State<StaffPerformanceScreen> {
  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  final DateFormat _prettyFmt = DateFormat('EEE, d MMM');
  final DateFormat _groupFmt = DateFormat('EEEE, d MMMM');
  DateTime _selectedDate = DateTime.now();

  List<Map<String, dynamic>> _reservations = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showAll = false;
  String? _error;
  int _lastRealtimeTick = 0;

  @override
  void initState() {
    super.initState();
    _selectedDate = _businessNow();
    _loadReservations();
    _lastRealtimeTick = MonitoringSocketService.updateCounter.value;
    MonitoringSocketService.updateCounter.addListener(_onRealtimeEvent);
    MonitoringSocketService.lastReservationDate.addListener(
      _onReservationDateHint,
    );
  }

  @override
  void dispose() {
    MonitoringSocketService.updateCounter.removeListener(_onRealtimeEvent);
    MonitoringSocketService.lastReservationDate.removeListener(
      _onReservationDateHint,
    );
    super.dispose();
  }

  void _onRealtimeEvent() {
    final tick = MonitoringSocketService.updateCounter.value;
    if (tick == _lastRealtimeTick) return;
    _lastRealtimeTick = tick;
    unawaited(_loadReservations());
  }

  void _onReservationDateHint() {
    final raw = MonitoringSocketService.lastReservationDate.value;
    if (raw == null || raw.isEmpty) return;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return;
    final target = DateTime(parsed.year, parsed.month, parsed.day);
    final current = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    if (target == current) return;
    if (mounted) {
      setState(() => _selectedDate = target);
      unawaited(_loadReservations());
    }
  }

  int _statusRank(String s) {
    final x = s.toLowerCase();
    if (x.startsWith('confirmed')) return 0;
    if (x.startsWith('pending')) return 1;
    if (x.startsWith('completed')) return 2;
    return 3;
  }

  String _dateKey(Map<String, dynamic> r) {
    final raw = (r['reservationDate'] ?? '').toString();
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  Future<void> _loadReservations() async {
    try {
      final rows = _showAll
          ? await MobileApiService.getReservations()
          : await MobileApiService.getReservations(
              date: _dateFmt.format(_selectedDate),
            );
      rows.sort((a, b) {
        if (_showAll) {
          final d = _dateKey(a).compareTo(_dateKey(b));
          if (d != 0) return d;
        }
        final r = _statusRank(
          (a['status'] ?? '').toString(),
        ).compareTo(_statusRank((b['status'] ?? '').toString()));
        if (r != 0) return r;
        return (a['reservationTime'] ?? '').toString().compareTo(
          (b['reservationTime'] ?? '').toString(),
        );
      });
      if (mounted) {
        setState(() {
          _reservations = rows;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'სერვერთან კავშირი ვერ დამყარდა';
        });
      }
    }
  }

  DateTime _businessNow() {
    final raw = MonitoringSocketService.currentBusinessDate.value;
    if (raw != null && raw.trim().isNotEmpty) {
      final parts = raw.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
    }
    return DateTime.now();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ManagerToast.showSnackBar(context, msg, isError: error);
  }

  Future<void> _updateStatus(String id, String status) async {
    await MobileApiService.updateReservationStatus(
      reservationId: id,
      status: status,
    );
    await _loadReservations();
  }

  Future<void> _deleteReservation(String id) async {
    await MobileApiService.deleteReservation(id);
    await _loadReservations();
  }

  Future<void> _pickReservationDate() async {
    final businessDate = _businessNow();
    final initial = _selectedDate.isBefore(businessDate)
        ? businessDate
        : _selectedDate;
    if (!kIsWeb && Platform.isIOS) {
      DateTime temp = initial;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: MobileGlassTheme.data.surfaceCard,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'გაუქმება',
                          style: TextStyle(
                            color: MobileGlassTheme.textSecondary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(
                            () => _selectedDate = DateTime(
                              temp.year,
                              temp.month,
                              temp.day,
                            ),
                          );
                          Navigator.pop(ctx);
                          unawaited(_loadReservations());
                        },
                        child: Text(
                          'არჩევა',
                          style: TextStyle(color: MobileGlassTheme.accentText),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(brightness: Brightness.dark),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      minimumDate: DateTime(
                        businessDate.year,
                        businessDate.month,
                        businessDate.day,
                      ),
                      initialDateTime: initial,
                      onDateTimeChanged: (value) => temp = value,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(
        businessDate.year,
        businessDate.month,
        businessDate.day,
      ),
      lastDate: businessDate.add(const Duration(days: 365)),
      initialDate: initial,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: MobileGlassTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      unawaited(_loadReservations());
    }
  }

  void _shiftDay(int delta) {
    final next = _selectedDate.add(Duration(days: delta));
    final businessDate = _businessNow();
    final floor = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );
    if (next.isBefore(floor)) return;
    setState(() => _selectedDate = next);
    unawaited(_loadReservations());
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      ReservationCreateScreen.route(
        user: widget.user,
        initialDate: _selectedDate,
      ),
    );
    if (created == true) {
      _toast('რეზერვაცია შეიქმნა');
      await _loadReservations();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final changed = await Navigator.of(context).push<bool>(
      ReservationDetailScreen.route(
        row: row,
        onUpdateStatus: _updateStatus,
        onDelete: _deleteReservation,
      ),
    );
    if (changed == true) await _loadReservations();
  }

  // ── Walk-in flow (unchanged logic) ─────────────────────────────────────
  Future<void> _startWalkInFlow() async {
    final selected = await Navigator.of(context).push<List<MenuSelectionLine>>(
      MaterialPageRoute(
        builder: (_) => managerThemedPage(
          const MobileCalculatorScreen(selectionMode: true),
        ),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final pick = await _pickWalkInTables();
    if (pick == null || !mounted) return;
    final floor = pick['floor'] as String;
    final tables = (pick['tables'] as List).cast<String>();
    if (tables.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final items = selected
          .map(
            (e) => <String, dynamic>{
              'itemName': e.itemName,
              'unitPrice': e.unitPrice,
              'quantity': e.qty,
            },
          )
          .toList();
      await MobileApiService.createWalkInOrder(
        tableNumbers: tables,
        floor: floor,
        waiterName: widget.user.username,
        items: items,
      );
      await _loadReservations();
      _toast('Walk-in შეიქმნა');
    } catch (_) {
      _toast('walk-in ვერ შეიქმნა', error: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<Map<String, dynamic>?> _pickWalkInTables() async {
    List<TableModel> tables;
    try {
      tables = await MobileApiService.getTables();
    } catch (_) {
      _toast('მაგიდების ჩატვირთვა ვერ მოხერხდა', error: true);
      return null;
    }
    final free = tables.where((t) => !t.isReserved).toList()
      ..sort((a, b) {
        final f = a.floor.compareTo(b.floor);
        if (f != 0) return f;
        return (int.tryParse(a.tableNumber) ?? 0).compareTo(
          int.tryParse(b.tableNumber) ?? 0,
        );
      });
    if (!mounted) return null;
    if (free.isEmpty) {
      _toast('თავისუფალი მაგიდა არ არის', error: true);
      return null;
    }

    String? selectedFloor;
    final selectedTables = <String>{};

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobileGlassTheme.data.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            String floorLabel(String f) =>
                f == 'second' ? 'მე-2 სართული' : '1-ლი სართული';
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'აირჩიე მაგიდა',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: MobileGlassTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'ერთ სართულზე ერთი ან რამდენიმე მაგიდა',
                      style: TextStyle(
                        color: MobileGlassTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: free.map((t) {
                        final isSel =
                            selectedTables.contains(t.tableNumber) &&
                            selectedFloor == t.floor;
                        final disabled =
                            selectedFloor != null && selectedFloor != t.floor;
                        return GestureDetector(
                          onTap: disabled
                              ? null
                              : () {
                                  setSheetState(() {
                                    if (isSel) {
                                      selectedTables.remove(t.tableNumber);
                                      if (selectedTables.isEmpty) {
                                        selectedFloor = null;
                                      }
                                    } else {
                                      selectedFloor = t.floor;
                                      selectedTables.add(t.tableNumber);
                                    }
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? MobileGlassTheme.primary
                                  : MobileGlassTheme.surface(
                                      disabled ? 0.02 : 0.05,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel
                                    ? MobileGlassTheme.primary
                                    : MobileGlassTheme.data.borderSubtle,
                              ),
                            ),
                            child: Text(
                              '${floorLabel(t.floor)} • ${t.tableNumber}',
                              style: TextStyle(
                                color: isSel
                                    ? Colors.white
                                    : MobileGlassTheme.textPrimary.withValues(
                                        alpha: disabled ? 0.35 : 0.85,
                                      ),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedTables.isEmpty
                            ? null
                            : () => Navigator.of(sheetContext).pop({
                                'floor': selectedFloor,
                                'tables': selectedTables.toList(),
                              }),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MobileGlassTheme.primary,
                          disabledBackgroundColor: MobileGlassTheme.primary
                              .withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'დადასტურება',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: _GlowOrb(color: MobileGlassTheme.primary, size: 300),
          ),
          Positioned(
            top: 320,
            left: -100,
            child: _GlowOrb(color: Color(0xFF0EA5E9), size: 240),
          ),
          SafeArea(
            bottom: false,
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: MobileGlassTheme.primary,
                    ),
                  )
                : _error != null
                ? _buildError()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 56,
          color: MobileGlassTheme.textSecondary,
        ),
        SizedBox(height: 14),
        Text(
          _error!,
          style: TextStyle(
            color: MobileGlassTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextButton.icon(
          onPressed: _loadReservations,
          icon: Icon(Icons.refresh_rounded, color: MobileGlassTheme.accentText),
          label: Text(
            'თავიდან ცდა',
            style: TextStyle(color: MobileGlassTheme.accentText),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: RefreshIndicator(
            color: MobileGlassTheme.primary,
            backgroundColor: MobileGlassTheme.data.surfaceCard,
            onRefresh: _loadReservations,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              children: [
                _buildModeToggle(),
                SizedBox(height: 14),
                _buildStatsCard(),
                SizedBox(height: 16),
                if (!_showAll) ...[_buildDateBar(), SizedBox(height: 12)],
                _buildWalkInButton(),
                SizedBox(height: 16),
                if (_reservations.isEmpty)
                  _buildEmpty()
                else if (_showAll)
                  ..._buildGroupedList()
                else
                  ..._reservations.map(_buildReservationCard),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'რეზერვები',
            style: TextStyle(
              color: MobileGlassTheme.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          _GlassCircleButton(
            icon: Icons.add_rounded,
            filled: true,
            onTap: _openCreate,
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MobileGlassTheme.surface(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MobileGlassTheme.data.borderSubtle),
      ),
      child: Row(
        children: [
          _togglePill('დღე', Icons.today_rounded, !_showAll, () {
            if (!_showAll) return;
            setState(() {
              _showAll = false;
              _isLoading = true;
            });
            unawaited(_loadReservations());
          }),
          _togglePill('ყველა', Icons.event_note_rounded, _showAll, () {
            if (_showAll) return;
            setState(() {
              _showAll = true;
              _isLoading = true;
            });
            unawaited(_loadReservations());
          }),
        ],
      ),
    );
  }

  Widget _togglePill(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MobileGlassTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : MobileGlassTheme.textSecondary,
              ),
              SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : MobileGlassTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedList() {
    final widgets = <Widget>[];
    String? currentKey;
    final businessDate = _businessNow();
    final today = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );
    final tomorrow = today.add(const Duration(days: 1));

    // Pre-count reservations per day for the header badge.
    final counts = <String, int>{};
    for (final r in _reservations) {
      final k = _dateKey(r);
      counts[k] = (counts[k] ?? 0) + 1;
    }

    for (final r in _reservations) {
      final key = _dateKey(r);
      if (key != currentKey) {
        currentKey = key;
        String label = key;
        final parsed = DateTime.tryParse(key);
        if (parsed != null) {
          final d = DateTime(parsed.year, parsed.month, parsed.day);
          if (d == today) {
            label = 'დღეს • ${_prettyFmt.format(d)}';
          } else if (d == tomorrow) {
            label = 'ხვალ • ${_prettyFmt.format(d)}';
          } else {
            label = _groupFmt.format(d);
          }
        }
        widgets.add(_buildDayHeader(label, counts[key] ?? 0));
      }
      widgets.add(_buildReservationCard(r));
    }
    return widgets;
  }

  Widget _buildDayHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: MobileGlassTheme.accentText,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: MobileGlassTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: MobileGlassTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: MobileGlassTheme.accentText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Divider(color: MobileGlassTheme.border(0.08)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final total = _reservations.length;
    final confirmed = _reservations
        .where(
          (r) => (r['status'] ?? '').toString().toLowerCase().startsWith(
            'confirmed',
          ),
        )
        .length;
    final guests = _reservations.fold<int>(0, (sum, r) {
      final g = r['numberOfGuests'];
      if (g is num) return sum + g.toInt();
      return sum + (int.tryParse('${g ?? ''}') ?? 0);
    });
    String lastValue;
    String lastLabel;
    if (_showAll) {
      final days = _reservations.map(_dateKey).toSet().length;
      lastValue = '$days';
      lastLabel = 'დღეები';
    } else {
      String nextTime = '—';
      for (final r in _reservations) {
        final s = (r['status'] ?? '').toString().toLowerCase();
        if (s.startsWith('completed') || s.startsWith('cancelled')) continue;
        final t = (r['reservationTime'] ?? '').toString();
        if (t.isNotEmpty) {
          nextTime = t;
          break;
        }
      }
      lastValue = nextTime;
      lastLabel = 'შემდეგი';
    }

    return _GlassCard(
      child: Row(
        children: [
          Expanded(child: _stat('$total', 'სულ', MobileGlassTheme.accentText)),
          _divider(),
          Expanded(
            child: _stat('$confirmed', 'დადასტ.', MobileGlassTheme.good),
          ),
          _divider(),
          Expanded(
            child: _stat('$guests', 'სტუმარი', MobileGlassTheme.textPrimary),
          ),
          _divider(),
          Expanded(child: _stat(lastValue, lastLabel, MobileGlassTheme.warn)),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 36, color: MobileGlassTheme.border(0.12));

  Widget _stat(String value, String label, Color color) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDateBar() {
    final businessDate = _businessNow();
    final atFloor = !_selectedDate.isAfter(
      DateTime(businessDate.year, businessDate.month, businessDate.day),
    );
    return Row(
      children: [
        _GlassCircleButton(
          icon: Icons.chevron_left_rounded,
          dim: atFloor,
          onTap: atFloor ? () {} : () => _shiftDay(-1),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _GlassCard(
            onTap: _pickReservationDate,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  color: MobileGlassTheme.accentText,
                  size: 18,
                ),
                SizedBox(width: 10),
                Text(
                  _prettyFmt.format(_selectedDate),
                  style: TextStyle(
                    color: MobileGlassTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: MobileGlassTheme.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10),
        _GlassCircleButton(
          icon: Icons.chevron_right_rounded,
          onTap: () => _shiftDay(1),
        ),
      ],
    );
  }

  Widget _buildWalkInButton() {
    return _GlassCard(
      onTap: _isSubmitting ? null : _startWalkInFlow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_walk_rounded,
            color: _isSubmitting
                ? MobileGlassTheme.textSecondary
                : MobileGlassTheme.good,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(
            _isSubmitting ? 'მუშავდება...' : 'Walk-in შეკვეთა',
            style: TextStyle(
              color: _isSubmitting
                  ? MobileGlassTheme.textSecondary
                  : MobileGlassTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 60,
              color: MobileGlassTheme.muted(0.25),
            ),
            SizedBox(height: 16),
            Text(
              _showAll
                  ? 'რეზერვაცია არ მოიძებნა'
                  : 'ამ თარიღზე რეზერვაცია არ არის',
              style: TextStyle(
                color: MobileGlassTheme.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'დაამატე ახალი + ღილაკით',
              style: TextStyle(
                color: MobileGlassTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReservationCard(Map<String, dynamic> row) {
    final status = (row['status'] ?? 'pending').toString();
    final meta = _statusMeta(status);
    final name = (row['customerName'] ?? 'უსახელო').toString();
    final time = (row['reservationTime'] ?? '').toString();
    final guests = (row['numberOfGuests'] ?? 0).toString();
    final tables = (row['tableNumbers'] is List)
        ? (row['tableNumbers'] as List).join(', ')
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _GlassCard(
        onTap: () => _openDetail(row),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 46,
              decoration: BoxDecoration(
                color: meta.color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobileGlassTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (time.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MobileGlassTheme.surface(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            time,
                            style: TextStyle(
                              color: MobileGlassTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.groups_rounded,
                        size: 14,
                        color: MobileGlassTheme.textSecondary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '$guests',
                        style: TextStyle(
                          color: MobileGlassTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (tables.isNotEmpty) ...[
                        SizedBox(width: 12),
                        Icon(
                          Icons.table_bar_rounded,
                          size: 14,
                          color: MobileGlassTheme.textSecondary,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            tables,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MobileGlassTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: meta.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          meta.label,
                          style: TextStyle(
                            color: meta.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: MobileGlassTheme.muted(0.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// ── shared dark glass widgets ───────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  const _GlassCard({required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    final radius = BorderRadius.circular(22);
    Widget card = Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.useGlassCards
            ? MobileGlassTheme.surface(0.04)
            : theme.heroCardBackground,
        borderRadius: radius,
        border: Border.all(color: theme.cardBorder, width: 1),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: theme.cardShadow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
    if (theme.useGlassCards) {
      card = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: card,
        ),
      );
    } else {
      card = ClipRRect(borderRadius: radius, child: card);
    }
    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.dim = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    Widget btn = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? theme.primary : theme.headerButtonBackground,
        border: Border.all(color: filled ? theme.primary : theme.cardBorder),
      ),
      child: Icon(
        icon,
        color: filled
            ? Colors.white
            : (dim ? theme.textSecondary : theme.textPrimary),
        size: 20,
      ),
    );
    if (theme.useGlassCards) {
      btn = ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: btn,
        ),
      );
    } else {
      btn = ClipOval(child: btn);
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: btn,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
