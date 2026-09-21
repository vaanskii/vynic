import { BadRequestException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { requireText } from '../platform/platform-validation';

export const profileSelect = {
  id: true,
  name: true,
  branchName: true,
  address: true,
  phone: true,
  legalId: true,
  profileUpdatedAt: true,
} as const;
export function profileInput(body: Record<string, unknown>) {
  const result = {
    name: requireText(body.name, 'რესტორნის სახელი', { max: 100 }),
  } as Record<string, string | null> & { name: string };
  for (const [key, max] of Object.entries({
    branchName: 100,
    address: 300,
    phone: 50,
    legalId: 50,
  })) {
    const value = body[key];
    if (
      value != null &&
      (typeof value !== 'string' || value.trim().length > max)
    )
      throw new BadRequestException(`არასწორი ველი: ${key}`);
    result[key] = typeof value === 'string' ? value.trim() || null : null;
  }
  return result;
}
export async function saveProfile(
  db: PrismaService,
  venueId: string,
  body: Record<string, unknown>,
  actor: { id: string; source: string },
) {
  const input = profileInput(body);
  return db.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
    const before = await tx.venue.findUniqueOrThrow({
      where: { id: venueId },
      select: profileSelect,
    });
    const after = await tx.venue.update({
      where: { id: venueId },
      data: { ...input, profileUpdatedAt: new Date() },
      select: profileSelect,
    });
    await tx.auditEventLog.create({
      data: {
        venueId,
        action: 'VENUE_PROFILE_CHANGED',
        entityType: 'SETTINGS',
        entityId: venueId,
        userId: actor.id,
        deviceType: actor.source.toLowerCase(),
        data: {
          source: actor.source,
          before: JSON.parse(JSON.stringify(before)),
          after: JSON.parse(JSON.stringify(after)),
        },
      },
    });
    return after;
  });
}
