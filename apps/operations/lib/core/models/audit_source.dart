/// Which mechanism caused an audited business action.
///
/// Distinct from the actor. The actor is the person the action is attributed
/// to; the source is the channel or process that carried it out. A crash
/// recovery completes a closure the operator started, so its actor is that
/// operator and its source is [systemRecovery].
enum AuditSource {
  /// A person working at the POS terminal itself.
  pos,

  /// A Manager app request, whichever transport (Edge pull queue or the legacy
  /// LAN adapter) delivered it to the POS.
  manager,

  /// A Cloud-originated command with no Manager identity of its own.
  edge,

  /// The public venue website, relayed through Cloud.
  website,

  /// An automatic POS process such as Close Day or reservation activation.
  system,

  /// Startup recovery completing a closure that a crash interrupted.
  systemRecovery,

  /// A developer service action.
  developer;

  /// The stable string written to `AuditEvent.details['source']`.
  String get wireValue {
    switch (this) {
      case AuditSource.pos:
        return 'POS';
      case AuditSource.manager:
        return 'MANAGER';
      case AuditSource.edge:
        return 'EDGE';
      case AuditSource.website:
        return 'WEBSITE';
      case AuditSource.system:
        return 'SYSTEM';
      case AuditSource.systemRecovery:
        return 'SYSTEM_RECOVERY';
      case AuditSource.developer:
        return 'DEVELOPER';
    }
  }

  /// The `details` key that carries [wireValue].
  static const String detailsKey = 'source';

  static AuditSource? fromWire(Object? raw) {
    final normalized = raw?.toString().trim().toUpperCase();
    for (final value in AuditSource.values) {
      if (value.wireValue == normalized) return value;
    }
    return null;
  }
}
