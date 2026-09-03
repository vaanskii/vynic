import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * Mirrors the POS menu tree onto the server.
 *
 * Four levels deep and identity-by-name: categories and subcategories match on
 * slug, items on (nameEn, parent), and variants are rewritten wholesale because
 * they carry no stable key. Payload position becomes `sortOrder`, which is how
 * the manager app reproduces the POS's ordering.
 *
 * Skipped entirely on the realtime fast path — the caller decides that.
 */
@Injectable()
export class MenuSyncService {
  constructor(private readonly prisma: PrismaService) {}

  async sync(tenant: TenantContext, menu: any[]): Promise<void> {
    console.log(`[SYNC] Syncing ${menu.length} categories...`);
    for (let catIndex = 0; catIndex < menu.length; catIndex++) {
      const cat = menu[catIndex];
      const category = await (this.prisma as any).menuCategory.upsert({
        where: {
          venueId_slug: { venueId: tenant.venueId, slug: cat.slug },
        },
        update: {
          nameKa: cat.nameKa,
          nameEn: cat.nameEn,
          sendToKitchen: cat.sendToKitchen,
          sortOrder: catIndex,
        },
        create: {
          venueId: tenant.venueId,
          slug: cat.slug,
          nameKa: cat.nameKa,
          nameEn: cat.nameEn,
          sendToKitchen: cat.sendToKitchen,
          sortOrder: catIndex,
        },
      });

      // Sync Subcategories
      if (cat.subcategories) {
        for (
          let subIndex = 0;
          subIndex < cat.subcategories.length;
          subIndex++
        ) {
          const sub = cat.subcategories[subIndex];
          const subcategory = await (this.prisma as any).menuSubcategory.upsert(
            {
              where: {
                slug_categoryId: { slug: sub.slug, categoryId: category.id },
              },
              update: {
                nameKa: sub.nameKa,
                nameEn: sub.nameEn,
                sortOrder: subIndex,
              },
              create: {
                slug: sub.slug,
                nameKa: sub.nameKa,
                nameEn: sub.nameEn,
                categoryId: category.id,
                sortOrder: subIndex,
              },
            },
          );

          if (sub.items) {
            for (let itemIndex = 0; itemIndex < sub.items.length; itemIndex++) {
              const it = sub.items[itemIndex];
              let existingItem = await (this.prisma as any).menuItem.findFirst({
                where: {
                  venueId: tenant.venueId,
                  nameEn: it.nameEn,
                  subcategoryId: subcategory.id,
                },
              });
              if (existingItem) {
                existingItem = await (this.prisma as any).menuItem.update({
                  where: { id: existingItem.id },
                  data: {
                    venueId: tenant.venueId,
                    nameKa: it.nameKa,
                    price: it.price,
                    sendToKitchen: it.sendToKitchen,
                    sortOrder: itemIndex,
                  },
                });
              } else {
                existingItem = await (this.prisma as any).menuItem.create({
                  data: {
                    venueId: tenant.venueId,
                    subcategoryId: subcategory.id,
                    nameKa: it.nameKa,
                    nameEn: it.nameEn,
                    price: it.price,
                    sendToKitchen: it.sendToKitchen,
                    sortOrder: itemIndex,
                  },
                });
              }

              // Sync Variants
              if (it.variants) {
                await (this.prisma as any).menuItemVariant.deleteMany({
                  where: { menuItemId: existingItem.id },
                });
                for (const v of it.variants) {
                  await (this.prisma as any).menuItemVariant.create({
                    data: {
                      menuItemId: existingItem.id,
                      size: v.size,
                      price: v.price,
                    },
                  });
                }
              }
            }
          }
        }
      }

      if (cat.items) {
        for (let itemIndex = 0; itemIndex < cat.items.length; itemIndex++) {
          const it = cat.items[itemIndex];
          let existingItem = await (this.prisma as any).menuItem.findFirst({
            where: {
              venueId: tenant.venueId,
              nameEn: it.nameEn,
              categoryId: category.id,
              subcategoryId: null,
            },
          });

          if (existingItem) {
            existingItem = await (this.prisma as any).menuItem.update({
              where: { id: existingItem.id },
              data: {
                venueId: tenant.venueId,
                nameKa: it.nameKa,
                price: it.price,
                sendToKitchen: it.sendToKitchen,
                sortOrder: itemIndex,
              },
            });
          } else {
            existingItem = await (this.prisma as any).menuItem.create({
              data: {
                venueId: tenant.venueId,
                categoryId: category.id,
                nameKa: it.nameKa,
                nameEn: it.nameEn,
                price: it.price,
                sendToKitchen: it.sendToKitchen,
                sortOrder: itemIndex,
              },
            });
          }

          // Sync Variants
          if (it.variants) {
            await (this.prisma as any).menuItemVariant.deleteMany({
              where: { menuItemId: existingItem.id },
            });
            for (const v of it.variants) {
              await (this.prisma as any).menuItemVariant.create({
                data: {
                  menuItemId: existingItem.id,
                  size: v.size,
                  price: v.price,
                },
              });
            }
          }
        }
      }
    }
  }
}
