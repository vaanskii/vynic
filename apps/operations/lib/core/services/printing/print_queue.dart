import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

enum PrintQueueTarget { kitchen, receipt }

typedef PrintQueueJob = Future<bool> Function();

class PrintQueue {
  const PrintQueue._();

  static final Queue<_QueuedPrintJob> _kitchenQueue = Queue<_QueuedPrintJob>();
  static final Queue<_QueuedPrintJob> _receiptQueue = Queue<_QueuedPrintJob>();

  static bool _isKitchenProcessing = false;
  static bool _isReceiptProcessing = false;
  static bool _isKitchenRunning = false;
  static bool _isReceiptRunning = false;

  static void enqueue({
    required PrintQueueTarget target,
    required PrintQueueJob job,
    void Function(bool success)? onComplete,
    String? debugLabel,
  }) {
    _queueFor(target).add(
      _QueuedPrintJob(job: job, onComplete: onComplete, debugLabel: debugLabel),
    );

    developer.log(
      '[PrintQueue] ${_targetLabel(target)} queue status: '
      '${pendingCountFor(target)} active jobs',
    );

    unawaited(_processQueue(target));
  }

  static int get pendingCount =>
      pendingCountFor(PrintQueueTarget.kitchen) +
      pendingCountFor(PrintQueueTarget.receipt);

  static int pendingCountFor(PrintQueueTarget target) {
    final queueCount = _queueFor(target).length;
    final runningCount = _isRunning(target) ? 1 : 0;
    return queueCount + runningCount;
  }

  static Future<void> _processQueue(PrintQueueTarget target) async {
    if (_isProcessing(target)) {
      return;
    }

    _setProcessing(target, true);

    try {
      final queue = _queueFor(target);
      while (queue.isNotEmpty) {
        final queuedJob = queue.removeFirst();
        bool success = false;

        _setRunning(target, true);
        try {
          final label = queuedJob.debugLabel;
          if (label != null && label.isNotEmpty) {
            developer.log('[PrintQueue] Starting $label');
          }
          success = await queuedJob.job();
        } catch (e) {
          developer.log('[PrintQueue] ${_targetLabel(target)} job failed: $e');
          success = false;
        } finally {
          _setRunning(target, false);
        }

        try {
          queuedJob.onComplete?.call(success);
        } catch (e) {
          developer.log(
            '[PrintQueue] ${_targetLabel(target)} completion callback failed: $e',
          );
        }
      }
    } finally {
      _setProcessing(target, false);
      developer.log(
        '[PrintQueue] ${_targetLabel(target)} queue status: '
        '${pendingCountFor(target)} active jobs',
      );
    }
  }

  static Queue<_QueuedPrintJob> _queueFor(PrintQueueTarget target) {
    switch (target) {
      case PrintQueueTarget.kitchen:
        return _kitchenQueue;
      case PrintQueueTarget.receipt:
        return _receiptQueue;
    }
  }

  static bool _isProcessing(PrintQueueTarget target) {
    switch (target) {
      case PrintQueueTarget.kitchen:
        return _isKitchenProcessing;
      case PrintQueueTarget.receipt:
        return _isReceiptProcessing;
    }
  }

  static void _setProcessing(PrintQueueTarget target, bool value) {
    switch (target) {
      case PrintQueueTarget.kitchen:
        _isKitchenProcessing = value;
        return;
      case PrintQueueTarget.receipt:
        _isReceiptProcessing = value;
        return;
    }
  }

  static bool _isRunning(PrintQueueTarget target) {
    switch (target) {
      case PrintQueueTarget.kitchen:
        return _isKitchenRunning;
      case PrintQueueTarget.receipt:
        return _isReceiptRunning;
    }
  }

  static void _setRunning(PrintQueueTarget target, bool value) {
    switch (target) {
      case PrintQueueTarget.kitchen:
        _isKitchenRunning = value;
        return;
      case PrintQueueTarget.receipt:
        _isReceiptRunning = value;
        return;
    }
  }

  static String _targetLabel(PrintQueueTarget target) {
    switch (target) {
      case PrintQueueTarget.kitchen:
        return 'Kitchen';
      case PrintQueueTarget.receipt:
        return 'Receipt';
    }
  }
}

class _QueuedPrintJob {
  const _QueuedPrintJob({
    required this.job,
    required this.onComplete,
    required this.debugLabel,
  });

  final PrintQueueJob job;
  final void Function(bool success)? onComplete;
  final String? debugLabel;
}
