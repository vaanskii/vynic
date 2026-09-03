import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DeviceStatus, EdgeCommandStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { EdgeCommandService } from '../edge/edge-command.service';
import { PosCallbackClient } from './pos-callback.client';
import { PosOutboxService } from './pos-outbox.service';
import type { TenantContext } from '../auth/pos-auth-context';
import {
  EDGE_COMMAND_CONTRACT_VERSION,
  EdgeCommandTypes,
  type EdgeCommandType,
} from '../shared/contracts/edge-command';

/** How far a Cloud-originated operation has actually got. */
export type PosDeliveryStatus =
  /** Recorded in the queue. The POS has not claimed it yet. */
  | 'QUEUED'
  /** A POS holds a lease on it and has not reported back. */
  | 'CLAIMED'
  /** The POS executed it and said so. */
  | 'SUCCEEDED'
  /** The POS executed it and reported a failure. */
  | 'FAILED'
  /** Handed to the POS over the LAN and accepted. Transitional. */
  | 'DELIVERED_LEGACY'
  /** Nothing could be recorded — no enrolled Device and no LAN address. */
  | 'UNAVAILABLE';

export interface PosDelivery {
  transport: 'edge' | 'legacy';
  status: PosDeliveryStatus;
  /** Present for the Edge transport: the row this operation became. */
  commandId?: string;
  /** The POS's own outcome code, once it has reported one. */
  code?: string | null;
  detail?: string | null;
}

export interface DispatchPosCommand {
  type: EdgeCommandType;
  payload: Record<string, unknown>;
  /**
   * Stable identity for this intent. Defaults to a fresh id, which is what
   * almost every caller wants: the key exists to make *redelivery of one
   * request* safe, not to collapse two edits a manager deliberately made.
   */
  idempotencyKey?: string;
  /** Null routes to the Venue's Edge; set addresses one terminal. */
  deviceId?: string | null;
}

/**
 * How long to wait for a POS to report back on work a person is watching.
 *
 * Only printing uses it. A manager who pressed "print check" is standing in
 * front of a printer, and "queued" is a worse answer than a few seconds of
 * waiting when the answer usually arrives inside them. Bounded on purpose: a
 * request must never hang on a restaurant that is offline.
 */
const DEFAULT_AWAIT_MS = 15_000;
const AWAIT_POLL_MS = 400;

/**
 * The legacy LAN route each command type used to take.
 *
 * Kept only so a Venue with no enrolled Device still works. The payloads are
 * identical — both transports land on the same POS-side applier — so this is a
 * path lookup and nothing more. No entry may be added here: a new command type
 * belongs on the Edge transport, and this table shrinks to nothing when the
 * last unenrolled installation is enrolled.
 */
const LEGACY_ENDPOINTS: Partial<Record<EdgeCommandType, string>> = {
  [EdgeCommandTypes.ORDER_UPDATE]: '/mobile-order-update',
  [EdgeCommandTypes.ORDER_CANCEL]: '/mobile-order-cancel',
  [EdgeCommandTypes.ORDER_STATUS_UPDATE]: '/mobile-order-status',
  [EdgeCommandTypes.TAKEAWAY_ORDER_UPSERT]: '/mobile-order-create',
  [EdgeCommandTypes.DINE_IN_ORDER_UPSERT]: '/mobile-walk-in-order-create',
  [EdgeCommandTypes.ORDER_CHECK_PRINT]: '/mobile-order-print-check',
  [EdgeCommandTypes.RESERVATION_CREATE]: '/mobile-reservation-create',
  [EdgeCommandTypes.RESERVATION_STATUS_UPDATE]: '/mobile-reservation-status',
  [EdgeCommandTypes.RESERVATION_DELETE]: '/mobile-reservation-delete',
  [EdgeCommandTypes.RESERVATION_CHECK_PRINT]: '/mobile-reservation-print-check',
  [EdgeCommandTypes.COUNTED_MENU_PRINT]: '/mobile-counted-menu-print',
  [EdgeCommandTypes.EXPENSE_CREATE]: '/mobile-expense-create',
  [EdgeCommandTypes.STAFF_CREATE]: '/mobile-user-create',
  [EdgeCommandTypes.STAFF_PIN_UPDATE]: '/mobile-user-update-pin',
  [EdgeCommandTypes.STAFF_ROLE_UPDATE]: '/mobile-user-update-role',
  [EdgeCommandTypes.STAFF_RENAME]: '/mobile-user-rename',
  [EdgeCommandTypes.STAFF_DELETE]: '/mobile-user-delete',
};

