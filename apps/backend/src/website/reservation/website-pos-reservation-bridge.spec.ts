jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { ConflictException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type { PrismaService } from '../../prisma.service';
import { MenuService } from '../menu/menu.service';
import { WebsitePosReservationBridgeService } from './website-pos-reservation-bridge.service';

const tenant = { venueId: 'venue-a', organizationId: 'org-a' };

describe('website paid preorder POS projection', () => {
  function fixture(
    variant: { id: string; posMenuVariantId: string | null } | null,
  ) {
    const db = {
      menuItem: {
        findFirst: jest
          .fn()
          .mockResolvedValue({ id: 'cloud-item', posMenuItemId: 'pos-item' }),
      },
      menuItemVariant: { findFirst: jest.fn().mockResolvedValue(variant) },
    };
    const service = new WebsitePosReservationBridgeService(
      db as unknown as PrismaService,
      {} as never,
      new MenuService(db as unknown as PrismaService),
      {} as never,
      {} as never,
    );
    const projection = service as unknown as {
      buildPreOrderItems(
        context: typeof tenant,
        json: string,
        db: Prisma.TransactionClient,
      ): Promise<Record<string, unknown>[]>;
    };
    return {
      db,
      project: (lines: unknown[]) =>
        projection.buildPreOrderItems(
          tenant,
          JSON.stringify(lines),
          db as unknown as Prisma.TransactionClient,
        ),
    };
  }

  it('keeps the paid variant, frozen price and name while translating Cloud IDs to POS IDs', async () => {
    const { project } = fixture({
      id: 'cloud-large',
      posMenuVariantId: 'pos-large',
    });
    expect(
      await project([
        {
          id: 'cloud-item',
          variantId: 'cloud-large',
          name: 'Frozen drink 1L',
          price: 12.5,
          quantity: 2,
        },
      ]),
    ).toEqual([
      {
        itemKey: 'Frozen drink 1L_12.50',
        itemName: 'Frozen drink 1L',
        unitPrice: 12.5,
        quantity: 2,
        total: 25,
        comment: null,
        menuItemId: 'pos-item',
        variantId: 'pos-large',
      },
    ]);
  });

  it('refuses an unresolved variant instead of silently dispatching a base item', async () => {
    const { project } = fixture(null);
    await expect(
      project([
        {
          id: 'cloud-item',
          variantId: 'foreign',
          name: 'Frozen drink',
          price: 12.5,
          quantity: 1,
        },
      ]),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('keeps unvaried preorder payloads compatible', async () => {
    const { db, project } = fixture(null);
    expect(
      await project([
        {
          id: 'cloud-item',
          name: 'Frozen meal',
          price: 12.5,
          quantity: 1,
        },
      ]),
    ).toEqual([
      expect.objectContaining({
        menuItemId: 'pos-item',
        itemName: 'Frozen meal',
      }),
    ]);
    expect(db.menuItemVariant.findFirst).not.toHaveBeenCalled();
  });
});
