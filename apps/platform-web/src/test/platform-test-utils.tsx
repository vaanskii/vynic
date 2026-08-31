import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { vi } from "vitest";
import { AppRoutes } from "../App";
import { AuthProvider } from "../platform/auth";
import { platformSession } from "../platform/session";

export const ids = {
  organization: "11111111-1111-4111-8111-111111111111",
  venue: "22222222-2222-4222-8222-222222222222",
  plan: "33333333-3333-4333-8333-333333333333",
  device: "44444444-4444-4444-8444-444444444444",
  domain: "55555555-5555-4555-8555-555555555555",
  actor: "66666666-6666-4666-8666-666666666666",
};

export const actor = {
  platformUserId: ids.actor,
  email: "admin@vynic.test",
  displayName: "Platform Admin",
  role: "SUPER_ADMIN",
};

export const organization = {
  id: ids.organization,
  name: "Vankisi Group",
  createdAt: "2026-08-30T10:00:00.000Z",
  updatedAt: "2026-08-31T10:00:00.000Z",
  _count: { venues: 1 },
};

export const venue = {
  id: ids.venue,
  organizationId: ids.organization,
  name: "Vankisi",
  status: "ACTIVE",
  timezone: "Asia/Tbilisi",
  currency: "GEL",
  createdAt: "2026-08-30T10:00:00.000Z",
  updatedAt: "2026-08-31T10:00:00.000Z",
  organization: { id: ids.organization, name: organization.name },
};

export const plans = [{
  id: ids.plan,
  key: "FULL",
  name: "Full Platform",
  status: "ACTIVE",
  features: [
    { feature: { key: "POS", name: "Point of Sale" } },
    { feature: { key: "WEBSITE", name: "Website" } },
  ],
}];

export const features = [
  { id: "77777777-7777-4777-8777-777777777771", key: "POS", name: "Point of Sale" },
  { id: "77777777-7777-4777-8777-777777777772", key: "WEBSITE", name: "Website" },
  { id: "77777777-7777-4777-8777-777777777773", key: "MANAGER_APP", name: "Manager App" },
];

export const product = {
  venueId: ids.venue,
  plan: { id: ids.plan, key: "FULL", name: "Full Platform", status: "ACTIVE" },
  planAssignedAt: "2026-08-31T10:00:00.000Z",
  overrides: [{ featureKey: "MANAGER_APP", featureName: "Manager App", effect: "DISABLED", note: null, updatedAt: "2026-08-31T10:00:00.000Z" }],
  effectiveFeatures: ["POS", "WEBSITE"],
  website: { entitled: true, configuredMode: "SAAS", effectiveMode: "SAAS", consistent: true },
};

export const device = {
  id: ids.device,
  venueId: ids.venue,
  installationId: "88888888-8888-4888-8888-888888888888",
  displayName: "Front POS",
  platform: "WINDOWS",
  status: "ACTIVE",
  lastSeenAt: "2026-08-31T10:00:00.000Z",
  createdAt: "2026-08-30T10:00:00.000Z",
  updatedAt: "2026-08-31T10:00:00.000Z",
};

export const audit = [{
  id: "99999999-9999-4999-8999-999999999999",
  action: "venue.plan_assigned",
  targetType: "Venue",
  targetId: ids.venue,
  metadata: { to: "FULL" },
  createdAt: "2026-08-31T10:00:00.000Z",
  actor: { id: ids.actor, email: actor.email, displayName: actor.displayName },
}];

export interface MockRequest {
  url: URL;
  method: string;
  body: Record<string, unknown> | null;
}

export interface MockReply { status?: number; body?: unknown }
export type MockHandler = (request: MockRequest) => MockReply | undefined | Promise<MockReply | undefined>;

export function installApi(handler?: MockHandler) {
  const requests: MockRequest[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url, "http://vynic.test");
    const method = (init.method ?? "GET").toUpperCase();
    const body = typeof init.body === "string" ? JSON.parse(init.body) as Record<string, unknown> : null;
    const request = { url, method, body };
    requests.push(request);
    const custom = await handler?.(request);
    const reply = custom ?? defaultReply(request);
    return new Response(JSON.stringify(reply.body ?? null), {
      status: reply.status ?? 200,
      headers: { "Content-Type": "application/json" },
    });
  });
  vi.stubGlobal("fetch", fetchMock);
  return { requests, fetchMock };
}

function defaultReply({ url, method }: MockRequest): MockReply {
  const path = url.pathname;
  if (path === "/platform/auth/login" && method === "POST") return { body: { access_token: "test-token", expiresIn: 28800, actor } };
  if (path === "/platform/auth/me") return { body: actor };
  if (path === "/platform/organizations" && method === "GET") return { body: { total: 1, limit: 50, offset: 0, items: [organization] } };
  if (path === `/platform/organizations/${ids.organization}`) return { body: { ...organization, venues: [venue] } };
  if (path === "/platform/venues" && method === "GET") return { body: { total: 1, limit: 50, offset: 0, items: [venue] } };
  if (path === `/platform/venues/${ids.venue}`) return { body: venue };
  if (path === "/platform/plans") return { body: plans };
  if (path === "/platform/features") return { body: features };
  if (path === `/platform/venues/${ids.venue}/product`) return { body: product };
  if (path === `/platform/venues/${ids.venue}/domains`) return { body: [] };
  if (path === `/platform/venues/${ids.venue}/devices`) return { body: [device] };
  if (path.startsWith(`/platform/venues/${ids.venue}/test-command/`)) return { body: { commandId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", type: "NOOP", status: "PENDING", attemptCount: 0, maxAttempts: 10, claimedAt: null, acknowledgedAt: null, resultCode: null, resultDetail: null, createdAt: "2026-08-31T10:00:00.000Z", updatedAt: "2026-08-31T10:00:00.000Z", claimedBy: null, device: null } };
  if (path === "/platform/audit") return { body: audit };
  return { body: {} };
}

export function renderPlatform(route: string, options: { authenticated?: boolean } = {}) {
  if (options.authenticated !== false) platformSession.save("test-token", 28800);
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 0 }, mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[route]}>
        <AuthProvider><AppRoutes /></AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}
