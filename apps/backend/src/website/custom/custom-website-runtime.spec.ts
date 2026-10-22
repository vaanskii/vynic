import * as http from 'node:http';
import type { AddressInfo } from 'node:net';
import { createHash } from 'node:crypto';
import { websiteVenueIdentity } from '../core/website-identity';
const expected = (id: string) => ({
  venueIdentity: websiteVenueIdentity(id),
  siteKey: 'custom-a-web',
  buildId: 'a'.repeat(64),
});
const bootstrap = (id: string) => ({
  schemaVersion: 1,
  mode: 'CUSTOM',
  identity: { venue: websiteVenueIdentity(id) },
  site: { key: 'custom-a-web', status: 'ACTIVE' },
  profile: { name: 'Identical restaurant name' },
});
const html = '<html>Compiled CUSTOM</html>';
const manifest = () => ({
  schemaVersion: 1,
  renderer: 'CUSTOM',
  siteKey: 'custom-a-web',
  buildId: 'a'.repeat(64),
  htmlDigest: createHash('sha256').update(html).digest('hex'),
});
import {
  checkCustomWebsite,
  isPublicAddress,
  localTarget,
  publicTarget,
} from './custom-website-runtime';

describe('CUSTOM website runtime check', () => {
  it('treats only routable public unicast addresses as public', () => {
    for (const ok of ['8.8.8.8', '1.1.1.1', '2606:4700:4700::1111'])
      expect(isPublicAddress(ok)).toBe(true);
    for (const bad of [
      '127.0.0.1',
      '10.1.2.3',
      '172.20.0.1',
      '192.168.1.10',
      '169.254.169.254',
      '100.64.0.1',
      '0.0.0.0',
      '224.0.0.1',
      '::1',
      '::',
      'fe80::1',
      'fd12:3456::1',
      '::ffff:127.0.0.1',
      '::ffff:10.0.0.1',
      'not-an-ip',
    ])
      expect(isPublicAddress(bad)).toBe(false);
  });

  it('builds public and local targets without any default port', () => {
    expect(publicTarget('vankisi.ge')).toEqual({
      hostname: 'vankisi.ge',
      local: false,
      url: 'https://vankisi.ge/',
    });
    expect(localTarget('vankisi.localhost', 5174)).toEqual({
      hostname: 'vankisi.localhost',
      local: true,
      url: 'http://vankisi.localhost:5174/',
    });
    expect(localTarget('custom-b.localhost', 5176).url).toBe(
      'http://custom-b.localhost:5176/',
    );
    // Loopback pinning is only for .localhost names and sane ports.
    expect(() => localTarget('vankisi.ge', 5174)).toThrow();
    expect(() => localTarget('vankisi.localhost', 80)).toThrow();
    expect(() => localTarget('vankisi.localhost', 70000)).toThrow();
  });

  it('refuses a domain that resolves anywhere non-public, before connecting', async () => {
    for (const answer of [['10.0.0.5'], ['8.8.8.8', '127.0.0.1'], []]) {
      const resolve = jest.fn(() => Promise.resolve(answer));
      const result = await checkCustomWebsite(
        publicTarget('internal.example'),
        expected('X'),
        resolve,
      );
      expect(resolve).toHaveBeenCalledWith('internal.example');
      expect(result).toMatchObject({
        availability: 'UNREACHABLE',
        frontend: { status: null },
        api: { state: 'NOT_CHECKED' },
      });
      expect(result.frontend.detail).toMatch(/non-public|does not resolve/);
    }
  });

  it('never contacts an IP-address domain', async () => {
    const resolve = jest.fn();
    const result = await checkCustomWebsite(
      publicTarget('169.254.169.254'),
      expected('X'),
      resolve,
    );
    expect(resolve).not.toHaveBeenCalled();
    expect(result.frontend.detail).toBe('IP-address domains are not checked');
  });

  describe('against a local dev server', () => {
    let server: http.Server;
    let port: number;
    const seen: Array<{ path?: string; host?: string }> = [];
    let answer: (req: http.IncomingMessage, res: http.ServerResponse) => void;

    beforeAll(async () => {
      server = http.createServer((req, res) => {
        seen.push({ path: req.url, host: req.headers.host });
        answer(req, res);
      });
      await new Promise<void>((resolve) =>
        server.listen(0, '127.0.0.1', resolve),
      );
      port = (server.address() as AddressInfo).port;
    });
    afterAll(() => new Promise((resolve) => server.close(resolve)));
    beforeEach(() => (seen.length = 0));

    const target = () => localTarget('custom-a.vynic.localhost', port);

    it.each([
      'same-name other Venue',
      'renamed same Venue',
      'SAAS renderer',
      'wrong app key',
      'wrong recorded build',
      'wrong served HTML',
      'missing manifest',
      'legacy bootstrap',
      'unrecorded build',
      'invalid manifest hash',
      'redirected frontend',
    ])(
      '%s cannot confuse reachability with verified deployment identity',
      async (scenario) => {
        const api = bootstrap(scenario === 'same-name other Venue' ? 'B' : 'A');
        const built = {
          ...manifest(),
          renderer: scenario === 'SAAS renderer' ? 'SAAS' : 'CUSTOM',
          siteKey:
            scenario === 'SAAS renderer'
              ? null
              : scenario === 'wrong app key'
                ? 'other-client-web'
                : 'custom-a-web',
          buildId:
            scenario === 'wrong recorded build'
              ? 'b'.repeat(64)
              : scenario === 'invalid manifest hash'
                ? 'invalid'
                : 'a'.repeat(64),
        };
        if (scenario === 'renamed same Venue')
          api.profile.name = 'A renamed restaurant';
        const apiData =
          scenario === 'legacy bootstrap'
            ? { ...api, identity: undefined }
            : api;
        answer = (req, res) => {
          if (req.url === '/api/website/venue') {
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify(apiData));
          } else if (req.url === '/vynic-site-manifest.json') {
            res.statusCode = scenario === 'missing manifest' ? 404 : 200;
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify(built));
          } else {
            res.statusCode = scenario === 'redirected frontend' ? 302 : 200;
            res.setHeader('content-type', 'text/html');
            if (scenario === 'redirected frontend')
              res.setHeader('location', 'https://other-client.invalid/');
            res.end(
              scenario === 'wrong served HTML'
                ? '<html>Other renderer</html>'
                : html,
            );
          }
        };
        const result = await checkCustomWebsite(target(), {
          ...expected('A'),
          buildId:
            scenario === 'unrecorded build' ? null : expected('A').buildId,
        });
        expect(result.environment).toBe('LOCAL_DEVELOPMENT');
        expect(result.api.state).toBe(
          scenario === 'same-name other Venue'
            ? 'WRONG_SITE'
            : scenario === 'legacy bootstrap'
              ? 'UNVERIFIED'
              : 'OK',
        );
        expect(result.build.state).toBe(
          ['missing manifest', 'invalid manifest hash'].includes(scenario)
            ? 'FAILED'
            : scenario === 'unrecorded build'
              ? 'UNRECORDED'
              : [
                    'same-name other Venue',
                    'renamed same Venue',
                    'legacy bootstrap',
                  ].includes(scenario)
                ? 'VERIFIED'
                : 'WRONG_BUILD',
        );
        expect(result.bindingIdentityVerified).toBe(
          scenario === 'renamed same Venue',
        );
        expect(
          seen.every(({ path }) =>
            ['/', '/api/website/venue', '/vynic-site-manifest.json'].includes(
              path ?? '',
            ),
          ),
        ).toBe(true);
      },
    );

    it.each(['oversized', 'truncated'])(
      '%s manifest never passes verification',
      async (scenario) => {
        answer = (req, res) => {
          if (req.url === '/api/website/venue') {
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify(bootstrap('A')));
          } else if (req.url === '/vynic-site-manifest.json') {
            res.setHeader('content-type', 'application/json');
            const body = JSON.stringify(manifest());
            if (scenario === 'oversized') res.end(body + ' '.repeat(70 * 1024));
            else {
              res.setHeader('content-length', Buffer.byteLength(body) + 100);
              res.end(body);
            }
          } else {
            res.setHeader('content-type', 'text/html');
            res.end(html);
          }
        };
        const result = await checkCustomWebsite(target(), expected('A'));
        expect(result.build.state).toBe('FAILED');
        expect(result.bindingIdentityVerified).toBe(false);
      },
    );

    it('reports a reachable frontend and the backend answering for this Venue', async () => {
      answer = (req, res) => {
        if (req.url === '/api/website/venue') {
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(bootstrap('A')));
        } else if (req.url === '/vynic-site-manifest.json') {
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(manifest()));
        } else {
          res.setHeader('content-type', 'text/html');
          res.end(html);
        }
      };
      const result = await checkCustomWebsite(target(), expected('A'));
      expect(result).toMatchObject({
        availability: 'REACHABLE',
        url: `http://custom-a.vynic.localhost:${port}/`,
        frontend: { status: 200 },
        api: { state: 'OK' },
        build: { state: 'VERIFIED' },
        bindingIdentityVerified: true,
      });
      // The domain is the Host, as a browser would send it.
      expect(seen).toEqual([
        { path: '/', host: `custom-a.vynic.localhost:${port}` },
        {
          path: '/api/website/venue',
          host: `custom-a.vynic.localhost:${port}`,
        },
        {
          path: '/vynic-site-manifest.json',
          host: `custom-a.vynic.localhost:${port}`,
        },
      ]);
    });

    it('separates a reachable frontend from an API that is not proxied or serves another restaurant', async () => {
      answer = (_req, res) => res.end('<html>SPA fallback</html>');
      expect(
        (await checkCustomWebsite(target(), expected('A'))).api,
      ).toMatchObject({
        state: 'FAILED',
        detail: '/api is not a supported Vynic bootstrap',
      });
      answer = (_req, res) => {
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify(bootstrap('B')));
      };
      const wrong = await checkCustomWebsite(target(), expected('A'));
      expect(wrong.availability).toBe('REACHABLE');
      expect(wrong.api.state).toBe('WRONG_SITE');
    });

    it('does not follow redirects', async () => {
      answer = (_req, res) => {
        res.statusCode = 302;
        res.setHeader('location', 'http://169.254.169.254/');
        res.end();
      };
      const result = await checkCustomWebsite(target(), expected('A'));
      expect(result.frontend).toEqual({
        status: 302,
        detail: 'Redirect refused (302)',
      });
      expect(result.api.state).toBe('FAILED');
      expect(seen.map((s) => s.path)).toEqual([
        '/',
        '/api/website/venue',
        '/vynic-site-manifest.json',
      ]);
    });

    it('reports a stopped frontend as unreachable', async () => {
      const closed = http.createServer();
      await new Promise<void>((resolve) =>
        closed.listen(0, '127.0.0.1', resolve),
      );
      const freePort = (closed.address() as AddressInfo).port;
      await new Promise((resolve) => closed.close(resolve));
      const result = await checkCustomWebsite(
        localTarget('custom-a.vynic.localhost', freePort),
        expected('A'),
      );
      expect(result).toMatchObject({
        availability: 'UNREACHABLE',
        frontend: { status: null, detail: 'Connection refused' },
        api: { state: 'FAILED' },
      });
    });
  });
});
