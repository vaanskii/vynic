import type {
  AuditEvent,
  Device,
  DeviceEnrollment,
  DeviceStatus,
  DomainStatus,
  Feature,
  IssuedCredential,
  IssuedEnrollment,
  LoginResult,
  Organization,
  OverrideEffect,
  Page,
  Plan,
  PlatformActor,
  ProductState,
  QueuedCommand,
  Venue,
  VenueDomain,
  VenueStatus,
  WebsiteAccess,
  WebsiteMode,
} from "./types";

const configuredBaseUrl = import.meta.env.VITE_API_BASE_URL?.trim() ?? "";
const API_BASE_URL = configuredBaseUrl.replace(/\/$/, "");

export class PlatformApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly details?: string[],
  ) {
    super(message);
  }
}

let readToken: () => string | null = () => null;
let handleUnauthorized: () => void = () => undefined;

export function configurePlatformApi(options: {
  token: () => string | null;
  onUnauthorized: () => void;
}) {
  readToken = options.token;
  handleUnauthorized = options.onUnauthorized;
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = readToken();
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body) headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);

  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, { ...init, headers });
  } catch {
    throw new PlatformApiError(
      "The Vynic API could not be reached. Check the connection and try again.",
      0,
    );
  }

  if (response.status === 401) handleUnauthorized();
  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as
      | { message?: string | string[] }
      | null;
    const details = Array.isArray(payload?.message) ? payload.message : undefined;
    const message =
      (typeof payload?.message === "string" && payload.message) ||
      details?.[0] ||
      `Request failed (${response.status})`;
    throw new PlatformApiError(message, response.status, details);
  }
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

const json = (value: object) => JSON.stringify(value);

export const authApi = {
  login: (email: string, password: string) =>
    request<LoginResult>("/platform/auth/login", {
      method: "POST",
      body: json({ email, password }),
    }),
  me: () => request<PlatformActor>("/platform/auth/me"),
};

export const platformApi = {
  organizations: (limit = 50, offset = 0) =>
    request<Page<Organization>>(
      `/platform/organizations?limit=${limit}&offset=${offset}`,
    ),
  organization: (id: string) =>
    request<Organization>(`/platform/organizations/${id}`),
  createOrganization: (name: string) =>
    request<Organization>("/platform/organizations", {
      method: "POST",
      body: json({ name }),
    }),
  updateOrganization: (id: string, name: string) =>
    request<Organization>(`/platform/organizations/${id}`, {
      method: "PATCH",
      body: json({ name }),
    }),
  venues: (options: { limit?: number; offset?: number; organizationId?: string } = {}) => {
    const search = new URLSearchParams({
      limit: String(options.limit ?? 50),
      offset: String(options.offset ?? 0),
    });
    if (options.organizationId) search.set("organizationId", options.organizationId);
    return request<Page<Venue>>(`/platform/venues?${search}`);
  },
  venue: (id: string) => request<Venue>(`/platform/venues/${id}`),
  createVenue: (input: {
    organizationId: string;
    name: string;
    timezone: string;
    currency: string;
  }) => request<Venue>("/platform/venues", { method: "POST", body: json(input) }),
  updateVenue: (id: string, input: { name: string; timezone: string; currency: string }) =>
    request<Venue>(`/platform/venues/${id}`, { method: "PATCH", body: json(input) }),
  setVenueStatus: (id: string, status: VenueStatus) =>
    request<Venue>(`/platform/venues/${id}/status`, {
      method: "PUT",
      body: json({ status }),
    }),
  plans: () => request<Plan[]>("/platform/plans"),
  features: () => request<Feature[]>("/platform/features"),
  product: (venueId: string) =>
    request<ProductState>(`/platform/venues/${venueId}/product`),
  assignPlan: (venueId: string, planId: string) =>
    request<ProductState>(`/platform/venues/${venueId}/plan`, {
      method: "PUT",
      body: json({ planId }),
    }),
  setFeatureOverride: (
    venueId: string,
    featureKey: string,
    effect: OverrideEffect,
    note?: string,
  ) =>
    request<ProductState>(`/platform/venues/${venueId}/features/${featureKey}`, {
      method: "PUT",
      body: json({ effect, note }),
    }),
  clearFeatureOverride: (venueId: string, featureKey: string) =>
    request<ProductState>(`/platform/venues/${venueId}/features/${featureKey}`, {
      method: "DELETE",
    }),
  setWebsiteMode: (venueId: string, mode: WebsiteMode) =>
    request<WebsiteAccess>(`/platform/venues/${venueId}/website`, {
      method: "PUT",
      body: json({ mode }),
    }),
  domains: (venueId: string) =>
    request<VenueDomain[]>(`/platform/venues/${venueId}/domains`),
  registerDomain: (venueId: string, hostname: string) =>
    request<VenueDomain>(`/platform/venues/${venueId}/domains`, {
      method: "POST",
      body: json({ hostname }),
    }),
  setDomainStatus: (venueId: string, domainId: string, status: DomainStatus) =>
    request<VenueDomain>(`/platform/venues/${venueId}/domains/${domainId}/status`, {
      method: "PUT",
      body: json({ status }),
    }),
  releaseDomain: (venueId: string, domainId: string) =>
    request<{ released: string }>(`/platform/venues/${venueId}/domains/${domainId}`, {
      method: "DELETE",
    }),
  enrollments: (venueId: string) =>
    request<DeviceEnrollment[]>(`/platform/venues/${venueId}/enrollments`),
  createEnrollment: (
    venueId: string,
    input: { displayName: string; platform: string; ttlMinutes?: number },
  ) =>
    request<IssuedEnrollment>(`/platform/venues/${venueId}/enrollments`, {
      method: "POST",
      body: json(input),
    }),
  cancelEnrollment: (venueId: string, enrollmentId: string) =>
    request<DeviceEnrollment>(
      `/platform/venues/${venueId}/enrollments/${enrollmentId}`,
      { method: "DELETE" },
    ),
  devices: (venueId: string) =>
    request<Device[]>(`/platform/venues/${venueId}/devices`),
  createDevice: (
    venueId: string,
    input: { displayName: string; platform: string; installationId?: string },
  ) =>
    request<IssuedCredential>(`/platform/venues/${venueId}/devices`, {
      method: "POST",
      body: json(input),
    }),
  setDeviceStatus: (venueId: string, deviceId: string, status: DeviceStatus) =>
    request<Device>(`/platform/venues/${venueId}/devices/${deviceId}/status`, {
      method: "PUT",
      body: json({ status }),
    }),
  rotateCredential: (venueId: string, deviceId: string) =>
    request<IssuedCredential>(
      `/platform/venues/${venueId}/devices/${deviceId}/credential`,
      { method: "POST" },
    ),
  queueTestCommand: (venueId: string, deviceId?: string) =>
    request<QueuedCommand>(`/platform/venues/${venueId}/test-command`, {
      method: "POST",
      body: json({ deviceId }),
    }),
  readTestCommand: (venueId: string, commandId: string) =>
    request<import("./types").EdgeCommandStatus>(
      `/platform/venues/${venueId}/test-command/${commandId}`,
    ),
  audit: (limit = 50, offset = 0, targetId?: string, venueId?: string) => {
    const search = new URLSearchParams({ limit: String(limit), offset: String(offset) });
    if (targetId) search.set("targetId", targetId);
    if (venueId) search.set("venueId", venueId);
    return request<AuditEvent[]>(`/platform/audit?${search}`);
  },
};
