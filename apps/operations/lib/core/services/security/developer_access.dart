import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/security/developer_code_format.dart';
import 'package:vynic/core/services/security/developer_otp.dart';
import 'package:vynic/core/services/security/developer_otp_chain.dart';
import 'package:vynic/core/services/security/developer_public_key.dart';

/// The capabilities a developer token can carry.
///
/// A token with no `scopes` field grants all of them. Narrow tokens exist so a
/// routine service call (read the logs, fix the backend URL) does not hand out
/// the ability to wipe a venue's database.
abstract final class DeveloperScope {
  /// Terminal id, version, box row counts, log export.
  static const diagnostics = 'diagnostics';

  /// Backend URL and sync plumbing.
  static const connection = 'connection';

  /// Printer host, port and protocol settings.
  static const printers = 'printers';

  /// The error log section, including clearing it.
  static const errors = 'errors';

  /// Creating a full backup from the developer panel.
  static const backup = 'backup';

  /// Restoring a backup over the live database.
  static const restore = 'restore';

  /// Erasing every box on this terminal.
  static const wipe = 'wipe';

  /// Resetting a locked-out venue's admin PIN.
  static const recovery = 'recovery';

  static const all = <String>[
    diagnostics,
    connection,
    printers,
    errors,
    backup,
    restore,
    wipe,
    recovery,
  ];

  /// The tools that destroy data or hand over an account. Nothing special
  /// gates them beyond the token's own scope list — they are named so the UI
  /// can warn about them, and so a narrow token has an obvious thing to omit.
  static const destructive = <String>[restore, wipe, recovery];
}

/// Why an unlock attempt failed, in the developer's language rather than the
/// user's — nobody but the developer ever sees these.
enum DeveloperUnlockFailure {
  malformed,
  badSignature,
  wrongTerminal,
  expired,
  notYetValid,
  badCode,
  spentCode,
}

class DeveloperUnlockResult {
  const DeveloperUnlockResult.success(this.expiresAt, this.scopes)
    : failure = null;
  const DeveloperUnlockResult.failure(this.failure)
    : expiresAt = null,
      scopes = const [];

  final DeveloperUnlockFailure? failure;
  final DateTime? expiresAt;
  final List<String> scopes;

  bool get isSuccess => failure == null;
}

/// Gates the developer-only half of the admin panel.
///
/// The threat this defends against is not a cryptanalyst — it is the venue
/// owner who bought the app, has full access to the machine, and would happily
/// "fix" the backend URL or restore last month's backup over a live database.
/// Client-side enforcement can never be absolute against someone editing Hive
/// files directly; what it does guarantee is that no sequence of taps inside
/// the app reaches a destructive tool, and that anything which does happen is
/// signed for and written to the audit log.
///
/// Unlock state lives in memory only. Closing the app relocks the panel, so a
/// token used during a service call cannot be found still active a week later.
class DeveloperAccess {
  DeveloperAccess._();

  static const _terminalIdKey = 'developerTerminalId';
  static const _clockHighWaterKey = 'developerClockHighWater';

  static final _algorithm = Ed25519();

  /// Swapped out only by the unlock tests, which sign against a throwaway
  /// keypair because the real private key is not in the repository.
  @visibleForTesting
  static String? publicKeyOverride;

  static String get _publicKeyBase64 =>
      publicKeyOverride ?? kDeveloperPublicKeyBase64;

  /// Rebuilds the admin chrome when the panel locks or unlocks.
  static final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  static DateTime? _expiresAt;
  static List<String> _scopes = const [];
  static String? _tokenId;
  static String? _cachedTerminalId;

  /// Stable per-terminal identifier, generated on first read.
  ///
  /// Tokens are bound to it so one venue cannot forward its unlock token to
  /// another. It is a random UUID rather than a hardware serial on purpose: it
  /// carries no information about the machine, and a reinstall getting a fresh
  /// id is the correct behaviour.
  /// Reading is pure — it never writes. A getter that kicked off an
  /// unawaited Hive put left a future dangling behind every widget that
  /// displayed the id, which is enough to wedge a `Hive.close()`. The write is
  /// [persistTerminalId], awaited by the callers that actually open the panel.
  ///
  /// Shaped to be read down a phone line: the venue's own name, then five
  /// random characters — `KAPRISI-7K3QM`. A raw UUID was unique and completely
  /// unusable, because every support call started with somebody spelling out
  /// thirty-six characters of hexadecimal.
  ///
  /// Generated once and then fixed. It does not follow a later rename: tokens
  /// are already signed against it, and an id that moved would invalidate them.
  static String get terminalId {
    final cached = _cachedTerminalId;
    if (cached != null) return cached;

    final existing = DatabaseCore.settingsBox?.get(_terminalIdKey);
    if (existing is String && existing.isNotEmpty) {
      return _cachedTerminalId = existing;
    }
    return _cachedTerminalId = _mintTerminalId();
  }

