import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  PrismaClient,
  PublicInfoProvenance,
  PublicInfoReviewState,
  WebsiteMode,
} from '@prisma/client';
import {
  websiteContactEmail,
  websiteGallery,
  websiteMapUrl,
  websiteSocials,
  websiteWorkingHours,
} from './website-content';
import { validateMediaReferences } from './website-media';

/**
 * WEB-02: publication authority over the Venue public information that
 * `20261010120000_shared_website_foundation` moved out of the SAAS documents.
 *
 * Migration is not publication consent. Where evidence was captured before
 * that migration (`20261010110000`), `20261012120000` already restored the
 * published values and kept a differing draft private. Where the migration ran
 * before evidence was kept, the draft/published distinction is gone; this
 * module reports what the remaining provenance still proves and records
 * explicit, audited owner/operator decisions. It never guesses a value.
 * See `docs/WEB02_SAFE_PUBLICATION_MIGRATION.md`.
 */
export const FOUNDATION_MIGRATION = '20261010120000_shared_website_foundation';

export const PUBLIC_INFO_FIELDS = [
  'workingHours',
  'contactEmail',
  'mapUrl',
  'socials',
  'gallery',
] as const;
export type PublicInfoField = (typeof PUBLIC_INFO_FIELDS)[number];

/** Public information in the `VenuePublicProfile` column shape. */
export type StoredPublicInfo = {
  workingHours: Prisma.JsonValue;
  contactEmail: string | null;
  mapUrl: string | null;
  socials: Prisma.JsonValue;
  gallery: Prisma.JsonValue;
};

export const EMPTY_PUBLIC_INFO: StoredPublicInfo = {
  workingHours: [],
  contactEmail: null,
  mapUrl: null,
  socials: [],
  gallery: [],
};

/** A profile row or a stored review document; absent means no information. */
export function storedInfo(value: unknown): StoredPublicInfo {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return { ...EMPTY_PUBLIC_INFO };
  const row = value as Record<string, unknown>;
  const text = (v: unknown) => (typeof v === 'string' && v ? v : null);
  return {
    workingHours: row.workingHours ?? [],
    contactEmail: text(row.contactEmail),
    mapUrl: text(row.mapUrl),
    socials: row.socials ?? [],
    gallery: row.gallery ?? [],
  };
}

/** Structural equality with object keys order-insensitive, like jsonb `=`. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object')
    return `{${Object.keys(value)
      .sort()
      .map(
        (k) =>
          `${JSON.stringify(k)}:${canonical((value as Record<string, unknown>)[k])}`,
      )
      .join(',')}}`;
  return JSON.stringify(value ?? null);
}

export function differingFields(
  a: StoredPublicInfo,
  b: StoredPublicInfo,
): PublicInfoField[] {
  return PUBLIC_INFO_FIELDS.filter(
    (field) => canonical(a[field]) !== canonical(b[field]),
  );
}

function isEmptyField(value: unknown) {
  return (
    value === null ||
    value === '' ||
    (Array.isArray(value) && value.length === 0)
  );
}

export type ReviewAction =
  | 'NONE'
  /** A private draft (or withheld values) awaits apply-draft or dismiss. */
  | 'DECIDE_PRIVATE_DRAFT'
  /** Provably never published but live: withhold unless the owner approves. */
  | 'WITHHOLD_RECOMMENDED'
  /** Provenance lost: the owner confirms the live values or they are withheld. */
  | 'CONFIRM_OR_WITHHOLD';

export type InferredProvenance = {
  provenance: PublicInfoProvenance | 'NOT_AFFECTED';
  migratedFields: PublicInfoField[];
  action: ReviewAction;
  reasons: string[];
};

/**
 * What the remaining provenance proves about a Venue whose information was
 * moved before evidence was kept. Pure, so the rules are unit tested.
 *
 * - A non-empty live field that no audited owner save touched can only have
 *   come from the migration (owner saves always audit the changed fields).
 * - Nothing clears `published`, so a missing published document proves the
 *   moved values came from a draft that was never published.
 * - Draft and published documents were identical exactly when their revisions
 *   matched; that is provable only if the settings row has not been written
 *   since the migration finished.
 * Anything else is AMBIGUOUS and needs an explicit decision.
 */
