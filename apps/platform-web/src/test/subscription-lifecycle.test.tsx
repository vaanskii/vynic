import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";
import { SubscriptionSection } from "../customer/SubscriptionSection";
import { SubscriptionPanel } from "../platform/pages/venue/SubscriptionPanel";
import { AccessRequests } from "../platform/pages/AccessRequests";
import { installApi, ids } from "./platform-test-utils";
import type { ComponentProps } from "react";
import type { VenueStatus } from "../customer/portal-types";
import type { BillingQuote, SubscriptionDetail } from "../subscriptions/types";
const venue = {
  venue: { id: ids.venue },
  plan: { name: "Website" },
  features: ["WEBSITE"],
  managers: [],
  devices: [],
  enrollments: [],
  checklist: {},
  ready: true,
} as unknown as VenueStatus;
const plans = [
  {
    id: "web",
    name: "Website",
    status: "ACTIVE",
    priceMinor: 5000,
    currency: "GEL",
    billingPeriod: "MONTH",
  },
  {
    id: "full",
    name: "Full",
    status: "ACTIVE",
    priceMinor: 15000,
    currency: "GEL",
    billingPeriod: "MONTH",
  },
];
const active = {
  status: "ACTIVE",
  billingManaged: true,
  currentPeriodEndsAt: "2027-10-25T12:00:00Z",
  billingAnchorAt: "2027-09-25T12:00:00Z",
  assignment: {
    planId: "web",
    plan: { name: "Website" },
    agreedPriceMinor: 5000,
    agreedCurrency: "GEL",
    agreedBillingPeriod: "MONTH",
  },
};
function serve(initial: SubscriptionDetail, quote?: BillingQuote) {
  let sub = initial;
  return installApi((req) => {
    if (req.url.pathname.endsWith("/plans")) return { body: plans };
    if (req.url.pathname.endsWith("/subscription/quote"))
      return { body: quote };
    if (req.url.pathname.endsWith("/subscription/actions")) {
      if (req.body?.action === "SCHEDULE_CANCEL")
        sub = { ...sub, cancelAtPeriodEnd: true };
      if (req.body?.action === "UNDO_CANCEL")
        sub = { ...sub, cancelAtPeriodEnd: false };
      if (req.body?.action === "CANCEL_CHANGE")
        sub = { ...sub, pendingPlan: null };
      return { body: {} };
    }
    if (req.url.pathname.endsWith("/subscription/manual-success"))
      return { body: {} };
    if (req.url.pathname.endsWith("/subscription")) return { body: sub };
    return undefined;
  });
}
const customer = () =>
  render(
    <MemoryRouter>
      <SubscriptionSection venue={venue} />
    </MemoryRouter>,
  );
const admin = (canEdit = true) =>
  render(
    <QueryClientProvider
      client={
        new QueryClient({ defaultOptions: { queries: { retry: false } } })
      }
    >
      <SubscriptionPanel venueId={ids.venue} canEdit={canEdit} />
    </QueryClientProvider>,
  );