/**
 * The one way Cloud asks a restaurant's POS to do something.
 *
 * Every Manager and website mutation that has to reach POS Hive comes through
 * here, and what it does is record work in the `EdgeCommand` queue for the POS
 * to claim. Cloud does not deliver. It cannot: a hosted Vynic has no route to
 * `192.168.1.50`, and the SSRF guard on the old callback path only ever
 * accepted the addresses a Cloud deployment can never reach.
 *
 * ## The transitional fallback, stated plainly
 *
 * A Venue with no enrolled Device cannot use this transport at all — the Edge
 * endpoints refuse the legacy shared sync key, because it names a Venue but no
 * machine. Those installations still exist, so this service falls back to the
 * legacy LAN callback for them, and only for them.
 *
 * That fallback is frozen. It carries no command type the Edge transport does
 * not, both routes end in the same POS-side applier, and it disappears for a
 * Venue the moment a terminal enrols. It is the reason "Cloud never needs a
 * private POS IP" is true of every *enrolled* Venue rather than of every Venue,
 * and that distinction is the honest one until the fleet has finished enrolling.
 *
 * ## What a caller may claim
 *
 * A queued command is not a completed one. `dispatch` returns `QUEUED`, and no
 * caller may turn that into "the POS was updated". Where a person is waiting on
 * the answer — printing — `dispatchAndAwait` waits a bounded few seconds for
 * the POS's own report and returns what actually happened.
 */
@Injectable()
export class PosCommandDispatcher {
  private readonly logger = new Logger(PosCommandDispatcher.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly commands: EdgeCommandService,
    private readonly posCallback: PosCallbackClient,
    private readonly posOutbox: PosOutboxService,
  ) {}

  /**
   * Record work for a Venue's POS and return where it got to.
   *
   * Does not wait. The POS claims on its own schedule, which is the whole point
   * of a pull transport — the restaurant decides when it is reachable.
   */
  async dispatch(
    tenant: Pick<TenantContext, 'venueId'>,
    command: DispatchPosCommand,
  ): Promise<PosDelivery> {
    if (await this.hasEnrolledDevice(tenant.venueId)) {
      const queued = await this.commands.enqueue(tenant, {
        deviceId: command.deviceId ?? null,
        type: command.type,
        payload: command.payload,
        idempotencyKey:
          command.idempotencyKey ?? `${command.type}:${randomUUID()}`,
        contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
      });
      return {
        transport: 'edge',
        status: this.toDeliveryStatus(queued.status),
        commandId: queued.id,
      };
    }
    return this.dispatchLegacy(tenant, command);
  }

  /**
   * Record work and wait, briefly, for the POS to say what happened to it.
   *
   * For operations a person is watching. Returns the real outcome when it
   * arrives inside the window and `QUEUED` when it does not — never a guess,
   * and never an unbounded wait on a restaurant that may be closed.
   */
  async dispatchAndAwait(
    tenant: Pick<TenantContext, 'venueId'>,
    command: DispatchPosCommand,
    timeoutMs: number = DEFAULT_AWAIT_MS,
  ): Promise<PosDelivery> {
    const delivery = await this.dispatch(tenant, command);
    if (delivery.transport !== 'edge' || !delivery.commandId) {
      return delivery;
    }
    return this.awaitTerminal(delivery, timeoutMs);
  }

