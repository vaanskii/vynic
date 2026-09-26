import type {
  BookingRequest,
  BookingResult,
  CustomSiteBootstrap,
  CustomSiteMenu,
  PaymentStatus,
  TableAvailability,
  WebsiteSession,
  WebsiteTable,
} from "./types";

/** The host has no custom website (unknown, disabled, SAAS, or not entitled). */
export class SiteUnavailableError extends Error {
  constructor(readonly status: number) {
    super(status === 403 ? "Website access is not active" : "No website here");
  }
}

/** Any other non-success answer from the backend. */
export class WebsiteApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export type WebsiteClientOptions = {
  /**
   * Leave empty. The API must be reached on the site's own origin through a
   * host-preserving proxy (`/api` → backend, Host unchanged): the Host is what
   * selects the restaurant, and the site's session cookies are same-site only.
   * Only tests and unusual proxies should set this.
   */
  baseUrl?: string;
  fetch?: typeof fetch;
};

/**
 * The shared Vynic public website API, for a CUSTOM frontend.
 *
 * Deliberately has no way to name a Venue, domain or organization: the backend
 * decides the restaurant from the request Host alone, so there is nothing a
 * frontend could put here to become another restaurant.
 */
export function createWebsiteClient(options: WebsiteClientOptions = {}) {
  const base = options.baseUrl ?? "";
  const doFetch = options.fetch ?? ((...a: Parameters<typeof fetch>) => fetch(...a));
  let csrfToken: string | null = null;

  async function call<T>(
    path: string,
    init: RequestInit & { json?: unknown } = {},
  ): Promise<T> {
    const headers = new Headers(init.headers);
    let body = init.body;
    if (init.json !== undefined) {
      headers.set("Content-Type", "application/json");
      body = JSON.stringify(init.json);
    }
    if (csrfToken && init.method && init.method !== "GET")
      headers.set("X-CSRF-Token", csrfToken);
    const response = await doFetch(`${base}${path}`, {
      ...init,
      body,
      headers,
      // Same-origin only: session cookies are SameSite=Strict and host-bound.
      credentials: "same-origin",
    });
    if (response.status === 404) throw new SiteUnavailableError(404);
    if (!response.ok) {
      let message = `Request failed: ${response.status}`;
      try {
        const payload = (await response.json()) as { message?: unknown };
        if (typeof payload.message === "string") message = payload.message;
      } catch {
        // Keep the status-only message.
      }
      throw new WebsiteApiError(response.status, message);
    }
    return (await response.json()) as T;
  }

  async function withCsrf<T>(path: string, json: unknown): Promise<T> {
    const { csrfToken: token } = await call<{ csrfToken: string }>(
      "/api/auth/csrf",
    );
    csrfToken = token;
    return call<T>(path, { method: "POST", json });
  }

  return {
    /** Identity, frontend binding, profile and capabilities of this site. */
    bootstrap: async () => {
      try {
        return await call<CustomSiteBootstrap>("/api/website/venue");
      } catch (error) {
        // At the site level a refusal means Website access is not active
        // (for example an ended Trial); elsewhere 403 is a capability answer.
        if (error instanceof WebsiteApiError && error.status === 403)
          throw new SiteUnavailableError(403);
        throw error;
      }
    },
    /** Canonical menu with the owner's website presentation applied. */
    menu: () => call<CustomSiteMenu>("/api/website/venue/menu"),

    tables: () => call<WebsiteTable[]>("/api/tables"),
    availability: (date: string) =>
      call<TableAvailability[]>(
        `/api/tables/availability?date=${encodeURIComponent(date)}`,
      ),
    /**
     * Creates a pending booking and a bank order through the Venue's own BOG
     * integration. Redirect the browser to `redirect_url`.
     */
    bookAndPay: (request: BookingRequest) =>
      call<BookingResult>("/api/bog/create-order", {
        method: "POST",
        json: request,
      }),
    /** Re-checks a booking's payment after the bank redirects back. */
    paymentStatus: (reservationId: string) =>
      call<PaymentStatus>(
        `/api/bog/check-reservation-status/${encodeURIComponent(reservationId)}`,
      ),

    /** Website customer accounts are global; bookings shown are this site's. */
    session: () => call<WebsiteSession>("/api/auth/verify"),
    signIn: (identifier: string, password: string) =>
      withCsrf<{ message: string }>("/api/auth/signin", { identifier, password }),
    signUp: (input: {
      phone: string;
      email: string;
      password: string;
      firstName?: string;
      lastName?: string;
    }) => withCsrf<{ message: string }>("/api/auth/signup", input),
    signOut: async () => {
      const result = await call<{ message: string }>("/api/auth/logout", {
        method: "POST",
      });
      csrfToken = null;
      return result;
    },
    myReservations: () => call<unknown[]>("/api/user/reservations"),
  };
}

export type WebsiteClient = ReturnType<typeof createWebsiteClient>;
