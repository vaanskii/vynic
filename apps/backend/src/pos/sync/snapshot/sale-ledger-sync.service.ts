import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { TenantContext } from '../../../tenancy/tenant-context';
import { PrismaService } from '../../../prisma.service';
import type {
  SaleLedgerDaySync,
  SaleLedgerSync,
  SalePaymentSync,
} from '../sync-payload';

const MONEY = /^-?\d{1,16}\.\d{2}$/;
const BUSINESS_DATE = /^\d{4}-\d{2}-\d{2}$/;
const ALLOWED_PAYMENTS = new Set([
  'cash',
  'card',
  'card-tbc',
  'card-bog',
  'advance',
  'other',
]);

export interface SaleLedgerAck {
  posSaleId: string;
  revision: number;
}

export interface SaleLedgerSyncResult {
  acknowledgements: SaleLedgerAck[];
}

/** Cloud equivalent of `SalesRepository.countsAsRevenue`. */
export function cloudSaleCountsAsRevenue(sale: {
  isFiscal: boolean;
  isCancelled: boolean;
  restoredToOrder: boolean;
}): boolean {
  return sale.isFiscal && !sale.isCancelled && !sale.restoredToOrder;
}

function decimal(value: string, field: string): Prisma.Decimal {
  if (!MONEY.test(value)) {
    throw new BadRequestException(
      `${field} must be a fixed two-decimal string`,
    );
  }
  return new Prisma.Decimal(value);
}

function instant(value: string | null | undefined, field: string): Date | null {
  if (value == null) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) {
    throw new BadRequestException(`${field} must be an ISO timestamp`);
  }
  return parsed;
}

function paymentTotal(
  payments: SalePaymentSync[],
  includeAdvance: boolean,
): Prisma.Decimal {
  return payments.reduce((sum, payment) => {
    if (!includeAdvance && payment.method === 'advance') return sum;
    return sum.plus(decimal(payment.amount, `payments.${payment.method}`));
  }, new Prisma.Decimal(0));
}

@Injectable()
export class SaleLedgerSyncService {
  constructor(private readonly prisma: PrismaService) {}

  async sync(
    tenant: TenantContext,
    sales: SaleLedgerSync[] | undefined,
    days: SaleLedgerDaySync[] | undefined,
  ): Promise<SaleLedgerSyncResult> {
    const acknowledgements: SaleLedgerAck[] = [];
    for (const sale of sales ?? []) {
      const revision = await this.upsertSale(tenant, sale);
      acknowledgements.push({ posSaleId: sale.posSaleId, revision });
    }
    for (const day of days ?? []) {
      await this.reconcileDay(tenant, day);
    }
    return { acknowledgements };
  }

