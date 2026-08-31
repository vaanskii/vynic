import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ids, installApi, renderPlatform } from "./platform-test-utils";

describe("platform directory", () => {
  it("loads organizations from the control-plane API", async () => {
    installApi();
    renderPlatform("/organizations");
    expect(await screen.findByText("Vankisi Group")).toBeVisible();
    expect(screen.getByText(ids.organization)).toBeVisible();
  });

  it("loads the venue directory", async () => {
    installApi();
    renderPlatform("/venues");
    expect(await screen.findByText("Vankisi")).toBeVisible();
    expect(screen.getByText("Asia/Tbilisi")).toBeVisible();
    expect(screen.getByText("GEL")).toBeVisible();
  });

  it("loads venue detail and ownership metadata", async () => {
    installApi();
    renderPlatform(`/venues/${ids.venue}`);
    expect(await screen.findByRole("heading", { name: "Vankisi" })).toBeVisible();
    expect(screen.getByText(ids.venue)).toBeVisible();
    expect(screen.getByText("Vankisi Group")).toBeVisible();
  });
});
