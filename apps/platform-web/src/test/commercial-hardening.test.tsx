import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AccessRequests } from "../platform/pages/AccessRequests";
import {
  actor,
  features,
  ids,
  installApi,
  renderPlatform,
} from "./platform-test-utils";

const lead = {
  id: "request-1",
  applicantName: "Owner",
  businessName: "Restaurant",
  email: "owner@test.invalid",
  phone: "555010123",
  status: "PENDING",
  createdAt: "2026-09-24",
  requestedVenueId: null,
};

describe("Commercial operator controls", () => {
  it("edits list price and features without offering non-fiscal close", async () => {
    const api = installApi((req) =>
      req.url.pathname === "/platform/features"
        ? {
            body: [
              ...features,
              { key: "NON_FISCAL_CLOSE", name: "Non-fiscal close" },
            ],
          }
        : undefined,
    );
    const user = userEvent.setup();
    renderPlatform("/admin/plans");
    await user.click(await screen.findByRole("button", { name: "Edit plan" }));
    expect(
      screen.queryByRole("checkbox", { name: "Non-fiscal close" }),
    ).toBeNull();
    await user.clear(screen.getByLabelText("Price"));
    await user.type(screen.getByLabelText("Price"), "79.50");
    await user.click(screen.getByRole("checkbox", { name: "Point of Sale" }));
    await user.click(screen.getByRole("button", { name: "Save plan" }));
    await waitFor(() =>
      expect(
        api.requests.some(
          (r) =>
            r.method === "PUT" &&
            r.url.pathname === `/platform/plans/${ids.plan}`,
        ),
      ).toBe(true),
    );
    expect(api.requests.find((r) => r.method === "PUT")?.body).toMatchObject({
      priceMinor: 7950,
      featureKeys: ["WEBSITE"],
      mediaQuotaFiles: 50,
    });
  });
  it("customer approval creates an invitation without an implicit trial assignment", async () => {
    let approved = false;
    const api = installApi((req) => {
      if (req.method === "POST") {
        approved = true;
        return {
          body: { prepared: { invitationPath: "/invite#token=test-only" } },
        };
      }
      return {
        body: approved
          ? [{ ...lead, status: "APPROVED", approvedVenueId: ids.venue }]
          : [lead],
      };
    });
    const user = userEvent.setup();
    render(
      <MemoryRouter>
        <AccessRequests readonly={false} plans={[]} />
      </MemoryRouter>,
    );
    await user.click(
      await screen.findByRole("button", { name: "Review approval" }),
    );
    await user.click(await screen.findByRole("button", { name: "Confirm review" }));
    expect(
      ((await screen.findByLabelText(/Owner invitation/)) as HTMLInputElement)
        .value,
    ).toContain("/invite#token=test-only");
    expect(api.requests.find((r) => r.method === "POST")?.body).toEqual({
      status: "APPROVED",
      outcome: "NO_PLAN",
      note: "",
    });
    expect(
      screen.getByRole("link", { name: "Manage plan and trial" }),
    ).toBeVisible();
  });
  it("trial approval requires an explicitly selected plan and end date in the submitted form", async () => {
    const api = installApi((req) => ({
      body:
        req.method === "GET" ? [{ ...lead, requestedVenueId: ids.venue }] : {},
    }));
    const user = userEvent.setup();
    render(
      <MemoryRouter>
        <AccessRequests
          readonly={false}
          plans={[
            { id: ids.plan, name: "Website trial", status: "ACTIVE" } as any,
          ]}
        />
      </MemoryRouter>,
    );
    await user.selectOptions(
      await screen.findByLabelText("Approved trial plan"),
      ids.plan,
    );
    await user.type(screen.getByLabelText("Trial ends"), "2099-12-31");
    await user.click(screen.getByRole("button", { name: "Review approval" }));
    await user.click(await screen.findByRole("button", { name: "Confirm review" }));
    await waitFor(() =>
      expect(api.requests.find((r) => r.method === "POST")?.body).toMatchObject(
        { status: "APPROVED", planId: ids.plan, trialEndsAt: "2099-12-31" },
      ),
    );
  });
  it("support can read requests and catalog but has no edit controls", async () => {
    installApi((req) =>
      req.url.pathname === "/platform/auth/me"
        ? { body: { ...actor, role: "SUPPORT_READONLY" } }
        : undefined,
    );
    renderPlatform("/admin/plans");
    await screen.findByText("Full Platform");
    expect(screen.queryByRole("button", { name: "Create plan" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Edit plan" })).toBeNull();
  });
});
