import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { LEGACY_MANAGER_TENANT } from '../../tenancy/legacy-manager-tenant';
import { BootstrapService } from './bootstrap.service';
import { WEBSITE_TABLE_MAPPINGS } from './website-table-mappings';

describe('BootstrapService', () => {
  function setup(venue: { id: string } | null) {
    const prisma = {
      venue: { findUnique: jest.fn().mockResolvedValue(venue) },
      websiteTable: { upsert: jest.fn().mockResolvedValue({}) },
      websiteUser: {
        count: jest.fn().mockResolvedValue(0),
        upsert: jest.fn().mockResolvedValue({}),
      },
      menuItem: { count: jest.fn().mockResolvedValue(0) },
    };
    const service = new BootstrapService(
      prisma as unknown as PrismaService,
      { get: jest.fn().mockReturnValue(undefined) } as unknown as ConfigService,
    );
    return { prisma, service };
  }

  it('starts with no legacy Venue without creating tables or accounts', async () => {
    const { prisma, service } = setup(null);
    await expect(service.onModuleInit()).resolves.toBeUndefined();
    expect(prisma.venue.findUnique).toHaveBeenCalledWith({
      where: { id: LEGACY_MANAGER_TENANT.venueId },
      select: { id: true },
    });
    expect(prisma.websiteTable.upsert).not.toHaveBeenCalled();
    expect(prisma.websiteUser.count).not.toHaveBeenCalled();
    expect(prisma.websiteUser.upsert).not.toHaveBeenCalled();
    expect(prisma.menuItem.count).not.toHaveBeenCalled();
  });

  it('keeps website mappings scoped to the existing legacy Venue', async () => {
    const { prisma, service } = setup({ id: LEGACY_MANAGER_TENANT.venueId });
    await service.onModuleInit();
    expect(prisma.websiteTable.upsert).toHaveBeenCalledTimes(
      WEBSITE_TABLE_MAPPINGS.length,
    );
    for (const mapping of WEBSITE_TABLE_MAPPINGS) {
      expect(prisma.websiteTable.upsert).toHaveBeenCalledWith({
        where: {
          venueId_websiteTableNumber: {
            venueId: LEGACY_MANAGER_TENANT.venueId,
            websiteTableNumber: mapping.websiteTableNumber,
          },
        },
        create: { ...mapping, venueId: LEGACY_MANAGER_TENANT.venueId },
        update: {
          posTableNumber: mapping.posTableNumber,
          posFloor: mapping.posFloor,
          capacity: mapping.capacity,
        },
      });
    }
  });

  it('propagates database failures instead of treating them as a fresh install', async () => {
    const { prisma, service } = setup(null);
    prisma.venue.findUnique.mockRejectedValue(
      new Error('Database unavailable'),
    );
    await expect(service.onModuleInit()).rejects.toThrow(
      'Database unavailable',
    );
  });
});