  private validate(sale: SaleLedgerSync) {
    if (!sale.posSaleId.trim()) {
      throw new BadRequestException('posSaleId is required');
    }
    if (
      !Number.isInteger(sale.posOrderId) ||
      sale.posOrderId < 1 ||
      !Number.isInteger(sale.revision) ||
      sale.revision < 1
    ) {
      throw new BadRequestException('Sale identity/revision is invalid');
    }
    if (!BUSINESS_DATE.test(sale.businessDate)) {
      throw new BadRequestException('businessDate must be YYYY-MM-DD');
    }
    if (
      !instant(sale.createdAt, 'createdAt') ||
      !instant(sale.closedAt, 'closedAt') ||
      !instant(sale.sourceUpdatedAt, 'sourceUpdatedAt')
    ) {
      throw new BadRequestException('Sale timestamps are required');
    }
    if (
      new Set(sale.lines.map((line) => line.lineSeq)).size !== sale.lines.length
    ) {
      throw new BadRequestException('Sale lineSeq values must be unique');
    }
    if (
      new Set(sale.payments.map((part) => part.method)).size !==
      sale.payments.length
    ) {
      throw new BadRequestException('Sale payment methods must be unique');
    }
    for (const part of sale.payments) {
      const normalized = part.method.startsWith('other:')
        ? 'other'
        : part.method;
      if (!ALLOWED_PAYMENTS.has(normalized)) {
        throw new BadRequestException(
          `Unsupported Sale payment method ${part.method}`,
        );
      }
      if (!decimal(part.amount, `payments.${part.method}`).isPositive()) {
        throw new BadRequestException('Sale payment amounts must be positive');
      }
    }

    const gross = decimal(sale.gross, 'gross');
    const advance = decimal(sale.advanceApplied, 'advanceApplied');
    const due = decimal(sale.amountDueNow, 'amountDueNow');
    const collected = decimal(sale.collectedNow, 'collectedNow');
    if (!gross.equals(advance.plus(due))) {
      throw new BadRequestException(
        'gross must equal advanceApplied + amountDueNow',
      );
    }
    // Non-fiscal history preserves the advance context, but records no payment
    // rows: that receipt was collected earlier, not at this internal close.
    // Fiscal Sales still require an exact advance payment part below.
    if (!sale.isFiscal && (!collected.isZero() || sale.payments.length > 0)) {
      throw new BadRequestException('Non-fiscal Sales cannot collect tender');
    }
    if (sale.isFiscal && !collected.equals(due)) {
      throw new BadRequestException(
        'collectedNow must equal amountDueNow for fiscal Sales',
      );
    }
    if (!paymentTotal(sale.payments, false).equals(collected)) {
      throw new BadRequestException(
        'Tender payment parts must equal collectedNow',
      );
    }
    const advancePart = sale.payments.find((part) => part.method === 'advance');
    const advancePartAmount = advancePart
      ? decimal(advancePart.amount, 'payments.advance')
      : new Prisma.Decimal(0);
    if (sale.isFiscal && !advancePartAmount.equals(advance)) {
      throw new BadRequestException(
        'Advance payment part must equal advanceApplied',
      );
    }

    for (const line of sale.lines) {
      if (
        !Number.isInteger(line.lineSeq) ||
        line.lineSeq < 0 ||
        !Number.isInteger(line.quantity) ||
        line.quantity < 1
      ) {
        throw new BadRequestException(
          'Sale line sequence/quantity must be integers',
        );
      }
      const unitPrice = decimal(
        line.unitPrice,
        `lines.${line.lineSeq}.unitPrice`,
      );
      const lineTotal = decimal(
        line.lineTotal,
        `lines.${line.lineSeq}.lineTotal`,
      );
      if (!unitPrice.times(line.quantity).equals(lineTotal)) {
        throw new BadRequestException(
          `Sale line ${line.lineSeq} total must equal unit price × quantity`,
        );
      }
    }
  }

