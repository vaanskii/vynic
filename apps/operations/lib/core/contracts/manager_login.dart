// Generated from packages/contracts/schema/manager-login.contract.json. Do not edit.
abstract final class ManagerLoginContract {
  static const version = 1;
  static const path = r'/auth/mobile-login';
  static const venueCodeField = r'venueCode';
  static const pinField = r'pin';
  static const rolloutVenueCode = r'vankisi';
  static const legacyMaximumDeadline = r'2026-12-01T00:00:00Z';
  static const venueCodePattern = r'^[a-z0-9][a-z0-9-]{2,31}$';
}