export function inferProvenance(input: {
  live: StoredPublicInfo;
  ownerEditedFields: PublicInfoField[];
  config: {
    published: unknown;
    revision: number;
    publishedRevision: number | null;
    updatedAt: Date;
  } | null;
  migratedAt: Date | null;
}): InferredProvenance {
  const migratedFields = PUBLIC_INFO_FIELDS.filter(
    (field) =>
      !input.ownerEditedFields.includes(field) &&
      !isEmptyField(input.live[field]),
  );
  if (!migratedFields.length)
    return {
      provenance: 'NOT_AFFECTED',
      migratedFields,
      action: 'NONE',
      reasons: ['no live value remains from the migration'],
    };
  const { config, migratedAt } = input;
  if (!config)
    return {
      provenance: 'AMBIGUOUS',
      migratedFields,
      action: 'CONFIRM_OR_WITHHOLD',
      reasons: ['no website settings remain to compare against'],
    };
  if (config.published === null || config.published === undefined)
    return {
      provenance: 'DRAFT_ONLY',
      migratedFields,
      action: 'WITHHOLD_RECOMMENDED',
      reasons: ['never published: the values came from an unpublished draft'],
    };
  const reasons: string[] = [];
  if (!migratedAt) reasons.push('the foundation migration time is unknown');
  else if (config.updatedAt > migratedAt)
    reasons.push(
      'website settings changed after the migration, so the draft/published revisions at that time are unknown',
    );
  if (config.revision !== config.publishedRevision)
    reasons.push(
      'the draft had unpublished changes; whether they touched these fields is no longer knowable',
    );
  if (!reasons.length)
    return {
      provenance: 'PUBLISHED',
      migratedFields,
      action: 'NONE',
      reasons: [
        'draft and published were the same revision when the migration ran',
      ],
    };
  return {
    provenance: 'AMBIGUOUS',
    migratedFields,
    action: 'CONFIRM_OR_WITHHOLD',
    reasons,
  };
}

type Db = PrismaClient | Prisma.TransactionClient;

export type ReviewEntry = {
  venueId: string;
  venueName: string;
  websiteMode: WebsiteMode | null;
  publicationStatus: string | null;
  /** Whether the Venue serves a website now (when the caller can tell). */
  launched: boolean | null;
  basis: 'EVIDENCE' | 'DECISION' | 'INFERENCE';
  provenance: PublicInfoProvenance | 'NOT_AFFECTED';
  state: PublicInfoReviewState | null;
  /** Fields where the private draft differs from the approved values. */
  draftFields: PublicInfoField[];
  /** Live fields that still hold what the migration wrote (inference only). */
  migratedFields: PublicInfoField[];
  /** Fields the owner saved live after the migration. */
  ownerEditedFields: PublicInfoField[];
  liveMatchesApproved: boolean | null;
  action: ReviewAction;
  reasons: string[];
  values?: {
    live: StoredPublicInfo;
    approved: StoredPublicInfo | null;
    privateDraft: StoredPublicInfo | null;
  };
};

export async function foundationMigratedAt(db: Db): Promise<Date | null> {
  // The ledger lives in the connection's default schema; never assume which.
  const [ledger] = await db.$queryRaw<{ present: boolean }[]>`
    SELECT to_regclass('_prisma_migrations') IS NOT NULL AS present`;
  if (!ledger?.present) return null;
  const rows = await db.$queryRaw<{ finished_at: Date }[]>`
    SELECT finished_at FROM _prisma_migrations
    WHERE migration_name = ${FOUNDATION_MIGRATION}
      AND finished_at IS NOT NULL AND rolled_back_at IS NULL
    ORDER BY finished_at LIMIT 1`;
  return rows[0]?.finished_at ?? null;
}

async function ownerEditedFields(
  db: Db,
  venueIds: string[],
): Promise<Map<string, PublicInfoField[]>> {
  const events = await db.customerAuditEvent.findMany({
    where: {
      targetId: { in: venueIds },
      action: 'website.public_info_saved',
    },
    select: { targetId: true, metadata: true },
  });
  const edited = new Map<string, PublicInfoField[]>();
  for (const event of events) {
    const fields = (event.metadata as { fields?: unknown } | null)?.fields;
    const list = edited.get(event.targetId) ?? [];
    if (Array.isArray(fields))
      for (const field of fields)
        if (
          PUBLIC_INFO_FIELDS.includes(field as PublicInfoField) &&
          !list.includes(field as PublicInfoField)
        )
          list.push(field as PublicInfoField);
    edited.set(event.targetId, list);
  }
  return edited;
}

/**
 * Read-only affected-state report: every Venue with live public information
 * or a WEB-02 review row. Values are included only on request.
 */
