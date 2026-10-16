import { render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import Footer from "../../../vankisi-custom-web/src/components/Footer";
import { LanguageProvider } from "../../../vankisi-custom-web/src/contexts/LanguageContext";

import { WebsiteInfoProvider } from "../../../vankisi-custom-web/src/contexts/WebsiteInfoProvider";
import { vankisiSite } from "./vankisi-shared-info.fixture";
const apiGet = vi.hoisted(() => vi.fn());
vi.mock("../../../vankisi-custom-web/src/services/api", () => ({
  default: { get: apiGet },
}));

describe("WEB-07 Footer telephone matches the displayed restaurant number", () => {
  it.each(["ka", "en", "ru"])(
    "%s links to the visible phone, with no placeholder telephone",
    async (lang) => {
      apiGet.mockResolvedValue({ data: vankisiSite() });
      render(
        <MemoryRouter initialEntries={[`/${lang}`]}>
          <Routes>
            <Route
              path="/:lang"
              element={
                <LanguageProvider>
                  <WebsiteInfoProvider>
                    <Footer />
                  </WebsiteInfoProvider>
                </LanguageProvider>
              }
            />
          </Routes>
        </MemoryRouter>,
      );
      const footer = within(screen.getByRole("contentinfo"));
      const phone = await footer.findByRole("link", {
        name: "+995 599 98 93 76",
      });
      expect(phone).toHaveAttribute("href", "tel:+995599989376");
      expect(phone).toHaveTextContent("+995 599 98 93 76");
      const telephoneLinks = footer
        .getAllByRole("link")
        .filter((link) => link.getAttribute("href")?.startsWith("tel:"));
      expect(telephoneLinks).toEqual([phone]);
      expect(footer.getByRole("img", { name: "Vankisi Logo" })).toBeVisible();
    },
  );
});
