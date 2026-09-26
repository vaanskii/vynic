import { ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

/** Recognizes local media even inside an absolute URL; prevents cross-Venue aliases. */
export function mediaKeys(value: unknown): Set<string> {
  const keys = new Set<string>();
  const walk = (v: unknown) => {
    if (typeof v === 'string') {
      let path: string;
      try {
        path = new URL(v, 'https://media.invalid').pathname;
      } catch {
        return;
      }
      if (path.startsWith('/media/website-logos/'))
        keys.add(path.slice('/media/website-logos/'.length));
    } else if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === 'object') Object.values(v).forEach(walk);
  };
  walk(value);
  return keys;
}

/** Existing unmanaged references may stay on their original Venue, but cannot be copied. */
export async function validateMediaReferences(
  tx: Prisma.TransactionClient,
  venueId: string,
  content: unknown,
  prior: unknown,
) {
  const keys = [...mediaKeys(content)];
  if (!keys.length) return;
  const previous = mediaKeys(prior);
  const rows = await tx.websiteMediaAsset.findMany({
    where: { storageKey: { in: keys } },
  });
  for (const key of keys) {
    const asset = rows.find((row) => row.storageKey === key);
    if (asset ? asset.venueId !== venueId : !previous.has(key))
      throw new ForbiddenException('Image does not belong to this restaurant');
  }
  await tx.websiteMediaAsset.updateMany({
    where: { venueId, storageKey: { in: keys } },
    data: { unusedSince: null },
  });
}

export async function referencedMedia(
  tx: Prisma.TransactionClient,
  venueId: string,
) {
  const [site, menu, info] = await Promise.all([
    tx.venueWebsiteConfig.findUnique({
      where: { venueId },
      select: { draft: true, published: true },
    }),
    tx.menuItemWebsitePresentation.findMany({
      where: { venueId },
      select: { imageUrl: true },
    }),
    tx.venuePublicProfile.findUnique({
      where: { venueId },
      select: { gallery: true },
    }),
  ]);
  return mediaKeys([site, menu, info]);
}
