import 'reflect-metadata';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { differingFields, storedInfo } from './public-info-review';
import {
  fixtures,
  host,
  venueId,
  type FixtureKey,
} from '../../../test/web02-public-info.fixture';
import {
  shared,
  web02App,
  content,
  info,
  json,
} from '../../../test/web02-public-info.harness';

/**
 * WEB-02 defect reproduction: the same pre-foundation fixtures upgraded
 * through the ORIGINAL chain (the 60 migrations at `64d668f`, without the
 * WEB-02 evidence/repair migrations). These assertions pass exactly when the
 * unsafe behaviour exists; they document it, they do not accept it.
 */
const url = process.env.WEB02_REPRODUCTION_DATABASE_URL;
const proofDir = process.env.WEB02_PROOF_DIR;

(url ? describe : describe.skip)(
  'WEB-02 reproduction: original shared-foundation chain (real PostgreSQL / Nest HTTP)',
  () => {
    let ctx: Awaited<ReturnType<typeof web02App>>;
    let media: string;
    const fixture = (key: FixtureKey) => fixtures.find((f) => f.key === key)!;

    beforeAll(async () => {
      media = mkdtempSync(join(tmpdir(), 'web02-media-'));
      ctx = await web02App(url!, media);
    });
    afterAll(async () => {
      await ctx?.app.close();
      await ctx?.db.$disconnect();
      rmSync(media, { recursive: true, force: true });
    });

    it('is the original chain: no WEB-02 evidence table or migrations', async () => {
      const [{ table }] = await ctx.db.$queryRaw<{ table: string | null }[]>`
        SELECT to_regclass('"pos"."VenuePublicInfoReview"')::text AS table`;
      expect(table).toBeNull();
      const names = await ctx.db.$queryRaw<{ migration_name: string }[]>`
        SELECT migration_name FROM _prisma_migrations ORDER BY migration_name`;
      expect(names).toHaveLength(60);
      expect(names.at(-1)!.migration_name).toBe(
        '20261011120000_canonical_menu_sync',
      );
    });

    it('copies the draft, not the published version, into live storage and deletes the published values', async () => {
      const state: Record<string, unknown> = {};
      for (const f of fixtures) {
        const [profile, config] = await Promise.all([
          ctx.db.venuePublicProfile.findUnique({
            where: { venueId: venueId(f.key) },
          }),
          ctx.db.venueWebsiteConfig.findUniqueOrThrow({
            where: { venueId: venueId(f.key) },
          }),
        ]);
        if (f.historicalLive === null) expect(profile).toBeNull();
        else
          expect([
            f.key,
            differingFields(storedInfo(profile), storedInfo(f.historicalLive)),
          ]).toEqual([f.key, []]);
        for (const doc of [config.draft, config.published] as Record<
          string,
          unknown
        >[])
          if (doc) expect(doc).not.toHaveProperty('contactEmail');
        state[f.key] = {
          live: storedInfo(profile),
          safe:
            differingFields(storedInfo(profile), storedInfo(f.expectedLive))
              .length === 0,
        };
      }
      const unsafe = Object.entries(state)
        .filter(([, v]) => !(v as { safe: boolean }).safe)
        .map(([k]) => k)
        .sort();
      expect(unsafe).toEqual([
        'customdiv',
        'customdraft',
        'disabled',
        'divergent',
        'draftonly',
        'partial',
      ]);
      if (proofDir) {
        mkdirSync(proofDir, { recursive: true });
        writeFileSync(
          join(proofDir, 'reproduction-database.json'),
          JSON.stringify({ unsafe, state }, null, 2),
        );
      }
    });

    it('serves the unpublished draft B to SAAS visitors instead of published A', async () => {
      const response = await ctx
        .http()
        .get('/api/website/bootstrap')
        .set('Host', host('divergent'))
        .expect(200);
      expect(shared(content(response))).toEqual(
        fixture('divergent').historicalLive,
      );
      expect(content(response).contactEmail).toBe('b-divergent@web02.test');
      expect(JSON.stringify(json(response))).not.toContain(
        'a-divergent@web02.test',
      );
    });

    it('makes a never-published draft public on a CUSTOM site with no publish action', async () => {
      const response = await ctx
        .http()
        .get('/api/website/venue')
        .set('Host', host('customdraft'))
        .expect(200);
      expect(shared(info(response))).toEqual(
        fixture('customdraft').historicalLive,
      );
      expect(info(response).contactEmail).toBe('b-customdraft@web02.test');
    });

    it('drops published socials and gallery when a legacy draft lacked them', async () => {
      const response = await ctx
        .http()
        .get('/api/website/bootstrap')
        .set('Host', host('partial'))
        .expect(200);
      expect(content(response).socials).toEqual([]);
      expect(content(response).gallery).toEqual([]);
      expect(
        fixture('partial').published!.socials!.length +
          fixture('partial').published!.gallery!.length,
      ).toBe(2);
    });

    it('leaves published-only and empty Venues correct', async () => {
      for (const key of ['pubonly', 'synced', 'empty'] as const) {
        const response = await ctx
          .http()
          .get('/api/website/bootstrap')
          .set('Host', host(key))
          .expect(200);
        expect(shared(content(response))).toEqual(fixture(key).expectedLive);
      }
    });
  },
);
