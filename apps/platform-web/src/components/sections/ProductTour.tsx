import { useCallback, useEffect, useRef, useState } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useReducedMotion } from "motion/react";
import { getLocalizedContent } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";
import { ProductScreenshot } from "../product/ProductScreenshot";

gsap.registerPlugin(ScrollTrigger);

export function ProductTour() {
  const wrapRef = useRef<HTMLElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const headerProgressRef = useRef<HTMLDivElement>(null);
  const footerProgressRef = useRef<HTMLDivElement>(null);
  const activeRef = useRef<HTMLSpanElement>(null);
  const reduceMotion = useReducedMotion();
  const { locale, copy } = useLocale();
  const localizedContent = getLocalizedContent(locale);
  const serviceTour = localizedContent.serviceTour;
  const liveFloorStates = copy.product.states;
  const staticTour = reduceMotion === true;
  const [liveStage, setLiveStage] = useState(0);
  const handleLiveStageChange = useCallback((stage: number) => setLiveStage(stage), []);

  useEffect(() => {
    const scope = wrapRef.current;
    const stage = stageRef.current;
    if (reduceMotion || !scope || !stage) return;

    const media = gsap.matchMedia();
    media.add("(min-width: 1024px) and (prefers-reduced-motion: no-preference)", () => {
      const context = gsap.context(() => {
        const screens = Array.from(scope.querySelectorAll<HTMLElement>(".product-screen-layer"));
        const details = Array.from(scope.querySelectorAll<HTMLElement>(".product-detail-layer"));

        gsap.set(screens.slice(1), { autoAlpha: 0, scale: 1.015, y: 18 });
        gsap.set(details.slice(1), { autoAlpha: 0, y: 12 });

        const timeline = gsap.timeline({
          scrollTrigger: {
            trigger: stage,
            start: "top 56px",
            end: () => `+=${Math.round((serviceTour.length - 1) * window.innerHeight * 1.18)}`,
            pin: stage,
            scrub: 1.15,
            snap: {
              snapTo: 1 / (serviceTour.length - 1),
              duration: { min: 0.45, max: 1.05 },
              delay: 0.18,
              ease: "sine.inOut",
            },
            invalidateOnRefresh: true,
            onUpdate: (self) => {
              const slideIndex = Math.min(
                serviceTour.length - 1,
                Math.round(self.progress * (serviceTour.length - 1)),
              );

              if (headerProgressRef.current) gsap.set(headerProgressRef.current, { scaleX: self.progress });
              if (footerProgressRef.current) gsap.set(footerProgressRef.current, { scaleX: self.progress });
              if (activeRef.current) activeRef.current.textContent = String(slideIndex + 1).padStart(2, "0");
            },
          },
        });

        for (let index = 1; index < screens.length; index += 1) {
          const position = index - 1;
          timeline
            .to(screens[index - 1], { autoAlpha: 0, scale: 0.985, y: -12, duration: 0.38, ease: "power2.inOut" }, position)
            .fromTo(screens[index], { autoAlpha: 0, scale: 1.015, y: 18 }, { autoAlpha: 1, scale: 1, y: 0, duration: 0.58, ease: "power3.out" }, position + 0.22)
            .to(details[index - 1], { autoAlpha: 0, y: -8, duration: 0.25, ease: "power2.in" }, position)
            .fromTo(details[index], { autoAlpha: 0, y: 12 }, { autoAlpha: 1, y: 0, duration: 0.42, ease: "power3.out" }, position + 0.24);
        }

      }, scope);

      return () => context.revert();
    });

    return () => media.revert();
  }, [reduceMotion]);

  return (
    <section
      id="product"
      ref={wrapRef}
      className="overflow-hidden border-y border-[#403a35] bg-[#eeece9]"
    >
      <div className="bg-[#22201E] px-4 py-14 text-[#F7F6F4] sm:px-6 lg:py-16">
        <div className="mx-auto max-w-7xl">
        <div className="flex flex-wrap items-end justify-between gap-8">
          <div className="max-w-3xl">
          <p className="mb-4 font-vynic-mono text-xs font-semibold uppercase tracking-[0.18em] text-[#D8B6DE]">
            {copy.product.eyebrow}
          </p>
          <h2 className="text-3xl font-semibold leading-[1.08] sm:text-4xl lg:text-5xl">
            {copy.product.title}
          </h2>
          <p className="mt-5 max-w-2xl text-base leading-7 text-[#D8D0C9] sm:text-lg">
            {copy.product.body}
          </p>
          </div>
          <div className="min-w-[180px]">
            <div className="flex items-center justify-between font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-[#B9A8C4]">
              <span>{copy.product.shiftFlow}</span>
              <span><span ref={activeRef}>01</span> / {String(serviceTour.length).padStart(2, "0")}</span>
            </div>
            <div className="mt-3 h-px overflow-hidden bg-white/15">
              <div ref={headerProgressRef} className="vynic-progress-fill h-full bg-[#B9A8C4]" />
            </div>
          </div>
        </div>
        </div>
      </div>

      <div
        ref={stageRef}
        className={`relative hidden h-[calc(100dvh-56px)] min-h-[620px] bg-[#eeece9] text-[#292622] ${staticTour ? "lg:hidden" : "lg:grid lg:grid-rows-[minmax(0,1fr)_142px]"}`}
      >
        <div className="relative min-h-0 overflow-hidden px-3 pt-3 sm:px-5 sm:pt-5">
          {serviceTour.map((item, index) => (
            <div key={item.title} className={`product-screen-layer absolute inset-x-3 inset-y-3 origin-center sm:inset-x-5 sm:inset-y-5 ${index === 0 ? "z-[1]" : ""}`}>
              <ProductScreenshot
                spec={item.screenshot}
                live={index === 0}
                onLiveStageChange={index === 0 ? handleLiveStageChange : undefined}
                fill
                className="shadow-[0_24px_70px_rgba(41,38,34,0.16)]"
              />
            </div>
          ))}
        </div>

        <div className="relative border-t border-[#d2cdc7] bg-[#f8f7f5] px-6 py-5 xl:px-10">
          {serviceTour.map((item, index) => (
            <article key={item.title} className={`product-detail-layer absolute inset-x-6 inset-y-5 grid grid-cols-[150px_minmax(0,0.9fr)_minmax(280px,1.1fr)] items-start gap-7 xl:inset-x-10 ${index === 0 ? "z-[1]" : ""}`}>
              <p className="pt-1 font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-[#765f83]">
                {String(index + 1).padStart(2, "0")} / {String(serviceTour.length).padStart(2, "0")} · {item.label}
              </p>
              <h3 className="text-2xl font-semibold leading-tight xl:text-[28px]">{item.title}</h3>
              <div>
                <p className="max-w-2xl text-sm leading-6 text-[#6f6962] xl:text-base xl:leading-7">{item.body}</p>
              {index === 0 ? <LiveFloorRail stage={liveStage} states={liveFloorStates} label={copy.product.liveStatus} /> : null}
              </div>
            </article>
          ))}
          <div className="absolute bottom-0 left-0 h-[3px] w-full bg-[#ded9d3]">
            <div ref={footerProgressRef} className="vynic-progress-fill h-full origin-left bg-[#765f83]" />
          </div>
        </div>
      </div>

      <div className={`bg-[#eeece9] px-4 py-10 sm:px-6 ${staticTour ? "" : "lg:hidden"}`}>
        <div className="mx-auto grid max-w-3xl gap-14">
          {serviceTour.map((item, index) => (
            <article key={item.title} className="border-b border-[#d2cdc7] pb-14 last:border-0 last:pb-0">
              <ProductScreenshot
                spec={item.screenshot}
                live={index === 0}
                onLiveStageChange={index === 0 ? handleLiveStageChange : undefined}
                className="w-full"
              />
              <div className="mt-5 grid gap-3 sm:grid-cols-[130px_1fr]">
                <p className="font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-[#765f83]">
                  {String(index + 1).padStart(2, "0")} / {String(serviceTour.length).padStart(2, "0")} · {item.label}
                </p>
                <div>
                  <h3 className="text-2xl font-semibold text-[#292622]">{item.title}</h3>
                  <p className="mt-3 text-sm leading-6 text-[#6f6962]">{item.body}</p>
                  {index === 0 ? <LiveFloorRail stage={liveStage} states={liveFloorStates} label={copy.product.liveStatus} dark={false} /> : null}
                </div>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function LiveFloorRail({ stage, states, label, dark = true }: { stage: number; states: string[]; label: string; dark?: boolean }) {
  return (
    <div className="mt-4" aria-live="polite" aria-label="Table 8 live status">
      <p className={`font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.12em] ${dark ? "text-[#765f83]" : "text-vynic-plum"}`}>
        {label} {states[stage]}
      </p>
      <div className="mt-2 flex flex-wrap gap-2">
        {states.map((state, index) => (
          <span
            key={state}
            className={`rounded-full border px-2.5 py-1 text-[10px] font-semibold transition-colors duration-500 ${stage === index
              ? dark
                ? "border-[#cbb6d9] bg-[#f5eff9] text-[#5b4b86]"
                : "border-vynic-plum bg-vynic-plum text-white"
              : dark
                ? "border-[#d8d1cb] bg-[#f8f7f5] text-[#8a827b]"
                : "border-vynic-border bg-transparent text-vynic-muted"
              }`}
          >
            {state}
          </span>
        ))}
      </div>
    </div>
  );
}