  /// `<VENUE>-<5 random>`, or just the random half before setup has run.
  static String _mintTerminalId() {
    final random = Random.secure();
    final suffix = List.generate(
      5,
      (_) => _terminalIdAlphabet[random.nextInt(_terminalIdAlphabet.length)],
    ).join();

    final slug = _venueSlug();
    return slug.isEmpty ? suffix : '$slug-$suffix';
  }

  /// The venue name reduced to something typeable: Latin letters and digits,
  /// upper case, capped so a long restaurant name does not undo the point.
  ///
  /// Georgian names transliterate to nothing under this, which is fine — the
  /// random half still identifies the terminal, and a bare code is no worse
  /// than the UUID it replaces.
  static String _venueSlug() {
    final raw = DatabaseCore.settingsBox?.get('venueName');
    if (raw is! String) return '';
    final slug = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').trim();
    return slug.length > 10 ? slug.substring(0, 10) : slug;
  }

  /// Crockford base32 minus the characters people mishear.
  static const _terminalIdAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Writes the terminal id if this machine has not stored one yet.
  ///
  /// Call before showing the id to anyone: a token gets signed against it, so
  /// an id that a restart would change is worse than no id at all.
  static Future<void> persistTerminalId() async {
    final box = DatabaseCore.settingsBox;
    if (box == null) return;
    final existing = box.get(_terminalIdKey);
    if (existing is String && existing.isNotEmpty) return;
    await box.put(_terminalIdKey, terminalId);
  }

  /// Retained as the name the rest of the app already calls. The id is short
  /// by construction now, so there is nothing left to truncate.
  static String get terminalIdShort => terminalId;

  static bool get isUnlocked {
    final expiry = _expiresAt;
    if (expiry == null) return false;
    if (_now().isAfter(expiry)) {
      lock(reason: 'expired');
      return false;
    }
    return true;
  }

  static DateTime? get expiresAt => _expiresAt;

  static List<String> get grantedScopes => List.unmodifiable(_scopes);

  /// Whether the current session may perform [scope].
  static bool can(String scope) => isUnlocked && _scopes.contains(scope);

