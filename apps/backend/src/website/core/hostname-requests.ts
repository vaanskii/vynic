import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { requireCommercialFeature } from '../../entitlements/commercial-state';
import { requireText } from '../../platform/platform-validation';
import {
  lockHostnames,
  requestableSlug,
  saasHostname,
} from '../provisioning/hostname';
import { readWebsiteContent } from './website-content';

/** What an owner sees of a request: never the reviewing operator's identity. */
const customerFields = {
  id: true,
  hostname: true,
  currentHostname: true,
  status: true,
  createdAt: true,
  reviewedAt: true,
  reason: true,
} as const;

@Injectable()
export class HostnameRequestsService {
  constructor(private readonly db: PrismaService) {}
  list(venueId: string) {
    return this.db.websiteHostnameRequest.findMany({
      where: { venueId },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
  }
  listForCustomer(venueId: string) {
    return this.db.websiteHostnameRequest.findMany({
      where: { venueId },
      orderBy: { createdAt: 'desc' },
      take: 20,
      select: customerFields,
    });
  }
  private async lock(tx: Prisma.TransactionClient, venueId: string) {
    await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
    await requireCommercialFeature(tx, venueId, 'WEBSITE');
    const sub = await tx.venueSubscription.findUnique({ where: { venueId } });
    if (sub?.status !== 'ACTIVE')
      throw new ForbiddenException('An ACTIVE paid Website plan is required');
    await tx.$queryRaw`SELECT "venueId" FROM "pos"."VenueWebsiteConfig" WHERE "venueId"=${venueId} FOR UPDATE`;
    const row = await tx.venueWebsiteConfig.findUnique({ where: { venueId } });
    if (row?.mode !== 'SAAS' || !row.assignedSlug)
      throw new ForbiddenException('An assigned SaaS website is required');
    await lockHostnames(tx);
    return row;
  }
  private async available(
    tx: Prisma.TransactionClient,
    hostname: string,
    slug: string,
  ) {
    if (
      (await tx.venueDomain.findUnique({ where: { hostname } })) ||
      (await tx.venueWebsiteConfig.findUnique({
        where: { assignedSlug: slug },
      }))
    )
      throw new ConflictException('Website address is unavailable');
  }
  /**
   * Records a paid owner's wish for another address. Nothing is bound here:
   * the availability check is advisory and is repeated at approval.
   */
  async create(venueId: string, customerAccountId: string, value: unknown) {
    const slug = requestableSlug(value);
    const hostname = saasHostname(slug);
    try {
      return await this.db.$transaction(async (tx) => {
        const config = await this.lock(tx, venueId);
        if (
          await tx.websiteHostnameRequest.findFirst({
            where: { venueId, status: 'PENDING' },
          })
        )
          throw new ConflictException(
            'A hostname request is already awaiting review',
          );
        if (slug === config.assignedSlug)
          throw new ConflictException('This is already your website address');
        await this.available(tx, hostname, slug);
        const currentHostname = saasHostname(config.assignedSlug!);
        const row = await tx.websiteHostnameRequest.create({
          data: {
            venueId,
            requestedBy: customerAccountId,
            slug,
            hostname,
            currentHostname,
          },
          select: customerFields,
        });
        const event = {
          action: 'website.hostname_change_requested',
          targetType: 'Venue',
          targetId: venueId,
          metadata: {
            requestId: row.id,
            currentHostname,
            hostname,
            customerAccountId,
          },
        };
        await tx.customerAuditEvent.create({
          data: { ...event, customerAccountId },
        });
        await tx.platformAuditEvent.create({ data: event });
        return row;
      });
    } catch (error) {
      throw unavailableOnConflict(
        error,
        'A hostname request is already awaiting review',
      );
    }
  }
  /**
   * Operator decision. Approval re-validates the name and re-checks, under the
   * Venue, configuration and global name locks, that nobody claimed it since
   * the owner asked; only then does the one SaaS binding move. The old SaaS
   * hostname is removed in the same transaction (no alias or redirect), while
   * custom domains are never touched.
   */
  async review(
    venueId: string,
    id: string,
    platformUserId: string,
    body: Record<string, unknown>,
  ) {
    if (!['APPROVED', 'REJECTED'].includes(String(body.status)))
      throw new BadRequestException('Approve or reject the request');
    const reason = requireText(body.reason, 'Review reason', { max: 1000 });
    try {
      return await this.db.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
        const request = await tx.websiteHostnameRequest.findFirst({
          where: { id, venueId },
        });
        if (!request) throw new NotFoundException('Request not found');
        if (request.status !== 'PENDING')
          throw new ConflictException('Request was already reviewed');
        const current = await tx.venueWebsiteConfig.findUnique({
          where: { venueId },
          select: { assignedSlug: true },
        });
        let previousHostname = current?.assignedSlug
          ? saasHostname(current.assignedSlug)
          : null;
        if (body.status === 'APPROVED') {
          const config = await this.lock(tx, venueId);
          previousHostname = saasHostname(config.assignedSlug!);
          if (request.hostname !== saasHostname(requestableSlug(request.slug)))
            throw new ConflictException(
              'Website base domain changed; submit a new request',
            );
          await this.available(tx, request.hostname, request.slug);
          const old = await tx.venueDomain.findUnique({
            where: { hostname: previousHostname },
          });
          if (old && old.venueId !== venueId)
            throw new ConflictException(
              'Current address is not owned by this venue',
            );
          // The new binding inherits an operator-set status (e.g. DISABLED).
          await tx.venueDomain.create({
            data: {
              venueId,
              hostname: request.hostname,
              status: old?.status ?? 'ACTIVE',
            },
          });
          // Release only the old SaaS identity; custom domains remain untouched.
          if (old) await tx.venueDomain.delete({ where: { id: old.id } });
          await tx.venueWebsiteConfig.update({
            where: { venueId },
            data: {
              assignedSlug: request.slug,
              ...(config.published ? { slug: request.slug } : {}),
              draft: {
                ...readWebsiteContent(config.draft),
                slug: request.slug,
              } as unknown as Prisma.InputJsonValue,
              ...(config.published
                ? {
                    published: {
                      ...readWebsiteContent(config.published),
                      slug: request.slug,
                    } as unknown as Prisma.InputJsonValue,
                  }
                : {}),
              revision: { increment: 1 },
              ...(config.publishedRevision === config.revision
                ? { publishedRevision: config.revision + 1 }
                : {}),
            },
          });
        }
        const result = await tx.websiteHostnameRequest.update({
          where: { id },
          data: {
            status: String(body.status),
            reviewedBy: platformUserId,
            reviewedAt: new Date(),
            reason,
          },
        });
        await tx.platformAuditEvent.create({
          data: {
            platformUserId,
            action:
              body.status === 'APPROVED'
                ? 'website.hostname_change_approved'
                : 'website.hostname_change_rejected',
            targetType: 'Venue',
            targetId: venueId,
            metadata: {
              requestId: id,
              requestedBy: request.requestedBy,
              previousHostname,
              hostname: request.hostname,
              activeHostname:
                body.status === 'APPROVED'
                  ? request.hostname
                  : previousHostname,
              reason,
            },
          },
        });
        return result;
      });
    } catch (error) {
      throw unavailableOnConflict(error, 'Website address is unavailable');
    }
  }
}

/** A unique-index race surfaces as the same 409 the explicit checks give. */
function unavailableOnConflict(error: unknown, message: string) {
  return error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === 'P2002'
    ? new ConflictException(message)
    : error;
}
