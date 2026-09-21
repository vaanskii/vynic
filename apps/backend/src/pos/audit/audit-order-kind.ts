import { normalizeAuditEventType } from './audit-event-type';

/** What kind of Order a report describes. */
export type CanonicalOrderKind =
  | 'WALK_IN'
  | 'TAKEAWAY'
  | 'PACKAGE'
  | 'RESERVATION';

const CANONICAL: readonly CanonicalOrderKind[] = [
  'WALK_IN',
  'TAKEAWAY',
  'PACKAGE',
  'RESERVATION',
];

/** The shape this derivation needs; the full sync event has more. */
interface OrderKindEventSource {
  type?: string;
  previousQty?: number;
  newQty?: number;
  details?: unknown;
  sequence?: number;
}

function declaredKind(details: unknown): CanonicalOrderKind | null {
  if (details === null || typeof details !== 'object') return null;
  const raw = (details as Record<string, unknown>).orderKind;
  if (typeof raw !== 'string') return null;
  const upper = raw.trim().toUpperCase();
  return (CANONICAL as readonly string[]).includes(upper)
    ? (upper as CanonicalOrderKind)
    : null;
}

/**
 * The Order kind a report's own creation event states, or null.
 *
 * Query metadata, never a substitute for the events: it exists so "every
 * Takeaway cancelled this week" is an indexed column rather than a join, a
 * sort and a JSON path. It is a pure function of the events being written, so
 * re-ingesting the same report always produces the same answer.
 *
 * Null is a real answer. A report opened before creation events existed has
 * nothing that says what kind of Order it was, and `floor` is not evidence —
 * it is a display string that a floor plan edit can change under history.
 * Guessing there would put an unprovable value in a column meant for filtering.
 */
export function deriveOrderKind(
  events: readonly OrderKindEventSource[],
): CanonicalOrderKind | null {
  if (events.length === 0) return null;

  // The creation event is the one that says what was opened. Take the earliest
  // by the POS's own ordering when it sends one, so a report whose events
  // arrive in some other order still resolves to the same kind.
  const ordered = events
    .map((event, index) => ({ event, index }))
    .sort((a, b) => {
      const left = Number.isInteger(a.event.sequence)
        ? (a.event.sequence as number)
        : a.index;
      const right = Number.isInteger(b.event.sequence)
        ? (b.event.sequence as number)
        : b.index;
      return left - right || a.index - b.index;
    })
    .map((entry) => entry.event);

  for (const event of ordered) {
    const type = normalizeAuditEventType(
      event.type,
      event.previousQty,
      event.newQty,
    );
    switch (type) {
      case 'CREATE_WALKIN':
        // A Package is carried by a Walk-In creation that says so.
        return declaredKind(event.details) ?? 'WALK_IN';
      case 'CREATE_TAKEAWAY':
        return declaredKind(event.details) ?? 'TAKEAWAY';
      case 'ACTIVATE_RESERVATION':
        return declaredKind(event.details) ?? 'RESERVATION';
      default:
        break;
    }
  }

  // No creation event, but the package was applied to this Order — which only
  // happens on a Package carrier.
  const applied = ordered.some(
    (event) =>
      normalizeAuditEventType(event.type, event.previousQty, event.newQty) ===
      'APPLY_PACKAGE',
  );
  return applied ? 'PACKAGE' : null;
}
