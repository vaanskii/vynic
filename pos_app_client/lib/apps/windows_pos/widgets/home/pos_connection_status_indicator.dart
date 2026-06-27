import 'package:flutter/material.dart';
import 'package:vynic/core/services/connection_status_service.dart';

class PosConnectionStatusIndicator extends StatelessWidget {
  const PosConnectionStatusIndicator({
    super.key,
    this.compact = false,
    this.dark = true,
  });

  final bool compact;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ConnectionStatusService.backendState,
        ConnectionStatusService.hasPendingLocalChanges,
        ConnectionStatusService.lastSyncedAt,
        ConnectionStatusService.lastError,
      ]),
      builder: (context, _) {
        final visual = _visualFor(
          ConnectionStatusService.backendState.value,
          hasPendingChanges:
              ConnectionStatusService.hasPendingLocalChanges.value,
        );
        final lastSyncedAt = ConnectionStatusService.lastSyncedAt.value;
        final lastError = ConnectionStatusService.lastError.value;

        final tooltipLines = <String>[
          'Backend: ${visual.label}',
          'Last sync: ${_formatDateTime(lastSyncedAt)}',
          if (lastError != null && lastError.isNotEmpty) 'Error: $lastError',
        ];

        return Tooltip(
          message: tooltipLines.join('\n'),
          waitDuration: const Duration(milliseconds: 350),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 34,
            constraints: BoxConstraints(
              minWidth: compact ? 34 : 96,
              maxWidth: compact ? 34 : 126,
            ),
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
            decoration: BoxDecoration(
              color: dark
                  ? visual.color.withValues(alpha: 0.13)
                  : visual.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: visual.color.withValues(alpha: 0.44)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusIcon(visual: visual),
                if (!compact) ...[
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      visual.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dark ? Colors.white : visual.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  _StatusVisual _visualFor(
    BackendConnectionState state, {
    required bool hasPendingChanges,
  }) {
    if (hasPendingChanges && state == BackendConnectionState.connected) {
      return const _StatusVisual(
        label: 'Pending',
        color: Color(0xFFF59E0B),
        icon: Icons.sync_problem_rounded,
        syncing: false,
      );
    }

    switch (state) {
      case BackendConnectionState.syncing:
        return const _StatusVisual(
          label: '',
          color: Color(0xFF38BDF8),
          icon: Icons.sync_rounded,
          syncing: true,
        );
      case BackendConnectionState.connected:
        return const _StatusVisual(
          label: '',
          color: Color(0xFF22C55E),
          icon: Icons.cloud_done_rounded,
          syncing: false,
        );
      case BackendConnectionState.offline:
        return const _StatusVisual(
          label: '',
          color: Color(0xFFEF4444),
          icon: Icons.cloud_off_rounded,
          syncing: false,
        );
      case BackendConnectionState.idle:
        return const _StatusVisual(
          label: '',
          color: Color(0xFFF59E0B),
          icon: Icons.schedule_rounded,
          syncing: false,
        );
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
    return '$year-$month-$day $hour:$minute';
  }
}

class _StatusVisual {
  const _StatusVisual({
    required this.label,
    required this.color,
    required this.icon,
    required this.syncing,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool syncing;
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.visual});

  final _StatusVisual visual;

  @override
  Widget build(BuildContext context) {
    if (visual.syncing) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: visual.color),
      );
    }

    return Icon(visual.icon, color: visual.color, size: 18);
  }
}