  /// Verifies a signed token and, if it holds up, opens the panel.
  static Future<DeveloperUnlockResult> unlock(String rawToken) async {
    await _advanceClockHighWater();
    await persistTerminalId();

    final token = rawToken.trim().replaceAll(RegExp(r'\s+'), '');
    final parts = token.split('.');
    if (parts.length != 2) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.malformed,
      );
    }

    final List<int> payloadBytes;
    final List<int> signatureBytes;
    final Map<String, dynamic> payload;
    try {
      payloadBytes = base64Url.decode(_pad(parts[0]));
      signatureBytes = base64Url.decode(_pad(parts[1]));
      final decoded = json.decode(utf8.decode(payloadBytes));
      if (decoded is! Map<String, dynamic>) {
        return const DeveloperUnlockResult.failure(
          DeveloperUnlockFailure.malformed,
        );
      }
      payload = decoded;
    } catch (_) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.malformed,
      );
    }

    // Signature before anything else. Every field below is attacker-supplied
    // until this passes.
    final publicKey = SimplePublicKey(
      base64Url.decode(_publicKeyBase64),
      type: KeyPairType.ed25519,
    );
    final signatureValid = await _algorithm.verify(
      payloadBytes,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
    if (!signatureValid) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.badSignature,
      );
    }

    final boundTerminal = payload['terminal'] as String?;
    if (boundTerminal != '*' && boundTerminal != terminalId) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.wrongTerminal,
      );
    }

    final expiry = DateTime.tryParse(payload['expiresAt'] as String? ?? '');
    final issued = DateTime.tryParse(payload['issuedAt'] as String? ?? '');
    if (expiry == null || issued == null) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.malformed,
      );
    }

    final now = _now();
    if (now.isAfter(expiry)) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.expired,
      );
    }
    // A token dated in the future is a clock that has been wound back far
    // enough to matter, not a legitimate token.
    if (issued.isAfter(now.add(const Duration(hours: 24)))) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.notYetValid,
      );
    }

    final rawScopes = payload['scopes'];
    _scopes = rawScopes is List
        ? rawScopes.whereType<String>().toList(growable: false)
        : DeveloperScope.all;
    _expiresAt = expiry;
    _tokenId = payload['jti'] as String?;
    unlocked.value = true;

    await logAction(
      'unlocked',
      data: {
        'scopes': _scopes,
        'expiresAt': expiry.toIso8601String(),
        'boundTerminal': boundTerminal,
      },
    );

    return DeveloperUnlockResult.success(expiry, _scopes);
  }

  static const _otpTipKey = 'developerOtpTip';

  /// How long a one-time code holds the panel open.
  ///
  /// Shorter than a signed token's window: a code is dictated during a support
  /// call and should not outlive it.
  static const oneTimeCodeSessionLength = Duration(hours: 2);

  /// Opens the panel with a sixteen-character one-time code.
  ///
  /// The code is checked against this terminal's position in the hash chain and
  /// then spent — the terminal moves past it, so the same code never works
  /// twice here. Grants every scope: the code cannot be forged from previous
  /// ones, so there is nothing gained by withholding half the tools and
  /// forcing a second credential mid-call.
  static Future<DeveloperUnlockResult> unlockWithOneTimeCode(
    String rawCode,
  ) async {
    await _advanceClockHighWater();
    await persistTerminalId();

    final candidate = decodeDeveloperCode(
      rawCode,
      byteLength: DeveloperOtpChain.linkBytes,
    );
    if (candidate == null) {
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.badCode,
      );
    }

    final tip = _currentOtpTip();
    final distance = DeveloperOtpChain.distanceToTip(candidate, tip);
    if (distance == null) {
      // Either nonsense, or a code already spent on this terminal — the tip has
      // moved past it and hashing forward no longer arrives.
      return const DeveloperUnlockResult.failure(
        DeveloperUnlockFailure.spentCode,
      );
    }

    await DatabaseCore.settingsBox?.put(
      _otpTipKey,
      DeveloperOtpChain.encodeTip(candidate),
    );

    final expiry = _now().add(oneTimeCodeSessionLength);
    _scopes = DeveloperScope.all;
    _expiresAt = expiry;
    _tokenId = 'otp';
    unlocked.value = true;

    await logAction(
      'unlocked',
      data: {
        'method': 'oneTimeCode',
        'skipped': distance - 1,
        'expiresAt': expiry.toIso8601String(),
      },
    );

    return DeveloperUnlockResult.success(expiry, _scopes);
  }

  /// Where this terminal has got to in the chain — the shipped tip until a
  /// code has been spent here.
  static List<int> _currentOtpTip() {
    final stored = DatabaseCore.settingsBox?.get(_otpTipKey);
    if (stored is String && stored.isNotEmpty) {
      try {
        return DeveloperOtpChain.decodeTip(stored);
      } catch (_) {
        // A corrupted tip should not brick short codes forever; fall back to
        // the shipped one and let the next code re-anchor the chain.
      }
    }
    return DeveloperOtpChain.decodeTip(otpTipOverride ?? kDeveloperOtpTip);
  }

  /// Set by tests so they can drive a chain of their own.
  @visibleForTesting
  static String? otpTipOverride;

  static void lock({String reason = 'manual'}) {
    if (_expiresAt == null) return;
    _expiresAt = null;
    _scopes = const [];
    _tokenId = null;
    unlocked.value = false;
    debugPrint('[DeveloperAccess] locked ($reason)');
  }

  /// Writes a developer action to the same audit trail staff actions use.
  ///
  /// The actor is the token id, not a staff account, so a venue reading its own
  /// audit log can tell "the developer did this during Tuesday's service call"
  /// apart from "our manager did this".
  static Future<void> logAction(
    String action, {
    Map<String, dynamic> data = const {},
  }) async {
    await AuditEventService.logEvent(
      action: 'developer.$action',
      userId: 'developer:${_tokenId ?? 'none'}',
      data: {...data, 'terminal': terminalIdShort},
    );
  }

  /// Wall clock, floored at the highest time this terminal has ever seen.
  ///
  /// Expiry is otherwise trivially defeated by setting the machine's clock back
  /// a week, which on a POS running offline in a restaurant is a thing that
  /// happens by accident as well as on purpose.
  static DateTime _now() {
    final wall = DateTime.now().toUtc();
    final stored = DatabaseCore.settingsBox?.get(_clockHighWaterKey);
    final highWater = stored is String ? DateTime.tryParse(stored) : null;

    if (highWater == null || wall.isAfter(highWater)) return wall;
    return highWater;
  }

  /// Advances the stored high-water mark. Separate from [_now] so the read
  /// path stays free of writes; called from the awaited unlock flow.
  static Future<void> _advanceClockHighWater() async {
    final box = DatabaseCore.settingsBox;
    if (box == null) return;
    final wall = DateTime.now().toUtc();
    final stored = box.get(_clockHighWaterKey);
    final highWater = stored is String ? DateTime.tryParse(stored) : null;
    if (highWater == null || wall.isAfter(highWater)) {
      await box.put(_clockHighWaterKey, wall.toIso8601String());
    }
  }

  static String _pad(String value) {
    final remainder = value.length % 4;
    return remainder == 0 ? value : value + '=' * (4 - remainder);
  }

  @visibleForTesting
  static void resetForTest() {
    _expiresAt = null;
    _scopes = const [];
    _tokenId = null;
    _cachedTerminalId = null;
    unlocked.value = false;
  }

  @visibleForTesting
  static DateTime effectiveNowForTest() => _now();
}
