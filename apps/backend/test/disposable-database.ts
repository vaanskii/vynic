/**
 * A fresh, per-run integration database: a loopback server and a name that
 * declares itself throwaway (`disposable_…`), so a suite can run on its own
 * newly created database instead of a long-lived named one. A developer or
 * restaurant database never matches.
 */
export function isFreshDisposableDatabase(url: string | URL) {
  const u = typeof url === 'string' ? new URL(url) : url;
  return (
    u.hostname === '127.0.0.1' &&
    /^\/disposable_[a-z0-9_]+$/.test(u.pathname) &&
    !u.pathname.includes('vankisi')
  );
}
