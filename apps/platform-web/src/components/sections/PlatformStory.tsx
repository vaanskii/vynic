import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { Browser, CloudCheck, Code, DeviceMobile, Desktop } from "@phosphor-icons/react";
import type { Icon } from "@phosphor-icons/react";
import managerDashboard from "../../assets/manager-android-dashboard.png";
import posFloor from "../../assets/pos-live-floor.jpg";
import vynicLogo from "../../assets/vynic-logo.png";
import { useLocale, type Locale } from "../../lib/i18n";
import { gsapEase, motionQuery } from "../../lib/motion";
import { Reveal } from "../ui/Reveal";

gsap.registerPlugin(ScrollTrigger);

type Step = { label: string; title: string; body: string };

const storyCopy: Record<Locale, {
  eyebrow: string;
  title: string;
  body: string;
  hub: string;
  hubDetail: string;
  connected: string;
  hosted: string;
  custom: string;
  sameBackend: string;
  steps: Step[];
}> = {
  en: {
    eyebrow: "One connected platform",
    title: "One restaurant record behind every surface.",
    body: "The POS, the Manager app and the restaurant website work from the same venue data in the Vynic cloud.",
    hub: "Vynic cloud",
    hubDetail: "Venue record",
    connected: "One connected restaurant platform",
    hosted: "Vynic-hosted site",
    custom: "Custom build",
    sameBackend: "Same venue backend",
    steps: [
      { label: "POS", title: "Vynic POS runs the floor", body: "Tables, orders, payments and day close. Offline-first, so service continues when the connection drops." },
      { label: "Manager", title: "The Manager app follows the day", body: "Owners and managers see tables, reservations and the business day from their phone." },
      { label: "Website", title: "The website publishes it", body: "Menu, opening hours, photos and contact go live from the same venue data." },
      { label: "Hosted or custom", title: "Hosted by Vynic, or your own build", body: "Launch on a Vynic-hosted site, or connect a custom website to the same backend." },
    ],
  },
  ka: {
    eyebrow: "ერთი დაკავშირებული პლატფორმა",
    title: "ერთი რესტორნის ჩანაწერი ყველა ეკრანის უკან.",
    body: "POS, მენეჯერის აპი და რესტორნის ვებსაიტი Vynic cloud-ში ობიექტის ერთსა და იმავე მონაცემებით მუშაობს.",
    hub: "Vynic cloud",
    hubDetail: "ობიექტის ჩანაწერი",
    connected: "ერთი დაკავშირებული რესტორნის პლატფორმა",
    hosted: "Vynic-ის საიტი",
    custom: "ინდივიდუალური საიტი",
    sameBackend: "ობიექტის იგივე სისტემა",
    steps: [
      { label: "POS", title: "Vynic POS მართავს დარბაზს", body: "მაგიდები, შეკვეთები, გადახდები და დღის დახურვა. Offline-first — სერვისი კავშირის გაწყვეტისას არ ჩერდება." },
      { label: "მენეჯერი", title: "მენეჯერის აპი დღეს მიჰყვება", body: "მფლობელები და მენეჯერები ტელეფონიდან ხედავენ მაგიდებს, რეზერვაციებს და სამუშაო დღეს." },
      { label: "ვებსაიტი", title: "ვებსაიტი ამას აქვეყნებს", body: "მენიუ, სამუშაო საათები, ფოტოები და კონტაქტი იმავე მონაცემებიდან ქვეყნდება." },
      { label: "Vynic ან საკუთარი", title: "Vynic-ის საიტი ან საკუთარი", body: "გაუშვი საიტი Vynic-ზე ან დააკავშირე ინდივიდუალური ვებსაიტი იმავე სისტემას." },
    ],
  },
};

const stepIcons: Icon[] = [Desktop, DeviceMobile, Browser, Code];

// Connector paths, hub → surface, in a 114×100 space matching the stage's
// 1.14 aspect ratio so strokes stay uniform.
const connectors = [
  "M 57 52 C 48 52, 43 46, 34 44",
  "M 57 52 C 71 50, 84 44, 96 38",
  "M 57 52 C 64 58, 71 62, 80 64",
  "M 57 52 C 46 60, 36 66, 25 70",
];

/**
 * Vynic → POS → Manager → Website → hosted/custom → one platform.
 * Desktop: a sticky stage assembled by native scrolling (scrubbed, never
 * pinned or snapped); short viewports and reduced motion see the finished
 * composition. Mobile: a plain list.
 */
