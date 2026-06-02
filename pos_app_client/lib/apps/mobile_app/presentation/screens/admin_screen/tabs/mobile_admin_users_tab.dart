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

    final admins =
        _users.where((u) => (u['role'] as String?) == 'ADMIN').toList();
    final waiters =
        _users.where((u) => (u['role'] as String?) != 'ADMIN').toList();
    final activeCount =
        _users.where((u) => (u['isActive'] as bool? ?? true)).length;

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
          _AdminKpiGrid(
            items: [
              _AdminKpiItem(
                label: 'სულ',
                value: '${_users.length}',
                icon: Icons.people_rounded,
                color: AdminTheme.primary,
              ),
              _AdminKpiItem(
                label: 'აქტიური',
                value: '$activeCount',
                icon: Icons.verified_user_rounded,
                color: AdminTheme.good,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AdminPrimaryButton(
            label: 'მომხმარებლის დამატება',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: _showCreateUserDialog,
          ),
          if (admins.isNotEmpty) ...[
            const SizedBox(height: 20),
            _AdminSection(
              title: 'ადმინისტრატორები',
              trailing: '${admins.length}',
              child: Column(
                children: admins.map(
              (u) => _UserCard(
                user: u,
                onChangePin: () => _showChangePinDialog(u),
                onDelete: () => _confirmDeleteUser(u),
              ),
            ).toList(),
              ),
            ),
          ],
          if (waiters.isNotEmpty) ...[
            const SizedBox(height: 20),
            _AdminSection(
              title: 'ოფიციანტები',
              trailing: '${waiters.length}',
              child: Column(
                children: waiters.map(
              (u) => _UserCard(
                user: u,
                onChangePin: () => _showChangePinDialog(u),
                onDelete: () => _confirmDeleteUser(u),
              ),
            ).toList(),
              ),
            ),
          ],
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
    String role = 'WAITER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AdminTheme.surface,
          title: const Text(
            'ახალი მომხმარებელი',
            style: TextStyle(color: AdminTheme.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                style: const TextStyle(color: AdminTheme.text),
                decoration: _adminInput('სახელი'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                style: const TextStyle(color: AdminTheme.text),
                decoration: _adminInput('PIN'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: role,
                dropdownColor: const Color(0xFF1E1E28),
                style: const TextStyle(color: AdminTheme.text),
                decoration: _adminInput('როლი'),
                items: const [
                  DropdownMenuItem(value: 'ADMIN', child: Text('ადმინისტრატორი')),
                  DropdownMenuItem(value: 'WAITER', child: Text('ოფიციანტი')),
                ],
                onChanged: (v) => setLocal(() => role = v ?? 'WAITER'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('გაუქმება', style: TextStyle(color: AdminTheme.textMuted)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
              child: const Text('დამატება'),
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

  Future<void> _showChangePinDialog(dynamic user) async {
    final ctrl = TextEditingController(text: (user['pinCode'] ?? '').toString());
    final ok = await _adminFormDialog(
      context,
      title: 'PIN შეცვლა • ${user['username']}',
      fields: [
        TextField(
          controller: ctrl,
          style: const TextStyle(color: AdminTheme.text),
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
  final VoidCallback onChangePin;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onChangePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final role = user['role'] as String? ?? 'WAITER';
    final isActive = user['isActive'] as bool? ?? true;
    final isAdmin = role == 'ADMIN';
    final accent = isAdmin ? const Color(0xFF8B5CF6) : AdminTheme.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AdminPanel(
        padding: const EdgeInsets.all(14),
        accentBorder: accent.withValues(alpha: 0.35),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.person_rounded,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['username'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AdminTheme.text,
                    ),
                  ),
                  Text(
                    _roleName(role),
                    style: TextStyle(fontSize: 12, color: accent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PIN: ${(user['pinCode'] ?? '').toString()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'PIN',
              onPressed: onChangePin,
              icon: Icon(Icons.pin_rounded, size: 18, color: AdminTheme.textMuted),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: AdminTheme.bad),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isActive ? AdminTheme.good : AdminTheme.bad)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? 'აქტიური' : 'გათიშული',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? AdminTheme.good : AdminTheme.bad,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleName(String role) {
    switch (role) {
      case 'ADMIN':
        return 'ადმინისტრატორი';
      default:
        return 'ოფიციანტი';
    }
  }
}
