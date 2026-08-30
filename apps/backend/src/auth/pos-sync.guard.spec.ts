import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { DeviceCredentialService } from './device-credential.service';
import { PosAuthenticatedRequest, PosAuthContext } from './pos-auth-context';
import { PosSyncGuard } from './pos-sync.guard';

interface GuardHarness {
  context: ExecutionContext;
  request: PosAuthenticatedRequest;
}

function contextWithHeaders(
  headers: PosAuthenticatedRequest['headers'],
): GuardHarness {
  const request: PosAuthenticatedRequest = { headers };
  const context = {
    switchToHttp: () => ({
      getRequest: () => request,
    }),
  } as unknown as ExecutionContext;
  return { context, request };
}

function makeGuard(deviceContext: PosAuthContext | null = null): {
  guard: PosSyncGuard;
  verifyCredential: jest.Mock;
} {
  const verifyCredential = jest.fn(() => Promise.resolve(deviceContext));
  const deviceCredentials = {
    isDeviceCredential: (value: string | undefined) =>
      value?.startsWith('vynic-device-v1.') === true,
    verifyCredential,
  } as unknown as DeviceCredentialService;
  return {
    guard: new PosSyncGuard(deviceCredentials),
    verifyCredential,
  };
}

describe('PosSyncGuard — transitional authentication', () => {
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

  it('accepts the configured X-POS-Sync-Key and publishes legacy context', async () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';
    const { guard, verifyCredential } = makeGuard();
    const { context, request } = contextWithHeaders({
      'x-pos-sync-key': 'legacy-secret',
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);

    expect(request.posAuthContext).toEqual({
      authenticationMode: 'legacy_shared_key',
      deviceId: null,
    });
    expect(verifyCredential).not.toHaveBeenCalled();
  });

  it('trims the configured and provided legacy key', async () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = '  legacy-secret  ';
    const { guard } = makeGuard();
    const { context } = contextWithHeaders({
      'X-POS-Sync-Key': ' legacy-secret ',
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);
  });

  it('accepts a verified Device credential and publishes its Device id', async () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';
    const deviceContext: PosAuthContext = {
      authenticationMode: 'device',
      deviceId: 'device-1',
    };
    const { guard, verifyCredential } = makeGuard(deviceContext);
    const credential = 'vynic-device-v1.device-1.redacted-secret';
    const { context, request } = contextWithHeaders({
      'x-pos-sync-key': credential,
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);

    expect(verifyCredential).toHaveBeenCalledWith(credential);
    expect(request.posAuthContext).toEqual(deviceContext);
  });

  it('rejects a Device-shaped credential that does not verify', async () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';
    const { guard } = makeGuard(null);
    const { context } = contextWithHeaders({
      'x-pos-sync-key': 'vynic-device-v1.device-1.wrong-secret',
    });

    await expect(guard.canActivate(context)).rejects.toThrow(
      new UnauthorizedException('Invalid POS device credential'),
    );
  });

  it('rejects an invalid shared key', async () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';
    const { guard } = makeGuard();
    const { context } = contextWithHeaders({
      'x-pos-sync-key': 'wrong-secret',
    });

    await expect(guard.canActivate(context)).rejects.toThrow(
      new UnauthorizedException('Invalid or missing POS sync API key'),
    );
  });

  it('rejects missing authentication when a shared key is configured', async () => {
    process.env.NODE_ENV = 'production';
    process.env.POS_SYNC_API_KEY = 'legacy-secret';
    const { guard } = makeGuard();
    const { context } = contextWithHeaders({});

    await expect(guard.canActivate(context)).rejects.toThrow(
      new UnauthorizedException('Invalid or missing POS sync API key'),
    );
  });

  it('fails closed in production when the shared key is not configured', async () => {
    process.env.NODE_ENV = 'production';
    delete process.env.POS_SYNC_API_KEY;
    const { guard } = makeGuard();
    const { context } = contextWithHeaders({});

    await expect(guard.canActivate(context)).rejects.toThrow(
      new UnauthorizedException(
        'POS sync API key is not configured on the server',
      ),
    );
  });

  it('retains the existing unauthenticated development fallback', async () => {
    process.env.NODE_ENV = 'test';
    delete process.env.POS_SYNC_API_KEY;
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const { guard } = makeGuard();
    const { context, request } = contextWithHeaders({});

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.posAuthContext).toEqual({
      authenticationMode: 'legacy_shared_key',
      deviceId: null,
    });
  });
});
