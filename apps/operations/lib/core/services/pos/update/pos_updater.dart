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
  PosUpdater({this.requestOverride, this.flushOverride, this.dataDirectory});
  final String? dataDirectory;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)?
  requestOverride;
  final Future<void> Function()? flushOverride;
  Map<String, dynamic> state = {'status': 'UP_TO_DATE'};
  bool configured = false;
  bool installing = false;
  bool probation = false;
  bool awaitingDecision = false;
  bool preparingInstall = false;
  bool get inputHeld => installing || probation || awaitingDecision;
  String? localBlock;
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

  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    probation = Platform.environment['VYNIC_POS_UPDATE_NONCE'] != null;
    final path = Platform.environment['VYNIC_POS_UPDATER_CONFIG'];
    if (path == null) return;
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
      final nonce = Platform.environment['VYNIC_POS_UPDATE_NONCE'];
      probation = nonce != null;
    } catch (e, st) {
      state = {'status': 'FAILED'};
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
    if (requestOverride != null) return requestOverride!(route, body);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
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
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _stopping) return;
    _refreshing = true;
    try {
      state = await _request('status');
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
        final readiness = UpdateReadiness.evaluate();
        if (readiness.status == 'READY') {
          await _request('health', {
            'nonce': Platform.environment['VYNIC_POS_UPDATE_NONCE'],
            'version': Platform.environment['VYNIC_POS_UPDATE_VERSION'],
            'pid': pid,
            'dataPath': DatabaseCore.dataDirectoryPath,
            'hiveSchema': DatabaseCore.dbVersion,
          });
          state = await _request('status');
          if (state['startupVerified'] == true) {
            await _clearAttempt();
            probation = false;
          }
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
      if (!installing) state = {...state, 'status': 'FAILED'};
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
      state = {...state, 'status': 'FAILED'};
      notifyListeners();
    }
  }

  Future<void> installNow() async {
    if (preparingInstall) return;
    preparingInstall = true;
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
    final readiness = UpdateReadiness.evaluate();
    if (readiness.status == 'BLOCKED') {
      localBlock = readiness.reason;
      notifyListeners();
      return;
    }
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
      notifyListeners();
      return;
    }
    installing = true;
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
    super.dispose();
  }
}
