import '../widgets/manager_design_components.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_modal.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_data_status.dart';
import 'package:vynic/core/services/manager_app/manager_operation_request.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_operations_panel.dart';
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
  Map<String, ManagerReadStatus> _displayReads = {};
  int _readGeneration = 0;
  void _readFailed(Object error, String key) {
    final previous = _displayReads[key];
    final failure = error is ManagerReadFailure
        ? error.status
        : ManagerReadStatus(key: key, error: 'მონაცემები ვერ განახლდა.');
    _displayReads = {
      ..._displayReads,
      key: previous?.fetchedAt == null || previous?.query != failure.query
          ? failure
          : previous!.failed(
              failure.error ?? 'მონაცემები ვერ განახლდა.',
              location: 'memory',
            ),
    };
  }

  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  final DateFormat _prettyFmt = DateFormat('dd.MM.yyyy');
  final DateFormat _groupFmt = DateFormat('dd.MM.yyyy');
  DateTime _selectedDate = DateTime.now();

  List<Map<String, dynamic>> _reservations = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showAll = false;
  String? _error;
  int _lastRealtimeTick = 0;

  String? _operationScope;
  @override
  void initState() {
    super.initState();
    try {
      _operationScope = MobileApiService.tableRepairScope;
    } catch (_) {
      _operationScope = null;
    }
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
    final generation = ++_readGeneration;
    final query =
        '/mobile/reservations${_showAll ? '' : '?date=${_dateFmt.format(_selectedDate)}'}';
    if (mounted && _displayReads['reservations']?.query != query) {
      setState(() {
        _reservations = [];
        _displayReads = {};
        _isLoading = true;
      });
    }
    try {
      final rows = _showAll
          ? await MobileApiService.getReservations()
          : await MobileApiService.getReservations(
              date: _dateFmt.format(_selectedDate),
            );
      if (!mounted || generation != _readGeneration) return;
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
          _displayReads = {'reservations': MobileApiService.statusFor(rows)!};
          _reservations = rows;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _readGeneration) {
        setState(() {
          _readFailed(e, 'reservations');
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

  Future<ManagerOperationResult> _updateStatus(String id, String status) async {
    final result = await MobileApiService.updateReservationStatus(
      reservationId: id,
      expectedScope: _operationScope,
      status: status,
    );
    if (result.isDone) await _loadReservations();
    return result;
  }

  Future<ManagerOperationResult> _deleteReservation(String id) async {
    final result = await MobileApiService.deleteReservation(
      id,
      expectedScope: _operationScope,
    );
    if (result.isDone) await _loadReservations();
    return result;
  }

  Future<void> _pickReservationDate() async {
    final businessDate = _businessNow();
    final initial = _selectedDate.isBefore(businessDate)
        ? businessDate
        : _selectedDate;
    if (!kIsWeb && Platform.isIOS) {
      DateTime temp = initial;
      await showManagerModal<void>(
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
                    data: CupertinoThemeData(
                      brightness: MobileGlassTheme.data.isDark
                          ? Brightness.dark
                          : Brightness.light,
                    ),
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
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: MobileGlassTheme.primary),
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
        operationScope: _operationScope,
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
      final result = await MobileApiService.createWalkInOrder(
        expectedScope: _operationScope,
        newRequest: true,
        tableNumbers: tables,
        floor: floor,
        waiterName: widget.user.username,
        items: items,
      );
      if (!mounted ||
          _operationScope == null ||
          !MobileApiService.isCurrentTableRepairScope(_operationScope!))
        return;
      if (result.isDone) await _loadReservations();
      _toast(result.message, error: result.delivery.name == 'failed');
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

    return showManagerModal<Map<String, dynamic>>(
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
                        return InkWell(
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
                                    ? MobileGlassTheme.onPrimary
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
                          style: TextStyle(
                            color: MobileGlassTheme.onPrimary,
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
    return ManagerDataBoundary(
      reads: _displayReads,
      blocks: const {'reservations'},
      onRefresh: _loadReservations,
      child: ManagerOperationBoundary(
        scope: _operationScope,
        child: Scaffold(
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
        ),
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

  Widget _buildContent() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1424),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              color: MobileGlassTheme.primary,
              onRefresh: _loadReservations,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
                  4,
                  MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
                  32,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildModeToggle(),
                  ),
                  const SizedBox(height: 20),
                  if (!_showAll) ...[
                    _buildDateBar(),
                    const SizedBox(height: 22),
                  ],
                  _buildStatsCard(),
                  const SizedBox(height: 20),
                  ManagerPanel(
                    padding: MediaQuery.sizeOf(context).width < 700 ? 16 : 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ManagerSectionHeading(
                          _showAll
                              ? 'ყველა რეზერვაცია'
                              : '${_prettyFmt.format(_selectedDate)} · სტუმრები',
                        ),
                        if (MediaQuery.sizeOf(context).width >= 900)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    'დრო',
                                    style: managerDesignText(
                                      context,
                                      10,
                                      muted: true,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'სტუმარი',
                                    style: managerDesignText(
                                      context,
                                      10,
                                      muted: true,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'რაოდენობა',
                                    style: managerDesignText(
                                      context,
                                      10,
                                      muted: true,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'მაგიდა',
                                    style: managerDesignText(
                                      context,
                                      10,
                                      muted: true,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 158,
                                  child: Text(
                                    'სტატუსი',
                                    style: managerDesignText(
                                      context,
                                      10,
                                      muted: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_reservations.isEmpty)
                          _buildEmpty()
                        else if (_showAll)
                          ..._buildGroupedList()
                        else
                          ..._reservations.map(_buildReservationCard),
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
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          'რეზერვაციები',
          style: TextStyle(
            color: MobileGlassTheme.textPrimary,
            fontSize: constraints.maxWidth < 700 ? 25 : 30,
            fontWeight: FontWeight.w600,
          ),
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const Key('manager-new-reservation'),
              onPressed: _openCreate,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('ახალი რეზერვაცია'),
            ),
            OutlinedButton.icon(
              key: const Key('manager-walk-in'),
              onPressed: _isSubmitting ? null : _startWalkInFlow,
              icon: const Icon(Icons.directions_walk_rounded, size: 20),
              label: Text(
                _isSubmitting ? 'მუშავდება…' : 'სტუმარი რეზერვაციის გარეშე',
              ),
            ),
          ],
        );
        return constraints.maxWidth >= 1000
            ? Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 20),
                  actions,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 18), actions],
              );
      },
    ),
  );

  Widget _buildModeToggle() => ManagerSegments(
    labels: const ['დღე', 'ყველა'],
    selected: _showAll ? 1 : 0,
    onSelect: (value) {
      if (_showAll == (value == 1)) return;
      setState(() {
        _showAll = value == 1;
        _isLoading = true;
      });
      unawaited(_loadReservations());
    },
  );

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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final metric in [
          ('$total რეზერვაცია', MobileGlassTheme.primary),
          ('$confirmed დადასტურებული', MobileGlassTheme.good),
          ('$guests სტუმარი', MobileGlassTheme.textSecondary),
          ('$lastLabel · $lastValue', MobileGlassTheme.warn),
        ])
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: metric.$2.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              metric.$1,
              style: managerDesignText(
                context,
                11,
                weight: FontWeight.w500,
              ).copyWith(color: metric.$2),
            ),
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
                Flexible(
                  child: Text(
                    _prettyFmt.format(_selectedDate),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MobileGlassTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
              'აირჩიეთ „ახალი რეზერვაცია“',
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
    final meta = _statusMeta('${row['status'] ?? 'pending'}');
    final name = '${row['customerName'] ?? 'უსახელო'}';
    final time = '${row['reservationTime'] ?? '—'}';
    final guests = '${row['numberOfGuests'] ?? '—'}';
    final tables = (row['tableNumbers'] as List? ?? const []).join(', ');
    final small = MediaQuery.sizeOf(context).width < 900;
    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        meta.label,
        style: managerDesignText(
          context,
          11,
          weight: FontWeight.w500,
        ).copyWith(color: meta.color),
      ),
    );
    return Column(
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: () => _openDetail(row),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: small ? 12 : 22),
            child: Row(
              children: [
                if (small)
                  Container(
                    width: 52,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: managerThemeOf(context).scaffoldBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      time,
                      textAlign: TextAlign.center,
                      style: managerDesignText(
                        context,
                        12,
                        weight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: 90,
                    child: Text(
                      time,
                      style: managerDesignText(
                        context,
                        15,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (small) const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: managerDesignText(
                          context,
                          small ? 12 : 13,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        small
                            ? '$guests სტუმარი · მაგიდა ${tables.isEmpty ? '—' : tables}'
                            : '${row['customerPhone'] ?? ''}',
                        style: managerDesignText(context, 10, muted: true),
                      ),
                      if (small) ...[const SizedBox(height: 6), status],
                    ],
                  ),
                ),
                if (!small) ...[
                  Expanded(
                    child: Text(
                      '$guests სტუმარი',
                      style: managerDesignText(context, 12, muted: true),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tables.isEmpty ? '—' : tables,
                      style: managerDesignText(context, 12),
                    ),
                  ),
                  SizedBox(
                    width: 138,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: status,
                    ),
                  ),
                ],
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: MobileGlassTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ── shared dark glass widgets ───────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    final radius = BorderRadius.circular(18);
    return Material(
      color: theme.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: theme.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(18),
          child: child,
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onTap,
    this.dim = false,
  });
  final IconData icon;
  final VoidCallback onTap;
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
        color: theme.headerButtonBackground,
        border: Border.all(color: theme.cardBorder),
      ),
      child: Icon(
        icon,
        color: dim ? theme.textSecondary : theme.textPrimary,
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
    return InkWell(onTap: onTap, child: btn);
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
