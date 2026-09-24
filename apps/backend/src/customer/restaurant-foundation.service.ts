import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID, createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { CustomerService } from './customer.service';
import type { CustomerPrincipal } from './customer-auth';
import { profileSelect } from '../venue-profile/venue-profile';

const order = [{ sortOrder: 'asc' as const }, { id: 'asc' as const }];
export async function catalog(tx: Prisma.TransactionClient, venueId: string) {
  return tx.menuCategory.findMany({
    where: { venueId },
    orderBy: order,
    include: {
      items: { orderBy: order, include: { variants: true } },
      subcategories: {
        orderBy: order,
        include: { items: { orderBy: order, include: { variants: true } } },
      },
    },
  });
}
function text(value: unknown, field: string) {
  if (typeof value !== 'string' || !value.trim() || value.length > 120)
    throw new BadRequestException(`Invalid ${field}`);
  return value.trim();
}
function number(value: unknown, field: string, integer = false) {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < 0 ||
    value > 1000000 ||
    (integer && !Number.isInteger(value))
  )
    throw new BadRequestException(`Invalid ${field}`);
  return value;
}
@Injectable()
export class RestaurantFoundationService {
  constructor(
    private readonly db: PrismaService,
    private readonly owners: CustomerService,
    private readonly entitlements: VenueEntitlementsService,
  ) {}
  async read(actor: CustomerPrincipal, venueId: string) {
    const venue = await this.owners.venue(actor, venueId);
    return {
      authority: venue.menuAuthority,
      editingEnabled: venue.cloudMenuEditingEnabled,
      revision: venue.catalogRevision,
      categories: await catalog(this.db, venueId),
    };
  }
  async save(
    actor: CustomerPrincipal,
    venueId: string,
    kind: string,
    body: Record<string, unknown>,
  ) {
    await this.owners.venue(actor, venueId);
    if (!body || typeof body !== 'object' || Array.isArray(body))
      throw new BadRequestException('Catalog object required');
    if (!['category', 'subcategory', 'item', 'variant'].includes(kind))
      throw new BadRequestException('Unknown catalog kind');
    const id = body.id === undefined ? randomUUID() : text(body.id, 'id');
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        id,
      )
    )
      throw new BadRequestException('Catalog id must be a UUID');
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const venue = await tx.venue.findUniqueOrThrow({
        where: { id: venueId },
      });
      if (venue.menuAuthority !== 'CLOUD')
        throw new ConflictException('Menu is managed in POS');
      if (!venue.cloudMenuEditingEnabled)
        throw new ConflictException('Dashboard menu editing is disabled');
      if (body.expectedRevision !== venue.catalogRevision)
        throw new ConflictException('Menu changed. Reload before saving.');
      const named = () => ({
        nameKa: text(body.nameKa, 'nameKa'),
        nameEn: text(body.nameEn, 'nameEn'),
        sortOrder: number(body.sortOrder ?? 0, 'sortOrder', true),
      });
      const category = async (value: unknown) => {
        const row = await tx.menuCategory.findFirst({
          where: { id: text(value, 'categoryId'), venueId },
        });
        if (!row) throw new NotFoundException('Category not found');
        return row;
      };
      if (kind === 'category') {
        const existing = await tx.menuCategory.findUnique({ where: { id } });
        if (existing && existing.venueId !== venueId)
          throw new NotFoundException('Category not found');
        const data = { ...named(), slug: existing?.slug ?? id };
        await tx.menuCategory.upsert({
          where: { id },
          create: { id, venueId, posMenuCategoryId: id, ...data },
          update: data,
        });
      } else if (kind === 'subcategory') {
        const parent = await category(body.categoryId);
        const existing = await tx.menuSubcategory.findUnique({
          where: { id },
          include: { category: true },
        });
        if (existing && existing.category.venueId !== venueId)
          throw new NotFoundException('Subcategory not found');
        const data = {
          ...named(),
          categoryId: parent.id,
          slug: existing?.slug ?? id,
        };
        await tx.menuSubcategory.upsert({
          where: { id },
          create: { id, posMenuSubcategoryId: id, ...data },
          update: data,
        });
      } else if (kind === 'item') {
        let categoryId: string | null = null,
          subcategoryId: string | null = null;
        if (body.subcategoryId) {
          const sub = await tx.menuSubcategory.findFirst({
            where: {
              id: text(body.subcategoryId, 'subcategoryId'),
              category: { venueId },
            },
          });
          if (!sub) throw new NotFoundException('Subcategory not found');
          subcategoryId = sub.id;
        } else categoryId = (await category(body.categoryId)).id;
        const existing = await tx.menuItem.findUnique({ where: { id } });
        if (existing && existing.venueId !== venueId)
          throw new NotFoundException('Item not found');
        if (typeof body.enabled !== 'boolean')
          throw new BadRequestException('enabled is required');
        const data = {
          ...named(),
          categoryId,
          subcategoryId,
          price: number(body.price, 'price'),
          enabled: body.enabled,
        };
        await tx.menuItem.upsert({
          where: { id },
          create: { id, venueId, posMenuItemId: id, ...data },
          update: data,
        });
      } else {
        const parent = await tx.menuItem.findFirst({
          where: { id: text(body.menuItemId, 'menuItemId'), venueId },
        });
        if (!parent) throw new NotFoundException('Item not found');
        const existing = await tx.menuItemVariant.findUnique({
          where: { id },
          include: { menuItem: true },
        });
        if (
          existing &&
          (existing.menuItem.venueId !== venueId ||
            existing.menuItemId !== parent.id)
        )
          throw new NotFoundException('Variant not found');
        const data = {
          size: number(body.size, 'size'),
          price: number(body.price, 'price'),
        };
        await tx.menuItemVariant.upsert({
          where: { id },
          create: { id, menuItemId: parent.id, posMenuVariantId: id, ...data },
          update: data,
        });
      }
      await tx.venue.update({
        where: { id: venueId },
        data: { catalogRevision: { increment: 1 } },
      });
      await tx.customerAuditEvent.create({
        data: {
          customerAccountId: actor.customerAccountId,
          action: `catalog.${kind}.saved`,
          targetType: 'RestaurantCatalog',
          targetId: id,
        },
      });
      return { id, revision: venue.catalogRevision + 1 };
    });
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