export function PlatformStory() {
  const { locale } = useLocale();
  const copy = storyCopy[locale];
  const trackRef = useRef<HTMLDivElement>(null);
  const copyRef = useRef<HTMLDivElement>(null);
  // Whether the step list fits beside the sticky stage at this viewport size.
  const [fits, setFits] = useState(false);

  useLayoutEffect(() => {
    const copyEl = copyRef.current;
    if (!copyEl) return;
    const check = () => setFits(copyEl.offsetHeight + 96 <= window.innerHeight);
    const observer = new ResizeObserver(check);
    observer.observe(copyEl);
    window.addEventListener("resize", check);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", check);
    };
  }, []);

  useLayoutEffect(() => {
    const track = trackRef.current;
    if (!track || !fits) return;
    const media = gsap.matchMedia();
    // Scrubbed only where the sticky stage fits the viewport; otherwise the
    // section stays a normal, fully readable composition.
    media.add(motionQuery.desktop, () => {
      track.dataset.scrub = "true";
      const context = gsap.context(() => {
        const q = gsap.utils.selector(track);
        const surfaces = q("[data-surface]");
        const rows = q("[data-step-row]");
        const bars = q("[data-step-bar]");
        const lines = q("[data-connector]");
        const pulses = q("[data-pulse]");
        const timeline = gsap.timeline({
          defaults: { ease: gsapEase.scrub },
          scrollTrigger: {
            trigger: track,
            // Begins as the section arrives so the stage is never empty.
            start: "top 55%",
            end: "bottom bottom",
            scrub: 0.6,
            invalidateOnRefresh: true,
          },
        });

        // Start state; the markup itself is the finished, static composition.
        gsap.set(rows, { autoAlpha: 0.32 });
        gsap.set(bars, { scaleY: 0 });
        gsap.set(lines, { strokeDashoffset: 1 });
        gsap.set(pulses, { strokeDashoffset: 0.06, autoAlpha: 0 });
        gsap.set("[data-connected]", { autoAlpha: 0, y: 12 });
        timeline.fromTo("[data-hub]", { autoAlpha: 0.4, scale: 0.9 }, { autoAlpha: 1, scale: 1, duration: 0.6 }, 0);

        surfaces.forEach((surface, index) => {
          const at = 0.4 + index * 1.2;
          timeline
            .fromTo(surface, { autoAlpha: 0, y: 36, scale: 0.94 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.8, ease: "power2.out" }, at)
            .to(lines[index], { strokeDashoffset: 0, duration: 0.6 }, at + 0.3)
            .to(rows[index], { autoAlpha: 1, duration: 0.3 }, at)
            .to(bars[index], { scaleY: 1, duration: 0.4 }, at);
          if (index > 0) {
            // Hand-off: the previous surface steps back as the next arrives.
            timeline
              .to(surfaces[index - 1], { autoAlpha: 0.45, scale: 0.97, duration: 0.5 }, at)
              .to(rows[index - 1], { autoAlpha: 0.5, duration: 0.3 }, at)
              .to(bars[index - 1], { scaleY: 0, duration: 0.3 }, at);
          }
        });

        // Everything connected: every surface returns, data runs outward once.
        const finale = 0.4 + surfaces.length * 1.2;
        timeline
          .to(surfaces, { autoAlpha: 1, scale: 1, duration: 0.6 }, finale)
          .to(rows, { autoAlpha: 1, duration: 0.4 }, finale)
          .to(bars, { scaleY: 1, duration: 0.4 }, finale)
          .to(pulses, { autoAlpha: 1, duration: 0.1 }, finale + 0.1)
          .to(pulses, { strokeDashoffset: -1, duration: 1.1, stagger: 0.08 }, finale + 0.1)
          .to(pulses, { autoAlpha: 0, duration: 0.2 }, finale + 1.2)
          .to("[data-connected]", { autoAlpha: 1, y: 0, duration: 0.5, ease: "power2.out" }, finale + 0.3)
          .to({}, { duration: 0.5 });
      }, track);
      ScrollTrigger.refresh();
      return () => {
        context.revert();
        delete track.dataset.scrub;
      };
    });
    return () => media.revert();
  }, [locale, fits]);

  return (
    <section id="platform" aria-labelledby="platform-title" className="relative border-b border-vynic-border">
      {/* Desktop stage */}
      <div ref={trackRef} className="vynic-story-track hidden lg:block">
        <div className="vynic-story-stage flex items-center">
          <div className="mx-auto grid w-full max-w-7xl grid-cols-[0.78fr_1.22fr] items-center gap-12 px-8 xl:gap-16">
            <div ref={copyRef}>
              <StoryHeading copy={copy} id="platform-title" compact={locale === "ka"} />
              <ol className="mt-6 grid gap-1">
                {copy.steps.map((step, index) => {
                  const StepIcon = stepIcons[index];
                  return (
                    <li key={step.label} data-step-row className="relative grid grid-cols-[36px_1fr] gap-4 py-3 pl-5">
                      <span data-step-bar className="absolute inset-y-3 left-0 w-[2px] origin-top rounded-full bg-vynic-plum" aria-hidden="true" />
                      <span className="flex h-9 w-9 items-center justify-center rounded-[8px] border border-vynic-border bg-vynic-surface text-vynic-plum">
                        <StepIcon size={18} weight="duotone" />
                      </span>
                      <div>
                        <p className="font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-vynic-plum">
                          {String(index + 1).padStart(2, "0")} · {step.label}
                        </p>
                        <h3 className="mt-1 text-base font-semibold text-vynic-charcoal xl:text-lg">{step.title}</h3>
                        <p className="mt-1 max-w-md text-sm leading-6 text-vynic-muted">{step.body}</p>
                      </div>
                    </li>
                  );
                })}
              </ol>
            </div>

            <div className="relative mx-auto aspect-[1.14] w-full max-w-[720px]" aria-hidden="true">
              <div className="vynic-stage-aura absolute -inset-16" />
              <svg className="absolute inset-0 h-full w-full overflow-visible" viewBox="0 0 114 100">
                {connectors.map((d) => (
                  <g key={d}>
                    <path d={d} fill="none" stroke="var(--vynic-border)" strokeWidth="0.18" />
                    <path data-connector d={d} pathLength={1} strokeDasharray="1 1" fill="none" stroke="var(--vynic-plum)" strokeOpacity="0.6" strokeWidth="0.22" />
                    <path data-pulse d={d} pathLength={1} strokeDasharray="0.06 1" strokeLinecap="round" fill="none" stroke="var(--vynic-plum)" strokeWidth="0.55" style={{ opacity: 0 }} />
                  </g>
                ))}
              </svg>

              <div data-surface className="absolute left-0 top-0 w-[48%]"><PosSurface /></div>
              <div data-surface className="absolute right-[3%] top-0 w-[19%]"><ManagerSurface /></div>
              <div data-surface className="absolute bottom-0 right-0 w-[48%]"><WebsiteSurface locale={locale} /></div>
              <div data-surface className="absolute bottom-[8%] left-0 w-[34%]"><HostingSurface copy={copy} /></div>

              <div className="absolute left-1/2 top-[52%] -translate-x-1/2 -translate-y-1/2">
                <div data-hub className="vynic-neu-surface flex items-center gap-3 rounded-[12px] border border-vynic-border px-4 py-3">
                  <img className="h-9 w-9 rounded-[9px]" src={vynicLogo} alt="" />
                  <div>
                    <p className="text-sm font-semibold text-vynic-charcoal">{copy.hub}</p>
                    <p className="flex items-center gap-1.5 font-vynic-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-vynic-green">
                      <CloudCheck size={12} weight="bold" />
                      {copy.hubDetail}
                    </p>
                  </div>
                </div>
              </div>

              <div className="absolute -bottom-12 left-1/2 -translate-x-1/2">
                <p data-connected className="whitespace-nowrap font-vynic-mono text-[11px] font-semibold uppercase tracking-[0.16em] text-vynic-plum">
                  {copy.connected}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Mobile and tablet */}
      <div className="px-4 py-20 sm:px-6 lg:hidden">
        <div className="mx-auto max-w-3xl">
          <Reveal>
            <StoryHeading copy={copy} />
          </Reveal>
          <ol className="mt-10 grid gap-10">
            {copy.steps.map((step, index) => (
              <li key={step.label}>
                <Reveal>
                  <div className="mx-auto max-w-md">
                    {index === 0 ? <PosSurface /> : index === 1 ? <div className="mx-auto w-[46%]"><ManagerSurface /></div> : index === 2 ? <WebsiteSurface locale={locale} /> : <HostingSurface copy={copy} />}
                  </div>
                  <p className="mt-5 font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-vynic-plum">
                    {String(index + 1).padStart(2, "0")} · {step.label}
                  </p>
                  <h3 className="mt-2 text-xl font-semibold text-vynic-charcoal">{step.title}</h3>
                  <p className="mt-2 text-sm leading-6 text-vynic-muted">{step.body}</p>
                </Reveal>
              </li>
            ))}
          </ol>
          <p className="mt-12 border-t border-vynic-border pt-5 font-vynic-mono text-[11px] font-semibold uppercase tracking-[0.16em] text-vynic-plum">
            {copy.connected}
          </p>
        </div>
      </div>
    </section>
  );
}

