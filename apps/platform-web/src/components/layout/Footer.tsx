import vynicLogo from "../../assets/vynic-logo.png";
import { localeHref, useLocale } from "../../lib/i18n";
import { Button } from "../ui/Button";

export function Footer() {
  const { copy, locale } = useLocale();
  const navItems = [
    { label: copy.nav.product, href: "#product" },
    { label: copy.nav.floorPlan, href: "#floor-plan" },
    { label: copy.nav.reservations, href: "#reservations" },
    { label: copy.nav.manager, href: "#manager" },
    { label: copy.nav.contact, href: "#contact" },
  ];
  return (
    <footer className="border-t border-vynic-border bg-vynic-surface">
      <div className="mx-auto grid max-w-7xl gap-8 px-4 py-10 sm:px-6 md:grid-cols-[1fr_auto] lg:px-8">
        <div>
          <a
            href="#top"
            className="inline-flex items-center gap-3 rounded-[8px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-vynic-plum"
          >
            <img className="h-9 w-9 rounded-[8px]" src={vynicLogo} alt="" />
            <span className="text-lg font-semibold text-vynic-charcoal">Vynic</span>
          </a>
          <p className="mt-4 max-w-md text-sm leading-6 text-vynic-muted">
            {locale === "ka" ? "რესტორნის POS და ოპერაციების პროგრამა მაგიდებისთვის, რეზერვაციებისთვის, გადახდებისთვის, დღის დახურვისა და მენეჯერის ხედვისთვის." : "Restaurant POS and operations software for tables, reservations, payments, close-day, and manager visibility."}
          </p>
        </div>

        <div className="flex flex-col gap-5 sm:flex-row sm:items-center">
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            {navItems.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className="text-sm font-medium text-vynic-muted transition hover:text-vynic-charcoal focus-visible:rounded-[8px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-vynic-plum"
              >
                {item.label}
              </a>
            ))}
          </div>
          <a href={localeHref(locale === "en" ? "ka" : "en")} className="font-vynic-mono text-xs font-semibold text-vynic-muted">{locale.toUpperCase()} / {copy.nav.languageLabel}</a>
          <Button href="#contact" className="w-fit">
            {copy.nav.bookDemo}
          </Button>
        </div>
      </div>
    </footer>
  );
}
