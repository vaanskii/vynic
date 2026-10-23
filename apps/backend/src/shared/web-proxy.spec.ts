import type { Server } from 'node:http';
import { randomUUID } from 'node:crypto';
import { ConfigService } from '@nestjs/config';
import express, { type Request } from 'express';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import { WebsiteTenantService } from '../website/tenancy/website-tenant.service';
import { isSameOriginRequest } from '../website/tenancy/same-origin';
import { WebsiteAuthController } from '../website/auth/auth.controller';
import { CsrfService } from '../website/common/csrf.service';
import { WEB_PROXY_SECRET_HEADER, webProxyIngress } from './web-proxy';
import { PrismaService } from '../prisma.service';
import { isFreshDisposableDatabase } from '../../test/disposable-database';

const secret = 'synthetic-web-proxy-key-for-local-tests-only'.repeat(2);
const hostA = 'proxy-a.example.invalid';
const hostB = 'proxy-b.example.invalid';
const upstream = 'api.example.invalid';
const signed = (host = hostA) => ({
  Host: upstream,
  [WEB_PROXY_SECRET_HEADER]: secret,
  'X-Vynic-Web-Proxy-Host': host,
  'X-Vynic-Web-Proxy-Proto': 'https',
  'X-Vynic-Web-Proxy-Ip': '203.0.113.21',
  'X-Forwarded-Host': 'attacker.invalid',
  'X-Forwarded-Proto': 'http',
  'X-Real-IP': '198.51.100.99',
  'X-Forwarded-For': '198.51.100.99, 10.0.0.1',
});

function jsonObject(response: { body: unknown }): Record<string, unknown> {
  if (
    !response.body ||
    typeof response.body !== 'object' ||
    Array.isArray(response.body)
  )
    throw new Error('Expected a JSON object response');
  return response.body as Record<string, unknown>;
}

function jsonString(response: { body: unknown }, key: string): string {
  const value = jsonObject(response)[key];
  if (typeof value !== 'string') throw new Error(`Expected JSON string ${key}`);
  return value;
}

const databaseUrl = process.env.WEB_PROXY_TEST_DATABASE_URL;
(databaseUrl ? describe : describe.skip)(
  'web gateway with real PostgreSQL domain authority',
  () => {
    let db: PrismaService;
    let server: Server;
    const hosts = [hostA, hostB].map((host) => `${randomUUID()}.${host}`);
    const venues: string[] = [];

    beforeAll(async () => {
      if (!isFreshDisposableDatabase(databaseUrl!))
        throw new Error(
          'WEB_PROXY_TEST_DATABASE_URL must name a fresh owned loopback disposable_* database',
        );
      db = new PrismaService({ datasourceUrl: databaseUrl });
      await db.$connect();
      for (const host of hosts) {
        const organization = await db.organization.create({
          data: { name: 'Gateway synthetic fixture' },
        });
        const venue = await db.venue.create({
          data: {
            organizationId: organization.id,
            name: host,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            domains: { create: { hostname: host } },
            websiteConfig: { create: { mode: 'CUSTOM' } },
          },
        });
        venues.push(venue.id);
      }
      const tenants = new WebsiteTenantService(
        db,
        new ConfigService({
          NODE_ENV: 'production',
          TRUST_PROXY_HOST: 'false',
        }),
      );
      const app = express();
      app.use(webProxyIngress(secret));
      app.get('/api/website/bootstrap', async (req, res) => {
        const resolved = await tenants.resolveRequest(req);
        return resolved
          ? res.json({ venue: resolved.tenant.venueId })
          : res.status(404).json({ message: 'Website unavailable' });
      });
      server = await new Promise<Server>((resolve) => {
        const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
      });
    });
    afterAll(async () => {
      if (server)
        await new Promise<void>((resolve, reject) =>
          server.close((error) => (error ? reject(error) : resolve())),
        );
      if (db) await db.$disconnect();
    });

    it.each([0, 1])(
      'serves only the database-owned Venue behind gateway host %s',
      async (index) => {
        const result = await request(server)
          .get('/api/website/bootstrap?venueId=other')
          .set(signed(hosts[index]))
          .set('X-Venue-Id', venues[1 - index]);
        expect(result.status).toBe(200);
        expect(jsonObject(result).venue).toBe(venues[index]);
      },
    );

    it('fails closed for a disabled domain and for unauthenticated forwarding', async () => {
      await db.venueDomain.update({
        where: { hostname: hosts[0] },
        data: { status: 'DISABLED' },
      });
      expect(
        (
          await request(server)
            .get('/api/website/bootstrap')
            .set(signed(hosts[0]))
        ).status,
      ).toBe(404);
      expect(
        (
          await request(server)
            .get('/api/website/bootstrap')
            .set('Host', upstream)
            .set('X-Forwarded-Host', hosts[1])
        ).status,
      ).toBe(404);
    });
  },
);

