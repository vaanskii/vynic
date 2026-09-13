const base = (import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");
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
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json();
  if (!response.ok) {
    if (response.status === 401) customerLogout();
    throw new Error(
      Array.isArray(data.message)
        ? data.message.join(", ")
        : (data.message ?? "მოთხოვნა ვერ შესრულდა"),
    );
  }
  if (data.access_token) {
    token = data.access_token;
    sessionStorage.setItem("vynic-customer-token", token!);
  }
  return data;
}
export const hasCustomerSession = () => !!token;
