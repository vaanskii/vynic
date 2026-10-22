import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { EdgeCommandStatus, Prisma } from '@prisma/client';
import { isUUID } from 'class-validator';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';
import { lockOperationalVenue } from '../../edge/operational-authority';
import { PrismaService } from '../../prisma.service';
import type { PosDelivery } from '../../pos/pos-command-dispatcher.service';
import {
  EDGE_COMMAND_CONTRACT_VERSION,
  EdgeCommandTypes,
} from '../../shared/contracts/edge-command';

/** Record one immutable repair intent. The next POS snapshot owns the mirror. */
export async function requestTableRepair(
  db: PrismaService,
  actor: ManagerAuthContext,
  tableNumber: string,
  floor: string,
  requestId: unknown,
): Promise<{ success: boolean; accepted: boolean; posDelivery: PosDelivery }> {
  if (
    typeof requestId !== 'string' ||
    !isUUID(requestId, '4') ||
    typeof tableNumber !== 'string' || typeof floor !== 'string' ||
    !tableNumber.trim() || tableNumber.length > 128 ||
    !floor.trim() || floor.length > 128
  ) throw new BadRequestException('A UUID requestId and table identity are required');
  if (!actor.staffId || !actor.username || actor.role !== 'MANAGER') {
    throw new BadRequestException('An authenticated Manager principal is required');
  }
  return db.$transaction(async (tx) => {
    const venue = await lockOperationalVenue(tx, actor.venueId);
    const idempotencyKey = `TABLE_REPAIR:${actor.staffId}:${requestId}`;
    const prior = await tx.edgeCommand.findUnique({
      where: { venueId_idempotencyKey: { venueId: actor.venueId, idempotencyKey } },
    });
    if (prior) {
      const payload = prior.payload as Record<string, unknown>;
      if (prior.type !== EdgeCommandTypes.TABLE_REPAIR ||
          payload.floor !== floor || payload.tableNumber !== tableNumber ||
          payload.actorStaffId !== actor.staffId) {
        throw new ConflictException('requestId belongs to another repair');
      }
      return result(prior);
    }
    const table = await tx.table.findUnique({
      where: { tableIdentifier: { venueId: actor.venueId, tableNumber, floor } },
    });
    if (!table) throw new NotFoundException('table_not_found');
    if (!isUUID(table.id)) throw new ConflictException('canonical_table_identity_required');
    const primary = venue.activeOperationalDeviceId
      ? await tx.device.findFirst({
          where: { id: venue.activeOperationalDeviceId, venueId: actor.venueId, status: 'ACTIVE' },
        })
      : null;
    if (!primary) return {
      success: false,
      accepted: false,
      posDelivery: { transport: 'edge', status: 'UNAVAILABLE', code: 'primary_pos_required' },
    };
    const created = await tx.edgeCommand.create({
      data: {
        venueId: actor.venueId,
        deviceId: primary.id,
        type: EdgeCommandTypes.TABLE_REPAIR,
        contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
        idempotencyKey,
        payload: {
          tableId: table.id,
          mirrorUpdatedAt: table.updatedAt.toISOString(),
          tableNumber,
          floor,
          expectedIsReserved: table.isReserved,
          expectedActiveOrderId: table.activeOrderId,
          actorStaffId: actor.staffId,
          actorUsername: actor.username,
        } satisfies Prisma.InputJsonObject,
      },
    });
    return result(created);
  });
}

function result(row: {
  id: string; status: EdgeCommandStatus;
  resultCode: string | null; resultDetail: string | null;
}) {
  const status = row.status === EdgeCommandStatus.PENDING ? 'QUEUED' : row.status;
  return {
    success: status === 'SUCCEEDED',
    accepted: status !== 'FAILED',
    posDelivery: {
      transport: 'edge', status, commandId: row.id,
      code: row.resultCode, detail: row.resultDetail,
    } as PosDelivery,
  };
}
