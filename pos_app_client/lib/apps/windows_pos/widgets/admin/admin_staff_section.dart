import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

const Color _staffPrimary = Color(0xFF1E3A8A);
const Color _staffAccent = Color(0xFF2563EB);
const Color _staffSurface = Color(0xFFF4F6FF);
const Color _staffCard = Colors.white;
const Color _staffBorder = Color(0xFFE2E8F0);
const Color _staffText = Color(0xFF1F2937);
const Color _staffMuted = Color(0xFF64748B);

const TextStyle _staffFieldLabel = TextStyle(
  color: _staffMuted,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

InputDecoration _staffInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _staffMuted.withValues(alpha: 0.7)),
      filled: true,
      fillColor: _staffSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _staffBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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

  bool get _waitersOnlyAdmin => widget.user.isSupervisor;

  void _refreshList() => setState(() => _listVersion++);

  List<User> get _allUsers => DatabaseService.getAllUsers();

  List<User> get _directoryUsers {
    if (_waitersOnlyAdmin) {
      return _allUsers.where((u) => u.isWaiter).toList();
    }
    return _filteredUsers;
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
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(isMobile),
                if (_waitersOnlyAdmin) ...[
                  const SizedBox(height: 16),
                  _buildSupervisorAccessNotice(isMobile),
                ],
                const SizedBox(height: 20),
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
                const SizedBox(height: 24),
                _buildDirectory(isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupervisorAccessNotice(bool isMobile) {
    const noticeBorder = Color(0xFFFCD34D);
    const noticeBg = Color(0xFFFFFBEB);
    const noticeTitle = Color(0xFF92400E);
    const noticeBody = Color(0xFFB45309);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: noticeBg,
        borderRadius: BorderRadius.circular(14),
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
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'პერსონალი',
          style: TextStyle(
            color: _staffText,
            fontSize: isMobile ? 24 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _waitersOnlyAdmin
              ? 'ოფიციანტების დამატება და PIN-ების მართვა'
              : 'თანამშრომლების რეესტრი და მართვა',
          style: TextStyle(color: _staffMuted, fontSize: isMobile ? 14 : 15),
        ),
      ],
    );

    final addButton = SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _openAddStaffDialog,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(
          _waitersOnlyAdmin ? 'ახალი ოფიციანტი' : 'ახალი თანამშრომელი',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _staffAccent,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 16),
          addButton,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        addButton,
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
              label: 'ოფიციანტი',
              value: waiters,
              color: const Color(0xFF0EA5E9),
            ),
          ]
        : [
            _KpiChip(label: 'სულ', value: total, color: _staffPrimary),
            _KpiChip(label: 'მენეჯერი', value: managers, color: _staffAccent),
            _KpiChip(
              label: 'ზედამხედველი',
              value: supervisors,
              color: const Color(0xFF7C3AED),
            ),
            _KpiChip(
              label: 'ოფიციანტი',
              value: waiters,
              color: const Color(0xFF0EA5E9),
            ),
          ];
    if (isMobile) {
      return Wrap(spacing: 10, runSpacing: 10, children: items);
    }
    return Row(
      children: items
          .map((c) => Expanded(child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: c,
              )))
          .toList(),
    );
  }

  Widget _buildDirectory(bool isMobile) {
    // ignore: unused_local_variable — bumps rebuild
    final _ = _listVersion;
    final users = _directoryUsers;

    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: _staffPrimary, size: 22),
              const SizedBox(width: 10),
              Text(
                'რეესტრი',
                style: TextStyle(
                  color: _staffText,
                  fontSize: isMobile ? 17 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${users.length} ჩანაწერი',
                style: TextStyle(color: _staffMuted, fontSize: 13),
              ),
            ],
          ),
          if (!_waitersOnlyAdmin) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip('ყველა', _StaffListFilter.all),
                _filterChip('მენეჯერი', _StaffListFilter.manager),
                _filterChip('ზედამხედველი', _StaffListFilter.supervisor),
                _filterChip('ოფიციანტი', _StaffListFilter.waiter),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'ამ ფილტრში ჩანაწერი არ არის',
                  style: TextStyle(color: _staffMuted, fontSize: 14),
                ),
              ),
            )
          else
            ...users.map(
              (u) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StaffUserTile(
                  user: u,
                  showPin: widget.user.canViewStaffPinOf(u),
                  canManage: widget.user.canManageStaffUser(u),
                  onEditName: () => _showEditNameDialog(u),
                  onChangePin: () => _showChangePinDialog(u),
                  onDelete: () => _confirmDeleteUser(u),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _StaffListFilter filter) {
    final selected = _listFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _listFilter = filter),
      selectedColor: _staffAccent.withValues(alpha: 0.15),
      checkmarkColor: _staffAccent,
      labelStyle: TextStyle(
        color: selected ? _staffAccent : _staffMuted,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? _staffAccent : _staffBorder),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
              borderRadius: BorderRadius.circular(16),
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
                            () => tempPin =
                                tempPin.substring(0, tempPin.length - 1),
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
                      widget.waiterOnly ? 'ახალი ოფიციანტი' : 'ახალი თანამშრომელი',
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
                        Row(
                          children: [
                            Expanded(
                              child: _roleChip(
                                StaffRole.waiter,
                                StaffRole.labelKa(StaffRole.waiter),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _roleChip(
                                StaffRole.supervisor,
                                StaffRole.labelKa(StaffRole.supervisor),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _roleChip(
                                StaffRole.manager,
                                StaffRole.labelKa(StaffRole.manager),
                              ),
                            ),
                          ],
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _staffCard,
        borderRadius: BorderRadius.circular(18),
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
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _staffCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _staffBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _staffMuted, fontSize: 12)),
              Text(
                '$value',
                style: TextStyle(
                  color: _staffText,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
        borderRadius: BorderRadius.circular(18),
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

class _StaffUserTile extends StatelessWidget {
  const _StaffUserTile({
    required this.user,
    required this.showPin,
    required this.canManage,
    required this.onEditName,
    required this.onChangePin,
    required this.onDelete,
  });

  final User user;
  final bool showPin;
  final bool canManage;
  final VoidCallback onEditName;
  final VoidCallback onChangePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isManager = user.isManager;
    final isSupervisor = user.isSupervisor;
    final accent = isManager
        ? _staffAccent
        : isSupervisor
            ? const Color(0xFF7C3AED)
            : _staffPrimary;
    final allUsers = DatabaseService.getAllUsers();
    final canDelete = !isManager || allUsers.where((u) => u.isManager).length > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _staffSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(
              isManager
                  ? Icons.shield_rounded
                  : isSupervisor
                      ? Icons.supervisor_account_rounded
                      : Icons.person_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: const TextStyle(
                    color: _staffText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.roleLabelKa,
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (showPin) ...[
                  const SizedBox(height: 6),
                  Text(
                    'PIN: ${user.pinCode}',
                    style: const TextStyle(color: _staffMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            TextButton.icon(
              onPressed: onEditName,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('სახელი'),
              style: TextButton.styleFrom(foregroundColor: _staffAccent),
            ),
            TextButton.icon(
              onPressed: onChangePin,
              icon: const Icon(Icons.pin_rounded, size: 18),
              label: const Text('PIN'),
              style: TextButton.styleFrom(foregroundColor: _staffAccent),
            ),
            if (canDelete)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: Colors.red.shade400,
                tooltip: 'წაშლა',
              ),
          ],
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
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 420),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_reset, color: Color(0xFF2563EB), size: 40),
              const SizedBox(height: 12),
              Text(
                'PIN — ${widget.user.username}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
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
                Text(_errorMessage, style: const TextStyle(color: Colors.red)),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
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
