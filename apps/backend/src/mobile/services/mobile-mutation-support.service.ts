import { Injectable } from '@nestjs/common';
import {
  suppressPosAuditBroadcast,
  suppressPosEchoForOrder,
  suppressPosEchoForTable,
} from '../../pos/sync-echo-guard';

/** WS exclude options for the REST client that initiated a mutation. */
export type BroadcastExclude = { excludeSocketIds: string[] } | undefined;

/**
 * Shared realtime/echo glue for mobile mutations.
 *
 * Extracted verbatim from MobileController's private helpers so the mobile
 * feature services (menu, reservations, orders, …) can share them. Behavior
 * unchanged.
 */
@Injectable()
export class MobileMutationSupport {
  /** Do not push WS notifications back to the REST client that initiated the action. */
  wsExcludeOpts(monitoringSocketId?: string): BroadcastExclude {
    const id = monitoringSocketId?.trim();
    return id ? { excludeSocketIds: [id] } : undefined;
  }

  /** Block POS round-trip WS notifications after this mobile mutation. */
  registerMobileMutationEchoGuard(
    posOrderId?: number,
    options?: { tableNumber?: string; floor?: string },
  ): void {
    if (posOrderId !== undefined && Number.isFinite(posOrderId)) {
      suppressPosEchoForOrder(posOrderId);
    }
    suppressPosAuditBroadcast();
    const tableNumber = options?.tableNumber?.trim();
    const floor = options?.floor?.trim() ?? 'first';
    if (tableNumber && tableNumber.length > 0) {
      suppressPosEchoForTable(tableNumber, floor);
    }
  }
}