function StoryHeading({ copy, id, compact = false }: { copy: (typeof storyCopy)[Locale]; id?: string; compact?: boolean }) {
  return (
    <div>
      <p className="mb-4 font-vynic-mono text-xs font-semibold uppercase tracking-[0.18em] text-vynic-plum">{copy.eyebrow}</p>
      <h2 id={id} className={`text-3xl font-semibold leading-[1.08] text-vynic-charcoal sm:text-4xl ${compact ? "lg:text-[2rem] xl:text-[2.25rem]" : "lg:text-[2.25rem] xl:text-[2.75rem]"}`}>
        {copy.title}
      </h2>
      <p className="mt-4 max-w-xl text-base leading-7 text-vynic-muted">{copy.body}</p>
    </div>
  );
}

function SurfaceFrame({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`overflow-hidden rounded-[10px] border border-vynic-border bg-vynic-surface shadow-[0_24px_60px_-20px_color-mix(in_srgb,var(--vynic-charcoal)_32%,transparent)] ${className}`}>
      {children}
    </div>
  );
}

function PosSurface() {
  return (
    <SurfaceFrame className="p-1.5">
      <img className="aspect-[800/632] w-full rounded-[6px] object-cover" src={posFloor} alt="Vynic POS live floor plan" loading="lazy" />
    </SurfaceFrame>
  );
}

