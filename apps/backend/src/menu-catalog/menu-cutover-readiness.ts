import type { Prisma } from '@prisma/client';

/**
 * Read-only readiness audit for moving an ESTABLISHED POS Venue (legacy POS
 * menu authority) onto the canonical Cloud Menu (docs/CANONICAL_MENU_SYNC.md
 * §Existing POS Venues). It changes nothing: no authority, no rows, no
 * sequence. The cutover itself is a separate, explicit, audited operator step
 * that this milestone deliberately does not perform.
 *
 * Canonical identity is the POS's own stable UUID (`posMenu*Id`), so a
 * mirrored catalog can become canonical without re-keying Cloud rows,
 * website presentation or recipes — provided every node carries it.
 */
export interface MenuCutoverReport {
  venueId: string;
  authority: 'POS' | 'CLOUD';
  verdict: 'ALREADY_CANONICAL' | 'READY_FOR_REHEARSAL' | 'BLOCKED';
  blockers: string[];
  warnings: string[];
  counts: {
    categories: number;
    subcategories: number;
    items: number;
    variants: number;
    withoutPosIdentity: number;
    websitePresentations: number;
    consumptionRecipes: number;
    activeDevices: number;
  };
  primaryDeviceId: string | null;
  lastPrimarySeenAt: string | null;
}

export async function menuCutoverReadiness(
  tx: Prisma.TransactionClient,
  venueId: string,
  now: Date = new Date(),
): Promise<MenuCutoverReport> {
  const venue = await tx.venue.findUniqueOrThrow({
    where: { id: venueId },
    select: { menuAuthority: true, activeOperationalDeviceId: true },
  });
  const [
    categories,
    subcategories,
    items,
    variants,
    orphanCategories,
    orphanSubcategories,
    orphanItems,
    orphanVariants,
    websitePresentations,
    consumptionRecipes,
    devices,
  ] = await Promise.all([
    tx.menuCategory.count({ where: { venueId } }),
    tx.menuSubcategory.count({ where: { category: { venueId } } }),
    tx.menuItem.count({ where: { venueId } }),
    tx.menuItemVariant.count({ where: { menuItem: { venueId } } }),
    tx.menuCategory.count({ where: { venueId, posMenuCategoryId: null } }),
    tx.menuSubcategory.count({
      where: { category: { venueId }, posMenuSubcategoryId: null },
    }),
    tx.menuItem.count({ where: { venueId, posMenuItemId: null } }),
    tx.menuItemVariant.count({
      where: { menuItem: { venueId }, posMenuVariantId: null },
    }),
    tx.menuItemWebsitePresentation.count({ where: { venueId } }),
    tx.menuConsumptionRecipe.count({ where: { venueId } }),
    tx.device.findMany({
      where: { venueId, status: 'ACTIVE' },
      select: { id: true, lastSeenAt: true, firstSyncAt: true },
    }),
  ]);
  const withoutPosIdentity =
    orphanCategories + orphanSubcategories + orphanItems + orphanVariants;
  const primary = devices.find((d) => d.id === venue.activeOperationalDeviceId);
  const blockers: string[] = [];
  const warnings: string[] = [];
  if (venue.menuAuthority === 'POS') {
    if (!devices.length)
      blockers.push('No active POS Device holds the authoritative menu');
    if (!primary)
      blockers.push(
        'No operational primary POS: the authoritative copy is ambiguous',
      );
    else if (!primary.firstSyncAt)
      blockers.push('The primary POS has never completed a full snapshot');
    else if (
      !primary.lastSeenAt ||
      now.getTime() - primary.lastSeenAt.getTime() > 24 * 3600_000
    )
      blockers.push(
        'The primary POS was not seen in the last 24 hours; its latest menu may not be mirrored',
      );
    if (withoutPosIdentity)
      blockers.push(
        `${withoutPosIdentity} mirrored Menu node(s) have no POS identity; resync from a POS build with stable ids first`,
      );
    if (devices.length > 1)
      warnings.push(
        `${devices.length} active POS Devices: every one must adopt the same baseline, and secondary local menus are replaced only by explicit adoption`,
      );
    if (!items)
      warnings.push(
        'The mirrored catalog has no items; confirm the POS menu is really empty',
      );
  }
  return {
    venueId,
    authority: venue.menuAuthority,
    verdict:
      venue.menuAuthority === 'CLOUD'
        ? 'ALREADY_CANONICAL'
        : blockers.length
          ? 'BLOCKED'
          : 'READY_FOR_REHEARSAL',
    blockers,
    warnings,
    counts: {
      categories,
      subcategories,
      items,
      variants,
      withoutPosIdentity,
      websitePresentations,
      consumptionRecipes,
      activeDevices: devices.length,
    },
    primaryDeviceId: venue.activeOperationalDeviceId,
    lastPrimarySeenAt: primary?.lastSeenAt?.toISOString() ?? null,
  };
}
