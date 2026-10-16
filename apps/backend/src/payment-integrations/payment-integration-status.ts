import type { Prisma } from '@prisma/client';

/** Safe metadata only; historical ciphertext is never loaded for readiness. */
export function latestBogIntegrationStatus(
  db: Pick<Prisma.TransactionClient, 'paymentIntegration'>,
  venueId: string,
) {
  return db.paymentIntegration.findFirst({
    where: { venueId, provider: 'BOG' },
    orderBy: { revision: 'desc' },
    select: { enabled: true, revision: true, createdAt: true },
  });
}
