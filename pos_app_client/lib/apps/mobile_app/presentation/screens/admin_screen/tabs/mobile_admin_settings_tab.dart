part of '../mobile_admin_screen.dart';

class _SettingsTab extends StatefulWidget {
  final User user;
  final VoidCallback onLogout;

  const _SettingsTab({required this.user, required this.onLogout});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic>? _settings;
  ManagerDashboardMetrics? _ops;
  bool _loadingRemote = true;
  bool _loadingOps = true;
  bool _remoteUnavailable = false;
  bool _opsUnavailable = false;

  @override
  void initState() {
    super.initState();
    MonitoringSocketService.isConnected.addListener(_onConnectionChanged);
    MonitoringSocketService.apiError.addListener(_onConnectionChanged);
    _loadAll();
  }

  @override
  void dispose() {
    MonitoringSocketService.isConnected.removeListener(_onConnectionChanged);
    MonitoringSocketService.apiError.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    if (_isServerReachable) {
      _loadAll();
    } else {
      setState(() {
        _loadingRemote = false;
        _loadingOps = false;
        _remoteUnavailable = true;
        _opsUnavailable = true;
      });
    }
  }

  bool get _isServerReachable {
    return MonitoringSocketService.isConnected.value &&
        !MonitoringSocketService.apiError.value;
  }

  String get _connectionStatusLabel {
    if (!MonitoringSocketService.isConnected.value) {
      return 'სერვერთან კავშირი არ არის';
    }
    if (MonitoringSocketService.apiError.value) {
      return 'სერვერზე პრობლემაა';
    }
    return 'კავშირი სტაბილურია';
  }

  Future<void> _loadAll() async {
    if (!_isServerReachable) {
      if (mounted) {
        setState(() {
          _loadingRemote = false;
          _loadingOps = false;
          _remoteUnavailable = true;
          _opsUnavailable = true;
        });
      }
      return;
    }

    setState(() {
      _loadingRemote = true;
      _loadingOps = true;
      _remoteUnavailable = false;
      _opsUnavailable = false;
    });

    await Future.wait([_loadRestaurantSettings(), _loadOperations()]);
  }

  Future<void> _loadRestaurantSettings() async {
    try {
      final data = await MobileApiService.getRestaurantSettings(
        throwOnFailure: true,
      );
      if (!mounted) return;
      setState(() {
        _settings = Map<String, dynamic>.from(data);
        _loadingRemote = false;
        _remoteUnavailable = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRemote = false;
        _remoteUnavailable = true;
      });
    }
  }

  Future<void> _loadOperations() async {
    try {
      final metrics = await MobileApiService.getDashboard();
      if (!mounted) return;
      setState(() {
        _ops = metrics;
        _loadingOps = false;
        _opsUnavailable = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOps = false;
        _opsUnavailable = true;
      });
    }
  }

  String _formatOpened(String? isoUtc) {
    if (isoUtc == null || isoUtc.isEmpty) return '—';
    final dt = DateTime.tryParse(isoUtc);
    if (dt == null) return '—';
    return DateFormat('HH:mm · dd.MM.yyyy').format(dt.toLocal());
  }

  String _formatShiftDuration(ManagerDashboardMetrics? m) {
    if (m == null) return '—';
    final mins = m.businessDayDurationMinutes;
    if (mins != null) {
      if (mins < 60) return '$mins წთ';
      final h = mins ~/ 60;
      final r = mins % 60;
      return r == 0 ? '$h სთ' : '$h სთ $r წთ';
    }
    final opened = m.businessDayOpenedAt;
    if (opened != null && opened.isNotEmpty) {
      final start = DateTime.tryParse(opened);
      if (start != null) {
        final mins = DateTime.now().difference(start.toLocal()).inMinutes;
        if (mins < 60) return '$mins წთ';
        return '${mins ~/ 60} სთ ${mins % 60} წთ';
      }
    }
    return '—';
  }

