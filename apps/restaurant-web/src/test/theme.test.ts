import { describe, expect, it } from "vitest";
import { DEFAULT_THEME_KEY, themeFor } from "../theme/registry";
import { ClassicTheme } from "../theme/classic/ClassicTheme";
import { absolute } from "../seo/documentHead";
import { week, formatPrice, formatSize, paragraphs } from "../theme/classic/format";

describe("Theme registry", () => {
  it("resolves a published themeKey and falls back rather than rendering nothing", () => {
    expect(themeFor("classic")).toBe(ClassicTheme);
    expect(themeFor("retired-theme")).toBe(themeFor(DEFAULT_THEME_KEY));
  });
});

describe("Media references", () => {
  it("resolves managed paths against this site's origin and leaves external URLs alone", () => {
    expect(absolute("/media/sample/logo.svg", "https://a.example")).toBe(
      "https://a.example/media/sample/logo.svg",
    );
    expect(absolute("https://cdn.example/photo.jpg", "https://a.example")).toBe(
      "https://cdn.example/photo.jpg",
    );
    expect(absolute("", "https://a.example")).toBeNull();
  });
});

describe("Presentation formatting", () => {
  it("marks days without hours as closed and closing times as next-day", () => {
    const rows = week([
      { day: 1, opens: "11:00", closes: "01:00" },
      { day: 2, opens: "12:00", closes: "23:00" },
    ]);
    expect(rows).toHaveLength(7);
    expect(rows[0]).toMatchObject({ closed: false, overnight: true });
    expect(rows[1]).toMatchObject({ closed: false, overnight: false });
    expect(rows[6]).toMatchObject({ closed: true });
  });

  it("prices in the restaurant's currency and survives an unknown code", () => {
    expect(formatPrice(12.5, "GEL", "en")).toContain("12.50");
    expect(formatPrice(12.5, "NOT-A-CURRENCY", "en")).toBe(
      "12.50 NOT-A-CURRENCY",
    );
    expect(formatSize(0.75)).toBe("0.75");
    expect(formatSize(2)).toBe("2");
  });

  it("splits owner text into paragraphs without interpreting it", () => {
    expect(paragraphs("one\n\ntwo\n\n\n  three  ")).toEqual([
      "one",
      "two",
      "three",
    ]);
    expect(paragraphs("   ")).toEqual([]);
  });
});
