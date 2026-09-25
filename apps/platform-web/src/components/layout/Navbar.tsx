import { List, X } from "@phosphor-icons/react";
import { useState } from "react";
import vynicLogo from "../../assets/vynic-logo.png";
import { hasCustomerSession } from "../../customer/api";
import { localeHref, useLocale } from "../../lib/i18n";
import { ButtonLink } from "../ui/Button";

const focusRing =
  "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-vynic-plum";

/**
 * Vynic product navigation. Visitors can request access or sign in; an owner who is
 * already signed in gets a direct way back to their dashboard.
 */
export function Navbar() {
  const [open, setOpen] = useState(false);
  const { copy, locale } = useLocale();
  const home = localeHref(locale);
  const signedIn = hasCustomerSession();
  const navItems = [
    { label: copy.nav.product, href: `${home}#product` },
    { label: copy.nav.floorPlan, href: `${home}#floor-plan` },
    { label: copy.nav.reservations, href: `${home}#reservations` },
    { label: copy.nav.manager, href: `${home}#manager` },
    { label: copy.nav.contact, href: `${home}#contact` },
  ];
  const close = () => setOpen(false);
  const primary = signedIn
    ? { to: "/dashboard", label: copy.nav.dashboard }
    : {
        to: "/request-access",
        label: locale === "ka" ? "გამოსცადე Vynic" : "Try Vynic",
      };

  return (
    <header className="sticky top-0 z-30 border-b border-vynic-border/80 bg-vynic-background/92 backdrop-blur-xl">
      <nav className="mx-auto flex h-14 max-w-7xl items-center justify-between gap-3 px-4 sm:px-6 lg:px-8">
        <a
          href={home}
          className={`flex shrink-0 items-center gap-3 rounded-[8px] text-vynic-charcoal ${focusRing}`}
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
              className={`whitespace-nowrap text-sm font-medium text-vynic-muted transition hover:text-vynic-charcoal focus-visible:rounded-[8px] ${focusRing}`}
            >
              {item.label}
            </a>
          ))}
        </div>

        <div className="flex min-w-0 shrink-0 items-center gap-3 xl:gap-4">
          <a
            href={localeHref(locale === "en" ? "ka" : "en")}
            className={`hidden rounded-[8px] font-vynic-mono text-xs font-semibold text-vynic-muted transition hover:text-vynic-plum xl:inline ${focusRing}`}
            aria-label="English / ქართული"
          >
            {locale.toUpperCase()} / {copy.nav.languageLabel}
          </a>
          {!signedIn && (
            <a href="/login" className={`text-sm ${focusRing}`}>
              {copy.nav.login}
            </a>
          )}
          <ButtonLink
            to={primary.to}
            className="min-h-9 px-3 py-2 sm:px-4"
            iconClassName="hidden sm:block"
          >
            {primary.label}
          </ButtonLink>
          <button
            className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-[8px] border border-vynic-border bg-vynic-surface text-vynic-charcoal transition hover:border-vynic-plum focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-vynic-plum xl:hidden"
            type="button"
            aria-label={open ? copy.nav.closeNav : copy.nav.openNav}
            aria-expanded={open}
            onClick={() => setOpen((value) => !value)}
          >
            {open ? (
              <X size={20} weight="bold" />
            ) : (
              <List size={20} weight="bold" />
            )}
          </button>
        </div>
      </nav>

      {open ? (
        <div className="border-t border-vynic-border bg-vynic-background px-4 py-4 xl:hidden">
          <div className="mx-auto grid max-w-7xl gap-2">
            {navItems.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className="rounded-[8px] px-3 py-3 text-base font-medium text-vynic-charcoal transition hover:bg-vynic-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-vynic-plum"
                onClick={close}
              >
                {item.label}
              </a>
            ))}
            <div className="mt-2 flex flex-wrap items-center gap-3 border-t border-vynic-border pt-4">
              <a
                href={localeHref(locale === "en" ? "ka" : "en")}
                className="font-vynic-mono text-xs font-semibold text-vynic-muted"
              >
                {locale.toUpperCase()} / {copy.nav.languageLabel}
              </a>
            </div>
          </div>
        </div>
      ) : null}
    </header>
  );
}
