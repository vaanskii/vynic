import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/audit_report.dart';

/// Which revision of each audit report the backend has acknowledged.
///
/// The POS used to push every audit report it had on every change, because it
/// had no way to tell a report the server already holds from one it does not.
/// This box is that missing answer, and it is deliberately *beside* the audit
/// data rather than inside it: an audit report is the restaurant's record of
/// what happened, and cloud bookkeeping has no business being a field on it.
///
/// ## Why a content revision and not a timestamp
///
/// A wall-clock cursor ("send everything changed since T") loses records the
/// moment a clock moves backwards, a report is edited in the same second the
/// cursor was written, or a restored backup carries old timestamps. The
/// revision here is a hash of the report's own serialized content, so it
/// answers the only question that matters — *is what I hold different from what
/// the server acknowledged* — without consulting a clock at all.
///
/// It also works for the reports [AuditRepository] derives from legacy event
/// logs rather than storing, which have nowhere to keep a counter.
///
/// ## The acknowledgment rule
///
/// A revision becomes clean only when the backend says it persisted *that*
/// revision. The revision recorded is the one that was sent, never the report's
/// current content, so a report edited to N+1 while N was in flight stays dirty
/// and is sent again. Marking it clean would be the one bug this whole
/// mechanism exists to prevent.
///
/// ## Durability
///
/// Every batch's acknowledgments are written before the next batch is sent, so
/// an interrupted backfill resumes where it stopped rather than starting over.
/// The box is not part of a backup: a restored install has no acknowledgments,
/// so it re-uploads what it holds, which is the safe direction. Nothing here is
/// audit authority — deleting the whole box costs one re-upload, not one
/// record.
class AuditSyncState {
  AuditSyncState._();

  static const String boxName = 'audit_sync_state';

  static Box<Map>? _box;

  static bool get isOpen => _box != null;

  /// Opens the box. Safe to call repeatedly; safe to fail.
  ///
  /// A POS that cannot open this box must still sync, so a failure here
  /// degrades to "nothing is acknowledged" — every report looks dirty and is
  /// sent — rather than stopping audit sync altogether.
  static Future<void> open() async {
    if (_box != null) return;
    try {
      _box = await Hive.openBox<Map>(boxName);
    } catch (error) {
      debugPrint('[AuditSync] Could not open $boxName: $error');
    }
  }

  static Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  @visibleForTesting
  static Future<void> clearForTest() async {
    await _box?.clear();
  }

  /// The revision the backend last acknowledged for [reportId], if any.
  static String? acknowledgedRevision(String reportId) {
    final raw = _box?.get(reportId);
    if (raw == null) return null;
    final revision = raw['revision'];
    return revision is String && revision.isNotEmpty ? revision : null;
  }

  /// Records that the backend persisted [revision] of [reportId].
  ///
  /// [revision] must be the revision that was *sent*. Recomputing it from the
  /// report at this point would silently mark a newer local edit as synced.
  static Future<void> markAcknowledged(String reportId, String revision) async {
    final box = _box;
    if (box == null) return;
    await box.put(reportId, <String, dynamic>{
      'revision': revision,
      'ackedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Forgets acknowledgments for reports the POS no longer has.
  ///
  /// Bookkeeping only: it keeps the box proportional to the audit history
  /// rather than to everything that ever existed. Nothing is deleted from the
  /// audit log itself.
  static Future<void> pruneUnknown(Set<String> knownReportIds) async {
    final box = _box;
    if (box == null) return;
    final stale = box.keys
        .where((key) => key is String && !knownReportIds.contains(key))
        .toList();
    if (stale.isEmpty) return;
    await box.deleteAll(stale);
  }

  /// Which of [reports] the backend has not acknowledged at their current
  /// content, and every report id the POS holds.
  ///
  /// This is the whole selection rule in one place, so the property that matters
  /// — an acknowledged history plus one change sends one report — is something
  /// a test can state directly rather than infer from a network log.
  static AuditSyncSelection selectDirty(Iterable<AuditReport> reports) {
    final knownReportIds = <String>{};
    final dirty = <DirtyAuditReport>[];
    for (final report in reports) {
      final reportId = report.reportId.trim();
      if (reportId.isEmpty) continue;
      // A repeated id would be sent as two conflicting versions of one report
      // in the same batch, and only one of them could ever be acknowledged —
      // so the other would come back dirty on every sync forever. The producer
      // already collapses duplicates; this makes the invariant local.
      if (!knownReportIds.add(reportId)) continue;
      final revision = revisionOf(report);
      final acknowledged = acknowledgedRevision(reportId);
      if (acknowledged != revision) {
        dirty.add(
          DirtyAuditReport(
            report: report,
            revision: revision,
            isNew: acknowledged == null,
          ),
        );
      }
    }
    return AuditSyncSelection(dirty: dirty, knownReportIds: knownReportIds);
  }

  /// A stable content revision for [report].
  ///
  /// Hashes the same map that is sent over the wire, canonicalized so that map
  /// iteration order can never make an unchanged report look dirty.
  static String revisionOf(AuditReport report) {
    return sha256
        .convert(utf8.encode(_canonicalJson(report.toMap())))
        .toString();
  }

  static String _canonicalJson(Object? value) {
    final buffer = StringBuffer();
    _writeCanonical(buffer, value);
    return buffer.toString();
  }

  static void _writeCanonical(StringBuffer out, Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(json.encode(keys[i]));
        out.write(':');
        _writeCanonical(out, value[keys[i]]);
      }
      out.write('}');
      return;
    }
    if (value is List) {
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        _writeCanonical(out, value[i]);
      }
      out.write(']');
      return;
    }
    out.write(json.encode(value));
  }
}

/// One report the POS intends to send, with the revision it is sending.
@immutable
class DirtyAuditReport {
  const DirtyAuditReport({
    required this.report,
    required this.revision,
    this.isNew = true,
  });

  final AuditReport report;
  final String revision;

  /// True when the backend has never acknowledged this report at all, false
  /// when it acknowledged an earlier revision. Diagnostics only: the same ids
  /// arriving as `changed` on pass after pass is the signature of a report
  /// whose content is not settling, which is a producer bug rather than a
  /// restaurant that keeps editing it.
  final bool isNew;

  String get reportId => report.reportId;

  /// The wire shape: the report's own map plus the revision the backend must
  /// acknowledge. Additive — an older backend ignores the extra field.
  Map<String, dynamic> toPayload() => <String, dynamic>{
    ...report.toMap(),
    'revision': revision,
  };
}

/// What one pass of [AuditSyncState.selectDirty] found.
@immutable
class AuditSyncSelection {
  const AuditSyncSelection({required this.dirty, required this.knownReportIds});

  /// Reports to send, each carrying the revision to be acknowledged.
  final List<DirtyAuditReport> dirty;

  /// Every report id the POS holds, for reconciliation.
  final Set<String> knownReportIds;
}
