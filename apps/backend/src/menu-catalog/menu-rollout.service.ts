import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { lockOperationalVenue } from '../edge/operational-authority';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import type { CustomerPrincipal } from '../customer/customer-auth';
import { menuCutoverReadiness } from './menu-cutover-readiness';
import {
  menuClientReport,
  menuCompatibility,
  MENU_REPORT_FRESH_MS,
} from './menu-client-policy';

async function owner(
  tx: Prisma.TransactionClient,
  actor: CustomerPrincipal,
  venueId: string,
) {
  if (
    !(await tx.venue.count({
      where: {
        id: venueId,
        organization: {
          memberships: {
            some: { customerAccountId: actor.customerAccountId, role: 'OWNER' },
          },
        },
      },
    }))
  )
    throw new NotFoundException('Restaurant not found');
}

export async function menuRolloutReadiness(
  tx: Prisma.TransactionClient,
  venueId: string,
  now = new Date(),
) {
  const baseline = await menuCutoverReadiness(tx, venueId, now);
  const devices = await tx.device.findMany({
    where: { venueId },
    orderBy: { id: 'asc' },
    select: {
      id: true,
      displayName: true,
      platform: true,
      status: true,
      lastSeenAt: true,
      menuClientReport: true,
      menuClientObservedAt: true,
      lastLegacyMenuSyncAt: true,
    },
  });
  const fleet = devices.map((d) => {
    const report = menuClientReport(d.menuClientReport);
    const fresh =
      d.menuClientObservedAt !== null &&
      now.getTime() - d.menuClientObservedAt.getTime() >= 0 &&
      now.getTime() - d.menuClientObservedAt.getTime() <= MENU_REPORT_FRESH_MS;
    return {
      ...d,
      appVersion: report?.appVersion ?? null,
      buildNumber: report?.buildNumber ?? null,
      capabilities: report?.capabilities ?? [],
      fresh,
      compatibility: menuCompatibility('CLOUD', d.platform, report),
      isOperationalPrimary: d.id === baseline.primaryDeviceId,
    };
  });
  const blockers = [...baseline.blockers];
  if (baseline.authority === 'POS') {
    for (const d of fleet.filter((d) => d.status === 'ACTIVE')) {
      if (!d.fresh) blockers.push(`DEVICE_REPORT_STALE_OR_UNKNOWN:${d.id}`);
      if (d.compatibility.result !== 'SUPPORTED')
        blockers.push(`DEVICE_${d.compatibility.result}:${d.id}`);
    }
    const primary = fleet.find(
      (d) => d.isOperationalPrimary && d.status === 'ACTIVE',
    );
    if (
      !primary?.lastLegacyMenuSyncAt ||
      now.getTime() - primary.lastLegacyMenuSyncAt.getTime() >
        MENU_REPORT_FRESH_MS
    )
      blockers.push('FINAL_LEGACY_MENU_SYNC_REQUIRED');
  }
  // Legacy snapshots do not advance canonical sequence. Include row evidence
  // so a snapshot racing an operator's preview invalidates its readiness token.
  const catalog = await Promise.all([
    tx.menuCategory.findMany({ where: { venueId }, orderBy: { id: 'asc' } }),
    tx.menuSubcategory.findMany({
      where: { category: { venueId } },
      orderBy: { id: 'asc' },
    }),
    tx.menuItem.findMany({ where: { venueId }, orderBy: { id: 'asc' } }),
    tx.menuItemVariant.findMany({
      where: { menuItem: { venueId } },
      orderBy: { id: 'asc' },
    }),
  ]);
  if (baseline.authority === 'POS') {
    const identities = [
      ...catalog[0].map((n) => n.posMenuCategoryId),
      ...catalog[1].map((n) => n.posMenuSubcategoryId),
      ...catalog[2].map((n) => n.posMenuItemId),
      ...catalog[3].map((n) => n.posMenuVariantId),
    ];
    const uuid =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (identities.some((id) => id !== null && !uuid.test(id)))
      blockers.push(
        'MENU_IDENTITY_INVALID: reconcile stable UUIDs before cutover',
      );
    const retained = identities.filter((id): id is string => id !== null);
    if (new Set(retained).size !== retained.length)
      blockers.push(
        'MENU_IDENTITY_COLLISION: reconcile shared node identities before cutover',
      );
  }
  const token = createHash('sha256')
    .update(JSON.stringify({ baseline, fleet, catalog, blockers }))
    .digest('hex');
  return {
    ...baseline,
    verdict:
      baseline.authority === 'CLOUD'
        ? 'ALREADY_CANONICAL'
        : blockers.length
          ? 'BLOCKED'
          : 'READY_FOR_CUTOVER',
    blockers,
    fleet,
    readinessToken: token,
    readinessExpiresAfterSeconds: MENU_REPORT_FRESH_MS / 1000,
    operatorRequirements: [
      'ALL_POS_ONLINE',
      'FINAL_LEGACY_SYNC_CONFIRMED',
      'NO_PENDING_LOCAL_MENU_EDITS',
      'EXPLICIT_CLOUD_ADOPTION_ON_EACH_POS',
    ],
  };
}

