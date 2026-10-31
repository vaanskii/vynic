import { timingSafeEqual } from 'node:crypto';
import { performance } from 'node:perf_hooks';

export const MAX_PROXY_OVERLAP_MS = 30 * 60 * 1000;
export interface ProxyRotation {
  previousSecret?: string;
  startsAt?: string;
  expiresAt?: string;
}

export function proxyRotationFromEnv(env: NodeJS.ProcessEnv): ProxyRotation {
  return {
    previousSecret: env.VYNIC_WEB_PROXY_PREVIOUS_SECRET,
    startsAt: env.VYNIC_WEB_PROXY_ROTATION_START,
    expiresAt: env.VYNIC_WEB_PROXY_ROTATION_END,
  };
}

export function validateProxyRotation(
  current: string | undefined,
  rotation: ProxyRotation,
): void {
  const { previousSecret, startsAt, expiresAt } = rotation;
  if ([previousSecret, startsAt, expiresAt].every((v) => v === undefined))
    return;
  const validSecret = (v: string | undefined) =>
    !!v && v.trim().length >= 32 && !/change-me|replace-me/i.test(v);
  if (
    !validSecret(current) ||
    !validSecret(previousSecret) ||
    previousSecret === current
  )
    throw new Error(
      'Proxy rotation requires distinct strong current and previous secrets',
    );
  const iso = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
  const start = Date.parse(startsAt ?? '');
  const end = Date.parse(expiresAt ?? '');
  if (
    !iso.test(startsAt ?? '') ||
    !iso.test(expiresAt ?? '') ||
    !Number.isFinite(start) ||
    !Number.isFinite(end) ||
    new Date(start).toISOString() !== startsAt ||
    new Date(end).toISOString() !== expiresAt ||
    end <= start ||
    end - start > MAX_PROXY_OVERLAP_MS
  )
    throw new Error(
      'Proxy rotation requires exact UTC timestamps and an overlap of at most 30 minutes',
    );
}

/** Absolute timestamps survive restarts; monotonic elapsed time prevents a local
 * clock rollback from extending an already running process's overlap. Expiry is
 * latched: an expired previous key cannot become valid again in this process. */
export function proxyCredentialVerifier(
  current: string,
  rotation: ProxyRotation = {},
  clock = { wall: () => Date.now(), monotonic: () => performance.now() },
): (value: string | string[] | undefined) => boolean {
  validateProxyRotation(current, rotation);
  const expected = Buffer.from(current);
  const previous = rotation.previousSecret
    ? Buffer.from(rotation.previousSecret)
    : undefined;
  const start = Date.parse(rotation.startsAt ?? '');
  const end = Date.parse(rotation.expiresAt ?? '');
  const wallAnchor = clock.wall();
  const monotonicAnchor = clock.monotonic();
  let expired = !previous || wallAnchor >= end;
  const matches = (actual: Buffer, trusted: Buffer) =>
    actual.length === trusted.length && timingSafeEqual(actual, trusted);
  return (value) => {
    if (typeof value !== 'string') return false;
    const actual = Buffer.from(value);
    if (matches(actual, expected)) return true;
    if (!previous || expired) return false;
    const wall = clock.wall();
    const elapsed = clock.monotonic() - monotonicAnchor;
    if (
      !Number.isFinite(wall) ||
      !Number.isFinite(elapsed) ||
      elapsed < 0 ||
      wall >= end ||
      wallAnchor + elapsed >= end
    ) {
      expired = true;
      return false;
    }
    return wall >= start && matches(actual, previous);
  };
}
