import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';

/** Server-owned financial review, no buyer/PAN/auth/credential projection. */
export async function websitePaymentReviews(
  db: PrismaService,
  venueId: string,
  rawOffset?: string,
) {
  const offset = rawOffset === undefined ? 0 : Number(rawOffset);
  if (!Number.isSafeInteger(offset) || offset < 0 || offset > 100_000)
    throw new BadRequestException('Invalid offset');
  if (
    !(await db.venue.findUnique({
      where: { id: venueId },
      select: { id: true },
    }))
  )
    throw new NotFoundException('Venue not found');
  const where = {
    venueId,
    OR: [
      { paymentReviewReason: { not: null } },
      { paymentState: 'REVIEW' },
      { paymentState: 'UNTRACKED', paymentId: { not: null } },
    ],
  };
  const [total, rows] = await Promise.all([
    db.websiteReservation.count({ where }),
    db.websiteReservation.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      skip: offset,
      take: 25,
      select: {
        id: true,
        date: true,
        dayHolds: { take: 1, select: { serviceDate: true } },
        timeSlot: true,
        status: true,
        paymentState: true,
        paymentExpectedMinor: true,
        paymentGrossMinor: true,
        paymentRefundedMinor: true,
        paymentCurrency: true,
        paymentReviewReason: true,
        paymentId: true,
        holdState: true,
        holdExpiresAt: true,
        paymentObservations: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { paymentId: true },
        },
      },
    }),
  ]);
  return {
    total,
    offset,
    limit: 25,
    financialDecisionOwner: 'RESTAURANT_OWNER' as const,
    items: rows.map((row) => ({
      bookingId: row.id,
      date: row.dayHolds[0]?.serviceDate ?? row.date,
      timeSlot: row.timeSlot,
      bookingStatus: row.status,
      paymentState: row.paymentState,
      expectedMinor: row.paymentExpectedMinor,
      grossPaidMinor: row.paymentGrossMinor,
      refundedMinor: row.paymentRefundedMinor,
      currency: row.paymentCurrency,
      reason: row.paymentReviewReason ?? 'historical_payment_snapshot_missing',
      paymentId: row.paymentId ?? row.paymentObservations[0]?.paymentId ?? null,
      holdState: row.holdState,
      holdExpiresAt: row.holdExpiresAt,
    })),
  };
}
