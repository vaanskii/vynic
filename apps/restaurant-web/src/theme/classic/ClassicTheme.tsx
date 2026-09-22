import type { ThemeProps } from "../registry";
import { Header, type NavTarget } from "./sections/Header";
import { Hero } from "./sections/Hero";
import { About } from "./sections/About";
import { Menu } from "./sections/Menu";
import { Gallery } from "./sections/Gallery";
import { Visit } from "./sections/Visit";
import { Footer } from "./sections/Footer";
import { paragraphs } from "./format";
import "./classic.css";

/**
 * The `classic` presentation.
 *
 * Section order is fixed — this is a theme, not a page builder — but each
 * section is responsible for removing itself when the restaurant has nothing
 * to put in it, so a sparse draft and a complete site are both coherent pages.
 */
export function ClassicTheme({
  site,
  menu,
  strings,
  language,
  onLanguage,
  origin,
}: ThemeProps) {
  const { content } = site;
  const hasAbout = paragraphs(content.about).length > 0;
  const hasVisit =
    content.workingHours.length > 0 ||
    content.socials.length > 0 ||
    !!site.profile.address ||
    !!site.profile.phone ||
    !!content.contactEmail;

  // Navigation offers only sections this restaurant actually renders.
  const targets: NavTarget[] = [
    hasAbout && { id: "about", label: strings.nav.about },
    content.showMenu && { id: "menu", label: strings.nav.menu },
    content.gallery.length > 0 && { id: "gallery", label: strings.nav.gallery },
    content.workingHours.length > 0 && {
      id: "hours",
      label: strings.nav.hours,
    },
    hasVisit && { id: "contact", label: strings.nav.contact },
  ].filter(Boolean) as NavTarget[];

  return (
    <>
      <a className="skip-link" href="#main">
        {strings.skipToContent}
      </a>
      <Header
        site={site}
        strings={strings}
        language={language}
        onLanguage={onLanguage}
        targets={targets}
        origin={origin}
      />
      <main id="main">
        <Hero site={site} origin={origin} />
        <About site={site} strings={strings} origin={origin} />
        <Menu
          site={site}
          menu={menu}
          strings={strings}
          language={language}
          origin={origin}
        />
        <Gallery site={site} strings={strings} origin={origin} />
        <Visit site={site} strings={strings} />
      </main>
      <Footer site={site} />
    </>
  );
}
