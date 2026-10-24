import { Test } from '@nestjs/testing';
import { Logger, NotFoundException } from '@nestjs/common';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import { runInNewContext } from 'node:vm';
import { createServer } from 'node:http';
const binary = (res: any, done: any) => {
  const chunks: Buffer[] = [];
  res.on('data', (c: Buffer) => chunks.push(c));
  res.on('end', () => done(null, Buffer.concat(chunks)));
};
import { InstallerDownloadFileController } from './installer-downloads.controller';
import { InstallerDownloadsService } from './installer-downloads.service';
import { installerDownloadBridge } from './installer-download-bridge';
const grant = {
  id: 'synthetic-grant',
  artifactId: '999',
  artifactBytes: 10,
  artifactSha256: 'a'.repeat(64),
  platformUserId: 'synthetic-operator',
};
describe('Protected installer browser delivery', () => {
  let app: any, downloads: InstallerDownloadsService;
  beforeAll(async () => {
    downloads = new InstallerDownloadsService({
      installerDownloadGrant: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      platformAuditEvent: { create: jest.fn().mockResolvedValue({}) },
    } as any);
    const module = await Test.createTestingModule({
      controllers: [InstallerDownloadFileController],
      providers: [{ provide: InstallerDownloadsService, useValue: downloads }],
    }).compile();
    app = module.createNestApplication();
    app.use(cookieParser());
    await app.listen(0, '127.0.0.1');
  });
  afterAll(async () => app.close());
  beforeEach(() => {
    jest.spyOn(downloads, 'configuration').mockReturnValue({
      ready: true,
      token: 'synthetic-storage-secret',
      assetId: '999',
      bytes: 10,
      sha256: grant.artifactSha256,
    });
    jest.spyOn(downloads, 'resolve').mockImplementation(async (token) => {
      if (token !== 'synthetic-capability')
        throw new NotFoundException('secret diagnostic');
      return grant as any;
    });
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => {});
  });
  afterEach(() => jest.restoreAllMocks());
  const path = '/customer/downloads/access/synthetic-grant/file',
    cookie = 'vynic-download=synthetic-capability';
  it('renders a denied file request as an error page, never file.json or an attachment', async () => {
    const r = await request(app.getHttpServer()).get(path).expect(404);
    expect(r.headers['content-type']).toContain('text/html');
    expect(r.headers['content-disposition']).toBeUndefined();
    expect(r.headers['cache-control']).toContain('no-store');
    expect(r.text).toContain('Request a new link');
    expect(r.text).not.toContain('secret diagnostic');
    await request(app.getHttpServer()).head(path).expect(404);
  });
  it.each([401, 403, 404, 429, 503])(
    'keeps upstream %s private and shows a storage error instead of saving JSON',
    async (status) => {
      jest.spyOn(globalThis, 'fetch').mockResolvedValue(
        new Response('private upstream body', {
          status,
          headers: {
            'content-type': 'application/json',
            'content-length': '21',
          },
        }),
      );
      const r = await request(app.getHttpServer())
        .get(path)
        .set('Cookie', cookie)
        .expect(503);
      expect(r.headers['content-type']).toContain('text/html');
      expect(r.headers['content-disposition']).toBeUndefined();
      expect(r.text).toContain('temporarily unavailable');
      expect(r.text).not.toContain('private upstream body');
      const logs = JSON.stringify(
        (Logger.prototype.warn as jest.Mock).mock.calls,
      );
      expect(logs).toContain('installer_storage_unavailable');
      expect(logs).not.toMatch(
        /synthetic-storage-secret|synthetic-capability|synthetic-grant|https:/,
      );
    },
  );
  it('delivers full bytes, HEAD and resumed ranges through HTTP with ZIP headers', async () => {
    const spy = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async (url: any, init: any) => {
        if (String(url).startsWith('https://api.github.com'))
          return new Response(null, {
            status: 302,
            headers: {
              location:
                'https://release-assets.githubusercontent.com/synthetic',
            },
          });
        const range = init.headers.Range;
        return new Response(
          init.method === 'HEAD' ? null : range ? '345' : '0123456789',
          {
            status: range ? 206 : 200,
            headers: {
              'content-type': 'application/octet-stream',
              'content-length': range ? '3' : '10',
              ...(range ? { 'content-range': 'bytes 3-5/10' } : {}),
            },
          },
        );
      });
    const full = await request(app.getHttpServer())
      .get(path)
      .buffer(true)
      .parse(binary)
      .set('Cookie', cookie)
      .expect(200);
    expect(full.headers['content-type']).toBe('application/zip');
    expect(full.headers['content-disposition']).toBe(
      'attachment; filename="Vynic-Windows-beta-offline.zip"',
    );
    expect(full.body).toEqual(Buffer.from('0123456789'));
    const head = await request(app.getHttpServer())
      .head(path)
      .set('Cookie', cookie)
      .expect(200);
    expect(head.headers['content-length']).toBe('10');
    const partial = await request(app.getHttpServer())
      .get(path)
      .buffer(true)
      .parse(binary)
      .set('Cookie', cookie)
      .set('Range', 'bytes=3-5')
      .expect(206);
    expect(partial.headers['content-range']).toBe('bytes 3-5/10');
    expect(partial.body).toEqual(Buffer.from('345'));
    expect(partial.headers.location).toBeUndefined();
    for (const [url, init] of spy.mock.calls)
      if (String(url).includes('release-assets'))
        expect((init!.headers as any).Authorization).toBeUndefined();
  });
  it('supports a ranged asset streamed directly by the GitHub API', async () => {
    const spy = jest
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(
        new Response('345', {
          status: 206,
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': '3',
            'content-range': 'bytes 3-5/10',
          },
        }),
      );
    const r = await request(app.getHttpServer())
      .get(path)
      .buffer(true)
      .parse(binary)
      .set('Cookie', cookie)
      .set('Range', 'bytes=3-5')
      .expect(206);
    expect(r.body).toEqual(Buffer.from('345'));
    expect((spy.mock.calls[0][1]!.headers as any).Range).toBe('bytes=3-5');
  });
  it('follows a technical origin redirect through the cookie handshake to complete and resumed HTTP delivery', async () => {
    const nativeFetch = globalThis.fetch;
    jest.spyOn(downloads, 'linkContext').mockResolvedValue(grant as any);
    jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async (url: any, init: any) => {
        if (String(url).startsWith('https://api.github.com'))
          return new Response(null, {
            status: 302,
            headers: {
              location:
                'https://release-assets.githubusercontent.com/synthetic',
            },
          });
        if (String(url).startsWith('https://release-assets')) {
          const range = init.headers.Range;
          return new Response(
            init.method === 'HEAD' ? null : range ? '345' : '0123456789',
            {
              status: range ? 206 : 200,
              headers: {
                'content-type': 'application/octet-stream',
                'content-length': range ? '3' : '10',
                ...(range ? { 'content-range': 'bytes 3-5/10' } : {}),
              },
            },
          );
        }
        return nativeFetch(url, init);
      });
    const api = await app.getUrl();
    const origin = createServer((_req, res) => {
      res.writeHead(301, {
        Location: api + '/customer/downloads/access/synthetic-grant',
      });
      res.end();
    });
    await new Promise<void>((resolve) =>
      origin.listen(0, '127.0.0.1', resolve),
    );
    try {
      const page = await nativeFetch(
        'http://127.0.0.1:' +
          (origin.address() as any).port +
          '/windows/access/synthetic-grant',
      );
      expect(page.status).toBe(200);
      const html = await page.text();
      const source = html
        .split(/<script nonce="[^"]+">/)[1]
        .split('</script>')[0];
      let sessionCookie = '';
      const file = { hidden: true, href: '' },
        status = { textContent: '' };
      const browserFetch = async (path: string, init: any) => {
        const response = await nativeFetch(api + path, {
          ...init,
          headers: {
            ...init.headers,
            Origin: api,
            ...(sessionCookie ? { Cookie: sessionCookie } : {}),
          },
        });
        const set = response.headers.get('set-cookie');
        if (set) sessionCookie = set.split(';')[0];
        return response;
      };
      runInNewContext(source, {
        URLSearchParams,
        location: {
          hash: '#token=synthetic-capability',
          pathname: new URL(page.url).pathname,
        },
        history: { replaceState: () => {} },
        document: {
          getElementById: (id: string) => (id === 'file' ? file : status),
        },
        fetch: browserFetch,
      });
      for (let i = 0; i < 100 && file.hidden; i++)
        await new Promise((resolve) => setTimeout(resolve, 5));
      expect(file.hidden).toBe(false);
      expect(sessionCookie).toContain('vynic-download=');
      const full = await browserFetch(file.href, { method: 'GET' });
      expect(full.status).toBe(200);
      expect(full.headers.get('content-type')).toBe('application/zip');
      expect(full.headers.get('content-disposition')).toContain(
        'filename="Vynic-Windows-beta-offline.zip"',
      );
      expect(Buffer.from(await full.arrayBuffer())).toEqual(
        Buffer.from('0123456789'),
      );
      const part = await browserFetch(file.href, {
        method: 'GET',
        headers: { Range: 'bytes=3-5' },
      });
      expect(part.status).toBe(206);
      expect(part.headers.get('content-range')).toBe('bytes 3-5/10');
      expect(Buffer.from(await part.arrayBuffer())).toEqual(Buffer.from('345'));
    } finally {
      await new Promise<void>((resolve) => origin.close(() => resolve()));
    }
  });
});
describe('Protected installer transport handshake', () => {
  async function bridge(head: Response) {
    const status = { textContent: '' },
      file = { hidden: true, href: '' };
    const fetch = jest
      .fn()
      .mockResolvedValueOnce(new Response('{}', { status: 201 }))
      .mockResolvedValueOnce(head);
    const history = { replaceState: jest.fn() };
    const html = installerDownloadBridge('synthetic-grant', 'synthetic-nonce');
    runInNewContext(
      html.split('<script nonce="synthetic-nonce">')[1].split('</script>')[0],
      {
        URLSearchParams,
        location: {
          hash: '#token=synthetic-capability',
          pathname: '/synthetic',
        },
        history,
        document: {
          getElementById: (id: string) => (id === 'status' ? status : file),
        },
        fetch,
      },
    );
    await new Promise((resolve) => setImmediate(resolve));
    return { status, file, fetch, html, history };
  }
  it('checks protected HEAD before offering the natural attachment link', async () => {
    const r = await bridge(
      new Response(null, {
        status: 200,
        headers: {
          'content-type': 'application/zip',
          'content-disposition': 'attachment; filename="package.zip"',
          'content-length': '10',
        },
      }),
    );
    expect(r.file.hidden).toBe(false);
    expect(r.html).not.toMatch(/rel="noreferrer" download/);
    expect(r.fetch.mock.calls[1][1]).toMatchObject({
      method: 'HEAD',
      credentials: 'same-origin',
      cache: 'no-store',
    });
    expect(r.history.replaceState).toHaveBeenCalledWith(null, '', '/synthetic');
  });
  it.each([404, 503])(
    'does not offer a download for HEAD error %s',
    async (status) => {
      const r = await bridge(new Response(null, { status }));
      expect(r.file.hidden).toBe(true);
      expect(r.file.href).toBe('');
      expect(r.status.textContent).toContain(
        status === 503 ? 'temporarily unavailable' : 'Request a new link',
      );
    },
  );
  it('refuses a successful JSON response in place of the archive', async () => {
    const r = await bridge(
      new Response(null, {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );
    expect(r.file.hidden).toBe(true);
    expect(r.status.textContent).toContain('temporarily unavailable');
  });
});