  /** The current state of a dispatched command, for a caller that polls. */
  async statusOf(
    tenant: Pick<TenantContext, 'venueId'>,
    commandId: string,
  ): Promise<PosDelivery | null> {
    const row = await this.prisma.edgeCommand.findUnique({
      where: { id: commandId },
      select: {
        id: true,
        venueId: true,
        status: true,
        resultCode: true,
        resultDetail: true,
      },
    });
    // A foreign Venue's command is reported as missing rather than forbidden:
    // a status lookup must not become a way to probe which ids exist elsewhere.
    if (!row || row.venueId !== tenant.venueId) return null;
    return {
      transport: 'edge',
      status: this.toDeliveryStatus(row.status),
      commandId: row.id,
      code: row.resultCode,
      detail: row.resultDetail,
    };
  }

  /**
   * Whether this Venue has a terminal that can claim work.
   *
   * The queue is useless without one: an `EdgeCommand` for a Venue whose only
   * POS authenticates with the legacy shared key would sit `PENDING` forever,
   * because that key resolves no Device and the Edge endpoints refuse it.
   */
  private async hasEnrolledDevice(venueId: string): Promise<boolean> {
    const device = await this.prisma.device.findFirst({
      where: { venueId, status: DeviceStatus.ACTIVE },
      select: { id: true },
    });
    return device !== null;
  }

  private async awaitTerminal(
    delivery: PosDelivery,
    timeoutMs: number,
  ): Promise<PosDelivery> {
    const deadline = Date.now() + timeoutMs;
    let current = delivery;
    while (Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, AWAIT_POLL_MS));
      const row = await this.prisma.edgeCommand.findUnique({
        where: { id: delivery.commandId },
        select: { status: true, resultCode: true, resultDetail: true },
      });
      if (!row) return current;
      current = {
        ...delivery,
        status: this.toDeliveryStatus(row.status),
        code: row.resultCode,
        detail: row.resultDetail,
      };
      if (current.status === 'SUCCEEDED' || current.status === 'FAILED') {
        return current;
      }
    }
    return current;
  }

  /**
   * The transitional path for a Venue with no enrolled Device.
   *
   * Mutations go through the durable outbox, exactly as they did before, so a
   * POS that is briefly offline still receives them. Prints go direct: a print
   * queued for an hour and delivered after service is worse than one that fails
   * where somebody can see it.
   */
  private async dispatchLegacy(
    tenant: Pick<TenantContext, 'venueId'>,
    command: DispatchPosCommand,
  ): Promise<PosDelivery> {
    const endpoint = LEGACY_ENDPOINTS[command.type];
    if (!endpoint) {
      this.logger.warn(
        `No legacy route for ${command.type}; venue ${tenant.venueId} has no enrolled device.`,
      );
      return { transport: 'legacy', status: 'UNAVAILABLE' };
    }

    if (isPrintCommand(command.type)) {
      const result = await this.posCallback.deliverToPos(
        endpoint,
        command.payload,
      );
      return {
        transport: 'legacy',
        status: result.ok ? 'DELIVERED_LEGACY' : 'UNAVAILABLE',
        code: result.ok ? null : (result.error ?? 'pos_unreachable'),
      };
    }

    await this.posOutbox.enqueue(
      {
        endpoint,
        payload: command.payload,
        posOrderId:
          typeof command.payload.posOrderId === 'number'
            ? command.payload.posOrderId
            : undefined,
        // Distinct requests stay distinct. Collapsing was an optimisation for a
        // transport that pushed; it costs an edit when two arrive together.
        collapse: false,
      },
      tenant,
    );
    return { transport: 'legacy', status: 'QUEUED' };
  }

  private toDeliveryStatus(status: EdgeCommandStatus): PosDeliveryStatus {
    switch (status) {
      case EdgeCommandStatus.SUCCEEDED:
        return 'SUCCEEDED';
      case EdgeCommandStatus.FAILED:
        return 'FAILED';
      case EdgeCommandStatus.CLAIMED:
        return 'CLAIMED';
      default:
        return 'QUEUED';
    }
  }
}

/** Whether this type puts something on paper. */
export function isPrintCommand(type: EdgeCommandType): boolean {
  return (
    type === EdgeCommandTypes.ORDER_CHECK_PRINT ||
    type === EdgeCommandTypes.RESERVATION_CHECK_PRINT ||
    type === EdgeCommandTypes.COUNTED_MENU_PRINT
  );
}
