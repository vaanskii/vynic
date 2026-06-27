import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/services/api_config.dart';
import 'package:vynic/core/services/app_mode.dart';
import 'package:vynic/core/services/connection_status_service.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/manager_sync_service.dart';
import 'package:vynic/core/services/pos_callback_config.dart';

class AdminConnectionSection extends StatefulWidget {
  const AdminConnectionSection({super.key});

  @override
  State<AdminConnectionSection> createState() => _AdminConnectionSectionState();
}

class _AdminConnectionSectionState extends State<AdminConnectionSection> {
  late final TextEditingController _backendUrlController;
  bool _isRetrying = false;
  bool _isTesting = false;
  bool _isEditingBackendUrl = false;
  bool _isSavingBackendUrl = false;
  String? _backendUrlFeedback;
  bool _backendUrlFeedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _backendUrlController = TextEditingController(text: ApiConfig.baseUrl);
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: AnimatedBuilder(
            animation: Listenable.merge([
              ConnectionStatusService.backendState,
              ConnectionStatusService.lastAttemptAt,
              ConnectionStatusService.lastSyncedAt,
              ConnectionStatusService.lastError,
              ConnectionStatusService.hasPendingLocalChanges,
            ]),
            builder: (context, _) {
              final state = ConnectionStatusService.backendState.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminSectionHeader(
                    icon: Icons.lan_outlined,
                    title: 'კავშირი',
                    subtitle:
                        'Windows POS კავშირი backend-თან, sync სტატუსი და callback მისამართები.',
                    badge: _StatusBadge(state: state),
                  ),
                  const SizedBox(height: 16),
                  _buildActionPanel(),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 820;
                      final statusPanel = _buildStatusPanel(state);
                      final endpointPanel = _buildEndpointPanel();
                      if (!twoColumns) {
                        return Column(
                          children: [
                            statusPanel,
                            const SizedBox(height: 14),
                            endpointPanel,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: statusPanel),
                          const SizedBox(width: 14),
                          Expanded(child: endpointPanel),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildPrintHostPanel(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildActionPanel() {
    final busy = _isRetrying || _isTesting;
    return AdminPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ElevatedButton.icon(
            style: AdminDesign.primaryButtonStyle(),
            onPressed: busy ? null : _retrySyncNow,
            icon: _isRetrying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, size: 18),
            label: const Text('Retry Sync Now'),
          ),
          OutlinedButton.icon(
            style: AdminDesign.outlineButtonStyle(),
            onPressed: busy ? null : _testBackendConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Test Backend Connection'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(BackendConnectionState state) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.cloud_done_outlined, label: 'Sync'),
          const SizedBox(height: 14),
          _InfoRow(label: 'Status', value: _statusLabel(state)),
          _InfoRow(
            label: 'Pending local changes',
            value: ConnectionStatusService.hasPendingLocalChanges.value
                ? 'Yes'
                : 'No',
          ),
          _InfoRow(
            label: 'Last attempt',
            value: _formatDateTime(ConnectionStatusService.lastAttemptAt.value),
          ),
          _InfoRow(
            label: 'Last successful sync',
            value: _formatDateTime(ConnectionStatusService.lastSyncedAt.value),
          ),
          _InfoRow(
            label: 'Last error',
            value: ConnectionStatusService.lastError.value ?? 'None',
            valueColor: ConnectionStatusService.lastError.value == null
                ? AdminDesign.text
                : AdminDesign.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointPanel() {
    final callbackUrl = PosCallbackConfig.baseUrl;
    final connectionKey = PosCallbackConfig.connectionKey;
    final backendOverride = DatabaseService.getBackendUrlOverride();
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.settings_ethernet, label: 'Endpoints'),
          const SizedBox(height: 14),
          _InfoRow(label: 'Backend URL', value: ApiConfig.baseUrl),
          _InfoRow(
            label: 'Backend source',
            value: backendOverride == null
                ? '.env / app config'
                : 'Admin override',
          ),
          const SizedBox(height: 8),
          _buildBackendUrlEditor(),
          const SizedBox(height: 10),
          _InfoRow(
            label: 'POS callback URL',
            value: callbackUrl == null || callbackUrl.isEmpty
                ? 'Not running'
                : callbackUrl,
            valueColor: callbackUrl == null || callbackUrl.isEmpty
                ? AdminDesign.warning
                : AdminDesign.text,
          ),
          _InfoRow(
            label: 'Callback key',
            value: connectionKey == null || connectionKey.isEmpty
                ? 'Missing'
                : 'Registered',
            valueColor: connectionKey == null || connectionKey.isEmpty
                ? AdminDesign.warning
                : AdminDesign.text,
          ),
        ],
      ),
    );
  }

  Widget _buildBackendUrlEditor() {
    final busy = _isRetrying || _isTesting || _isSavingBackendUrl;
    final hasOverride = DatabaseService.getBackendUrlOverride() != null;
    if (!_isEditingBackendUrl) {
      return Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            style: AdminDesign.outlineButtonStyle(),
            onPressed: busy
                ? null
                : () {
                    setState(() {
                      _backendUrlController.text = ApiConfig.baseUrl;
                      _backendUrlFeedback = null;
                      _backendUrlFeedbackIsError = false;
                      _isEditingBackendUrl = true;
                    });
                  },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Edit Backend URL'),
          ),
          if (hasOverride)
            OutlinedButton.icon(
              style: AdminDesign.outlineButtonStyle(
                foreground: AdminDesign.warning,
              ),
              onPressed: busy ? null : _resetBackendUrlOverride,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('Reset to .env'),
            ),
          if (_backendUrlFeedback != null)
            _InlineFeedback(
              message: _backendUrlFeedback!,
              isError: _backendUrlFeedbackIsError,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _backendUrlController,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: 'Backend URL or IP',
            hintText: 'http://10.10.10.3:3000',
            helperText: 'Example: 10.10.10.3 becomes http://10.10.10.3:3000',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AdminDesign.radius),
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              style: AdminDesign.primaryButtonStyle(),
              onPressed: busy ? null : _saveBackendUrlOverride,
              icon: _isSavingBackendUrl
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Test and Save'),
            ),
            OutlinedButton.icon(
              style: AdminDesign.outlineButtonStyle(),
              onPressed: busy
                  ? null
                  : () {
                      setState(() {
                        _backendUrlController.text = ApiConfig.baseUrl;
                        _backendUrlFeedback = null;
                        _backendUrlFeedbackIsError = false;
                        _isEditingBackendUrl = false;
                      });
                    },
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel'),
            ),
            if (_backendUrlFeedback != null)
              _InlineFeedback(
                message: _backendUrlFeedback!,
                isError: _backendUrlFeedbackIsError,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrintHostPanel() {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.print_outlined, label: 'Print Host'),
          const SizedBox(height: 14),
          _InfoRow(
            label: 'Windows POS print host',
            value: AppMode.isPrintHost ? 'Active' : 'Disabled',
            valueColor: AppMode.isPrintHost
                ? AdminDesign.text
                : AdminDesign.warning,
          ),
          _InfoRow(
            label: 'Kitchen printer',
            value:
                '${DatabaseService.getKitchenPrinterIp()}:'
                '${DatabaseService.getPrinterPort()}',
          ),
          _InfoRow(
            label: 'Receipt printer',
            value:
                '${DatabaseService.getReceiptPrinterIp()}:'
                '${DatabaseService.getPrinterPort()}',
          ),
        ],
      ),
    );
  }

