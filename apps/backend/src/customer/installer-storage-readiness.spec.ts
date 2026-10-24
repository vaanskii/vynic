import { Logger } from '@nestjs/common';
import { InstallerDownloadsService } from './installer-downloads.service';
import {
  checkInstallerStorage,
  classifyInstallerStorage,
} from './installer-storage-readiness';
const config = { token: 'synthetic-storage-secret', assetId: '999', bytes: 10 };
afterEach(() => jest.restoreAllMocks());
it.each([
  [
    403,
    'Resource not accessible by personal access token',
    'credential_scope_denied',
  ],
  [403, 'API rate limit exceeded for user', 'provider_rate_limited'],
  [429, 'secondary rate limit', 'provider_rate_limited'],
  [401, 'Bad credentials', 'credential_rejected'],
  [404, 'Not Found', 'asset_hidden_or_missing'],
  [
    403,
    'Resource protected by organization SAML enforcement',
    'provider_sso_required',
  ],
  [
    403,
    'sensitive text must never escape https://private.invalid/token=secret',
    'provider_forbidden',
  ],
] as const)(
  'classifies provider %s without exposing its body',
  async (status, message, classification) => {
    const r = await classifyInstallerStorage(
      new Response(JSON.stringify({ message }), {
        status,
        headers: {
          'content-type': 'application/json',
          'x-ratelimit-remaining': '0',
          'x-accepted-github-permissions': 'contents=read',
        },
      }),
      'github_api',
    );
    expect(r).toMatchObject({
      status,
      classification,
      rateLimitRemaining: 0,
      acceptedContentsRead: true,
    });
    expect(JSON.stringify(r)).not.toMatch(
      /secret|private.invalid|sensitive text/,
    );
  },
);
it('bounds provider error body parsing', async () => {
  const r = await classifyInstallerStorage(
    new Response('x'.repeat(8193), {
      status: 403,
      headers: { 'content-type': 'application/json' },
    }),
    'github_api',
  );
  expect(r.classification).toBe('provider_error_body_oversize');
});
it('checks existing credential and exact asset headers without downloading or forwarding the credential', async () => {
  const spy = jest
    .spyOn(globalThis, 'fetch')
    .mockResolvedValueOnce(
      new Response(null, {
        status: 302,
        headers: {
          location:
            'https://release-assets.githubusercontent.com/synthetic?signed=private',
        },
      }),
    )
    .mockResolvedValueOnce(
      new Response(null, {
        status: 200,
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': '10',
        },
      }),
    );
  await expect(checkInstallerStorage(config)).resolves.toMatchObject({
    available: true,
    host: 'artifact_host',
    classification: 'verified_headers',
  });
  expect(spy.mock.calls[0][1]!.headers).toMatchObject({
    Authorization: 'Bearer synthetic-storage-secret',
  });
  expect(spy.mock.calls[1][1]).toMatchObject({ method: 'HEAD' });
  expect((spy.mock.calls[1][1]!.headers as any).Authorization).toBeUndefined();
});
it('also supports a directly streamed API asset', async () => {
  jest.spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response('0123456789', {
      status: 200,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '10',
      },
    }),
  );
  await expect(checkInstallerStorage(config)).resolves.toMatchObject({
    available: true,
    host: 'github_api',
  });
});
it('rejects a redirect outside fixed storage hosts', async () => {
  jest.spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response(null, {
      status: 302,
      headers: { location: 'https://attacker.invalid/private' },
    }),
  );
  const r = await checkInstallerStorage(config);
  expect(r).toMatchObject({
    available: false,
    classification: 'redirect_refused',
  });
  expect(JSON.stringify(r)).not.toContain('attacker');
});
it('reports the runtime permission refusal rather than treating configured storage as verified', async () => {
  jest.spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response(
      JSON.stringify({
        message: 'Resource not accessible by personal access token',
      }),
      {
        status: 403,
        headers: {
          'content-type': 'application/json',
          'x-ratelimit-remaining': '4999',
        },
      },
    ),
  );
  await expect(checkInstallerStorage(config)).resolves.toMatchObject({
    available: false,
    classification: 'credential_scope_denied',
    rateLimitRemaining: 4999,
  });
});

it('checks once at production startup without creating a grant or logging the credential', async () => {
  const before = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  const create = jest.fn();
  const service = new InstallerDownloadsService({
    installerDownloadGrant: { create },
  } as any);
  jest
    .spyOn(service, 'configuration')
    .mockReturnValue({ ...config, ready: true, sha256: 'a'.repeat(64) });
  const fetch = jest
    .spyOn(globalThis, 'fetch')
    .mockResolvedValue(
      new Response(
        JSON.stringify({
          message: 'Resource not accessible by personal access token',
        }),
        {
          status: 403,
          headers: {
            'content-type': 'application/json',
            'github-authentication-token-expiration': '2026-11-23T00:00:00Z',
          },
        },
      ),
    );
  const log = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => {});
  try {
    expect(service.onApplicationBootstrap()).toBeUndefined();
    await new Promise((resolve) => setImmediate(resolve));
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(create).not.toHaveBeenCalled();
    const output = JSON.stringify(log.mock.calls);
    expect(output).toContain('credential_scope_denied');
    expect(output).toContain('2026-11-23T00:00:00.000Z');
    expect(output).not.toMatch(
      /synthetic-storage-secret|Bearer|Resource not accessible|https:/,
    );
  } finally {
    if (before === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = before;
  }
});
