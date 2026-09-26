import * as http from 'node:http';
import type { AddressInfo } from 'node:net';
import {
  checkCustomWebsite,
  isPublicAddress,
  runtimeTarget,
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

  it('maps only a .localhost domain outside production to the dev server', () => {
    const dev = { production: false, localPort: 5176 };
    expect(runtimeTarget('custom-a.vynic.localhost', dev)).toEqual({
      hostname: 'custom-a.vynic.localhost',
      local: true,
      url: 'http://custom-a.vynic.localhost:5176/',
    });
    expect(runtimeTarget('vankisi.ge', dev)).toMatchObject({
      local: false,
      url: 'https://vankisi.ge/',
    });
    expect(
      runtimeTarget('custom-a.vynic.localhost', { ...dev, production: true }),
    ).toMatchObject({
      local: false,
      url: 'https://custom-a.vynic.localhost/',
    });
  });

  it('refuses a domain that resolves anywhere non-public, before connecting', async () => {
    for (const answer of [['10.0.0.5'], ['8.8.8.8', '127.0.0.1'], []]) {
      const resolve = jest.fn(() => Promise.resolve(answer));
      const result = await checkCustomWebsite(
        runtimeTarget('internal.example', { production: true, localPort: 1 }),
        { venueName: 'X' },
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
      runtimeTarget('169.254.169.254', { production: true, localPort: 1 }),
      { venueName: 'X' },
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

    const target = () =>
      runtimeTarget('custom-a.vynic.localhost', {
        production: false,
        localPort: port,
      });

    it('reports a reachable frontend and the backend answering for this Venue', async () => {
      answer = (req, res) => {
        if (req.url === '/api/website/venue') {
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ mode: 'CUSTOM', profile: { name: 'A' } }));
        } else res.end('<html></html>');
      };
      const result = await checkCustomWebsite(target(), { venueName: 'A' });
      expect(result).toMatchObject({
        availability: 'REACHABLE',
        url: `http://custom-a.vynic.localhost:${port}/`,
        frontend: { status: 200 },
        api: { state: 'OK' },
      });
      // The domain is the Host, as a browser would send it.
      expect(seen).toEqual([
        { path: '/', host: `custom-a.vynic.localhost:${port}` },
        {
          path: '/api/website/venue',
          host: `custom-a.vynic.localhost:${port}`,
        },
      ]);
    });

    it('separates a reachable frontend from an API that is not proxied or serves another restaurant', async () => {
      answer = (_req, res) => res.end('<html>SPA fallback</html>');
      expect(
        (await checkCustomWebsite(target(), { venueName: 'A' })).api,
      ).toMatchObject({
        state: 'FAILED',
        detail: '/api is not proxied to the Vynic backend',
      });
      answer = (_req, res) => {
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify({ mode: 'CUSTOM', profile: { name: 'B' } }));
      };
      const wrong = await checkCustomWebsite(target(), { venueName: 'A' });
      expect(wrong.availability).toBe('REACHABLE');
      expect(wrong.api.state).toBe('WRONG_SITE');
    });

    it('does not follow redirects', async () => {
      answer = (_req, res) => {
        res.statusCode = 302;
        res.setHeader('location', 'http://169.254.169.254/');
        res.end();
      };
      const result = await checkCustomWebsite(target(), { venueName: 'A' });
      expect(result.frontend).toEqual({
        status: 302,
        detail: 'Answers with a redirect (302)',
      });
      expect(result.api.state).toBe('FAILED');
      expect(seen.map((s) => s.path)).toEqual(['/', '/api/website/venue']);
    });

    it('reports a stopped frontend as unreachable', async () => {
      const closed = http.createServer();
      await new Promise<void>((resolve) =>
        closed.listen(0, '127.0.0.1', resolve),
      );
      const freePort = (closed.address() as AddressInfo).port;
      await new Promise((resolve) => closed.close(resolve));
      const result = await checkCustomWebsite(
        runtimeTarget('custom-a.vynic.localhost', {
          production: false,
          localPort: freePort,
        }),
        { venueName: 'A' },
      );
      expect(result).toMatchObject({
        availability: 'UNREACHABLE',
        frontend: { status: null, detail: 'Connection refused' },
        api: { state: 'FAILED' },
      });
    });
  });
});
