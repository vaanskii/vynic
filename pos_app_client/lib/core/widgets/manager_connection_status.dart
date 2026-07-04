import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

/// Live / reconnecting / offline indicator for the manager app.
enum ManagerConnectionLevel {
  online,
  connecting,
  offline,
}

ManagerConnectionLevel resolveManagerConnectionLevel() {
  if (MonitoringSocketService.isAppPaused) {
    return ManagerConnectionLevel.offline;
  }
  if (MonitoringSocketService.isInitializing.value) {
    return ManagerConnectionLevel.connecting;
  }
  if (MonitoringSocketService.isConnected.value) {
    if (MonitoringSocketService.apiError.value) {
      return ManagerConnectionLevel.connecting;
    }
    return ManagerConnectionLevel.online;
  }
  if (MonitoringSocketService.isReconnecting.value) {
    return ManagerConnectionLevel.connecting;
  }
  return ManagerConnectionLevel.offline;
}

Color colorForManagerConnectionLevel(ManagerConnectionLevel level) {
  switch (level) {
    case ManagerConnectionLevel.online:
      return const Color(0xFF22C55E);
    case ManagerConnectionLevel.connecting:
      return const Color(0xFFF97316);
    case ManagerConnectionLevel.offline:
      return const Color(0xFFEF4444);
  }
}

String labelForManagerConnectionLevel(ManagerConnectionLevel level) {
  switch (level) {
    case ManagerConnectionLevel.online:
      return 'დაკავშირებულია';
    case ManagerConnectionLevel.connecting:
      return 'კავშირი იღებს...';
    case ManagerConnectionLevel.offline:
      return 'კავშირი გაწყვეტილია';
  }
}

/// Connection dot: hidden while stable online; visible when offline/connecting;
/// brief green pulse when connection is restored.
class ManagerConnectionStatusDot extends StatefulWidget {
  const ManagerConnectionStatusDot({
    super.key,
    this.size = 9,
    this.restoredVisibleDuration = const Duration(seconds: 3),
  });

  final double size;
  final Duration restoredVisibleDuration;

  @override
  State<ManagerConnectionStatusDot> createState() =>
      _ManagerConnectionStatusDotState();
}

class _ManagerConnectionStatusDotState extends State<ManagerConnectionStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  ManagerConnectionLevel? _previousLevel;
  bool _showingRestored = false;
  Timer? _restoredHideTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _previousLevel = resolveManagerConnectionLevel();
    for (final n in _notifiers) {
      n.addListener(_onSignals);
    }
  }

  List<ValueNotifier<dynamic>> get _notifiers => [
        MonitoringSocketService.isConnected,
        MonitoringSocketService.isInitializing,
        MonitoringSocketService.isReconnecting,
        MonitoringSocketService.apiError,
      ];

  void _onSignals() {
    final level = resolveManagerConnectionLevel();
    final prev = _previousLevel;
    _previousLevel = level;

    if (level == ManagerConnectionLevel.online) {
      if (prev == ManagerConnectionLevel.offline ||
          prev == ManagerConnectionLevel.connecting) {
        _beginRestoredFeedback();
      } else if (!_showingRestored) {
        _pulse.stop();
      }
    } else {
      _cancelRestoredFeedback();
      if (level == ManagerConnectionLevel.connecting) {
        _pulse.repeat(reverse: true);
      }
    }

    if (mounted) setState(() {});
  }

  void _beginRestoredFeedback() {
    _restoredHideTimer?.cancel();
    _showingRestored = true;
    _pulse.repeat(reverse: true);
    _restoredHideTimer = Timer(widget.restoredVisibleDuration, () {
      if (!mounted) return;
      _pulse.stop();
      setState(() => _showingRestored = false);
    });
  }

  void _cancelRestoredFeedback() {
    _restoredHideTimer?.cancel();
    _restoredHideTimer = null;
    _showingRestored = false;
    _pulse.stop();
  }

  bool get _isProblemVisible {
    final level = resolveManagerConnectionLevel();
    return level == ManagerConnectionLevel.offline ||
        level == ManagerConnectionLevel.connecting;
  }

  bool get _shouldShow => _isProblemVisible || _showingRestored;

  @override
  void dispose() {
    _restoredHideTimer?.cancel();
    for (final n in _notifiers) {
      n.removeListener(_onSignals);
    }
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return SizedBox(
        width: widget.size + 6,
        height: widget.size + 6,
      );
    }

    final level = _showingRestored
        ? ManagerConnectionLevel.online
        : resolveManagerConnectionLevel();
    final color = colorForManagerConnectionLevel(level);
    final pulsing = _showingRestored ||
        level == ManagerConnectionLevel.connecting;

    return Semantics(
      label: labelForManagerConnectionLevel(level),
      child: Tooltip(
        message: labelForManagerConnectionLevel(level),
        child: SizedBox(
          width: widget.size + 6,
          height: widget.size + 6,
          child: Center(
            child: pulsing
                ? AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final glow = _showingRestored
                          ? 0.4 + _pulse.value * 0.5
                          : 0.35 + _pulse.value * 0.45;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: glow),
                              blurRadius: _showingRestored ? 12 : 8,
                              spreadRadius: _showingRestored ? 2 : 1,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: _dot(color),
                  )
                : _dot(color),
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
      ),
    );
  }
}
