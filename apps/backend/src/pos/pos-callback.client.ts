import { Injectable } from '@nestjs/common';
import { isAllowedPosCallbackUrl } from './pos-callback-url';

/**
 * The LAN transport Cloud used to reach a POS with. **Frozen.**
 *
 * Every business operation moved to the Edge command queue in Step 6C, and the
 * per-operation methods that used to live here — create an order, cancel a
 * reservation, print a check, rename a user — went with them. What is left is
 * the raw sender and the address it sends to, kept for exactly one situation:
 * a Venue with no enrolled Device cannot use the Edge transport at all, because
 * the Edge endpoints refuse the legacy shared sync key. See
 * `PosCommandDispatcher`, which is the only thing that decides to use this.
 *
 * The synchronous request/response half is **gone**, deliberately. It was how a
 * backend request read a restaurant's reservations over the LAN, and there is
 * no version of that a hosted Vynic can perform: the SSRF guard accepts only
 * private addresses, which are precisely the ones Cloud cannot route to.
 * Reservation reads are answered from `PosReservationMirrorService` now, and
 * removing the method is what stops a future caller reaching for the old shape.
 *
 * No method may be added here. A new Cloud → POS operation is a command type.
 *
 * State ownership: the in-memory callback URL and connection key live here.
 * `PosConnectionRegistry` owns the durable half and pushes the current values
 * in via {@link setCallbackUrl} / {@link setConnectionKey}.
 */
@Injectable()
export class PosCallbackClient {
  // Cached in memory; persisted in DB by SyncController so server restarts do
  // not lose the URL.
  private callbackUrl: string | null = null;
  private connectionKey: string | null = null;

  setCallbackUrl(url: string | null): void {
    // SSRF guard: never hold a non-LAN URL that we'd later fetch().
    if (url !== null && !isAllowedPosCallbackUrl(url)) {
      console.warn(
        `[Sync] Rejected POS callback URL (not a private/LAN address): ${url}`,
      );
      this.callbackUrl = null;
      return;
    }
    this.callbackUrl = url;
  }

  setConnectionKey(key: string | null): void {
    this.connectionKey = key;
  }

  private headers(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (this.connectionKey) {
      headers['x-connection-key'] = this.connectionKey;
    }
    return headers;
  }

  hasCallbackUrl(): boolean {
    return !!this.callbackUrl;
  }

  /**
   * Single low-level sender for cloud → POS callbacks. Used by the immediate
   * path and by the durable outbox worker (sync-7). Never throws.
   */
  async deliverToPos(
    endpoint: string,
    payload: unknown,
    timeoutMs = 5000,
  ): Promise<{
    ok: boolean;
    noUrl?: boolean;
    status?: number;
    error?: string;
  }> {
    const url = this.callbackUrl;
    if (!url) return { ok: false, noUrl: true, error: 'no_pos_callback_url' };
    try {
      const res = await fetch(`${url}${endpoint}`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        return {
          ok: false,
          status: res.status,
          error: `pos_${res.status}: ${body}`.trim(),
        };
      }
      return { ok: true, status: res.status };
    } catch (e) {
      return { ok: false, error: (e as Error).message };
    }
  }
}
