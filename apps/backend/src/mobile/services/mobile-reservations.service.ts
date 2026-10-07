import { PrismaService } from '../../prisma.service';
import { requestManagerOperation } from './manager-operation';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import { EdgeCommandTypes } from '../../shared/contracts/edge-command';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
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
    private readonly prisma: PrismaService,
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

  createReservation(
    actor: ManagerAuthContext,
    _socket: string | undefined,
    body: unknown,
  ) {
    return requestManagerOperation(this.prisma, actor, 'reservation_create', {
      requestId: (body as Record<string, unknown> | null)?.requestId,
      body,
    });
  }
  updateReservationStatus(
    actor: ManagerAuthContext,
    id: string,
    _socket: string | undefined,
    body: unknown,
  ) {
    return requestManagerOperation(this.prisma, actor, 'reservation_status', {
      requestId: (body as Record<string, unknown> | null)?.requestId,
      body: {
        reservationId: id,
        status: (body as Record<string, unknown> | null)?.status,
      },
    });
  }
  deleteReservation(
    actor: ManagerAuthContext,
    id: string,
    _socket?: string,
    body?: unknown,
  ) {
    return requestManagerOperation(this.prisma, actor, 'reservation_delete', {
      requestId: (body as Record<string, unknown> | null)?.requestId,
      body: { reservationId: id },
    });
  }

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
