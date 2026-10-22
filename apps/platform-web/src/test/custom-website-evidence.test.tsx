import { render, screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CustomWebsitePanel } from "../platform/pages/venue/CustomWebsitePanel";
import type { CustomWebsite, CustomWebsiteCheck } from "../platform/types";
const api = vi.hoisted(() => ({
  read: vi.fn(),
  check: vi.fn(),
  save: vi.fn(),
}));
vi.mock("../platform/api", () => ({
  platformApi: {
    customWebsite: api.read,
    checkCustomWebsite: api.check,
    updateCustomWebsite: api.save,
  },
}));
function venue(): CustomWebsite {
  return {
    venueId: "00000000-0000-4000-a000-000000000501",
    mode: "CUSTOM",
    effectiveMode: "CUSTOM",
    entitled: true,
    commercialStatus: "ACTIVE",
    trialEndsAt: null,
    status: "ACTIVE",
    siteKey: "custom-a-web",
    expectedBuildId: "a".repeat(64),
    publicIdentity: "1".repeat(64),
    statusNote: null,
    updatedAt: "2026-10-13T10:00:00.000Z",
    domains: [],
    primaryDomain: "synthetic.test.invalid",
    publicUrl: "https://synthetic.test.invalid/",
    menu: {
      authority: "CLOUD",
      editingEnabled: true,
      posIncluded: false,
      needsCloudAuthority: false,
    },
    payments: "NOT_INCLUDED",
    readiness: {
      complete: true,
      checks: {
        entitled: true,
        customMode: true,
        siteKey: true,
        activeDomain: true,
      },
    },
    audit: [],
  };
}
function observation(data = venue()): CustomWebsiteCheck {
  return {
    availability: "REACHABLE",
    checkedAt: "2026-10-13T10:01:00.000Z",
    hostname: data.primaryDomain!,
    url: data.publicUrl!,
    frontend: { status: 200, detail: "Frontend answers" },
    api: {
      state: "OK",
      status: 200,
      detail: "Stable Venue and CUSTOM binding match",
    },
    environment: "LOCAL_DEVELOPMENT",
    build: {
      state: "VERIFIED",
      status: 200,
      detail: "Compiled synthetic artifact matches",
      observedBuildId: data.expectedBuildId!,
      expectedBuildId: data.expectedBuildId!,
      siteKey: data.siteKey,
    },
    observationCurrent: true,
    checkedFor: {
      publicIdentity: data.publicIdentity!,
      mode: data.mode,
      siteKey: data.siteKey,
      expectedBuildId: data.expectedBuildId!,
      bindingUpdatedAt: data.updatedAt,
      status: data.status,
      entitled: data.entitled,
      hostname: data.primaryDomain!,
      domainActive: true,
    },
    facts: {
      commercial: true,
      domainRegistration: true,
      rendererDeployed: true,
      bindingIdentityVerified: true,
      publicationLive: true,
    },
  };
}
function show(data = venue()) {
  api.read.mockResolvedValue(data);
  const query = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={query}>
      <CustomWebsitePanel venueId={data.venueId} />
    </QueryClientProvider>,
  );
}
function fact(label: string) {
  return within(screen.getByRole("list", { name: "Deployment evidence" }))
    .getByText(label)
    .closest("li")!;
}
async function check() {
  await userEvent.click(
    await screen.findByRole("button", { name: "Check now" }),
  );
}
beforeEach(() => {
  api.read.mockReset();
  api.check.mockReset();
  api.save.mockReset();
});
describe("WEB05 operator evidence never equates configuration with deployed identity", () => {
  it("shows five separate facts and leaves deployment unknown before checking", async () => {
    show();
    await screen.findByRole("button", { name: "Check now" });
    expect(fact("Commercial access")).toHaveTextContent("Confirmed");
    expect(fact("Domain registration")).toHaveTextContent("Confirmed");
    for (const label of [
      "Renderer deployed",
      "Binding identity verified",
      "Publication live",
    ])
      expect(fact(label)).toHaveTextContent("Not verified");
  });
  it("valid reviewed evidence is visibly scoped to its observed environment", async () => {
    api.check.mockResolvedValue(observation());
    show();
    await check();
    await waitFor(() =>
      expect(fact("Binding identity verified")).toHaveTextContent("Confirmed"),
    );
    expect(fact("Publication live")).toHaveTextContent("Confirmed");
    expect(
      screen.getByText(/LOCAL_DEVELOPMENT.*not a production acceptance/),
    ).toBeVisible();
    expect(screen.getByText("a".repeat(64))).toBeVisible();
  });
  it.each(["WRONG_BUILD", "UNRECORDED", "FAILED"] as const)(
    "%s cannot borrow successful API or HTTP reachability",
    async (state) => {
      const result = observation();
      result.build!.state = state;
      result.facts!.bindingIdentityVerified = false;
      result.facts!.publicationLive = false;
      api.check.mockResolvedValue(result);
      show();
      await check();
      await waitFor(() =>
        expect(fact("Binding identity verified")).toHaveTextContent(
          "Not confirmed",
        ),
      );
      expect(fact("Publication live")).toHaveTextContent("Not confirmed");
    },
  );
  it.each(["foreign Venue", "changed build", "changed binding timestamp"])(
    "%s observation is stale even if its old facts were successful",
    async (kind) => {
      const result = observation();
      if (kind === "foreign Venue")
        result.checkedFor!.publicIdentity = "2".repeat(64);
      if (kind === "changed build")
        result.checkedFor!.expectedBuildId = "b".repeat(64);
      if (kind === "changed binding timestamp")
        result.checkedFor!.bindingUpdatedAt = "2026-10-13T09:00:00.000Z";
      api.check.mockResolvedValue(result);
      show();
      await check();
      expect(await screen.findByText(/observation is stale/)).toBeVisible();
      expect(fact("Binding identity verified")).toHaveTextContent(
        "Not verified",
      );
      expect(fact("Publication live")).toHaveTextContent("Not verified");
    },
  );
  it("an older backend answer remains explicitly unverified", async () => {
    const result = observation();
    delete result.checkedFor;
    delete result.build;
    delete result.facts;
    api.check.mockResolvedValue(result);
    show();
    await check();
    expect(
      await screen.findByText("Legacy answer; stable identity not verified"),
    ).toBeVisible();
    expect(fact("Renderer deployed")).toHaveTextContent("Not verified");
    expect(fact("Publication live")).toHaveTextContent("Not verified");
  });
  it("saving expected metadata clears prior evidence and sends only the intended fingerprint", async () => {
    const data = venue(),
      next = {
        ...data,
        expectedBuildId: "b".repeat(64),
        updatedAt: "2026-10-13T10:02:00.000Z",
      };
    api.check.mockResolvedValue(observation(data));
    api.save.mockResolvedValue(next);
    show(data);
    await check();
    await waitFor(() =>
      expect(fact("Publication live")).toHaveTextContent("Confirmed"),
    );
    const input = screen.getByRole("textbox", {
      name: /^Expected build fingerprint/,
    });
    await userEvent.clear(input);
    await userEvent.type(input, next.expectedBuildId);
    await userEvent.click(
      screen.getByRole("button", { name: "Save custom setup" }),
    );
    await screen.findByText("Custom website setup saved.");
    expect(api.save).toHaveBeenCalledWith(data.venueId, {
      expectedBuildId: next.expectedBuildId,
    });
    expect(fact("Publication live")).toHaveTextContent("Not verified");
  });
  it("a failed new check cannot preserve an older affirmative observation", async () => {
    api.check
      .mockResolvedValueOnce(observation())
      .mockRejectedValueOnce(new Error("Synthetic site unavailable"));
    show();
    await check();
    await waitFor(() =>
      expect(fact("Publication live")).toHaveTextContent("Confirmed"),
    );
    await check();
    expect(await screen.findByText("Synthetic site unavailable")).toBeVisible();
    expect(fact("Publication live")).toHaveTextContent("Not verified");
  });
  it("a delayed check started before a save cannot restore the prior verified build", async () => {
    const data = venue(),
      next = {
        ...data,
        expectedBuildId: "b".repeat(64),
        updatedAt: "2026-10-13T10:02:00.000Z",
      };
    let resolveCheck!: (value: CustomWebsiteCheck) => void;
    api.check.mockReturnValue(
      new Promise<CustomWebsiteCheck>((resolve) => {
        resolveCheck = resolve;
      }),
    );
    api.save.mockResolvedValue(next);
    show(data);
    await check();
    await waitFor(() => expect(api.check).toHaveBeenCalledTimes(1));
    const input = screen.getByRole("textbox", {
      name: /^Expected build fingerprint/,
    });
    await userEvent.clear(input);
    await userEvent.type(input, next.expectedBuildId);
    await userEvent.click(
      screen.getByRole("button", { name: "Save custom setup" }),
    );
    await screen.findByText("Custom website setup saved.");
    resolveCheck(observation(data));
    await waitFor(() => expect(screen.queryByText("Checking…")).toBeNull());
    expect(input).toHaveValue(next.expectedBuildId);
    expect(fact("Publication live")).toHaveTextContent("Not verified");
  });
  it("switching Venues cannot carry another Venue's draft or successful check", async () => {
    const a = venue(),
      b = {
        ...a,
        venueId: "00000000-0000-4000-a000-000000000502",
        siteKey: "custom-b-web",
        expectedBuildId: "b".repeat(64),
        publicIdentity: "2".repeat(64),
      };
    api.read.mockImplementation((id: string) =>
      Promise.resolve(id === a.venueId ? a : b),
    );
    api.check.mockResolvedValue(observation(a));
    const query = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    const view = render(
      <QueryClientProvider client={query}>
        <CustomWebsitePanel venueId={a.venueId} />
      </QueryClientProvider>,
    );
    await check();
    await waitFor(() =>
      expect(fact("Publication live")).toHaveTextContent("Confirmed"),
    );
    const draft = screen.getByRole("textbox", {
      name: /^Expected build fingerprint/,
    });
    await userEvent.clear(draft);
    await userEvent.type(draft, "c".repeat(64));
    view.rerender(
      <QueryClientProvider client={query}>
        <CustomWebsitePanel venueId={b.venueId} />
      </QueryClientProvider>,
    );
    await waitFor(() =>
      expect(
        screen.getByRole("textbox", { name: /^Expected build fingerprint/ }),
      ).toHaveValue(b.expectedBuildId),
    );
    expect(fact("Publication live")).toHaveTextContent("Not verified");
  });
});