export async function publicInfoReviewReport(
  db: Db,
  options: {
    venueId?: string;
    includeValues?: boolean;
    launched?: (venueId: string) => Promise<boolean>;
  } = {},
) {
  const venueFilter = options.venueId ? { venueId: options.venueId } : {};
  const [migratedAt, profiles, reviews] = await Promise.all([
    foundationMigratedAt(db),
    db.venuePublicProfile.findMany({ where: venueFilter }),
    db.venuePublicInfoReview.findMany({ where: venueFilter }),
  ]);
  const ids = [
    ...new Set([
      ...profiles.map((p) => p.venueId),
      ...reviews.map((r) => r.venueId),
    ]),
  ].sort();
  const [venues, configs, edited] = await Promise.all([
    db.venue.findMany({
      where: { id: { in: ids } },
      select: { id: true, name: true },
    }),
    db.venueWebsiteConfig.findMany({ where: { venueId: { in: ids } } }),
    ownerEditedFields(db, ids),
  ]);
  const entries: ReviewEntry[] = [];
  for (const venueId of ids) {
    const profile = profiles.find((p) => p.venueId === venueId) ?? null;
    const review = reviews.find((r) => r.venueId === venueId) ?? null;
    const config = configs.find((c) => c.venueId === venueId) ?? null;
    const live = storedInfo(profile);
    const owner = edited.get(venueId) ?? [];
    const base = {
      venueId,
      venueName: venues.find((v) => v.id === venueId)?.name ?? '',
      websiteMode: config?.mode ?? null,
      publicationStatus: config?.status ?? null,
      launched: options.launched ? await options.launched(venueId) : null,
      ownerEditedFields: owner,
    };
    let entry: ReviewEntry;
    if (review) {
      const approved =
        review.publishedInfo === null
          ? { ...EMPTY_PUBLIC_INFO }
          : storedInfo(review.publishedInfo);
      const draft =
        review.draftInfo === null ? null : storedInfo(review.draftInfo);
      entry = {
        ...base,
        basis:
          review.source === 'PRE_FOUNDATION_SNAPSHOT' ? 'EVIDENCE' : 'DECISION',
        provenance: review.provenance,
        state: review.state,
        draftFields: draft ? differingFields(draft, approved) : [],
        migratedFields: [],
        liveMatchesApproved: differingFields(live, approved).length === 0,
        action: review.state === 'PENDING' ? 'DECIDE_PRIVATE_DRAFT' : 'NONE',
        reasons: [],
      };
      if (options.includeValues)
        entry.values = { live, approved, privateDraft: draft };
    } else {
      const inferred = inferProvenance({
        live,
        ownerEditedFields: owner,
        config,
        migratedAt,
      });
      entry = {
        ...base,
        basis: 'INFERENCE',
        provenance: inferred.provenance,
        state: null,
        draftFields: [],
        migratedFields: inferred.migratedFields,
        liveMatchesApproved: null,
        action: inferred.action,
        reasons: inferred.reasons,
      };
      if (options.includeValues)
        entry.values = { live, approved: null, privateDraft: null };
    }
    entries.push(entry);
  }
  return {
    foundationMigration: FOUNDATION_MIGRATION,
    foundationMigratedAt: migratedAt,
    entries,
    requiringDecision: entries.filter((e) => e.action !== 'NONE').length,
  };
}

export const publicInfoDecisions = [
  'apply-draft',
  'dismiss',
  'confirm-live',
  'withhold',
] as const;
export type PublicInfoDecision = (typeof publicInfoDecisions)[number];

/** Current parsers, so a stale document cannot reach a live row unvalidated. */
const parsers: Record<PublicInfoField, (info: StoredPublicInfo) => unknown> = {
  workingHours: (info) => websiteWorkingHours(info.workingHours),
  contactEmail: (info) => websiteContactEmail(info.contactEmail ?? '') || null,
  mapUrl: (info) => websiteMapUrl(info.mapUrl ?? '') || null,
  socials: (info) => websiteSocials(info.socials),
  gallery: (info) => websiteGallery(info.gallery),
};

function columns(info: StoredPublicInfo, fields: PublicInfoField[]) {
  const data: Prisma.VenuePublicProfileUpdateInput = {};
  for (const field of fields) {
    if (field === 'contactEmail' || field === 'mapUrl')
      data[field] = info[field];
    else data[field] = info[field] as Prisma.InputJsonValue;
  }
  return data;
}

const json = (info: StoredPublicInfo) => info as Prisma.InputJsonValue;

/**
 * One explicit owner/operator decision, attributed to an active PlatformUser
 * and audited. Compare-and-set against the live row: a field the owner has
 * changed since the evidence was taken is never overwritten.
 *
 * - `apply-draft`: publish the private draft (or withheld values).
 * - `dismiss`: discard the private draft; live values stay.
 * - `confirm-live` / `withhold`: for information moved before evidence was
 *   kept, confirm the live values as approved, or move the migrated values
 *   into a private draft and clear them from the public profile.
 */
