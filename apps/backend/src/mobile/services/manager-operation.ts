import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, type EdgeCommand } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { isUUID } from 'class-validator';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';
import { lockOperationalVenue } from '../../edge/operational-authority';
import { PrismaService } from '../../prisma.service';
import { EDGE_COMMAND_CONTRACT_VERSION } from '../../shared/contracts/edge-command';
import {
  readEditProjection,
  sameJson,
} from '../../shared/contracts/order-edit-projection';

const types: Record<string, string> = {
  order_cancel: 'ORDER_STATUS_UPDATE',
  takeaway_cancel: 'ORDER_CANCEL',
  takeaway_create: 'TAKEAWAY_ORDER_UPSERT',
  dine_in_create: 'DINE_IN_ORDER_UPSERT',
  reservation_create: 'RESERVATION_CREATE',
  reservation_status: 'RESERVATION_STATUS_UPDATE',
  reservation_delete: 'RESERVATION_DELETE',
};
const fail = (): never => {
  throw new BadRequestException('invalid_manager_operation');
};
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return fail();
  return value as Record<string, unknown>;
}
type OperationLine = {
  itemName: string;
  unitPrice: number;
  quantity: number;
  comment: string | null;
  menuItemId?: string;
  variantId?: string;
};
type OperationBody = Prisma.InputJsonObject & {
  posOrderId?: number;
  reservationId?: string;
  status?: string;
  floor?: string;
  tableNumbers?: string[] | number[];
  items?: OperationLine[];
  preOrderItems?: OperationLine[];
};
function text(v: unknown, max = 200, empty = false): string {
  if (typeof v !== 'string' || v.length > max || (!empty && !v.trim()))
    return fail();
  return v.trim();
}
function integer(v: unknown, min = 1, max = 2147483647): number {
  if (typeof v !== 'number' || !Number.isSafeInteger(v) || v < min || v > max)
    return fail();
  return v;
}
function lines(raw: unknown, allowEmpty = false): OperationLine[] {
  if (!Array.isArray(raw) || raw.length > 500 || (!allowEmpty && !raw.length))
    return fail();
  const values: unknown[] = raw;
  return values.map((value) => {
    const i = record(value);
    const price = i.unitPrice;
    if (
      typeof price !== 'number' ||
      !Number.isFinite(price) ||
      price < 0 ||
      price > 1000000 ||
      Math.abs(price * 100 - Math.round(price * 100)) > 1e-7
    )
      return fail();
    return {
      itemName: text(i.itemName),
      unitPrice: price,
      quantity: integer(i.quantity, 1, 10000),
      comment: i.comment == null ? null : text(i.comment, 1000, true),
      ...(i.menuItemId != null ? { menuItemId: text(i.menuItemId) } : {}),
      ...(i.variantId != null ? { variantId: text(i.variantId) } : {}),
    };
  });
}
function normalized(kind: string, raw: unknown): OperationBody {
  if (!Object.hasOwn(types, kind)) return fail();
  const b = record(raw);
  switch (kind) {
    case 'order_cancel':
    case 'takeaway_cancel':
      return { posOrderId: integer(b.posOrderId) };
    case 'reservation_delete':
      return { reservationId: text(b.reservationId, 80) };
    case 'reservation_status': {
      if (
        typeof b.status !== 'string' ||
        !['pending', 'confirmed', 'cancelled'].includes(b.status)
      )
        return fail();
      return { reservationId: text(b.reservationId, 80), status: b.status };
    }
    case 'reservation_create': {
      if (
        !Array.isArray(b.tableNumbers) ||
        b.tableNumbers.length < 1 ||
        b.tableNumbers.length > 100
      )
        return fail();
      const tables = (b.tableNumbers as unknown[]).map((v) =>
        integer(v, 1, 100000),
      );
      if (new Set(tables).size !== tables.length) return fail();
      const date = text(b.reservationDate, 10),
        time = text(b.reservationTime, 5);
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        !Number.isFinite(Date.parse(date + 'T00:00:00Z')) ||
        new Date(date + 'T00:00:00Z').toISOString().slice(0, 10) !== date ||
        !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)
      )
        return fail();
      return {
        customerName: text(b.customerName),
        customerPhone: text(b.customerPhone, 80, true),
        tableNumbers: tables,
        reservationDate: date,
        reservationTime: time,
        numberOfGuests: integer(b.numberOfGuests, 1, 10000),
        notes: text(b.notes ?? '', 2000, true),
        preOrderItems: lines(b.preOrderItems ?? [], true),
      };
    }
    case 'takeaway_create':
      return {
        customerName: text(b.customerName),
        pickupTime: text(b.pickupTime, 80),
        items: lines(b.items),
      };
    case 'dine_in_create': {
      if (
        !Array.isArray(b.tableNumbers) ||
        !b.tableNumbers.length ||
        b.tableNumbers.length > 100
      )
        return fail();
      const tables = (b.tableNumbers as unknown[]).map((v) =>
        text(String(v), 80),
      );
      if (new Set(tables).size !== tables.length) return fail();
      return {
        tableNumbers: tables,
        floor: text(b.floor, 80),
        guestCount: integer(b.guestCount ?? 1, 0, 10000),
        items: lines(b.items),
      };
    }
    default:
      return fail();
  }
}
function identity(actor: ManagerAuthContext, requestId: string) {
  return {
    venueId_idempotencyKey: {
      venueId: actor.venueId,
      idempotencyKey: `MANAGER_OPERATION:${actor.staffId}:${requestId}`,
    },
  };
}
function response(row: EdgeCommand) {
  const m = record(record(row.payload).managerOperation);
  const status = row.status === 'PENDING' ? 'QUEUED' : row.status;
  return {
    ...record(m.reply),
    requestId: text(m.requestId, 36),
    kind: text(m.kind, 80),
    success: status === 'SUCCEEDED',
    accepted: true,
    posDelivery: {
      transport: 'edge',
      status,
      commandId: row.id,
      code: row.resultCode,
      detail: row.resultDetail,
    },
  };
}
export async function managerOperationStatus(
  db: PrismaService,
  actor: ManagerAuthContext,
  requestId: string,
) {
  if (!isUUID(requestId, '4')) return fail();
  const row = await db.edgeCommand.findUnique({
    where: identity(actor, requestId),
  });
  if (
    !row ||
    !record(row.payload).managerOperation ||
    record(row.payload).actorStaffId !== actor.staffId
  )
    throw new NotFoundException('operation_not_found');
  return response(row);
}
/** One durable immutable identity, no Cloud operational effects at admission. */
export async function requestManagerOperation(
  db: PrismaService,
  actor: ManagerAuthContext,
  kind: string,
  input: unknown,
) {
  const raw = record(input);
  const requestId = text(raw.requestId, 36);
  if (!actor.staffId || actor.role !== 'MANAGER' || !isUUID(requestId, '4'))
    return fail();
  const body = normalized(kind, raw.body);
  return db.$transaction(async (tx) => {
    const venue = await lockOperationalVenue(tx, actor.venueId);
    const prior = await tx.edgeCommand.findUnique({
      where: identity(actor, requestId),
    });
    if (prior) {
      const m = record(record(prior.payload).managerOperation);
      if (
        !m ||
        m.kind !== kind ||
        !sameJson(m.body, body) ||
        record(prior.payload).actorStaffId !== actor.staffId
      )
        throw new ConflictException('request_conflict');
      return response(prior);
    }
    const primary =
      venue.activeOperationalDeviceId &&
      (await tx.device.findFirst({
        where: {
          id: venue.activeOperationalDeviceId,
          venueId: actor.venueId,
          status: 'ACTIVE',
        },
      }));
    if (!primary)
      return {
        requestId: requestId,
        kind,
        success: false,
        accepted: false,
        posDelivery: {
          transport: 'edge',
          status: 'UNAVAILABLE',
          code: 'primary_pos_required',
        },
      };
    const payload: Record<string, Prisma.InputJsonValue | undefined> = {
      operationType: types[kind],
      ...body,
      actorStaffId: actor.staffId,
      actorUsername: actor.username,
      updatedBy: actor.username,
      createdBy: actor.username,
      waiterName: actor.username,
      source: 'MANAGER',
    };
    let reply: Prisma.InputJsonObject = {};
    if (kind.endsWith('_cancel')) {
      const row = await tx.order.findUnique({
        where: {
          venueId_posOrderId: {
            venueId: actor.venueId,
            posOrderId: body.posOrderId!,
          },
        },
      });
      if (!row) throw new NotFoundException('order_not_found');
      if (['paid', 'closed'].includes(row.status.toLowerCase()))
        throw new ConflictException('closed_order');
      if (
        !row.managerEditProjection ||
        record(row.managerEditProjection).sourceDeviceId !== primary.id
      )
        return {
          requestId: requestId,
          kind,
          success: false,
          accepted: false,
          posDelivery: {
            transport: 'edge',
            status: 'UNAVAILABLE',
            code: 'primary_order_baseline_required',
          },
        };
      const decoded = readEditProjection(
        row.managerEditProjection,
        row.posOrderId,
      );
      if (
        text(record(decoded.order).createdAt, 80).slice(0, 10) !==
        row.businessDate
      )
        throw new ConflictException('stale_order_identity');
      payload.orderUuid = decoded.projection.orderUuid;
      payload.status = 'cancelled';
      payload.businessDate = row.businessDate;
      reply = { posOrderId: body.posOrderId };
    } else if (kind.endsWith('_create') && kind !== 'reservation_create') {
      const setting = await tx.setting.findUnique({
        where: {
          venueId_key: { venueId: actor.venueId, key: 'currentBusinessDate' },
        },
      });
      if (!setting || !/^\d{4}-\d{2}-\d{2}$/.test(setting.value))
        return {
          requestId: requestId,
          kind,
          success: false,
          accepted: false,
          posDelivery: {
            transport: 'edge',
            status: 'UNAVAILABLE',
            code: 'business_date_required',
          },
        };
      if (kind === 'dine_in_create') {
        const tables = await tx.table.findMany({
          where: {
            venueId: actor.venueId,
            floor: body.floor,
            tableNumber: { in: body.tableNumbers as string[] },
          },
        });
        if (tables.length !== body.tableNumbers!.length)
          throw new NotFoundException('table_not_found');
      }
      const counterKey = 'mobileOrderIdCounter';
      const counter = await tx.setting.findUnique({
        where: { venueId_key: { venueId: actor.venueId, key: counterKey } },
      });
      const maximum = await tx.order.aggregate({
        where: { venueId: actor.venueId },
        _max: { posOrderId: true },
      });
      const id = Math.max(
        Number(counter?.value ?? 0) + 1,
        (maximum._max.posOrderId ?? 0) + 1,
        90001,
      );
      integer(id);
      await tx.setting.upsert({
        where: { venueId_key: { venueId: actor.venueId, key: counterKey } },
        update: { value: String(id) },
        create: { venueId: actor.venueId, key: counterKey, value: String(id) },
      });
      payload.posOrderId = id;
      payload.businessDate = setting.value;
      payload.items = body.items!.map((i) => ({
        ...i,
        lineUuid: randomUUID(),
      }));
      payload.totalAmount =
        Math.round(
          body.items!.reduce((s, i) => s + i.quantity * i.unitPrice, 0) * 100,
        ) / 100;
      reply = {
        ...body,
        posOrderId: id,
        waiterName: actor.username,
        status: 'pending',
        businessDate: setting.value,
        totalAmount: payload.totalAmount,
      };
    } else if (kind === 'reservation_create') {
      // Retain the existing numeric identity shape; a Venue-locked counter and
      // collision check also cover multiple requests in the same millisecond.
      const key = 'mobileReservationIdCounter';
      const counter = await tx.setting.findUnique({
        where: { venueId_key: { venueId: actor.venueId, key } },
      });
      let id = Math.max(Number(counter?.value ?? 0) + 1, Date.now() * 1000);
      const reserved = await tx.edgeCommand.findMany({
        where: {
          venueId: actor.venueId,
          type: { in: ['RESERVATION_CREATE', 'MANAGER_OPERATION'] },
        },
        select: { payload: true },
      });
      const used = new Set(
        reserved.map((r) => String(record(r.payload).reservationId)),
      );
      while (
        used.has(String(id)) ||
        (await tx.posReservation.findFirst({
          where: { venueId: actor.venueId, posReservationId: String(id) },
        }))
      )
        id++;
      if (!Number.isSafeInteger(id)) return fail();
      await tx.setting.upsert({
        where: { venueId_key: { venueId: actor.venueId, key } },
        update: { value: String(id) },
        create: { venueId: actor.venueId, key, value: String(id) },
      });
      payload.reservationId = String(id);
      payload.status = 'confirmed';
      payload.isTakeAway = false;
      payload.preOrderItems = body.preOrderItems!.map((i) => ({
        ...i,
        lineUuid: randomUUID(),
        total: i.quantity * i.unitPrice,
      }));
      reply = {
        ...body,
        id: String(id),
        createdBy: actor.username,
        status: 'pending',
      };
    } else {
      const row = await tx.posReservation.findFirst({
        where: { venueId: actor.venueId, posReservationId: body.reservationId },
      });
      if (!row) throw new NotFoundException('reservation_not_found');
      reply = { id: body.reservationId };
    }
    payload.managerOperation = { requestId: requestId, kind, body, reply };
    const row = await tx.edgeCommand.create({
      data: {
        venueId: actor.venueId,
        deviceId: primary.id,
        type: 'MANAGER_OPERATION',
        contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
        idempotencyKey: identity(actor, requestId).venueId_idempotencyKey
          .idempotencyKey,
        payload: payload,
      },
    });
    return response(row);
  });
}
