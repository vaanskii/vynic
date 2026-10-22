/** Missing subscriptions are allowed only for migration-marked legacy Venues. */
export function commercialAccessAllowed(
  status?: string | null,
  trialEndsAt?: Date | null,
  legacyCommercialAccess = false,
  now = new Date(),
): boolean {
  if (status == null) return legacyCommercialAccess;
  if (status === 'TRIAL') return !!trialEndsAt && trialEndsAt > now;
  return status === 'ACTIVE' || status === 'PAST_DUE';
}
