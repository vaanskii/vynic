import { ArrowRight } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { localeHref, useLocale } from "../../lib/i18n";
import { getHomeCopy } from "./homeCopy";
import { BrandMark, Rise, SectionOpen } from "./primitives";
import { getSiteCopy, PAGE_ORDER } from "./siteCopy";

/** The homepage opens the existing application flow; only that flow submits. */
export function HomeContact() {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale);

  return (
    <section
      id="contact"
      className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32"
    >
      <div className="mx-auto max-w-[1320px]">
        <SectionOpen
          kicker={home.contact.kicker}
          title={home.contact.title}
          body={copy.form.body}
        />
        <div className="mt-14 grid grid-cols-[minmax(0,1fr)] gap-8 lg:grid-cols-[0.8fr_1.2fr] lg:gap-14">
          <Rise>
            <ol className="grid">
              {copy.form.steps.map((step) => (
                <li
                  key={step.number}
                  className="grid grid-cols-[44px_1fr] gap-4 border-t border-[var(--vh-line)] py-5 last:border-b"
                >
                  <span className="vh-mono text-[11px] text-[var(--vh-orchid)]">
                    {step.number}
                  </span>
                  <div>
                    <p className="text-[15px] font-medium text-[var(--vh-text)]">
                      {step.title}
                    </p>
                    <p className="mt-1 text-[13px] leading-6 text-[var(--vh-muted)]">
                      {step.body}
                    </p>
                  </div>
                </li>
              ))}
            </ol>
          </Rise>
          <Rise y={36} delay={0.08}>
            <div className="vh-glass rounded-[20px] p-5 sm:p-7">
              <h3 className="vh-display text-2xl text-[var(--vh-text)]">
                {home.contact.requestTitle}
              </h3>
              <p className="mt-4 max-w-lg text-[15px] leading-7 text-[var(--vh-muted)]">
                {home.contact.requestBody}
              </p>
              <Link
                to="/request-access"
                className="vh-btn-primary group mt-6 inline-flex min-h-11 items-center gap-2 rounded-full px-5 py-3 text-sm font-semibold text-white transition-transform active:scale-[0.97] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--vh-orchid)]"
              >
                {home.contact.requestCta}
                <ArrowRight
                  aria-hidden="true"
                  className="shrink-0 transition-transform group-hover:translate-x-0.5"
                  size={15}
                  weight="bold"
                />
              </Link>
            </div>
          </Rise>
        </div>
      </div>
    </section>
  );
}

export function HomeFooter() {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale);
  const pages = getSiteCopy(locale).pages;
  const base = localeHref(locale);
  const links = [
    ...PAGE_ORDER.map((key) => ({ label: pages[key].nav, href: `${base}/${pages[key].path}` })),
    { label: home.nav.contact, href: `${base}#contact` },
  ];
  return (
    <footer className="relative border-t border-[var(--vh-line)] bg-[var(--vh-bg-deep)]/80 px-4 pb-10 pt-16 backdrop-blur sm:px-6 lg:px-8">
      <div className="mx-auto grid max-w-[1320px] gap-10 md:grid-cols-[1fr_auto]">
        <div>
          <Link to={base} className="inline-flex items-center gap-2.5">
            <BrandMark size={36} />
            <span className="vh-display text-2xl text-[var(--vh-text)]">Vynic</span>
          </Link>
          <p className="mt-4 max-w-md text-[13px] leading-6 text-[var(--vh-muted)]">{home.footer.line}</p>
        </div>
        <div className="flex flex-col gap-5 md:items-end">
          <div className="flex flex-wrap gap-x-6 gap-y-3">
            {links.map((link) => (
              <Link key={link.href} to={link.href} className="vh-nav-link text-[13px] text-[var(--vh-muted)] transition-colors hover:text-[var(--vh-text)]">
                {link.label}
              </Link>
            ))}
          </div>
          <a href={localeHref(locale === "en" ? "ka" : "en")} className="vh-mono text-[11px] text-[var(--vh-faint)] hover:text-[var(--vh-orchid)]">
            {locale.toUpperCase()} / {copy.nav.languageLabel}
          </a>
        </div>
      </div>
      <p className="mx-auto mt-14 max-w-[1320px] vh-display select-none text-[24vw] leading-[0.8] text-transparent [-webkit-text-stroke:1px_rgba(247,246,244,0.07)] lg:text-[20rem]" aria-hidden="true">
        Vynic
      </p>
    </footer>
  );
}
