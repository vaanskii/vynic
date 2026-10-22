import { BadRequestException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { isUUID } from 'class-validator';

export interface OrderEditProjection {
  version: 1;
  effectiveServiceFeePercent: number;
  orderUuid: string;
  fingerprint: string;
  image: string;
  sourceDeviceId?: string | null;
}
const invalid = () => {
  throw new BadRequestException('invalid_order_edit_projection');
};
export function readEditProjection(
  raw: unknown,
  posOrderId: number,
): { projection: OrderEditProjection; order: any } {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return invalid();
  const v = raw as OrderEditProjection;
  if (
    !Number.isFinite(v.effectiveServiceFeePercent) ||
    v.effectiveServiceFeePercent < 0 ||
    v.effectiveServiceFeePercent > 100 ||
    v.version !== 1 ||
    !isUUID(v.orderUuid) ||
    typeof v.image !== 'string' ||
    v.image.length > 1000000 ||
    typeof v.fingerprint !== 'string' ||
    createHash('sha256').update(v.image).digest('hex') !== v.fingerprint
  )
    return invalid();
  let order: any;
  try {
    order = JSON.parse(v.image);
  } catch {
    return invalid();
  }
  if (
    !order ||
    order.orderId !== posOrderId ||
    order.orderUuid !== v.orderUuid ||
    typeof order.status !== 'string' ||
    !Number.isFinite(order.totalAmount) ||
    typeof order.floor !== 'string' ||
    !Array.isArray(order.tableNumbers) ||
    !order.tableNumbers.every((t: unknown) => typeof t === 'string') ||
    typeof order.includeServiceFee !== 'boolean' ||
    !Array.isArray(order.items) ||
    typeof order.createdAt !== 'string' ||
    !Number.isFinite(Date.parse(order.createdAt))
  )
    return invalid();
  readEditItems(order.items);
  return {
    projection: {
      version: 1,
      effectiveServiceFeePercent: v.effectiveServiceFeePercent,
      orderUuid: v.orderUuid,
      fingerprint: v.fingerprint,
      image: v.image,
    },
    order,
  };
}
export function readEditItems(raw: unknown): any[] {
  if (!Array.isArray(raw) || raw.length > 1000)
    throw new BadRequestException('items_array_required');
  const lines = new Set<string>();
  return raw.map((v: any) => {
    if (
      !v ||
      typeof v !== 'object' ||
      typeof v.itemKey !== 'string' ||
      !v.itemKey.trim() ||
      v.itemKey.length > 512 ||
      typeof v.itemName !== 'string' ||
      !v.itemName.trim() ||
      v.itemName.length > 512 ||
      typeof v.lineUuid !== 'string' ||
      !v.lineUuid.trim() ||
      v.lineUuid.length > 512 ||
      lines.has(v.lineUuid) ||
      !Number.isInteger(v.quantity) ||
      v.quantity <= 0 ||
      v.quantity > 100000 ||
      !Number.isFinite(v.unitPrice) ||
      v.unitPrice < 0 ||
      v.unitPrice > 10000000 ||
      Math.abs(v.unitPrice * 100 - Math.round(v.unitPrice * 100)) > 0.000001 ||
      !Number.isFinite(v.total) ||
      v.total < 0 ||
      v.total > 1000000000 ||
      Math.abs(v.total * 100 - Math.round(v.total * 100)) > 0.000001 ||
      (v.comment != null &&
        (typeof v.comment !== 'string' || v.comment.length > 4096)) ||
      [v.menuItemId, v.variantId].some(
        (id) =>
          id != null &&
          (typeof id !== 'string' || !id.trim() || id.length > 512),
      )
    )
      throw new BadRequestException('invalid_order_edit_items');
    lines.add(v.lineUuid);
    return {
      itemKey: v.itemKey,
      itemName: v.itemName,
      lineUuid: v.lineUuid,
      quantity: v.quantity,
      unitPrice: v.unitPrice,
      total: v.total,
      comment: v.comment ?? null,
      ...(v.menuItemId != null ? { menuItemId: v.menuItemId } : {}),
      ...(v.variantId != null ? { variantId: v.variantId } : {}),
    };
  });
}
export function sameJson(a: any, b: any): boolean {
  function canonical(v: any): string {
    if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
    if (v && typeof v === 'object')
      return (
        '{' +
        Object.keys(v)
          .sort()
          .map((k) => JSON.stringify(k) + ':' + canonical(v[k]))
          .join(',') +
        '}'
      );
    return JSON.stringify(v);
  }
  return canonical(a) === canonical(b);
}

export function validateLineTotals(items: any[], before: any[]) {
  for (const item of items) {
    const original = before.find(
      (i) => i.lineUuid === item.lineUuid && i.itemKey === item.itemKey,
    );
    const expected =
      original &&
      original.quantity === item.quantity &&
      original.unitPrice === item.unitPrice
        ? original.total
        : Math.round(item.quantity * item.unitPrice * 100) / 100;
    if (Math.abs(item.total - expected) > 0.000001)
      throw new BadRequestException('invalid_line_total');
  }
}
