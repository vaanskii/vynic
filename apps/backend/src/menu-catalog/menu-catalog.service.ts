import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { MenuEntityKind, MenuMutationActor, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import {
  normalizeMutation,
  requestHash,
  type MenuMutation,
  type MenuPatch,
} from './menu-mutation';

/**
 * The canonical converged Restaurant Menu (docs/CANONICAL_MENU_SYNC.md, D030).
 *
 * Every writer — the owner Dashboard, ANY enrolled POS Device of the Venue (no
 * primary requirement), and later a permissioned Manager — submits the same
 * entity mutation. Each node carries its own revision, so edits to different
 * products never conflict; `Venue.catalogRevision` is only the Venue's change
 * sequence for catch-up. Accepted mutations are recorded once per
 * (Venue, mutationId): a retry replays the stored result and writes nothing.
 * A stale revision is an explicit conflict carrying the current node; it never
 * overwrites. Deletion writes a tombstone; omission never deletes.
 *
 * Tenancy is resolved by the caller (Device -> Venue, CustomerAccount ->
 * membership -> Venue, Staff -> Venue). Every lookup here is Venue-scoped, so a
 * mutation or conflict can never read or touch another Venue's node.
 */
export interface MenuActor {
  type: MenuMutationActor;
  id: string;
  /** POS, DASHBOARD, MANAGER, PLATFORM, SYSTEM. */
  source: string;
}

export type CatalogNode = Record<string, unknown> & {
  id: string;
  revision: number;
  changeSeq: number;
};

export interface MutationAccepted {
  status: 'ACCEPTED';
  duplicate: boolean;
  mutationId: string;
  entityType: MenuEntityKind;
  entityId: string;
  operation: 'UPSERT' | 'DELETE';
  revision: number;
  sequence: number;
  deleted: boolean;
  entity: CatalogNode | null;
}

const byOrder = <T extends { sortOrder?: number | null; id: string }>(
  a: T,
  b: T,
) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0) || a.id.localeCompare(b.id);

type Tx = Prisma.TransactionClient;

/** Protocol identity: the stable offline id, or the row key for a Cloud-born node. */
const key = (posId: string | null, id: string) => posId ?? id;

@Injectable()
export class MenuCatalogService {
  constructor(private readonly db: PrismaService) {}

  // ---------------------------------------------------------------- reads

  private async rows(tx: Tx, venueId: string) {
    const [categories, subcategories, items, variants] = await Promise.all([
      tx.menuCategory.findMany({ where: { venueId } }),
      tx.menuSubcategory.findMany({ where: { category: { venueId } } }),
      tx.menuItem.findMany({ where: { venueId } }),
      tx.menuItemVariant.findMany({ where: { menuItem: { venueId } } }),
    ]);
    const catKey = new Map(
      categories.map((c) => [c.id, key(c.posMenuCategoryId, c.id)]),
    );
    const subKey = new Map(
      subcategories.map((s) => [s.id, key(s.posMenuSubcategoryId, s.id)]),
    );
    const itemKey = new Map(
      items.map((i) => [i.id, key(i.posMenuItemId, i.id)]),
    );
    return {
      categories: categories.map((c) => this.category(c)).sort(byOrder),
      subcategories: subcategories
        .map((s) => this.subcategory(s, catKey.get(s.categoryId)!))
        .sort(byOrder),
      items: items
        .map((i) =>
          this.item(
            i,
            i.categoryId ? (catKey.get(i.categoryId) ?? null) : null,
            i.subcategoryId ? (subKey.get(i.subcategoryId) ?? null) : null,
          ),
        )
        .sort(byOrder),
      variants: variants
        .map((v) => this.variant(v, itemKey.get(v.menuItemId)!))
        .sort(
          (a, b) =>
            (a.size as number) - (b.size as number) || a.id.localeCompare(b.id),
        ),
    };
  }

