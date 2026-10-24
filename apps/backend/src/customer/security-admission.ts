import { HttpException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma.service';

export const secretHash = (value: string) =>
  createHash('sha256').update(value).digest('hex');

export async function admit(
  db: PrismaService,
  namespace: string,
  identity: string,
  limit: number,
  duration: number,
) {
  const key = namespace + ':' + secretHash(identity);
  const window = BigInt(Math.floor(Date.now() / duration));
  const rows = await db.$queryRaw<Array<{ count: number }>>`
    INSERT INTO "pos"."SecurityAdmission" ("key", "window", "count", "updatedAt")
    VALUES (${key}, ${window}, 1, NOW())
    ON CONFLICT ("key") DO UPDATE SET
      "count" = CASE WHEN "SecurityAdmission"."window" = EXCLUDED."window" THEN "SecurityAdmission"."count" + 1 ELSE 1 END,
      "window" = EXCLUDED."window", "updatedAt" = NOW()
    WHERE "SecurityAdmission"."window" <> EXCLUDED."window" OR "SecurityAdmission"."count" < ${limit}
    RETURNING "count"`;
  if (!rows.length)
    throw new HttpException('Too many attempts. Try again later.', 429);
  // Retain no raw email/IP, and bound old anonymous identities after admission.
  await db.securityAdmission.deleteMany({
    where: { updatedAt: { lt: new Date(Date.now() - 7 * 86400000) } },
  });
}
