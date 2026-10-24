import { Test } from '@nestjs/testing';
import request from 'supertest';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformVenuesController } from './platform-venues.controller';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { PlatformDirectoryService } from './platform-directory.service';
import { PlatformDeviceService } from './platform-device.service';
import type { PlatformPrincipal } from './platform-auth-context';

describe('Nonfiscal override authorization (HTTP)', () => {
  const venue = '00000000-0000-4000-8000-000000000001';
  const admin: PlatformPrincipal = {
    platformUserId: 'admin',
    role: 'SUPER_ADMIN',
    email: 'synthetic@test.invalid',
    displayName: 'Synthetic Admin',
  };
  let app: any;
  const config = {
    setFeatureOverride: jest.fn().mockResolvedValue({}),
    clearFeatureOverride: jest.fn().mockResolvedValue({}),
  };
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [PlatformVenuesController],
      providers: [
        PlatformAuthGuard,
        {
          provide: PlatformAuthService,
          useValue: {
            resolve: async (token: string) =>
              token === 'admin'
                ? admin
                : token === 'support'
                  ? { ...admin, role: 'SUPPORT_READONLY' }
                  : null,
          },
        },
        { provide: PlatformVenueConfigService, useValue: config },
        { provide: PlatformDirectoryService, useValue: {} },
        { provide: PlatformDeviceService, useValue: {} },
      ],
    }).compile();
    app = module.createNestApplication();
    await app.listen(0, '127.0.0.1');
  });
  afterAll(async () => app.close());
  beforeEach(() => jest.clearAllMocks());
  it.each(['owner', 'manager', 'device', 'anonymous', 'support'])(
    'refuses override writes from %s',
    async (token) => {
      const path = `/platform/venues/${venue}/features/NON_FISCAL_CLOSE`;
      const expected = token === 'support' ? 403 : 401;
      await request(app.getHttpServer())
        .put(path)
        .set('Authorization', `Bearer ${token}`)
        .send({ effect: 'ENABLED' })
        .expect(expected);
      await request(app.getHttpServer())
        .delete(path)
        .set('Authorization', `Bearer ${token}`)
        .expect(expected);
      expect(config.setFeatureOverride).not.toHaveBeenCalled();
      expect(config.clearFeatureOverride).not.toHaveBeenCalled();
    },
  );
  it('admits the existing platform SUPER_ADMIN', async () => {
    await request(app.getHttpServer())
      .put(`/platform/venues/${venue}/features/NON_FISCAL_CLOSE`)
      .set('Authorization', 'Bearer admin')
      .send({ effect: 'ENABLED' })
      .expect(200);
    expect(config.setFeatureOverride).toHaveBeenCalledWith(
      admin,
      venue,
      'NON_FISCAL_CLOSE',
      'ENABLED',
      undefined,
    );
  });
  it('also refuses a direct service call by a readonly principal before database access', async () => {
    const service = new PlatformVenueConfigService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );
    const support = { ...admin, role: 'SUPPORT_READONLY' } as PlatformPrincipal;
    await expect(
      service.setFeatureOverride(support, venue, 'NON_FISCAL_CLOSE', 'ENABLED'),
    ).rejects.toMatchObject({ status: 403 });
    await expect(
      service.clearFeatureOverride(support, venue, 'NON_FISCAL_CLOSE'),
    ).rejects.toMatchObject({ status: 403 });
  });
});
