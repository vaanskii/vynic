import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  PosCommandDispatcher,
  type PosDelivery,
} from '../../pos/pos-command-dispatcher.service';
import { EdgeCommandTypes } from '../../shared/contracts/edge-command';
import { allocatePosReservationId } from '../../pos/pos-reservation-id';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { suppressPosEchoForReservation } from '../../pos/sync-echo-guard';
import { MobileMutationSupport } from './mobile-mutation-support.service';
import type { TenantContext } from '../../tenancy/tenant-context';

export interface ReservationResponseItem {
  id: string;
  customerName: string;
  customerPhone: string;
  tableNumbers: number[];
  reservationDate: string;
  reservationTime: string;
  numberOfGuests: number;
  notes?: string;
  status: string;
  createdBy?: string;
}

/**
 * Reservation endpoints for the mobile manager app (`/mobile/reservations*`).
 * The POS (via posCallback) is the source of truth — these read/mutate POS
 * reservations and broadcast the change to other connected clients.
 *
 * Extracted verbatim from MobileController; behavior unchanged. The controller
 * keeps the route decorators and passes the monitoring socket id through.
 */
@Injectable()
export class MobileReservationsService {
  constructor(
    private readonly posReservations: PosReservationMirrorService,
    private readonly posCommands: PosCommandDispatcher,
    private readonly gateway: MonitoringGateway,
    private readonly mutationSupport: MobileMutationSupport,
  ) {}

  /**
   * The Venue's reservations, read from the Cloud mirror.
   *
   * This used to be an HTTP request from here into the restaurant's LAN, which
   * meant a manager could not see a reservation list unless the POS PC was
   * awake and reachable — and which a hosted Vynic could not do at all. The POS
   * still owns these; it pushes them with every snapshot and Cloud reads its own
   * copy. See `PosReservationMirrorService` for what that costs in freshness.
   */
  async getReservations(
    tenant: TenantContext,
    date?: string,
  ): Promise<ReservationResponseItem[]> {
    const rows = await this.posReservations.listAll(tenant);
    const normalized = rows
      .filter((r) => r && typeof r === 'object')
      // Exclude walk-ins and takeaways: those are order-linked records the POS
      // creates for dine-in/takeaway orders, not real bookings. Mirrors the
      // Windows POS getAdminPanelReservations() filter.
      .filter((r: any) => {
        if (r.isTakeAway === true) return false;
        if (r.linkedOrderId !== undefined && r.linkedOrderId !== null) {
          return false;
        }
        const notes = String(r.notes ?? '');
        if (notes.startsWith('Order #')) return false;
        return true;
      })
      .map((r: any) => ({
        id: String(r.id ?? ''),
        customerName: String(r.customerName ?? ''),
        customerPhone: String(r.customerPhone ?? ''),
        tableNumbers: Array.isArray(r.tableNumbers)
          ? r.tableNumbers
              .map((x: any) => Number(x))
              .filter((x: number) => Number.isFinite(x))
          : [],
        reservationDate: String(r.reservationDate ?? ''),
        reservationTime: String(r.reservationTime ?? ''),
        numberOfGuests: Number(r.numberOfGuests ?? 0),
        notes: r.notes ? String(r.notes) : undefined,
        status: String(r.status ?? 'pending'),
        createdBy: r.createdBy ? String(r.createdBy) : undefined,
      }))
      .filter((r) => r.id.length > 0);

    if (date && date.trim().length > 0) {
      return normalized.filter((r) => r.reservationDate.startsWith(date));
    }
    return normalized;
  }

