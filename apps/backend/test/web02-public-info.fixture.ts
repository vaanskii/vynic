/**
 * WEB-02 pre-foundation fixtures: Venues as they existed before
 * `20261010120000_shared_website_foundation`, when opening hours, contact
 * email, map URL, socials and gallery were fields of the SAAS page document
 * in `VenueWebsiteConfig.draft` / `.published`.
 *
 * One source of truth for the proof runner (which prints the SQL into a
 * disposable database migrated only up to `20261009120000`) and for the
 * upgrade specs (which assert what each Venue shows after the real chain).
 * Every value carries its Venue key and whether it is the published (A) or
 * the private draft (B) value, so a crossed boundary is visible as text.
 *
 *   npx ts-node -T test/web02-public-info.fixture.ts > fixtures.sql
 */

export const WEB02_BASE_DOMAIN = 'vynic.local';

export type MovedInfo = {
  workingHours?: { day: number; opens: string; closes: string }[];
  contactEmail?: string;
  mapUrl?: string;
  socials?: { label: string; url: string }[];
  gallery?: { url: string; alt: string }[];
};

/** What `VenuePublicProfile`/the public payload hold for one Venue. */
export type LiveInfo = {
  workingHours: { day: number; opens: string; closes: string }[];
  contactEmail: string;
  mapUrl: string;
  socials: { label: string; url: string }[];
  gallery: { url: string; alt: string }[];
};

export const emptyLive: LiveInfo = {
  workingHours: [],
  contactEmail: '',
  mapUrl: '',
  socials: [],
  gallery: [],
};

/** A managed media file owned by the fixture Venue (`WebsiteMediaAsset`). */
export function mediaKey(key: string, side: 'a' | 'b') {
  // A stable UUID-shaped key per Venue/side, as uploads produce.
  const n = fixtureKeys.indexOf(key as FixtureKey) + 1;
  const hex = n.toString(16).padStart(4, '0');
  return `${side === 'a' ? 'a' : 'b'}0000000-0000-4000-8000-00000000${hex}.webp`;
}

function info(key: string, side: 'a' | 'b', hours: [string, string]) {
  const label = side === 'a' ? 'published' : 'draft';
  return {
    workingHours: [
      { day: 1, opens: hours[0], closes: hours[1] },
      { day: 5, opens: hours[0], closes: hours[1] },
    ],
    contactEmail: `${side}-${key}@web02.test`,
    mapUrl: `https://maps.example/${side}-${key}`,
    socials: [
      {
        label: `${label} ${key}`,
        url: `https://social.example/${side}-${key}`,
      },
    ],
    gallery: [
      {
        url: `/media/website-logos/${mediaKey(key, side)}`,
        alt: `${label} ${key}`,
      },
    ],
  } satisfies Required<MovedInfo>;
}

export const fixtureKeys = [
  'pubonly',
  'synced',
  'draftonly',
  'divergent',
  'empty',
  'blank',
  'partial',
  'customdraft',
  'customdiv',
  'disabled',
] as const;
export type FixtureKey = (typeof fixtureKeys)[number];

export type Fixture = {
  key: FixtureKey;
  /** Which class of the WEB-02 acceptance matrix the Venue represents. */
  scenario: string;
  mode: 'SAAS' | 'CUSTOM';
  status: 'DRAFT' | 'PUBLISHED';
  revision: number;
  publishedRevision: number | null;
  /** Moved fields in the draft; `null` = no draft document at all. */
  draft: MovedInfo | null;
  /** Moved fields in the published snapshot; `null` = never published. */
  published: MovedInfo | null;
  entitled: boolean;
  /** Provenance class the captured evidence proves. */
  expectedProvenance: 'EMPTY' | 'PUBLISHED' | 'DRAFT_ONLY' | 'DIVERGENT' | null;
  /** What the post-hoc report infers after the unmodified historical chain. */
  inferredProvenance:
    | 'NOT_AFFECTED'
    | 'PUBLISHED'
    | 'DRAFT_ONLY'
    | 'AMBIGUOUS'
    | null;
  /** Public shared information after a correct upgrade. */
  expectedLive: LiveInfo;
  /** Private draft kept for owner/operator review, or null when none. */
  expectedPrivateDraft: LiveInfo | null;
  /** What the unmodified historical chain puts live (the defect). */
  historicalLive: LiveInfo | null;
};

const live = (value: MovedInfo): LiveInfo => ({ ...emptyLive, ...value });

const A = (key: string) => info(key, 'a', ['09:00', '18:00']);
const B = (key: string) => info(key, 'b', ['11:00', '23:00']);
const empty: Required<MovedInfo> = {
  workingHours: [],
  contactEmail: '',
  mapUrl: '',
  socials: [],
  gallery: [],
};
// A legacy draft saved before socials/gallery existed in the document: the
// hours/contact equal the published values, the other two keys are absent.
const partialDraft = (key: string): MovedInfo => {
  const { workingHours, contactEmail, mapUrl } = A(key);
  return { workingHours, contactEmail, mapUrl };
};

