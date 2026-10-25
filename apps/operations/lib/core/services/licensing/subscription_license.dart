import 'package:crypto/crypto.dart' as crypto;
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../database/database_core.dart';
import '../../models/order.dart';
import '../edge/edge_device_credential_store.dart';
import '../sync/api_config.dart';
import 'offline_lease.dart';
import 'license_continuity.dart';

class _LicenseAdmission {
  bool active = true;
}

class SubscriptionLicense extends ChangeNotifier {
  SubscriptionLicense({
    http.Client? client,
    Future<LicenseClockSample> Function()? continuity,
    int Function()? wallClock,
    LicenseVault vault = const LicenseVault(),
    String? trustedKey,
  }) : _client = client,
       _readContinuity = continuity ?? LicenseClockSample.read,
       _wallClock = wallClock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _vault = vault,
       _trustedKey = trustedKey ?? publicKey;
  final http.Client? _client;
  final Future<LicenseClockSample> Function() _readContinuity;
  final int Function() _wallClock;
  final LicenseVault _vault;
  Future<void> _vaultWrites = Future.value();
  String? _boot;
  final String _trustedKey;
  static final instance = SubscriptionLicense();
  static const channel = MethodChannel('ge.vynic/license');
  static const publicKey = String.fromEnvironment('VYNIC_LICENSE_PUBLIC_KEY');
  OfflineLease lease = OfflineLease();
  bool enabled = false;
  bool busy = false;
  bool offline = false;
  String? error;
  String? _identity;
  Timer? _timer;
  final Map<int, String> _existing = {};
  int _ticks = 0;
  int _denialGeneration = 0;
  static final _settlement = Object();
  static final _saleAdmission = Object();
  String? _billsIdentity;
  static const saleOperations = {
    'cancelOrder',
    'activate',
    'transferItems',
    'createOrder',
    'createTakeAwayOrder',
    'upsertMobileDineInOrder',
    'createOrderForPackage',
    'updateOrder',
    'updateOrderStatus',
    'addItemToOrder',
    'removeItemFromOrder',
    'updateOrderItemQuantity',
    'managerOrderEdit',
    'changeTables',
    'reserveTable',
    'reserveTableForReservation',
    'createReservation',
    'activateReservation',
    'activateTodaysReservations',
    'updateReservationDetails',
    'updateReservationPreOrderItems',
    'updateReservationTables',
    'updateReservationStatus',
    'restoreClosedOrderFromSale',
    'saveSaleRecord',
    'recordAdvanceReceipt',
    'toggleServiceFee',
    'setDiscount',
    'setAdvance',
    'setManualAdjustment',
    'updateStatus',
    'addItem',
    'removeItem',
    'updateItemQuantity',
  };
  Future<T> operation<T>(String operation, Future<T> Function() action) =>
      enabled ? _operation(operation, action) : action();

  Future<T> _operation<T>(String operation, Future<T> Function() action) async {
    if (operation == 'closeTable' || operation == 'completeExistingSale') {
      final scope = _LicenseAdmission();
      try {
        return await runZoned(action, zoneValues: {_settlement: scope});
      } finally {
        scope.active = false;
      }
    }
    final parent = Zone.current[_saleAdmission];
    final settlement = Zone.current[_settlement];
    if (!saleOperations.contains(operation) ||
        (settlement is _LicenseAdmission &&
            settlement.active &&
            const {'updateOrder', 'saveSaleRecord'}.contains(operation)) ||
        parent is _LicenseAdmission && parent.active ||
        !enabled)
      return action();
    await requireSale();
    final scope = _LicenseAdmission();
    try {
      final result = await runZoned(
        action,
        zoneValues: {_saleAdmission: scope},
      );
      // An admitted transaction finishes even if a timer/revocation arrives
      // during its awaited writes. Its exact resulting bill stays settleable.
      await _recordBills();
      return result;
    } finally {
      scope.active = false;
    }
  }

  String _currentIdentity() =>
      '${EdgeDeviceCredentialStore.deviceId}|${EdgeDeviceCredentialStore.venueId}|${EdgeDeviceCredentialStore.installationId}|${EdgeDeviceCredentialStore.credential}';
  String get _vaultAccount => crypto.sha256
      .convert(
        utf8.encode(
          '${EdgeDeviceCredentialStore.deviceId}|${EdgeDeviceCredentialStore.installationId}',
        ),
      )
      .toString();
  String get _binding => crypto.sha256
      .convert(utf8.encode('${_currentIdentity()}|$_trustedKey'))
      .toString();

