import { useEffect, useId, useState } from "react";
import type { Language, Strings } from "../../../i18n";
import { languages } from "../../../i18n";
import type { WebsiteSite } from "../../../api/types";
import { absolute } from "../../../seo/documentHead";

export interface NavTarget {
  id: string;
  label: string;
}

/**
 * Brand, in-page navigation and the language switch.
 *
 * Navigation lists only the sections this restaurant actually published, so a
 * site without a gallery has no link that scrolls to nothing.
 */
export function Header({
  site,
  strings,
  language,
  onLanguage,
  targets,
  origin,
}: {
  site: WebsiteSite;
  strings: Strings;
  language: Language;
  onLanguage: (language: Language) => void;
  targets: NavTarget[];
  origin: string;
}) {
  const [open, setOpen] = useState(false);
  const navId = useId();
  const { profile, content } = site;
  const logo = absolute(content.logoUrl, origin);

  useEffect(() => {
    if (!open) return;
    const close = (event: KeyboardEvent) =>
      event.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [open]);

  return (
    <header className="site-header">
      <div className="shell site-header__bar">
        <a className="site-header__brand" href="#top">
          {logo && <img src={logo} alt="" />}
          <span className="site-header__name">
            {profile.name}
            {profile.branchName && (
              <span className="site-header__branch">{profile.branchName}</span>
            )}
          </span>
        </a>

        {targets.length > 0 && (
          <button
            type="button"
            className="nav-toggle"
            aria-expanded={open}
            aria-controls={navId}
            onClick={() => setOpen((value) => !value)}
          >
            {open ? strings.closeMenu : strings.openMenu}
          </button>
        )}

        <nav
          id={navId}
          className="site-nav"
          data-open={open}
          aria-label={strings.nav.menu}
        >
          <ul>
            {targets.map((target) => (
              <li key={target.id}>
                <a href={`#${target.id}`} onClick={() => setOpen(false)}>
                  {target.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div
          className="language-toggle"
          role="group"
          aria-label={strings.languageLabel}
        >
          {languages.map((code) => (
            <button
              key={code}
              type="button"
              lang={code}
              aria-pressed={language === code}
              onClick={() => onLanguage(code)}
            >
              {code === "ka" ? "ქარ" : "EN"}
              <span className="visually-hidden">
                {" "}
                {strings.languageNames[code]}
              </span>
            </button>
          ))}
        </div>
      </div>
    </header>
  );
}
