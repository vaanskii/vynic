import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { Visit } from "../theme/classic/sections/Visit";
import { siteA } from "./fixtures";
import { strings } from "../i18n";

describe("Profile-based website location", () => {
  it("follows the current profile address when no exact pin is supplied", () => {
    render(
      <Visit
        site={{ ...siteA, content: { ...siteA.content, mapUrl: "" } }}
        strings={strings.en}
      />,
    );
    expect(
      screen.getByRole("link", { name: strings.en.contact.directions }),
    ).toHaveAttribute(
      "href",
      `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(siteA.profile.address!)}`,
    );
  });
  it("hides directions without hiding the restaurant address", () => {
    render(
      <Visit
        site={{ ...siteA, content: { ...siteA.content, showMap: false } }}
        strings={strings.en}
      />,
    );
    expect(
      screen.queryByRole("link", { name: strings.en.contact.directions }),
    ).toBeNull();
    expect(screen.getByText(siteA.profile.address!)).toBeVisible();
  });
  it("uses an exact pin when provided", () => {
    render(<Visit site={siteA} strings={strings.en} />);
    expect(
      screen.getByRole("link", { name: strings.en.contact.directions }),
    ).toHaveAttribute("href", siteA.content.mapUrl);
  });
});