@Injectable()
export class MenuRolloutService {
  constructor(private readonly db: PrismaService) {}
  async readiness(actor: CustomerPrincipal, venueId: string) {
    return this.db.$transaction(async (tx) => {
      await owner(tx, actor, venueId);
      await lockOperationalVenue(tx, venueId);
      return menuRolloutReadiness(tx, venueId);
    });
  }
  async cutover(actor: CustomerPrincipal, venueId: string, raw: unknown) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw))
      throw new BadRequestException('Readiness confirmation required');
    const body = raw as Record<string, unknown>;
    if (
      body.allPosOnline !== true ||
      body.finalLegacySyncConfirmed !== true ||
      body.noPendingLocalMenuEdits !== true ||
      typeof body.reason !== 'string' ||
      !body.reason.trim() ||
      body.reason.length > 500
    )
      throw new BadRequestException(
        'Confirm all POS online, final legacy sync and reconciled local edits with a reason',
      );
    const reason = body.reason.trim();
    return this.db.$transaction(
      async (tx) => {
        await owner(tx, actor, venueId);
        await lockOperationalVenue(tx, venueId);
        await requireCommercialFeature(tx, venueId, 'POS');
        const report = await menuRolloutReadiness(tx, venueId);
        if (report.authority !== 'POS')
          throw new ConflictException({
            code: 'ALREADY_CANONICAL',
            message: 'Venue already uses canonical Menu',
          });
        if (report.blockers.length)
          throw new ConflictException({
            code: 'MENU_CUTOVER_BLOCKED',
            blockers: report.blockers,
          });
        if (body.readinessToken !== report.readinessToken)
          throw new ConflictException({
            code: 'MENU_READINESS_CHANGED',
            message: 'Refresh fleet readiness before cutover',
          });
        const cutover = {
          version: 1,
          from: 'POS',
          to: 'CLOUD',
          at: new Date().toISOString(),
          customerAccountId: actor.customerAccountId,
          reason,
          readinessToken: report.readinessToken,
          deviceIds: report.fleet
            .filter((d) => d.status === 'ACTIVE')
            .map((d) => d.id),
          operatorConfirmations: {
            allPosOnline: true,
            finalLegacySyncConfirmed: true,
            noPendingLocalMenuEdits: true,
          },
        };
        await tx.venue.update({
          where: { id: venueId },
          data: { menuAuthority: 'CLOUD', menuCutover: cutover },
        });
        await tx.customerAuditEvent.create({
          data: {
            customerAccountId: actor.customerAccountId,
            action: 'venue.menu_cutover',
            targetType: 'Venue',
            targetId: venueId,
            metadata: cutover,
          },
        });
        return { authority: 'CLOUD', cutover, adoptionRequired: true };
      },
      { timeout: 30000 },
    );
  }
  async rollback(actor: CustomerPrincipal, venueId: string) {
    await this.readiness(actor, venueId);
    throw new ConflictException({
      code: 'MENU_ROLLBACK_UNSUPPORTED',
      message:
        'Abort before cutover; after CLOUD activation update clients. Independent Menu histories cannot be merged by rollback.',
    });
  }
}
