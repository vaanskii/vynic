import { BadRequestException } from '@nestjs/common';

/** Version 1 content is plain text and HTTPS references, never HTML. */
export interface WebsiteContent {
  slug: string;
  themeKey: 'classic';
  heroTitle: string;
  heroSubtitle: string;
  about: string;
  seoTitle: string;
  seoDescription: string;
  workingHours: { day: number; opens: string; closes: string }[];
  socials: { label: string; url: string }[];
  gallery: { url: string; alt: string }[];
}
export const emptyWebsiteContent: WebsiteContent = {
  slug: '',
  themeKey: 'classic',
  heroTitle: '',
  heroSubtitle: '',
  about: '',
  seoTitle: '',
  seoDescription: '',
  workingHours: [],
  socials: [],
  gallery: [],
};
function invalid(): never {
  throw new BadRequestException('Invalid website content');
}
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    Object.keys(value).some((k) => !keys.includes(k))
  )
    invalid();
  return value as Record<string, unknown>;
}
function text(value: unknown, max: number): string {
  if (
    typeof value !== 'string' ||
    value.length > max ||
    /[<>\u0000-\u0008]/.test(value)
  )
    invalid();
  return value.trim();
}
function url(value: unknown) {
  const raw = text(value, 2048);
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return invalid();
  }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password)
    invalid();
  return parsed.href;
}
function list<T>(value: unknown, max: number, parse: (v: unknown) => T): T[] {
  if (!Array.isArray(value) || value.length > max) invalid();
  return value.map(parse);
}
export function websiteContent(value: unknown): WebsiteContent {
  const input = object(value, Object.keys(emptyWebsiteContent));
  const slug = text(input.slug, 48);
  if (
    !/^[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?$/.test(slug) ||
    ['www', 'api', 'admin', 'app', 'mail', 'platform'].includes(slug)
  )
    invalid();
  if (input.themeKey !== 'classic') invalid();
  const workingHours = list(input.workingHours, 7, (v) => {
    const row = object(v, ['day', 'opens', 'closes']);
    if (
      !Number.isInteger(row.day) ||
      Number(row.day) < 1 ||
      Number(row.day) > 7
    )
      invalid();
    const opens = text(row.opens, 5),
      closes = text(row.closes, 5);
    if (
      ![opens, closes].every((t) => /^([01]\d|2[0-3]):[0-5]\d$/.test(t)) ||
      opens === closes
    )
      invalid();
    return { day: Number(row.day), opens, closes };
  });
  if (new Set(workingHours.map((v) => v.day)).size !== workingHours.length)
    invalid();
  return {
    slug,
    themeKey: 'classic',
    heroTitle: text(input.heroTitle, 160),
    heroSubtitle: text(input.heroSubtitle, 400),
    about: text(input.about, 5000),
    seoTitle: text(input.seoTitle, 160),
    seoDescription: text(input.seoDescription, 320),
    workingHours,
    socials: list(input.socials, 8, (v) => {
      const row = object(v, ['label', 'url']);
      const label = text(row.label, 40);
      if (!label) invalid();
      return { label, url: url(row.url) };
    }),
    gallery: list(input.gallery, 20, (v) => {
      const row = object(v, ['url', 'alt']);
      return { url: url(row.url), alt: text(row.alt, 200) };
    }),
  };
}
export function websiteMutation(value: unknown, save: boolean) {
  const input = object(
    value,
    save ? ['expectedRevision', 'content'] : ['expectedRevision'],
  );
  if (
    !Number.isSafeInteger(input.expectedRevision) ||
    Number(input.expectedRevision) < 0
  )
    invalid();
  return {
    expectedRevision: Number(input.expectedRevision),
    content: save ? websiteContent(input.content) : undefined,
  };
}
