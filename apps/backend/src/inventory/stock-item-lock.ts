import { Prisma } from '@prisma/client';

/** Serialize unit-sensitive reads with stock edits and ledger writes. */
export async function lockStockItems(
  tx: Prisma.TransactionClient,
  venueId: string,
  stockItemIds: readonly string[],
): Promise<void> {
  const ids = [...new Set(stockItemIds)].sort();
  if (!ids.length) return;
  await tx.$queryRaw(
    Prisma.sql`SELECT id FROM pos."StockItem" WHERE "venueId"=${venueId} AND id IN (${Prisma.join(ids)}) ORDER BY id FOR UPDATE`,
  );
}
