import { ConflictException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import { InventoryService } from './inventory.service';

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
  audits: any[] = [];
  private sequence = 0;

  private row(data: any, prefix: string) {
    const now = new Date(`2026-09-05T10:00:0${this.sequence}.000Z`);
    return {
      id: `${prefix}-${++this.sequence}`,
      ...data,
      createdAt: now,
      updatedAt: now,
    };
  }

  readonly stockItem = {
    findMany: ({ where }: any) =>
      Promise.resolve(
        this.stockItems.filter((row) => row.venueId === where.venueId),
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
      const row = this.row(data, 'stock');
      this.stockItems.push(row);
      return Promise.resolve(row);
    },
    findFirst: ({ where }: any) =>
      Promise.resolve(
        this.stockItems.find(
          (row) => row.id === where.id && row.venueId === where.venueId,
        ) ?? null,
      ),
    update: ({ where, data }: any) => {
      const row = this.stockItems.find((item) => item.id === where.id);
      Object.assign(row, data, { updatedAt: new Date('2026-09-05T11:00:00Z') });
      return Promise.resolve(row);
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
  return { db, service: new InventoryService(db as never) };
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
    expect(edited.currentStock).toBe('0');
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
