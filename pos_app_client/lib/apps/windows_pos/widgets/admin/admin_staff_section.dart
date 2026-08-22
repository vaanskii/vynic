import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

const Color _staffPrimary = AdminDesign.accentDark;
const Color _staffAccent = AdminDesign.accent;
const Color _staffSurface = AdminDesign.panelSoft;
const Color _staffCard = AdminDesign.panel;
const Color _staffBorder = AdminDesign.border;
const Color _staffText = AdminDesign.text;
const Color _staffMuted = AdminDesign.muted;

const TextStyle _staffFieldLabel = TextStyle(
  color: _staffMuted,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

const TextStyle _staffTableHeaderStyle = TextStyle(
  color: _staffMuted,
  fontSize: 11,
  fontWeight: FontWeight.w700,
);

InputDecoration _staffInputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(color: _staffMuted.withValues(alpha: 0.7)),
  filled: true,
  fillColor: _staffSurface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AdminDesign.radius),
    borderSide: const BorderSide(color: _staffBorder),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AdminDesign.radius),
    borderSide: const BorderSide(color: _staffAccent, width: 1.4),
  ),
);

/// Combined staff create + directory (replaces separate waiters / users tabs).
class AdminStaffSection extends StatefulWidget {
  const AdminStaffSection({super.key, required this.user});

  final User user;

  @override
  State<AdminStaffSection> createState() => _AdminStaffSectionState();
}

enum _StaffListFilter { all, manager, supervisor, waiter }

class _AdminStaffSectionState extends State<AdminStaffSection> {
  _StaffListFilter _listFilter = _StaffListFilter.all;
  int _listVersion = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _waitersOnlyAdmin => widget.user.isSupervisor;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshList() => setState(() => _listVersion++);

  List<User> get _allUsers => DatabaseService.getAllUsers();

