import { Prisma } from '@prisma/client';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import type { TenantContext } from '../tenancy/tenant-context';
import { settingIdentity } from '../tenancy/tenant-identity';
import { day } from './finance-rules';
export type Actor = Pick<
  ManagerAuthContext,
  'venueId' | 'organizationId' | 'staffId' | 'username'
>;
export type Tx = Prisma.TransactionClient;
export async function financeDates(
  tx: Tx,
  tenant: TenantContext,
  now = new Date(),
) {
  const venue = await tx.venue.findUniqueOrThrow({
    where: { id: tenant.venueId },
    select: { timezone: true },
  });
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: venue.timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  const setting = await tx.setting.findUnique({
    where: settingIdentity(tenant, 'currentBusinessDate'),
  });
  return {
    today,
    businessDate: day(setting?.value || today),
    periodMonth: today.slice(0, 7),
  };
}
export function audit(
  tx: Tx,
  actor: Actor,
  action: string,
  entityType: string,
  entityId: string,
  data: Prisma.InputJsonObject,
) {
  return tx.auditEventLog.create({
    data: {
      venueId: actor.venueId,
      action,
      entityType,
      entityId,
      userId: actor.staffId,
      deviceType: 'manager',
      data: {
        ...data,
        actorId: actor.staffId,
        actorName: actor.username,
        source: 'MANAGER',
      },
    },
  });
}
export const actorData = (actor: Actor) => ({
  venueId: actor.venueId,
  actorId: actor.staffId,
  actorName: actor.username,
});
