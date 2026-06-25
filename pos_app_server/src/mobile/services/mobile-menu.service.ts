import {
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';
import { PrismaService } from '../../prisma.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { PosCallbackClient } from '../../pos/pos-callback.client';
import { readRestaurantServiceFeeSettings } from '../util/mobile-date.util';

/** WS exclude options for the REST client that initiated a mutation. */
type BroadcastExclude = { excludeSocketIds: string[] } | undefined;

/**
 * Menu + counted-menu (quick-order draft) endpoints for the mobile manager app
 * (`/mobile/menu`, `/mobile/counted-menus`, `/mobile/counted-menu/save`,
 * `/mobile/counted-menu/:id/delete`).
 *
 * Extracted verbatim from MobileController; behavior unchanged. The controller
 * keeps the route decorators and passes the computed WS exclude-opts in (the
 * shared echo/exclude glue stays on the controller until MobileMutationSupport
 * is extracted).
 */
@Injectable()
export class MobileMenuService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly posCallback: PosCallbackClient,
  ) {}

  async getMenu() {
    const cats = await (this.prisma as any).menuCategory.findMany({
      include: {
        items: {
          include: { variants: true },
          orderBy: { sortOrder: 'asc' },
        },
        subcategories: {
          include: {
            items: {
              include: { variants: true },
              orderBy: { sortOrder: 'asc' },
            },
          },
          orderBy: { sortOrder: 'asc' },
        },
      },
      orderBy: { sortOrder: 'asc' },
    });
    return cats.map((cat: any) => ({
      slug: cat.slug,
      nameEn: cat.nameEn,
      nameKa: cat.nameKa,
      sendToKitchen: cat.sendToKitchen,
      items: (cat.items ?? []).map((it: any) => ({
        nameEn: it.nameEn,
        nameKa: it.nameKa,
        price: Math.round(it.price * 100) / 100,
        sendToKitchen: it.sendToKitchen,
        variants: (it.variants ?? []).map((v: any) => ({
          size: v.size,
          price: v.price,
        })),
      })),
      subcategories: (cat.subcategories ?? []).map((sub: any) => ({
        slug: sub.slug,
        nameEn: sub.nameEn,
        nameKa: sub.nameKa,
        items: (sub.items ?? []).map((it: any) => ({
          nameEn: it.nameEn,
          nameKa: it.nameKa,
          price: Math.round(it.price * 100) / 100,
          sendToKitchen: it.sendToKitchen,
          variants: (it.variants ?? []).map((v: any) => ({
            size: v.size,
            price: v.price,
          })),
        })),
      })),
    }));
  }

  async getCountedMenus() {
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const drafts = await (this.prisma as any).quickOrderDraft.findMany({
      include: { items: true },
      orderBy: { createdAt: 'desc' },
    });

    return drafts.map((d: any) => {
      const subtotal = Number(d.subtotal);
      const includeServiceFee =
        feeSettings.serviceFeeAvailable && d.includeServiceFee === true;
      const serviceFeeRate = includeServiceFee
        ? Number(d.serviceFeeRate ?? feeSettings.serviceFeePercent / 100)
        : 0;
      const serviceFeeAmount = includeServiceFee
        ? Math.round(subtotal * serviceFeeRate * 100) / 100
        : 0;
      const total = Math.round((subtotal + serviceFeeAmount) * 100) / 100;

      return {
        id: d.draftId,
        displayName: d.displayName,
        subtotal,
        serviceFeeAmount,
        total,
        includeServiceFee,
        serviceFeeRate,
        createdAt: d.createdAt.toISOString(),
        createdBy: d.createdBy,
        items: d.items.map((it: any) => ({
          itemName: it.name,
          quantity: it.quantity,
          unitPrice: it.price,
          total: it.quantity * it.price,
          comment: it.comment,
        })),
      };
    });
  }

  async saveCountedMenu(data: any, excludeOpts: BroadcastExclude) {
    const { displayName, items, subtotal, includeServiceFee, createdBy } = data;
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const shouldInclude =
      feeSettings.serviceFeeAvailable && includeServiceFee === true;
    const serviceFeeRate = feeSettings.serviceFeeAvailable
      ? feeSettings.serviceFeePercent / 100
      : 0;
    const serviceFeeAmount = shouldInclude ? subtotal * serviceFeeRate : 0;
    const total = subtotal + serviceFeeAmount;

    const dbDraft = await (this.prisma as any).quickOrderDraft.create({
      data: {
        draftId: uuidv4(),
        displayName,
        subtotal,
        serviceFeeAmount,
        total,
        includeServiceFee: shouldInclude,
        serviceFeeRate,
        createdBy,
        createdAt: new Date(),
      },
    });

    for (const item of items) {
      await (this.prisma as any).quickOrderDraftItem.create({
        data: {
          draftId: dbDraft.id,
          name: item.itemName,
          quantity: item.quantity,
          price: item.unitPrice,
          comment: item.comment,
        },
      });
    }

    this.gateway.broadcastUpdate(
      'data_updated',
      { type: 'all' },
      excludeOpts,
    );
    return { success: true, id: dbDraft.draftId };
  }

  async deleteCountedMenu(id: string, excludeOpts: BroadcastExclude) {
    await (this.prisma as any).quickOrderDraft.delete({
      where: { draftId: id },
    });
    this.gateway.broadcastUpdate(
      'data_updated',
      { type: 'all' },
      excludeOpts,
    );
    return { success: true };
  }

  /**
   * Edit an existing counted menu (quick-order draft) in place. Postgres only —
   * NOT synced to the Windows POS Hive. Recomputes service fee / total exactly
   * like saveCountedMenu, then replaces the draft's items atomically. Returns a
   * clean 404 if the draft no longer exists.
   */
  async updateCountedMenu(
    id: string,
    data: any,
    excludeOpts: BroadcastExclude,
  ) {
    const { displayName, items, subtotal, includeServiceFee } = data;

    const existing = await (this.prisma as any).quickOrderDraft.findUnique({
      where: { draftId: id },
    });
    if (!existing) {
      throw new NotFoundException('Counted menu not found');
    }

    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const shouldInclude =
      feeSettings.serviceFeeAvailable && includeServiceFee === true;
    const serviceFeeRate = feeSettings.serviceFeeAvailable
      ? feeSettings.serviceFeePercent / 100
      : 0;
    const serviceFeeAmount = shouldInclude ? subtotal * serviceFeeRate : 0;
    const total = subtotal + serviceFeeAmount;

    // Update the draft header, then replace its items (delete + recreate) so the
    // stored lines exactly match the edited cart. Scoped to this draft's id.
    await (this.prisma as any).quickOrderDraft.update({
      where: { id: existing.id },
      data: {
        displayName,
        subtotal,
        serviceFeeAmount,
        total,
        includeServiceFee: shouldInclude,
        serviceFeeRate,
      },
    });

    await (this.prisma as any).quickOrderDraftItem.deleteMany({
      where: { draftId: existing.id },
    });
    for (const item of items ?? []) {
      await (this.prisma as any).quickOrderDraftItem.create({
        data: {
          draftId: existing.id,
          name: item.itemName,
          quantity: item.quantity,
          price: item.unitPrice,
          comment: item.comment,
        },
      });
    }

    this.gateway.broadcastUpdate(
      'data_updated',
      { type: 'all' },
      excludeOpts,
    );
    return { success: true, id: existing.draftId };
  }

  /**
   * Relay a counted-menu receipt print to the Windows POS — the only print
   * host — via the direct POS callback path. Loads the draft from Postgres and
   * sends its full payload (the POS doesn't reliably have the draft in Hive).
   * No realtime broadcast: printing is not a data mutation. Missing draft → 404;
   * unreachable POS → 503.
   */
  async printCountedMenu(id: string): Promise<{ success: true }> {
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const draft = await (this.prisma as any).quickOrderDraft.findUnique({
      where: { draftId: id },
      include: { items: true },
    });
    if (!draft) {
      throw new NotFoundException('Counted menu not found');
    }

    // Recompute totals exactly like getCountedMenus so the printed receipt
    // matches what the manager app shows.
    const subtotal = Number(draft.subtotal);
    const includeServiceFee =
      feeSettings.serviceFeeAvailable && draft.includeServiceFee === true;
    const serviceFeeRate = includeServiceFee
      ? Number(draft.serviceFeeRate ?? feeSettings.serviceFeePercent / 100)
      : 0;
    const serviceFeeAmount = includeServiceFee
      ? Math.round(subtotal * serviceFeeRate * 100) / 100
      : 0;
    const total = Math.round((subtotal + serviceFeeAmount) * 100) / 100;

    const payload = {
      displayName: draft.displayName,
      subtotal,
      serviceFeeAmount,
      total,
      includeServiceFee,
      serviceFeeRate,
      items: (draft.items ?? []).map((it: any) => ({
        itemName: it.name,
        quantity: it.quantity,
        unitPrice: it.price,
        total: it.quantity * it.price,
        comment: it.comment,
      })),
    };

    try {
      await this.posCallback.printPosCountedMenu(payload);
    } catch (e) {
      throw new ServiceUnavailableException(
        `Could not print counted menu — is the Windows POS running? (${(e as Error).message})`,
      );
    }
    return { success: true };
  }
}
