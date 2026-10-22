import 'reflect-metadata';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import {
  decidePublicInfoReview,
  differingFields,
  publicInfoReviewReport,
  storedInfo,
} from './public-info-review';
import { referencedMedia } from './website-media';
import {
  disabledHost,
  emptyLive,
  fixtures,
  host,
  mediaKey,
  unknownHost,
  venueId,
  type FixtureKey,
} from '../../../test/web02-public-info.fixture';
import {
  markers,
  ownerToken,
  platformUser,
  privateMarkers,
  shared,
  web02App,
  content,
  info,
  json,
  type Json,
} from '../../../test/web02-public-info.harness';

/**
 * WEB-02 acceptance: a database holding pre-foundation SAAS documents
 * (published only, draft only, divergent, empty; SAAS, CUSTOM, entitlement
 * withheld) upgraded through the real current migration chain. The runner
 * (`scripts/prove-web02-upgrade.py`) owns creation, the pre-foundation chain,
 * fixtures, the upgrade and cleanup; this suite only asserts.
 */
const url = process.env.WEB02_UPGRADE_DATABASE_URL;
const proofDir = process.env.WEB02_PROOF_DIR;
const label = process.env.WEB02_PROOF_LABEL ?? 'upgrade';
const MOVED = ['workingHours', 'contactEmail', 'mapUrl', 'socials', 'gallery'];