  String _businessDayStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'OPEN':
        return 'ღია';
      case 'CLOSED':
        return 'დახურული';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _settings;
    final restaurantName = s == null
        ? null
        : (s['restaurantName'] ?? s['name'])?.toString();
    final serviceFee = (s?['serviceFeePercent'] as num?)?.toDouble();
    final serviceFeeEnabled = s?['serviceFeeEnabled'] as bool? ?? false;
    final currency = s?['currency']?.toString();
    final showRestaurantSkeleton = _loadingRemote && s == null;
    final restaurantDisabled = _remoteUnavailable || showRestaurantSkeleton;
    final showOpsSkeleton = _loadingOps && _ops == null;
    final opsDisabled = _opsUnavailable || showOpsSkeleton;
    final ops = _ops;
    final businessDate =
        ops?.businessDate ??
        MonitoringSocketService.currentBusinessDate.value ??
        '—';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: _adminScrollPadding(context),
      children: [
        if (_remoteUnavailable || _opsUnavailable) ...[
          const _AdminOfflineBanner(
            message:
                'სერვერთან კავშირი არ არის. ოპერაციული და რესტორანის მონაცემები განახლდება კავშირის აღდგენისას.',
          ),
          SizedBox(height: 16),
        ],
        _SettingsSection(
          title: 'ოპერაცია',
          children: showOpsSkeleton
              ? [
                  _SettingsTileSkeleton(),
                  _SettingsTileSkeleton(),
                  _SettingsTileSkeleton(),
                  _SettingsTileSkeleton(),
                ]
              : [
                  _SettingsTile(
                    icon: Icons.today_outlined,
                    label: 'საქმიანი დღე',
                    value: businessDate,
                    unavailable: opsDisabled,
                  ),
                  _SettingsTile(
                    icon: Icons.schedule_outlined,
                    label: 'სტატუსი',
                    value: ops != null
                        ? _businessDayStatusLabel(ops.businessDayStatus)
                        : '—',
                    unavailable: opsDisabled,
                  ),
                  _SettingsTile(
                    icon: Icons.play_circle_outline,
                    label: 'ცვლის დაწყება',
                    value: _formatOpened(ops?.businessDayOpenedAt),
                    unavailable: opsDisabled,
                  ),
                  _SettingsTile(
                    icon: Icons.timelapse_outlined,
                    label: 'ხანგრძლივობა',
                    value: _formatShiftDuration(ops),
                    unavailable: opsDisabled,
                  ),
                  _SettingsTile(
                    icon: Icons.table_bar_outlined,
                    label: 'მაგიდები',
                    value: ops != null
                        ? '${ops.occupiedTables} დაკავებული / ${ops.totalTables} სულ'
                        : '—',
                    unavailable: opsDisabled,
                  ),
                  _SettingsTile(
                    icon: Icons.receipt_outlined,
                    label: 'შეკვეთები დღეს',
                    value: ops != null ? '${ops.todayOrderCount}' : '—',
                    unavailable: opsDisabled,
                  ),
                ],
        ),
        SizedBox(height: 16),
        _SettingsSection(
          title: 'სესია',
          children: [
            _SettingsTile(
              icon: Icons.person_rounded,
              label: 'მომხმარებელი',
              value: widget.user.username,
            ),
            _SettingsTile(
              icon: Icons.admin_panel_settings_rounded,
              label: 'როლი',
              value: widget.user.roleLabelKa,
            ),
          ],
        ),
        SizedBox(height: 16),
        _SettingsSection(
          title: 'რესტორანი',
          children: showRestaurantSkeleton
              ? [
                  _SettingsTileSkeleton(),
                  _SettingsTileSkeleton(),
                  _SettingsTileSkeleton(),
                ]
              : [
                  _SettingsTile(
                    icon: Icons.storefront_rounded,
                    label: 'სახელი',
                    value: restaurantName ?? '—',
                    unavailable: restaurantDisabled || restaurantName == null,
                  ),
                  _SettingsTile(
                    icon: Icons.percent_rounded,
                    label: 'სერვისის ფი',
                    value: serviceFee != null
                        ? '${serviceFee.toStringAsFixed(0)}%${serviceFeeEnabled ? '' : ' (გამორთ.)'}'
                        : '—',
                    unavailable: restaurantDisabled || serviceFee == null,
                  ),
                  _SettingsTile(
                    icon: Icons.payments_rounded,
                    label: 'ვალუტა',
                    value: currency ?? 'GEL',
                    unavailable: restaurantDisabled && currency == null,
                  ),
                ],
        ),
        SizedBox(height: 16),
        _SettingsSection(
          title: 'კავშირი',
          children: [
            _SettingsTile(
              icon: Icons.hub_outlined,
              label: 'სტატუსი',
              value: _connectionStatusLabel,
              unavailable: !MonitoringSocketService.isConnected.value,
            ),
            _SettingsTile(
              icon: Icons.dns_rounded,
              label: 'Backend',
              value: ApiConfig.baseUrl,
              small: true,
            ),
          ],
        ),
        SizedBox(height: 16),
        _SettingsSection(
          title: 'აპლიკაცია',
          children: [
            const _SettingsTile(
              icon: Icons.smartphone_outlined,
              label: 'ვერსია',
              value: '1.0.0',
            ),
            ValueListenableBuilder<ManagerDashboardAppearance>(
              valueListenable: ManagerAppPreferences.dashboardAppearance,
              builder: (context, appearance, _) {
                return _DashboardAppearanceTile(
                  appearance: appearance,
                  onChanged: ManagerAppPreferences.setDashboardAppearance,
                );
              },
            ),
          ],
        ),
        SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: Icon(Icons.logout_rounded, color: AdminTheme.bad),
            label: Text(
              'გასვლა',
              style: TextStyle(
                color: AdminTheme.bad,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AdminTheme.bad, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminSectionTitle(title: title),
          _AdminPanel(
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      );
}

class _DashboardAppearanceTile extends StatelessWidget {
  final ManagerDashboardAppearance appearance;
  final Future<void> Function(ManagerDashboardAppearance) onChanged;

  const _DashboardAppearanceTile({
    required this.appearance,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.palette_outlined,
            size: 20,
            color: AdminTheme.primary,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'დაფის თემა',
                  style: TextStyle(fontSize: 12, color: AdminTheme.textDim),
                ),
                Text(
                  'ღია ან მუქი გარეგნობა',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.text,
                  ),
                ),
              ],
            ),
          ),
          SegmentedButton<ManagerDashboardAppearance>(
            segments: [
              for (final mode in ManagerDashboardAppearance.values)
                ButtonSegment(
                  value: mode,
                  label: Text(mode.labelGeorgian),
                ),
            ],
            selected: {appearance},
            onSelectionChanged: (selected) {
              final next = selected.first;
              if (next != appearance) {
                onChanged(next);
              }
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool small;
  final bool unavailable;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    this.small = false,
    this.unavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final muted = unavailable;
    return Opacity(
      opacity: muted ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: muted ? AdminTheme.textDim : AdminTheme.primary,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminTheme.textDim,
                    ),
                  ),
                  Text(
                    muted ? 'მიუწვდომელია' : value,
                    style: TextStyle(
                      fontSize: small ? 12 : 14,
                      fontWeight: FontWeight.w600,
                      color: muted ? AdminTheme.textDim : AdminTheme.text,
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
}