export async function decidePublicInfoReview(
  db: PrismaClient,
  input: {
    venueId: string;
    decision: PublicInfoDecision;
    platformUserId: string;
    note: string;
  },
) {
  const note = input.note.trim();
  if (!publicInfoDecisions.includes(input.decision))
    throw new BadRequestException('Unknown decision');
  if (!note || note.length > 500)
    throw new BadRequestException('A decision note (max 500) is required');
  return db.$transaction(async (tx) => {
    const actor = await tx.platformUser.findUnique({
      where: { id: input.platformUserId },
      select: { status: true },
    });
    if (actor?.status !== 'ACTIVE')
      throw new ForbiddenException('An active platform user must decide');
    const { venueId } = input;
    // Same lock as owner saves: a decision and a live edit never interleave.
    const locked = await tx.$queryRaw<
      unknown[]
    >`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
    if (!locked.length) throw new NotFoundException('Venue not found');
    const [review, profile] = await Promise.all([
      tx.venuePublicInfoReview.findUnique({ where: { venueId } }),
      tx.venuePublicProfile.findUnique({ where: { venueId } }),
    ]);
    const live = storedInfo(profile);
    const now = new Date();
    const decided = {
      decidedAt: now,
      decidedBy: input.platformUserId,
      decisionNote: note,
    };
    let fields: PublicInfoField[] = [];
    let revision = profile?.revision ?? 0;

    const writeLive = async (next: StoredPublicInfo) => {
      fields = differingFields(live, next);
      if (!fields.length) return;
      await tx.$executeRaw`INSERT INTO "pos"."VenuePublicProfile" ("venueId", "updatedAt") VALUES (${venueId}, CURRENT_TIMESTAMP) ON CONFLICT DO NOTHING`;
      revision += 1;
      await tx.venuePublicProfile.update({
        where: { venueId },
        data: { ...columns(next, fields), revision },
      });
    };

    if (input.decision === 'apply-draft' || input.decision === 'dismiss') {
      if (review?.state !== 'PENDING' || review.draftInfo === null)
        throw new ConflictException('No private draft awaits a decision');
      if (input.decision === 'apply-draft') {
        const approved =
          review.publishedInfo === null
            ? { ...EMPTY_PUBLIC_INFO }
            : storedInfo(review.publishedInfo);
        const draft = storedInfo(review.draftInfo);
        const changes = differingFields(draft, approved);
        const liveChanged = differingFields(live, approved);
        const moved = changes.filter((field) => liveChanged.includes(field));
        if (moved.length)
          throw new ConflictException(
            `Live ${moved.join(', ')} changed since the review was recorded; decide again from the current values`,
          );
        const next = { ...live };
        for (const field of changes)
          Object.assign(next, { [field]: parsers[field](draft) });
        // Legacy unmanaged references may stay with the Venue they came from.
        if (changes.includes('gallery'))
          await validateMediaReferences(tx, venueId, next.gallery, [
            live.gallery,
            review.draftInfo,
            review.publishedInfo,
          ]);
        await writeLive(next);
      }
      await tx.venuePublicInfoReview.update({
        where: { venueId },
        data: {
          state: input.decision === 'apply-draft' ? 'APPLIED' : 'DISMISSED',
          ...decided,
        },
      });
    } else {
      if (review)
        throw new ConflictException(
          'This Venue already has WEB-02 evidence or a decision',
        );
      const [config, migratedAt, edited] = await Promise.all([
        tx.venueWebsiteConfig.findUnique({ where: { venueId } }),
        foundationMigratedAt(tx),
        ownerEditedFields(tx, [venueId]),
      ]);
      const inferred = inferProvenance({
        live,
        ownerEditedFields: edited.get(venueId) ?? [],
        config,
        migratedAt,
      });
      if (
        inferred.provenance !== 'DRAFT_ONLY' &&
        inferred.provenance !== 'AMBIGUOUS'
      )
        throw new ConflictException('No migrated information needs review');
      let publicAfter = live;
      if (input.decision === 'withhold') {
        publicAfter = { ...live };
        for (const field of inferred.migratedFields)
          Object.assign(publicAfter, { [field]: EMPTY_PUBLIC_INFO[field] });
        await writeLive(publicAfter);
      }
      await tx.venuePublicInfoReview.create({
        data: {
          venueId,
          source: 'POST_MIGRATION_REVIEW',
          provenance: inferred.provenance,
          state: input.decision === 'withhold' ? 'PENDING' : 'CONFIRMED',
          // Withheld values stay recoverable, privately.
          draftInfo: input.decision === 'withhold' ? json(live) : undefined,
          publishedInfo: json(publicAfter),
          migratedInfo: json(live),
          draftRevision: config?.revision ?? null,
          publishedRevision: config?.publishedRevision ?? null,
          ...decided,
        },
      });
    }
    await tx.platformAuditEvent.create({
      data: {
        platformUserId: input.platformUserId,
        action: `website.public_info_${input.decision.replace('-', '_')}`,
        targetType: 'Venue',
        targetId: venueId,
        metadata: {
          decision: input.decision,
          fields,
          revisionBefore: profile?.revision ?? 0,
          revisionAfter: revision,
          note,
        },
      },
    });
    return (await publicInfoReviewReport(tx, { venueId })).entries.find(
      (e) => e.venueId === venueId,
    )!;
  });
}
