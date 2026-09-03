/**
 * The capability keys seeded by the Step 5A migration.
 *
 * Features are database rows, not an enum, so a later capability
 * (RESERVATIONS, ADVANCED_REPORTS, INTEGRATIONS, …) is a seed insert rather
 * than a schema migration. These constants exist only so the three that ship
 * today can be referenced without stringly-typed call sites; resolution itself
 * works on plain keys and never enumerates them.
 */
export const FeatureKeys = {
  /** The point-of-sale product itself. */
  POS: 'POS',
  /** The Venue has a restaurant website product. Its implementation is configured separately. */
  WEBSITE: 'WEBSITE',
  /** The Venue has the mobile Manager product. Never gates POS → Cloud sync. */
  MANAGER_APP: 'MANAGER_APP',
} as const;

export type KnownFeatureKey = (typeof FeatureKeys)[keyof typeof FeatureKeys];
