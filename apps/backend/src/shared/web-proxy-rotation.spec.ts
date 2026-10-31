import express from 'express';
import request from 'supertest';
import { webProxyIngress } from './web-proxy';
import {
  MAX_PROXY_OVERLAP_MS,
  proxyCredentialVerifier,
  proxyRotationFromEnv,
  validateProxyRotation,
} from './web-proxy-rotation';
import { validateDeploymentEnvironment } from './deployment-config';

const current = 'synthetic-new-proxy-key-for-tests-only';
const previous = 'synthetic-old-proxy-key-for-tests-only';
const start = Date.parse('2026-10-31T12:00:00.000Z');
const rotation = {
  previousSecret: previous,
  startsAt: new Date(start).toISOString(),
  expiresAt: new Date(start + MAX_PROXY_OVERLAP_MS).toISOString(),
};

describe('bounded web proxy credential transition', () => {
  it('preserves ordinary single-key behavior and rejects missing/array credentials', () => {
    const verify = proxyCredentialVerifier(current);
    expect(verify(current)).toBe(true);
    for (const value of [previous, '', undefined, [current]])
      expect(verify(value)).toBe(false);
  });
  it('admits previous only inside the fixed absolute interval, never extends on restart', () => {
    let wall = start - 1;
    let mono = 0;
    const clock = { wall: () => wall, monotonic: () => mono };
    const verify = proxyCredentialVerifier(current, rotation, clock);
    expect(verify(previous)).toBe(false);
    wall = start;
    mono = 1;
    expect(verify(previous)).toBe(true);
    wall = start + MAX_PROXY_OVERLAP_MS - 1;
    mono = MAX_PROXY_OVERLAP_MS;
    expect(proxyCredentialVerifier(current, rotation, clock)(previous)).toBe(
      true,
    );
    wall++;
    expect(verify(previous)).toBe(false);
    expect(proxyCredentialVerifier(current, rotation, clock)(previous)).toBe(
      false,
    );
    expect(verify(current)).toBe(true);
    wall = start;
    mono = 1;
    expect(verify(previous)).toBe(false); // Expiry cannot be undone within the process.
  });
  it('fails closed for previous on monotonic exhaustion even if wall time rolls back', () => {
    let wall = start;
    let mono = 100;
    const verify = proxyCredentialVerifier(current, rotation, {
      wall: () => wall,
      monotonic: () => mono,
    });
    expect(verify(previous)).toBe(true);
    wall += 1000;
    mono += MAX_PROXY_OVERLAP_MS;
    expect(verify(previous)).toBe(false);
    expect(verify(current)).toBe(true);
  });
  it('rejects invalid clocks for previous without disabling the current key', () => {
    let mono = 10;
    const verify = proxyCredentialVerifier(current, rotation, {
      wall: () => start,
      monotonic: () => mono,
    });
    mono = 9;
    expect(verify(previous)).toBe(false);
    expect(verify(current)).toBe(true);
  });
  it.each([
    {},
    { previousSecret: previous },
    { ...rotation, previousSecret: current },
    { ...rotation, previousSecret: 'short' },
    { ...rotation, startsAt: '2026-10-31' },
    { ...rotation, startsAt: '2026-02-30T00:00:00.000Z' },
    { ...rotation, expiresAt: rotation.startsAt },
    {
      ...rotation,
      expiresAt: new Date(start + MAX_PROXY_OVERLAP_MS + 1).toISOString(),
    },
  ])(
    'fails boot on incomplete or unsafe transition configuration %#',
    (invalid) => {
      const candidate = Object.keys(invalid).length
        ? invalid
        : { expiresAt: rotation.expiresAt };
      expect(() => validateProxyRotation(current, candidate)).toThrow();
    },
  );
  it('rejects transition without primary configuration before app startup', () => {
    const env = {
      NODE_ENV: 'test',
      VYNIC_WEB_PROXY_PREVIOUS_SECRET: previous,
      VYNIC_WEB_PROXY_ROTATION_START: rotation.startsAt,
      VYNIC_WEB_PROXY_ROTATION_END: rotation.expiresAt,
    };
    expect(proxyRotationFromEnv(env)).toEqual(rotation);
    expect(() => validateDeploymentEnvironment(env)).toThrow();
    expect(() =>
      validateDeploymentEnvironment({
        ...env,
        VYNIC_WEB_PROXY_SECRET: current,
      }),
    ).not.toThrow();
  });
  it('keeps metadata authentication/stripping intact through rolling frontend deployment', async () => {
    const now = Date.now();
    const app = express();
    app.use(
      webProxyIngress(current, {
        previousSecret: previous,
        startsAt: new Date(now - 1000).toISOString(),
        expiresAt: new Date(now + 60_000).toISOString(),
      }),
    );
    app.get('/api/probe', (req, res) =>
      res.json({
        host: req.headers.host,
        ip: req.ip,
        leaked: req.headers['x-vynic-web-proxy-secret'] ?? null,
      }),
    );
    for (const credential of [current, previous]) {
      const result = await request(app).get('/api/probe').set({
        'x-vynic-web-proxy-secret': credential,
        'x-vynic-web-proxy-host': 'tenant.example.invalid',
        'x-vynic-web-proxy-proto': 'https',
        'x-vynic-web-proxy-ip': '203.0.113.2',
        'x-forwarded-host': 'forged.example.invalid',
      });
      expect(result.status).toBe(200);
      expect(result.body).toEqual({
        host: 'tenant.example.invalid',
        ip: '203.0.113.2',
        leaked: null,
      });
    }
    expect(
      (
        await request(app)
          .get('/api/probe')
          .set('x-vynic-web-proxy-secret', previous)
      ).status,
    ).toBe(400);
    expect(
      (
        await request(app)
          .get('/api/probe')
          .set('x-vynic-web-proxy-secret', 'wrong')
      ).status,
    ).toBe(403);
  });
});
