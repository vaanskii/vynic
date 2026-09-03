import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import type { DeviceCredentialService } from '../auth/device-credential.service';
import { EdgeDeviceGuard } from './edge-device.guard';

function contextFor(headers: Record<string, string | undefined>) {
  const request: Record<string, unknown> = { headers };
  return {
    request,
    context: {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext,
  };
}

function credentialService(
  overrides: Partial<DeviceCredentialService> = {},
): DeviceCredentialService {
  return {
    isDeviceCredential: (value?: string) =>
      value?.startsWith('vynic-device-v1.') === true,
    verifyCredential: () => Promise.resolve(null),
    ...overrides,
  } as unknown as DeviceCredentialService;
}

describe('EdgeDeviceGuard', () => {
  it('establishes the device identity the queue routes by', async () => {
    const guard = new EdgeDeviceGuard(
      credentialService({
        verifyCredential: () =>
          Promise.resolve({
            authenticationMode: 'device',
            deviceId: 'device-a',
            venueId: 'venue-a',
            organizationId: 'org-1',
          }),
      }),
    );
    const { request, context } = contextFor({
      'x-pos-sync-key': 'vynic-device-v1.abc.def',
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.posAuthContext).toMatchObject({
      deviceId: 'device-a',
      venueId: 'venue-a',
    });
  });

  it('refuses the legacy shared key, which names no device', async () => {
    // The shared key resolves a Venue but not a machine, so it could neither be
    // routed to nor be held responsible for a lease.
    const guard = new EdgeDeviceGuard(credentialService());
    const { context } = contextFor({ 'x-pos-sync-key': 'legacy-shared-key' });

    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('refuses a missing credential', async () => {
    const guard = new EdgeDeviceGuard(credentialService());
    const { context } = contextFor({});

    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('refuses a credential the device service rejects', async () => {
    // Revoked device, disabled venue, or a wrong secret all land here.
    const guard = new EdgeDeviceGuard(credentialService());
    const { context } = contextFor({
      'x-pos-sync-key': 'vynic-device-v1.abc.def',
    });

    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
