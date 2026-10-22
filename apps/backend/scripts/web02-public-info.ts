// WEB-02 shared public information: affected-state report and explicit
// decisions (docs/WEB02_SAFE_PUBLICATION_MIGRATION.md).
//
//   DATABASE_URL=... npx ts-node -T scripts/web02-public-info.ts report [--values] [<venueId>]
//   DATABASE_URL=... npx ts-node -T scripts/web02-public-info.ts decide <venueId> \
//     <apply-draft|dismiss|confirm-live|withhold> --actor <platform-admin-email> --note "<owner request>"
//
// `report` runs inside a READ ONLY transaction and changes nothing. `decide`
// records one owner/operator decision under an active PlatformUser, audited.
import { PrismaClient } from '@prisma/client';
import { VenueEntitlementsService } from '../src/entitlements/venue-entitlements.service';
import type { PrismaService } from '../src/prisma.service';
import { WebsiteCapabilitiesService } from '../src/website/tenancy/website-capabilities.service';
import {
  decidePublicInfoReview,
  publicInfoDecisions,
  publicInfoReviewReport,
  type PublicInfoDecision,
} from '../src/website/core/public-info-review';

function option(args: string[], name: string) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  const db = new PrismaClient();
  try {
    if (command === 'report') {
      const venueId = args.find((a) => !a.startsWith('--'));
      const report = await db.$transaction(async (tx) => {
        await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');
        const capabilities = new WebsiteCapabilitiesService(
          tx as unknown as PrismaService,
          new VenueEntitlementsService(tx as unknown as PrismaService),
        );
        return publicInfoReviewReport(tx, {
          venueId,
          includeValues: args.includes('--values'),
          launched: (id) => capabilities.launched(id),
        });
      });
      console.log(JSON.stringify(report, null, 2));
      return;
    }
    if (command === 'decide') {
      const [venueId, decision] = args;
      const email = option(args, '--actor');
      const note = option(args, '--note');
      if (
        !venueId ||
        !publicInfoDecisions.includes(decision as PublicInfoDecision) ||
        !email ||
        !note
      )
        throw Error(
          `Usage: decide <venueId> <${publicInfoDecisions.join('|')}> --actor <email> --note <text>`,
        );
      const actor = await db.platformUser.findUnique({
        where: { email: email.trim().toLowerCase() },
        select: { id: true },
      });
      if (!actor) throw Error('Unknown platform user');
      const entry = await decidePublicInfoReview(db, {
        venueId,
        decision: decision as PublicInfoDecision,
        platformUserId: actor.id,
        note,
      });
      console.log(JSON.stringify(entry, null, 2));
      return;
    }
    throw Error('Usage: web02-public-info.ts <report|decide> ...');
  } finally {
    await db.$disconnect();
  }
}
main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
