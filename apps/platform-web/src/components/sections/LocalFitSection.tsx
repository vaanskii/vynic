import {
  Bank,
  CalendarCheck,
  ClockCounterClockwise,
  CurrencyCircleDollar,
  Translate,
} from "@phosphor-icons/react";
import restaurantContext from "../../assets/restaurant-service-context.png";
import { getLocalizedContent } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";
import { Reveal } from "../ui/Reveal";
import { SectionHeading } from "../ui/SectionHeading";

const icons = [Translate, CurrencyCircleDollar, Bank, CalendarCheck, ClockCounterClockwise];

const toneClass: Record<string, string> = {
  plum: "bg-[color-mix(in_srgb,var(--vynic-plum)_13%,var(--vynic-surface))]",
  green: "bg-[color-mix(in_srgb,var(--vynic-green)_15%,var(--vynic-surface))]",
  amber: "bg-[color-mix(in_srgb,var(--vynic-amber)_16%,var(--vynic-surface))]",
  charcoal: "bg-[color-mix(in_srgb,var(--vynic-charcoal)_7%,var(--vynic-surface))]",
};

export function LocalFitSection() {
  const { locale, copy } = useLocale();
  const localFitItems = getLocalizedContent(locale).localFitItems;
  return (
    <section className="px-4 py-20 sm:px-6 lg:px-8 lg:py-28">
      <div className="mx-auto max-w-7xl">
        <SectionHeading
          title={copy.local.title}
          body={copy.local.body}
        />

        <div className="mt-12 grid gap-5 lg:grid-cols-12">
          <Reveal className="lg:col-span-6 lg:row-span-2">
            <figure className="h-full overflow-hidden rounded-[8px] border border-vynic-border bg-vynic-surface">
              <img
                src={restaurantContext}
                alt={locale === "ka" ? "რესტორნის გუნდი დარბაზს და POS გადახდის ტერმინალს ამზადებს" : "Restaurant staff preparing a dining room with POS and payment terminal context"}
                className="h-full min-h-[360px] w-full object-cover"
                loading="lazy"
              />
            </figure>
          </Reveal>

          <div className="grid gap-5 sm:grid-cols-2 lg:col-span-6">
            {localFitItems.map((item, index) => {
              const IconComponent = icons[index];
              const featured = index === 0;

              return (
                <Reveal key={item.title} delay={index * 0.05} className={featured ? "sm:col-span-2" : ""}>
                  <article
                      className={`min-h-full rounded-[8px] border border-vynic-border p-5 ${
                      featured ? "bg-[#22201E] text-[#F7F6F4]" : `vynic-neu-surface ${toneClass[item.tone]}`
                    }`}
                  >
                    <IconComponent
                      className={featured ? "text-[#B9A8C4]" : "text-vynic-plum"}
                      size={22}
                      weight="duotone"
                    />
                    <h3
                      className={`mt-4 text-lg font-semibold ${
                        featured ? "text-[#F7F6F4]" : "text-vynic-charcoal"
                      }`}
                    >
                      {item.title}
                    </h3>
                    <p
                      className={`mt-3 text-sm leading-6 ${
                        featured ? "text-[#D8D0C9]" : "text-vynic-muted"
                      }`}
                    >
                      {item.body}
                    </p>
                  </article>
                </Reveal>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
