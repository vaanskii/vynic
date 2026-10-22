import 'reflect-metadata';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConflictException } from '@nestjs/common';
import {
  decidePublicInfoReview,
  differingFields,
  publicInfoReviewReport,
  storedInfo,
} from './public-info-review';
import { referencedMedia } from './website-media';
import {
  emptyLive,
  fixtures,
  host,
  mediaKey,
  venueId,
  type FixtureKey,
} from '../../../test/web02-public-info.fixture';
import {
  ownerToken,
  platformUser,
  shared,
  web02App,
  content,
  info,
} from '../../../test/web02-public-info.harness';

/**
 * WEB-02 on a database the original shared-foundation chain already
 * upgraded, before evidence was kept: the draft/published distinction is
 * gone. The fixed chain must not guess; the report must say what remaining
 * provenance proves; only explicit audited decisions change live data.
 */
const url = process.env.WEB02_POSTHOC_DATABASE_URL;
const proofDir = process.env.WEB02_PROOF_DIR;

(url ? describe : describe.skip)(
  'WEB-02 already-migrated database (real PostgreSQL / Nest HTTP)',
  () => {
    let ctx: Awaited<ReturnType<typeof web02App>>;
    let media: string;
    const fixture = (key: FixtureKey) => fixtures.find((f) => f.key === key)!;
    const site = (key: FixtureKey) =>
      ctx.http().get('/api/website/venue').set('Host', host(key));
    const report = () =>
      ctx.db.$transaction(async (tx) => {
        await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');
        return publicInfoReviewReport(tx, {
          launched: (id) => ctx.capabilities.launched(id),
        });
      });
    const entry = async (key: FixtureKey) =>
      (await report()).entries.find((e) => e.venueId === venueId(key));

    beforeAll(async () => {
      media = mkdtempSync(join(tmpdir(), 'web02-media-'));
      ctx = await web02App(url!, media);
    });
    afterAll(async () => {
      await ctx?.app.close();
      await ctx?.db.$disconnect();
      rmSync(media, { recursive: true, force: true });
    });

    it('applied the capture late as a no-op and changed no live value', async () => {
      const ledger = await ctx.db.$queryRaw<{ migration_name: string }[]>`
        SELECT migration_name FROM _prisma_migrations
        WHERE migration_name >= '20261010' ORDER BY finished_at`;
      expect(ledger.map((r) => r.migration_name)).toEqual([
        '20261010120000_shared_website_foundation',
        '20261011120000_canonical_menu_sync',
        '20261010110000_web02_capture_public_info_evidence',
        '20261012120000_web02_restore_public_info_authority',
      ]);
      expect(await ctx.db.venuePublicInfoReview.count()).toBe(0);
      for (const f of fixtures) {
        const profile = await ctx.db.venuePublicProfile.findUnique({
          where: { venueId: venueId(f.key) },
        });
        if (f.historicalLive === null) expect(profile).toBeNull();
        else
          expect([
            f.key,
            differingFields(storedInfo(profile), storedInfo(f.historicalLive)),
          ]).toEqual([f.key, []]);
      }
    });

    it('reports only what the remaining provenance proves, read-only', async () => {
      const before = await ctx.db.venuePublicProfile.findMany({
        orderBy: { venueId: 'asc' },
      });
      const result = await report();
      expect(
        await ctx.db.venuePublicProfile.findMany({
          orderBy: { venueId: 'asc' },
        }),
      ).toEqual(before);
      expect(result.foundationMigratedAt).toBeInstanceOf(Date);
      for (const f of fixtures) {
        const e = result.entries.find((x) => x.venueId === venueId(f.key));
        if (f.inferredProvenance === null) {
          expect(e).toBeUndefined();
          continue;
        }
        expect([f.key, e?.basis, e?.provenance]).toEqual([
          f.key,
          'INFERENCE',
          f.inferredProvenance,
        ]);
      }
      expect(await entry('draftonly')).toMatchObject({
        action: 'WITHHOLD_RECOMMENDED',
        launched: false,
      });
      // The never-published draft is publicly exposed only on the CUSTOM site.
      expect(await entry('customdraft')).toMatchObject({
        action: 'WITHHOLD_RECOMMENDED',
        launched: true,
      });
      expect(await entry('divergent')).toMatchObject({
        action: 'CONFIRM_OR_WITHHOLD',
        migratedFields: [
          'workingHours',
          'contactEmail',
          'mapUrl',
          'socials',
          'gallery',
        ],
      });
      expect((await entry('divergent'))!.reasons.join(' ')).toContain(
        'no longer knowable',
      );
      expect(await entry('synced')).toMatchObject({ action: 'NONE' });
      expect(result.requiringDecision).toBe(
        fixtures.filter(
          (f) =>
            f.inferredProvenance === 'DRAFT_ONLY' ||
            f.inferredProvenance === 'AMBIGUOUS',
        ).length,
      );
      if (proofDir) {
        mkdirSync(proofDir, { recursive: true });
        writeFileSync(
          join(proofDir, 'posthoc-report.json'),
          JSON.stringify(result, null, 2),
        );
      }
    });

    it('keeps serving current values until a decision (no guessed restoration)', async () => {
      for (const key of ['divergent', 'customdiv'] as const) {
        const response = await site(key).expect(200);
        expect(shared(info(response))).toEqual(fixture(key).historicalLive);
      }
    });

    it('withholds a provable never-published draft privately and can publish it on request', async () => {
      const operator = await platformUser(ctx.db);
      const withheld = await decidePublicInfoReview(ctx.db, {
        venueId: venueId('customdraft'),
        decision: 'withhold',
        platformUserId: operator.id,
        note: 'Never published; withheld pending owner review',
      });
      expect(withheld).toMatchObject({
        basis: 'DECISION',
        provenance: 'DRAFT_ONLY',
        state: 'PENDING',
        action: 'DECIDE_PRIVATE_DRAFT',
      });
      expect(shared(info(await site('customdraft').expect(200)))).toEqual(
        emptyLive,
      );
      expect(
        (await referencedMedia(ctx.db, venueId('customdraft'))).has(
          mediaKey('customdraft', 'b'),
        ),
      ).toBe(true);
      const review = await ctx.db.venuePublicInfoReview.findUniqueOrThrow({
        where: { venueId: venueId('customdraft') },
      });
      expect(
        differingFields(
          storedInfo(review.draftInfo),
          storedInfo(fixture('customdraft').historicalLive),
        ),
      ).toEqual([]);
      await decidePublicInfoReview(ctx.db, {
        venueId: venueId('customdraft'),
        decision: 'apply-draft',
        platformUserId: operator.id,
        note: 'Owner confirmed these hours and contacts',
      });
      expect(shared(info(await site('customdraft').expect(200)))).toEqual(
        fixture('customdraft').historicalLive,
      );
      expect(
        await ctx.db.platformAuditEvent.count({
          where: { targetId: venueId('customdraft') },
        }),
      ).toBe(2);
    });

    it('records an owner confirmation of ambiguous live values without changing them', async () => {
      const operator = await platformUser(ctx.db);
      const confirmed = await decidePublicInfoReview(ctx.db, {
        venueId: venueId('divergent'),
        decision: 'confirm-live',
        platformUserId: operator.id,
        note: 'Owner confirmed the current public information',
      });
      expect(confirmed).toMatchObject({
        provenance: 'AMBIGUOUS',
        state: 'CONFIRMED',
        action: 'NONE',
      });
      expect(shared(info(await site('divergent').expect(200)))).toEqual(
        fixture('divergent').historicalLive,
      );
      await expect(
        decidePublicInfoReview(ctx.db, {
          venueId: venueId('pubonly'),
          decision: 'confirm-live',
          platformUserId: operator.id,
          note: 'nothing to confirm',
        }),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('withholds only migrated fields and leaves audited owner edits live', async () => {
      const owner = await ownerToken(ctx.db, ctx.jwt, 'partial');
      await ctx
        .http()
        .put(`/customer/venues/${venueId('partial')}/website/public-info`)
        .set(owner.auth)
        .send({ expectedRevision: 0, contactEmail: 'owner-partial@web02.test' })
        .expect(200);
      expect(await entry('partial')).toMatchObject({
        provenance: 'AMBIGUOUS',
        ownerEditedFields: ['contactEmail'],
        migratedFields: ['workingHours', 'mapUrl'],
      });
      const operator = await platformUser(ctx.db);
      await decidePublicInfoReview(ctx.db, {
        venueId: venueId('partial'),
        decision: 'withhold',
        platformUserId: operator.id,
        note: 'Owner will re-enter hours and map',
      });
      const live = await ctx
        .http()
        .get('/api/website/bootstrap')
        .set('Host', host('partial'))
        .expect(200);
      expect(shared(content(live))).toEqual({
        ...emptyLive,
        contactEmail: 'owner-partial@web02.test',
      });
      await decidePublicInfoReview(ctx.db, {
        venueId: venueId('partial'),
        decision: 'dismiss',
        platformUserId: operator.id,
        note: 'Owner discarded the old values',
      });
      expect(await entry('partial')).toMatchObject({
        state: 'DISMISSED',
        action: 'NONE',
      });
    });
  },
);
