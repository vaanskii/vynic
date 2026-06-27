import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { PosCallbackClient } from './pos-callback.client';
import { suppressPosEchoForOrder } from './sync-echo-guard';

export interface EnqueuePosCallback {
  endpoint: string;
  payload: Record<string, unknown>;
  posOrderId?: number;
  /** When true, repeated pending rows for the same target collapse (latest wins). */
  collapse?: boolean;
}

export interface PosOutboxStats {
  pending: number;
  failed: number;
  oldestPendingAt: string | null;
  lastError: string | null;
  posReachable: boolean;
}

const WORKER_INTERVAL_MS = 15_000;
const BATCH_SIZE = 25;
const BACKOFF_BASE_MS = 5_000;
// Cap kept low so a POS that was offline a while still delivers quickly once
// it reconnects (a reconnect also kicks the queue — see kickPending()).
const BACKOFF_CAP_MS = 60_000;
// Delivered rows are kept briefly for observability, then pruned.
const DELIVERED_RETENTION_MS = 10 * 60_000;

/**
 * Durable cloud → Windows POS callback queue with a retry worker (sync-7).
 *
 * Mobile mutations that must reach Hive are enqueued here. A background worker
 * retries each row with exponential backoff until the POS confirms delivery,
 * so a temporarily offline/unreachable POS no longer loses the change.
 */
