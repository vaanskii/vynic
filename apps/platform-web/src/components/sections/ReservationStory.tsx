import { Check, ForkKnife, PencilSimpleLine, UsersThree } from "@phosphor-icons/react";
import { useEffect, useRef } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useReducedMotion } from "motion/react";
import { getLocalizedContent } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";
import { ProductScreenshot } from "../product/ProductScreenshot";
import { SectionHeading } from "../ui/SectionHeading";

gsap.registerPlugin(ScrollTrigger);

const stepIcons = [UsersThree, ForkKnife, PencilSimpleLine];

export function ReservationStory() {
  const { locale, copy } = useLocale();
  const reservationSteps = getLocalizedContent(locale).reservationSteps;
  const sectionRef = useRef<HTMLElement>(null);
  const reduceMotion = useReducedMotion();
  const staticStory = reduceMotion === true;
  const journeyCopy = locale === "ka"
    ? {
        kicker: "ერთი ჯავშანი · ერთი სამუშაო ნაკადი",
        identity: "მაგიდა 8 · 20:30 · 4 სტუმარი",
        handoff: "სტუმრიდან გუნდამდე",
        stages: ["სტუმარი", "წინასწარი შეკვეთა", "გუნდი"],
        stageLabel: "ეტაპი",
      }
    : {
        kicker: "ONE BOOKING · ONE WORKFLOW",
        identity: "Table 8 · 20:30 · 4 guests",
        handoff: "Guest to staff",
        stages: ["Guest", "Preorder", "Staff"],
        stageLabel: "Stage",
      };

  useEffect(() => {
    const section = sectionRef.current;
    if (reduceMotion || !section) return;

    const media = gsap.matchMedia();
    media.add("(min-width: 1024px) and (prefers-reduced-motion: no-preference)", () => {
      const context = gsap.context(() => {
        const cards = Array.from(section.querySelectorAll<HTMLElement>(".reservation-stack-card"));
        const progressBars = Array.from(section.querySelectorAll<HTMLElement>(".reservation-journey-progress"));
        const timeline = gsap.timeline({
          scrollTrigger: {
            trigger: section,
            start: "top 72px",
            end: "bottom 72%",
            scrub: 0.8,
            invalidateOnRefresh: true,
          },
        });
        gsap.set(progressBars, { scaleX: 0 });

        cards.slice(0, -1).forEach((card, index) => {
          timeline.to(card, {
            scale: 0.96,
            autoAlpha: 0.82,
            y: -8,
            duration: 0.38,
            ease: "none",
          }, index + 0.62);

          const progress = progressBars[index];
          if (progress) timeline.to(progress, { scaleX: 1, duration: 1, ease: "none" }, index);
        });

        const lastProgress = progressBars.at(-1);
        if (lastProgress) timeline.to(lastProgress, { scaleX: 1, duration: 1, ease: "none" }, cards.length - 1);
      }, section);

      return () => context.revert();
    });

    return () => media.revert();
  }, [reduceMotion]);

  return (
    <section ref={sectionRef} id="reservations" className="px-4 py-20 sm:px-6 lg:px-8 lg:py-28">
      <div className="mx-auto max-w-7xl">
        <SectionHeading
          title={copy.reservations.title}
          body={copy.reservations.body}
        />

        <div className="mt-10 flex items-center gap-4 border-y border-vynic-border py-4 sm:mt-12 sm:gap-6">
          <div className="flex shrink-0 items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-vynic-charcoal text-vynic-surface">
              <Check size={16} weight="bold" />
            </span>
            <span className="hidden font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-vynic-plum sm:block">
              {journeyCopy.kicker}
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center justify-between gap-4">
              <span className="truncate text-sm font-semibold text-vynic-charcoal">{journeyCopy.identity}</span>
              <span className="shrink-0 font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-vynic-muted">
                {journeyCopy.handoff}
              </span>
            </div>
            <div className="mt-2 h-1 overflow-hidden rounded-full bg-vynic-border">
              <div className="h-full w-full origin-left rounded-full bg-vynic-plum" />
            </div>
          </div>
        </div>

        <div className="mt-6 grid gap-6">
          {reservationSteps.map((step, index) => {
            const IconComponent = stepIcons[index];

            return (
              <article
                key={step.title}
                className={`vynic-neu-surface reservation-stack-card grid min-h-[76dvh] items-center gap-8 rounded-[8px] border border-vynic-border bg-vynic-surface p-5 shadow-[0_22px_70px_color-mix(in_srgb,var(--vynic-charcoal)_8%,transparent)] sm:p-8 lg:grid-cols-[0.42fr_0.58fr] lg:p-10 ${staticStory ? "" : "lg:sticky lg:top-[72px]"}`}
                style={{ zIndex: index + 1 }}
              >
                <div className="max-w-xl">
                  <div className="mb-6 flex items-center gap-3">
                    <div className="flex h-12 w-12 items-center justify-center rounded-[8px] bg-vynic-background text-vynic-plum">
                      <IconComponent size={24} weight="duotone" />
                    </div>
                    <div>
                      <p className="font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-vynic-plum">
                        {journeyCopy.stageLabel} {String(index + 1).padStart(2, "0")} / {String(reservationSteps.length).padStart(2, "0")}
                      </p>
                      <p className="mt-1 text-xs text-vynic-muted">{journeyCopy.stages[index]}</p>
                    </div>
                  </div>
                  <h3 className="text-3xl font-semibold leading-[1.08] text-vynic-charcoal lg:text-4xl">
                    {step.title}
                  </h3>
                  <p className="mt-5 text-base leading-7 text-vynic-muted sm:text-lg">{step.body}</p>
                  <div className="mt-8 max-w-sm">
                    <div className="flex items-center justify-between gap-4 text-xs font-semibold text-vynic-charcoal">
                      <span>{journeyCopy.identity}</span>
                      <span className="font-vynic-mono text-[10px] text-vynic-muted">{index + 1} / {reservationSteps.length}</span>
                    </div>
                    <div className="relative mt-3 h-1 overflow-hidden rounded-full bg-vynic-border">
                      <div
                        className="reservation-journey-progress h-full origin-left rounded-full bg-vynic-plum"
                        style={{ width: `${((index + 1) / reservationSteps.length) * 100}%` }}
                      />
                    </div>
                  </div>
                </div>
                <ProductScreenshot spec={step.screenshot} />
              </article>
            );
          })}
        </div>
      </div>
    </section>
  );
}
