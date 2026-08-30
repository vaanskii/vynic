import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/user_repository.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

/// The developer-only tools: diagnostics, restore, wipe, and PIN recovery.
///
/// Everything here is either destructive or only meaningful to whoever
/// maintains the installation. It is unreachable without a signed token, and
/// each individual tool checks its own scope — a token issued for a routine
/// log-reading call cannot reach the wipe button just because it opened the
/// panel.
class AdminDeveloperSection extends StatefulWidget {
  const AdminDeveloperSection({
    super.key,
    required this.onCreateBackupFile,
    required this.onRestoreBackupFromFile,
    required this.isCreatingBackup,
    required this.isRestoringBackup,
    required this.lastBackupPath,
    required this.lastRestorePath,
  });

  final Future<void> Function() onCreateBackupFile;
  final Future<void> Function() onRestoreBackupFromFile;
  final bool isCreatingBackup;
  final bool isRestoringBackup;
  final String? lastBackupPath;
  final String? lastRestorePath;

  @override
  State<AdminDeveloperSection> createState() => _AdminDeveloperSectionState();
}

class _AdminDeveloperSectionState extends State<AdminDeveloperSection> {
  bool _isWiping = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: adminSectionPadding(
        isMobile: MediaQuery.of(context).size.width < 700,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: adminSectionMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSessionHeader(),
              const SizedBox(height: 16),
              _buildDiagnosticsPanel(),
              const SizedBox(height: 16),
              _buildBackupPanel(),
              const SizedBox(height: 16),
              _buildRecoveryPanel(),
              const SizedBox(height: 16),
              _buildDangerPanel(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // --- session ---------------------------------------------------------

  Widget _buildSessionHeader() {
    // An absolute time rather than a countdown: it needs no ticking timer to
    // stay honest, and „until 19:42" is what you actually want to know.
    final expiry = DeveloperAccess.expiresAt?.toLocal();
    final expiryLabel = expiry == null
        ? 'locked'
        : 'until ${DateFormat('HH:mm').format(expiry)}';

    return AdminSectionHeader(
      icon: Icons.engineering_outlined,
      title: 'Developer tools',
      subtitle:
          'Signed session on terminal ${DeveloperAccess.terminalIdShort}. '
          'Every action here is written to the audit log.',
      badge: AdminStatusBadge(
        icon: Icons.timer_outlined,
        label: expiryLabel,
        color: AdminDesign.accentDark,
        background: AdminDesign.accentSoft,
        border: AdminDesign.accentSoftBorder,
      ),
      action: OutlinedButton.icon(
        onPressed: () {
          DeveloperAccess.lock();
        },
        style: AdminDesign.outlineButtonStyle(),
        icon: const Icon(Icons.lock_outline, size: 18),
        label: const Text('Lock now'),
      ),
    );
  }

  // --- diagnostics -----------------------------------------------------

  Widget _buildDiagnosticsPanel() {
    if (!DeveloperAccess.can(DeveloperScope.diagnostics)) {
      return _scopeDeniedPanel('Diagnostics', DeveloperScope.diagnostics);
    }

    final rows = <String, String>{
      'Terminal ID': DeveloperAccess.terminalId,
      'DB schema version': '${DatabaseCore.dbVersion}',
      'Data directory': DatabaseCore.dataDirectoryPath,
      'Granted scopes': DeveloperAccess.grantedScopes.join(', '),
    };

    final counts = <String, int>{
      'users': DatabaseCore.userBox?.length ?? 0,
      'tables': DatabaseCore.tableBox?.length ?? 0,
      'orders': DatabaseCore.orderBox?.length ?? 0,
      'menu': DatabaseCore.menuBox?.length ?? 0,
      'packages': DatabaseCore.packageBox?.length ?? 0,
      'reservations': DatabaseCore.reservationBox?.length ?? 0,
      'sales': DatabaseCore.salesBox?.length ?? 0,
      'expenses': DatabaseCore.expenseBox?.length ?? 0,
      'auditLog': DatabaseCore.auditLogBox?.length ?? 0,
      'errorLog': DatabaseCore.errorLogBox?.length ?? 0,
    };

    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelTitle(Icons.monitor_heart_outlined, 'Diagnostics'),
          const SizedBox(height: 14),
          ...rows.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InfoLine(label: entry.key, value: entry.value),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(color: AdminDesign.border, height: 20),
          const Text(
            'Box row counts',
            style: TextStyle(
              color: AdminDesign.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: counts.entries
                .map(
                  (entry) => AdminTag(
                    label: '${entry.key}: ${entry.value}',
                    tone: AdminTones.neutral,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: AdminDesign.outlineButtonStyle(),
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('Copy diagnostics'),
            onPressed: () {
              final report = StringBuffer()
                ..writeln('Vynic POS diagnostics')
                ..writeln(
                  DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                );
              rows.forEach((k, v) => report.writeln('$k: $v'));
              counts.forEach((k, v) => report.writeln('box.$k: $v'));
              Clipboard.setData(ClipboardData(text: report.toString()));
              unawaited(showSuccessToast(context, 'Diagnostics copied.'));
            },
          ),
        ],
      ),
    );
  }

  // --- backup ----------------------------------------------------------

  Widget _buildBackupPanel() {
    final canBackup = DeveloperAccess.can(DeveloperScope.backup);
    final canRestore = DeveloperAccess.can(DeveloperScope.restore);
    if (!canBackup && !canRestore) {
      return _scopeDeniedPanel('Backup and restore', DeveloperScope.restore);
    }

    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelTitle(Icons.settings_backup_restore, 'Backup and restore'),
          const SizedBox(height: 6),
          const Text(
            'Restore replaces users, menu, tables, sales, reservations and the '
            'audit log with the file\'s contents. A safety copy is taken first.',
            style: TextStyle(color: AdminDesign.muted, fontSize: 12.5),
          ),
          if (widget.lastBackupPath != null) ...[
            const SizedBox(height: 10),
            _InfoLine(label: 'Last backup', value: widget.lastBackupPath!),
          ],
          if (widget.lastRestorePath != null) ...[
            const SizedBox(height: 6),
            _InfoLine(label: 'Last restore', value: widget.lastRestorePath!),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                style: AdminDesign.outlineButtonStyle(),
                icon: const Icon(Icons.save_alt, size: 18),
                label: Text(
                  widget.isCreatingBackup ? 'Creating…' : 'Create backup file',
                ),
                onPressed: !canBackup || widget.isCreatingBackup
                    ? null
                    : () async {
                        await widget.onCreateBackupFile();
                        await DeveloperAccess.logAction('backup.create');
                      },
              ),
              ElevatedButton.icon(
                style: AdminDesign.primaryButtonStyle(),
                icon: const Icon(Icons.restore_page_outlined, size: 18),
                label: Text(
                  widget.isRestoringBackup ? 'Restoring…' : 'Restore from file',
                ),
                onPressed: !canRestore || widget.isRestoringBackup
                    ? null
                    : _confirmRestore,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRestore() async {
    final confirmed = await _confirmTypedPhrase(
      title: 'Restore over live data',
      body:
          'This overwrites every record on this terminal with the backup file. '
          'Anything entered since that backup was taken is lost.',
      phrase: 'RESTORE',
      danger: false,
    );
    if (!confirmed) return;

    await widget.onRestoreBackupFromFile();
    await DeveloperAccess.logAction('backup.restore');
  }

  // --- recovery --------------------------------------------------------

  Widget _buildRecoveryPanel() {
    if (!DeveloperAccess.can(DeveloperScope.recovery)) {
      return _scopeDeniedPanel('Access recovery', DeveloperScope.recovery);
    }

    final managers = UserRepository.getAllUsers()
        .where((user) => user.isAdmin)
        .toList();

    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelTitle(Icons.key_outlined, 'Access recovery'),
          const SizedBox(height: 6),
          const Text(
            'For the venue that has locked itself out of the admin PIN. Resets '
            'one manager account to a PIN you set here.',
            style: TextStyle(color: AdminDesign.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          if (managers.isEmpty)
            const AdminEmptyState(
              icon: Icons.person_off_outlined,
              title: 'No manager accounts',
              message:
                  'This terminal has no manager. Restore a backup or wipe and '
                  'let it re-seed the default account.',
            )
          else
            ...managers.map(
              (manager) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        manager.username,
                        style: const TextStyle(
                          color: AdminDesign.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      style: AdminDesign.outlineButtonStyle(),
                      onPressed: () => _resetPin(manager.username),
                      child: const Text('Reset PIN'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _resetPin(String username) async {
    final controller = TextEditingController();
    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminDesign.panel,
        title: Text('Reset PIN for $username'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New 6-digit PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: AdminDesign.primaryButtonStyle(),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newPin == null) return;
    if (!mounted) return;
    if (newPin.length != 6 || int.tryParse(newPin) == null) {
      unawaited(showErrorToast(context, 'PIN must be exactly 6 digits.'));
      return;
    }

    final ok = await UserRepository.updateUserPinByUsername(
      username: username,
      pinCode: newPin,
    );
    if (!mounted) return;

    if (ok) {
      await DeveloperAccess.logAction(
        'recovery.pinReset',
        data: {'username': username},
      );
      if (!mounted) return;
      unawaited(showSuccessToast(context, 'PIN reset for $username.'));
      setState(() {});
    } else {
      unawaited(
        showErrorToast(context, 'Could not reset — that PIN may be in use.'),
      );
    }
  }

  // --- danger ----------------------------------------------------------

  Widget _buildDangerPanel() {
    if (!DeveloperAccess.can(DeveloperScope.wipe)) {
      return _scopeDeniedPanel('Erase terminal', DeveloperScope.wipe);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AdminDesign.panelDecoration(
        borderColor: AdminDesign.danger.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.delete_forever_outlined,
                color: AdminDesign.danger,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Erase all data on this terminal',
                style: TextStyle(
                  color: AdminDesign.danger,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Clears every box — staff, menu, tables, orders, sales, expenses, '
            'reservations, audit and error logs — and re-seeds the terminal as '
            'a fresh install with the default manager account. A safety backup '
            'is written first.',
            style: TextStyle(color: AdminDesign.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminDesign.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AdminDesign.radius),
              ),
            ),
            icon: _isWiping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_forever, size: 18),
            label: Text(_isWiping ? 'Erasing…' : 'Erase everything'),
            onPressed: _isWiping ? null : _confirmWipe,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWipe() async {
    final confirmed = await _confirmTypedPhrase(
      title: 'Erase this terminal',
      body:
          'Every record on this machine is deleted and cannot be recovered '
          'except from the safety backup written just before the wipe.',
      phrase: 'ERASE',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isWiping = true);
    try {
      // Logged before the wipe, because the audit box is one of the things
      // about to be cleared — the record survives in the safety backup and in
      // whatever has already synced to the server.
      await DeveloperAccess.logAction('data.wipe.start');
      final safetyPath = await BackupRepository.wipeAllData();
      await DeveloperAccess.logAction(
        'data.wipe.done',
        data: {'safetyBackup': safetyPath},
      );
      if (!mounted) return;
      unawaited(
        showSuccessToast(
          context,
          'Terminal erased. Safety backup: ${safetyPath ?? 'none'}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Wipe failed: $e'));
    } finally {
      if (mounted) setState(() => _isWiping = false);
    }
  }

  // --- shared ----------------------------------------------------------

  /// A confirmation the user has to type, not one they can dismiss by reflex.
  Future<bool> _confirmTypedPhrase({
    required String title,
    required String body,
    required String phrase,
    required bool danger,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final matches = controller.text.trim() == phrase;
          return AlertDialog(
            backgroundColor: AdminDesign.panel,
            title: Text(
              title,
              style: TextStyle(
                color: danger ? AdminDesign.danger : AdminDesign.text,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  body,
                  style: const TextStyle(
                    color: AdminDesign.muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Type $phrase to continue.',
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setLocalState(() {}),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: danger
                      ? AdminDesign.danger
                      : AdminDesign.accentDark,
                  foregroundColor: Colors.white,
                ),
                onPressed: matches ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  Widget _panelTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AdminDesign.accentDark, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AdminDesign.text,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _scopeDeniedPanel(String title, String scope) {
    // Naming a scope string is no help to anyone standing at a terminal. For
    // the three destructive tools, say what to actually do about it.
    final message = DeveloperScope.destructive.contains(scope)
        ? '$title — this token does not grant it. Sign one that includes '
              '"$scope" and unlock again.'
        : '$title — not granted by this token (needs "$scope").';

    return AdminPanel(
      color: AdminDesign.panelSoft,
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AdminDesign.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: const TextStyle(color: AdminDesign.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(color: AdminDesign.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              color: AdminDesign.text,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
