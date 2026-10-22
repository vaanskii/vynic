import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Prisma, WebsiteCapabilityKey } from '@prisma/client';
import { requireCommercialFeature } from '../../entitlements/commercial-state';
import { PrismaService } from '../../prisma.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import type { CapabilityState } from '../tenancy/website-capabilities';
import {
  WebsitePublicInfo,
  emptyPublicInfo,
  websiteContactEmail,
  websiteGallery,
  websiteMapUrl,
  websiteSocials,
  websiteWorkingHours,
} from './website-content';
import { validateMediaReferences } from './website-media';

type Field = keyof WebsitePublicInfo;

const parsers: Record<Field, (value: unknown) => unknown> = {
  workingHours: websiteWorkingHours,
  contactEmail: websiteContactEmail,
  mapUrl: websiteMapUrl,
  socials: websiteSocials,
  gallery: websiteGallery,
};

/** Fields that belong to a switchable capability; the rest are profile data. */
const fieldCapability: Partial<Record<Field, WebsiteCapabilityKey>> = {
  workingHours: 'HOURS',
  gallery: 'GALLERY',
};

type Row = {
  workingHours: Prisma.JsonValue;
  contactEmail: string | null;
  mapUrl: string | null;
  socials: Prisma.JsonValue;
  gallery: Prisma.JsonValue;
  revision: number;
};

/**
 * Stored rows were validated on write; reading them back through the same
 * parsers keeps a hand-edited or legacy value from reaching a frontend.
 */
function toInfo(row: Row | null): WebsitePublicInfo & { revision: number } {
  if (!row) return { ...emptyPublicInfo, revision: 0 };
  return {
    workingHours: websiteWorkingHours(row.workingHours),
    contactEmail: websiteContactEmail(row.contactEmail ?? ''),
    mapUrl: websiteMapUrl(row.mapUrl ?? ''),
    socials: websiteSocials(row.socials),
    gallery: websiteGallery(row.gallery),
    revision: row.revision,
  };
}

/**
 * The Venue's public information: opening hours, contact, socials and gallery.
 *
 * Restaurant data, not page content. SAAS and CUSTOM websites read the same
 * rows, owners edit them live (no draft/publish) from either kind of
 * Dashboard, and hours/gallery follow their shared capability.
 */
@Injectable()
export class VenuePublicProfileService {
  constructor(
    private readonly db: PrismaService,
    private readonly capabilities: WebsiteCapabilitiesService,
  ) {}

  async read(venueId: string) {
    return toInfo(
      await this.db.venuePublicProfile.findUnique({ where: { venueId } }),
    );
  }

  /**
   * What a public website shows. A capability that is not available (not in
   * the package, or switched off) contributes nothing, in either mode.
   */
  async publicInfo(
    venueId: string,
    states?: CapabilityState[],
  ): Promise<WebsitePublicInfo> {
    const [info, current] = await Promise.all([
      this.read(venueId),
      states ?? this.capabilities.states(venueId),
    ]);
    const available = (key: WebsiteCapabilityKey) =>
      current.some((s) => s.key === key && s.available);
    return {
      contactEmail: info.contactEmail,
      mapUrl: info.mapUrl,
      socials: info.socials,
      workingHours: available('HOURS') ? info.workingHours : [],
      gallery: available('GALLERY') ? info.gallery : [],
    };
  }

  /**
   * Owner edit of any subset of the fields, fenced by `expectedRevision`.
   * Changing hours or gallery needs that capability available; unchanged
   * fields are not re-checked, so a switched-off capability does not block
   * saving the others.
   */
  async save(venueId: string, body: unknown, customerAccountId: string) {
    if (!body || typeof body !== 'object' || Array.isArray(body))
      throw new BadRequestException('Invalid public information');
    const input = body as Record<string, unknown>;
    const fields = Object.keys(input).filter((k) => k !== 'expectedRevision');
    if (fields.some((k) => !(k in parsers)))
      throw new BadRequestException('Invalid public information');
    if (
      !Number.isSafeInteger(input.expectedRevision) ||
      Number(input.expectedRevision) < 0
    )
      throw new BadRequestException('Invalid public information');
    const next: Partial<WebsitePublicInfo> = {};
    for (const field of fields as Field[])
      Object.assign(next, { [field]: parsers[field](input[field]) });

    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      await requireCommercialFeature(tx, venueId, 'WEBSITE');
      await tx.$executeRaw`INSERT INTO "pos"."VenuePublicProfile" ("venueId", "updatedAt") VALUES (${venueId}, CURRENT_TIMESTAMP) ON CONFLICT DO NOTHING`;
      const before = toInfo(
        await tx.venuePublicProfile.findUniqueOrThrow({ where: { venueId } }),
      );
      if (before.revision !== input.expectedRevision)
        throw new ConflictException(
          'Restaurant information changed. Reload before saving.',
        );
      const changed = (Object.keys(next) as Field[]).filter(
        (field) =>
          JSON.stringify(next[field]) !== JSON.stringify(before[field]),
      );
      if (!changed.length) return;
      const states = await this.capabilities.states(venueId);
      for (const field of changed) {
        const key = fieldCapability[field];
        const state = key && states.find((s) => s.key === key);
        if (state && !state.available)
          throw new ForbiddenException(
            `${state.label} is not available for this website`,
          );
      }
      if (changed.includes('gallery'))
        await validateMediaReferences(
          tx,
          venueId,
          next.gallery,
          before.gallery,
        );
      const data: Prisma.VenuePublicProfileUpdateInput = {
        revision: before.revision + 1,
      };
      for (const field of changed) {
        const value = next[field];
        if (field === 'contactEmail' || field === 'mapUrl')
          data[field] = (value as string) || null;
        else data[field] = value as Prisma.InputJsonValue;
      }
      await tx.venuePublicProfile.update({ where: { venueId }, data });
      await tx.customerAuditEvent.create({
        data: {
          customerAccountId,
          action: 'website.public_info_saved',
          targetType: 'VenuePublicProfile',
          targetId: venueId,
          metadata: { revision: before.revision + 1, fields: changed },
        },
      });
    });
    return this.read(venueId);
  }
}