  private category(c: {
    id: string;
    posMenuCategoryId: string | null;
    slug: string;
    nameKa: string;
    nameEn: string;
    sendToKitchen: boolean;
    sortOrder: number;
    revision: number;
    changeSeq: number;
  }): CatalogNode {
    return {
      id: key(c.posMenuCategoryId, c.id),
      slug: c.slug,
      nameKa: c.nameKa,
      nameEn: c.nameEn,
      sendToKitchen: c.sendToKitchen,
      sortOrder: c.sortOrder,
      revision: c.revision,
      changeSeq: c.changeSeq,
    };
  }
  private subcategory(
    s: {
      id: string;
      posMenuSubcategoryId: string | null;
      slug: string;
      nameKa: string;
      nameEn: string;
      sortOrder: number;
      revision: number;
      changeSeq: number;
    },
    categoryId: string,
  ): CatalogNode {
    return {
      id: key(s.posMenuSubcategoryId, s.id),
      categoryId,
      slug: s.slug,
      nameKa: s.nameKa,
      nameEn: s.nameEn,
      sortOrder: s.sortOrder,
      revision: s.revision,
      changeSeq: s.changeSeq,
    };
  }
  private item(
    i: {
      id: string;
      posMenuItemId: string | null;
      nameKa: string;
      nameEn: string;
      price: number;
      enabled: boolean;
      sendToKitchen: boolean;
      sortOrder: number;
      revision: number;
      changeSeq: number;
    },
    categoryId: string | null,
    subcategoryId: string | null,
  ): CatalogNode {
    return {
      id: key(i.posMenuItemId, i.id),
      categoryId,
      subcategoryId,
      nameKa: i.nameKa,
      nameEn: i.nameEn,
      price: i.price,
      enabled: i.enabled,
      sendToKitchen: i.sendToKitchen,
      sortOrder: i.sortOrder,
      revision: i.revision,
      changeSeq: i.changeSeq,
    };
  }
  private variant(
    v: {
      id: string;
      posMenuVariantId: string | null;
      size: number;
      price: number;
      revision: number;
      changeSeq: number;
    },
    menuItemId: string,
  ): CatalogNode {
    return {
      id: key(v.posMenuVariantId, v.id),
      menuItemId,
      size: v.size,
      price: v.price,
      revision: v.revision,
      changeSeq: v.changeSeq,
    };
  }

  private async venue(tx: Tx, venueId: string) {
    const venue = await tx.venue.findUnique({
      where: { id: venueId },
      select: {
        id: true,
        menuAuthority: true,
        catalogRevision: true,
        cloudMenuEditingEnabled: true,
      },
    });
    if (!venue) throw new NotFoundException('Restaurant not found');
    return venue;
  }