export const fixtures: Fixture[] = [
  {
    key: 'pubonly',
    scenario: 'A. published only (no draft document)',
    mode: 'SAAS',
    status: 'PUBLISHED',
    revision: 1,
    publishedRevision: 1,
    draft: null,
    published: A('pubonly'),
    entitled: true,
    expectedProvenance: 'PUBLISHED',
    inferredProvenance: 'PUBLISHED',
    expectedLive: live(A('pubonly')),
    expectedPrivateDraft: null,
    historicalLive: live(A('pubonly')),
  },
  {
    key: 'synced',
    scenario: 'A. published, draft identical',
    mode: 'SAAS',
    status: 'PUBLISHED',
    revision: 2,
    publishedRevision: 2,
    draft: A('synced'),
    published: A('synced'),
    entitled: true,
    expectedProvenance: 'PUBLISHED',
    inferredProvenance: 'PUBLISHED',
    expectedLive: live(A('synced')),
    expectedPrivateDraft: null,
    historicalLive: live(A('synced')),
  },
  {
    key: 'draftonly',
    scenario: 'B. draft only, never published',
    mode: 'SAAS',
    status: 'DRAFT',
    revision: 1,
    publishedRevision: null,
    draft: B('draftonly'),
    published: null,
    entitled: true,
    expectedProvenance: 'DRAFT_ONLY',
    inferredProvenance: 'DRAFT_ONLY',
    expectedLive: emptyLive,
    expectedPrivateDraft: live(B('draftonly')),
    historicalLive: live(B('draftonly')),
  },
  {
    key: 'divergent',
    scenario: 'C. published A, unpublished draft B',
    mode: 'SAAS',
    status: 'PUBLISHED',
    revision: 4,
    publishedRevision: 3,
    draft: B('divergent'),
    published: A('divergent'),
    entitled: true,
    expectedProvenance: 'DIVERGENT',
    inferredProvenance: 'AMBIGUOUS',
    expectedLive: live(A('divergent')),
    expectedPrivateDraft: live(B('divergent')),
    historicalLive: live(B('divergent')),
  },
  {
    key: 'empty',
    scenario: 'D. published and draft both empty',
    mode: 'SAAS',
    status: 'PUBLISHED',
    revision: 1,
    publishedRevision: 1,
    draft: empty,
    published: empty,
    entitled: true,
    expectedProvenance: 'EMPTY',
    inferredProvenance: 'NOT_AFFECTED',
    expectedLive: emptyLive,
    expectedPrivateDraft: null,
    historicalLive: emptyLive,
  },
  {
    key: 'blank',
    scenario: 'D. no draft and no published document',
    mode: 'SAAS',
    status: 'DRAFT',
    revision: 0,
    publishedRevision: null,
    draft: null,
    published: null,
    entitled: true,
    expectedProvenance: null,
    inferredProvenance: null,
    expectedLive: emptyLive,
    expectedPrivateDraft: null,
    historicalLive: null,
  },
  {
    key: 'partial',
    scenario: 'C. legacy partial draft drops published socials/gallery',
    mode: 'SAAS',
    status: 'PUBLISHED',
    revision: 3,
    publishedRevision: 2,
    draft: partialDraft('partial'),
    published: A('partial'),
    entitled: true,
    expectedProvenance: 'DIVERGENT',
    inferredProvenance: 'AMBIGUOUS',
    expectedLive: live(A('partial')),
    expectedPrivateDraft: live(partialDraft('partial')),
    historicalLive: live(partialDraft('partial')),
  },
  {
    key: 'customdraft',
    scenario: 'B. CUSTOM Venue with a leftover never-published SAAS draft',
    mode: 'CUSTOM',
    status: 'DRAFT',
    revision: 1,
    publishedRevision: null,
    draft: B('customdraft'),
    published: null,
    entitled: true,
    expectedProvenance: 'DRAFT_ONLY',
    inferredProvenance: 'DRAFT_ONLY',
    expectedLive: emptyLive,
    expectedPrivateDraft: live(B('customdraft')),
    historicalLive: live(B('customdraft')),
  },
  {
    key: 'customdiv',
    scenario: 'C. CUSTOM Venue, earlier SAAS publication A, draft B',
    mode: 'CUSTOM',
    status: 'PUBLISHED',
    revision: 5,
    publishedRevision: 4,
    draft: B('customdiv'),
    published: A('customdiv'),
    entitled: true,
    expectedProvenance: 'DIVERGENT',
    inferredProvenance: 'AMBIGUOUS',
    expectedLive: live(A('customdiv')),
    expectedPrivateDraft: live(B('customdiv')),
    historicalLive: live(B('customdiv')),
  },
  {
    key: 'disabled',
    scenario: 'C. Website entitlement withheld, published A, draft B',
    mode: 'SAAS',
    status: 'PUBLISHED',
    revision: 2,
    publishedRevision: 1,
    draft: B('disabled'),
    published: A('disabled'),
    entitled: false,
    expectedProvenance: 'DIVERGENT',
    inferredProvenance: 'AMBIGUOUS',
    expectedLive: live(A('disabled')),
    expectedPrivateDraft: live(B('disabled')),
    historicalLive: live(B('disabled')),
  },
];

