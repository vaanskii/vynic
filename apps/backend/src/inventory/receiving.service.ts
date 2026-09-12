import { createHash } from 'node:crypto';
import { paymentSummary, SupplierPayments } from './supplier-payments';
import { stockQuantityText } from './inventory-quantity';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, ReceivingStatus, StockMovementType } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import {
  InventoryAuditAction,
  writeInventoryAudit,
  type InventoryActor,
} from './inventory-audit';
import {
  baseUnitCostText,
  lineMoney,
  moneyText,
  multiplierText,
  nonNegativeCost,
  positiveQuantity,
  quantityText,
  resolveBaseQuantity,
  sumMoney,
  unitCostText,
} from './inventory-quantity';
import { inventoryUnit } from './inventory-unit';

export interface ReceivingLineInput {
  stockItemId?: unknown;
  enteredQuantity?: unknown;
  enteredUnit?: unknown;
  unitPurchaseCost?: unknown;
  lineTotal?: unknown;
  priceBasis?: unknown;
  notes?: unknown;
}

export interface ReceivingInput {
  requestId?: unknown;
  supplierId?: unknown;
  sourceType?: unknown;
  sourceLabel?: unknown;
  dueDate?: unknown;
  waybillNumber?: unknown;
  invoiceNumber?: unknown;
  documentDate?: unknown;
  businessDate?: unknown;
  receivedAt?: unknown;
  notes?: unknown;
  lines?: unknown;
}

export interface ReceivingListQuery {
  businessDate?: string;
  from?: string;
  to?: string;
  supplierId?: string;
  status?: string;
  search?: string;
  take?: number;
  cursor?: string;
}

/** A line after validation, ready to persist. */
interface PreparedLine {
  lineSequence: number;
  stockItemId: string;
  stockItemNameSnapshot: string;
  enteredQuantity: Prisma.Decimal;
  enteredUnit: string;
  baseQuantity: Prisma.Decimal;
  baseUnit: string;
  unitPurchaseCost: Prisma.Decimal;
  lineTotal: Prisma.Decimal;
  effectiveBaseUnitCost: Prisma.Decimal;
  notes: string | null;
}

const MAX_PAGE = 100;
const DEFAULT_PAGE = 25;

/**
 * Receiving documents and the movements they produce.
 *
 * The three states mean three different things about stock. A DRAFT is working
 * paper: it can be edited freely and has moved nothing. POSTED is the only
 * state behind which StockMovements exist. CANCELLED keeps the document and
 * its original movements and adds reversals beside them, because a receipt that
 * was entered and then withdrawn is two facts, not zero.
 *
 * Posting and cancelling both take a row lock on the document and both rely on
 * a database uniqueness rule as the final word, so a redelivered command or two
 * simultaneous clicks cannot double a venue's stock.
 */
@Injectable()
export class ReceivingService {
  constructor(private readonly prisma: PrismaService) {}

  reversePayment(
    actor: InventoryActor,
    id: string,
    paymentId: string,
    input: unknown,
  ) {
    return new SupplierPayments(this.prisma).reverse(
      actor,
      id,
      paymentId,
      input,
    );
  }
  verifyPayments(actor: InventoryActor, id: string, input: unknown) {
    return new SupplierPayments(this.prisma).verifyHistory(actor, id, input);
  }
  payments(tenant: TenantContext, supplierId?: string) {
    return new SupplierPayments(this.prisma).list(tenant, supplierId);
  }
  recordPayment(actor: InventoryActor, id: string, input: unknown) {
    return new SupplierPayments(this.prisma).record(actor, id, input);
  }

  // ── Reads ───────────────────────────────────────────────────────────────

