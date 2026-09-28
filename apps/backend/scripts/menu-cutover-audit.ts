// Read-only Menu cutover readiness report for one Venue
// (docs/CANONICAL_MENU_SYNC.md, "Existing POS Venues").
//   DATABASE_URL=... npx ts-node -T scripts/menu-cutover-audit.ts <venueId>
// Runs inside a READ ONLY transaction: it cannot change authority or rows.
import { PrismaClient } from '@prisma/client';
import { menuCutoverReadiness } from '../src/menu-catalog/menu-cutover-readiness';

async function main() {
  const venueId = process.argv[2];
  if (!venueId) throw Error('Usage: menu-cutover-audit.ts <venueId>');
  const db = new PrismaClient();
  try {
    const report = await db.$transaction(async (tx) => {
      await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');
      return menuCutoverReadiness(tx, venueId);
    });
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await db.$disconnect();
  }
}
main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
