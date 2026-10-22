part of '../mobile_admin_screen.dart';

class _UsersTab extends StatefulWidget {
  final User currentUser;
  const _UsersTab({required this.currentUser});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await MobileApiService.getUsers();
      setState(() {
        _users = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const _AdminLoading();
    if (_error != null) return _ErrorWidget(onRetry: _load);

    bool isRole(Map<String, dynamic> u, String apiRole) {
      final raw = (u['role'] as String?) ?? '';
      return StaffRole.toApi(StaffRole.fromApi(raw)) == apiRole;
    }

    final managers = _users
        .where((u) => isRole(u, StaffRole.toApi(StaffRole.manager)))
        .toList();
    final supervisors = _users
        .where((u) => isRole(u, StaffRole.toApi(StaffRole.supervisor)))
        .toList();
    final waiters = _users
        .where((u) => isRole(u, StaffRole.toApi(StaffRole.waiter)))
        .toList();
    final activeCount = _users
        .where((u) => (u['isActive'] as bool? ?? true))
        .length;

    return RefreshIndicator(
      color: AdminTheme.primary,
      backgroundColor: AdminTheme.surface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: _adminScrollPadding(context),
        children: [
          ManagerPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ManagerSectionHeading(
                  'გუნდი',
                  subtitle:
                      '${_users.length} თანამშრომელი · $activeCount აქტიური',
                  action: 'თანამშრომლის დამატება',
                  onAction: _showCreateUserDialog,
                ),
                for (final u in [...managers, ...supervisors, ...waiters])
                  _UserCard(
                    user: u,
                    onEditName: () => _showEditNameDialog(u),
                    onChangePin: () => _showChangePinDialog(u),
                    onChangeRole: () => _showChangeRoleDialog(u),
                    onDelete: () => _confirmDeleteUser(u),
                  ),
              ],
            ),
          ),
          if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'მომხმარებლები ვერ მოიძებნა',
                  style: TextStyle(color: AdminTheme.textDim),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateUserDialog() async {
    final usernameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String role = StaffRole.toApi(StaffRole.waiter);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ManagerFormDialog(
          backgroundColor: AdminTheme.surface,
          title: Text(
            'ახალი მომხმარებელი',
            style: TextStyle(color: AdminTheme.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PosOnScreenTextField(
                controller: usernameCtrl,
                style: TextStyle(color: AdminTheme.text),
                decoration: _adminInput(
                  shouldUsePosOnScreenKeyboard()
                      ? 'დააჭირეთ სახელის შესაყვანად'
                      : 'სახელი',
                ),
              ),
              SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                style: TextStyle(color: AdminTheme.text),
                decoration: _adminInput('PIN'),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 8),
              _adminRoleDropdown(
                value: role,
                onChanged: (v) => setLocal(
                  () => role = v ?? StaffRole.toApi(StaffRole.waiter),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'გაუქმება',
                style: TextStyle(color: AdminTheme.textMuted),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AdminTheme.primary,
              ),
              child: Text(
                'დამატება',
                style: TextStyle(color: AdminTheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await MobileApiService.createUser(
        username: usernameCtrl.text.trim(),
        pinCode: pinCtrl.text.trim(),
        role: role,
      );
      if (!mounted) return;
      _adminToast(context, 'მომხმარებელი დაემატა');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _adminToast(context, 'შეცდომა: $e', error: true);
    }
  }

  Future<void> _showEditNameDialog(dynamic user) async {
    final oldUsername = (user['username'] ?? '').toString();
    final ctrl = TextEditingController(text: oldUsername);
    final ok = await _adminFormDialog(
      context,
      title: 'სახელის შეცვლა',
      fields: [
        PosOnScreenTextField(
          controller: ctrl,
          style: TextStyle(color: AdminTheme.text),
          decoration: _adminInput(
            shouldUsePosOnScreenKeyboard()
                ? 'დააჭირეთ სახელის შესაყვანად'
                : 'სახელი',
          ),
        ),
      ],
    );
    if (ok != true) return;
    final newUsername = ctrl.text.trim();
    if (newUsername.isEmpty || newUsername == oldUsername) return;
    try {
      await MobileApiService.renameUser(
        oldUsername: oldUsername,
        newUsername: newUsername,
      );
      if (!mounted) return;
      _adminToast(context, 'სახელი განახლდა');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _adminToast(context, 'შეცდომა: $e', error: true);
    }
  }

  Future<void> _showChangePinDialog(dynamic user) async {
    final ctrl = TextEditingController(
      text: (user['pinCode'] ?? '').toString(),
    );
    final ok = await _adminFormDialog(
      context,
      title: 'PIN შეცვლა • ${user['username']}',
      fields: [
        TextField(
          controller: ctrl,
          style: TextStyle(color: AdminTheme.text),
          decoration: _adminInput('ახალი PIN'),
          keyboardType: TextInputType.number,
        ),
      ],
    );
    if (ok != true) return;
    try {
      await MobileApiService.updateUserPin(
        username: (user['username'] ?? '').toString(),
        pinCode: ctrl.text.trim(),
      );
      if (!mounted) return;
      _adminToast(context, 'PIN განახლდა');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _adminToast(context, 'შეცდომა: $e', error: true);
    }
  }

  Future<void> _showChangeRoleDialog(dynamic user) async {
    final username = (user['username'] ?? '').toString();
    final currentRole = StaffRole.fromApi((user['role'] ?? '').toString());
    final managerCount = _users.where((entry) {
      return StaffRole.fromApi((entry['role'] ?? '').toString()) ==
          StaffRole.manager;
    }).length;
    final preventManagerDemotion =
        currentRole == StaffRole.manager && managerCount <= 1;
    String role = StaffRole.toApi(currentRole);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ManagerFormDialog(
          backgroundColor: AdminTheme.surface,
          title: Text(
            'როლის შეცვლა • $username',
            style: TextStyle(color: AdminTheme.text),
          ),
          content: _adminRoleDropdown(
            value: role,
            onChanged: (value) {
              final selectedRole = value ?? StaffRole.toApi(StaffRole.waiter);
              if (preventManagerDemotion &&
                  StaffRole.fromApi(selectedRole) != StaffRole.manager) {
                _adminToast(
                  ctx,
                  'როლის შესაცვლელად საჭიროა მეორე მენეჯერის ანგარიში',
                  error: true,
                );
                return;
              }
              setLocal(() {
                role = selectedRole;
              });
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'გაუქმება',
                style: TextStyle(color: AdminTheme.textMuted),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AdminTheme.primary,
              ),
              child: Text(
                'შენახვა',
                style: TextStyle(color: AdminTheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await MobileApiService.updateUserRole(username: username, role: role);
      if (!mounted) return;
      _adminToast(context, 'როლი განახლდა');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _adminToast(context, 'შეცდომა: $e', error: true);
    }
  }

  Future<void> _confirmDeleteUser(dynamic user) async {
    final confirm = await _adminConfirmDialog(
      context,
      title: 'წავშალოთ ${user['username']}?',
    );
    if (confirm != true) return;
    try {
      await MobileApiService.deleteUser((user['username'] ?? '').toString());
      if (!mounted) return;
      _adminToast(context, 'მომხმარებელი წაიშალა');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _adminToast(context, 'შეცდომა: $e', error: true);
    }
  }
}

class _UserCard extends StatelessWidget {
  final dynamic user;
  final VoidCallback onEditName;
  final VoidCallback onChangePin;
  final VoidCallback onChangeRole;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onEditName,
    required this.onChangePin,
    required this.onChangeRole,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final role = user['role'] as String? ?? 'WAITER';
    final accent = AdminTheme.primary;
    final name = user['username'] as String? ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.12),
        child: Text(
          name
              .split(' ')
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.characters.first)
              .join(),
          style: managerDesignText(context, 12).copyWith(color: accent),
        ),
      ),
      title: Text(
        name,
        style: managerDesignText(context, 14, weight: FontWeight.w500),
      ),
      subtitle: Text(
        _roleName(role),
        style: managerDesignText(context, 11, muted: true),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => ManagerFormDialog(
          title: Text(name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManagerKeyValue('როლი', _roleName(role)),
              ManagerKeyValue(
                'წვდომა',
                user['platformManaged'] == true
                    ? 'წვდომას მართავს პლატფორმა'
                    : 'PIN: ${user['pinCode'] ?? ''}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('დახურვა'),
            ),
          ],
        ),
      ),
      trailing: user['platformManaged'] == true
          ? const Icon(Icons.chevron_right, size: 20)
          : PopupMenuButton<String>(
              tooltip: 'მოქმედებები',
              icon: Icon(Icons.more_vert, color: AdminTheme.textMuted),
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
                  child: Text('სახელის შეცვლა'),
                ),
                const PopupMenuItem(value: 'pin', child: Text('PIN-ის შეცვლა')),
                const PopupMenuItem(value: 'role', child: Text('როლის შეცვლა')),
                const PopupMenuItem(value: 'delete', child: Text('წაშლა')),
              ],
            ),
    );
  }

  String _roleName(String role) => StaffRole.labelKaFromApi(role);
}
