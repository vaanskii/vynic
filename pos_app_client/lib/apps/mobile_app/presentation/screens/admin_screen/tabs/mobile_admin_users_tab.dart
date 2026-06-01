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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorWidget(onRetry: _load);

    final admins = _users.where((u) => (u['role'] as String?) == 'ADMIN').toList();
    final waiters = _users
        .where((u) => (u['role'] as String?) != 'ADMIN')
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _showCreateUserDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('მომხმარებლის დამატება'),
            ),
          ),
          const SizedBox(height: 12),
          if (admins.isNotEmpty) ...[
            _sectionHeader('👑 ადმინისტრატორები', admins.length),
            const SizedBox(height: 8),
            ...admins.map(
              (u) => _UserCard(
                user: u,
                onChangePin: () => _showChangePinDialog(u),
                onDelete: () => _confirmDeleteUser(u),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (waiters.isNotEmpty) ...[
            _sectionHeader('👤 ოფიციანტები', waiters.length),
            const SizedBox(height: 8),
            ...waiters.map(
              (u) => _UserCard(
                user: u,
                onChangePin: () => _showChangePinDialog(u),
                onDelete: () => _confirmDeleteUser(u),
              ),
            ),
          ],
          if (_users.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'მომხმარებლები ვერ მოიძებნა',
                  style: TextStyle(color: Color(0xFF64748B)),
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
          title: const Text('ახალი მომხმარებელი'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'სახელი'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
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
              child: const Text('გაუქმება'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('მომხმარებელი დაემატა')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('შეცდომა: $e')),
      );
    }
  }

  Future<void> _showChangePinDialog(dynamic user) async {
    final ctrl = TextEditingController(text: (user['pinCode'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('PIN შეცვლა • ${user['username']}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'ახალი PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('შენახვა'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MobileApiService.updateUserPin(
        username: (user['username'] ?? '').toString(),
        pinCode: ctrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN განახლდა')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('შეცდომა: $e')),
      );
    }
  }

  Future<void> _confirmDeleteUser(dynamic user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('წავშალოთ ${user['username']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('არა'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('დიახ'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await MobileApiService.deleteUser((user['username'] ?? '').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('მომხმარებელი წაიშალა')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('შეცდომა: $e')),
      );
    }
  }

  Widget _sectionHeader(String title, int count) => Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        ],
      );
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
    final color = isAdmin
        ? const Color(0xFF7C3AED)
        : const Color(0xFF1E3A8A);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              isAdmin
                  ? Icons.admin_panel_settings_rounded
                  : Icons.person_rounded,
              color: color,
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
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  _roleName(role),
                  style: TextStyle(fontSize: 12, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'PIN: ${(user['pinCode'] ?? '').toString()}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'PIN',
            onPressed: onChangePin,
            icon: const Icon(Icons.pin_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF10B981).withValues(alpha: 0.1)
                  : const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isActive ? 'აქტიური' : 'გათიშული',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
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