  async list(tenant: TenantContext, query: ReceivingListQuery = {}) {
    const take = Math.min(
      Math.max(Math.trunc(query.take ?? DEFAULT_PAGE), 1),
      MAX_PAGE,
    );
    const search = query.search?.trim();
    const where: Prisma.ReceivingWhereInput = {
      venueId: tenant.venueId,
      ...(query.businessDate
        ? { businessDate: isoDateText(query.businessDate) }
        : {}),
      ...(query.supplierId?.trim()
        ? { supplierId: query.supplierId.trim() }
        : {}),
      ...(query.status?.trim()
        ? { status: receivingStatus(query.status) }
        : {}),
      ...(query.from?.trim() || query.to?.trim()
        ? {
            businessDate: {
              ...(query.from?.trim() ? { gte: isoDateText(query.from) } : {}),
              ...(query.to?.trim() ? { lte: isoDateText(query.to) } : {}),
            },
          }
        : {}),
      ...(search
        ? {
            OR: [
              { waybillNumber: { contains: search, mode: 'insensitive' } },
              { invoiceNumber: { contains: search, mode: 'insensitive' } },
              {
                supplierNameSnapshot: {
                  contains: search,
                  mode: 'insensitive',
                },
              },
            ],
          }
        : {}),
    };

    const rows = await this.prisma.receiving.findMany({
      where,
      orderBy: [
        { businessDate: 'desc' },
        { createdAt: 'desc' },
        { id: 'desc' },
      ],
      take: take + 1,
      ...(query.cursor?.trim()
        ? { cursor: { id: query.cursor.trim() }, skip: 1 }
        : {}),
      include: { payments: true, _count: { select: { lines: true } } },
    });

    const page = rows.slice(0, take);
    const days = await this.prisma.receiving.groupBy({
      by: ['businessDate', 'status'],
      where: {
        venueId: tenant.venueId,
        businessDate: { in: [...new Set(page.map((row) => row.businessDate))] },
      },
      _sum: { documentTotal: true },
      _count: { _all: true },
    });
    return {
      businessDays: days.map((day) => ({
        businessDate: day.businessDate,
        status: day.status,
        count: day._count._all,
        total: (day._sum.documentTotal ?? new Prisma.Decimal(0)).toFixed(2),
      })),
      currentBusinessDate: await this.currentBusinessDate(tenant),
      receivings: page.map((row) => this.presentSummary(row)),
      nextCursor: rows.length > take ? (page.at(-1)?.id ?? null) : null,
    };
  }