  async createReservation(
    tenant: TenantContext,
    monitoringSocketId: string | undefined,
    payload: {
      customerName?: string;
      customerPhone?: string;
      tableNumbers?: number[];
      reservationDate?: string;
      reservationTime?: string;
      numberOfGuests?: number;
      notes?: string;
      createdBy?: string;
      status?: string;
      preOrderItems?: Array<Record<string, unknown>>;
    },
  ): Promise<ReservationResponseItem & { posDelivery: PosDelivery }> {
    const customerName = (payload.customerName ?? '').trim();
    const customerPhone = (payload.customerPhone ?? '').trim();
    const reservationDate = (payload.reservationDate ?? '').trim();
    const reservationTime = (payload.reservationTime ?? '').trim();
    const tableNumbers = Array.isArray(payload.tableNumbers)
      ? payload.tableNumbers
          .map((n) => Number(n))
          .filter((n) => Number.isFinite(n))
      : [];
    const numberOfGuests = Number(payload.numberOfGuests ?? 0);
    if (
      customerName.length === 0 ||
      reservationDate.length === 0 ||
      reservationTime.length === 0
    ) {
      throw new BadRequestException(
        'customerName, reservationDate, reservationTime are required',
      );
    }
    if (!Number.isFinite(numberOfGuests) || numberOfGuests <= 0) {
      throw new BadRequestException('numberOfGuests must be greater than zero');
    }

    const preOrderItems = Array.isArray(payload.preOrderItems)
      ? payload.preOrderItems
      : [];

    const reservationPayload = {
      customerName,
      customerPhone,
      tableNumbers,
      reservationDate,
      reservationTime,
      numberOfGuests,
      notes: (payload.notes ?? '').toString(),
      createdBy: (payload.createdBy ?? 'mobile_manager').toString(),
      status: (payload.status ?? 'confirmed').toString(),
      isTakeAway: false,
      preOrderItems,
    };

    // The reservation's identity is allocated here rather than by the POS.
    // It used to come back from a synchronous LAN call, which meant the id did
    // not exist until the restaurant answered — and meant a redelivered create
    // produced a second booking. Cloud naming it makes the command convergent
    // and lets this request answer immediately.
    const reservationId = allocatePosReservationId();
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.RESERVATION_CREATE,
      payload: { ...reservationPayload, reservationId },
    });

    // Suppress the POS round-trip echo so the device that created this
    // reservation isn't re-notified when the POS syncs it back.
    suppressPosEchoForReservation(reservationId);
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: 'created',
        customerName,
        tableNumbers,
        reservationTime,
        reservationDate,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    return {
      id: reservationId,
      customerName,
      customerPhone,
      tableNumbers,
      reservationDate,
      reservationTime,
      numberOfGuests,
      notes: reservationPayload.notes || undefined,
      status: reservationPayload.status,
      createdBy: reservationPayload.createdBy,
      posDelivery,
    };
  }

  async updateReservationStatus(
    tenant: TenantContext,
    id: string,
    monitoringSocketId: string | undefined,
    payload: { status?: string },
  ) {
    const status = (payload.status ?? '').trim().toLowerCase();
    if (status.length === 0) {
      throw new BadRequestException('status is required');
    }
    if (
      status === 'completed' ||
      status === 'in-progress' ||
      status === 'inprogress'
    ) {
      throw new BadRequestException(
        'Moving reservation to table is not allowed from mobile',
      );
    }
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.RESERVATION_STATUS_UPDATE,
      payload: { reservationId: id, status },
    });
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: status === 'cancelled' ? 'cancelled' : 'updated',
        reservationId: id,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true, posDelivery };
  }

  async deleteReservation(
    tenant: TenantContext,
    id: string,
    monitoringSocketId?: string,
  ) {
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.RESERVATION_DELETE,
      payload: { reservationId: id },
    });
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: 'cancelled',
        reservationId: id,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true, posDelivery };
  }

  /**
   * Relay a reservation-check print request to the Windows POS (the only print
   * host) via the direct POS callback path. No realtime broadcast: printing is
   * not a data mutation, so nothing changes for other clients. POS-side
   * failures (unreachable POS, reservation missing in Hive) are surfaced as
   * clean HTTP errors instead of a raw 500.
   */
  async printReservationCheck(tenant: TenantContext, id: string) {
    const reservationId = (id ?? '').trim();
    if (reservationId.length === 0) {
      throw new BadRequestException('reservation id is required');
    }
    const posDelivery = await this.posCommands.dispatchAndAwait(tenant, {
      type: EdgeCommandTypes.RESERVATION_CHECK_PRINT,
      payload: { reservationId },
    });

    if (posDelivery.status === 'FAILED') {
      if (posDelivery.code === 'reservation_not_found') {
        throw new NotFoundException('Reservation not found on POS');
      }
      throw new ServiceUnavailableException(
        `The POS could not print this check (${posDelivery.code ?? 'unknown'})`,
      );
    }
    if (posDelivery.status === 'UNAVAILABLE') {
      throw new ServiceUnavailableException(
        'Could not reach the POS to print this check — is it running?',
      );
    }
    return { success: true, posDelivery };
  }
}
