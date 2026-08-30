import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { PosSyncGuard } from './pos-sync.guard';

interface TestRequest {
  headers: Record<string, string | string[] | undefined>;
}

function contextWithHeaders(headers: TestRequest['headers']): ExecutionContext {
  const request: TestRequest = { headers };
  return {
    switchToHttp: () => ({
      getRequest: () => request,
    }),
  } as unknown as ExecutionContext;
}

describe('PosSyncGuard — legacy shared-key authentication', () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalSyncKey = process.env.POS_SYNC_API_KEY;

  afterEach(() => {
    if (originalNodeEnv === undefined) {
      delete process.env.NODE_ENV;
    } else {
      process.env.NODE_ENV = originalNodeEnv;
    }
    if (originalSyncKey === undefined) {
      delete process.env.POS_SYNC_API_KEY;
    } else {
      process.env.POS_SYNC_API_KEY = originalSyncKey;
    }
    jest.restoreAllMocks();
  });

  it('accepts the configured X-POS-Sync-Key', () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';

    const result = new PosSyncGuard().canActivate(
      contextWithHeaders({ 'x-pos-sync-key': 'legacy-secret' }),
    );

    expect(result).toBe(true);
  });

  it('trims the configured and provided key', () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = '  legacy-secret  ';

    const result = new PosSyncGuard().canActivate(
      contextWithHeaders({ 'X-POS-Sync-Key': ' legacy-secret ' }),
    );

    expect(result).toBe(true);
  });

  it('rejects an invalid shared key', () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';

    expect(() =>
      new PosSyncGuard().canActivate(
        contextWithHeaders({ 'x-pos-sync-key': 'wrong-secret' }),
      ),
    ).toThrow(new UnauthorizedException('Invalid or missing POS sync API key'));
  });

  it('rejects missing authentication when a shared key is configured', () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';

    expect(() =>
      new PosSyncGuard().canActivate(contextWithHeaders({})),
    ).toThrow(new UnauthorizedException('Invalid or missing POS sync API key'));
  });

  it('fails closed in production when the shared key is not configured', () => {
    process.env.NODE_ENV = 'production';
    delete process.env.POS_SYNC_API_KEY;

    expect(() =>
      new PosSyncGuard().canActivate(contextWithHeaders({})),
    ).toThrow(
      new UnauthorizedException(
        'POS sync API key is not configured on the server',
      ),
    );
  });

  it('retains the existing unauthenticated development fallback', () => {
    process.env.NODE_ENV = 'test';
    delete process.env.POS_SYNC_API_KEY;
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);

    const result = new PosSyncGuard().canActivate(contextWithHeaders({}));

    expect(result).toBe(true);
  });
});