  List<User> get _directoryUsers {
    final users = _waitersOnlyAdmin
        ? _allUsers.where((u) => u.isWaiter)
        : _filteredUsers;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return users.toList();
    }
    return users.where((user) {
      return user.username.toLowerCase().contains(query) ||
          user.roleLabelKa.toLowerCase().contains(query);
    }).toList();
  }

  List<User> get _filteredUsers {
    final users = _allUsers;
    switch (_listFilter) {
      case _StaffListFilter.manager:
        return users.where((u) => u.isManager).toList();
      case _StaffListFilter.supervisor:
        return users.where((u) => u.isSupervisor).toList();
      case _StaffListFilter.waiter:
        return users.where((u) => u.isWaiter).toList();
      case _StaffListFilter.all:
        return users;
    }
  }

  Future<void> _openAddStaffDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _AddStaffDialog(waiterOnly: _waitersOnlyAdmin),
    );
    if (created == true && mounted) _refreshList();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final managers = _allUsers.where((u) => u.isManager).length;
    final supervisors = _allUsers.where((u) => u.isSupervisor).length;
    final waiters = _allUsers.where((u) => u.isWaiter).length;

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
                    _buildPageHeader(isMobile),
                    if (_waitersOnlyAdmin) ...[
                      const SizedBox(height: 14),
                      _buildSupervisorAccessNotice(isMobile),
                    ],
                    const SizedBox(height: 16),
                    if (_waitersOnlyAdmin)
                      _buildKpiRow(
                        total: waiters,
                        managers: 0,
                        supervisors: 0,
                        waiters: waiters,
                        isMobile: isMobile,
                        waitersOnly: true,
                      )
                    else
                      _buildKpiRow(
                        total: _allUsers.length,
                        managers: managers,
                        supervisors: supervisors,
                        waiters: waiters,
                        isMobile: isMobile,
                      ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showSidePanel = constraints.maxWidth >= 700;
                        final compactDirectory = constraints.maxWidth < 1040;
                        final rolesPanelWidth = constraints.maxWidth < 1120
                            ? 260.0
                            : 330.0;
                        if (!showSidePanel) {
                          return Column(
                            children: [
                              _buildDirectory(isMobile),
                              const SizedBox(height: 14),
                              _buildRolesPanel(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildDirectory(
                                isMobile || compactDirectory,
                              ),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: rolesPanelWidth,
                              child: _buildRolesPanel(),
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

  Widget _buildSupervisorAccessNotice(bool isMobile) {
    const noticeBorder = AdminTones.warningBorder;
    const noticeBg = AdminTones.warningFill;
    const noticeTitle = AdminTones.warningText;
    const noticeBody = AdminTones.warningText;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 16),
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
              children: [
                Text(
                  'სუპერვაიზერის შეზღუდვები',
                  style: TextStyle(
                    color: noticeTitle,
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ამ განყოფილებაში შეგიძლიათ მხოლოდ ოფიციანტების მართვა:\n'
                  '• ახალი თანამშრომლის დამატება — მხოლოდ ოფიციანტის როლით\n'
                  '• სიაში ჩანს მხოლოდ ოფიციანტები\n'
                  '• PIN-ის ნახვა და შეცვლა — მხოლოდ ოფიციანტებისთვის\n'
                  '• მენეჯერისა და სხვა სუპერვაიზერის PIN-ები არ ჩანს',
                  style: TextStyle(
                    color: noticeBody,
                    fontSize: isMobile ? 12.5 : 13,
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

  Widget _buildPageHeader(bool isMobile) {
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
            Icons.groups_2_outlined,
            color: AdminDesign.accentDark,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'პერსონალი',
                style: TextStyle(
                  color: _staffText,
                  fontSize: isMobile ? 23 : 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _waitersOnlyAdmin
                    ? 'ოფიციანტების დამატება და PIN-ების მართვა.'
                    : 'მართეთ თანამშრომლები, როლები და PIN-ები.',
                style: const TextStyle(color: _staffMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (!isMobile)
          AdminStatusBadge(
            icon: Icons.badge_outlined,
            label: '${_allUsers.length} თანამშრომელი',
          ),
      ],
    );
  }

  Widget _buildKpiRow({
    required int total,
    required int managers,
    required int supervisors,
    required int waiters,
    required bool isMobile,
    bool waitersOnly = false,
  }) {
    final items = waitersOnly
        ? [
            _KpiChip(
              label: 'ყველა ოფიციანტი',
              value: waiters,
              color: AdminTones.successText,
              icon: Icons.groups_2_outlined,
            ),
          ]
        : [
            _KpiChip(
              label: 'სულ თანამშრომლები',
              value: total,
              color: AdminTones.successText,
              icon: Icons.groups_2_outlined,
            ),
            _KpiChip(
              label: 'მენეჯერი',
              value: managers,
              color: AdminDesign.accentDark,
              icon: Icons.admin_panel_settings_outlined,
            ),
            _KpiChip(
              label: 'სუპერვაიზერი',
              value: supervisors,
              color: AdminDesign.accentDark,
              icon: Icons.supervisor_account_outlined,
            ),
            _KpiChip(
              label: 'ოფიციანტი',
              value: waiters,
              color: AdminTones.warningText,
              icon: Icons.room_service_outlined,
            ),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = isMobile || constraints.maxWidth < 520
            ? 1
            : constraints.maxWidth >= 700
            ? items.length
            : 2;
        final spacing = 12.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _KpiChip(
                    label: item.label,
                    value: item.value,
                    color: item.color,
                    icon: item.icon,
                    compact: width < 230,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildDirectory(bool isMobile) {
    // ignore: unused_local_variable — bumps rebuild
    final _ = _listVersion;
    final users = _directoryUsers;

    return Container(
      decoration: AdminDesign.panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final title = const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.manage_accounts_outlined,
                      color: _staffText,
                      size: 21,
                    ),
                    SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        'თანამშრომლების სია',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _staffText,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                );
                final searchField = SizedBox(
                  height: 42,
                  child: PosOnScreenTextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    style: const TextStyle(color: _staffText, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ძებნა სახელით ან როლით...',
                      hintStyle: const TextStyle(
                        color: _staffMuted,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 19,
                        color: _staffMuted,
                      ),
                      filled: true,
                      fillColor: _staffSurface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                        borderSide: const BorderSide(color: _staffBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                        borderSide: const BorderSide(color: _staffBorder),
                      ),
                    ),
                  ),
                );
                final controls = Row(
                  mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    // 270 is the field's preferred width, not a floor. It used
                    // to be a hard SizedBox, so once the title and the filter
                    // button had taken their share there was nothing left to
                    // give and the row overflowed instead of the field
                    // shrinking.
                    if (compact)
                      Expanded(child: searchField)
                    else
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 270),
                          child: searchField,
                        ),
                      ),
                    if (!_waitersOnlyAdmin) ...[
                      const SizedBox(width: 8),
                      _buildFilterMenu(iconOnly: compact),
                    ],
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 12), controls],
                  );
                }
                return Row(
                  children: [
                    Flexible(child: title),
                    const SizedBox(width: 12),
                    const Spacer(),
                    Flexible(child: controls),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, color: _staffBorder),
          if (!isMobile) _buildTableHeader(),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.person_search_outlined,
                    size: 36,
                    color: _staffMuted,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'თანამშრომელი ვერ მოიძებნა',
                    style: TextStyle(color: _staffMuted, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            ...users.asMap().entries.map(
              (entry) => _StaffUserTile(
                user: entry.value,
                showDivider: entry.key < users.length - 1,
                showPin: widget.user.canViewStaffPinOf(entry.value),
                canManage: widget.user.canManageStaffUser(entry.value),
                canChangeRole: widget.user.canManageAllStaffInAdmin,
                useCompactLayout: isMobile,
                onEditName: () => _showEditNameDialog(entry.value),
                onChangePin: () => _showChangePinDialog(entry.value),
                onChangeRole: () => _showChangeRoleDialog(entry.value),
                onDelete: () => _confirmDeleteUser(entry.value),
              ),
            ),
          if (users.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: _staffSurface,
                border: Border(top: BorderSide(color: _staffBorder)),
              ),
              child: Text(
                '${users.length} ჩანაწერი',
                style: const TextStyle(
                  color: _staffMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: _staffSurface,
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: EdgeInsets.only(left: 44),
              child: Text('სახელი', style: _staffTableHeaderStyle),
            ),
          ),
          Expanded(flex: 4, child: Text('როლი', style: _staffTableHeaderStyle)),
          Expanded(flex: 4, child: Text('PIN', style: _staffTableHeaderStyle)),
          SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _buildFilterMenu({required bool iconOnly}) {
    return PopupMenuButton<_StaffListFilter>(
      tooltip: 'ფილტრი',
      initialValue: _listFilter,
      onSelected: (value) => setState(() => _listFilter = value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: _StaffListFilter.all, child: Text('ყველა')),
        PopupMenuItem(value: _StaffListFilter.manager, child: Text('მენეჯერი')),
        PopupMenuItem(
          value: _StaffListFilter.supervisor,
          child: Text('სუპერვაიზერი'),
        ),
        PopupMenuItem(value: _StaffListFilter.waiter, child: Text('ოფიციანტი')),
      ],
      child: Container(
        height: 42,
        width: iconOnly ? 42 : null,
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          border: Border.all(color: _staffBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_outlined, size: 18, color: _staffText),
            if (!iconOnly) ...[
              const SizedBox(width: 7),
              const Text(
                'ფილტრი',
                style: TextStyle(
                  color: _staffText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRolesPanel() {
    return Column(
      children: [
        _StaffCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security_outlined, color: _staffText, size: 21),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'როლები და წვდომა',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _staffText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _RoleAccessTile(
                icon: Icons.admin_panel_settings_outlined,
                title: 'მენეჯერი',
                description:
                    'სრული ადმინისტრაციული წვდომა, პერსონალი და ანგარიშები.',
                color: AdminDesign.accentDark,
              ),
              const SizedBox(height: 9),
              _RoleAccessTile(
                icon: Icons.supervisor_account_outlined,
                title: 'სუპერვაიზერი',
                description:
                    'ოპერაციული მართვა და ოფიციანტების შეზღუდული კონტროლი.',
                color: AdminDesign.accentDark,
              ),
              const SizedBox(height: 9),
              _RoleAccessTile(
                icon: Icons.room_service_outlined,
                title: 'ოფიციანტი',
                description:
                    'შეკვეთები, მაგიდები და რეზერვაციის სამზარეულოს ჩეკი.',
                color: AdminTones.warningText,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _StaffCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: _staffPrimary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'PIN კოდი უნიკალური უნდა იყოს. მენეჯერი მართავს ყველა როლს, სუპერვაიზერი კი მხოლოდ ოფიციანტებს.',
                  style: TextStyle(
                    color: _staffMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 11, 22, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _staffBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final action = ElevatedButton.icon(
            onPressed: _openAddStaffDialog,
            style: AdminDesign.primaryButtonStyle(),
            icon: const Icon(Icons.person_add_alt_1, size: 19),
            label: Text(
              _waitersOnlyAdmin ? 'ახალი ოფიციანტი' : 'ახალი თანამშრომელი',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          );
          if (compact) {
            return SizedBox(width: double.infinity, child: action);
          }
          return Row(
            children: [
              const Icon(Icons.info_outline, color: _staffPrimary, size: 20),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'ყველა ცვლილება ინახება მოქმედების დასრულებისთანავე.',
                  style: TextStyle(color: _staffMuted, fontSize: 12),
                ),
              ),
              action,
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditNameDialog(User user) async {
    if (!widget.user.canManageStaffUser(user)) return;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _EditStaffNameDialog(user: user),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    if (newName == user.username) return;

    final ok = await DatabaseService.renameUserByUsername(
      oldUsername: user.username,
      newUsername: newName,
    );
    if (!ok) {
      unawaited(
        showErrorToast(context, 'სახელი ვერ შეიცვალა (შესაძლოა უკვე არსებობს)'),
      );
      return;
    }
    _refreshList();
    unawaited(showSuccessToast(context, 'სახელი განახლდა — $newName'));
  }

  Future<void> _showChangePinDialog(User user) async {
    if (!widget.user.canManageStaffUser(user)) return;

    final newPin = await showDialog<String>(
      context: context,
      builder: (context) => _ChangePinDialog(user: user),
    );
    if (newPin == null || newPin.isEmpty || !mounted) return;

    final ok = await DatabaseService.updateUserPinByUsername(
      username: user.username,
      pinCode: newPin,
    );
    if (!ok) {
      unawaited(showErrorToast(context, 'PIN-ის შენახვა ვერ მოხერხდა'));
      return;
    }
    _refreshList();
    unawaited(showSuccessToast(context, 'PIN განახლდა — ${user.username}'));
  }

  Future<void> _showChangeRoleDialog(User user) async {
    if (!widget.user.canManageAllStaffInAdmin) return;
    final isOnlyManager =
        user.isManager &&
        _allUsers.where((entry) => entry.isManager).length <= 1;

    final role = await showDialog<String>(
      context: context,
      builder: (context) =>
          _ChangeRoleDialog(user: user, preventManagerDemotion: isOnlyManager),
    );
    if (role == null || !mounted) return;
    if (StaffRole.normalizeClient(role) == user.normalizedRole) return;

    final ok = await DatabaseService.updateUserRoleByUsername(
      username: user.username,
      role: role,
    );
    if (!mounted) return;
    if (!ok) {
      unawaited(
        showErrorToast(context, 'ბოლო მენეჯერის როლის შეცვლა არ შეიძლება'),
      );
      return;
    }
    _refreshList();
    unawaited(
      showSuccessToast(
        context,
        '${user.username} — ${StaffRole.labelKa(role)}',
      ),
    );
  }

  Future<void> _confirmDeleteUser(User user) async {
    if (!widget.user.canManageStaffUser(user)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _staffCard,
        title: const Text('წაშლა', style: TextStyle(color: _staffText)),
        content: Text(
          'დარწმუნებული ხართ, რომ გსურთ „${user.username}“ წაშლა?',
          style: const TextStyle(color: _staffMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminDesign.danger),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await DatabaseService.deleteUserByUsername(user.username);
    if (!deleted) {
      unawaited(showErrorToast(context, 'ბოლო მენეჯერის წაშლა არ შეიძლება'));
      return;
    }
    _refreshList();
    unawaited(
      showPosToast(
        context: context,
        message: '„${user.username}“ წაიშალა',
        style: PosToastStyle.info,
      ),
    );
  }
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog({this.waiterOnly = false});

  final bool waiterOnly;

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _usernameController = TextEditingController();
  String _pinCode = '';
  String _selectedRole = StaffRole.waiter;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _showPinPicker() async {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    var tempPin = _pinCode;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: _staffCard,
            insetPadding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 40,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminDesign.radius),
              side: const BorderSide(color: _staffBorder),
            ),
            child: SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'PIN კოდი',
                      style: TextStyle(
                        color: _staffText,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: _staffSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _staffBorder),
                      ),
                      child: Center(
                        child: Text(
                          tempPin.isEmpty ? '------' : tempPin.padRight(6, '-'),
                          style: const TextStyle(
                            color: _staffText,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _PinPad(
                      onDigit: (d) {
                        if (tempPin.length < 6) {
                          setDialogState(() => tempPin += d);
                        }
                      },
                      onBackspace: () {
                        if (tempPin.isNotEmpty) {
                          setDialogState(
                            () => tempPin = tempPin.substring(
                              0,
                              tempPin.length - 1,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('გაუქმება'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: tempPin.length == 6
                                ? () {
                                    setState(() => _pinCode = tempPin);
                                    Navigator.pop(dialogContext);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _staffAccent,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('შენახვა'),
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
      ),
    );
  }

  Future<void> _createStaff() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      unawaited(showErrorToast(context, 'შეიყვანეთ სახელი'));
      return;
    }
    if (_pinCode.length != 6) {
      unawaited(showErrorToast(context, 'PIN უნდა იყოს 6 ციფრი'));
      return;
    }
    if (DatabaseService.isPinCodeExists(_pinCode)) {
      unawaited(showErrorToast(context, 'ეს PIN უკვე გამოიყენება'));
      return;
    }

    final role = widget.waiterOnly
        ? StaffRole.waiter
        : StaffRole.normalizeClient(_selectedRole);
    final ok = await DatabaseService.addUser(
      username: username,
      pinCode: _pinCode,
      role: role,
    );
    if (!mounted) return;

    if (ok) {
      unawaited(
        showSuccessToast(
          context,
          '${StaffRole.labelKa(role)} „$username“ დაემატა',
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      unawaited(showErrorToast(context, 'შექმნა ვერ მოხერხდა'));
    }
  }

  Widget _roleChip(String role, String label) {
    final selected = StaffRole.normalizeClient(_selectedRole) == role;
    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _staffAccent : _staffSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _staffAccent : _staffBorder),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : _staffMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Dialog(
      backgroundColor: _staffCard,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _staffBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _staffAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1,
                      color: _staffAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.waiterOnly
                          ? 'ახალი ოფიციანტი'
                          : 'ახალი თანამშრომელი',
                      style: const TextStyle(
                        color: _staffText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: _staffMuted,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('სახელი', style: _staffFieldLabel),
                      const SizedBox(height: 8),
                      PosOnScreenTextField(
                        controller: _usernameController,
                        style: const TextStyle(color: _staffText),
                        decoration: _staffInputDecoration(
                          shouldUsePosOnScreenKeyboard()
                              ? 'დააჭირეთ სახელის შესაყვანად'
                              : 'მაგ. გიორგი',
                        ),
                        onChanged: (_) {
                          if (mounted) setState(() {});
                        },
                      ),
                      if (!widget.waiterOnly) ...[
                        const SizedBox(height: 16),
                        const Text('როლი', style: _staffFieldLabel),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 8.0;
                            final columns = constraints.maxWidth >= 390 ? 3 : 1;
                            final width =
                                (constraints.maxWidth -
                                    (spacing * (columns - 1))) /
                                columns;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                SizedBox(
                                  width: width,
                                  child: _roleChip(
                                    StaffRole.waiter,
                                    StaffRole.labelKa(StaffRole.waiter),
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _roleChip(
                                    StaffRole.supervisor,
                                    StaffRole.labelKa(StaffRole.supervisor),
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _roleChip(
                                    StaffRole.manager,
                                    StaffRole.labelKa(StaffRole.manager),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text('PIN (6 ციფრი)', style: _staffFieldLabel),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _showPinPicker,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _staffSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _staffBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _pinCode.isEmpty
                                    ? '------'
                                    : _pinCode.padRight(6, '•'),
                                style: const TextStyle(
                                  color: _staffText,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 6,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.dialpad, color: _staffAccent),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('გაუქმება'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _createStaff,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'დამატება',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _staffAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _staffCard,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: _staffBorder),
        boxShadow: [
          BoxShadow(
            color: _staffPrimary.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.compact = false,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _staffCard,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: _staffBorder),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: compact ? 21 : 25),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _staffMuted,
                    fontSize: compact ? 10 : 11,
                    height: 1.15,
                  ),
                ),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: _staffText,
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

class _EditStaffNameDialog extends StatefulWidget {
  const _EditStaffNameDialog({required this.user});

  final User user;

  @override
  State<_EditStaffNameDialog> createState() => _EditStaffNameDialogState();
}

class _EditStaffNameDialogState extends State<_EditStaffNameDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.username);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Dialog(
      backgroundColor: _staffCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: _staffBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 420),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 20 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'სახელის შეცვლა',
                style: TextStyle(
                  color: _staffText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const Text('სახელი', style: _staffFieldLabel),
              const SizedBox(height: 8),
              PosOnScreenTextField(
                controller: _nameController,
                style: const TextStyle(color: _staffText),
                decoration: _staffInputDecoration(
                  shouldUsePosOnScreenKeyboard()
                      ? 'დააჭირეთ სახელის შესაყვანად'
                      : 'სახელი',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('გაუქმება'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _staffAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('შენახვა'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({
    required this.user,
    required this.preventManagerDemotion,
  });

  final User user;
  final bool preventManagerDemotion;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late String _selectedRole;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.user.normalizedRole;
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final roles = StaffRole.assignableClientRoles;

    return Dialog(
      backgroundColor: _staffCard,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: _staffBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'როლის შეცვლა • ${widget.user.username}',
                style: const TextStyle(
                  color: _staffText,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'აირჩიეთ თანამშრომლის ახალი წვდომის დონე.',
                style: TextStyle(color: _staffMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final columns = constraints.maxWidth >= 390 ? 3 : 1;
                  final width =
                      (constraints.maxWidth - (spacing * (columns - 1))) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: roles.map((role) {
                      final selected = _selectedRole == role;
                      return SizedBox(
                        width: width,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AdminDesign.radius,
                          ),
                          onTap: () {
                            if (widget.preventManagerDemotion &&
                                role != StaffRole.manager) {
                              unawaited(
                                showErrorToast(
                                  context,
                                  'როლის შესაცვლელად საჭიროა მეორე მენეჯერის ანგარიში',
                                ),
                              );
                              return;
                            }
                            setState(() => _selectedRole = role);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AdminDesign.accentDark
                                  : _staffSurface,
                              borderRadius: BorderRadius.circular(
                                AdminDesign.radius,
                              ),
                              border: Border.all(
                                color: selected
                                    ? AdminDesign.accentDark
                                    : _staffBorder,
                              ),
                            ),
                            child: Text(
                              StaffRole.labelKa(role),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: selected ? Colors.white : _staffText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('გაუქმება'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _selectedRole),
                      style: AdminDesign.primaryButtonStyle(),
                      child: const Text('შენახვა'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffUserTile extends StatelessWidget {
  const _StaffUserTile({
    required this.user,
    required this.showDivider,
    required this.showPin,
    required this.canManage,
    required this.canChangeRole,
    required this.useCompactLayout,
    required this.onEditName,
    required this.onChangePin,
    required this.onChangeRole,
    required this.onDelete,
  });

  final User user;
  final bool showDivider;
  final bool showPin;
  final bool canManage;
  final bool canChangeRole;
  final bool useCompactLayout;
  final VoidCallback onEditName;
  final VoidCallback onChangePin;
  final VoidCallback onChangeRole;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isManager = user.isManager;
    final isSupervisor = user.isSupervisor;
    final accent = isManager
        ? _staffAccent
        : isSupervisor
        ? AdminDesign.accentDark
        : _staffPrimary;
    final allUsers = DatabaseService.getAllUsers();
    final canDelete =
        !isManager || allUsers.where((u) => u.isManager).length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = useCompactLayout;
        final avatar = CircleAvatar(
          radius: 17,
          backgroundColor: accent.withValues(alpha: 0.13),
          child: Icon(
            isManager
                ? Icons.shield_outlined
                : isSupervisor
                ? Icons.supervisor_account_outlined
                : Icons.person_outline,
            color: accent,
            size: 19,
          ),
        );
        final actions = canManage
            ? PopupMenuButton<String>(
                tooltip: 'მოქმედებები',
                icon: const Icon(Icons.more_vert, color: _staffText, size: 20),
                onSelected: (value) {
                  switch (value) {
                    case 'name':
                      onEditName();
                      return;
                    case 'pin':
                      onChangePin();
                      return;
                    case 'role':
                      onChangeRole();
                      return;
                    case 'delete':
                      onDelete();
                      return;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'name',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('სახელის შეცვლა'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'pin',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.pin_outlined),
                      title: Text('PIN-ის შეცვლა'),
                    ),
                  ),
                  if (canChangeRole)
                    const PopupMenuItem(
                      value: 'role',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.manage_accounts_outlined),
                        title: Text('როლის შეცვლა'),
                      ),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.delete_outline,
                          color: AdminDesign.danger,
                        ),
                        title: Text(
                          'წაშლა',
                          style: TextStyle(color: AdminDesign.danger),
                        ),
                      ),
                    ),
                ],
              )
            : const SizedBox(width: 42);

        if (compact) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: showDivider
                  ? const Border(bottom: BorderSide(color: _staffBorder))
                  : null,
            ),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username,
                        style: const TextStyle(
                          color: _staffText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user.roleLabelKa,
                        style: const TextStyle(
                          color: _staffMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        showPin ? 'PIN: ${user.pinCode}' : 'PIN დაცულია',
                        style: const TextStyle(
                          color: _staffText,
                          fontSize: 12,
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
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(bottom: BorderSide(color: _staffBorder))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        user.username,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _staffText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: InkWell(
                  onTap: canChangeRole ? onChangeRole : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            user.roleLabelKa,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (canChangeRole) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, color: accent, size: 17),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  showPin ? user.pinCode : '••••••',
                  style: const TextStyle(
                    color: _staffText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              SizedBox(width: 42, child: actions),
            ],
          ),
        );
      },
    );
  }
}

class _RoleAccessTile extends StatelessWidget {
  const _RoleAccessTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _staffSurface,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: _staffBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _staffText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: _staffMuted,
                    fontSize: 11,
                    height: 1.35,
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

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget row(List<String> keys) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          PinButton(
            number: keys[i],
            onPressed: keys[i] == '⌫' ? onBackspace : () => onDigit(keys[i]),
            isSpecial: keys[i] == '⌫',
          ),
        ],
      ],
    );

    return Column(
      children: [
        row(['1', '2', '3']),
        const SizedBox(height: 10),
        row(['4', '5', '6']),
        const SizedBox(height: 10),
        row(['7', '8', '9']),
        const SizedBox(height: 10),
        row(['', '0', '⌫']),
      ],
    );
  }
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({required this.user});
  final User user;

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  String _enteredPin = '';
  String _errorMessage = '';

  void _onNumberPressed(String number) {
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += number;
        _errorMessage = '';
      });
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = '';
      });
    }
  }

  void _onConfirm() {
    if (_enteredPin.length != 6) {
      setState(() => _errorMessage = 'PIN კოდი უნდა იყოს 6 ციფრი');
      return;
    }
    final pinExists = DatabaseService.getAllUsers().any(
      (u) => u.pinCode == _enteredPin && u.username != widget.user.username,
    );
    if (pinExists) {
      setState(() {
        _errorMessage = 'ეს PIN კოდი უკვე გამოიყენება';
        _enteredPin = '';
      });
      return;
    }
    Navigator.of(context).pop(_enteredPin);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: AdminDesign.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 420),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_reset,
                color: AdminDesign.accentDark,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'PIN — ${widget.user.username}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AdminDesign.text,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _enteredPin.padRight(6, '•'),
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_errorMessage, style: const TextStyle(color: AdminDesign.danger)),
              ],
              const SizedBox(height: 16),
              _PinPad(
                onDigit: _onNumberPressed,
                onBackspace: _onBackspacePressed,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('გაუქმება'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _onConfirm,
                      style: AdminDesign.primaryButtonStyle(),
                      child: const Text('შენახვა'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
