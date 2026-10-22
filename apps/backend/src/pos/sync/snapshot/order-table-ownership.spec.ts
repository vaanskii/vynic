import type { TenantContext } from '../../../auth/pos-auth-context';
import { OrderSyncService } from './order-sync.service';
import { updateExistingTableRecord } from './table-record-identity';

const tenant: TenantContext = { venueId: 'venue-a', organizationId: 'org-a' };
const canonicalId = 'a1111111-1111-4111-8111-111111111111';
const foreignId = 'b2222222-2222-4222-8222-222222222222';
const identities = ['legacy', 'canonical', 'canonical-adoption'] as const;
type Identity = (typeof identities)[number];
type TableRow = {
  id: string;
  venueId: string;
  tableNumber: string;
  floor: string;
  isReserved: boolean;
  activeOrderId: number | null;
  currentBill: number;
};

/** Stateful table storage exercises the final occupancy, not only query shape. */
function fixture(identity: Identity, owner: number | null) {
  const table: TableRow = {
    id: identity === 'canonical' ? canonicalId : 'legacy-table-row',
    venueId: tenant.venueId,
    tableNumber: '2',
    floor: 'first',
    isReserved: owner !== null,
    activeOrderId: owner,
    currentBill: owner === null ? 0 : 42,
  };
  const foreign: TableRow = { ...table, id: foreignId, venueId: 'venue-b' };
  const rows = [table, foreign];
  const matches = (row: TableRow, where: Record<string, unknown>) =>
    Object.entries(where).every(([key, value]) => row[key] === value);
  const find = (where: any) =>
    rows.find((row) => matches(row, where.tableIdentifier ?? where)) ?? null;
  let beforeRelease: (() => void) | undefined;
  const prisma = {
    posCallbackOutbox: { findMany: jest.fn().mockResolvedValue([]) },
    order: {
      upsert: jest.fn(async ({ create }: any) => ({
        id: `order-${create.posOrderId}`,
      })),
    },
    table: {
      findUnique: jest.fn(async ({ where }: any) => {
        const row = find(where);
        return row ? { ...row } : null;
      }),
      upsert: jest.fn(async ({ where, update, create }: any) => {
        const row = find(where);
        if (row) return Object.assign(row, update);
        rows.push(create);
        return create;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const row = find(where);
        if (!row) throw new Error('table_not_found');
        return Object.assign(row, data);
      }),
      updateMany: jest.fn(async ({ where, data }: any) => {
        beforeRelease?.();
        const selected = rows.filter((row) => matches(row, where));
        selected.forEach((row) => Object.assign(row, data));
        return { count: selected.length };
      }),
    },
  };
  const tableIdentity = {
    tableNumber: table.tableNumber,
    floor: table.floor,
    ...(identity !== 'legacy' ? { tableId: canonicalId } : {}),
  };
  return {
    prisma,
    table,
    foreign,
    tableIdentity,
    beforeRelease: (callback: () => void) => {
      beforeRelease = callback;
    },
    order: (posOrderId: number, status: string) => ({
      posOrderId,
      status,
      totalAmount: 42,
      floor: table.floor,
      tableNumbers: [table.tableNumber],
      ...(identity !== 'legacy' ? { tableIds: [canonicalId] } : {}),
    }),
  };
}

describe.each(identities)('snapshot table ownership (%s)', (identity) => {
  it.each(['closed', 'cancelled', 'paid'])(
    '%s cannot release another open order, in either enumeration order',
    async (status) => {
      for (const activeFirst of [true, false]) {
        const f = fixture(identity, 1);
        const active = f.order(1, 'confirmed');
        const terminal = f.order(2, status);
        const result = await new OrderSyncService(f.prisma as any).sync(
          tenant,
          activeFirst ? [active, terminal] : [terminal, active],
        );

        expect(f.table).toMatchObject({
          isReserved: true,
          activeOrderId: 1,
          currentBill: 42,
        });
        expect(f.foreign).toMatchObject({
          isReserved: true,
          activeOrderId: 1,
          currentBill: 42,
        });
        expect(result.releasedTables).toBe(false);
        expect(f.prisma.table.updateMany).toHaveBeenCalledWith(
          expect.objectContaining({
            where: expect.objectContaining({
              venueId: tenant.venueId,
              activeOrderId: 2,
            }),
          }),
        );
      }
    },
  );

  it.each(['closed', 'cancelled', 'paid'])(
    '%s releases its own table and preserves the other Venue',
    async (status) => {
      const f = fixture(identity, 2);
      const result = await new OrderSyncService(f.prisma as any).sync(tenant, [
        f.order(2, status),
      ]);

      expect(f.table).toMatchObject({
        isReserved: false,
        activeOrderId: null,
        currentBill: 0,
      });
      if (identity !== 'legacy') expect(f.table.id).toBe(canonicalId);
      expect(f.foreign).toMatchObject({
        isReserved: true,
        activeOrderId: 2,
        currentBill: 42,
      });
      expect(result.releasedTables).toBe(true);
    },
  );

  it('checks ownership atomically when an owner changes immediately before the release write', async () => {
    const f = fixture(identity, 2);
    f.beforeRelease(() => {
      f.table.activeOrderId = 3;
    });
    const result = await new OrderSyncService(f.prisma as any).sync(tenant, [
      f.order(2, 'closed'),
    ]);

    expect(f.table).toMatchObject({
      isReserved: true,
      activeOrderId: 3,
      currentBill: 42,
    });
    expect(result.releasedTables).toBe(false);
  });

  it('does not turn an already-free table into a reported release', async () => {
    const f = fixture(identity, null);
    const result = await new OrderSyncService(f.prisma as any).sync(tenant, [
      f.order(2, 'closed'),
    ]);

    expect(f.table).toMatchObject({
      isReserved: false,
      activeOrderId: null,
      currentBill: 0,
    });
    expect(result.releasedTables).toBe(false);
  });
});

it('retains canonical-versus-alias conflict refusal before releasing either row', async () => {
  const f = fixture('legacy', 2);
  f.prisma.table.findUnique.mockImplementation(async ({ where }: any) =>
    where.id ? { ...f.table, id: canonicalId } : { ...f.table },
  );

  await expect(
    updateExistingTableRecord(
      f.prisma as any,
      tenant,
      { ...f.tableIdentity, tableId: canonicalId },
      { isReserved: false, activeOrderId: null, currentBill: 0 },
      2,
    ),
  ).rejects.toThrow('conflicts with legacy alias');
  expect(f.prisma.table.updateMany).not.toHaveBeenCalled();
  expect(f.prisma.table.update).not.toHaveBeenCalled();
});