  async detail(tenant: TenantContext, id: string) {
    const row = await this.prisma.receiving.findFirst({
      where: { id: requiredText(id, 'id'), venueId: tenant.venueId },
      include: {
        payments: true,
        lines: { orderBy: { lineSequence: 'asc' } },
        movements: { orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] },
        _count: { select: { lines: true } },
      },
    });
    if (!row) throw new NotFoundException('Receiving not found');
    return {
      ...this.presentSummary(row),
      lines: row.lines.map((line) => this.presentLine(line)),
      movements: row.movements.map((movement) => presentMovement(movement)),
    };
  }

  // ── Draft lifecycle ─────────────────────────────────────────────────────

  async createDraft(actor: InventoryActor, input: ReceivingInput) {
    const header = this.readHeader(input);
    const requestId =
      input.requestId == null
        ? null
        : requiredText(input.requestId, 'requestId');
    if (requestId && !/^[0-9a-f-]{36}$/i.test(requestId))
      throw new BadRequestException('requestId must be UUID');
    const fingerprint = createHash('sha256')
      .update(JSON.stringify(input))
      .digest('hex');
    return this.prisma.$transaction(async (tx) => {
      if (requestId) {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${actor.venueId + ':receipt:' + requestId},0))`;
        const prior = await tx.receiving.findUnique({
          where: {
            venueId_creationRequestId: {
              venueId: actor.venueId,
              creationRequestId: requestId,
            },
          },
        });
        if (prior) {
          if (prior.creationFingerprint !== fingerprint)
            throw new ConflictException(
              'Receiving request reused with different values',
            );
          return this.loadDetail(tx, prior.id);
        }
      }
      const supplier = header.supplierId
        ? await this.requireSupplier(tx, actor, header.supplierId)
        : null;
      const lines = await this.prepareLines(tx, actor, input.lines);
      const created = await tx.receiving.create({
        data: {
          venueId: actor.venueId,
          dueDate: input.dueDate ? isoDateText(input.dueDate) : null,
          supplierId: supplier?.id ?? null,
          sourceType: header.sourceType,
          supplierNameSnapshot: supplier?.name ?? header.sourceLabel,
          waybillNumber: header.waybillNumber,
          invoiceNumber: header.invoiceNumber,
          documentDate: header.documentDate,
          businessDate: isoDateText(
            input.businessDate ??
              (await this.currentBusinessDate(actor)) ??
              header.documentDate,
          ),
          receivedAt: header.receivedAt,
          notes: header.notes,
          creationRequestId: requestId,
          creationFingerprint: fingerprint,
          status: ReceivingStatus.DRAFT,
          documentTotal: sumMoney(lines.map((line) => line.lineTotal)),
          createdById: actor.staffId,
          createdByName: actor.username,
          lines: { create: lines },
        },
        include: {
          payments: true,
          lines: { orderBy: { lineSequence: 'asc' } },
          movements: true,
          _count: { select: { lines: true } },
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: InventoryAuditAction.RECEIVING_CREATED,
        entityType: 'RECEIVING',
        entityId: created.id,
        data: this.auditContext(created),
      });
      return this.presentDetail(created);
    });
  }

  async updateDraft(actor: InventoryActor, id: string, input: ReceivingInput) {
    const cleanId = requiredText(id, 'id');
    const header = this.readHeader(input);
    return this.prisma.$transaction(async (tx) => {
      const existing = await this.lockReceiving(tx, actor.venueId, cleanId);
      if (existing.status !== ReceivingStatus.DRAFT) {
        throw new ConflictException(
          `A ${existing.status.toLowerCase()} Receiving is inventory history and cannot be edited`,
        );
      }
      const supplier = header.supplierId
        ? await this.requireSupplier(tx, actor, header.supplierId)
        : null;
      const lines = await this.prepareLines(tx, actor, input.lines);
      await tx.receivingLine.deleteMany({ where: { receivingId: cleanId } });
      const updated = await tx.receiving.update({
        where: { id: cleanId },
        data: {
          dueDate: input.dueDate ? isoDateText(input.dueDate) : null,
          supplierId: supplier?.id ?? null,
          sourceType: header.sourceType,
          supplierNameSnapshot: supplier?.name ?? header.sourceLabel,
          waybillNumber: header.waybillNumber,
          invoiceNumber: header.invoiceNumber,
          documentDate: header.documentDate,
          businessDate: isoDateText(
            input.businessDate ?? existing.businessDate,
          ),
          receivedAt: header.receivedAt,
          notes: header.notes,
          documentTotal: sumMoney(lines.map((line) => line.lineTotal)),
          lines: { create: lines },
        },
        include: {
          payments: true,
          lines: { orderBy: { lineSequence: 'asc' } },
          movements: true,
          _count: { select: { lines: true } },
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: InventoryAuditAction.RECEIVING_UPDATED,
        entityType: 'RECEIVING',
        entityId: updated.id,
        data: this.auditContext(updated),
      });
      return this.presentDetail(updated);
    });
  }

  /**
   * A draft is working paper and may be discarded. A posted or cancelled
   * document never can be: the database itself refuses, because its movements
   * reference its lines.
   */
  async deleteDraft(actor: InventoryActor, id: string) {
    const cleanId = requiredText(id, 'id');
    return this.prisma.$transaction(async (tx) => {
      const existing = await this.lockReceiving(tx, actor.venueId, cleanId);
      if (existing.status !== ReceivingStatus.DRAFT) {
        throw new ConflictException(
          'Only a draft Receiving can be deleted; post it and cancel it instead',
        );
      }
      await tx.receiving.delete({ where: { id: cleanId } });
      return { id: cleanId, deleted: true };
    });
  }

  // ── Posting ─────────────────────────────────────────────────────────────

  /**
   * Freeze the document and write one movement per line, atomically.
   *
   * Redelivery is expected, not exceptional: a Manager double-tap and a retried
   * request both arrive here. The row lock serialises them, the status check
   * turns the second into `already_posted`, and the movement's unique index
   * over `(receivingLineId, movementType)` is the backstop if anything ever
   * gets past both.
   */
  async post(actor: InventoryActor, id: string) {
    const cleanId = requiredText(id, 'id');
    return this.prisma.$transaction(async (tx) => {
      const locked = await this.lockReceiving(tx, actor.venueId, cleanId);

      if (locked.status === ReceivingStatus.POSTED) {
        return {
          ...(await this.loadDetail(tx, cleanId)),
          result: 'already_posted' as const,
        };
      }
      if (locked.status === ReceivingStatus.CANCELLED) {
        throw new ConflictException('A cancelled Receiving cannot be posted');
      }

      const lines = await tx.receivingLine.findMany({
        where: { receivingId: cleanId },
        orderBy: { lineSequence: 'asc' },
      });
      if (lines.length === 0) {
        throw new BadRequestException(
          'A Receiving must have at least one line before it is posted',
        );
      }

      // Re-validate against live tenancy: a Stock Item may have been disabled
      // or a Supplier reassigned while the draft sat open.
      const stockItems = await tx.stockItem.findMany({
        where: {
          id: { in: lines.map((line) => line.stockItemId) },
          venueId: actor.venueId,
        },
        select: { id: true, baseUnit: true },
      });
      const byId = new Map(stockItems.map((item) => [item.id, item]));
      for (const line of lines) {
        const item = byId.get(line.stockItemId);
        if (!item) {
          throw new BadRequestException(
            `Stock item ${line.stockItemId} does not belong to this Venue`,
          );
        }
        if (item.baseUnit !== line.baseUnit) {
          throw new ConflictException(
            `Stock item base unit changed to ${item.baseUnit} after this line was entered as ${line.baseUnit}; re-enter the line`,
          );
        }
        if (line.baseQuantity.lessThanOrEqualTo(0)) {
          throw new BadRequestException('Line quantities must be positive');
        }
        if (line.unitPurchaseCost.isNegative()) {
          throw new BadRequestException('Line costs must not be negative');
        }
      }
      if (locked.supplierId)
        await this.requireSupplier(tx, actor, locked.supplierId);

      await tx.$queryRaw`SELECT id FROM pos."StockItem" WHERE "venueId"=${actor.venueId} AND id IN (SELECT "stockItemId" FROM pos."ReceivingLine" WHERE "receivingId"=${cleanId}) ORDER BY id FOR UPDATE`;
      const postedAt = new Date();
      await tx.stockMovement.createMany({
        data: lines.map((line) => ({
          venueId: actor.venueId,
          stockItemId: line.stockItemId,
          movementType: StockMovementType.RECEIVING,
          quantityDeltaBase: line.baseQuantity,
          baseUnit: line.baseUnit,
          receivingId: cleanId,
          receivingLineId: line.id,
          businessDate: locked.businessDate,
          effectiveAt: locked.receivedAt,
          actorId: actor.staffId,
          actorName: actor.username,
          source: 'MANAGER',
          details: {
            waybillNumber: locked.waybillNumber,
            lineSequence: line.lineSequence,
            stockItemName: line.stockItemNameSnapshot,
          } as Prisma.InputJsonValue,
        })),
      });

      const posted = await tx.receiving.update({
        where: { id: cleanId },
        data: {
          status: ReceivingStatus.POSTED,
          paymentHistoryKnown: true,
          postedAt,
          postedById: actor.staffId,
          postedByName: actor.username,
          documentTotal: sumMoney(lines.map((line) => line.lineTotal)),
        },
        include: {
          payments: true,
          lines: { orderBy: { lineSequence: 'asc' } },
          movements: { orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] },
          _count: { select: { lines: true } },
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: InventoryAuditAction.RECEIVING_POSTED,
        entityType: 'RECEIVING',
        entityId: posted.id,
        data: {
          ...this.auditContext(posted),
          previousStatus: ReceivingStatus.DRAFT,
          newStatus: ReceivingStatus.POSTED,
          movementCount: lines.length,
        },
      });
      return { ...this.presentDetail(posted), result: 'posted' as const };
    });
  }

  // ── Cancellation ────────────────────────────────────────────────────────

  /**
   * Withdraw a posted receipt without erasing it.
   *
   * Every original RECEIVING movement gains exactly one mirrored reversal, and
   * `reversalOfMovementId` is unique, so a second cancellation adds nothing. The
   * reversal is dated when the cancellation happened rather than when the goods
   * arrived: the day the stock genuinely was on the shelf keeps saying so.
   */
  async cancel(actor: InventoryActor, id: string, reason?: unknown) {
    const cleanId = requiredText(id, 'id');
    const cancellationReason = optionalText(reason);
    return this.prisma.$transaction(async (tx) => {
      const locked = await this.lockReceiving(tx, actor.venueId, cleanId);

      if (locked.status === ReceivingStatus.CANCELLED) {
        return {
          ...(await this.loadDetail(tx, cleanId)),
          result: 'already_cancelled' as const,
        };
      }
      if (locked.status !== ReceivingStatus.POSTED) {
        throw new ConflictException(
          'Only a posted Receiving can be cancelled; delete the draft instead',
        );
      }

      const paid = await tx.supplierPayment.aggregate({
        where: { venueId: actor.venueId, receivingId: cleanId },
        _sum: { amount: true },
      });
      const settlement = await tx.receiving.findUniqueOrThrow({
        where: { id: cleanId },
      });
      if (
        !settlement.paymentHistoryKnown ||
        !new Prisma.Decimal(paid._sum.amount ?? 0).isZero()
      ) {
        throw new ConflictException(
          'Cannot cancel: supplier settlement must be verified and payments reversed first',
        );
      }
      const originals = await tx.stockMovement.findMany({
        where: {
          receivingId: cleanId,
          venueId: actor.venueId,
          movementType: StockMovementType.RECEIVING,
        },
        orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      });
      const alreadyReversed = new Set(
        (
          await tx.stockMovement.findMany({
            where: {
              receivingId: cleanId,
              movementType: StockMovementType.RECEIVING_REVERSAL,
            },
            select: { reversalOfMovementId: true },
          })
        ).flatMap((row) =>
          row.reversalOfMovementId ? [row.reversalOfMovementId] : [],
        ),
      );

      await tx.$queryRaw`SELECT id FROM pos."StockItem" WHERE "venueId"=${actor.venueId} AND id IN (SELECT "stockItemId" FROM pos."ReceivingLine" WHERE "receivingId"=${cleanId}) ORDER BY id FOR UPDATE`;
      const cancelledAt = new Date();
      const pending = originals.filter((row) => !alreadyReversed.has(row.id));
      if (pending.length > 0) {
        await tx.stockMovement.createMany({
          data: pending.map((original) => ({
            venueId: actor.venueId,
            stockItemId: original.stockItemId,
            movementType: StockMovementType.RECEIVING_REVERSAL,
            quantityDeltaBase: original.quantityDeltaBase.negated(),
            baseUnit: original.baseUnit,
            receivingId: cleanId,
            receivingLineId: original.receivingLineId,
            reversalOfMovementId: original.id,
            businessDate: isoDate(cancelledAt),
            effectiveAt: cancelledAt,
            actorId: actor.staffId,
            actorName: actor.username,
            source: 'MANAGER',
            details: {
              waybillNumber: locked.waybillNumber,
              reversalOf: original.id,
              reason: cancellationReason,
            } as Prisma.InputJsonValue,
          })),
        });
      }

      const cancelled = await tx.receiving.update({
        where: { id: cleanId },
        data: {
          status: ReceivingStatus.CANCELLED,
          cancelledAt,
          cancelledById: actor.staffId,
          cancelledByName: actor.username,
          cancellationReason,
        },
        include: {
          payments: true,
          lines: { orderBy: { lineSequence: 'asc' } },
          movements: { orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] },
          _count: { select: { lines: true } },
        },
      });
      await writeInventoryAudit(tx, actor, {
        action: InventoryAuditAction.RECEIVING_CANCELLED,
        entityType: 'RECEIVING',
        entityId: cancelled.id,
        data: {
          ...this.auditContext(cancelled),
          previousStatus: ReceivingStatus.POSTED,
          newStatus: ReceivingStatus.CANCELLED,
          reversalCount: pending.length,
          reason: cancellationReason,
        },
      });
      return { ...this.presentDetail(cancelled), result: 'cancelled' as const };
    });
  }

  // ── Internals ───────────────────────────────────────────────────────────

  /**
   * `SELECT ... FOR UPDATE` on the document.
   *
   * Prisma has no first-class row lock, and without one two concurrent posts
   * could each read DRAFT before either wrote POSTED.
   */
  private async lockReceiving(
    tx: Prisma.TransactionClient,
    venueId: string,
    id: string,
  ) {
    const locked = await tx.$queryRaw<
      {
        id: string;
        status: ReceivingStatus;
        supplierId: string | null;
        documentDate: string;
        businessDate: string;
        receivedAt: Date;
        waybillNumber: string | null;
      }[]
    >`
      SELECT "id", "status", "supplierId", "documentDate", "businessDate", "receivedAt", "waybillNumber"
      FROM "pos"."Receiving"
      WHERE "id" = ${id} AND "venueId" = ${venueId}
      FOR UPDATE
    `;
    const row = locked[0];
    if (!row) throw new NotFoundException('Receiving not found');
    return row;
  }

  private async requireSupplier(
    tx: Prisma.TransactionClient,
    actor: InventoryActor,
    supplierId: string,
  ) {
    const supplier = await tx.supplier.findFirst({
      where: { id: supplierId, venueId: actor.venueId },
      select: { id: true, name: true },
    });
    if (!supplier) throw new NotFoundException('Supplier not found');
    return supplier;
  }

  async currentBusinessDate(tenant: TenantContext): Promise<string | null> {
    const setting = await this.prisma.setting.findUnique({
      where: {
        venueId_key: { venueId: tenant.venueId, key: 'currentBusinessDate' },
      },
    });
    return setting?.value ? isoDateText(setting.value) : null;
  }

  private readHeader(input: ReceivingInput) {
    const receivedAtRaw = input.receivedAt;
    const receivedAt =
      receivedAtRaw == null || receivedAtRaw === ''
        ? new Date()
        : new Date(String(receivedAtRaw));
    if (Number.isNaN(receivedAt.getTime())) {
      throw new BadRequestException('receivedAt is not a valid date');
    }
    const sourceType = input.sourceType ?? 'SUPPLIER';
    if (!['SUPPLIER', 'SELF_PURCHASE'].includes(String(sourceType)))
      throw new BadRequestException('Invalid receiving source');
    if (sourceType === 'SELF_PURCHASE' && input.supplierId)
      throw new BadRequestException('Self purchase cannot have a supplier');
    const sourceLabel = optionalText(input.sourceLabel) ?? 'ჩემით / ბაზრიდან';
    if (sourceLabel.length > 200)
      throw new BadRequestException('Source label is too long');
    return {
      sourceType: String(sourceType),
      sourceLabel,
      supplierId:
        sourceType === 'SELF_PURCHASE'
          ? null
          : requiredText(input.supplierId, 'supplierId'),
      waybillNumber: optionalText(input.waybillNumber),
      invoiceNumber: optionalText(input.invoiceNumber),
      documentDate: isoDateText(input.documentDate ?? isoDate(receivedAt)),
      receivedAt,
      notes: optionalText(input.notes),
    };
  }

  /**
   * Validate the line set against live Stock Items and their packaging.
   *
   * Every line is converted to the item's own base unit here, so the document
   * keeps saying "10 box" while the ledger only ever deals in "240 bottle".
   */
  private async prepareLines(
    tx: Prisma.TransactionClient,
    actor: InventoryActor,
    raw: unknown,
  ): Promise<PreparedLine[]> {
    if (raw == null) return [];
    if (!Array.isArray(raw)) {
      throw new BadRequestException('lines must be an array');
    }
    if (raw.length === 0) return [];
    if (raw.length > 200) {
      throw new BadRequestException('A Receiving may hold up to 200 lines');
    }

    const inputs = raw as ReceivingLineInput[];
    const ids = Array.from(
      new Set(
        inputs.map((line) => requiredText(line.stockItemId, 'stockItemId')),
      ),
    );
    const items = await tx.stockItem.findMany({
      where: { id: { in: ids }, venueId: actor.venueId },
      select: {
        id: true,
        name: true,
        baseUnit: true,
        purchaseUnits: { select: { unit: true, baseUnitMultiplier: true } },
      },
    });
    const byId = new Map(items.map((item) => [item.id, item]));

    return inputs.map((line, index) => {
      const stockItemId = requiredText(line.stockItemId, 'stockItemId');
      const item = byId.get(stockItemId);
      if (!item) {
        throw new NotFoundException(`Stock item ${stockItemId} not found`);
      }
      const enteredQuantity = positiveQuantity(
        line.enteredQuantity,
        'enteredQuantity',
      );
      const enteredUnit = inventoryUnit(line.enteredUnit ?? item.baseUnit);
      let unitPurchaseCost = nonNegativeCost(
        line.unitPurchaseCost ?? '0',
        'unitPurchaseCost',
      );
      const resolved = resolveBaseQuantity({
        enteredQuantity,
        enteredUnit,
        baseUnit: item.baseUnit,
        purchaseUnits: item.purchaseUnits,
      });
      if (resolved.baseQuantity.lessThanOrEqualTo(0)) {
        throw new BadRequestException(
          'A line must deliver a positive base quantity',
        );
      }
      if (line.priceBasis === 'base')
        unitPurchaseCost = unitPurchaseCost
          .times(resolved.baseQuantity)
          .div(enteredQuantity);
      let { lineTotal, effectiveBaseUnitCost } = lineMoney({
        enteredQuantity,
        unitPurchaseCost,
        baseQuantity: resolved.baseQuantity,
      });
      if (line.lineTotal != null) {
        if (line.unitPurchaseCost != null)
          throw new BadRequestException(
            'Supply lineTotal or unitPurchaseCost, not both',
          );
        const text = String(line.lineTotal);
        if (!/^\d+(\.\d{1,2})?$/.test(text))
          throw new BadRequestException('lineTotal must be exact GEL');
        lineTotal = new (Prisma.Decimal.clone({ precision: 60 }))(text);
        unitPurchaseCost = lineTotal.div(enteredQuantity).toDecimalPlaces(4);
        effectiveBaseUnitCost = lineTotal
          .div(resolved.baseQuantity)
          .toDecimalPlaces(6);
      }
      return {
        lineSequence: index,
        stockItemId,
        stockItemNameSnapshot: item.name,
        enteredQuantity,
        enteredUnit,
        baseQuantity: resolved.baseQuantity,
        baseUnit: item.baseUnit,
        unitPurchaseCost,
        lineTotal,
        effectiveBaseUnitCost,
        notes: optionalText(line.notes),
      };
    });
  }

  private loadDetail(tx: Prisma.TransactionClient, id: string) {
    return tx.receiving
      .findUniqueOrThrow({
        where: { id },
        include: {
          payments: true,
          lines: { orderBy: { lineSequence: 'asc' } },
          movements: { orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] },
          _count: { select: { lines: true } },
        },
      })
      .then((row) => this.presentDetail(row));
  }

  private auditContext(row: {
    id: string;
    supplierId: string | null;
    supplierNameSnapshot: string;
    waybillNumber: string | null;
    documentDate: string;
    businessDate: string;
    status: ReceivingStatus;
    documentTotal: Prisma.Decimal;
    lines: unknown[];
  }) {
    return {
      receivingId: row.id,
      supplierId: row.supplierId,
      supplierName: row.supplierNameSnapshot,
      sourceType: 'sourceType' in row ? row.sourceType : 'SUPPLIER',
      waybillNumber: row.waybillNumber,
      documentDate: row.documentDate,
      businessDate: row.businessDate,
      status: row.status,
      lineCount: row.lines.length,
      documentTotal: moneyText(row.documentTotal),
    };
  }

  private presentSummary(row: any) {
    return {
      ...paymentSummary(row),
      payments: (row.payments ?? []).map((p: any) => ({
        ...p,
        amount: p.amount.toFixed(2),
      })),
      id: row.id,
      supplierId: row.supplierId,
      supplierName: row.supplierNameSnapshot,
      sourceType: 'sourceType' in row ? row.sourceType : 'SUPPLIER',
      waybillNumber: row.waybillNumber,
      invoiceNumber: row.invoiceNumber,
      documentDate: row.documentDate,
      businessDate: row.businessDate,
      receivedAt: row.receivedAt,
      status: row.status,
      notes: row.notes,
      documentTotal: moneyText(row.documentTotal),
      lineCount: row._count?.lines ?? row.lines?.length ?? 0,
      createdById: row.createdById,
      createdByName: row.createdByName,
      postedById: row.postedById,
      postedByName: row.postedByName,
      postedAt: row.postedAt,
      cancelledById: row.cancelledById,
      cancelledByName: row.cancelledByName,
      cancelledAt: row.cancelledAt,
      cancellationReason: row.cancellationReason,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private presentLine(line: any) {
    return {
      id: line.id,
      lineSequence: line.lineSequence,
      stockItemId: line.stockItemId,
      stockItemName: line.stockItemNameSnapshot,
      enteredQuantity: quantityText(line.enteredQuantity),
      enteredUnit: line.enteredUnit,
      baseQuantity: quantityText(line.baseQuantity),
      baseUnit: line.baseUnit,
      unitPurchaseCost: unitCostText(line.unitPurchaseCost),
      lineTotal: moneyText(line.lineTotal),
      effectiveBaseUnitCost: baseUnitCostText(line.effectiveBaseUnitCost),
      notes: line.notes,
    };
  }

  private presentDetail(row: any) {
    return {
      ...this.presentSummary(row),
      lines: (row.lines ?? []).map((line: any) => this.presentLine(line)),
      movements: (row.movements ?? []).map((movement: any) =>
        presentMovement(movement),
      ),
    };
  }
}

export function presentMovement(movement: any) {
  return {
    costPerBaseUnit: movement.costPerBaseUnit?.toFixed(12) ?? null,
    inventoryValueDelta: movement.inventoryValueDelta?.toFixed(12) ?? null,
    valuationStatus: movement.valuationStatus,
    id: movement.id,
    stockItemId: movement.stockItemId,
    movementType: movement.movementType,
    quantityDeltaBase: stockQuantityText(movement.quantityDeltaBase),
    baseUnit: movement.baseUnit,
    receivingId: movement.receivingId,
    receivingLineId: movement.receivingLineId,
    reversalOfMovementId: movement.reversalOfMovementId,
    businessDate: movement.businessDate,
    effectiveAt: movement.effectiveAt,
    actorId: movement.actorId,
    actorName: movement.actorName,
    source: movement.source,
    createdAt: movement.createdAt,
    details: movement.details ?? null,
  };
}

export { multiplierText };

function receivingStatus(raw: string): ReceivingStatus {
  const value = raw.trim().toUpperCase();
  if (value in ReceivingStatus) return value as ReceivingStatus;
  throw new BadRequestException(
    `status must be one of: ${Object.keys(ReceivingStatus).join(', ')}`,
  );
}

function isoDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function isoDateText(raw: unknown): string {
  const value = String(raw ?? '').trim();
  const parsed = new Date(value + 'T00:00:00Z');
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value
  ) {
    throw new BadRequestException('documentDate must be YYYY-MM-DD');
  }
  return value;
}

function requiredText(raw: unknown, field: string): string {
  const value = typeof raw === 'string' ? raw.trim() : '';
  if (!value) throw new BadRequestException(`${field} is required`);
  if (value.length > 500) throw new BadRequestException(`${field} is too long`);
  return value;
}

function optionalText(raw: unknown): string | null {
  if (raw == null) return null;
  if (typeof raw !== 'string') throw new BadRequestException('Expected text');
  const value = raw.trim();
  if (value.length > 2000) throw new BadRequestException('Text is too long');
  return value || null;
}
