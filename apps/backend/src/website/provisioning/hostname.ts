import {
  BadRequestException,
  ConflictException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { normalizeHostname } from '../tenancy/website-host';
import {
  emptyWebsiteContent,
  readWebsiteContent,
  websiteSlug,
} from '../core/website-content';
const georgian: Record<string, string> = {
  ა: 'a',
  ბ: 'b',
  გ: 'g',
  დ: 'd',
  ე: 'e',
  ვ: 'v',
  ზ: 'z',
  თ: 't',
  ი: 'i',
  კ: 'k',
  ლ: 'l',
  მ: 'm',
  ნ: 'n',
  ო: 'o',
  პ: 'p',
  ჟ: 'zh',
  რ: 'r',
  ს: 's',
  ტ: 't',
  უ: 'u',
  ფ: 'p',
  ქ: 'k',
  ღ: 'gh',
  ყ: 'q',
  შ: 'sh',
  ჩ: 'ch',
  ც: 'ts',
  ძ: 'dz',
  წ: 'ts',
  ჭ: 'ch',
  ხ: 'kh',
  ჯ: 'j',
  ჰ: 'h',
};

/**
 * Names a restaurant may not newly receive or request as its SaaS address.
 *
 * Broader than the format rule in `websiteSlug`, which also validates content
 * already stored: an existing address stays valid even if its name is listed.
 */
const reservedSaasNames = new Set([
  'www',
  'api',
  'admin',
  'app',
  'mail',
  'platform',
  'vynic',
  'dashboard',
  'login',
  'auth',
  'account',
  'accounts',
  'billing',
  'support',
  'help',
  'status',
  'docs',
  'blog',
  'media',
  'static',
  'assets',
  'cdn',
  'preview',
  'staging',
  'dev',
  'test',
  'demo',
  'localhost',
  'webmail',
  'smtp',
  'imap',
  'ftp',
  'ns1',
  'ns2',
  'mx',
  'manager',
  'pos',
  'edge',
  'portal',
  'root',
]);

/** A valid, non-reserved address label for a new assignment or change request. */
export function requestableSlug(value: unknown) {
  const slug = websiteSlug(value);
  if (reservedSaasNames.has(slug))
    throw new BadRequestException('This website address is reserved');
  return slug;
}

/**
 * The initial address label derived from a restaurant name.
 *
 * Whitespace is removed rather than hyphenated: "Restaurant Vankisi" becomes
 * `restaurantvankisi`. Georgian is transliterated, other letters lose their
 * accents, and anything else a hostname cannot carry is dropped.
 */
export function generatedSlug(name: string) {
  const slug =
    [...name.toLowerCase()]
      .map((c) => georgian[c] ?? c)
      .join('')
      .normalize('NFKD')
      .replace(/[^a-z0-9-]/g, '')
      .replace(/^-+|-+$/g, '')
      .slice(0, 40)
      .replace(/-+$/, '') || 'restaurant';
  try {
    return requestableSlug(slug);
  } catch {
    return `restaurant-${slug}`;
  }
}
function configuredBaseDomain() {
  const raw = process.env.SAAS_WEBSITE_BASE_DOMAIN;
  const host = normalizeHostname(raw);
  return raw && host && host === raw && host.includes('.') ? host : null;
}
export function saasBaseDomain() {
  const host = configuredBaseDomain();
  if (!host)
    throw new ServiceUnavailableException(
      'SaaS website domain is not configured',
    );
  return host;
}
export function saasHostname(slug: string) {
  return `${slug}.${saasBaseDomain()}`;
}
/**
 * Whether a hostname sits in the SaaS address namespace, which only
 * provisioning and approved hostname requests may bind.
 */
export function isSaasNamespace(hostname: string) {
  const base = configuredBaseDomain();
  return !!base && (hostname === base || hostname.endsWith(`.${base}`));
}
/**
 * Whether another Venue holds, or retains, this SaaS address.
 *
 * A name is held by its domain row (any status, including one in retention)
 * and by the Venue whose assigned identity it is, even while that Venue's
 * domain row has been released.
 */
export async function saasNameTaken(
  tx: Prisma.TransactionClient,
  slug: string,
  hostname: string,
  venueId: string,
) {
  const domain = await tx.venueDomain.findUnique({
    where: { hostname },
    select: { venueId: true },
  });
  const config = await tx.venueWebsiteConfig.findUnique({
    where: { assignedSlug: slug },
    select: { venueId: true },
  });
  return (
    (!!domain && domain.venueId !== venueId) ||
    (!!config && config.venueId !== venueId)
  );
}
/** Shared by provisioning and requests. Lock order: Venue, config, global names. */
export async function lockHostnames(tx: Prisma.TransactionClient) {
  await tx.$queryRaw`SELECT pg_advisory_xact_lock(782341902)::text`;
}
export async function assignHostname(
  tx: Prisma.TransactionClient,
  venueId: string,
  platformUserId?: string | null,
) {
  const row = await tx.venueWebsiteConfig.findUniqueOrThrow({
    where: { venueId },
  });
  if (row.assignedSlug) return row; // Restaurant display-name edits never rename identity.
  const base = saasBaseDomain();
  await lockHostnames(tx);
  const venue = await tx.venue.findUniqueOrThrow({ where: { id: venueId } });
  const stem = generatedSlug(venue.name);
  let slug = stem;
  for (
    let n = 2;
    await saasNameTaken(tx, slug, `${slug}.${base}`, venueId);
    n++
  )
    slug = `${stem}-${n}`;
  const hostname = `${slug}.${base}`;
  const existing = await tx.venueDomain.findUnique({ where: { hostname } });
  if (existing && existing.venueId !== venueId)
    throw new ConflictException('Website address is unavailable');
  if (!existing) await tx.venueDomain.create({ data: { venueId, hostname } });
  const draft = row.draft ? readWebsiteContent(row.draft) : emptyWebsiteContent;
  // After a released name is reassigned, a published site keeps one identity
  // everywhere; open editors are fenced only when the name actually changed.
  const renamed = !!row.published && draft.slug !== slug;
  const result = await tx.venueWebsiteConfig.update({
    where: { venueId },
    data: {
      assignedSlug: slug,
      draft: { ...draft, slug } as unknown as Prisma.InputJsonValue,
      ...(row.published
        ? {
            slug,
            published: {
              ...readWebsiteContent(row.published),
              slug,
            } as unknown as Prisma.InputJsonValue,
          }
        : {}),
      ...(renamed
        ? {
            revision: { increment: 1 },
            ...(row.publishedRevision === row.revision
              ? { publishedRevision: row.revision + 1 }
              : {}),
          }
        : {}),
    },
  });
  await tx.platformAuditEvent.create({
    data: {
      platformUserId,
      action: 'website.hostname_assigned',
      targetType: 'Venue',
      targetId: venueId,
      metadata: {
        hostname,
        source: platformUserId ? 'PLATFORM' : 'SYSTEM',
      },
    },
  });
  return result;
}

/**
 * Frees the SaaS identity whose domain row is being released, in the same
 * transaction, so the name becomes genuinely available to another Venue.
 *
 * A released binding leaves no reservation behind: the assigned name is
 * cleared (the published `slug` mirror is history and reserves nothing), and a
 * pending change request, whose current address no longer exists, is closed. Content and history remain;
 * regaining Website access assigns a fresh address. Custom domains are ignored.
 */
export async function releaseSaasIdentity(
  tx: Prisma.TransactionClient,
  venueId: string,
  hostname: string,
  actor: { platformUserId?: string | null; source: 'PLATFORM' | 'SYSTEM' },
) {
  const base = configuredBaseDomain();
  const config = await tx.venueWebsiteConfig.findUnique({ where: { venueId } });
  if (!base || !config?.assignedSlug) return;
  if (hostname !== `${config.assignedSlug}.${base}`) return;
  await lockHostnames(tx);
  await tx.venueWebsiteConfig.update({
    where: { venueId },
    data: { assignedSlug: null },
  });
  const closed = await tx.websiteHostnameRequest.updateMany({
    where: { venueId, status: 'PENDING' },
    data: {
      status: 'REJECTED',
      reviewedAt: new Date(),
      reason: 'Closed automatically: the website address was released',
    },
  });
  await tx.platformAuditEvent.create({
    data: {
      platformUserId: actor.platformUserId ?? null,
      action: 'website.hostname_released',
      targetType: 'Venue',
      targetId: venueId,
      metadata: {
        hostname,
        assignedSlug: config.assignedSlug,
        closedRequests: closed.count,
        source: actor.source,
      },
    },
  });
}