describe("Commercial lifecycle UI", () => {
  it("shows an approved Trial and no second Trial request", async () => {
    serve({ ...active, status: "TRIAL", trialEndsAt: "2027-10-08T12:00:00Z" });
    customer();
    expect(await screen.findByText("საცდელი პერიოდი")).toBeVisible();
    expect(screen.getByText(/საცდელი პერიოდი აქტიურია/)).toBeVisible();
    expect(screen.getByText("ფასიან პაკეტზე გადასვლა")).toBeVisible();
    expect(screen.queryByText("მოითხოვეთ საცდელი პერიოდი")).toBeNull();
  });
  it("offers Trial requests only to NO_PLAN customers", async () => {
    serve({ status: "NO_PLAN" });
    customer();
    expect(await screen.findByText("მოითხოვეთ საცდელი პერიოდი")).toBeVisible();
  });
  it.each(["SUSPENDED", "CANCELLED", "PAST_DUE", "ACTIVE"])(
    "never solicits a duplicate Trial in %s",
    async (status) => {
      serve({ ...active, status });
      customer();
      await screen.findByText("Website");
      expect(screen.queryByText("მოითხოვეთ საცდელი პერიოდი")).toBeNull();
    },
  );
  it("shows current and next plans and cancels a pending downgrade", async () => {
    const api = serve({
      ...active,
      assignment: { ...active.assignment, plan: { name: "Full" } },
      pendingPlan: { id: "web", name: "Website" },
      pendingChangeAt: active.currentPeriodEndsAt,
      pendingPriceMinor: 5000,
      pendingCurrency: "GEL",
    });
    customer();
    const user = userEvent.setup();
    await screen.findByText("Full");
    expect(screen.getByText(/შემდეგი პაკეტი: Website/)).toBeVisible();
    await user.click(
      screen.getByRole("button", { name: "ცვლილების გაუქმება" }),
    );
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(0);
    await user.click(screen.getByRole("button", { name: "დადასტურება" }));
    await waitFor(() =>
      expect(api.requests.some((r) => r.body?.action === "CANCEL_CHANGE")).toBe(
        true,
      ),
    );
  });
  it("schedules cancellation only after confirmation and offers keep subscription", async () => {
    const api = serve(active);
    customer();
    const user = userEvent.setup();
    await user.click(
      await screen.findByRole("button", { name: "გამოწერის გაუქმება" }),
    );
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(0);
    await user.click(screen.getByRole("button", { name: "დადასტურება" }));
    await user.click(
      await screen.findByRole("button", { name: "გამოწერის შენარჩუნება" }),
    );
    await user.click(screen.getByRole("button", { name: "დადასტურება" }));
    await waitFor(() =>
      expect(api.requests.some((r) => r.body?.action === "UNDO_CANCEL")).toBe(
        true,
      ),
    );
  });
  it("displays server proration without a browser payment-success request", async () => {
    const api = serve(active, {
      id: "quote",
      kind: "UPGRADE",
      planId: "full",
      planName: "Full",
      amountMinor: 4321,
      priceMinor: 15000,
      currency: "GEL",
      billingPeriod: "MONTH",
    });
    customer();
    const user = userEvent.setup();
    await screen.findByText("Website");
    await user.selectOptions(screen.getByLabelText("პაკეტი"), "full");
    await user.click(screen.getByRole("button", { name: "პირობების ნახვა" }));
    expect(await screen.findByText("გადასახდელი: 43.21 GEL")).toBeVisible();
    expect(
      api.requests
        .filter((r) => r.method === "POST")
        .map((r) => r.url.pathname),
    ).toEqual([`/customer/venues/${ids.venue}/subscription/quote`]);
  });
  it("requires a payment reference and confirmation for operator manual success", async () => {
    const api = serve(active, {
      id: "quote",
      kind: "UPGRADE",
      planId: "full",
      planName: "Full",
      amountMinor: 5000,
      priceMinor: 15000,
      currency: "GEL",
      billingPeriod: "MONTH",
    });
    admin();
    const user = userEvent.setup();
    await user.selectOptions(
      await screen.findByLabelText("Commercial action"),
      "QUOTE",
    );
    await user.selectOptions(screen.getByLabelText("Plan"), "full");
    await user.type(
      screen.getByLabelText("Operator reason"),
      "Bank transfer checked",
    );
    await user.click(screen.getByRole("button", { name: "Calculate quote" }));
    expect(
      await screen.findByRole("button", { name: "Confirm manual payment…" }),
    ).toBeDisabled();
    await user.type(
      screen.getByLabelText("External payment reference"),
      "receipt-001",
    );
    await user.click(
      screen.getByRole("button", { name: "Confirm manual payment…" }),
    );
    expect(
      api.requests.some((r) => r.url.pathname.endsWith("manual-success")),
    ).toBe(false);
    await user.click(
      screen.getByRole("button", { name: "Record verified payment" }),
    );
    await waitFor(() =>
      expect(
        api.requests.find((r) => r.url.pathname.endsWith("manual-success"))
          ?.body,
      ).toMatchObject({
        operationId: "quote",
        reference: "receipt-001",
        confirm: true,
        reason: "Bank transfer checked",
      }),
    );
  });
  it("support can inspect the agreement without mutation controls", async () => {
    serve(active);
    admin(false);
    expect(await screen.findByText("Website")).toBeVisible();
    expect(screen.queryByLabelText("Commercial action")).toBeNull();
  });
  it("original public review previews Trial provisioning before approval", async () => {
    const api = installApi((req) => ({
      body:
        req.method === "GET"
          ? [
              {
                id: "lead",
                businessName: "Cafe",
                applicantName: "Owner",
                email: "owner@test.invalid",
                phone: "555",
                status: "PENDING",
                createdAt: "2026-09-25",
              },
            ]
          : {},
    }));
    render(
      <MemoryRouter>
        <AccessRequests readonly={false} plans={plans as unknown as ComponentProps<typeof AccessRequests>["plans"]} />
      </MemoryRouter>,
    );
    const user = userEvent.setup();
    await user.selectOptions(
      await screen.findByLabelText("Approval outcome"),
      "TRIAL",
    );
    await user.selectOptions(
      screen.getByLabelText("Approved trial plan"),
      "web",
    );
    await user.type(screen.getByLabelText("Trial ends"), "2099-10-08");
    await user.click(screen.getByRole("button", { name: "Review approval" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getAllByText(/Website Trial/)[0]).toBeVisible();
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(0);
    await user.click(
      within(dialog).getByRole("button", { name: "Confirm review" }),
    );
    await waitFor(() =>
      expect(api.requests.find((r) => r.method === "POST")?.body).toMatchObject(
        {
          outcome: "TRIAL",
          planId: "web",
          trialEndsAt: "2099-10-08",
          status: "APPROVED",
        },
      ),
    );
  });
});