function ManagerSurface() {
  return (
    <div className="rounded-[22px] border-[4px] border-[#2b2927] bg-[#2b2927] shadow-[0_24px_60px_-20px_color-mix(in_srgb,var(--vynic-charcoal)_40%,transparent)]">
      <img
        className="aspect-[9/16] w-full rounded-[18px] object-cover"
        style={{ objectPosition: "center 52%" }}
        src={managerDashboard}
        alt="Vynic Manager app business-day dashboard"
        loading="lazy"
      />
    </div>
  );
}

/** Synthetic demo restaurant — illustrates the published page, not a real venue. */
function WebsiteSurface({ locale }: { locale: Locale }) {
  const ka = locale === "ka";
  const items: Array<[string, string]> = ka
    ? [["ხაჭაპური", "25.00 ₾"], ["სეზონური სალათი", "18.00 ₾"], ["ლიმონათი", "7.50 ₾"]]
    : [["Khachapuri", "25.00 ₾"], ["Seasonal salad", "18.00 ₾"], ["Lemonade", "7.50 ₾"]];
  return (
    <SurfaceFrame>
      <div className="flex items-center gap-1.5 border-b border-vynic-border bg-vynic-background px-3 py-2">
        <span className="h-2 w-2 rounded-full bg-[#d8d1cb]" />
        <span className="h-2 w-2 rounded-full bg-[#d8d1cb]" />
        <span className="h-2 w-2 rounded-full bg-[#d8d1cb]" />
        <span className="ml-2 h-4 flex-1 rounded-full bg-vynic-surface" />
      </div>
      <div className="grid grid-cols-[1fr_0.9fr]">
        <div className="bg-[#22201e] p-4 text-[#f7f6f4]">
          <p className="font-vynic-mono text-[8px] font-semibold uppercase tracking-[0.14em] text-[#b9a8c4]">Demo Bistro</p>
          <p className="mt-2 text-sm font-semibold leading-tight">{ka ? "ღიაა დღეს 12:00–23:00" : "Open today 12:00–23:00"}</p>
          <div className="mt-4 grid grid-cols-3 gap-1">
            <span className="aspect-square rounded-[4px] bg-[#4a4541]" />
            <span className="aspect-square rounded-[4px] bg-[#5b4b5f]" />
            <span className="aspect-square rounded-[4px] bg-[#4d5a4c]" />
          </div>
        </div>
        <div className="p-3">
          <p className="font-vynic-mono text-[8px] font-semibold uppercase tracking-[0.14em] text-vynic-plum">{ka ? "მენიუ" : "Menu"}</p>
          <div className="mt-2 grid gap-1.5">
            {items.map(([name, price]) => (
              <div key={name} className="flex items-center justify-between gap-2 border-b border-vynic-border pb-1.5 text-[10px] last:border-0">
                <span className="truncate font-semibold text-vynic-charcoal">{name}</span>
                <span className="shrink-0 text-vynic-muted">{price}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </SurfaceFrame>
  );
}

function HostingSurface({ copy }: { copy: (typeof storyCopy)[Locale] }) {
  return (
    <div className="grid gap-2">
      {[
        { icon: Browser, label: copy.hosted },
        { icon: Code, label: copy.custom },
      ].map(({ icon: ItemIcon, label }) => (
        <div key={label} className="vynic-neu-surface flex items-center gap-3 rounded-[10px] border border-vynic-border px-3 py-2.5">
          <ItemIcon className="shrink-0 text-vynic-plum" size={18} weight="duotone" />
          <span className="text-sm font-semibold text-vynic-charcoal">{label}</span>
        </div>
      ))}
      <p className="pl-1 font-vynic-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-vynic-muted">{copy.sameBackend}</p>
    </div>
  );
}