(url ? describe : describe.skip)(
  'WEB-02 pre-foundation → current chain (real PostgreSQL / Nest HTTP)',
  () => {
    let ctx: Awaited<ReturnType<typeof web02App>>;
    let media: string;
    const bodies: { host: string; body: string }[] = [];
    const saas = (key: FixtureKey) =>
      ctx.http().get('/api/website/bootstrap').set('Host', host(key));
    const site = (key: FixtureKey) =>
      ctx.http().get('/api/website/venue').set('Host', host(key));
    const record = (h: string, body: unknown) =>
      bodies.push({ host: h, body: JSON.stringify(body) });
    const proof = (name: string, value: unknown) => {
      if (!proofDir) return;
      mkdirSync(proofDir, { recursive: true });
      writeFileSync(
        join(proofDir, `${label}-${name}.json`),
        JSON.stringify(value, null, 2),
      );
    };

    beforeAll(async () => {
      media = mkdtempSync(join(tmpdir(), 'web02-media-'));
      ctx = await web02App(url!, media);
    });
    afterAll(async () => {
      await ctx?.app.close();
      await ctx?.db.$disconnect();
      rmSync(media, { recursive: true, force: true });
    });

    it('captured evidence before the foundation and repaired after the tip', async () => {
      const rows = await ctx.db.$queryRaw<{ migration_name: string }[]>`
        SELECT migration_name FROM _prisma_migrations
        WHERE migration_name >= '20261010' ORDER BY finished_at`;
      expect(rows.map((r) => r.migration_name)).toEqual([
        '20261010110000_web02_capture_public_info_evidence',
        '20261010120000_shared_website_foundation',
        '20261011120000_canonical_menu_sync',
        '20261012120000_web02_restore_public_info_authority',
      ]);
    });

    it('stores the approved values live and keeps every differing draft private', async () => {
      const snapshot: Record<string, unknown> = {};
      for (const f of fixtures) {
        const id = venueId(f.key);
        const [profile, review, config] = await Promise.all([
          ctx.db.venuePublicProfile.findUnique({ where: { venueId: id } }),
          ctx.db.venuePublicInfoReview.findUnique({ where: { venueId: id } }),
          ctx.db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: id },
          }),
        ]);
        expect([
          f.key,
          differingFields(storedInfo(profile), storedInfo(f.expectedLive)),
        ]).toEqual([f.key, []]);
        if (!f.expectedProvenance) expect(review).toBeNull();
        else {
          expect(review).toMatchObject({
            source: 'PRE_FOUNDATION_SNAPSHOT',
            provenance: f.expectedProvenance,
            state: f.expectedPrivateDraft ? 'PENDING' : 'NOT_REQUIRED',
            draftRevision: f.revision,
            publishedRevision: f.publishedRevision,
          });
          if (f.expectedPrivateDraft)
            expect(
              differingFields(
                storedInfo(review!.draftInfo),
                storedInfo(f.expectedPrivateDraft),
              ),
            ).toEqual([]);
          // Published values are recorded exactly; nothing is invented.
          expect(review!.publishedInfo === null).toBe(f.published === null);
        }
        // The foundation's intended move still happened; page content stays.
        for (const doc of [config.draft, config.published] as Record<
          string,
          unknown
        >[]) {
          if (!doc) continue;
          for (const key of MOVED) expect(doc).not.toHaveProperty(key);
          expect(doc.heroTitle).toBe(`Hero ${f.key}`);
        }
        expect(config.revision).toBe(f.revision);
        expect(config.publishedRevision).toBe(f.publishedRevision);
        snapshot[f.key] = {
          live: storedInfo(profile),
          review: review && {
            provenance: review.provenance,
            state: review.state,
            draftInfo: review.draftInfo,
            publishedInfo: review.publishedInfo,
          },
        };
      }
      proof('database', snapshot);
    });

    it('serves SAAS and CUSTOM visitors only the approved values', async () => {
      const results: Record<string, unknown> = {};
      for (const f of fixtures) {
        const bootstrap = await saas(f.key);
        const venue = await site(f.key);
        record(host(f.key), json(bootstrap));
        record(host(f.key), json(venue));
        const launched =
          f.entitled && (f.mode === 'CUSTOM' || f.status === 'PUBLISHED');
        if (f.mode === 'SAAS' && launched) {
          expect(bootstrap.status).toBe(200);
          expect(content(bootstrap).heroTitle).toBe(`Hero ${f.key}`);
          expect(shared(content(bootstrap))).toEqual(f.expectedLive);
        } else if (f.mode === 'CUSTOM') {
          // The SAAS renderer never answers for a CUSTOM Venue.
          expect(bootstrap.status).toBe(200);
          expect(json(bootstrap)).toEqual({ schemaVersion: 2, mode: 'CUSTOM' });
        } else expect(bootstrap.status).toBe(404);
        if (launched) {
          expect(venue.status).toBe(200);
          expect(shared(info(venue))).toEqual(f.expectedLive);
        } else expect([403, 404]).toContain(venue.status);
        results[f.key] = {
          bootstrap: bootstrap.status,
          venue: venue.status,
          shared:
            venue.status === 200
              ? shared(info(venue))
              : bootstrap.status === 200 && content(bootstrap)
                ? shared(content(bootstrap))
                : null,
        };
      }
      // Draft-only SAAS stays unpublished; its CUSTOM counterpart shows nothing.
      expect(results.draftonly).toMatchObject({ bootstrap: 404, venue: 404 });
      expect(results.customdraft).toMatchObject({
        venue: 200,
        shared: emptyLive,
      });
      proof('public', results);
    });

    it('fails closed for unknown and disabled hosts and ignores client Venue ids', async () => {
      for (const h of [unknownHost, disabledHost]) {
        for (const route of ['/api/website/bootstrap', '/api/website/venue']) {
          const response = await ctx.http().get(route).set('Host', h);
          expect([403, 404]).toContain(response.status);
          record(h, json(response));
        }
      }
      const forged = await ctx
        .http()
        .get(`/api/website/venue?venueId=${venueId('customdraft')}`)
        .set('Host', host('divergent'))
        .set('X-Venue-Id', venueId('customdraft'))
        .expect(200);
      expect(shared(info(forged))).toEqual(
        fixtures.find((f) => f.key === 'divergent')!.expectedLive,
      );
      record(host('divergent'), json(forged));
    });

    it('never exposes a private draft value, and no host shows another Venue', () => {
      const all = fixtures.flatMap((f) => privateMarkers(f.key));
      expect(all.length).toBeGreaterThanOrEqual(20);
      expect(bodies.length).toBeGreaterThanOrEqual(fixtures.length * 2 + 5);
      for (const { host: h, body } of bodies) {
        for (const value of all)
          expect([h, value, body.includes(value)]).toEqual([h, value, false]);
        const own = fixtures.find((f) => host(f.key) === h)?.key;
        for (const other of fixtures.filter((f) => f.key !== own))
          for (const marker of markers(other.key))
            expect([h, body.includes(marker)]).toEqual([h, false]);
      }
    });

    it('shows each owner the approved live values with a usable revision', async () => {
      const owner = await ownerToken(ctx.db, ctx.jwt, 'divergent');
      const settings = await ctx
        .http()
        .get(`/customer/venues/${venueId('divergent')}/website`)
        .set(owner.auth)
        .expect(200);
      const fixture = fixtures.find((f) => f.key === 'divergent')!;
      expect(shared(json(settings).shared as Json)).toEqual(
        fixture.expectedLive,
      );
      expect((json(settings).shared as Json).revision).toBe(0);
      for (const value of privateMarkers('divergent'))
        expect(JSON.stringify(json(settings))).not.toContain(value);
      // Tenant isolation of the owner surface is unchanged.
      const foreign = await ctx
        .http()
        .get(`/customer/venues/${venueId('customdiv')}/website`)
        .set(owner.auth);
      expect([403, 404]).toContain(foreign.status);
    });

    it('reports the evidence-backed state without changing anything', async () => {
      const before = await ctx.db.venuePublicProfile.findMany({
        orderBy: { venueId: 'asc' },
      });
      const report = await ctx.db.$transaction(async (tx) => {
        await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');
        return publicInfoReviewReport(tx, {
          launched: (id) => ctx.capabilities.launched(id),
        });
      });
      expect(
        await ctx.db.venuePublicProfile.findMany({
          orderBy: { venueId: 'asc' },
        }),
      ).toEqual(before);
      const fixtureEntries = report.entries.filter((e) =>
        e.venueId.startsWith('web02-'),
      );
      for (const f of fixtures) {
        const entry = fixtureEntries.find((e) => e.venueId === venueId(f.key));
        if (!f.expectedProvenance) {
          expect(entry).toBeUndefined();
          continue;
        }
        expect(entry).toMatchObject({
          basis: 'EVIDENCE',
          provenance: f.expectedProvenance,
          state: f.expectedPrivateDraft ? 'PENDING' : 'NOT_REQUIRED',
          liveMatchesApproved: true,
          action: f.expectedPrivateDraft ? 'DECIDE_PRIVATE_DRAFT' : 'NONE',
        });
        expect(entry!.values).toBeUndefined();
      }
      expect(
        fixtureEntries.filter((e) => e.action !== 'NONE').map((e) => e.venueId),
      ).toEqual(
        fixtures
          .filter((f) => f.expectedPrivateDraft)
          .map((f) => venueId(f.key))
          .sort(),
      );
      expect(
        fixtureEntries.find((e) => e.venueId === venueId('partial'))!
          .draftFields,
      ).toEqual(['socials', 'gallery']);
      proof('report', report);
    });

    it('keeps private draft images through media cleanup until a decision', async () => {
      for (const f of fixtures.filter((x) => x.expectedPrivateDraft)) {
        const refs = await referencedMedia(ctx.db, venueId(f.key));
        if (f.key !== 'partial')
          expect(refs.has(mediaKey(f.key, 'b'))).toBe(true);
      }
      await ctx.logos.cleanup();
      const assets = await ctx.db.websiteMediaAsset.findMany({
        where: { venueId: { startsWith: 'web02-' } },
      });
      const unused = (key: FixtureKey, side: 'a' | 'b') =>
        assets.find((a) => a.storageKey === mediaKey(key, side))!.unusedSince;
      for (const key of [
        'divergent',
        'customdiv',
        'disabled',
        'draftonly',
        'customdraft',
      ] as const)
        expect([key, unused(key, 'b')]).toEqual([key, null]);
      for (const key of [
        'pubonly',
        'synced',
        'divergent',
        'partial',
        'customdiv',
        'disabled',
      ] as const)
        expect([key, unused(key, 'a')]).toEqual([key, null]);
      // The fixture's unreferenced spare stays for the normal 24h retention.
      expect(unused('pubonly', 'b')).not.toBeNull();
      expect(assets).toHaveLength(fixtures.length * 2);
    });

    it('publishes a private draft only through an explicit audited decision', async () => {
      const operator = await platformUser(ctx.db);
      const applied = await decidePublicInfoReview(ctx.db, {
        venueId: venueId('customdiv'),
        decision: 'apply-draft',
        platformUserId: operator.id,
        note: 'Owner asked to publish the saved draft (WEB-02 proof)',
      });
      expect(applied).toMatchObject({ state: 'APPLIED', action: 'NONE' });
      const customdiv = fixtures.find((f) => f.key === 'customdiv')!;
      const now = await site('customdiv').expect(200);
      expect(shared(info(now))).toEqual(customdiv.expectedPrivateDraft);
      expect(
        await ctx.db.platformAuditEvent.findFirst({
          where: {
            targetId: venueId('customdiv'),
            action: 'website.public_info_apply_draft',
            platformUserId: operator.id,
          },
        }),
      ).toMatchObject({
        metadata: {
          decision: 'apply-draft',
          fields: [
            'workingHours',
            'contactEmail',
            'mapUrl',
            'socials',
            'gallery',
          ],
          revisionBefore: 0,
          revisionAfter: 1,
        },
      });
      // A draft-only SAAS site gets its values live, but is still unpublished.
      await decidePublicInfoReview(ctx.db, {
        venueId: venueId('draftonly'),
        decision: 'apply-draft',
        platformUserId: operator.id,
        note: 'Owner approved the saved hours and contacts',
      });
      await saas('draftonly').expect(404);
      await site('draftonly').expect(404);
      // Nothing crossed into another Venue.
      const divergent = await saas('divergent').expect(200);
      expect(shared(content(divergent))).toEqual(
        fixtures.find((f) => f.key === 'divergent')!.expectedLive,
      );
    });

    it('never overwrites a later live owner edit with an older draft', async () => {
      const owner = await ownerToken(ctx.db, ctx.jwt, 'divergent');
      const operator = await platformUser(ctx.db);
      const path = `/customer/venues/${venueId('divergent')}/website/public-info`;
      await ctx
        .http()
        .put(path)
        .set(owner.auth)
        .send({ expectedRevision: 0, contactEmail: 'owner-live@web02.test' })
        .expect(200);
      await expect(
        decidePublicInfoReview(ctx.db, {
          venueId: venueId('divergent'),
          decision: 'apply-draft',
          platformUserId: operator.id,
          note: 'stale decision',
        }),
      ).rejects.toThrow(/contactEmail changed/);
      expect(
        await ctx.db.venuePublicInfoReview.findUnique({
          where: { venueId: venueId('divergent') },
        }),
      ).toMatchObject({ state: 'PENDING' });
      await decidePublicInfoReview(ctx.db, {
        venueId: venueId('divergent'),
        decision: 'dismiss',
        platformUserId: operator.id,
        note: 'Owner discarded the old draft',
      });
      const live = await saas('divergent').expect(200);
      const fixture = fixtures.find((f) => f.key === 'divergent')!;
      expect(shared(content(live))).toEqual({
        ...fixture.expectedLive,
        contactEmail: 'owner-live@web02.test',
      });
      // A dismissed draft's image goes back to ordinary 24h retention.
      expect(
        (await referencedMedia(ctx.db, venueId('divergent'))).has(
          mediaKey('divergent', 'b'),
        ),
      ).toBe(false);
      await ctx.logos.cleanup();
      const asset = await ctx.db.websiteMediaAsset.findUniqueOrThrow({
        where: { storageKey: mediaKey('divergent', 'b') },
      });
      expect(asset.unusedSince).not.toBeNull();
    });

    it('refuses decisions without an active operator, a note or a pending draft', async () => {
      const active = await platformUser(ctx.db);
      const disabled = await platformUser(ctx.db, 'DISABLED');
      const decide = (
        key: FixtureKey,
        decision: 'apply-draft' | 'dismiss' | 'confirm-live' | 'withhold',
        platformUserId = active.id,
        note = 'proof',
      ) =>
        decidePublicInfoReview(ctx.db, {
          venueId: venueId(key),
          decision,
          platformUserId,
          note,
        });
      await expect(
        decide('disabled', 'dismiss', disabled.id),
      ).rejects.toBeInstanceOf(ForbiddenException);
      await expect(
        decide('disabled', 'dismiss', active.id, '  '),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(decide('synced', 'apply-draft')).rejects.toBeInstanceOf(
        ConflictException,
      );
      await expect(decide('disabled', 'withhold')).rejects.toBeInstanceOf(
        ConflictException,
      );
      await expect(decide('disabled', 'confirm-live')).rejects.toBeInstanceOf(
        ConflictException,
      );
      expect(
        await ctx.db.venuePublicInfoReview.findUnique({
          where: { venueId: venueId('disabled') },
        }),
      ).toMatchObject({ state: 'PENDING', decidedAt: null });
    });
  },
);
