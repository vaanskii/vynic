const base = (import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");
/** A refused request; keeps the status and server body (e.g. a Menu conflict). */
export class CustomerApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly data: { code?: string; conflict?: unknown } & Record<
      string,
      unknown
    >,
  ) {
    super(message);
  }
}
let token = sessionStorage.getItem("vynic-customer-token");
export function customerLogout() {
  token = null;
  sessionStorage.removeItem("vynic-customer-token");
}
export async function customerApi<T = any>(
  path: string,
  body?: unknown,
  method = "POST",
): Promise<T> {
  const response = await fetch(`${base}/customer/${path}`, {
    method: body === undefined ? "GET" : method,
    headers: {
      ...(path.startsWith("invitations/")
        ? { "X-CSRF-Token": "vynic-invitation" }
        : {}),
      ...(body instanceof FormData
        ? {}
        : { "Content-Type": "application/json" }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    credentials: "same-origin",
    ...(body === undefined
      ? {}
      : { body: body instanceof FormData ? body : JSON.stringify(body) }),
  });
  const data = await response.json();
  if (!response.ok) {
    if (response.status === 401) customerLogout();
    throw new CustomerApiError(
      Array.isArray(data.message)
        ? data.message.join(", ")
        : (data.message ?? "მოთხოვნა ვერ შესრულდა"),
      response.status,
      data,
    );
  }
  if (data.access_token) {
    token = data.access_token;
    sessionStorage.setItem("vynic-customer-token", token!);
  }
  return data;
}
export const hasCustomerSession = () => !!token;