describe('authenticated web proxy (real loopback HTTP)', () => {
  let server: Server;
  const lookup = jest.fn(({ where }: { where: { hostname: string } }) => {
    const venue =
      where.hostname === hostA
        ? 'venue-a'
        : where.hostname === hostB
          ? 'venue-b'
          : null;
    return Promise.resolve(
      venue
        ? {
            hostname: where.hostname,
            status: 'ACTIVE',
            venue: {
              id: venue,
              organizationId: 'fixture-org',
              status: 'ACTIVE',
              websiteConfig: { mode: 'CUSTOM' },
            },
          }
        : null,
    );
  });
  const tenants = new WebsiteTenantService(
    { venueDomain: { findUnique: lookup } } as never,
    new ConfigService({ NODE_ENV: 'production', TRUST_PROXY_HOST: 'false' }),
  );
  const csrf = new CsrfService();
  const auth = new WebsiteAuthController(
    {} as never,
    {} as never,
    csrf,
    {} as never,
  );
  const oldEnvironment = process.env.NODE_ENV;

  beforeAll(async () => {
    process.env.NODE_ENV = 'production';
    const app = express();
    app.use(webProxyIngress(secret));
    app.use(
      express.json({
        verify: (req, _res, bytes) => {
          (req as Request & { rawBody: Buffer }).rawBody = Buffer.from(bytes);
        },
      }),
    );
    app.use(cookieParser());
    app.get('/api/website/bootstrap', async (req, res) => {
      const resolved = await tenants.resolveRequest(req);
      if (!resolved)
        return res.status(404).json({ message: 'Website unavailable' });
      return res.json({
        venue: resolved.tenant.venueId,
        host: resolved.hostname,
        sameOrigin: isSameOriginRequest(req.get('origin') ?? '', req.headers, {
          trustForwardedHost: false,
        }),
      });
    });
    app.get('/api/auth/csrf', (req, res) =>
      res.json(auth.getCsrfToken(res, req)),
    );
    app.all(
      ['/api/probe', '/mobile/probe', '/api/bog/payment-callback'],
      (req, res) => {
        if (
          req.path === '/api/probe' &&
          req.method !== 'GET' &&
          !csrf.validateToken(
            req.headers['x-csrf-token'],
            (req.cookies as Record<string, unknown> | undefined)?.csrf_token,
          )
        )
          return res.status(403).json({ message: 'Invalid CSRF token' });
        return res.json({
          host: req.headers.host,
          method: req.method,
          url: req.originalUrl,
          body: req.body as unknown,
          rawBody: (req as Request & { rawBody?: Buffer }).rawBody?.toString(),
          authorization: req.headers.authorization,
          ip: req.ip,
          credentialVisibleToHandler:
            req.headers[WEB_PROXY_SECRET_HEADER] !== undefined,
          forwardedHostVisibleToHandler:
            req.headers['x-forwarded-host'] !== undefined,
        });
      },
    );
    server = await new Promise<Server>((resolve) => {
      const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
    });
  });
  afterAll(async () => {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
    if (oldEnvironment === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = oldEnvironment;
  });
  beforeEach(() => lookup.mockClear());

  it.each([
    [hostA, 'venue-a'],
    [hostB, 'venue-b'],
  ])('resolves only the registered forwarded host %s', async (host, venue) => {
    const response = await request(server)
      .get('/api/website/bootstrap')
      .set(signed(host))
      .set('Origin', `https://${host}`);
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ venue, host, sameOrigin: true });
  });

  it('does not let body/query tenant IDs override the authenticated site', async () => {
    const response = await request(server)
      .get('/api/website/bootstrap?venueId=venue-b')
      .set(signed(hostA))
      .set('X-Venue-Id', 'venue-b');
    expect(response.status).toBe(200);
    expect(jsonObject(response).venue).toBe('venue-a');
  });

  it('ignores an unauthenticated forwarded host and never falls back to a Venue', async () => {
    const response = await request(server)
      .get('/api/website/bootstrap')
      .set('Host', upstream)
      .set('X-Forwarded-Host', hostA);
    expect(response.status).toBe(404);
    expect(lookup).toHaveBeenCalledWith(
      expect.objectContaining({ where: { hostname: upstream } }),
    );
  });

  it('preserves direct Host authority while dropping a forged forwarded host', async () => {
    const response = await request(server)
      .get('/api/website/bootstrap')
      .set('Host', hostA)
      .set('X-Forwarded-Host', hostB);
    expect(jsonObject(response).venue).toBe('venue-a');
  });

  it('rejects a wrong gateway credential before any tenant lookup', async () => {
    const response = await request(server)
      .get('/api/website/bootstrap')
      .set(signed())
      .set(WEB_PROXY_SECRET_HEADER, 'wrong');
    expect(response.status).toBe(403);
    expect(lookup).not.toHaveBeenCalled();
    expect(response.text).not.toContain(secret);
  });

  it('does not fall back from an unknown authenticated host to a registered upstream', async () => {
    const response = await request(server)
      .get('/api/website/bootstrap')
      .set(signed('unknown.example.invalid'))
      .set('Host', hostA);
    expect(response.status).toBe(404);
    expect(lookup).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['X-Vynic-Web-Proxy-Host', 'https://proxy-a.example.invalid'],
    ['X-Vynic-Web-Proxy-Host', `${hostA}, ${hostB}`],
    ['X-Vynic-Web-Proxy-Host', ''],
    ['X-Vynic-Web-Proxy-Proto', 'http'],
    ['X-Vynic-Web-Proxy-Proto', 'https,http'],
    ['X-Vynic-Web-Proxy-Ip', 'not-an-ip'],
    ['X-Vynic-Web-Proxy-Ip', ''],
    ['X-Vynic-Web-Proxy-Ip', '203.0.113.21, 198.51.100.99'],
  ])(
    'rejects malformed authenticated metadata %s=%s',
    async (header, value) => {
      const response = await request(server)
        .get('/api/website/bootstrap')
        .set(signed())
        .set(header, value);
      expect(response.status).toBe(400);
      expect(jsonObject(response).invalidFields).toEqual([
        header.endsWith('Host')
          ? 'host'
          : header.endsWith('Proto')
            ? 'protocol'
            : 'clientIp',
      ]);
      expect(response.text).not.toContain(secret);
      expect(lookup).not.toHaveBeenCalled();
    },
  );

  it.each(['203.0.113.21', '2001:db8::21'])(
    'uses private visitor metadata and ignores generic forwarded IPs %s',
    async (visitor) => {
      const response = await request(server)
        .get('/api/probe')
        .set(signed())
        .set('X-Vynic-Web-Proxy-Ip', visitor)
        .set('X-Forwarded-For', 'not-an-ip, also-invalid')
        .set('X-Real-IP', 'not-an-ip');
      expect(response.status).toBe(200);
      expect(jsonObject(response).ip).toBe(visitor);
    },
  );

  it('never falls back to generic forwarded authority, even with a credential', async () => {
    const response = await request(server)
      .get('/api/probe')
      .set(signed())
      .unset('X-Vynic-Web-Proxy-Host')
      .unset('X-Vynic-Web-Proxy-Proto')
      .unset('X-Vynic-Web-Proxy-Ip')
      .set('X-Forwarded-Host', hostA)
      .set('X-Forwarded-Proto', 'https')
      .set('X-Forwarded-For', '203.0.113.21');
    expect(response.status).toBe(400);
    expect(jsonObject(response).invalidFields).toEqual([
      'host',
      'protocol',
      'clientIp',
    ]);
  });

  it('keeps method, exact body, query, Authorization, cookies and CSRF intact', async () => {
    const tokenResponse = await request(server)
      .get('/api/auth/csrf')
      .set(signed());
    const cookies: string[] = tokenResponse.headers[
      'set-cookie'
    ] as unknown as string[];
    expect(cookies[0]).toContain('Secure');
    expect(cookies[0]).toContain('SameSite=Strict');
    expect(cookies[0]).not.toContain('Domain=');
    const rawBody = '{\n  "message": "ქართული", "venueId": "untrusted"\n}';
    const response = await request(server)
      .patch('/api/probe?cursor=a%2Fb&limit=2')
      .set(signed())
      .set('Cookie', cookies.map((cookie) => cookie.split(';')[0]).join('; '))
      .set('X-CSRF-Token', jsonString(tokenResponse, 'csrfToken'))
      .set('Authorization', 'Bearer synthetic-owner-token')
      .set('Content-Type', 'application/json')
      .send(rawBody);
    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      host: hostA,
      method: 'PATCH',
      url: '/api/probe?cursor=a%2Fb&limit=2',
      body: { message: 'ქართული', venueId: 'untrusted' },
      rawBody,
      authorization: 'Bearer synthetic-owner-token',
      ip: '203.0.113.21',
      credentialVisibleToHandler: false,
      forwardedHostVisibleToHandler: false,
    });
  });

  it('still refuses a state-changing request with an incorrect CSRF pair', async () => {
    const response = await request(server)
      .post('/api/probe')
      .set(signed())
      .set('X-CSRF-Token', 'wrong')
      .send({});
    expect(response.status).toBe(403);
  });

  it('does not widen same-origin CORS to another site', async () => {
    const response = await request(server)
      .get('/api/website/bootstrap')
      .set(signed(hostA))
      .set('Origin', `https://${hostB}`);
    expect(jsonObject(response).sameOrigin).toBe(false);
  });

  it('leaves direct payment callbacks available without gateway credentials', async () => {
    const response = await request(server)
      .post('/api/bog/payment-callback')
      .set('Host', upstream)
      .send({ synthetic: true });
    expect(response.status).toBe(200);
    expect(jsonObject(response).host).toBe(upstream);
  });

  it('does not grant native transports host/IP authority from gateway headers', async () => {
    const response = await request(server)
      .get('/mobile/probe')
      .set(signed())
      .set(WEB_PROXY_SECRET_HEADER, 'wrong');
    expect(response.status).toBe(200);
    expect(jsonObject(response).host).toBe(upstream);
    expect(jsonObject(response).ip).not.toBe('203.0.113.21');
  });
});
