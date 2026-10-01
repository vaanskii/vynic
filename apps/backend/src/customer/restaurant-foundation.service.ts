import { requireCommercialFeature } from '../entitlements/commercial-state';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { CustomerService } from './customer.service';
import type { CustomerPrincipal } from './customer-auth';
import { profileSelect } from '../venue-profile/venue-profile';
import { MenuCatalogService } from '../menu-catalog/menu-catalog.service';
import {
  activeCategory,
  activeSubcategory,
  activeMenuItem,
} from '../menu-catalog/menu-active';

const order = [{ sortOrder: 'asc' as const }, { id: 'asc' as const }];
export async function catalog(tx: Prisma.TransactionClient, venueId: string) {
  return tx.menuCategory.findMany({
    where: { venueId, ...activeCategory },
    orderBy: order,
    include: {
      items: {
        where: activeMenuItem,
        orderBy: order,
        include: { variants: { where: { retiredAt: null } } },
      },
      subcategories: {
        where: activeSubcategory,
        orderBy: order,
        include: {
          items: {
            where: activeMenuItem,
            orderBy: order,
            include: { variants: { where: { retiredAt: null } } },
          },
        },
      },
    },
  });
}
@Injectable()
export class RestaurantFoundationService {
  constructor(
    private readonly db: PrismaService,
    private readonly owners: CustomerService,
    private readonly entitlements: VenueEntitlementsService,
    private readonly catalogs: MenuCatalogService,
  ) {}
  async read(actor: CustomerPrincipal, venueId: string) {
    const venue = await this.owners.venue(actor, venueId);
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    const tree = await this.catalogs.tree(venueId);
    return {
      authority: venue.menuAuthority,
      editingEnabled: venue.cloudMenuEditingEnabled,
      // Without POS a POS authority is an unfinished operator setup, not POS.
      posIncluded: (await this.entitlements.planFeatures(venueId)).includes(
        'POS',
      ),
      // The Venue change sequence; each node carries its own `revision`.
      sequence: tree.sequence,
      categories: tree.categories,
    };
  }
  async retired(actor: CustomerPrincipal, venueId: string) {
    await this.owners.venue(actor, venueId);
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    return this.catalogs.retired(venueId);
  }
  /**
   * One owner catalog mutation (docs/CANONICAL_MENU_SYNC.md). The owner is
   * CustomerAccount -> OWNER membership -> Organization -> Venue; POS presence
   * never makes the Menu read-only, only the commercial editing permission.
   */
  async mutate(actor: CustomerPrincipal, venueId: string, body: unknown) {
    await this.owners.venue(actor, venueId);
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    return this.catalogs.apply(
      venueId,
      { type: 'CUSTOMER', id: actor.customerAccountId, source: 'DASHBOARD' },
      body,
      { requireOwnerEditing: true },
    );
  }
  async bootstrap(venueId: string, deviceId: string) {
    if (!(await this.entitlements.hasFeature(venueId, 'POS')))
      throw new ConflictException('POS entitlement required for bootstrap');
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const device = await tx.device.findFirst({
        where: { id: deviceId, venueId },
      });
      if (!device) throw new NotFoundException('Device not found');
      if (device.foundationBootstrap) return device.foundationBootstrap;
      const venue = await tx.venue.findUniqueOrThrow({
        where: { id: venueId },
      });
      if (venue.menuAuthority !== 'CLOUD' || device.firstSyncAt)
        throw new ConflictException(
          'Only a fresh device may import Cloud foundation',
        );
      const profile = await tx.venue.findUniqueOrThrow({
        where: { id: venueId },
        select: { ...profileSelect, timezone: true, currency: true },
      });
      const website = await tx.venueWebsiteConfig.findUnique({
        where: { venueId },
        select: { draft: true },
      });
      const payload = {
        version: 1,
        venueId,
        deviceId,
        authority: 'CLOUD',
        operationalActivationAllowed: false,
        catalogRevision: venue.catalogRevision,
        profile,
        website,
        categories: await catalog(tx, venueId),
      };
      const normalized = JSON.parse(JSON.stringify(payload));
      const result = {
        ...normalized,
        snapshotId: createHash('sha256')
          .update(JSON.stringify(normalized))
          .digest('hex'),
      };
      await tx.device.update({
        where: { id: deviceId },
        data: { foundationBootstrap: result },
      });
      return result;
    });
  }
}
