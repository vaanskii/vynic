import { ConflictException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import { InventoryService } from './inventory.service';
import { RecipeService } from './recipe.service';

const ACTOR_A: ManagerAuthContext = {
  staffId: 'staff-a',
  username: 'Nino',
  role: 'MANAGER',
  venueId: 'venue-a',
  organizationId: 'org-a',
};
const ACTOR_B: ManagerAuthContext = {
  ...ACTOR_A,
  staffId: 'staff-b',
  username: 'Gio',
  venueId: 'venue-b',
  organizationId: 'org-b',
};

class InventoryFakeDb {
  stockItems: any[] = [];
  suppliers: any[] = [];
  purchaseUnits: any[] = [];
  movements: any[] = [];
  audits: any[] = [];
  private sequence = 0;

  /** What a Prisma `include` would attach to a Stock Item row. */
  private withRelations(row: any) {
    return {
      ...row,
      purchaseUnits: this.purchaseUnits
        .filter((unit) => unit.stockItemId === row.id)
        .sort((left, right) => left.unit.localeCompare(right.unit)),
    };
  }

  private row(data: any, prefix: string) {
    const now = new Date(`2026-09-05T10:00:0${this.sequence}.000Z`);
    return {
      id: `${prefix}-${++this.sequence}`,
      ...data,
      createdAt: now,
      updatedAt: now,
    };
  }

  readonly supplierProduct = { findMany: () => Promise.resolve([]) };
  readonly receivingLine = { findFirst: () => Promise.resolve(null) };
  readonly menuConsumptionComponent = {
    findFirst: () => Promise.resolve(null),
  };

  readonly stockItem = {
    findMany: ({ where }: any) =>
      Promise.resolve(
        this.stockItems
          .filter((row) => row.venueId === where.venueId)
          .map((row) => this.withRelations(row)),
      ),
    create: ({ data }: any) => {
      if (
        data.sku != null &&
        this.stockItems.some(
          (row) => row.venueId === data.venueId && row.sku === data.sku,
        )
      ) {
        throw new Prisma.PrismaClientKnownRequestError('duplicate sku', {
          code: 'P2002',
          clientVersion: '6.19.3',
        });
      }
      const { purchaseUnits, ...fields } = data;
      const row = this.row(fields, 'stock');
      this.stockItems.push(row);
      for (const unit of purchaseUnits?.create ?? []) {
        this.purchaseUnits.push(
          this.row({ ...unit, stockItemId: row.id }, 'purchase'),
        );
      }
      return Promise.resolve(this.withRelations(row));
    },
    findFirst: ({ where }: any) =>
      Promise.resolve(
        this.stockItems.find(
          (row) => row.id === where.id && row.venueId === where.venueId,
        ) ?? null,
      ),
    findUniqueOrThrow: ({ where }: any) => {
      const row = this.stockItems.find((item) => item.id === where.id);
      if (!row) throw new Error('Stock item not found');
      return Promise.resolve(this.withRelations(row));
    },
    update: ({ where, data }: any) => {
      const row = this.stockItems.find((item) => item.id === where.id);
      Object.assign(row, data, { updatedAt: new Date('2026-09-05T11:00:00Z') });
      return Promise.resolve(this.withRelations(row));
    },
  };

  readonly stockItemPurchaseUnit = {
    findMany: ({ where }: any) =>
      Promise.resolve(
        this.purchaseUnits
          .filter((row) => row.stockItemId === where.stockItemId)
          .sort((left, right) => left.unit.localeCompare(right.unit)),
      ),
    deleteMany: ({ where }: any) => {
      this.purchaseUnits = this.purchaseUnits.filter(
        (row) => row.stockItemId !== where.stockItemId,
      );
      return Promise.resolve({ count: 0 });
    },
    createMany: ({ data }: any) => {
      for (const unit of data) {
        this.purchaseUnits.push(this.row(unit, 'purchase'));
      }
      return Promise.resolve({ count: data.length });
    },
  };

  /** Enough of `groupBy` for the derived-balance read. */
  readonly stockMovement = {
    groupBy: ({ where }: any) => {
      const wanted: string[] | null = where.stockItemId?.in ?? null;
      const totals = new Map<string, Prisma.Decimal>();
      for (const movement of this.movements) {
        if (movement.venueId !== where.venueId) continue;
        if (wanted && !wanted.includes(movement.stockItemId)) continue;
        totals.set(
          movement.stockItemId,
          (totals.get(movement.stockItemId) ?? new Prisma.Decimal(0)).plus(
            movement.quantityDeltaBase,
          ),
        );
      }
      return Promise.resolve(
        [...totals].map(([stockItemId, sum]) => ({
          stockItemId,
          _sum: { quantityDeltaBase: sum },
        })),
      );
    },
  };

  readonly supplier = {
    findMany: ({ where }: any) =>
      Promise.resolve(
        this.suppliers.filter((row) => row.venueId === where.venueId),
      ),
    create: ({ data }: any) => {
      const row = this.row(data, 'supplier');
      this.suppliers.push(row);
      return Promise.resolve(row);
    },
    findFirst: ({ where }: any) =>
      Promise.resolve(
        this.suppliers.find(
          (row) => row.id === where.id && row.venueId === where.venueId,
        ) ?? null,
      ),
    update: ({ where, data }: any) => {
      const row = this.suppliers.find((item) => item.id === where.id);
      Object.assign(row, data, { updatedAt: new Date('2026-09-05T11:00:00Z') });
      return Promise.resolve(row);
    },
  };

  readonly auditEventLog = {
    create: ({ data }: any) => {
      const row = this.row(data, 'audit');
      this.audits.push(row);
      return Promise.resolve(row);
    },
  };

  $transaction<T>(callback: (tx: this) => Promise<T>) {
    return callback(this);
  }
}

function harness() {
  const db = new InventoryFakeDb();
  return {
    db,
    service: new InventoryService(db as never, new RecipeService(db as never)),
  };
}

describe('InventoryService', () => {
  it('allows same-name Stock Items while preserving immutable generated ids', async () => {
    const h = harness();
    const first = await h.service.createStockItem(ACTOR_A, {
      name: 'Beef',
      baseUnit: 'kg',
    });
    const second = await h.service.createStockItem(ACTOR_A, {
      name: 'Beef',
      baseUnit: 'g',
    });
    const edited = await h.service.updateStockItem(ACTOR_A, first.id, {
      name: 'Premium beef',
    });

    expect(first.id).not.toBe(second.id);
    expect(edited.id).toBe(first.id);
    expect(edited.name).toBe('Premium beef');
    // Step 2 derives the balance from the ledger; no movements is an exact
    // zero at quantity scale, not a placeholder.
    expect(edited.currentStock).toBe('0.000');
    expect(edited.stockStatus).toBe('NO_MINIMUM');
  });

  it('stores item packaging as one declared set and audits the change', async () => {
    const h = harness();
    const created = await h.service.createStockItem(ACTOR_A, {
      name: 'Lemonade 0.5L',
      baseUnit: 'bottle',
      purchaseUnits: [
        { unit: 'box', baseUnitMultiplier: '24' },
        { unit: 'pack', baseUnitMultiplier: '6' },
      ],
    });
    expect(created.purchaseUnits.map((unit: any) => unit.unit)).toEqual([
      'box',
      'pack',
    ]);
    expect(created.purchaseUnits[0].baseUnitMultiplier).toBe('24');

    // Sending the set without "pack" is how a ratio is removed.
    const edited = await h.service.updateStockItem(ACTOR_A, created.id, {
      purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '12' }],
    });
    expect(edited.purchaseUnits).toEqual([
      { id: expect.any(String), unit: 'box', baseUnitMultiplier: '12' },
    ]);
    expect(h.db.audits.at(-1).data.changes).toEqual([
      {
        field: 'purchaseUnits',
        previousValue: 'box=24, pack=6',
        newValue: 'box=12',
      },
    ]);
  });

  it('leaves packaging alone when a save does not mention it', async () => {
    const h = harness();
    const created = await h.service.createStockItem(ACTOR_A, {
      name: 'Wine',
      baseUnit: 'bottle',
      purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '6' }],
    });
    const renamed = await h.service.updateStockItem(ACTOR_A, created.id, {
      name: 'Saperavi',
    });
    expect(renamed.purchaseUnits).toHaveLength(1);
    expect(renamed.purchaseUnits[0].baseUnitMultiplier).toBe('6');
  });

  it('refuses a ratio for the item’s own base unit or a duplicate label', async () => {
    const h = harness();
    await expect(
      h.service.createStockItem(ACTOR_A, {
        name: 'Confused',
        baseUnit: 'bottle',
        purchaseUnits: [{ unit: 'bottle', baseUnitMultiplier: '1' }],
      }),
    ).rejects.toThrow('needs no purchase ratio');
    await expect(
      h.service.createStockItem(ACTOR_A, {
        name: 'Twice',
        baseUnit: 'bottle',
        purchaseUnits: [
          { unit: 'box', baseUnitMultiplier: '24' },
          { unit: 'box', baseUnitMultiplier: '12' },
        ],
      }),
    ).rejects.toThrow('listed twice');
    await expect(
      h.service.createStockItem(ACTOR_A, {
        name: 'Zero',
        baseUnit: 'bottle',
        purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '0' }],
      }),
    ).rejects.toThrow('greater than zero');
  });

  it('normalizes SKU and enforces uniqueness only inside one Venue', async () => {
    const h = harness();
    await h.service.createStockItem(ACTOR_A, {
      name: 'Flour',
      sku: ' flour-01 ',
      baseUnit: 'kg',
    });
    await expect(
      h.service.createStockItem(ACTOR_A, {
        name: 'Other flour',
        sku: 'FLOUR-01',
        baseUnit: 'kg',
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    await expect(
      h.service.createStockItem(ACTOR_B, {
        name: 'Venue B flour',
        sku: 'FLOUR-01',
        baseUnit: 'kg',
      }),
    ).resolves.toMatchObject({ sku: 'FLOUR-01' });
  });

  it('cannot read or mutate another Venue Stock Item', async () => {
    const h = harness();
    const item = await h.service.createStockItem(ACTOR_B, {
      name: 'Onion',
      baseUnit: 'kg',
    });
    await expect(h.service.listStockItems(ACTOR_A)).resolves.toEqual([]);
    await expect(
      h.service.updateStockItem(ACTOR_A, item.id, { name: 'Stolen onion' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('disables a Stock Item and audits stable identity plus actor/source', async () => {
    const h = harness();
    const item = await h.service.createStockItem(ACTOR_A, {
      name: 'Onion',
      baseUnit: 'kg',
    });
    await h.service.updateStockItem(ACTOR_A, item.id, { isActive: false });

    expect(h.db.audits.at(-1)).toMatchObject({
      venueId: ACTOR_A.venueId,
      action: 'STOCK_ITEM_DISABLED',
      userId: ACTOR_A.staffId,
      entityType: 'STOCK_ITEM',
      entityId: item.id,
      deviceType: 'manager',
      data: {
        actorId: ACTOR_A.staffId,
        actorName: ACTOR_A.username,
        source: 'MANAGER',
        stockItemId: item.id,
      },
    });
  });

  it('creates, edits, and disables a Supplier without changing its id', async () => {
    const h = harness();
    const supplier = await h.service.createSupplier(ACTOR_A, {
      name: 'Farm',
      phone: '555 12 34 56',
    });
    const edited = await h.service.updateSupplier(ACTOR_A, supplier.id, {
      name: 'Farm Georgia',
      isActive: false,
    });

    expect(edited.id).toBe(supplier.id);
    expect(edited).toMatchObject({ name: 'Farm Georgia', isActive: false });
    expect(h.db.audits.at(-1)).toMatchObject({
      action: 'SUPPLIER_DISABLED',
      entityType: 'SUPPLIER',
      entityId: supplier.id,
      data: { supplierId: supplier.id, source: 'MANAGER' },
    });
    // Contact values are not copied into the audit payload.
    expect(JSON.stringify(h.db.audits)).not.toContain('555 12 34 56');
  });

  it('cannot read or mutate another Venue Supplier', async () => {
    const h = harness();
    const supplier = await h.service.createSupplier(ACTOR_B, { name: 'Farm' });
    await expect(h.service.listSuppliers(ACTOR_A)).resolves.toEqual([]);
    await expect(
      h.service.updateSupplier(ACTOR_A, supplier.id, { name: 'Other' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
