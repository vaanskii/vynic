import { BadRequestException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import {
  readEditItems,
  readEditProjection,
  sameJson,
} from '../shared/contracts/order-edit-projection';

/** Runs inside the Venue-locked ACK transaction, including all mirror effects. */
export async function applyOrderEditResult(
  db: PrismaService,
  venueId: string,
  payload: any,
  raw: unknown,
) {
  const { projection, order } = readEditProjection(
    raw,
    payload.request.posOrderId,
  );
  const before = readEditProjection(
    payload.baseline,
    payload.request.posOrderId,
  ).order;
  const mutable = new Set([
    'items',
    'includeServiceFee',
    'customServiceFeePercentage',
    'totalAmount',
    'updatedAt',
    'packagePrice',
  ]);
  const fixed = (v: any) =>
    Object.fromEntries(Object.entries(v).filter(([k]) => !mutable.has(k)));
  if (
    projection.orderUuid !== payload.baseline.orderUuid ||
    !sameJson(fixed(before), fixed(order)) ||
    !sameJson(readEditItems(order.items), payload.request.items) ||
    order.includeServiceFee !== payload.request.includeServiceFee ||
    order.customServiceFeePercentage !==
      payload.request.customServiceFeePercentage ||
    typeof order.updatedAt !== 'string' ||
    !Number.isFinite(Date.parse(order.updatedAt))
  )
    throw new BadRequestException('invalid_order_edit_result');
  const current = await db.order.findUnique({
    where: {
      venueId_posOrderId: { venueId, posOrderId: payload.request.posOrderId },
    },
  });
  // An absent, closed, replaced or subsequently changed order wins over a delayed ACK.
  if (
    current &&
    !['paid', 'closed', 'cancelled'].includes(current.status.toLowerCase()) &&
    (current.managerEditProjection as any)?.fingerprint ===
      payload.baseline.fingerprint &&
    current.updatedAt.toISOString() === payload.mirrorUpdatedAt
  ) {
    await db.order.update({
      where: { id: current.id },
      data: {
        totalAmount: order.totalAmount,
        includeServiceFee: order.includeServiceFee,
        serviceFeePercent: projection.effectiveServiceFeePercent,
        managerEditProjection: {
          ...projection,
          sourceDeviceId: (current.managerEditProjection as any).sourceDeviceId,
        },
        items: {
          deleteMany: {},
          create: order.items.map((i: any) => ({
            name: i.itemName,
            quantity: i.quantity,
            price: i.unitPrice,
            menuItemId: i.menuItemId ?? null,
            variantId: i.variantId ?? null,
          })),
        },
      },
    });
    for (const t of payload.mirrorTables ?? [])
      await db.table.updateMany({
        where: {
          id: t.id,
          venueId,
          activeOrderId: payload.request.posOrderId,
          updatedAt: new Date(t.updatedAt),
        },
        data: { currentBill: order.totalAmount },
      });
  }
  return projection;
}
