import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import {
  installApi,
  renderPublic,
  type MockHandler,
} from "./platform-test-utils";
import { customerLogout } from "../customer/api";

const success = "განაცხადი მიღებულია";
const requestPath = "/customer/access-requests";
const backend =
  (post?: MockHandler): MockHandler =>
  (req) => {
    if (req.url.pathname === `${requestPath}/plans`) return { body: [] };
    if (req.url.pathname === requestPath && req.method === "POST")
      return post?.(req) ?? { status: 201, body: { received: true } };
    return undefined;
  };
async function fillApplication() {
  const user = userEvent.setup();
  await user.type(
    await screen.findByLabelText("თქვენი სახელი"),
    "Synthetic visitor",
  );
  await user.type(
    screen.getByLabelText("რესტორნის / ბიზნესის სახელი"),
    "Synthetic restaurant",
  );
  await user.type(screen.getByLabelText("ელფოსტა"), "ux01@test.invalid");
  await user.type(screen.getByLabelText("ტელეფონი"), "fixture-phone");
  return user;
}
function showApplication(handler?: MockHandler) {
  customerLogout();
  const api = installApi(backend(handler));
  renderPublic("/request-access", { authenticated: false });
  return api;
}

describe("UX-01 active homepage → existing durable application", () => {
  it.each([
    ["ka", "დემოსთვის განაცხადი"],
    ["en", "Request a demo"],
  ])(
    "%s contact CTA navigates before collecting or sending data",
    async (locale, label) => {
      customerLogout();
      const api = installApi(backend());
      renderPublic(`/${locale}#contact`, { authenticated: false });
      const contact = document.getElementById("contact");
      expect(contact).not.toBeNull();
      const section = within(contact!);
      const link = section.getByRole("link", { name: label });
      expect(link).toHaveAttribute("href", "/request-access");
      expect(section.queryByRole("textbox")).toBeNull();
      expect(section.queryByRole("button")).toBeNull();
      expect(section.queryByRole("status")).toBeNull();
      expect(api.requests.filter((r) => r.method !== "GET")).toHaveLength(0);
      // Enter is native link navigation, not an invented submit action.
      link.focus();
      await userEvent.setup().keyboard("{Enter}");
      expect(
        await screen.findByRole("heading", { name: "გამოსცადე Vynic" }),
      ).toBeVisible();
      expect(screen.queryByRole("heading", { name: success })).toBeNull();
      expect(api.requests.filter((r) => r.method !== "GET")).toHaveLength(0);
    },
  );
  it("shows success only after POST resolves and prevents another submit while waiting", async () => {
    let release!: () => void;
    const pending = new Promise<void>((resolve) => {
      release = resolve;
    });
    const api = showApplication(async () => {
      await pending;
      return { status: 201, body: { received: true } };
    });
    const user = await fillApplication();
    await user.click(
      screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
    );
    await waitFor(() =>
      expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(1),
    );
    expect(screen.getByRole("button", { name: "იგზავნება…" })).toBeDisabled();
    expect(screen.queryByRole("heading", { name: success })).toBeNull();
    expect(api.requests.find((r) => r.method === "POST")?.body).toMatchObject({
      applicantName: "Synthetic visitor",
      businessName: "Synthetic restaurant",
      email: "ux01@test.invalid",
      phone: "fixture-phone",
    });
    release();
    const heading = await screen.findByRole("heading", { name: success });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(1);
    expect(
      screen.getByRole("link", { name: /მთავარ გვერდზე დაბრუნება/ }),
    ).toHaveAttribute("href", "/ka");
  });
  it.each([429, 503])(
    "HTTP %s keeps entered data and supports retry without claiming success",
    async (status) => {
      let posts = 0;
      const api = showApplication(() =>
        ++posts === 1
          ? { status, body: { message: "Synthetic request failure" } }
          : { status: 201, body: { received: true } },
      );
      const user = await fillApplication();
      await user.click(
        screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
      );
      expect(await screen.findByRole("alert")).toHaveTextContent(
        "Synthetic request failure",
      );
      expect(screen.queryByRole("heading", { name: success })).toBeNull();
      expect(screen.getByLabelText("ელფოსტა")).toHaveValue("ux01@test.invalid");
      await user.click(
        screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
      );
      expect(
        await screen.findByRole("heading", { name: success }),
      ).toBeVisible();
      expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(2);
    },
  );
  it("network failure stays an error with the form intact", async () => {
    showApplication(() => {
      throw new TypeError("Synthetic network unavailable");
    });
    const user = await fillApplication();
    await user.click(
      screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
    );
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Synthetic network unavailable",
    );
    expect(screen.queryByRole("heading", { name: success })).toBeNull();
    expect(screen.getByLabelText("თქვენი სახელი")).toHaveValue(
      "Synthetic visitor",
    );
  });
  it("retains the existing already-persisted pending request response", async () => {
    const api = showApplication(() => ({
      status: 409,
      body: { message: "A request is already awaiting review" },
    }));
    const user = await fillApplication();
    await user.click(
      screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
    );
    expect(await screen.findByRole("heading", { name: success })).toBeVisible();
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(1);
  });
  it("an unrelated conflict is not turned into application success", async () => {
    showApplication(() => ({
      status: 409,
      body: { message: "Synthetic different conflict" },
    }));
    const user = await fillApplication();
    await user.click(
      screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
    );
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Synthetic different conflict",
    );
    expect(screen.queryByRole("heading", { name: success })).toBeNull();
  });
  it("missing required contact fields never send an application", async () => {
    const api = showApplication();
    await screen.findByLabelText("თქვენი სახელი");
    await userEvent
      .setup()
      .click(screen.getByRole("button", { name: "განაცხადის გაგზავნა" }));
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(0);
    expect(screen.getByLabelText("ელფოსტა")).toBeInvalid();
    expect(screen.queryByRole("heading", { name: success })).toBeNull();
  });
  it("unavailable plans do not pretend to save or block the existing plan-less request", async () => {
    customerLogout();
    const api = installApi((req) =>
      req.url.pathname === `${requestPath}/plans`
        ? { status: 503, body: { message: "Synthetic plans unavailable" } }
        : backend()(req),
    );
    renderPublic("/request-access", { authenticated: false });
    const user = await fillApplication();
    expect(screen.queryByRole("heading", { name: success })).toBeNull();
    await user.click(
      screen.getByRole("button", { name: "განაცხადის გაგზავნა" }),
    );
    expect(await screen.findByRole("heading", { name: success })).toBeVisible();
    expect(api.requests.filter((r) => r.method === "POST")).toHaveLength(1);
  });
});
