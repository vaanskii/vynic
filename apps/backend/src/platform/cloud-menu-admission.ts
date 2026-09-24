import type { Prisma } from '@prisma/client';

/** Conservative first-use admission, not a migration of an established POS. */
export async function cloudMenuAdmission(tx: Prisma.TransactionClient, venueId: string) {
  const venue = await tx.venue.findUniqueOrThrow({ where: { id: venueId }, include: { websiteConfig: { select: { mode: true } } } });
  if (venue.menuAuthority === 'CLOUD') return { authority: venue.menuAuthority, canEnableCloud: true, enabled: venue.cloudMenuEditingEnabled, reason: null };
  const checks: Array<[string, Promise<number>]> = [
    ['POS devices', tx.device.count({ where: { venueId } })],
    ['POS enrollment records', tx.deviceEnrollment.count({ where: { venueId } })],
    ['menu categories', tx.menuCategory.count({ where: { venueId } })],
    ['menu items', tx.menuItem.count({ where: { venueId } })],
    ['tables', tx.table.count({ where: { venueId } })],
    ['orders', tx.order.count({ where: { venueId } })],
    ['sales', tx.cloudSale.count({ where: { venueId } })],
    ['POS reservations', tx.posReservation.count({ where: { venueId } })],
    ['order audit history', tx.auditReport.count({ where: { venueId } })],
    ['daily snapshots', tx.dailySnapshot.count({ where: { venueId } })],
    ['POS settings', tx.setting.count({ where: { venueId } })],
    ['expenses', tx.expense.count({ where: { venueId } })],
    ['operational drafts', tx.quickOrderDraft.count({ where: { venueId } })],
    ['Edge installations', tx.edgeFoundationInstallation.count({ where: { venueId } })],
  ];
  const counts = await Promise.all(checks.map(([, count]) => count));
  const existing = checks.filter((_, i) => counts[i] > 0).map(([label]) => label);
  const reason = venue.websiteConfig?.mode === 'CUSTOM' ? 'Custom websites keep their existing menu management.'
    : venue.activeOperationalDeviceId ? 'A primary POS is already assigned.'
    : existing.length ? `Cloud menu setup is blocked by existing ${existing.join(', ')}.` : null;
  return { authority: venue.menuAuthority, canEnableCloud: !reason, enabled: false, reason };
}
