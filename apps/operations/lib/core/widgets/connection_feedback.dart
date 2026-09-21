import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/sync/connection_status_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

/// Transient connection feedback; null means an attempt, not a recovery.
class ConnectionFeedback extends StatefulWidget {
  const ConnectionFeedback({
    super.key,
    required this.signals,
    required this.readConnected,
    required this.child,
    this.enabled,
  });

  factory ConnectionFeedback.pos({required Widget child}) => ConnectionFeedback(
    signals: ConnectionStatusService.backendState,
    readConnected: () => switch (ConnectionStatusService.backendState.value) {
      BackendConnectionState.connected => true,
      BackendConnectionState.offline => false,
      _ => null,
    },
    child: child,
  );

  factory ConnectionFeedback.manager({required Widget child}) =>
      ConnectionFeedback(
        signals: Listenable.merge([
          MonitoringSocketService.isConnected,
          MonitoringSocketService.isInitializing,
          MonitoringSocketService.isReconnecting,
          MonitoringSocketService.apiError,
        ]),
        enabled: () => AuthTokenService.token != null,
        readConnected: () {
          if (MonitoringSocketService.isAppPaused ||
              MonitoringSocketService.isInitializing.value) {
            return null;
          }
          return MonitoringSocketService.isConnected.value &&
              !MonitoringSocketService.apiError.value;
        },
        child: child,
      );

  final Listenable signals;
  final bool? Function() readConnected;
  final bool Function()? enabled;
  final Widget child;

  @override
  State<ConnectionFeedback> createState() => _ConnectionFeedbackState();
}

class _ConnectionFeedbackState extends State<ConnectionFeedback>
    with WidgetsBindingObserver {
  Timer? _lossTimer;
  Timer? _hideTimer;
  bool _outageReported = false;
  bool _foreground = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.signals.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(ConnectionFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signals != widget.signals) {
      oldWidget.signals.removeListener(_check);
      widget.signals.addListener(_check);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _check();
    } else {
      _lossTimer?.cancel();
      _lossTimer = null;
      _hideTimer?.cancel();
      if (_message != null) setState(() => _message = null);
    }
  }

  void _check() {
    if (widget.enabled?.call() == false) {
      _lossTimer?.cancel();
      _lossTimer = null;
      _outageReported = false;
      _hideTimer?.cancel();
      if (_message != null) setState(() => _message = null);
      return;
    }
    if (!_foreground) return;
    final connected = widget.readConnected();
    if (connected == null) return;
    if (connected) {
      _lossTimer?.cancel();
      _lossTimer = null;
      if (_outageReported) {
        _outageReported = false;
        _show('კავშირი აღდგა');
      }
    } else if (!_outageReported && _lossTimer == null) {
      // Ignore brief reconnects, including normal foreground socket renewal.
      _lossTimer = Timer(const Duration(seconds: 3), () {
        _lossTimer = null;
        if (!mounted || !_foreground || widget.enabled?.call() == false) return;
        if (widget.readConnected() != false) return;
        _outageReported = true;
        _show('სერვერთან კავშირი დაკარგულია');
      });
    }
  }

  void _show(String message) {
    _hideTimer?.cancel();
    setState(() => _message = message);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  void dispose() {
    widget.signals.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    _lossTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_message != null)
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.inverseSurface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
