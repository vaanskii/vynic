import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { isUUID } from 'class-validator';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';
import { lockOperationalVenue } from '../../edge/operational-authority';
import { PrismaService } from '../../prisma.service';
import { EDGE_COMMAND_CONTRACT_VERSION } from '../../shared/contracts/edge-command';
import {
  readEditItems,
  readEditProjection,
  sameJson,
  validateLineTotals,
} from '../../shared/contracts/order-edit-projection';

/** Cloud owns the immutable intent; only the selected POS owns its effects. */
export async function requestOrderEdit(
  db: PrismaService,
  actor: ManagerAuthContext,
  id: string,
  raw: any,
) {
  if (
    !/^[1-9]\d*$/.test(id) ||
    !Number.isSafeInteger(Number(id)) ||
    !raw ||
    !isUUID(raw.requestId, '4') ||
    typeof raw.expectedFingerprint !== 'string' ||
    !/^[a-f0-9]{64}$/.test(raw.expectedFingerprint) ||
    typeof raw.includeServiceFee !== 'boolean' ||
    (raw.customServiceFeePercentage !== null &&
      (!Number.isFinite(raw.customServiceFeePercentage) ||
        raw.customServiceFeePercentage < 0 ||
        raw.customServiceFeePercentage > 100))
  )
    throw new BadRequestException('invalid_order_edit_request');
  if (!actor.staffId || !actor.username || actor.role !== 'MANAGER')
    throw new BadRequestException('manager_required');
  const request = {
    posOrderId: Number(id),
    expectedFingerprint: raw.expectedFingerprint,
    items: readEditItems(raw.items),
    includeServiceFee: raw.includeServiceFee,
    customServiceFeePercentage: raw.customServiceFeePercentage,
  };
  return db.$transaction(async (tx) => {
    const venue = await lockOperationalVenue(tx, actor.venueId);
    const idempotencyKey = `ORDER_EDIT:${actor.staffId}:${raw.requestId}`;
    const prior = await tx.edgeCommand.findUnique({
      where: {
        venueId_idempotencyKey: { venueId: actor.venueId, idempotencyKey },
      },
    });
    if (prior) {
      const p = prior.payload as any;
      if (
        prior.type !== 'ORDER_EDIT' ||
        !sameJson(p.request, request) ||
        p.actorStaffId !== actor.staffId
      )
        throw new ConflictException('request_conflict');
      return result(prior);
    }
    const row = await tx.order.findUnique({
      where: {
        venueId_posOrderId: { venueId: actor.venueId, posOrderId: Number(id) },
      },
    });
    if (!row) throw new NotFoundException('order_not_found');
    if (['paid', 'closed', 'cancelled'].includes(row.status.toLowerCase()))
      throw new ConflictException('closed_order');
    if (!row.managerEditProjection)
      return unavailable('pos_edit_baseline_required');
    const { projection, order } = readEditProjection(
      row.managerEditProjection,
      Number(id),
    );
    if (projection.fingerprint !== request.expectedFingerprint)
      throw new ConflictException('stale_order');
    validateLineTotals(request.items, order.items);
    if (['paid', 'closed', 'cancelled'].includes(order.status.toLowerCase()))
      throw new ConflictException('closed_order');
    const primary =
      venue.activeOperationalDeviceId &&
      (await tx.device.findFirst({
        where: {
          id: venue.activeOperationalDeviceId,
          venueId: actor.venueId,
          status: 'ACTIVE',
        },
      }));
    if (!primary) return unavailable('primary_pos_required');
    if ((row.managerEditProjection as any).sourceDeviceId !== primary.id)
      return unavailable('primary_edit_baseline_required');
    const mirrorTables = await tx.table.findMany({
      where: { venueId: actor.venueId, activeOrderId: Number(id) },
      select: { id: true, updatedAt: true },
    });
    const created = await tx.edgeCommand.create({
      data: {
        venueId: actor.venueId,
        deviceId: primary.id,
        type: 'ORDER_EDIT',
        contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
        idempotencyKey,
        payload: {
          request,
          baseline: { ...projection },
          businessDate: row.businessDate,
          mirrorUpdatedAt: row.updatedAt.toISOString(),
          mirrorTables: mirrorTables.map((t) => ({
            id: t.id,
            updatedAt: t.updatedAt.toISOString(),
          })),
          actorStaffId: actor.staffId,
          actorUsername: actor.username,
        } as Prisma.InputJsonObject,
      },
    });
    return result(created);
  });
}
function unavailable(code: string) {
  return {
    success: false,
    accepted: false,
    posDelivery: { transport: 'edge', status: 'UNAVAILABLE', code },
  };
}
function result(row: any) {
  const status = row.status === 'PENDING' ? 'QUEUED' : row.status;
  return {
    success: status === 'SUCCEEDED',
    accepted: status !== 'FAILED',
    editProjection: row.resultProjection ?? undefined,
    posDelivery: {
      transport: 'edge',
      status,
      commandId: row.id,
      code: row.resultCode,
      detail: row.resultDetail,
    },
  };
}
