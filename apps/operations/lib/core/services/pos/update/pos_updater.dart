import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/services/edge/orders_tables/coordinator.dart';
import 'update_readiness.dart';

/// Host-local updater IPC, separate from Venue operational authority.
class PosUpdater extends ChangeNotifier {
  static final instance = PosUpdater();
  PosUpdater({
    this.requestOverride,
    this.flushOverride,
    this.dataDirectory,
    this.environmentOverride,
    this.windowsOverride,
    this.requestTimeout = const Duration(seconds: 12),
    this.startupTimeout = const Duration(seconds: 150),
  });
  final Map<String, String>? environmentOverride;
  final bool? windowsOverride;
  final Duration requestTimeout;
  final Duration startupTimeout;
  Map<String, String> get _environment =>
      environmentOverride ?? Platform.environment;
  String? startupFailure;
  String startupStage = 'მოწმდება ადგილობრივი მონაცემები';
  final Stopwatch _startupWatch = Stopwatch();
  Timer? _startupTimer;
  int get startupSeconds => _startupWatch.elapsed.inSeconds;
  String? _startupLogPath;
  String? _lastStartupLog;

  void _startupError(String message) {
    startupFailure = message;
    _recordStartup(message);
  }

  void _recordStartup(String message) {
    if (_lastStartupLog == message) return;
    _lastStartupLog = message;
    final path = _startupLogPath;
    if (path != null) {
      unawaited(
        File(path)
            .writeAsString(
              '${DateTime.now().toUtc().toIso8601String()} $message\n',
              mode: FileMode.append,
              flush: true,
            )
            .catchError((Object error) {
              developer.log(
                'Cannot write startup diagnostic',
                error: error,
                name: 'pos_updater',
              );
              return File(path);
            }),
      );
    }
  }

