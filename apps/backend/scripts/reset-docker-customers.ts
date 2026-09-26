import { PrismaClient } from '@prisma/client';
import { requireLocalDocker } from '../src/local-tools/local-docker-guard';
import {
  cleanupCustomers,
  cleanupMedia,
} from '../src/local-tools/customer-cleanup';
async function main() {
  requireLocalDocker();
  const args = process.argv.slice(2);
  const dryRun = args.length === 1 && args[0] === '--dry-run';
  const mediaOnly =
    args.length === 2 &&
    args[0] === '--cleanup-media' &&
    args[1] === '--confirm-local';
  if (
    !dryRun &&
    !mediaOnly &&
    !(args.length === 1 && args[0] === '--confirm-local')
  )
    throw new Error(
      'Use --dry-run or --confirm-local. Cleanup recovery: --cleanup-media --confirm-local',
    );
  const db = new PrismaClient();
  try {
    const result = mediaOnly
      ? await cleanupMedia(db)
      : await cleanupCustomers(db, { kind: 'all' }, dryRun);
    console.log(JSON.stringify(result, null, 2));
    const failures =
      'mediaCleanup' in result ? result.mediaCleanup.failures : result.failures;
    if (failures.length) {
      console.error(
        'Database cleanup committed; media cleanup incomplete. Run cleanup-customer-media --confirm-local after resolving the reported failures.',
      );
      process.exitCode = 1;
    }
  } finally {
    await db.$disconnect();
  }
}
main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
