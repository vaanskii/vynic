import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { LOCALE_STORAGE_KEY } from "../lib/i18n";
import { installApi, renderPlatform } from "./platform-test-utils";

describe("public language routing", () => {
  it("redirects the root to the saved language", async () => {
    installApi();
    localStorage.setItem(LOCALE_STORAGE_KEY, "ka");

    renderPlatform("/", { authenticated: false });

    expect(await screen.findByRole("heading", { name: "რესტორნის POS — დარბაზის მართვა" })).toBeInTheDocument();
  });

  it("saves an explicit language route for the next root visit", async () => {
    installApi();

    renderPlatform("/en", { authenticated: false });

    await screen.findByRole("heading", { name: "Restaurant POS for the room as it runs" });
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe("en");
  });
});