export const venueId = (key: FixtureKey) => `web02-venue-${key}`;
export const slug = (key: FixtureKey) => `web02-${key}`;
export const host = (key: FixtureKey) => `${slug(key)}.${WEB02_BASE_DOMAIN}`;
/** A registered but operator-disabled hostname of the `synced` Venue. */
export const disabledHost = `web02-synced-disabled.${WEB02_BASE_DOMAIN}`;
export const unknownHost = `web02-unknown.${WEB02_BASE_DOMAIN}`;

/** The complete pre-foundation (schema version 2) SAAS page document. */
function document(f: Fixture, moved: MovedInfo) {
  return {
    slug: slug(f.key),
    themeKey: 'classic',
    logoUrl: '',
    heroTitle: `Hero ${f.key}`,
    heroSubtitle: '',
    heroImageUrl: '',
    about: '',
    aboutImageUrl: '',
    showMenu: true,
    menuHeading: '',
    menuIntro: '',
    seoTitle: '',
    seoDescription: '',
    showMap: true,
    footerNote: '',
    ...moved,
  };
}

const lit = (value: unknown) =>
  value === null || value === undefined
    ? 'NULL'
    : `'${(typeof value === 'string' ? value : JSON.stringify(value)).replace(/'/g, "''")}'`;

/** SQL for the pre-foundation schema (migrations through `20261009120000`). */
export function fixtureSql() {
  const lines = ['BEGIN;'];
  for (const f of fixtures) {
    const v = venueId(f.key);
    lines.push(
      `INSERT INTO pos."Organization" (id,name,"updatedAt") VALUES (${lit(`web02-org-${f.key}`)},${lit(`WEB02 ${f.key}`)},now());`,
      `INSERT INTO pos."Venue" (id,"organizationId",name,timezone,currency,address,"legacyCommercialAccess","updatedAt") VALUES (${lit(v)},${lit(`web02-org-${f.key}`)},${lit(`WEB02 ${f.key}`)},'Asia/Tbilisi','GEL',${lit(`${f.key} street`)},false,now());`,
      `INSERT INTO pos."VenueSubscription" ("venueId",status,"startedAt","updatedAt") VALUES (${lit(v)},'ACTIVE',now(),now());`,
      `INSERT INTO pos."VenuePlanAssignment" ("venueId","planId","updatedAt") SELECT ${lit(v)},id,now() FROM pos."Plan" WHERE key='WEBSITE_ONLY';`,
      `INSERT INTO pos."VenueFeatureOverride" ("venueId","featureId",effect,"updatedAt") SELECT ${lit(v)},id,${lit(f.entitled ? 'ENABLED' : 'DISABLED')},now() FROM pos."Feature" WHERE key='WEBSITE';`,
      `INSERT INTO pos."VenueWebsiteConfig" ("venueId",mode,status,slug,"assignedSlug",draft,revision,published,"publishedRevision","publishedAt","updatedAt") VALUES (${lit(v)},${lit(f.mode)},${lit(f.status)},${f.published ? lit(slug(f.key)) : 'NULL'},${lit(slug(f.key))},${f.draft ? lit(document(f, f.draft)) : 'NULL'}::jsonb,${f.revision},${f.published ? lit(document(f, f.published)) : 'NULL'}::jsonb,${f.publishedRevision ?? 'NULL'},${f.published ? "now() - interval '2 days'" : 'NULL'},now() - interval '1 day');`,
      `INSERT INTO pos."VenueDomain" (id,"venueId",hostname,"updatedAt") VALUES (${lit(`web02-domain-${f.key}`)},${lit(v)},${lit(host(f.key))},now());`,
    );
    if (f.mode === 'CUSTOM')
      lines.push(
        `INSERT INTO pos."CustomWebsiteBinding" ("venueId","siteKey",status,"updatedAt") VALUES (${lit(v)},${lit(`web02-${f.key}-web`)},'ACTIVE',now());`,
      );
    for (const side of ['a', 'b'] as const)
      lines.push(
        `INSERT INTO pos."WebsiteMediaAsset" (id,"venueId","storageKey",purpose,"byteSize","unusedSince") VALUES (${lit(`web02-asset-${f.key}-${side}`)},${lit(v)},${lit(mediaKey(f.key, side))},'gallery',1024,NULL);`,
      );
  }
  lines.push(
    `INSERT INTO pos."VenueDomain" (id,"venueId",hostname,status,"updatedAt") VALUES ('web02-domain-synced-disabled',${lit(venueId('synced'))},${lit(disabledHost)},'DISABLED',now());`,
    'COMMIT;',
  );
  return lines.join('\n') + '\n';
}

if (require.main === module) process.stdout.write(fixtureSql());
