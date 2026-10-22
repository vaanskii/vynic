// MENU03 only: real controllers/guards/services, disposable loopback PostgreSQL.
import 'reflect-metadata';
import { readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import {
  menu03App,
  seedMenu03,
  menu03Request,
  type Menu03Fixture,
} from '../test/menu03.fixture';

async function main() {
  const url = process.env.MENU03_TEST_DATABASE_URL;
  const path = process.env.MENU03_HTTP_FIXTURE;
  if (process.argv[2] !== '--confirm-local' || !url || !path)
    throw Error('Explicit disposable URL and fixture path required');
  const { app, db, base } = await menu03App(url);
  let fixture: Menu03Fixture & { ids?: Record<string, string> };
  if (process.env.MENU03_SEED === '0') {
    fixture = JSON.parse(readFileSync(path, 'utf8')) as typeof fixture;
  } else {
    fixture = await seedMenu03(db, app);
    fixture.ids = {
      category: randomUUID(),
      subcategory: randomUUID(),
      item: randomUUID(),
      other: randomUUID(),
      variant: randomUUID(),
    };
    const ids = fixture.ids;
    for (const body of [
      {
        entityType: 'CATEGORY',
        entityId: ids.category,
        patch: { nameKa: 'Synthetic', nameEn: 'Synthetic' },
      },
      {
        entityType: 'SUBCATEGORY',
        entityId: ids.subcategory,
        patch: {
          categoryId: ids.category,
          nameKa: 'Synthetic sub',
          nameEn: 'Synthetic sub',
        },
      },
      {
        entityType: 'ITEM',
        entityId: ids.item,
        patch: {
          subcategoryId: ids.subcategory,
          nameKa: 'Synthetic item',
          nameEn: 'Synthetic item',
          price: 10,
        },
      },
      {
        entityType: 'ITEM',
        entityId: ids.other,
        patch: {
          categoryId: ids.category,
          nameKa: 'Other',
          nameEn: 'Other',
          price: 20,
        },
      },
      {
        entityType: 'VARIANT',
        entityId: ids.variant,
        patch: { menuItemId: ids.item, size: 0.15, price: 9 },
      },
    ]) {
      const response = await menu03Request(base, fixture.venues[0], {
        ...body,
        mutationId: randomUUID(),
        operation: 'UPSERT',
        expectedRevision: 0,
      });
      if (response.status !== 200) throw Error('Synthetic Menu seed failed');
    }
  }
  writeFileSync(
    path,
    JSON.stringify({ ...fixture, baseUrl: base, backendPid: process.pid }),
    { mode: 0o600 },
  );
  console.log(`MENU03 disposable HTTP ready pid=${process.pid}`);
  const close = async () => {
    await app.close();
    await db.$disconnect();
  };
  process.once('SIGTERM', () => {
    void close();
  });
  process.once('SIGINT', () => {
    void close();
  });
}
void main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