  void _startStartupClock() {
    if (!probation || _startupTimer != null) return;
    _startupWatch.start();
    _startupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!probation) return;
      if (_startupWatch.elapsed >= startupTimeout) {
        _startupError(
          'გაშვების შემოწმების დრო ამოიწურა. დახურეთ POS და შეამოწმეთ გაშვების ჟურნალი.',
        );
      }
      notifyListeners();
    });
  }

  Future<void> retryStartupCheck() async {
    if (_refreshing) return;
    if (!configured) {
      await initialize();
    }
    if (configured) await refresh();
  }

  final String? dataDirectory;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)?
  requestOverride;
  final Future<void> Function()? flushOverride;
  Map<String, dynamic> state = {'status': 'UP_TO_DATE'};
  bool configured = false;
  bool installing = false;
  bool probation = false;
  bool awaitingDecision = false;
  bool checking = false;
  bool preparingInstall = false;
  bool get inputHeld => installing || probation || awaitingDecision;
  bool get blockingOverlay =>
      installing || awaitingDecision || startupFailure != null;

  /// Login/enrollment can remain visible while Go verifies startup. Do not
  /// enter restaurant operations or start command execution until Go accepts
  /// this process. A failed check is explicit and never bypasses admission.
  Future<void> waitForStartup() async {
    if (startupFailure != null) throw StateError(startupFailure!);
    if (!inputHeld) return;
    final done = Completer<void>();
    void changed() {
      if (done.isCompleted) return;
      if (startupFailure != null) {
        done.completeError(StateError(startupFailure!));
      } else if (!inputHeld) {
        done.complete();
      }
    }

    addListener(changed);
    try {
      changed();
      await done.future.timeout(startupTimeout);
    } finally {
      removeListener(changed);
    }
  }

  String? localBlock;
  bool _readinessBlocked = false;
  String? installStage;
  String? get visibleInstallStage => preparingInstall
      ? installStage ?? 'მოწმდება განახლების მზადყოფნა'
      : installing
      ? state['status'] == 'RESTARTING'
            ? 'POS თავიდან ირთვება'
            : state['status'] == 'INSTALLING'
            ? 'მიმდინარეობს ახალი ვერსიის დაყენება'
            : 'მოთხოვნა გაიგზავნა — ველოდებით Edge-ის პასუხს'
      : null;
  String? connectionIssue;
  DateTime? lastStatusAt;

  /// The launch identity belongs to this running process. Edge's current slot
  /// may already refer to a candidate while activation/recovery is in progress.
  String get currentVersion {
    final launched = _environment['VYNIC_POS_UPDATE_VERSION']?.trim();
    if (launched != null && launched.isNotEmpty) return launched;
    return (state['current'] as String? ?? '').trim();
  }

  bool get lastUpdateRolledBack =>
      state['lastOutcome'] == 'ROLLED_BACK' || state['status'] == 'ROLLED_BACK';
  bool get hasStagedUpdate =>
      connectionIssue == null &&
      (state['status'] == 'READY_TO_INSTALL' || state['status'] == 'BLOCKED') &&
      version.isNotEmpty &&
      version != currentVersion;

  /// Older Edge versions report all failures as FAILED. Preserve the failure,
  /// but distinguish a feed lookup from an installation in customer copy.
  bool get releaseCheckFailed {
    final reason = (state['reason'] as String? ?? '').toLowerCase();
    return state['status'] == 'FAILED' &&
        (reason.contains('/manifest.json') ||
            reason.contains('release http') ||
            reason.contains('manifest too large'));
  }

  String? deferredVersion;
  String? _attempt;
  Map<String, dynamic>? _config;
  Timer? _poll;
  bool _refreshing = false;
  bool _stopping = false;

  /// Cancel local polling only. Edge remains running and owns staged releases.
  Future<void> stopForQuit() async {
    _stopping = true;
    _poll?.cancel();
    // Startup probation is refused by Quit, so its heartbeat has already ended.
    while (_refreshing) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  String get status =>
      localBlock != null ? 'BLOCKED' : state['status'] as String? ?? 'FAILED';
  String get version => state['version'] as String? ?? '';

  /// Resolve the updater's already-persisted data identity before opening Hive.
  /// Windows publisher/product metadata may change; restaurant data must not.
  Future<String?> pinnedDataDirectory() async {
    if (!(windowsOverride ?? Platform.isWindows)) return null;
    final path = _environment['VYNIC_POS_UPDATER_CONFIG'];
    if (path == null) {
      if (_environment['VYNIC_POS_UPDATE_NONCE'] != null) {
        throw StateError('POS updater configuration is missing');
      }
      return null;
    }
    _config =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    if (!RegExp(
      r'^127\.0\.0\.1:[0-9]+$',
    ).hasMatch(_config!['listen'] as String)) {
      throw StateError('Updater must use loopback');
    }
    final current = await _request('status');
    final data = current['dataPath'];
    if (data == null || data == '') return null;
    if (data is! String ||
        !Directory(data).isAbsolute ||
        !await Directory(data).exists()) {
      throw StateError(
        'Saved restaurant data is unavailable; refusing to create an empty replacement.',
      );
    }
    return data;
  }

  Future<void> initialize() async {
    if (!(windowsOverride ?? Platform.isWindows)) return;
    probation = _environment['VYNIC_POS_UPDATE_NONCE'] != null;
    final path = _environment['VYNIC_POS_UPDATER_CONFIG'];
    _startStartupClock();
    if (path == null) {
      if (probation)
        _startupError('განახლების სერვისის კონფიგურაცია ვერ მოიძებნა.');
      return;
    }
    _startupLogPath =
        '${File(path).parent.parent.path}${Platform.pathSeparator}logs${Platform.pathSeparator}pos-startup.log';
    try {
      _config =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final listen = _config!['listen'] as String;
      if (!RegExp(r'^127\.0\.0\.1:[0-9]+$').hasMatch(listen))
        throw StateError('Updater must use loopback');
      await EdgeCommandJournal.open();
      configured = true;
      UpdateReadiness.enabled = true;
      UpdateReadiness.startupReady = DatabaseCore.dbVersion == 9;
      UpdateReadiness.recoveryChecks.add(
        () => ClosureJournalRepository.pending().isNotEmpty
            ? 'დახურვის აღდგენა ჯერ არ დასრულებულა'
            : null,
      );
      UpdateReadiness.recoveryChecks.add(OrderTableCoordinator.updateBlocker);
      UpdateReadiness.recoveryChecks.add(
        () => EdgeCommandJournal.hasUnresolvedExecution
            ? 'მიმდინარე ოპერაციის შედეგი გაურკვეველია'
            : null,
      );
      deferredVersion =
          DatabaseCore.settingsBox?.get('posUpdateLater') as String?;
      final savedAttempt = DatabaseCore.settingsBox?.get('posUpdateAttempt');
      if (savedAttempt is Map) {
        _attempt = savedAttempt['id'] as String?;
        awaitingDecision = _attempt != null && !probation;
      }
      final nonce = _environment['VYNIC_POS_UPDATE_NONCE'];
      probation = nonce != null;
    } catch (e, st) {
      state = {'status': 'FAILED'};
      if (probation) _startupError('გაშვების მომზადება ვერ დასრულდა: $e');
      developer.log(
        'POS updater initialization failed',
        error: e,
        stackTrace: st,
        name: 'pos_updater',
      );
      notifyListeners();
    }
  }

  /// Called after the first rendered frame, after Hive migration/recovery.
  Future<void> startAfterFirstFrame() async {
    if (configured) {
      await refresh();
      if (_stopping) return;
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refresh()),
      );
    }
    while (inputHeld) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, dynamic>> _request(
    String route, [
    Map<String, dynamic>? body,
  ]) async {
    if (requestOverride != null)
      return requestOverride!(route, body).timeout(requestTimeout);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final req = await client.openUrl(
          body == null ? 'GET' : 'POST',
          Uri.parse('http://${_config!['listen']}/v1/$route'),
        );
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${_config!['token']}',
        );
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final response = await req.close().timeout(const Duration(seconds: 10));
        final text = await utf8.decoder.bind(response).join();
        if (response.statusCode != 200)
          throw HttpException('Updater ${response.statusCode}: $text');
        return jsonDecode(text) as Map<String, dynamic>;
      })().timeout(requestTimeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _stopping) return;
    _refreshing = true;
    if (_readinessBlocked) {
      localBlock = UpdateReadiness.evaluate().reason;
      _readinessBlocked = localBlock != null;
    }
    try {
      state = await _request('status');
      connectionIssue = null;
      lastStatusAt = DateTime.now();
      if (awaitingDecision) {
        if (state['status'] == 'INSTALLING' ||
            state['status'] == 'RESTARTING') {
          installing = true;
          UpdateReadiness.frozen = true;
        } else {
          installing = false;
          UpdateReadiness.frozen = false;
          awaitingDecision = false;
          _attempt = null;
          await _clearAttempt();
        }
      }
      if (probation) {
        _startStartupClock();
        final readiness = UpdateReadiness.evaluate();
        if (readiness.status == 'READY') {
          startupStage = 'მოწმდება POS-ის სტაბილურობა';
          _recordStartup(
            'Sending startup health: schema=${DatabaseCore.dbVersion}, pid=$pid',
          );
          await _request('health', {
            'nonce': _environment['VYNIC_POS_UPDATE_NONCE'],
            'version': _environment['VYNIC_POS_UPDATE_VERSION'],
            'pid': pid,
            'dataPath': DatabaseCore.dataDirectoryPath,
            'hiveSchema': DatabaseCore.dbVersion,
          });
          state = await _request('status');
          if (state['startupVerified'] == true) {
            await _clearAttempt();
            probation = false;
            startupFailure = null;
            _startupTimer?.cancel();
            _startupTimer = null;
            _startupWatch.stop();
            _recordStartup('Startup health verified');
          } else if (_startupWatch.elapsed < startupTimeout) {
            startupFailure = null;
          }
        } else {
          _startupError(readiness.reason ?? 'მონაცემების აღდგენა ვერ დასრულდა');
        }
      }
      if (installing &&
          (state['status'] == 'FAILED' || state['status'] == 'ROLLED_BACK')) {
        // Go reports a terminal outcome. A surviving old process can resume;
        // during a real rollback it has already been replaced by a new process.
        installing = false;
        UpdateReadiness.frozen = false;
        _attempt = null;
        await _clearAttempt();
      }
    } catch (e, st) {
      developer.log(
        'POS updater connection failed',
        error: e,
        stackTrace: st,
        name: 'pos_updater',
      );
      if (probation) {
        final reason = state['reason'];
        _startupError(
          'გაშვების შემოწმება ვერ დასრულდა: $e${reason is String && reason.isNotEmpty ? '\n$reason' : ''}',
        );
      }
      connectionIssue = e.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> later() async {
    try {
      await _later();
    } catch (e, st) {
      developer.log(
        'Could not persist Later',
        error: e,
        stackTrace: st,
        name: 'pos_updater',
      );
      localBlock = 'არჩევანი ვერ შეინახა';
      notifyListeners();
    }
  }

  Future<void> _later() async {
    deferredVersion = version;
    if (DatabaseCore.settingsBox != null) {
      await DatabaseCore.settingsBox!.put('posUpdateLater', version);
      await DatabaseCore.settingsBox!.flush();
    }
    notifyListeners();
  }

  Future<void> check() async {
    if (checking || inputHeld) return;
    checking = true;
    localBlock = null;
    notifyListeners();
    try {
      await _request('check', {});
      await refresh();
    } catch (e, st) {
      developer.log(
        'Update check failed',
        error: e,
        stackTrace: st,
        name: 'pos_updater',
      );
      connectionIssue = e.toString();
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> installNow() async {
    if (preparingInstall) return;
    preparingInstall = true;
    installStage = 'მოწმდება განახლების მზადყოფნა';
    notifyListeners();
    try {
      await _installNow();
    } catch (e, st) {
      developer.log(
        'Could not prepare update',
        error: e,
        stackTrace: st,
        name: 'pos_updater',
      );
      localBlock = 'განახლებისთვის მონაცემების მომზადება ვერ დასრულდა';
    } finally {
      preparingInstall = false;
      installStage = null;
      notifyListeners();
    }
  }

  Future<void> _installNow() async {
    if (probation || awaitingDecision) return;
    if (installing) {
      await _submit();
      return;
    }
    localBlock = null;
    _readinessBlocked = false;
    final readiness = UpdateReadiness.evaluate();
    if (readiness.status == 'BLOCKED') {
      localBlock = readiness.reason;
      _readinessBlocked = true;
      _recordStartup(
        'Update blocked: $localBlock; active=${UpdateReadiness.activeOperations.join(', ')}',
      );
      notifyListeners();
      return;
    }
    installStage = 'ინახება მონაცემები — განახლება ჯერ არ დაწყებულა';
    notifyListeners();
    _attempt ??= const Uuid().v4();
    // Persist before freeze, then recheck: writes can have arrived during await.
    if (DatabaseCore.settingsBox != null) {
      await DatabaseCore.settingsBox!.put('posUpdateAttempt', {
        'id': _attempt,
        'version': version,
      });
      await DatabaseCore.settingsBox!.flush();
    }
    localBlock = await UpdateReadiness.freeze(flushOverride ?? flushLocalState);
    if (localBlock != null) {
      _readinessBlocked = true;
      _recordStartup(
        'Update blocked: $localBlock; active=${UpdateReadiness.activeOperations.join(', ')}',
      );
      notifyListeners();
      return;
    }
    installing = true;
    installStage = 'მოთხოვნა იგზავნება Edge-ში';
    notifyListeners();
    await _submit();
  }

  Future<void> _submit() async {
    try {
      state = await _request('install', {
        'requestId': _attempt,
        'version': version,
        'pid': pid,
        'ready': true,
        'dataPath': dataDirectory ?? DatabaseCore.dataDirectoryPath,
      });
    } catch (e, st) {
      // A lost ACK is uncertain: retain the same ID and barrier, never resume
      // business work while Go might be terminating this process.
      if (e is HttpException) {
        try {
          final current = await _request('status');
          if (current['attempt'] != _attempt &&
              current['status'] != 'INSTALLING' &&
              current['status'] != 'RESTARTING') {
            state = current;
            installing = false;
            UpdateReadiness.frozen = false;
            _attempt = null;
            localBlock = 'განახლება ვერ დაიწყო. სცადეთ ხელახლა';
          }
        } catch (statusError, statusStack) {
          developer.log(
            'Install rejection status unavailable',
            error: statusError,
            stackTrace: statusStack,
            name: 'pos_updater',
          );
        }
      }
      developer.log(
        'Install request unresolved or rejected',
        error: e,
        stackTrace: st,
        name: 'pos_updater',
      );
    }
    notifyListeners();
  }

  Future<void> _clearAttempt() async {
    final settings = DatabaseCore.settingsBox;
    if (settings != null && settings.isOpen) {
      await settings.delete('posUpdateAttempt');
      await settings.flush();
    }
  }

  static Future<void> flushLocalState() async {
    for (final box in <Box?>[
      DatabaseCore.metaBox,
      DatabaseCore.orderBox,
      DatabaseCore.tableBox,
      DatabaseCore.userBox,
      DatabaseCore.menuBox,
      DatabaseCore.packageBox,
      DatabaseCore.settingsBox,
      DatabaseCore.salesBox,
      DatabaseCore.expenseBox,
      DatabaseCore.auditLogBox,
      DatabaseCore.errorLogBox,
      DatabaseCore.reservationBox,
      DatabaseCore.quickOrderBox,
      DatabaseCore.closureJournalBox,
      DatabaseCore.inventoryBox,
    ]) {
      if (box != null && box.isOpen) await box.flush();
    }
    await OrderTableCoordinator.flushForUpdate();
    await EdgeCommandJournal.flushForUpdate();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _startupTimer?.cancel();
    _startupWatch.stop();
    super.dispose();
  }
}
