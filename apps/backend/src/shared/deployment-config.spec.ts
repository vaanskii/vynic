import {
  localDockerHost,
  validateDeploymentEnvironment,
  websiteCookieSecure,
} from './deployment-config';
import { dockerTarget } from '../website/custom/custom-website-runtime';

describe('deployment security configuration', () => {
  const original = process.env;
  afterEach(() => {
    process.env = original;
  });
  const valid = () => ({
    NODE_ENV: 'production',
    DATABASE_URL: 'postgresql://vynic:secret@postgres:5432/vynic_local_prod',
    JWT_SECRET: 'a'.repeat(64),
    JWT_REFRESH_SECRET: 'b'.repeat(64),
    COOKIE_ENCRYPTION_KEY: 'c'.repeat(64),
    WEBSITE_MEDIA_DIR: '/var/lib/vynic/media',
  });
  it('fails boot for absent/weak production secrets and malformed payment keys', () => {
    for (const key of [
      'JWT_SECRET',
      'JWT_REFRESH_SECRET',
      'COOKIE_ENCRYPTION_KEY',
      'WEBSITE_MEDIA_DIR',
    ]) {
      expect(() =>
        validateDeploymentEnvironment({ ...valid(), [key]: '' }),
      ).toThrow(key);
    }
    expect(() =>
      validateDeploymentEnvironment({ ...valid(), JWT_SECRET: 'change-me' }),
    ).toThrow('JWT_SECRET');
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        PAYMENT_INTEGRATION_MASTER_KEY: 'invalid',
      }),
    ).toThrow('64 hexadecimal');
    expect(() => validateDeploymentEnvironment(valid())).not.toThrow(); // No payment integration is required.
  });
  it('refuses local HTTP mode pointed at another DB or a public domain', () => {
    const env = {
      ...valid(),
      VYNIC_LOCAL_DOCKER: 'true',
      SAAS_WEBSITE_BASE_DOMAIN: 'vynic.localhost',
      FRONTEND_URL: 'http://vynic.localhost',
    };
    expect(() => validateDeploymentEnvironment(env)).not.toThrow();
    expect(() =>
      validateDeploymentEnvironment({
        ...env,
        DATABASE_URL: 'postgresql://user:secret@localhost/vankisi_database',
      }),
    ).toThrow('isolated');
    expect(() =>
      validateDeploymentEnvironment({
        ...env,
        SAAS_WEBSITE_BASE_DOMAIN: 'vynic.ge',
      }),
    ).toThrow('isolated');
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        FRONTEND_URL: 'http://vynic.ge',
      }),
    ).toThrow('HTTPS');
  });
  it('limits insecure cookies and the fixed proxy target to explicit local Docker hosts', () => {
    process.env = { ...valid(), VYNIC_LOCAL_DOCKER: 'true' };
    expect(websiteCookieSecure('tabla.vynic.localhost')).toBe(false);
    expect(dockerTarget('vankisi.vynic.localhost').url).toBe(
      'http://vankisi.vynic.localhost/',
    );
    for (const host of [
      'vynic.ge',
      'attacker.localhost',
      'vankisi.vynic.localhost.evil.test',
      '127.0.0.1',
      'a.b.vynic.localhost',
    ]) {
      expect(localDockerHost(host)).toBe(false);
      expect(websiteCookieSecure(host)).toBe(true);
      expect(() => dockerTarget(host)).toThrow();
    }
    delete process.env.VYNIC_LOCAL_DOCKER;
    expect(websiteCookieSecure('tabla.vynic.localhost')).toBe(true);
    expect(() => dockerTarget('vankisi.vynic.localhost')).toThrow();
  });
  it('rejects broad client-IP trust and wildcard CORS', () => {
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        ALLOWED_ORIGINS: 'http://vynic.ge',
      }),
    ).toThrow('HTTPS');
    expect(() =>
      validateDeploymentEnvironment({ ...valid(), TRUST_PROXY_IPS: 'true' }),
    ).toThrow('exact proxy');
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        TRUST_PROXY_IPS: '0.0.0.0/0',
      }),
    ).toThrow('exact proxy');
    expect(() =>
      validateDeploymentEnvironment({ ...valid(), ALLOWED_ORIGINS: '*' }),
    ).toThrow('wildcard');
  });
  it('requires a strong gateway secret without global forwarded-host trust', () => {
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        VYNIC_WEB_PROXY_SECRET: 'short',
      }),
    ).toThrow('VYNIC_WEB_PROXY_SECRET');
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        VYNIC_WEB_PROXY_SECRET: 'd'.repeat(64),
        TRUST_PROXY_HOST: 'true',
      }),
    ).toThrow('TRUST_PROXY_HOST');
    expect(() =>
      validateDeploymentEnvironment({
        ...valid(),
        VYNIC_WEB_PROXY_SECRET: 'd'.repeat(64),
        TRUST_PROXY_HOST: 'false',
      }),
    ).not.toThrow();
  });
});