  /** Complete versioned catalog: stable ids, entity revisions and the change sequence. */
  async snapshot(venueId: string) {
    return this.db.$transaction(
      async (tx) => {
        const venue = await this.venue(tx, venueId);
        return {
          version: 2,
          venueId,
          authority: venue.menuAuthority,
          sequence: venue.catalogRevision,
          ...(await this.rows(tx, venueId)),
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }

  /**
   * Everything that changed after `since`: current nodes with changeSeq > since
   * and tombstones with seq > since. A client at sequence X reaches Y by
   * applying upserts then tombstones; a `since` beyond the Venue's sequence
   * (a reset server) asks the client to re-bootstrap instead of guessing.
   */
  async changes(venueId: string, since: number) {
    if (!Number.isInteger(since) || since < 0)
      throw new BadRequestException('since must be a non-negative integer');
    return this.db.$transaction(
      async (tx) => {
        const venue = await this.venue(tx, venueId);
        if (since > venue.catalogRevision)
          throw new ConflictException({
            code: 'RESYNC_REQUIRED',
            message: 'Catalog sequence is behind the client; bootstrap again',
            sequence: venue.catalogRevision,
          });
        const all = await this.rows(tx, venueId);
        const changed = (rows: CatalogNode[]) =>
          rows.filter((row) => row.changeSeq > since);
        const tombstones = await tx.menuCatalogTombstone.findMany({
          where: { venueId, seq: { gt: since } },
          orderBy: { seq: 'asc' },
          select: {
            entityType: true,
            entityId: true,
            seq: true,
            revision: true,
          },
        });
        return {
          version: 2,
          venueId,
          authority: venue.menuAuthority,
          since,
          sequence: venue.catalogRevision,
          categories: changed(all.categories),
          subcategories: changed(all.subcategories),
          items: changed(all.items),
          variants: changed(all.variants),
          tombstones,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }

  /** The owner Dashboard tree, built from the same protocol identities. */
  async tree(venueId: string) {
    const flat = await this.snapshot(venueId);
    const variants = (itemId: string) =>
      flat.variants.filter((v) => v.menuItemId === itemId);
    const items = (where: (i: CatalogNode) => boolean) =>
      flat.items.filter(where).map((i) => ({ ...i, variants: variants(i.id) }));
    return {
      sequence: flat.sequence,
      categories: flat.categories.map((c) => ({
        ...c,
        items: items((i) => i.categoryId === c.id),
        subcategories: flat.subcategories
          .filter((s) => s.categoryId === c.id)
          .map((s) => ({
            ...s,
            items: items((i) => i.subcategoryId === s.id),
          })),
      })),
    };
  }

  // ------------------------------------------------------------- mutation

  private async find(
    tx: Tx,
    venueId: string,
    kind: MenuEntityKind,
    id: string,
  ) {
    switch (kind) {
      case 'CATEGORY':
        return tx.menuCategory.findFirst({
          where: {
            venueId,
            OR: [{ posMenuCategoryId: id }, { posMenuCategoryId: null, id }],
          },
        });
      case 'SUBCATEGORY':
        return tx.menuSubcategory.findFirst({
          where: {
            category: { venueId },
            OR: [
              { posMenuSubcategoryId: id },
              { posMenuSubcategoryId: null, id },
            ],
          },
          include: { category: true },
        });
      case 'ITEM':
        return tx.menuItem.findFirst({
          where: {
            venueId,
            OR: [{ posMenuItemId: id }, { posMenuItemId: null, id }],
          },
          include: { category: true, subcategory: true },
        });
      case 'VARIANT':
        return tx.menuItemVariant.findFirst({
          where: {
            menuItem: { venueId },
            OR: [{ posMenuVariantId: id }, { posMenuVariantId: null, id }],
          },
          include: { menuItem: true },
        });
    }
  }

  /** A created node's row key is its UUID; one already used anywhere is unavailable. */
  private async idTaken(tx: Tx, kind: MenuEntityKind, id: string) {
    const where = { id };
    const count =
      kind === 'CATEGORY'
        ? await tx.menuCategory.count({ where })
        : kind === 'SUBCATEGORY'
          ? await tx.menuSubcategory.count({ where })
          : kind === 'ITEM'
            ? await tx.menuItem.count({ where })
            : await tx.menuItemVariant.count({ where });
    return count > 0;
  }

  private reject(code: string, message: string): never {
    throw new ConflictException({ code, message });
  }

  private conflict(
    m: MenuMutation,
    currentRevision: number,
    current: CatalogNode | null,
    deleted: boolean,
  ): never {
    throw new ConflictException({
      code: 'REVISION_CONFLICT',
      message: 'This item was changed on another device.',
      conflict: {
        mutationId: m.mutationId,
        entityType: m.entityType,
        entityId: m.entityId,
        operation: m.operation,
        expectedRevision: m.expectedRevision,
        currentRevision,
        deleted,
        current,
        pending: m.patch,
      },
    });
  }

  private async parentCategory(tx: Tx, venueId: string, id: string) {
    const row = await this.find(tx, venueId, 'CATEGORY', id);
    if (!row) this.reject('PARENT_MISSING', 'Category not found');
    return row as { id: string };
  }

  private async uniqueSlug(
    taken: (slug: string) => Promise<boolean>,
    wanted: string,
    id: string,
  ) {
    if (!(await taken(wanted))) return wanted;
    return `${wanted}-${id.slice(0, 8)}`;
  }

  private changed(
    before: Record<string, unknown>,
    after: Record<string, unknown>,
  ) {
    const out: Record<string, { from: unknown; to: unknown }> = {};
    for (const [field, value] of Object.entries(after))
      if (before[field] !== value)
        out[field] = { from: before[field] ?? null, to: value };
    return out;
  }

  /**
   * Applies one mutation atomically under the Venue row lock.
   * `requireOwnerEditing` enforces the owner's commercial editing permission;
   * Device and system writers are not gated by it (POS presence never decides
   * authority, and commercial state never blocks a restaurant's own terminals).
   */
  async apply(
    venueId: string,
    actor: MenuActor,
    raw: unknown,
    options: { requireOwnerEditing?: boolean } = {},
  ): Promise<MutationAccepted> {
    const m = normalizeMutation(raw);
    const hash = requestHash(m);
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const venue = await this.venue(tx, venueId);
      if (venue.menuAuthority !== 'CLOUD')
        this.reject(
          'LEGACY_POS_MENU',
          'This restaurant menu is still in POS compatibility mode',
        );
      if (options.requireOwnerEditing && !venue.cloudMenuEditingEnabled)
        this.reject('EDITING_DISABLED', 'Dashboard menu editing is disabled');

      const prior = await tx.menuCatalogMutation.findUnique({
        where: { venueId_mutationId: { venueId, mutationId: m.mutationId } },
      });
      if (prior) {
        if (prior.requestHash !== hash)
          this.reject(
            'MUTATION_ID_REUSED',
            'This mutation id was already used for a different change',
          );
        const current = await this.find(
          tx,
          venueId,
          prior.entityType,
          prior.entityId,
        );
        return {
          status: 'ACCEPTED',
          duplicate: true,
          mutationId: prior.mutationId,
          entityType: prior.entityType,
          entityId: prior.entityId,
          operation: prior.operation as 'UPSERT' | 'DELETE',
          revision: prior.resultRevision,
          sequence: prior.seq,
          deleted: prior.operation === 'DELETE',
          entity: current
            ? await this.node(tx, venueId, prior.entityType, prior.entityId)
            : null,
        };
      }

      const current = await this.find(tx, venueId, m.entityType, m.entityId);
      const tombstone = current
        ? null
        : await tx.menuCatalogTombstone.findUnique({
            where: { venueId_entityId: { venueId, entityId: m.entityId } },
          });
      let seq = venue.catalogRevision;
      const next = () => (seq = venue.catalogRevision + 1);
      let revision: number;
      let changes: Record<string, unknown> = {};
      let deleted = false;

      if (m.operation === 'DELETE') {
        if (!current) {
          // Idempotent: already deleted (tombstone) or never existed here.
          revision = tombstone?.revision ?? 0;
          deleted = true;
          changes = { alreadyDeleted: true };
        } else {
          if (current.revision !== m.expectedRevision)
            this.conflict(
              m,
              current.revision,
              await this.node(tx, venueId, m.entityType, m.entityId),
              false,
            );
          next();
          revision = current.revision + 1;
          deleted = true;
          changes = await this.remove(tx, venueId, m, current, seq);
        }
      } else if (!current) {
        if (tombstone) this.conflict(m, tombstone.revision, null, true);
        if (m.expectedRevision !== 0) this.conflict(m, 0, null, false);
        if (await this.idTaken(tx, m.entityType, m.entityId))
          this.reject('ID_UNAVAILABLE', 'This catalog id cannot be used');
        next();
        revision = 1;
        changes = await this.create(tx, venueId, m, seq);
      } else {
        if (current.revision !== m.expectedRevision)
          this.conflict(
            m,
            current.revision,
            await this.node(tx, venueId, m.entityType, m.entityId),
            false,
          );
        const diff = await this.update(
          tx,
          venueId,
          m,
          current,
          venue.catalogRevision + 1,
        );
        if (Object.keys(diff).length) {
          next();
          revision = current.revision + 1;
        } else revision = current.revision;
        changes = diff;
      }

      if (seq !== venue.catalogRevision)
        await tx.venue.update({
          where: { id: venueId },
          data: { catalogRevision: seq },
        });
      await tx.menuCatalogMutation.create({
        data: {
          venueId,
          mutationId: m.mutationId,
          entityType: m.entityType,
          entityId: m.entityId,
          operation: m.operation,
          expectedRevision: m.expectedRevision,
          resultRevision: revision,
          seq,
          actorType: actor.type,
          actorId: actor.id,
          source: actor.source,
          requestHash: hash,
          changes: changes as Prisma.InputJsonValue,
          resolution: m.resolution,
        },
      });
      if (actor.type === 'CUSTOMER' && seq !== venue.catalogRevision)
        await tx.customerAuditEvent.create({
          data: {
            customerAccountId: actor.id,
            action: `catalog.${m.entityType.toLowerCase()}.${m.operation === 'DELETE' ? 'deleted' : 'saved'}`,
            targetType: 'RestaurantCatalog',
            targetId: m.entityId,
            metadata: { mutationId: m.mutationId, revision, sequence: seq },
          },
        });
      return {
        status: 'ACCEPTED',
        duplicate: false,
        mutationId: m.mutationId,
        entityType: m.entityType,
        entityId: m.entityId,
        operation: m.operation,
        revision,
        sequence: seq,
        deleted,
        entity: deleted
          ? null
          : await this.node(tx, venueId, m.entityType, m.entityId),
      };
    });
  }

  private async node(
    tx: Tx,
    venueId: string,
    kind: MenuEntityKind,
    id: string,
  ) {
    const all = await this.rows(tx, venueId);
    const list =
      kind === 'CATEGORY'
        ? all.categories
        : kind === 'SUBCATEGORY'
          ? all.subcategories
          : kind === 'ITEM'
            ? all.items
            : all.variants;
    return list.find((row) => row.id === id) ?? null;
  }

  private required(m: MenuMutation, fields: (keyof MenuPatch)[]) {
    for (const field of fields)
      if (m.patch[field] === undefined)
        throw new BadRequestException({
          code: 'INVALID_MUTATION',
          message: `${field} is required to create a ${m.entityType.toLowerCase()}`,
        });
    if (
      (fields.includes('nameKa') || fields.includes('nameEn')) &&
      !m.patch.nameKa &&
      !m.patch.nameEn
    )
      throw new BadRequestException({
        code: 'INVALID_MUTATION',
        message: 'A name is required',
      });
  }

  private async itemParent(tx: Tx, venueId: string, patch: MenuPatch) {
    if (patch.subcategoryId) {
      const sub = await this.find(
        tx,
        venueId,
        'SUBCATEGORY',
        patch.subcategoryId,
      );
      if (!sub) this.reject('PARENT_MISSING', 'Subcategory not found');
      return { categoryId: null, subcategoryId: sub.id };
    }
    if (patch.categoryId)
      return {
        categoryId: (await this.parentCategory(tx, venueId, patch.categoryId))
          .id,
        subcategoryId: null,
      };
    return null;
  }

  private async create(tx: Tx, venueId: string, m: MenuMutation, seq: number) {
    const p = m.patch;
    const id = m.entityId;
    const meta = { revision: 1, changeSeq: seq };
    if (m.entityType === 'CATEGORY') {
      this.required(m, ['nameKa', 'nameEn']);
      const slug = await this.uniqueSlug(
        async (s) =>
          (await tx.menuCategory.count({ where: { venueId, slug: s } })) > 0,
        p.slug ?? id,
        id,
      );
      const data = {
        nameKa: p.nameKa ?? '',
        nameEn: p.nameEn ?? '',
        slug,
        sortOrder: p.sortOrder ?? 0,
        sendToKitchen: p.sendToKitchen ?? true,
      };
      await tx.menuCategory.create({
        data: { id, venueId, posMenuCategoryId: id, ...data, ...meta },
      });
      return { created: data };
    }
    if (m.entityType === 'SUBCATEGORY') {
      this.required(m, ['categoryId', 'nameKa', 'nameEn']);
      const parent = await this.parentCategory(tx, venueId, p.categoryId!);
      const slug = await this.uniqueSlug(
        async (s) =>
          (await tx.menuSubcategory.count({
            where: { categoryId: parent.id, slug: s },
          })) > 0,
        p.slug ?? id,
        id,
      );
      const data = {
        nameKa: p.nameKa ?? '',
        nameEn: p.nameEn ?? '',
        slug,
        sortOrder: p.sortOrder ?? 0,
      };
      await tx.menuSubcategory.create({
        data: {
          id,
          categoryId: parent.id,
          posMenuSubcategoryId: id,
          ...data,
          ...meta,
        },
      });
      return { created: { ...data, categoryId: p.categoryId } };
    }
    if (m.entityType === 'ITEM') {
      this.required(m, ['nameKa', 'nameEn', 'price']);
      const parent = await this.itemParent(tx, venueId, p);
      if (!parent)
        throw new BadRequestException({
          code: 'INVALID_MUTATION',
          message: 'categoryId or subcategoryId is required to create an item',
        });
      const data = {
        nameKa: p.nameKa ?? '',
        nameEn: p.nameEn ?? '',
        price: p.price!,
        enabled: p.enabled ?? true,
        sendToKitchen: p.sendToKitchen ?? true,
        sortOrder: p.sortOrder ?? 0,
      };
      await tx.menuItem.create({
        data: { id, venueId, posMenuItemId: id, ...parent, ...data, ...meta },
      });
      return {
        created: {
          ...data,
          categoryId: p.categoryId ?? null,
          subcategoryId: p.subcategoryId ?? null,
        },
      };
    }
    this.required(m, ['menuItemId', 'size', 'price']);
    const item = await this.find(tx, venueId, 'ITEM', p.menuItemId!);
    if (!item) this.reject('PARENT_MISSING', 'Item not found');
    const data = { size: p.size!, price: p.price! };
    await tx.menuItemVariant.create({
      data: {
        id,
        menuItemId: item.id,
        posMenuVariantId: id,
        ...data,
        ...meta,
      },
    });
    return { created: { ...data, menuItemId: p.menuItemId } };
  }

  private async update(
    tx: Tx,
    venueId: string,
    m: MenuMutation,
    current: NonNullable<Awaited<ReturnType<MenuCatalogService['find']>>>,
    seq: number,
  ) {
    const p = m.patch;
    const bump = { revision: { increment: 1 }, changeSeq: seq };
    if (m.entityType === 'CATEGORY') {
      const row = current as Prisma.MenuCategoryGetPayload<object>;
      const after: Record<string, unknown> = {};
      for (const f of [
        'nameKa',
        'nameEn',
        'sortOrder',
        'sendToKitchen',
      ] as const)
        if (p[f] !== undefined) after[f] = p[f];
      if (p.slug !== undefined && p.slug !== row.slug)
        after.slug = await this.uniqueSlug(
          async (s) =>
            (await tx.menuCategory.count({
              where: { venueId, slug: s, NOT: { id: row.id } },
            })) > 0,
          p.slug,
          m.entityId,
        );
      const diff = this.changed(row, after);
      if (Object.keys(diff).length)
        await tx.menuCategory.update({
          where: { id: row.id },
          data: { ...pick(after, diff), ...bump },
        });
      return diff;
    }
    if (m.entityType === 'SUBCATEGORY') {
      const row = current as Prisma.MenuSubcategoryGetPayload<{
        include: { category: true };
      }>;
      const after: Record<string, unknown> = {};
      for (const f of ['nameKa', 'nameEn', 'sortOrder'] as const)
        if (p[f] !== undefined) after[f] = p[f];
      let categoryId = row.categoryId;
      if (p.categoryId !== undefined) {
        categoryId = (await this.parentCategory(tx, venueId, p.categoryId)).id;
        after.categoryId = categoryId;
      }
      if (p.slug !== undefined && p.slug !== row.slug)
        after.slug = await this.uniqueSlug(
          async (s) =>
            (await tx.menuSubcategory.count({
              where: { categoryId, slug: s, NOT: { id: row.id } },
            })) > 0,
          p.slug,
          m.entityId,
        );
      const diff = this.changed(row, after);
      if (Object.keys(diff).length)
        await tx.menuSubcategory.update({
          where: { id: row.id },
          data: { ...pick(after, diff), ...bump },
        });
      return diff;
    }
    if (m.entityType === 'ITEM') {
      const row = current as Prisma.MenuItemGetPayload<object>;
      const after: Record<string, unknown> = {};
      for (const f of [
        'nameKa',
        'nameEn',
        'sortOrder',
        'sendToKitchen',
        'enabled',
        'price',
      ] as const)
        if (p[f] !== undefined) after[f] = p[f];
      const parent = await this.itemParent(tx, venueId, p);
      if (parent) Object.assign(after, parent);
      const diff = this.changed(row, after);
      if (Object.keys(diff).length)
        await tx.menuItem.update({
          where: { id: row.id },
          data: { ...pick(after, diff), ...bump },
        });
      return diff;
    }
    const row = current as Prisma.MenuItemVariantGetPayload<{
      include: { menuItem: true };
    }>;
    if (
      p.menuItemId !== undefined &&
      p.menuItemId !== key(row.menuItem.posMenuItemId, row.menuItem.id)
    )
      throw new BadRequestException({
        code: 'INVALID_MUTATION',
        message: 'A variant cannot move to another item',
      });
    const after: Record<string, unknown> = {};
    for (const f of ['size', 'price'] as const)
      if (p[f] !== undefined) after[f] = p[f];
    const diff = this.changed(row, after);
    if (Object.keys(diff).length)
      await tx.menuItemVariant.update({
        where: { id: row.id },
        data: { ...pick(after, diff), ...bump },
      });
    return diff;
  }

  private async tombstone(
    tx: Tx,
    venueId: string,
    entityType: MenuEntityKind,
    entityId: string,
    revision: number,
    seq: number,
    mutationId: string,
  ) {
    await tx.menuCatalogTombstone.upsert({
      where: { venueId_entityId: { venueId, entityId } },
      create: { venueId, entityType, entityId, revision, seq, mutationId },
      update: { entityType, revision, seq, mutationId, deletedAt: new Date() },
    });
  }

  /**
   * Deletes one node. Categories/subcategories must be empty (their children
   * are separate nodes that other devices may still be editing); an item's
   * variants are owned by it and are tombstoned with it. Historical Sales and
   * Orders keep their frozen names/prices and nullable ids, so nothing they
   * rely on is removed.
   */
  private async remove(
    tx: Tx,
    venueId: string,
    m: MenuMutation,
    current: NonNullable<Awaited<ReturnType<MenuCatalogService['find']>>>,
    seq: number,
  ) {
    const revision = current.revision + 1;
    if (m.entityType === 'CATEGORY') {
      const [subs, items] = await Promise.all([
        tx.menuSubcategory.count({ where: { categoryId: current.id } }),
        tx.menuItem.count({ where: { categoryId: current.id } }),
      ]);
      if (subs || items)
        this.reject('NOT_EMPTY', 'Remove the category contents first');
      await tx.menuCategory.delete({ where: { id: current.id } });
    } else if (m.entityType === 'SUBCATEGORY') {
      if (await tx.menuItem.count({ where: { subcategoryId: current.id } }))
        this.reject('NOT_EMPTY', 'Remove the subcategory items first');
      await tx.menuSubcategory.delete({ where: { id: current.id } });
    } else if (m.entityType === 'ITEM') {
      const variants = await tx.menuItemVariant.findMany({
        where: { menuItemId: current.id },
      });
      for (const v of variants)
        await this.tombstone(
          tx,
          venueId,
          'VARIANT',
          key(v.posMenuVariantId, v.id),
          v.revision + 1,
          seq,
          m.mutationId,
        );
      await tx.menuItem.delete({ where: { id: current.id } });
    } else {
      await tx.menuItemVariant.delete({ where: { id: current.id } });
    }
    await this.tombstone(
      tx,
      venueId,
      m.entityType,
      m.entityId,
      revision,
      seq,
      m.mutationId,
    );
    return { deleted: true };
  }
}

function pick(after: Record<string, unknown>, diff: Record<string, unknown>) {
  return Object.fromEntries(
    Object.keys(diff).map((field) => [field, after[field]]),
  );
}
