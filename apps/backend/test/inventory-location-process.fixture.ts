import { PrismaService } from '../src/prisma.service';
import { StockLocations } from '../src/inventory/stock-locations';
import { ReceivingService } from '../src/inventory/receiving.service';
import type { InventoryActor } from '../src/inventory/inventory-audit';
import { isFreshDisposableDatabase } from './disposable-database';

/** A separate process retries synthetic committed work after a lost response. */
async function main() {
  const url = process.env.INV1_TEST_DATABASE_URL;
  if (!url || !isFreshDisposableDatabase(url))
    throw Error('Disposable INV-01 database required');
  const actor = JSON.parse(
    process.env.INV1_RETRY_ACTOR ?? '',
  ) as InventoryActor;
  const db = new PrismaService({ datasourceUrl: url });
  try {
    if (process.env.INV1_RETRY_KIND === 'location') {
      const input = JSON.parse(process.env.INV1_RETRY_INPUT ?? '') as {
        requestId: string;
        name: string;
      };
      const result = await new StockLocations(db).create(actor, input);
      process.stdout.write(JSON.stringify(result));
    } else if (process.env.INV1_RETRY_KIND === 'receiving') {
      const id = process.env.INV1_RETRY_INPUT;
      if (!id) throw Error('Receiving identity required');
      const result = await new ReceivingService(db).post(actor, id);
      const recordedId: unknown = result.id;
      if (typeof recordedId !== 'string')
        throw Error('Receiving identity missing');
      process.stdout.write(
        JSON.stringify({ id: recordedId, result: result.result }),
      );
    } else throw Error('Unsupported proof operation');
  } finally {
    await db.$disconnect();
  }
}
void main().catch((error: unknown) => {
  process.stderr.write(String(error));
  process.exitCode = 1;
});
