import { assignHostname } from './hostname';
import { BadRequestException } from '@nestjs/common';
import { Prisma, VenueWebsiteConfig } from '@prisma/client';
import { commercialState } from '../../entitlements/commercial-state';
import { cloudMenuAdmission } from '../../platform/cloud-menu-admission';

/** Operator-selected implementation; NONE is never a provisioning choice. */
export type ProvisionedWebsiteMode = 'SAAS' | 'CUSTOM';

/**
 * What the owner is shown, derived only from server state.
 *
 * NOT_ENTITLED: the package has no WEBSITE (or access is closed).
 * SETUP_PENDING: WEBSITE is included but the operator has not provisioned it.
 */
export type WebsiteState = 'NOT_ENTITLED' | 'SETUP_PENDING' | 'SAAS' | 'CUSTOM';

export function websiteState(
  features: readonly string[],
  config: Pick<VenueWebsiteConfig, 'mode'> | null | undefined,
): WebsiteState {
  if (!features.includes('WEBSITE')) return 'NOT_ENTITLED';
  if (config?.mode === 'SAAS') return 'SAAS';
  if (config?.mode === 'CUSTOM') return 'CUSTOM';
  return 'SETUP_PENDING';
}

export function requireWebsiteMode(value: unknown): ProvisionedWebsiteMode {
  if (value === 'SAAS' || value === 'CUSTOM') return value;
  throw new BadRequestException(
    'Choose the website implementation: SAAS or CUSTOM',
  );
}

/**
 * The one operation that turns a WEBSITE commercial right into a provisioned
 * website. Every Platform assignment path (access-request approval, manual
 * Trial, manual Active, legacy status PUT) calls this after the plan is set.
 *
 * Caller owns the transaction and the Venue lock. Idempotent: re-applying the
 * same mode writes nothing. Without WEBSITE in the package it is a no-op, so a
 * POS-only plan never acquires a website row.
 *
 * `requested` is operator input only; the owner has no path to this function.
 * When omitted, an already-provisioned mode is kept; a WEBSITE package with no
 * mode yet is refused, so assignment cannot silently leave setup half done.
 */
export async function provisionWebsite(
  tx: Prisma.TransactionClient,
  venueId: string,
  requested: unknown,
  actor: { platformUserId?: string | null },
  source: string,
) {
  const { planFeatures } = await commercialState(tx, venueId);
  if (!planFeatures.includes('WEBSITE')) {
    if (requested !== undefined && requested !== null && requested !== '')
      throw new BadRequestException('This plan does not include Website');
    return null;
  }
  await tx.$queryRaw`SELECT "venueId" FROM "pos"."VenueWebsiteConfig" WHERE "venueId" = ${venueId} FOR UPDATE`;
  const before = await tx.venueWebsiteConfig.findUnique({
    where: { venueId },
  });
  const mode: ProvisionedWebsiteMode =
    requested === undefined || requested === null || requested === ''
      ? before?.mode === 'SAAS' || before?.mode === 'CUSTOM'
        ? before.mode
        : requireWebsiteMode(requested)
      : requireWebsiteMode(requested);
  // Menu authority follows the package, never the implementation: a
  // Website-only Venue needs a Cloud catalog whether SAAS or CUSTOM renders it.
  if (!planFeatures.includes('POS'))
    await admitCloudMenu(tx, venueId, actor, source);
  if (before?.mode === mode)
    return mode === 'SAAS'
      ? assignHostname(tx, venueId, actor.platformUserId)
      : before;
  const row = await tx.venueWebsiteConfig.upsert({
    where: { venueId },
    create: { venueId, mode },
    update: { mode },
  });
  await tx.platformAuditEvent.create({
    data: {
      platformUserId: actor.platformUserId ?? null,
      action: 'venue.website_mode_changed',
      targetType: 'Venue',
      targetId: venueId,
      metadata: { from: before?.mode ?? 'NONE', to: mode, source },
    },
  });
  return mode === 'SAAS'
    ? assignHostname(tx, venueId, actor.platformUserId)
    : row;
}

/**
 * A POS-less website (SAAS or CUSTOM) needs Cloud menu authoring. The
 * operator's explicit Website assignment is the admission act; the existing
 * conservative checks still decide, so any POS evidence keeps POS authority
 * and the operator sees the recorded reason. Never runs for packages that
 * include POS.
 */
async function admitCloudMenu(
  tx: Prisma.TransactionClient,
  venueId: string,
  actor: { platformUserId?: string | null },
  source: string,
) {
  const admission = await cloudMenuAdmission(tx, venueId);
  if (!admission.canEnableCloud || admission.enabled) return;
  // First admission only: an operator who later disabled Cloud editing stays.
  // New Venues start CLOUD (D030), so an earlier operator decision, not the
  // authority, marks a Venue as already admitted.
  if (
    admission.authority === 'CLOUD' &&
    (await tx.platformAuditEvent.count({
      where: {
        targetType: 'Venue',
        targetId: venueId,
        action: {
          in: ['venue.cloud_menu_enabled', 'venue.cloud_menu_disabled'],
        },
      },
    }))
  )
    return;
  await tx.venue.update({
    where: { id: venueId },
    data: { menuAuthority: 'CLOUD', cloudMenuEditingEnabled: true },
  });
  await tx.platformAuditEvent.create({
    data: {
      platformUserId: actor.platformUserId ?? null,
      action: 'venue.cloud_menu_enabled',
      targetType: 'Venue',
      targetId: venueId,
      metadata: { from: admission.authority, enabled: true, source },
    },
  });
}
