/**
 * Pure conflict-resolution helpers for POS ↔ server sync.
 *
 * Kept free of NestJS/Prisma so the last-write-wins rule is unit-testable in
 * isolation (see sync-conflict.spec.ts). The SyncController wires these into
 * the `/sync/manager-data` order loop.
 */

/** Parse an ISO date string defensively; returns null for missing/invalid input. */
export function parseDate(value: unknown): Date | null {
  if (typeof value !== 'string' || value.trim().length === 0) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * Same-order conflict resolution between a POS snapshot and a queued mobile
 * change. The POS is the source of truth, so it wins only when it provides a
 * valid edit timestamp that is strictly newer than the queued mobile edit.
 *
 * In every other case — POS sent no/invalid timestamp, no queued mobile edit,
 * or the mobile edit is newer-or-equal — the queued mobile change is
 * authoritative (the original, backwards-compatible "hold" behavior).
 */
export function posWinsOrderConflict(
  posUpdatedAtRaw: unknown,
  managerEditedAt: Date | undefined | null,
): boolean {
  const posEditedAt = parseDate(posUpdatedAtRaw);
  if (posEditedAt === null || managerEditedAt == null) return false;
  return posEditedAt.getTime() > managerEditedAt.getTime();
}

/**
 * Usernames that have an in-flight queued mobile change which implies the user
 * should EXIST on the POS (create / rename / pin / role updates). The staff
 * reconcile must not delete these from the server just because the POS's
 * current snapshot predates the queued change — otherwise a manager-created
 * user is wrongly removed until the POS applies the queued create and re-pushes.
 *
 * Deletions are intentionally excluded: a queued delete means the user should
 * go away, so it must not be protected from removal.
 */
export function pendingStaffUsernames(
  rows: Array<{ endpoint: string; payload: unknown }>,
): Set<string> {
  const names = new Set<string>();
  for (const row of rows) {
    if (!row.endpoint.startsWith('/mobile-user-')) continue;
    if (row.endpoint === '/mobile-user-delete') continue;
    const payload = (row.payload ?? {}) as Record<string, unknown>;
    // For rename, the *new* username is the one that should survive.
    for (const key of ['username', 'newUsername']) {
      const value = payload[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        names.add(value.trim());
      }
    }
  }
  return names;
}
