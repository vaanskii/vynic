import { PrismaService } from '../../../prisma.service';
import { isCanonicalTableId } from '../../../shared/contracts/table-identity';

export interface TableRecordIdentity {
  tableId?: string;
  tableNumber: string;
  floor: string;
}

export interface TableOccupancyState {
  isReserved: boolean;
  activeOrderId: number | null;
  currentBill: number;
}

function canonicalIdOf(identity: TableRecordIdentity): string | null {
  const candidate = identity.tableId;
  return candidate && isCanonicalTableId(candidate) ? candidate : null;
}

async function findCanonicalAndAlias(
  prisma: PrismaService,
  identity: TableRecordIdentity,
  tableId: string,
) {
  const byId = await prisma.table.findUnique({ where: { id: tableId } });
  const byAlias = await prisma.table.findUnique({
    where: {
      tableIdentifier: {
        tableNumber: identity.tableNumber,
        floor: identity.floor,
      },
    },
  });

  if (byId && byAlias && byId.id !== byAlias.id) {
    throw new Error(
      `Canonical table ${tableId} conflicts with legacy alias ` +
        `${identity.floor}/${identity.tableNumber}`,
    );
  }
  return byId ?? byAlias;
}

/**
 * Writes one table using UUID identity when supplied, and the historical
 * floor/number upsert when it is not. The first UUID-aware sync adopts a
 * pre-existing legacy row by changing its otherwise-unreferenced primary key;
 * subsequent syncs resolve that same row directly by UUID.
 */
export async function upsertTableRecord(
  prisma: PrismaService,
  identity: TableRecordIdentity,
  state: TableOccupancyState,
) {
  const tableId = canonicalIdOf(identity);
  if (!tableId) {
    return prisma.table.upsert({
      where: {
        tableIdentifier: {
          tableNumber: identity.tableNumber,
          floor: identity.floor,
        },
      },
      update: state,
      create: {
        tableNumber: identity.tableNumber,
        floor: identity.floor,
        ...state,
      },
    });
  }

  const existing = await findCanonicalAndAlias(prisma, identity, tableId);
  if (existing) {
    return prisma.table.update({
      where: { id: existing.id },
      data: {
        id: tableId,
        tableNumber: identity.tableNumber,
        floor: identity.floor,
        ...state,
      },
    });
  }

  return prisma.table.create({
    data: {
      id: tableId,
      tableNumber: identity.tableNumber,
      floor: identity.floor,
      ...state,
    },
  });
}

/** Updates a linked table without creating one when a terminal order closes. */
export async function updateExistingTableRecord(
  prisma: PrismaService,
  identity: TableRecordIdentity,
  state: TableOccupancyState,
): Promise<number> {
  const tableId = canonicalIdOf(identity);
  if (!tableId) {
    const result = await prisma.table.updateMany({
      where: {
        tableNumber: identity.tableNumber,
        floor: identity.floor,
      },
      data: state,
    });
    return result.count;
  }

  const existing = await findCanonicalAndAlias(prisma, identity, tableId);
  if (!existing) {
    return 0;
  }
  await prisma.table.update({
    where: { id: existing.id },
    data: { id: tableId, ...state },
  });
  return 1;
}
