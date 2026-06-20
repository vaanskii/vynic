import { BadRequestException, Injectable } from '@nestjs/common';
import { PosCallbackClient } from '../../pos/pos-callback.client';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { suppressPosEchoForReservation } from '../../pos/sync-echo-guard';
import { MobileMutationSupport } from './mobile-mutation-support.service';

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
    private readonly posCallback: PosCallbackClient,
    private readonly gateway: MonitoringGateway,
    private readonly mutationSupport: MobileMutationSupport,
  ) {}

  async getReservations(date?: string): Promise<ReservationResponseItem[]> {
    let rows: any[] = [];
    try {
      rows = await this.posCallback.fetchPosReservations();
    } catch (e) {
      console.warn('[Mobile][Reservations] fetch failed:', (e as Error).message);
      // Keep mobile UI functional even before POS callback URL is synced.
      return [];
    }
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
          ? r.tableNumbers.map((x: any) => Number(x)).filter((x: number) => Number.isFinite(x))
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
  ): Promise<ReservationResponseItem> {
    const customerName = (payload.customerName ?? '').trim();
    const customerPhone = (payload.customerPhone ?? '').trim();
    const reservationDate = (payload.reservationDate ?? '').trim();
    const reservationTime = (payload.reservationTime ?? '').trim();
    const tableNumbers = Array.isArray(payload.tableNumbers)
      ? payload.tableNumbers.map((n) => Number(n)).filter((n) => Number.isFinite(n))
      : [];
    const numberOfGuests = Number(payload.numberOfGuests ?? 0);
    if (customerName.length === 0 || reservationDate.length === 0 || reservationTime.length === 0) {
      throw new BadRequestException('customerName, reservationDate, reservationTime are required');
    }
    if (!Number.isFinite(numberOfGuests) || numberOfGuests <= 0) {
      throw new BadRequestException('numberOfGuests must be greater than zero');
    }

    const preOrderItems = Array.isArray(payload.preOrderItems)
      ? payload.preOrderItems
      : [];

    const reservation = await this.posCallback.createPosReservation({
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
    });
    // Suppress the POS round-trip echo so the device that created this
    // reservation isn't re-notified when the POS syncs it back.
    const newReservationId = String(reservation?.id ?? '').trim();
    if (newReservationId.length > 0) {
      suppressPosEchoForReservation(newReservationId);
    }
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
      id: String(reservation?.id ?? ''),
      customerName: String(reservation?.customerName ?? customerName),
      customerPhone: String(reservation?.customerPhone ?? customerPhone),
      tableNumbers: Array.isArray(reservation?.tableNumbers)
        ? reservation.tableNumbers.map((x: any) => Number(x)).filter((x: number) => Number.isFinite(x))
        : tableNumbers,
      reservationDate: String(reservation?.reservationDate ?? reservationDate),
      reservationTime: String(reservation?.reservationTime ?? reservationTime),
      numberOfGuests: Number(reservation?.numberOfGuests ?? numberOfGuests),
      notes: reservation?.notes ? String(reservation.notes) : undefined,
      status: String(reservation?.status ?? 'confirmed'),
      createdBy: reservation?.createdBy ? String(reservation.createdBy) : undefined,
    };
  }

  async updateReservationStatus(
    id: string,
    monitoringSocketId: string | undefined,
    payload: { status?: string },
  ): Promise<{ success: true }> {
    const status = (payload.status ?? '').trim().toLowerCase();
    if (status.length === 0) {
      throw new BadRequestException('status is required');
    }
    if (status === 'completed' || status === 'in-progress' || status === 'inprogress') {
      throw new BadRequestException('Moving reservation to table is not allowed from mobile');
    }
    await this.posCallback.updatePosReservationStatus(id, status);
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: status === 'cancelled' ? 'cancelled' : 'updated',
        reservationId: id,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }

  async deleteReservation(
    id: string,
    monitoringSocketId?: string,
  ): Promise<{ success: true }> {
    await this.posCallback.deletePosReservation(id);
    this.gateway.broadcastUpdate(
      'data_updated',
      {
        type: 'reservations',
        action: 'cancelled',
        reservationId: id,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    return { success: true };
  }
}
