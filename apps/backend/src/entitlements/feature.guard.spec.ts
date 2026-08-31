import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { PosAuthContext } from '../auth/pos-auth-context';
import { FeatureGuard } from './feature.guard';
import { FeatureKeys } from './feature-keys';
import { VenueEntitlementsService } from './venue-entitlements.service';

const VENUE_CONTEXT: PosAuthContext = {
  authenticationMode: 'device',
  deviceId: 'device-1',
  venueId: 'venue-a',
  organizationId: 'org-1',
};

function makeContext(posAuthContext?: PosAuthContext): ExecutionContext {
  return {
    getHandler: () => () => undefined,
    getClass: () => class {},
    switchToHttp: () => ({
      getRequest: () => ({ headers: {}, posAuthContext }),
    }),
  } as unknown as ExecutionContext;
}

function makeGuard(requiredFeature: string | undefined, entitled: string[]) {
  const reflector = {
    getAllAndOverride: jest.fn(() => requiredFeature),
  } as unknown as Reflector;
  const hasFeature = jest.fn((_venueId: string, key: string) =>
    Promise.resolve(entitled.includes(key)),
  );
  const entitlements = { hasFeature } as unknown as VenueEntitlementsService;
  return { guard: new FeatureGuard(reflector, entitlements), hasFeature };
}

describe('FeatureGuard', () => {
  it('allows the route when the venue holds the required feature', async () => {
    const { guard } = makeGuard(FeatureKeys.MANAGER_APP, [
      FeatureKeys.POS,
      FeatureKeys.MANAGER_APP,
    ]);

    await expect(guard.canActivate(makeContext(VENUE_CONTEXT))).resolves.toBe(
      true,
    );
  });

  it('denies the route when the venue does not hold it', async () => {
    const { guard } = makeGuard(FeatureKeys.MANAGER_APP, [FeatureKeys.POS]);

    await expect(
      guard.canActivate(makeContext(VENUE_CONTEXT)),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('leaves an unannotated route exactly as it was', async () => {
    const { guard, hasFeature } = makeGuard(undefined, []);

    await expect(guard.canActivate(makeContext(undefined))).resolves.toBe(true);
    expect(hasFeature).not.toHaveBeenCalled();
  });

  it('fails closed when no authenticated venue established a tenant', async () => {
    const { guard } = makeGuard(FeatureKeys.MANAGER_APP, [
      FeatureKeys.MANAGER_APP,
    ]);

    await expect(guard.canActivate(makeContext(undefined))).rejects.toThrow(
      'Feature access requires an authenticated venue',
    );
  });

  it('asks the one authoritative resolver rather than reading a plan itself', async () => {
    const { guard, hasFeature } = makeGuard(FeatureKeys.WEBSITE, [
      FeatureKeys.WEBSITE,
    ]);

    await guard.canActivate(makeContext(VENUE_CONTEXT));

    expect(hasFeature).toHaveBeenCalledWith('venue-a', FeatureKeys.WEBSITE);
  });
});
