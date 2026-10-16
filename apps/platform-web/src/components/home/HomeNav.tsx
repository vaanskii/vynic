import { ArrowRight, List, X } from "@phosphor-icons/react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { hasCustomerSession } from "../../customer/api";
import { localeHref, useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { BrandMark } from "./primitives";
import { getHomeCopy } from "./homeCopy";
import { getSiteCopy, PAGE_ORDER } from "./siteCopy";

const ring = "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--vh-orchid)]";

/** Homepage navigation: glass bar that firms up once the page scrolls. */
export function HomeNav() {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale);
  const reduce = useReducedMotion();
  const headerRef = useRef<HTMLElement>(null);
  const [open, setOpen] = useState(false);
  const signedIn = hasCustomerSession();
  const base = localeHref(locale);
  const { pathname } = useLocation();
  const pages = getSiteCopy(locale).pages;
  // Same page in the other language.
  const rest = pathname.replace(/^\/(en|ka)/, "");
  const otherLanguage = `${localeHref(locale === "en" ? "ka" : "en")}${rest}`;

  useEffect(() => {
    const header = headerRef.current;
    if (!header) return;
    const update = () => {
      header.dataset.scrolled = String(window.scrollY > 12);
    };
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  const links = [
    ...PAGE_ORDER.map((key) => ({ label: pages[key].nav, href: `${base}/${pages[key].path}` })),
    { label: home.nav.contact, href: `${base}#contact` },
  ];
  const primary = signedIn
    ? { to: "/dashboard", label: copy.nav.dashboard }
    : { to: "/request-access", label: home.hero.cta };

  return (
    <header ref={headerRef} className="vh-nav sticky top-0 z-40 border-b border-transparent backdrop-blur-xl">
      <nav className="mx-auto flex h-16 max-w-[1320px] items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <Link to={base} className={`group flex shrink-0 items-center gap-2.5 rounded-[10px] ${ring}`} aria-label={copy.nav.homeLabel}>
          <span className="transition-transform duration-500 group-hover:rotate-[-8deg] group-hover:scale-110">
            <BrandMark size={32} />
          </span>
          <span className="vh-display text-[19px] text-[var(--vh-text)]">Vynic</span>
        </Link>

        <div className="hidden items-center gap-6 xl:flex">
          {links.map((link) => {
            const active = pathname === link.href;
            return (
              <Link
                key={link.href}
                to={link.href}
                aria-current={active ? "page" : undefined}
                className={`relative rounded-full px-3 py-1.5 text-[13px] transition-colors ${active ? "text-[var(--vh-text)]" : "text-[var(--vh-muted)] hover:text-[var(--vh-text)]"} ${ring}`}
              >
                {active ? (
                  <motion.span layoutId="vh-nav-active" className="absolute inset-0 rounded-full border border-[rgba(216,182,222,0.3)] bg-[rgba(118,75,124,0.22)]" transition={{ duration: 0.5, ease: curve.out }} />
                ) : null}
                <span className="relative">{link.label}</span>
              </Link>
            );
          })}
        </div>

        <div className="flex items-center gap-2.5 sm:gap-3">
          <span className="vh-chip vh-mono hidden items-center gap-2 rounded-full px-3 py-1.5 text-[11px] text-[var(--vh-soft)] md:inline-flex">
            <span className="vh-blink h-1.5 w-1.5 rounded-full bg-[var(--vh-sage)]" />
            {home.nav.status}
          </span>
          <a
            href={otherLanguage}
            className={`vh-mono hidden rounded-[8px] text-[11px] text-[var(--vh-muted)] transition-colors hover:text-[var(--vh-orchid)] sm:inline ${ring}`}
            aria-label="English / ქართული"
          >
            {locale.toUpperCase()} / {copy.nav.languageLabel}
          </a>
          {!signedIn ? (
            <a href="/login" className={`hidden text-[13px] text-[var(--vh-soft)] transition-colors hover:text-[var(--vh-text)] sm:inline ${ring}`}>
              {copy.nav.login}
            </a>
          ) : null}
          <Link
            to={primary.to}
            className={`vh-btn-primary group inline-flex h-9 items-center gap-1.5 rounded-full px-4 text-[13px] font-semibold text-white transition-transform active:scale-[0.97] ${ring}`}
          >
            {primary.label}
            <ArrowRight className="transition-transform group-hover:translate-x-0.5" size={14} weight="bold" />
          </Link>
          <button
            type="button"
            className={`vh-btn-ghost inline-flex h-9 w-9 items-center justify-center rounded-full text-[var(--vh-text)] xl:hidden ${ring}`}
            aria-label={open ? copy.nav.closeNav : copy.nav.openNav}
            aria-expanded={open}
            onClick={() => setOpen((value) => !value)}
          >
            {open ? <X size={18} weight="bold" /> : <List size={18} weight="bold" />}
          </button>
        </div>
      </nav>

      <AnimatePresence>
        {open ? (
          <motion.div
            key="menu"
            className="border-t border-[var(--vh-line)] bg-[var(--vh-bg-deep)]/95 px-4 pb-5 pt-3 xl:hidden"
            initial={reduce ? false : { opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, transition: { duration: 0 } }}
            transition={{ duration: 0.32, ease: curve.out }}
          >
            <div className="grid gap-1">
              {links.map((link) => (
                <Link
                  key={link.href}
                  to={link.href}
                  onClick={() => setOpen(false)}
                  className={`rounded-[10px] px-3 py-3 text-base text-[var(--vh-text)] transition-colors hover:bg-white/5 ${ring}`}
                >
                  {link.label}
                </Link>
              ))}
              <div className="mt-2 flex items-center gap-5 border-t border-[var(--vh-line)] px-3 pt-4">
                <a href={otherLanguage} className="vh-mono text-xs text-[var(--vh-muted)]">
                  {locale.toUpperCase()} / {copy.nav.languageLabel}
                </a>
                {!signedIn ? (
                  <a href="/login" className="text-sm text-[var(--vh-soft)]">
                    {copy.nav.login}
                  </a>
                ) : null}
              </div>
            </div>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </header>
  );
}