@Injectable()
export class PosOutboxService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PosOutboxService.name);
  private timer: NodeJS.Timeout | null = null;
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly posCallback: PosCallbackClient,
  ) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      void this.processDue();
    }, WORKER_INTERVAL_MS);
    // Don't keep the event loop alive solely for this timer.
    this.timer.unref?.();
    // Attempt any rows left over from a previous run shortly after boot.
    setTimeout(() => void this.processDue(), 3_000).unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  /**
   * Persist a callback then attempt immediate delivery. Returns immediately if
   * the immediate attempt is fired (non-blocking for the caller's request).
   */
  async enqueue(item: EnqueuePosCallback): Promise<void> {
    const dedupeKey =
      item.collapse !== false && item.posOrderId !== undefined
        ? `${item.endpoint}:${item.posOrderId}`
        : null;

    try {
      if (dedupeKey) {
        const existing = await (this.prisma as any).posCallbackOutbox.findFirst({
          where: { dedupeKey, status: 'pending' },
        });
        if (existing) {
          await (this.prisma as any).posCallbackOutbox.update({
            where: { id: existing.id },
            data: {
              payload: item.payload as object,
              attempts: 0,
              lastError: null,
              nextAttemptAt: new Date(),
            },
          });
        } else {
          await (this.prisma as any).posCallbackOutbox.create({
            data: {
              endpoint: item.endpoint,
              payload: item.payload as object,
              posOrderId: item.posOrderId ?? null,
              dedupeKey,
            },
          });
        }
      } else {
        await (this.prisma as any).posCallbackOutbox.create({
          data: {
            endpoint: item.endpoint,
            payload: item.payload as object,
            posOrderId: item.posOrderId ?? null,
          },
        });
      }
    } catch (e) {
      this.logger.error(
        `Failed to enqueue POS callback ${item.endpoint}: ${(e as Error).message}`,
      );
      return;
    }

    // Fire an immediate delivery pass without blocking the HTTP response.
    void this.processDue();
  }

  /** Process all due pending rows once. Safe against overlapping invocations. */
  async processDue(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const now = new Date();
      const due = await (this.prisma as any).posCallbackOutbox.findMany({
        where: { status: 'pending', nextAttemptAt: { lte: now } },
        orderBy: { createdAt: 'asc' },
        take: BATCH_SIZE,
      });

      if (due.length === 0) {
        await this.pruneDelivered();
        return;
      }

      // If the POS URL isn't registered yet, don't burn attempts — just wait.
      if (!this.posCallback.hasCallbackUrl()) {
        return;
      }

      for (const row of due) {
        await this.attemptRow(row);
      }
      await this.pruneDelivered();
    } catch (e) {
      this.logger.error(`Outbox processDue failed: ${(e as Error).message}`);
    } finally {
      this.running = false;
    }
  }

  private async attemptRow(row: {
    id: string;
    endpoint: string;
    payload: unknown;
    posOrderId: number | null;
    attempts: number;
    maxAttempts: number;
  }): Promise<void> {
    const result = await this.posCallback.deliverToPos(row.endpoint, row.payload);

    if (result.ok) {
      await (this.prisma as any).posCallbackOutbox.update({
        where: { id: row.id },
        data: { status: 'delivered', lastError: null },
      });
      // The POS will now re-push this change back to us. Re-arm echo
      // suppression from delivery time so that round-trip doesn't notify the
      // device that originated the edit (the original window likely expired
      // while the change sat queued for an offline POS).
      if (row.posOrderId !== null && Number.isFinite(row.posOrderId)) {
        suppressPosEchoForOrder(row.posOrderId);
      }
      return;
    }

    // POS dropped offline mid-batch — stop, retry whole batch next tick.
    if (result.noUrl) return;

    // Transport failure (connection refused / timeout) means the POS is offline,
    // not that the change is bad. Don't spend the attempt budget on an
    // unreachable POS — reschedule with backoff but keep the row recoverable so
    // a long outage can't exhaust retries and strand the change as `failed`.
    // Only a real HTTP response (4xx/5xx, which sets `status`) counts as an
    // attempt against maxAttempts.
    if (result.status === undefined) {
      await (this.prisma as any).posCallbackOutbox.update({
        where: { id: row.id },
        data: {
          lastError: result.error ?? 'pos_unreachable',
          nextAttemptAt: new Date(Date.now() + BACKOFF_CAP_MS),
        },
      });
      return;
    }

    const attempts = row.attempts + 1;
    if (attempts >= row.maxAttempts) {
      await (this.prisma as any).posCallbackOutbox.update({
        where: { id: row.id },
        data: {
          status: 'failed',
          attempts,
          lastError: result.error ?? 'unknown_error',
        },
      });
      this.logger.warn(
        `POS callback ${row.endpoint} permanently failed after ${attempts} attempts: ${result.error}`,
      );
      return;
    }

    const backoff = Math.min(
      BACKOFF_CAP_MS,
      BACKOFF_BASE_MS * 2 ** (attempts - 1),
    );
    await (this.prisma as any).posCallbackOutbox.update({
      where: { id: row.id },
      data: {
        attempts,
        lastError: result.error ?? 'unknown_error',
        nextAttemptAt: new Date(Date.now() + backoff),
      },
    });
  }

  private async pruneDelivered(): Promise<void> {
    const cutoff = new Date(Date.now() - DELIVERED_RETENTION_MS);
    try {
      // 'superseded' rows are terminal too (a newer POS edit won the LWW
      // conflict), so prune them on the same retention as delivered rows.
      await (this.prisma as any).posCallbackOutbox.deleteMany({
        where: {
          status: { in: ['delivered', 'superseded'] },
          updatedAt: { lt: cutoff },
        },
      });
    } catch {
      // Non-fatal; pruning retries next tick.
    }
  }

  /** Snapshot for the admin sync-health UI (sync-4). */
  async getStats(): Promise<PosOutboxStats> {
    const [pending, failed, oldest, lastErrored] = await Promise.all([
      (this.prisma as any).posCallbackOutbox.count({
        where: { status: 'pending' },
      }),
      (this.prisma as any).posCallbackOutbox.count({
        where: { status: 'failed' },
      }),
      (this.prisma as any).posCallbackOutbox.findFirst({
        where: { status: 'pending' },
        orderBy: { createdAt: 'asc' },
        select: { createdAt: true },
      }),
      (this.prisma as any).posCallbackOutbox.findFirst({
        where: { lastError: { not: null } },
        orderBy: { updatedAt: 'desc' },
        select: { lastError: true },
      }),
    ]);

    return {
      pending,
      failed,
      oldestPendingAt: oldest?.createdAt?.toISOString() ?? null,
      lastError: lastErrored?.lastError ?? null,
      posReachable: this.posCallback.hasCallbackUrl(),
    };
  }

  /**
   * Flush queued callbacks immediately — called when the POS reconnects
   * (manager-data push) so a held mobile change reaches Hive without waiting
   * out the backoff window. Resets pending rows to due, then delivers.
   */
  async kickPending(): Promise<void> {
    try {
      // Revive rows that exhausted their attempts while the POS was offline:
      // the POS is back now, so give them a clean retry budget. Without this a
      // long outage would strand changes as `failed` until a manual admin sync.
      await (this.prisma as any).posCallbackOutbox.updateMany({
        where: { status: 'failed' },
        data: { status: 'pending', attempts: 0, nextAttemptAt: new Date() },
      });
      const pending = await (this.prisma as any).posCallbackOutbox.count({
        where: { status: 'pending' },
      });
      if (pending === 0) return;
      await (this.prisma as any).posCallbackOutbox.updateMany({
        where: { status: 'pending', nextAttemptAt: { gt: new Date() } },
        data: { nextAttemptAt: new Date() },
      });
      void this.processDue();
    } catch (e) {
      this.logger.warn(`kickPending failed: ${(e as Error).message}`);
    }
  }

  /**
   * Classify an error thrown by the *direct* POS path (`PosCallbackClient`
   * `requestPos`) so callers can fall back to the durable outbox only when the
   * POS was unreachable — never when the POS actively rejected the request.
   *
   * - "callback URL is not available" → POS never registered (offline) → queue.
   * - "POS request failed <status>: …" → an HTTP response came back, so the POS
   *   is reachable and rejected it (validation, conflict, …) → do NOT queue.
   * - anything else (network error, timeout/abort) → unreachable → queue.
   */
  isPosUnreachableError(error: unknown): boolean {
    const message = (error as Error)?.message ?? '';
    if (message.includes('callback URL is not available')) return true;
    if (/POS request failed \d+/.test(message)) return false;
    return true;
  }

  /** Force a retry of all failed rows (admin "Sync now" — sync-4). */
  async retryFailed(): Promise<number> {
    const result = await (this.prisma as any).posCallbackOutbox.updateMany({
      where: { status: 'failed' },
      data: { status: 'pending', attempts: 0, nextAttemptAt: new Date() },
    });
    void this.processDue();
    return result.count ?? 0;
  }
}
