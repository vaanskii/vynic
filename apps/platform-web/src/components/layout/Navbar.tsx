import { List, X } from "@phosphor-icons/react";
import { useState } from "react";
import vynicLogo from "../../assets/vynic-logo.png";
import { localeHref, useLocale } from "../../lib/i18n";
import { Button } from "../ui/Button";

export function Navbar() {
  const [open, setOpen] = useState(false);
  const { copy, locale } = useLocale();
  const navItems = [
    { label: copy.nav.product, href: "#product" },
    { label: copy.nav.floorPlan, href: "#floor-plan" },
    { label: copy.nav.reservations, href: "#reservations" },
    { label: copy.nav.manager, href: "#manager" },
    { label: copy.nav.contact, href: "#contact" },
  ];

  return (
    <header className="sticky top-0 z-30 border-b border-vynic-border/80 bg-vynic-background/92 backdrop-blur-xl">
      <nav className="mx-auto flex h-14 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <a
          href={localeHref(locale)}
          className="flex shrink-0 items-center gap-3 rounded-[8px] text-vynic-charcoal focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-vynic-plum"
          aria-label={copy.nav.homeLabel}
        >
          <img className="h-8 w-8 rounded-[8px]" src={vynicLogo} alt="" />
          <span className="text-base font-semibold tracking-normal">Vynic</span>
          <span className="hidden items-center gap-2 border-l border-vynic-border pl-3 font-vynic-mono text-[10px] font-semibold tracking-[0.1em] text-vynic-muted sm:flex">
            <span className="h-1.5 w-1.5 rounded-full bg-vynic-green" />
            {copy.nav.serviceReady}
          </span>
        </a>

        <div className="hidden min-w-0 items-center justify-center gap-5 xl:flex">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="whitespace-nowrap text-sm font-medium text-vynic-muted transition hover:text-vynic-charcoal focus-visible:rounded-[8px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-vynic-plum"
            >
              {item.label}
            </a>
          ))}
        </div>

        <div className="hidden shrink-0 items-center gap-4 xl:flex">
          <a
            href={localeHref(locale === "en" ? "ka" : "en")}
            className="rounded-[8px] font-vynic-mono text-xs font-semibold text-vynic-muted transition hover:text-vynic-plum focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-vynic-plum"
            aria-label="English / ქართული"
          >
            {locale.toUpperCase()} / {copy.nav.languageLabel}
          </a>
          <Button href="#contact" className="min-h-9 px-4 py-2">
            {copy.nav.bookDemo}
          </Button>
        </div>

        <button
          className="inline-flex h-10 w-10 items-center justify-center rounded-[8px] border border-vynic-border bg-vynic-surface text-vynic-charcoal transition hover:border-vynic-plum focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-vynic-plum xl:hidden"
          type="button"
          aria-label={open ? copy.nav.closeNav : copy.nav.openNav}
          aria-expanded={open}
          onClick={() => setOpen((value) => !value)}
        >
          {open ? <X size={20} weight="bold" /> : <List size={20} weight="bold" />}
        </button>
      </nav>

      {open ? (
        <div className="border-t border-vynic-border bg-vynic-background px-4 py-4 xl:hidden">
          <div className="mx-auto grid max-w-7xl gap-2">
            {navItems.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className="rounded-[8px] px-3 py-3 text-base font-medium text-vynic-charcoal transition hover:bg-vynic-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-vynic-plum"
                onClick={() => setOpen(false)}
              >
                {item.label}
              </a>
            ))}
            <div className="mt-2 flex flex-wrap items-center gap-3 border-t border-vynic-border pt-4">
              <a href={localeHref(locale === "en" ? "ka" : "en")} className="font-vynic-mono text-xs font-semibold text-vynic-muted">
                {locale.toUpperCase()} / {copy.nav.languageLabel}
              </a>
              <Button href="#contact" onClick={() => setOpen(false)}>
                {copy.nav.bookDemo}
              </Button>
            </div>
          </div>
        </div>
      ) : null}
    </header>
  );
}