  Future<void> _persist(Map<String, dynamic> record) {
    final account = _vaultAccount;
    final value = jsonEncode({'version': 1, 'binding': _binding, ...record});
    // Never let a late positive write overtake a received denial.
    final next = _vaultWrites.then((_) => _vault.write(account, value));
    _vaultWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _restore({required bool localDenial}) async {
    final generation = _denialGeneration;
    final identity = _currentIdentity();
    try {
      final raw = await _vault.read(_vaultAccount);
      if (generation != _denialGeneration || identity != _currentIdentity()) {
        throw StateError('Restored license superseded');
      }
      if (raw == null) return;
      final record = jsonDecode(raw);
      if (localDenial && ['REVOKED', 'EXPIRED'].contains(lease.reason)) return;
      if (record is! Map<String, dynamic> ||
          record['version'] != 1 ||
          record['binding'] != _binding) {
        throw const FormatException('License vault binding mismatch');
      }
      if ([
        'REVOKED',
        'EXPIRED',
        'VERIFICATION_REQUIRED',
      ].contains(record['reason'])) {
        lease.restrict(record['reason'] as String);
        if (['TRIAL', 'SUBSCRIPTION'].contains(record['kind'])) {
          lease.kind = record['kind'] as String;
        }
        return;
      }
      // A legacy received denial remains stronger than a cached positive record.
      if (localDenial) return;
      final sample = await _readContinuity();
      if (record['boot'] != sample.boot ||
          record['lease'] is! Map<String, dynamic>) {
        throw const FormatException('License boot continuity uncertain');
      }
      final restored = OfflineLease();
      await restored.restore(
        record['lease'],
        publicKey: base64Decode(_trustedKey),
        device: EdgeDeviceCredentialStore.deviceId!,
        venue: EdgeDeviceCredentialStore.venueId!,
        installation: EdgeDeviceCredentialStore.installationId!,
        elapsed: sample.elapsed,
        wall: _wallClock(),
      );
      if (generation != _denialGeneration || identity != _currentIdentity()) {
        throw StateError('Restored license superseded');
      }
      lease = restored;
      _identity = identity;
      _boot = sample.boot;
      offline = true;
      if (!lease.allowed) await _rememberDenial();
    } catch (_) {
      if (!['REVOKED', 'EXPIRED'].contains(lease.reason)) {
        lease.restrict('VERIFICATION_REQUIRED');
      }
      error = 'CONTINUITY_UNAVAILABLE';
      // Do not fall back to a lease/anchor in application backups.
    }
  }

  Future<void> start() async {
    enabled = true;
    final denial = DatabaseCore.settingsBox?.get('subscriptionLicenseDenial');
    final localDenial =
        denial is Map &&
        denial['identity'] ==
            '${EdgeDeviceCredentialStore.deviceId}|${EdgeDeviceCredentialStore.installationId}' &&
        [
          'REVOKED',
          'EXPIRED',
          'VERIFICATION_REQUIRED',
        ].contains(denial['reason']);
    if (localDenial) {
      lease.restrict(denial['reason'] as String);
      if (['TRIAL', 'SUBSCRIPTION'].contains(denial['kind']))
        lease.kind = denial['kind'] as String;
    }
    await _restore(localDenial: localDenial);
    final bills = DatabaseCore.settingsBox?.get('subscriptionLicenseBills');
    if (bills is Map &&
        bills['identity'] == _billIdentity &&
        bills['orders'] is Map) {
      _billsIdentity = _billIdentity;
      for (final entry in (bills['orders'] as Map).entries) {
        final id = int.tryParse(entry.key.toString());
        if (id != null && entry.value is String)
          _existing[id] = entry.value as String;
      }
    }
    unawaited(verify());
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      await check();
      if (++_ticks % 60 == 0) unawaited(verify());
      notifyListeners();
    });
  }

  // All fields are frozen: restriction is settlement-only, not an edit mode.
  static String image(Order order) =>
      crypto.sha256.convert(utf8.encode(jsonEncode(order.toJson()))).toString();
  String get _billIdentity =>
      '${EdgeDeviceCredentialStore.deviceId}|${EdgeDeviceCredentialStore.installationId}|${EdgeDeviceCredentialStore.venueId}';

  /// Device-local checkpoint, excluded from portable restores. Only a verified
  /// session may admit bills; restart/restore cannot invent settlement rights.
  Future<void> recordBills() async {
    if (!enabled || !lease.allowed) return;
    await _recordBills();
  }

  Future<void> _recordBills() async {
    _billsIdentity = _billIdentity;
    _existing.clear();
    for (final order in DatabaseCore.orderBox?.values ?? <Order>[]) {
      if (!order.statusEnum.isTerminal) _existing[order.orderId] = image(order);
    }
    try {
      await DatabaseCore.settingsBox?.put('subscriptionLicenseBills', {
        'identity': _billIdentity,
        'orders': {
          for (final e in _existing.entries) e.key.toString(): e.value,
        },
      });
      await DatabaseCore.settingsBox?.flush();
    } catch (_) {
      lease.restrict('VERIFICATION_REQUIRED');
      rethrow;
    }
  }

  Future<void> check() async {
    if (!enabled || !lease.allowed) return;
    final checked = lease;
    try {
      final sample = await _readContinuity();
      // A newer online decision or received denial supersedes this sample.
      if (!identical(checked, lease) || !lease.allowed) return;
      if ((_identity != null && _identity != _currentIdentity()) ||
          (_boot != null && sample.boot != _boot)) {
        lease.restrict('VERIFICATION_REQUIRED');
      }
      lease.check(elapsed: sample.elapsed, wall: _wallClock());
    } catch (_) {
      if (identical(checked, lease) && lease.allowed) {
        lease.restrict('VERIFICATION_REQUIRED');
      }
    }
    if (identical(checked, lease) && !lease.allowed) {
      await _rememberDenial();
    }
  }

  Future<void> verify() async {
    if (busy || !enabled) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final device = EdgeDeviceCredentialStore.deviceId;
      final venue = EdgeDeviceCredentialStore.venueId;
      final installation = EdgeDeviceCredentialStore.installationId;
      final credential = EdgeDeviceCredentialStore.credential;
      final identity = _currentIdentity();
      final generation = _denialGeneration;
      if (device == null ||
          venue == null ||
          installation == null ||
          credential == null ||
          _trustedKey.isEmpty) {
        throw StateError(
          'License verification needs enrollment and a trusted signing key',
        );
      }
      final nonce = List.generate(
        32,
        (_) => Random.secure().nextInt(256),
      ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      // Bracket the request as well as the cached lease. A guest clock can
      // pause while a signed response is pending; a timeout alone cannot prove
      // freshness. Sampling wall time first is conservative if this read stalls.
      final requestWall = _wallClock();
      final requestClock = await _readContinuity();
      final response = await (_client?.post ?? http.post)(
        Uri.parse('${ApiConfig.baseUrl}/edge/subscription-lease'),
        headers: {
          ...ApiConfig.posSyncHeaders,
          'X-POS-Sync-Key': credential,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'nonce': nonce}),
      ).timeout(const Duration(seconds: 15));
      if (identity != _currentIdentity())
        throw StateError('License identity changed');
      if (response.statusCode == 401 || response.statusCode == 403) {
        await authenticationDenied();
        return;
      }
      if (response.statusCode != 200)
        throw StateError('Verification unavailable');
      final sample = await _readContinuity();
      if (sample.boot != requestClock.boot) {
        throw StateError('Boot changed during verification');
      }
      final candidate = OfflineLease();
      await candidate.accept(
        jsonDecode(response.body),
        publicKey: base64Decode(_trustedKey),
        nonce: nonce,
        device: device,
        venue: venue,
        installation: installation,
        requestElapsed: requestClock.elapsed,
        elapsed: sample.elapsed,
        wall: _wallClock(),
      );
      if (candidate.allowed) {
        // Include asynchronous signature verification before saving a positive
        // anchor. Confirmed signed negative decisions keep their existing path.
        final verifiedClock = await _readContinuity();
        final verifiedWall = _wallClock();
        final transit = verifiedClock.elapsed - requestClock.elapsed;
        final drift = verifiedWall - requestWall - transit;
        if (verifiedClock.boot != requestClock.boot ||
            transit < 0 ||
            transit > 30000 ||
            drift.abs() > 2000) {
          if (generation == _denialGeneration &&
              identity == _currentIdentity()) {
            if (!['REVOKED', 'EXPIRED'].contains(lease.reason)) {
              lease.restrict('VERIFICATION_REQUIRED');
            }
            await _rememberDenial();
          }
          throw StateError('Request clock continuity uncertain');
        }
        candidate.check(elapsed: verifiedClock.elapsed, wall: verifiedWall);
      }
      if (generation != _denialGeneration || identity != _currentIdentity()) {
        lease.restrict(
          generation != _denialGeneration ? 'REVOKED' : 'VERIFICATION_REQUIRED',
        );
        throw StateError('License decision superseded');
      }
      if (!candidate.allowed) {
        _denialGeneration++;
        lease = candidate;
        offline = false;
        await _rememberDenial();
        return;
      }
      await _persist({'boot': sample.boot, 'lease': candidate.checkpoint()});
      if (generation != _denialGeneration || identity != _currentIdentity()) {
        throw StateError('License decision superseded during persistence');
      }
      lease = candidate;
      _boot = sample.boot;
      _identity = identity;
      offline = false;
      if (lease.allowed) {
        await recordBills();
        if (generation == _denialGeneration && lease.allowed) {
          await DatabaseCore.settingsBox?.delete('subscriptionLicenseDenial');
        }
      } else {
        await _rememberDenial();
      }
    } catch (_) {
      offline = true;
      error = 'VERIFICATION_UNAVAILABLE';
      // Network/malformed replies never renew, clear a denial, or become unpaid.
    } finally {
      busy = false;
      await check();
      notifyListeners();
    }
  }

  Future<void> authenticationDenied() async {
    if (!enabled) return;
    _denialGeneration++;
    lease.restrict('REVOKED');
    await _rememberDenial();
    notifyListeners();
  }

  Future<void> _rememberDenial() async {
    final reason = lease.reason;
    final kind = lease.kind;
    // Queue the protected tombstone before awaiting unrelated Hive writes.
    // Each store is attempted even if the other is unavailable.
    final protectedSave = _persist({
      'reason': reason,
      'kind': kind,
    }).then((_) => true, onError: (Object _) => false);
    var localSaved = true;
    try {
      await DatabaseCore.settingsBox?.put('subscriptionLicenseDenial', {
        'identity':
            '${EdgeDeviceCredentialStore.deviceId}|${EdgeDeviceCredentialStore.installationId}',
        'reason': reason,
        'kind': kind,
      });
      await DatabaseCore.settingsBox?.flush();
    } catch (_) {
      localSaved = false;
    }
    if (!await protectedSave || !localSaved) {
      // Remain restricted and surface a durability fault, never false success.
      error = 'CONTINUITY_STORAGE_UNAVAILABLE';
    }
  }

  Future<void> requireSale() async {
    if (!enabled) return;
    final scope = Zone.current[_saleAdmission];
    if (scope is _LicenseAdmission && scope.active) return;
    await check();
    if (!lease.allowed)
      throw StateError(
        'საჭიროა ლიცენზიის შემოწმება / License restriction: ${lease.reason}',
      );
  }

  Future<void> consumeSettlement(int orderId) async {
    if (!enabled) return;
    _existing.remove(orderId);
    await DatabaseCore.settingsBox?.put('subscriptionLicenseBills', {
      'identity': _billIdentity,
      'orders': {for (final e in _existing.entries) e.key.toString(): e.value},
    });
    await DatabaseCore.settingsBox?.flush();
  }

  Future<void> requireSettlement(
    Order order, {
    required double gross,
    required double advance,
    List<OrderItem>? items,
  }) async {
    if (!enabled) return;
    await check();
    if (lease.allowed) return;
    if (_billsIdentity != _billIdentity ||
        _existing[order.orderId] != image(order) ||
        (gross - order.grossAmount).abs() > .005 ||
        (advance - order.effectiveAdvanceAmount).abs() > .005 ||
        (items != null &&
            jsonEncode(items.map((i) => i.toJson()).toList()) !=
                jsonEncode(
                  [
                    ...order.packageItems,
                    ...order.items,
                  ].map((i) => i.toJson()).toList(),
                ))) {
      throw StateError('Only unchanged pre-existing bills can be settled');
    }
  }

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    enabled = false;
    busy = false;
    offline = false;
    error = null;
    _identity = null;
    _boot = null;
    _billsIdentity = null;
    _denialGeneration = 0;
    _ticks = 0;
    _existing.clear();
    lease = OfflineLease();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> openPurchase() => channel.invokeMethod<void>('purchase');
}
