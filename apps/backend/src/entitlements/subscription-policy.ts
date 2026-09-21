/** Manual grace: dates are informational; only explicit status transitions revoke access. */
export function commercialAccessAllowed(status?: string | null): boolean {
  return status == null || ['TRIAL', 'ACTIVE', 'PAST_DUE'].includes(status);
}
