import { ConflictException, ServiceUnavailableException } from '@nestjs/common';
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
    return websiteSlug(slug);
  } catch {
    return `restaurant-${slug}`;
  }
}
export function saasBaseDomain() {
  const raw = process.env.SAAS_WEBSITE_BASE_DOMAIN;
  const host = normalizeHostname(raw);
  if (!raw || !host || host !== raw || !host.includes('.'))
    throw new ServiceUnavailableException(
      'SaaS website domain is not configured',
    );
  return host;
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
  for (let n = 2; ; n++) {
    const hostname = `${slug}.${base}`;
    const domain = await tx.venueDomain.findUnique({ where: { hostname } });
    const config = await tx.venueWebsiteConfig.findUnique({
      where: { assignedSlug: slug },
    });
    if (!config && (!domain || domain.venueId === venueId)) break;
    slug = `${stem}-${n}`;
  }
  const hostname = `${slug}.${base}`;
  const existing = await tx.venueDomain.findUnique({ where: { hostname } });
  if (existing && existing.venueId !== venueId)
    throw new ConflictException('Website address is unavailable');
  if (!existing) await tx.venueDomain.create({ data: { venueId, hostname } });
  const draft = row.draft ? readWebsiteContent(row.draft) : emptyWebsiteContent;
  const result = await tx.venueWebsiteConfig.update({
    where: { venueId },
    data: {
      assignedSlug: slug,
      draft: { ...draft, slug } as unknown as Prisma.InputJsonValue,
    },
  });
  await tx.platformAuditEvent.create({
    data: {
      platformUserId,
      action: 'website.hostname_assigned',
      targetType: 'Venue',
      targetId: venueId,
      metadata: { hostname },
    },
  });
  return result;
}
