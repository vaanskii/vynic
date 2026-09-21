import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { financeDates } from '../finance/finance-common';
import { day } from '../finance/finance-rules';
import { InventoryActor, writeInventoryAudit } from './inventory-audit';
import type { TenantContext } from '../tenancy/tenant-context';

export function paymentSummary(row: any) {
  const paid = (row.payments ?? []).reduce(
    (sum: Prisma.Decimal, p: any) => sum.plus(p.amount),
    new Prisma.Decimal(0),
  );
  const total = new Prisma.Decimal(row.documentTotal);
  return {
    paid: paid.toFixed(2),
    remaining:
      row.status === 'CANCELLED' ? '0.00' : total.minus(paid).toFixed(2),
    paymentStatus: !row.paymentHistoryKnown
      ? 'UNVERIFIED'
      : paid.eq(total)
        ? 'PAID'
        : paid.gt(0)
          ? 'PARTIALLY_PAID'
          : 'UNPAID',
    paymentHistoryKnown: row.paymentHistoryKnown,
    dueDate: row.dueDate ?? null,
  };
}
export class SupplierPayments {
  constructor(private readonly db: PrismaService) {}
  async list(tenant: TenantContext, supplierId?: string) {
    const rows = await this.db.receiving.findMany({
      where: {
        venueId: tenant.venueId,
        OR: [
          { status: 'POSTED' },
          { status: 'CANCELLED', payments: { some: {} } },
        ],
        ...(supplierId ? { supplierId } : {}),
      },
      include: { payments: { orderBy: { createdAt: 'desc' } } },
      orderBy: [{ businessDate: 'desc' }, { id: 'desc' }],
    });
    let outstanding = new Prisma.Decimal(0),
      unverified = new Prisma.Decimal(0);
    const receivings = rows.map((row) => {
      const summary = paymentSummary(row);
      if (row.paymentHistoryKnown)
        outstanding = outstanding.plus(summary.remaining);
      else unverified = unverified.plus(summary.remaining);
      return {
        id: row.id,
        status: row.status,
        supplierId: row.supplierId,
        supplierName: row.supplierNameSnapshot,
        businessDate: row.businessDate,
        documentTotal: row.documentTotal.toFixed(2),
        ...summary,
        payments: row.payments.map((p) => ({
          ...p,
          amount: p.amount.toFixed(2),
        })),
      };
    });
    return {
      ...(await financeDates(this.db, tenant)),
      outstanding: outstanding.toFixed(2),
      unverified: unverified.toFixed(2),
      receivings,
    };
  }
  async reverse(
    actor: InventoryActor,
    receivingId: string,
    paymentId: string,
    input: any,
  ) {
    const paymentDate = day(input.paymentDate),
      businessDate = day(input.businessDate ?? paymentDate);
    const reason = optional(input.notes);
    if (!reason)
      throw new BadRequestException(
        'Record the reason for an actual refund or correction',
      );
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM pos."Receiving" WHERE id=${receivingId} AND "venueId"=${actor.venueId} FOR UPDATE`;
      const original = await tx.supplierPayment.findFirst({
        where: { id: paymentId, receivingId, venueId: actor.venueId },
      });
      if (!original) throw new NotFoundException('Payment not found');
      if (original.amount.lt(0))
        throw new BadRequestException('Cannot reverse a reversal');
      const prior = await tx.supplierPayment.findUnique({
        where: { reversalOfId: paymentId },
      });
      if (prior) {
        if (
          prior.notes !== reason ||
          prior.paymentDate !== paymentDate ||
          prior.businessDate !== businessDate
        )
          throw new ConflictException(
            'Reversal already recorded with different values',
          );
        return { id: prior.id };
      }
      const today = (await financeDates(tx, actor)).today;
      if (
        paymentDate < original.paymentDate ||
        paymentDate > today ||
        businessDate > today
      )
        throw new BadRequestException('Invalid reversal date');
      const reversal = await tx.supplierPayment.create({
        data: {
          venueId: actor.venueId,
          receivingId,
          requestId: 'reverse:' + paymentId,
          amount: original.amount.negated(),
          paymentDate,
          businessDate,
          method: original.method,
          actorId: actor.staffId,
          actorName: actor.username,
          notes: reason,
          reversalOfId: paymentId,
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: 'SUPPLIER_PAYMENT_REVERSED',
        entityType: 'RECEIVING',
        entityId: receivingId,
        data: {
          paymentId,
          reversalId: reversal.id,
          amount: reversal.amount.toFixed(2),
          reason,
        },
      });
      return { id: reversal.id };
    });
  }
  async verifyHistory(actor: InventoryActor, receivingId: string, input: any) {
    const notes = optional(input.notes);
    if (!notes || input.confirmNoUnrecordedPayments !== true)
      throw new BadRequestException(
        'Confirm no unrecorded payments and explain the evidence',
      );
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM pos."Receiving" WHERE id=${receivingId} AND "venueId"=${actor.venueId} FOR UPDATE`;
      const row = await tx.receiving.findFirst({
        where: { id: receivingId, venueId: actor.venueId },
      });
      if (!row) throw new NotFoundException('Receiving not found');
      if (!row.paymentHistoryKnown) {
        await tx.receiving.update({
          where: { id: receivingId },
          data: { paymentHistoryKnown: true },
        });
        await writeInventoryAudit(tx, actor, {
          action: 'SUPPLIER_SETTLEMENT_VERIFIED',
          entityType: 'RECEIVING',
          entityId: receivingId,
          data: { notes },
        });
      }
      return { verified: true };
    });
  }
  async record(actor: InventoryActor, receivingId: string, input: any) {
    if (!/^[0-9a-f-]{36}$/i.test(input.requestId ?? ''))
      throw new BadRequestException('requestId must be a UUID');
    const date = day(input.paymentDate),
      businessDate = day(input.businessDate ?? date);
    if (!['cash', 'bank'].includes(input.method))
      throw new BadRequestException('Choose cash or bank');
    const raw = String(input.amount ?? '');
    if (!/^\d+(\.\d{1,2})?$/.test(raw))
      throw new BadRequestException(
        'amount must be positive GEL with at most two decimals',
      );
    const amount = new Prisma.Decimal(raw);
    if (!amount.gt(0) || amount.gte('10000000000000000'))
      throw new BadRequestException('Invalid amount');
    const notes = optional(input.notes),
      reference = optional(input.reference);
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${actor.venueId + ':payment:' + input.requestId},0))`;
      await tx.$queryRaw`SELECT id FROM pos."Receiving" WHERE id=${receivingId} AND "venueId"=${actor.venueId} FOR UPDATE`;
      const row = await tx.receiving.findFirst({
        where: { id: receivingId, venueId: actor.venueId },
        include: { payments: true },
      });
      if (!row) throw new NotFoundException('Receiving not found');
      const prior = await tx.supplierPayment.findUnique({
        where: {
          venueId_requestId: {
            venueId: actor.venueId,
            requestId: input.requestId,
          },
        },
      });
      if (prior) {
        if (
          prior.receivingId !== receivingId ||
          !prior.amount.eq(amount) ||
          prior.paymentDate !== date ||
          prior.businessDate !== businessDate ||
          prior.method !== input.method ||
          prior.notes !== notes ||
          prior.reference !== reference
        )
          throw new ConflictException(
            'Payment request already used with different values',
          );
        return paymentSummary(row);
      }
      if (row.status !== 'POSTED')
        throw new ConflictException('Only posted goods can be paid');

      if (amount.gt(paymentSummary(row).remaining))
        throw new ConflictException('Payment exceeds remaining payable');
      const today = (await financeDates(tx, actor)).today;
      if (date > today || businessDate > today)
        throw new BadRequestException('Payment cannot be in the future');
      const payment = await tx.supplierPayment.create({
        data: {
          venueId: actor.venueId,
          receivingId,
          requestId: input.requestId,
          amount,
          paymentDate: date,
          businessDate,
          method: input.method,
          actorId: actor.staffId,
          actorName: actor.username,
          notes,
          reference,
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: 'SUPPLIER_PAYMENT_RECORDED',
        entityType: row.supplierId ? 'SUPPLIER' : 'RECEIVING',
        entityId: row.supplierId ?? receivingId,
        data: {
          receivingId,
          paymentId: payment.id,
          amount: amount.toFixed(2),
          businessDate,
          paymentDate: date,
        },
      });
      return paymentSummary({ ...row, payments: [...row.payments, payment] });
    });
  }
}
function optional(raw: unknown): string | null {
  if (raw == null || raw === '') return null;
  if (typeof raw !== 'string' || raw.length > 2000)
    throw new BadRequestException('Invalid text');
  return raw.trim() || null;
}
