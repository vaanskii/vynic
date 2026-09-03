/**
 * Read a required environment variable, throwing on boot if it is missing.
 *
 * Used for security-critical secrets (JWT signing key, cookie encryption key)
 * so the server fails closed instead of silently falling back to a public
 * default value.
 */
export function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(
      `Missing required environment variable ${name}. ` +
        `Set it before starting the server (see scripts/check-env.mjs).`,
    );
  }
  return value;
}