  private async upsertSale(
    tenant: TenantContext,
    sale: SaleLedgerSync,
  ): Promise<number> {
    this.validate(sale);
    const existing = await (this.prisma as any).cloudSale.findUnique({
      where: {
        venueId_posSaleId: {
          venueId: tenant.venueId,
          posSaleId: sale.posSaleId,
        },
      },
      select: { id: true, sourceRevision: true },
    });
    if (existing && existing.sourceRevision >= sale.revision) {
      return existing.sourceRevision;
    }

    const lifecycle = {
      isCancelled: sale.isCancelled,
      cancelledAt: instant(sale.cancelledAt, 'cancelledAt'),
      cancelledBy: sale.cancelledBy ?? null,
      cancellationReason: sale.cancellationReason ?? null,
      restoredToOrder: sale.restoredToOrder,
      restoredAt: instant(sale.restoredAt, 'restoredAt'),
      restoredBy: sale.restoredBy ?? null,
      sourceRevision: sale.revision,
      sourceUpdatedAt: instant(sale.sourceUpdatedAt, 'sourceUpdatedAt')!,
    };

    if (existing) {
      await (this.prisma as any).cloudSale.updateMany({
        where: { id: existing.id, sourceRevision: { lt: sale.revision } },
        data: lifecycle,
      });
      const current = await (this.prisma as any).cloudSale.findUnique({
        where: { id: existing.id },
        select: { sourceRevision: true },
      });
      return current.sourceRevision;
    }

    try {
      await (this.prisma as any).cloudSale.create({
        data: {
          venueId: tenant.venueId,
          posSaleId: sale.posSaleId,
          posOrderId: sale.posOrderId,
          closureId: sale.closureId ?? null,
          businessDate: sale.businessDate,
          createdAt: instant(sale.createdAt, 'createdAt')!,
          closedAt: instant(sale.closedAt, 'closedAt')!,
          gross: decimal(sale.gross, 'gross'),
          subtotal: decimal(sale.subtotal, 'subtotal'),
          serviceFee: decimal(sale.serviceFee, 'serviceFee'),
          discount: decimal(sale.discount, 'discount'),
          manualAdjustment: decimal(sale.manualAdjustment, 'manualAdjustment'),
          advanceApplied: decimal(sale.advanceApplied, 'advanceApplied'),
          amountDueNow: decimal(sale.amountDueNow, 'amountDueNow'),
          collectedNow: decimal(sale.collectedNow, 'collectedNow'),
          paymentMethod: sale.paymentMethod,
          customPaymentLabel: sale.customPaymentLabel ?? null,
          isFiscal: sale.isFiscal,
          ...lifecycle,
          createdBy: sale.createdBy,
          closedById: sale.closedById ?? null,
          tableNumbers: sale.tableNumbers,
          floor: sale.floor,
          lines: {
            create: sale.lines.map((line) => ({
              lineSeq: line.lineSeq,
              menuItemId: line.menuItemId ?? null,
              variantId: line.variantId ?? null,
              itemName: line.itemName,
              variantName: line.variantName ?? null,
              quantity: line.quantity,
              unitPrice: decimal(
                line.unitPrice,
                `lines.${line.lineSeq}.unitPrice`,
              ),
              lineTotal: decimal(
                line.lineTotal,
                `lines.${line.lineSeq}.lineTotal`,
              ),
              comment: line.comment ?? null,
            })),
          },
          payments: {
            create: sale.payments.map((payment) => ({
              method: payment.method,
              amount: decimal(payment.amount, `payments.${payment.method}`),
            })),
          },
        },
      });
    } catch (error) {
      // Concurrent retry of the same POS identity: the winner created the
      // row, so apply this revision through the guarded update path. A
      // closureId collision with another Sale is not swallowed.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const winner = await (this.prisma as any).cloudSale.findUnique({
          where: {
            venueId_posSaleId: {
              venueId: tenant.venueId,
              posSaleId: sale.posSaleId,
            },
          },
          select: { id: true },
        });
        if (winner) return this.upsertSale(tenant, sale);
      }
      throw error;
    }
    return sale.revision;
  }

  private async reconcileDay(tenant: TenantContext, day: SaleLedgerDaySync) {
    if (!BUSINESS_DATE.test(day.businessDate)) {
      throw new BadRequestException('Ledger day must be YYYY-MM-DD');
    }
    const sales = await (this.prisma as any).cloudSale.findMany({
      where: { venueId: tenant.venueId, businessDate: day.businessDate },
      select: {
        gross: true,
        isFiscal: true,
        isCancelled: true,
        restoredToOrder: true,
      },
    });
    const revenueSales = sales.filter(cloudSaleCountsAsRevenue);
    const ledgerRevenue = revenueSales.reduce(
      (sum: Prisma.Decimal, sale: { gross: Prisma.Decimal }) =>
        sum.plus(sale.gross),
      new Prisma.Decimal(0),
    );
    const expectedRevenue = day.expectedRevenue
      ? decimal(day.expectedRevenue, 'expectedRevenue')
      : null;
    const legacyRevenue = day.legacyRevenue
      ? decimal(day.legacyRevenue, 'legacyRevenue')
      : null;
    const provenComplete =
      day.uploadComplete &&
      !day.legacySummaryOnly &&
      day.expectedSaleCount != null &&
      expectedRevenue != null &&
      day.expectedSaleCount === sales.length &&
      expectedRevenue.equals(ledgerRevenue);

    const completeness = day.legacySummaryOnly
      ? 'LEGACY_SUMMARY_ONLY'
      : provenComplete
        ? 'COMPLETE'
        : 'PARTIAL';
    const reconciliation = day.legacySummaryOnly
      ? 'LEGACY_ONLY'
      : !provenComplete
        ? 'INCOMPLETE'
        : legacyRevenue == null || legacyRevenue.equals(ledgerRevenue)
          ? 'MATCHED'
          : 'MISMATCH';
    await (this.prisma as any).saleLedgerDay.upsert({
      where: {
        venueId_businessDate: {
          venueId: tenant.venueId,
          businessDate: day.businessDate,
        },
      },
      create: {
        venueId: tenant.venueId,
        businessDate: day.businessDate,
        completeness,
        reconciliation,
        expectedSaleCount: day.expectedSaleCount ?? null,
        expectedRevenue,
        ledgerSaleCount: sales.length,
        ledgerRevenue,
        legacyRevenue,
        declaredCompleteAt: provenComplete ? new Date() : null,
        lastSyncedAt: new Date(),
      },
      update: {
        completeness,
        reconciliation,
        expectedSaleCount: day.expectedSaleCount ?? null,
        expectedRevenue,
        ledgerSaleCount: sales.length,
        ledgerRevenue,
        legacyRevenue,
        declaredCompleteAt: provenComplete ? new Date() : null,
        lastSyncedAt: new Date(),
      },
    });
  }
}
