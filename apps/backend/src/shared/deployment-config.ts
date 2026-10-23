import { isIP } from 'node:net';
import { normalizeHostname } from '../website/tenancy/website-host';

/** Explicit, isolated Compose HTTP mode. Never inferred from NODE_ENV or input. */
export function localDockerHost(host: string | undefined): boolean {
  const hostname = normalizeHostname(host);
  return (
    process.env.VYNIC_LOCAL_DOCKER === 'true' &&
    !!hostname &&
    /^(?:[a-z0-9-]+\.)?vynic\.localhost$/.test(hostname)
  );
}

export function websiteCookieSecure(host: string | undefined): boolean {
  return process.env.NODE_ENV === 'production' && !localDockerHost(host);
}

/** Validate before Nest creates services or connects to any database. */
export function validateDeploymentEnvironment(
  env: NodeJS.ProcessEnv = process.env,
): void {
  if (env.NODE_ENV !== 'production') return;
  for (const key of [
    'DATABASE_URL',
    'JWT_SECRET',
    'JWT_REFRESH_SECRET',
    'COOKIE_ENCRYPTION_KEY',
    'WEBSITE_MEDIA_DIR',
  ]) {
    if (!env[key]?.trim())
      throw new Error(`Missing required production configuration: ${key}`);
  }
  for (const key of [
    'JWT_SECRET',
    'JWT_REFRESH_SECRET',
    'COOKIE_ENCRYPTION_KEY',
    'PLATFORM_JWT_SECRET',
    'VYNIC_WEB_PROXY_SECRET',
  ]) {
    if (
      env[key] !== undefined &&
      (env[key]!.trim().length < 32 || /change-me|replace-me/i.test(env[key]!))
    )
      throw new Error(
        `${key} must contain at least 32 characters of generated secret material`,
      );
  }
  if (
    env.PAYMENT_INTEGRATION_MASTER_KEY &&
    !/^[a-fA-F0-9]{64}$/.test(env.PAYMENT_INTEGRATION_MASTER_KEY)
  )
    throw new Error(
      'PAYMENT_INTEGRATION_MASTER_KEY must be 64 hexadecimal characters',
    );
  if (env.ALLOWED_ORIGINS?.includes('*'))
    throw new Error('ALLOWED_ORIGINS cannot contain a wildcard');
  if (env.TRUST_PROXY_IPS?.split(',').some((ip) => !isIP(ip.trim())))
    throw new Error('TRUST_PROXY_IPS must contain exact proxy IP addresses');
  if (
    env.VYNIC_WEB_PROXY_SECRET &&
    ['1', 'true'].includes((env.TRUST_PROXY_HOST ?? '').trim().toLowerCase())
  )
    throw new Error('VYNIC_WEB_PROXY_SECRET requires TRUST_PROXY_HOST to remain disabled');
  if (env.VYNIC_LOCAL_DOCKER === 'true') {
    const db = new URL(env.DATABASE_URL!);
    if (
      db.hostname !== 'postgres' ||
      db.pathname !== '/vynic_local_prod' ||
      env.SAAS_WEBSITE_BASE_DOMAIN !== 'vynic.localhost' ||
      env.FRONTEND_URL !== 'http://vynic.localhost'
    )
      throw new Error(
        'VYNIC_LOCAL_DOCKER requires the isolated postgres/vynic_local_prod database and http://vynic.localhost',
      );
  } else {
    for (const origin of (env.ALLOWED_ORIGINS ?? '')
      .split(',')
      .filter(Boolean)) {
      const parsed = new URL(origin.trim());
      if (parsed.protocol !== 'https:' || parsed.origin !== origin.trim())
        throw new Error(
          'ALLOWED_ORIGINS must contain exact HTTPS origins in production',
        );
    }
    for (const key of [
      'FRONTEND_URL',
      'API_URL',
      'SAAS_WEBSITE_PREVIEW_ORIGIN',
      'DEVICE_API_BASE_URL',
    ]) {
      if (env[key] && new URL(env[key]!).protocol !== 'https:')
        throw new Error(`${key} must use HTTPS in production`);
    }
  }
}