  Future<void> _retrySyncNow() async {
    setState(() {
      _isRetrying = true;
    });
    try {
      await ManagerSyncService.syncToManagerApp();
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  Future<void> _testBackendConnection() async {
    setState(() {
      _isTesting = true;
    });
    try {
      await ManagerSyncService.testBackendConnection();
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveBackendUrlOverride() async {
    final normalized = ApiConfig.normalizeEditableBackendUrl(
      _backendUrlController.text,
    );
    if (normalized == null) {
      setState(() {
        _backendUrlFeedback = 'Invalid URL. Use IP or http://IP:3000.';
        _backendUrlFeedbackIsError = true;
      });
      return;
    }

    setState(() {
      _isSavingBackendUrl = true;
      _backendUrlFeedback = 'Testing $normalized...';
      _backendUrlFeedbackIsError = false;
    });

    try {
      final reachable = await ManagerSyncService.testBackendConnection(
        backendUrl: normalized,
        updateStatus: false,
      );
      if (!mounted) return;
      if (!reachable) {
        setState(() {
          _backendUrlFeedback =
              'Backend did not respond. Old URL was kept unchanged.';
          _backendUrlFeedbackIsError = true;
          _isSavingBackendUrl = false;
        });
        return;
      }

      await DatabaseService.saveBackendUrlOverride(normalized);
      ApiConfig.resetResolvedUrlLog();
      await ManagerSyncService.testBackendConnection();
      if (!mounted) return;
      setState(() {
        _backendUrlController.text = normalized;
        _backendUrlFeedback = 'Saved. POS will use $normalized.';
        _backendUrlFeedbackIsError = false;
        _isEditingBackendUrl = false;
        _isSavingBackendUrl = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backendUrlFeedback = 'Save failed: $e';
        _backendUrlFeedbackIsError = true;
        _isSavingBackendUrl = false;
      });
    }
  }

  Future<void> _resetBackendUrlOverride() async {
    setState(() {
      _isSavingBackendUrl = true;
      _backendUrlFeedback = 'Resetting to .env / app config...';
      _backendUrlFeedbackIsError = false;
    });

    try {
      await DatabaseService.clearBackendUrlOverride();
      ApiConfig.resetResolvedUrlLog();
      final fallbackUrl = ApiConfig.baseUrl;
      _backendUrlController.text = fallbackUrl;
      await ManagerSyncService.testBackendConnection();
      if (!mounted) return;
      setState(() {
        _backendUrlFeedback = 'Reset. POS will use $fallbackUrl.';
        _backendUrlFeedbackIsError = false;
        _isEditingBackendUrl = false;
        _isSavingBackendUrl = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backendUrlFeedback = 'Reset failed: $e';
        _backendUrlFeedbackIsError = true;
        _isSavingBackendUrl = false;
      });
    }
  }

  String _statusLabel(BackendConnectionState state) {
    switch (state) {
      case BackendConnectionState.idle:
        return 'Waiting';
      case BackendConnectionState.syncing:
        return 'Syncing';
      case BackendConnectionState.connected:
        return 'Connected';
      case BackendConnectionState.offline:
        return 'Offline';
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Never';
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final BackendConnectionState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      BackendConnectionState.connected => AdminDesign.accentDark,
      BackendConnectionState.syncing => const Color(0xFF2563EB),
      BackendConnectionState.offline => AdminDesign.danger,
      BackendConnectionState.idle => AdminDesign.warning,
    };
    final background = switch (state) {
      BackendConnectionState.connected => const Color(0xFFECFDF5),
      BackendConnectionState.syncing => const Color(0xFFEFF6FF),
      BackendConnectionState.offline => const Color(0xFFFEF2F2),
      BackendConnectionState.idle => const Color(0xFFFFFBEB),
    };
    final border = switch (state) {
      BackendConnectionState.connected => const Color(0xFFA7F3D0),
      BackendConnectionState.syncing => const Color(0xFFBFDBFE),
      BackendConnectionState.offline => const Color(0xFFFECACA),
      BackendConnectionState.idle => const Color(0xFFFDE68A),
    };
    final label = switch (state) {
      BackendConnectionState.connected => 'Connected',
      BackendConnectionState.syncing => 'Syncing',
      BackendConnectionState.offline => 'Offline',
      BackendConnectionState.idle => 'Waiting',
    };
    final icon = switch (state) {
      BackendConnectionState.connected => Icons.check_circle,
      BackendConnectionState.syncing => Icons.sync,
      BackendConnectionState.offline => Icons.error,
      BackendConnectionState.idle => Icons.schedule,
    };
    return AdminStatusBadge(
      icon: icon,
      label: label,
      color: color,
      background: background,
      border: border,
    );
  }
}

class _InlineFeedback extends StatelessWidget {
  const _InlineFeedback({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AdminDesign.danger : AdminDesign.accentDark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AdminDesign.accentDark, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AdminDesign.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor = AdminDesign.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final labelWidget = Text(
            label,
            style: const TextStyle(
              color: AdminDesign.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          );
          final valueWidget = SelectableText(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 170, child: labelWidget),
              const SizedBox(width: 12),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
