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
import { lockHostnames, saasBaseDomain } from '../provisioning/hostname';
import { readWebsiteContent, websiteSlug } from './website-content';

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
  async create(venueId: string, customerAccountId: string, value: unknown) {
    const slug = websiteSlug(value);
    const hostname = `${slug}.${saasBaseDomain()}`;
    return this.db.$transaction(async (tx) => {
      await this.lock(tx, venueId);
      if (
        await tx.websiteHostnameRequest.findFirst({
          where: { venueId, status: 'PENDING' },
        })
      )
        throw new ConflictException(
          'A hostname request is already awaiting review',
        );
      await this.available(tx, hostname, slug);
      const row = await tx.websiteHostnameRequest.create({
        data: { venueId, requestedBy: customerAccountId, slug, hostname },
      });
      const event = {
        action: 'website.hostname_change_requested',
        targetType: 'Venue',
        targetId: venueId,
        metadata: { requestId: row.id, hostname, customerAccountId },
      };
      await tx.customerAuditEvent.create({
        data: { ...event, customerAccountId },
      });
      await tx.platformAuditEvent.create({ data: event });
      return row;
    });
  }
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
        let previous: string | null = null;
        if (body.status === 'APPROVED') {
          const config = await this.lock(tx, venueId);
          previous = config.assignedSlug;
          if (request.hostname !== `${request.slug}.${saasBaseDomain()}`)
            throw new ConflictException(
              'Website base domain changed; submit a new request',
            );
          await this.available(tx, request.hostname, request.slug);
          await tx.venueDomain.create({
            data: { venueId, hostname: request.hostname },
          });
          // Release only the old SaaS identity; custom domains remain untouched.
          await tx.venueDomain.deleteMany({
            where: {
              venueId,
              hostname: `${config.assignedSlug}.${saasBaseDomain()}`,
            },
          });
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
              previous,
              hostname: request.hostname,
              reason,
            },
          },
        });
        return result;
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      )
        throw new ConflictException('Website address is unavailable');
      throw error;
    }
  }
}
