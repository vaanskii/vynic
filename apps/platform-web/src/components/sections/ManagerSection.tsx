import { DeviceMobile, LockKey, Monitor } from "@phosphor-icons/react";
import { getLocalizedContent, screenshots } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";
import { ProductScreenshot } from "../product/ProductScreenshot";
import { Reveal } from "../ui/Reveal";
import { SectionHeading } from "../ui/SectionHeading";

export function ManagerSection() {
  const { locale, copy } = useLocale();
  const managerPoints = getLocalizedContent(locale).managerPoints;
  return (
    <section id="manager" className="border-y border-vynic-border bg-vynic-surface px-4 py-20 sm:px-6 lg:px-8 lg:py-28">
      <div className="mx-auto max-w-7xl">
        <SectionHeading
          title={copy.manager.title}
          body={copy.manager.body}
        />

        <div className="mt-12 grid gap-8 lg:grid-cols-[1fr_0.52fr] lg:items-start">
          <Reveal>
            <div className="relative">
              <ProductScreenshot spec={screenshots.managerStaff} />
              <div className="mt-5 grid gap-4 sm:grid-cols-2">
                <div className="vynic-neu-surface rounded-[8px] border border-vynic-border bg-vynic-background p-5">
                  <Monitor className="text-vynic-plum" size={24} weight="duotone" />
                  <h3 className="mt-4 text-xl font-semibold text-vynic-charcoal">{copy.manager.roleTitle}</h3>
                  <p className="mt-3 text-sm leading-6 text-vynic-muted">
                    {copy.manager.roleBody}
                  </p>
                </div>
                <div className="vynic-neu-surface rounded-[8px] border border-vynic-border bg-vynic-background p-5">
                  <LockKey className="text-vynic-plum" size={24} weight="duotone" />
                  <h3 className="mt-4 text-xl font-semibold text-vynic-charcoal">{copy.manager.closeTitle}</h3>
                  <p className="mt-3 text-sm leading-6 text-vynic-muted">
                    {copy.manager.closeBody}
                  </p>
                </div>
              </div>
            </div>
          </Reveal>

          <Reveal delay={0.12}>
            <div className="grid gap-6">
              <ProductScreenshot spec={screenshots.managerMobile} mobile compact />
              <div className="vynic-neu-surface rounded-[8px] border border-vynic-border bg-vynic-background p-5">
                <DeviceMobile className="text-vynic-plum" size={24} weight="duotone" />
                <h3 className="mt-4 text-xl font-semibold text-vynic-charcoal">
                  {copy.manager.practicalTitle}
                </h3>
                <div className="mt-4 flex flex-wrap gap-2">
                  {managerPoints.map((point) => (
                    <span
                      key={point}
                      className="rounded-[8px] border border-vynic-border bg-vynic-surface px-3 py-2 text-sm text-vynic-muted"
                    >
                      {point}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
