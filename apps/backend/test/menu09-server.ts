import 'reflect-metadata';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { menu09App, seedMenu09 } from './menu09.fixture';
import { DeviceEnrollmentService } from '../src/edge/device-enrollment.service';
import { MenuCatalogService } from '../src/menu-catalog/menu-catalog.service';

async function main() {
  const path = process.env.MENU09_HTTP_FIXTURE;
  if (!path?.startsWith('/private/tmp/vynic-menu09-'))
    throw Error('Owned private fixture required');
  const live = await menu09App(process.env.MENU09_TEST_DATABASE_URL!);
  let fixture: Record<string, unknown>;
  if (existsSync(path))
    fixture = JSON.parse(readFileSync(path, 'utf8')) as Record<string, unknown>;
  else {
    const { venues } = await seedMenu09(live);
    const a = venues[0];
    const categoryId = randomUUID(),
      itemId = randomUUID();
    for (const [entityType, entityId, patch] of [
      ['CATEGORY', categoryId, { nameKa: 'Synthetic', nameEn: 'Synthetic' }],
      [
        'ITEM',
        itemId,
        {
          categoryId,
          nameKa: 'Synthetic dish',
          nameEn: 'Synthetic dish',
          price: 10,
        },
      ],
    ] as const)
      await live.app.get(MenuCatalogService).apply(
        a.venueId,
        { type: 'CUSTOMER', id: a.ownerId, source: 'DASHBOARD' },
        {
          mutationId: randomUUID(),
          entityType,
          entityId,
          operation: 'UPSERT',
          expectedRevision: 0,
          patch,
        },
      );
    const codes: string[] = [];
    for (const label of ['source', 'replacement'])
      codes.push(
        (
          await live.app
            .get(DeviceEnrollmentService)
            .create({ customerAccountId: a.ownerId }, a.venueId, {
              displayName: 'Native ' + label,
              platform: 'MACOS',
            })
        ).code,
      );
    fixture = { venues, categoryId, itemId, codes };
  }
  writeFileSync(
    path,
    JSON.stringify({ ...fixture, baseUrl: live.base, backendPid: process.pid }),
    { mode: 0o600 },
  );
  console.log('MENU09 private native bridge ready');
  process.once('SIGTERM', () => {
    void (async () => {
      await live.app.close();
      await live.db.$disconnect();
      process.exit(0);
    })();
  });
}
void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
