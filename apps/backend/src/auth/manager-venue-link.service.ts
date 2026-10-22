import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import * as argon2 from 'argon2';
import { randomInt } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { lockOperationalVenue } from '../edge/operational-authority';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { requireUuid } from '../platform/platform-validation';

const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const unavailable = () =>
  new UnauthorizedException('Manager linking code unavailable');
const fields = {
  id: true,
  venueId: true,
  codeSelector: true,
  expiresAt: true,
  consumedAt: true,
  cancelledAt: true,
  createdAt: true,
} as const;

/** Venue selection only. Staff authentication and unique-PIN checks stay in AuthService. */
@Injectable()
export class ManagerVenueLinkService {
  constructor(private readonly db: PrismaService) {}

  private async issuer(tx: Prisma.TransactionClient, id: string) {
    const allowed = await tx.$queryRaw<{ id: string }[]>`
      SELECT id FROM pos."PlatformUser" WHERE id=${id}
      AND status='ACTIVE' AND role='SUPER_ADMIN' FOR SHARE`;
    if (!allowed.length)
      throw new ForbiddenException('Platform Admin required');
  }
  private async ready(tx: Prisma.TransactionClient, venueId: string) {
    const venue = await lockOperationalVenue(tx, venueId);
    if (venue.status !== 'ACTIVE')
      throw new ForbiddenException('Restaurant unavailable');
    await requireCommercialFeature(tx, venueId, 'MANAGER_APP');
    if (
      !(await tx.staff.count({
        where: { venueId, isActive: true, role: { in: ['MANAGER', 'ADMIN'] } },
      }))
    )
      throw new ConflictException(
        'Complete initial Manager registration on the Primary POS first',
      );
    return venue;
  }
  private audit(
    tx: Prisma.TransactionClient,
    issuerId: string,
    venueId: string,
    action: string,
    linkId: string,
  ) {
    return tx.platformAuditEvent.create({
      data: {
        platformUserId: issuerId,
        action,
        targetType: 'Venue',
        targetId: venueId,
        metadata: { linkId },
      },
    });
  }
  async list(venueId: string) {
    const rows = await this.db.managerVenueLink.findMany({
      where: { venueId },
      select: fields,
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    const now = new Date();
    return rows.map((row) => ({
      ...row,
      status: row.cancelledAt
        ? 'CANCELLED'
        : row.consumedAt
          ? 'LINKED'
          : row.expiresAt <= now
            ? 'EXPIRED'
            : 'PENDING',
    }));
  }
  async issue(actor: PlatformPrincipal, venueId: string) {
    if (actor.role !== 'SUPER_ADMIN')
      throw new ForbiddenException('Platform Admin required');
    for (let attempt = 0; attempt < 5; attempt++) {
      const raw = Array.from(
        { length: 20 },
        () => alphabet[randomInt(alphabet.length)],
      ).join('');
      const codeHash = await argon2.hash(raw.slice(8), {
        type: argon2.argon2id,
      });
      try {
        const row = await this.db.$transaction(async (tx) => {
          await this.ready(tx, venueId);
          await this.issuer(tx, actor.platformUserId);
          const now = new Date();
          await tx.managerVenueLink.updateMany({
            where: { venueId, consumedAt: null, cancelledAt: null },
            data: { cancelledAt: now },
          });
          const link = await tx.managerVenueLink.create({
            data: {
              venueId,
              codeSelector: raw.slice(0, 8),
              codeHash,
              issuedByPlatformUserId: actor.platformUserId,
              expiresAt: new Date(now.getTime() + 30 * 60_000),
            },
            select: fields,
          });
          await this.audit(
            tx,
            actor.platformUserId,
            venueId,
            'manager.link_issued',
            link.id,
          );
          return link;
        });
        return { ...row, code: raw.match(/.{4}/g)!.join('-') };
      } catch (error) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === 'P2002'
        )
          continue;
        throw error;
      }
    }
    throw new ConflictException(
      'Could not allocate Manager linking code; try again',
    );
  }
  async cancel(actor: PlatformPrincipal, venueId: string, id: string) {
    if (actor.role !== 'SUPER_ADMIN')
      throw new ForbiddenException('Platform Admin required');
    return this.db.$transaction(async (tx) => {
      await lockOperationalVenue(tx, venueId);
      await this.issuer(tx, actor.platformUserId);
      const row = await tx.managerVenueLink.findFirst({
        where: { id, venueId },
      });
      if (!row) throw new NotFoundException('Manager linking code not found');
      if (row.consumedAt)
        throw new ConflictException(
          'Already linked; this code does not revoke existing Staff sessions',
        );
      if (!row.cancelledAt) {
        await tx.managerVenueLink.update({
          where: { id },
          data: { cancelledAt: new Date() },
        });
        await this.audit(
          tx,
          actor.platformUserId,
          venueId,
          'manager.link_cancelled',
          id,
        );
      }
      return { cancelled: true };
    });
  }
  async redeem(body: Record<string, unknown>) {
    if (!body || typeof body !== 'object' || Array.isArray(body))
      throw new BadRequestException('Link details required');
    const installationId = requireUuid(body.installationId, 'installationId');
    const raw =
      typeof body.code === 'string'
        ? body.code
            .toUpperCase()
            .replace(/[\s-]/g, '')
            .replace(/[IL]/g, '1')
            .replace(/O/g, '0')
        : '';
    if (raw.length !== 20 || [...raw].some((c) => !alphabet.includes(c)))
      throw unavailable();
    const found = await this.db.managerVenueLink.findUnique({
      where: { codeSelector: raw.slice(0, 8) },
      select: { venueId: true },
    });
    if (!found) throw unavailable();
    const result = await this.db.$transaction(async (tx) => {
      // Same order as issuance/cancellation: Venue, then link. One installation wins.
      await lockOperationalVenue(tx, found.venueId);
      const row = await tx.managerVenueLink.findUniqueOrThrow({
        where: { codeSelector: raw.slice(0, 8) },
      });
      if (
        row.cancelledAt ||
        row.expiresAt <= new Date() ||
        row.attemptCount >= 5
      )
        return null;
      if (!(await argon2.verify(row.codeHash, raw.slice(8)))) {
        await tx.managerVenueLink.update({
          where: { id: row.id },
          data: { attemptCount: { increment: 1 } },
        });
        return null; // Commit the durable failure count before returning 401.
      }
      if (row.consumedAt && row.consumedInstallationId !== installationId)
        return null;
      const venue = await this.ready(tx, row.venueId);
      await this.issuer(tx, row.issuedByPlatformUserId);
      if (!row.consumedAt) {
        await tx.managerVenueLink.update({
          where: { id: row.id },
          data: {
            consumedAt: new Date(),
            consumedInstallationId: installationId,
          },
        });
        await this.audit(
          tx,
          row.issuedByPlatformUserId,
          row.venueId,
          'manager.link_consumed',
          row.id,
        );
      }
      return {
        id: venue.id,
        code: venue.loginCode,
        name: venue.name,
        branchName: venue.branchName,
        address: venue.address,
      };
    });
    if (!result) throw unavailable();
    return result;
  }
}
