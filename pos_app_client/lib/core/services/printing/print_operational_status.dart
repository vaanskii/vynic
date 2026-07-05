/// Operational status of a print job (kitchen check or receipt).
///
/// **Unused scaffolding.** `printer_service.dart` currently has no observable
/// status — print calls report success/failure only via one-shot bool
/// callbacks and try/catch, with nothing persisted or exposed for the UI to
/// read. This enum exists so `docs/UI_PLAN.md`'s "Printed" / "Sent to
/// kitchen" / "Kitchen failed" / "Printer failed" states have a named target
/// to consume once printing gains real status tracking. Wiring it into
/// `printer_service.dart`'s actual print flow is out of scope for the
/// Phase 4 status-enum foundation — that would be new instrumentation
/// behavior, not a replacement of existing ad-hoc status usage.
enum PrintOperationalStatus { idle, sending, sent, failed }
