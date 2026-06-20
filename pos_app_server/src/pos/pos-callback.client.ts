import { Injectable } from '@nestjs/common';

/**
 * Transport client for cloud → POS callbacks (Option A in SYNC_CONTRACT.md).
 *
 * Extracted verbatim from `SyncController` so the POS-callback transport is a
 * plain injectable concern instead of static methods on an HTTP controller.
 * Behavior is unchanged: these are thin `fetch()` wrappers that reach the
 * Windows POS machine's local ingest server at the registered callback URL.
 *
 * State ownership: the in-memory callback URL / connection key live here (used
 * for every request). `SyncController` still owns DB persistence/restore and
 * pushes the current values in via {@link setCallbackUrl} / {@link setConnectionKey}.
 */
@Injectable()
export class PosCallbackClient {
  // Cached in memory; persisted in DB by SyncController so server restarts do
  // not lose the URL.
  private callbackUrl: string | null = null;
  private connectionKey: string | null = null;

  setCallbackUrl(url: string | null): void {
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
  ): Promise<{ ok: boolean; noUrl?: boolean; status?: number; error?: string }> {
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
        return { ok: false, status: res.status, error: `pos_${res.status}: ${body}`.trim() };
      }
      return { ok: true, status: res.status };
    } catch (e) {
      return { ok: false, error: (e as Error).message };
    }
  }

  /** Push a changed order back to the Windows POS via HTTP */
  async notifyPos(posOrderId: number, orderData: any): Promise<void> {
    const result = await this.deliverToPos('/mobile-order-update', {
      posOrderId,
      ...orderData,
    });
    if (!result.ok) {
      console.warn(
        `[Sync] POS callback failed for order ${posOrderId}:`,
        result.error,
      );
    }
  }

  /** Tell the Windows POS to cancel (delete) an order from Hive */
  async notifyPosCancel(posOrderId: number): Promise<void> {
    const result = await this.deliverToPos('/mobile-order-cancel', {
      posOrderId,
    });
    if (!result.ok) {
      console.warn('[Sync] POS cancel callback failed:', result.error);
    }
  }

  /** Tell the Windows POS to update the status of an order in Hive (without deleting) */
  async notifyPosStatusUpdate(posOrderId: number, status: string): Promise<void> {
    const result = await this.deliverToPos('/mobile-order-status', {
      posOrderId,
      status,
    });
    if (!result.ok) {
      console.warn('[Sync] POS status update callback failed:', result.error);
    }
  }

  /** Tell the Windows POS to create a new mobile-originated takeaway order in Hive */
  async notifyPosCreate(orderData: any): Promise<void> {
    const result = await this.deliverToPos('/mobile-order-create', orderData);
    if (!result.ok) {
      console.warn('[Sync] POS create callback failed:', result.error);
    }
  }

  private async requestPos(
    path: string,
    init: RequestInit = {},
  ): Promise<any> {
    const url = this.callbackUrl;
    if (!url) {
      throw new Error(
        'POS callback URL is not available — open Windows POS and wait for ManagerSync OK (posCallbackUrl).',
      );
    }
    const res = await fetch(`${url}${path}`, {
      ...init,
      headers: {
        ...this.headers(),
        ...(init.headers ?? {}),
      },
      signal: AbortSignal.timeout(7000),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`POS request failed ${res.status}: ${body}`);
    }
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  async fetchPosReservations(): Promise<any[]> {
    const response = await this.requestPos('/mobile-reservations', {
      method: 'GET',
    });
    return Array.isArray(response?.data) ? response.data : [];
  }

  async createPosReservation(payload: Record<string, unknown>): Promise<any> {
    const response = await this.requestPos('/mobile-reservation-create', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    return response?.reservation ?? null;
  }

  async updatePosReservationStatus(
    reservationId: string,
    status: string,
  ): Promise<void> {
    await this.requestPos('/mobile-reservation-status', {
      method: 'POST',
      body: JSON.stringify({ reservationId, status }),
    });
  }

  async deletePosReservation(reservationId: string): Promise<void> {
    await this.requestPos('/mobile-reservation-delete', {
      method: 'POST',
      body: JSON.stringify({ reservationId }),
    });
  }

  async createPosExpense(payload: Record<string, unknown>): Promise<any> {
    const response = await this.requestPos('/mobile-expense-create', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    return response?.expense ?? null;
  }

  async createPosUser(payload: Record<string, unknown>): Promise<any> {
    const response = await this.requestPos('/mobile-user-create', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    return response?.user ?? null;
  }

  async updatePosUserPin(payload: Record<string, unknown>): Promise<any> {
    const response = await this.requestPos('/mobile-user-update-pin', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    return response?.user ?? null;
  }

  async renamePosUser(payload: Record<string, unknown>): Promise<any> {
    const response = await this.requestPos('/mobile-user-rename', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    return response?.user ?? null;
  }

  async deletePosUser(payload: Record<string, unknown>): Promise<void> {
    await this.requestPos('/mobile-user-delete', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }
}
