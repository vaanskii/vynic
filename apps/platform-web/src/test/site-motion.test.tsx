import { screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { markHeroIntroPlayed, shouldPlayHeroIntro } from "../lib/motion";
import { installApi, renderPublic } from "./platform-test-utils";

function mockMedia(matches: (query: string) => boolean) {
  vi.mocked(window.matchMedia).mockImplementation((query: string) => ({
    matches: matches(query),
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }));
}

// "(prefers-reduced-motion)" and "(prefers-reduced-motion: reduce)" mean the
// visitor asked for less motion; every other query is treated as matching.
const asksForReduce = (query: string) => /prefers-reduced-motion(: ?reduce)?\)/.test(query);
const noPreference = (query: string) => !asksForReduce(query);
const reduce = (query: string) => asksForReduce(query);

describe("public site motion", () => {
  afterEach(() => {
    mockMedia(() => false);
  });

  it("plays the opening once per session", () => {
    mockMedia(noPreference);

    expect(shouldPlayHeroIntro()).toBe(true);
    markHeroIntroPlayed();
    expect(shouldPlayHeroIntro()).toBe(false);
  });

  it("skips the opening for reduced motion and for deep links", () => {
    mockMedia(reduce);
    expect(shouldPlayHeroIntro()).toBe(false);

    mockMedia(noPreference);
    window.history.replaceState(null, "", "/en#contact");
    expect(shouldPlayHeroIntro()).toBe(false);
    window.history.replaceState(null, "", "/");
  });

  it("renders the full page statically with reduced motion", async () => {
    mockMedia(reduce);
    installApi();

    renderPublic("/en", { authenticated: false });

    // The accented headline keeps one plain accessible name.
    await screen.findByRole("heading", { level: 1, name: "Restaurant POS for the room as it runs" });
    // The shared site navigation still lands on these home anchors.
    for (const id of ["product", "manager", "floor-plan", "reservations", "contact"]) {
      expect(document.getElementById(id)).not.toBeNull();
    }
    expect(document.querySelector(".vh-portal-track[data-scrub]")).toBeNull();
    // The swipeable Manager phone is a plain, operable tab list.
    expect(screen.getAllByRole("tab", { selected: true })).toHaveLength(1);
    expect(screen.getByRole("tab", { name: /Close day/ })).toBeInTheDocument();
    expect(sessionStorage.getItem("vynic-site-intro")).toBeNull();
  });

  it("serves each product page under the language path", async () => {
    mockMedia(reduce);
    installApi();

    renderPublic("/en/pos", { authenticated: false });
    await screen.findByRole("heading", { level: 1, name: "Built for the rush." });
    // The real-screen tour on the POS page.
    expect(screen.getByRole("tab", { name: /Read the room before opening a check/ })).toBeInTheDocument();
  });

  it("serves the Georgian manager page", async () => {
    mockMedia(reduce);
    installApi();

    renderPublic("/ka/manager", { authenticated: false });
    await screen.findByRole("heading", { level: 1, name: "სამუშაო დღე შენს ჯიბეში." });
  });

  it("renders the floor scene statically with reduced motion", async () => {
    mockMedia(reduce);
    installApi();

    renderPublic("/en/floor-plan", { authenticated: false });
    const floor = await screen.findByRole("img", { name: "Vynic POS live floor" });
    expect(floor.closest("section")).not.toHaveClass("h-[340vh]");
  });
});
