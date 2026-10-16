import { canEncodeTableCode, encodeTableCode } from './reservation-table-codes';
import { createHash } from 'node:crypto';
import { BadRequestException } from '@nestjs/common';
import { Prisma, type WebsiteReservationStatus } from '@prisma/client';
import {
  bogPaymentFacts,
  providerDate,
  type WebsitePaymentEvidence,
} from '../payment/bog-payment-facts';

export async function expireWebsiteHolds(
  tx: Prisma.TransactionClient,
  venueId: string,
  now: Date,
) {
  const expired = await tx.websiteReservation.findMany({
    where: { venueId, holdState: 'HELD', holdExpiresAt: { lte: now } },
    select: { id: true },
  });
  const ids = expired.map((row) => row.id);
  if (ids.length) {
    await tx.websiteReservationDayHold.updateMany({
      where: { venueId, reservationId: { in: ids }, status: 'HELD' },
      data: { status: 'RELEASED' },
    });
    await tx.websiteReservation.updateMany({
      where: { id: { in: ids }, venueId, holdState: 'HELD' },
      data: {
        status: 'FAILED',
        holdState: 'EXPIRED',
        paymentReviewReason: 'expired_awaiting_receipt',
        nextPaymentCheckAt: now,
      },
    });
  }
}

/** Caller holds Venue -> booking locks; no provider/LAN call in this transaction. */
export async function applyWebsitePaymentObservation(
  tx: Prisma.TransactionClient,
  booking: Prisma.WebsiteReservationGetPayload<{
    include: { tables: { include: { table: true } } };
  }>,
  paymentId: string,
  evidence: WebsitePaymentEvidence,
) {
  const facts = bogPaymentFacts(evidence.receipt);
  const signed = evidence.signedCallback
    ? bogPaymentFacts(evidence.signedCallback.receipt)
    : null;
  const sentAt = providerDate(evidence.signedCallback?.sentAt);
  const safeFacts = {
    receipt: facts,
    ...(signed ? { signedReceipt: signed, sentAt } : {}),
  };
  const fingerprint = createHash('sha256')
    .update(
      JSON.stringify({
        source: evidence.source,
        signed: evidence.signedCallback?.fingerprint ?? null,
        facts: safeFacts,
      }),
    )
    .digest('hex');
  if (
    (facts.orderId && facts.orderId !== paymentId) ||
    (facts.reservationId && facts.reservationId !== booking.id)
  )
    throw new BadRequestException('Payment reference mismatch');
  let decision = 'APPLIED',
    reason: string | null = null;
  let state = booking.paymentState,
    status: WebsiteReservationStatus = booking.status;
  let gross = booking.paymentGrossMinor,
    refunded = booking.paymentRefundedMinor;
  let timely = booking.paymentTimelyProofAt,
    holdState = booking.holdState;
  let providerStatus = booking.paymentStatus;
  const review = (code: string) => {
    decision = 'REVIEW';
    reason = code;
    if (!['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(state))
      state = 'REVIEW';
  };
  const expected = booking.paymentExpectedMinor;
  const complete =
    facts.orderId === paymentId &&
    facts.reservationId === booking.id &&
    facts.requestedMinor !== null &&
    facts.remainingMinor !== null &&
    facts.refundedMinor !== null;
  const paidStatuses = [
    'completed',
    'refunded_partially',
    'refunded',
    'refund_requested',
  ];
  const fullSignedPayment =
    signed &&
    signed.orderId === paymentId &&
    signed.reservationId === booking.id &&
    signed.capture === 'automatic' &&
    signed.currency === booking.paymentCurrency &&
    signed.requestedMinor === expected &&
    signed.remainingMinor !== null &&
    signed.refundedMinor !== null &&
    BigInt(signed.remainingMinor) + BigInt(signed.refundedMinor) ===
      BigInt(expected ?? '0') &&
    paidStatuses.includes(signed.status);
  // Keep signed causal proof across a provider outage/restart. It does not
  // confirm money by itself; the current pinned receipt still gates admission.
  if (
    fullSignedPayment &&
    sentAt &&
    booking.holdExpiresAt &&
    new Date(sentAt) >= booking.createdAt &&
    new Date(sentAt) <= evidence.observedAt &&
    new Date(sentAt) <= booking.holdExpiresAt &&
    !timely
  )
    timely = new Date(sentAt);
  if (!expected || !booking.paymentCurrency || !booking.holdExpiresAt)
    review('historical_payment_snapshot_missing');
  else if (!complete)
    review(
      evidence.receipt === null
        ? 'provider_receipt_unavailable'
        : 'receipt_incomplete',
    );
  else if (facts.currency !== booking.paymentCurrency)
    review('currency_mismatch');
  else if (facts.requestedMinor !== expected)
    review('requested_amount_mismatch');
  else if (facts.capture !== 'automatic') review('unsupported_capture');
  else {
    const incomingRefund = BigInt(facts.refundedMinor!),
      incomingGross = BigInt(facts.remainingMinor!) + incomingRefund;
    const priorGross = BigInt(gross ?? '0'),
      priorRefund = BigInt(refunded ?? '0');
    if (incomingRefund < priorRefund || incomingGross < priorGross) {
      decision = 'IGNORED_STALE';
      reason = null;
    } else if (
      incomingGross > BigInt(expected) ||
      incomingRefund > BigInt(expected)
    )
      review('settled_amount_mismatch');
    else if (paidStatuses.includes(facts.status)) {
      gross = incomingGross.toString();
      refunded = incomingRefund.toString();
      providerStatus = facts.status;
      if (incomingGross !== BigInt(expected)) review('partial_payment');
      else {
        // BOG documents transfer_amount as the remaining processed amount; its
        // full-refund example is transfer=0/refund=request. Preserve gross paid.
        state =
          incomingRefund === BigInt(expected)
            ? 'REFUNDED'
            : incomingRefund > 0n
              ? 'PARTIALLY_REFUNDED'
              : 'PAID';
        const bound =
          fullSignedPayment &&
          sentAt &&
          new Date(sentAt) >= booking.createdAt &&
          new Date(sentAt) <= evidence.observedAt
            ? new Date(sentAt)
            : evidence.observedAt;
        // A completed receipt observed/sent BEFORE the deadline proves payment
        // was complete by then. A later send time cannot prove a late payment.
        if (!timely && bound <= booking.holdExpiresAt) timely = bound;
        if (state === 'REFUNDED') {
          status = 'FAILED';
          holdState = 'RELEASED';
        } else if (
          booking.holdState === 'CONFIRMED' &&
          booking.status === 'CONFIRMED'
        ) {
          reason =
            facts.status === 'refund_requested' ? 'refund_pending' : null;
        } else if (
          booking.paymentReviewReason === 'on_time_payment_hold_reassigned'
        )
          review('on_time_payment_hold_reassigned');
        else if (!timely) {
          const definitelyLate =
            facts.createdAt &&
            new Date(facts.createdAt) > booking.holdExpiresAt &&
            new Date(facts.createdAt) <= evidence.observedAt;
          review(definitelyLate ? 'late_payment' : 'payment_timing_unproven');
          status = 'FAILED';
          holdState = 'EXPIRED';
        } else {
          const codes = booking.tables
            .map((row) => row.table)
            .map((table) => ({
              floor: table.posFloor,
              number: table.posTableNumber,
            }));
          // Existing hold rows capture physical identity, so aliases/changed
          // layout cannot steal another booking's occupancy during recovery.
          const holds = await tx.websiteReservationDayHold.findMany({
            where: { venueId: booking.venueId, reservationId: booking.id },
          });
          const currentCodes = codes.map((table) =>
            canEncodeTableCode(table.floor, table.number)
              ? encodeTableCode(table.floor, table.number)
              : null,
          );
          if (
            !holds.length ||
            holds.length !== codes.length ||
            holds.some((hold) => !currentCodes.includes(hold.tableCode))
          )
            review('hold_identity_missing');
          else {
            const conflict = await tx.websiteReservationDayHold.findFirst({
              where: {
                venueId: booking.venueId,
                serviceDate: holds[0].serviceDate,
                tableCode: { in: holds.map((row) => row.tableCode) },
                reservationId: { not: booking.id },
                status: { in: ['HELD', 'CONFIRMED'] },
              },
            });
            if (conflict) review('on_time_payment_hold_reassigned');
            else {
              status = 'CONFIRMED';
              holdState = 'CONFIRMED';
              reason =
                facts.status === 'refund_requested' ? 'refund_pending' : null;
            }
          }
        }
      }
    } else if (facts.status === 'rejected' && incomingGross === 0n) {
      state = 'DECLINED';
      status = 'FAILED';
      holdState = 'RELEASED';
      providerStatus = facts.status;
    } else if (
      ['created', 'processing', 'auth_requested', 'blocked'].includes(
        facts.status,
      )
    ) {
      if (
        priorGross > 0n ||
        ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(state)
      )
        decision = 'IGNORED_STALE';
      else {
        state = 'PENDING';
        providerStatus = facts.status;
        reason =
          booking.holdState === 'EXPIRED' ? 'expired_awaiting_receipt' : null;
      }
    } else review('provider_status_unrecognized');
  }
  const observation = await tx.websitePaymentObservation.findUnique({
    where: {
      venueId_reservationId_fingerprint: {
        venueId: booking.venueId,
        reservationId: booking.id,
        fingerprint,
      },
    },
  });
  if (!observation)
    await tx.websitePaymentObservation.create({
      data: {
        venueId: booking.venueId,
        reservationId: booking.id,
        paymentId,
        source: evidence.source,
        fingerprint,
        facts: safeFacts as unknown as Prisma.InputJsonObject,
        decision,
        reason,
        observedAt: evidence.observedAt,
      },
    });
  if (decision === 'IGNORED_STALE') return booking;
  const updated = await tx.websiteReservation.update({
    where: { id: booking.id },
    data: {
      ...(complete && facts.orderId === paymentId ? { paymentId } : {}),
      paymentState: state,
      status,
      paymentStatus: providerStatus,
      paymentGrossMinor: gross,
      paymentRefundedMinor: refunded,
      paymentTimelyProofAt: timely,
      paymentReviewReason: reason,
      holdState,
      nextPaymentCheckAt:
        ['PENDING', 'REVIEW'].includes(state) || reason
          ? new Date(evidence.observedAt.getTime() + 60_000)
          : null,
    },
    include: { tables: { include: { table: true } } },
  });
  if (holdState === 'CONFIRMED')
    await tx.websiteReservationDayHold.updateMany({
      where: { venueId: booking.venueId, reservationId: booking.id },
      data: { status: 'CONFIRMED' },
    });
  if (['RELEASED', 'EXPIRED'].includes(holdState ?? ''))
    await tx.websiteReservationDayHold.updateMany({
      where: { venueId: booking.venueId, reservationId: booking.id },
      data: { status: 'RELEASED' },
    });
  return updated;
}
