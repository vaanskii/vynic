import { ArrowUpRight } from "@phosphor-icons/react";
import { motion, useReducedMotion, useScroll, useTransform, type MotionValue } from "motion/react";
import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import screenFloorEditor from "../../assets/screen-floor-editor.png";
import screenFloor from "../../assets/screen-pos-floor-live.png";
import screenReservation from "../../assets/screen-reservation-confirm.png";
import { localeHref, useLocale } from "../../lib/i18n";
import { BrandMark, Kicker } from "./primitives";
import { KineticTitle } from "./kinetic";
import { getSiteCopy, PAGE_ORDER } from "./siteCopy";

// Section anchors the shared site navigation already links to (/en#product …).
const ANCHORS: Record<(typeof PAGE_ORDER)[number], string> = {
  pos: "product",
  manager: "manager",
  floor: "floor-plan",
  reservations: "reservations",
};

/**
 * Doors to the four product pages. Wide screens: vertical scroll drives a
 * horizontal track of full-height panels that turn in 3D as they pass the
 * centre. Narrow screens: the same panels stack and stick as you scroll.
 */
export function ExploreRail() {
  const { locale } = useLocale();
  const copy = getSiteCopy(locale);
  const reduce = useReducedMotion();
  const [wide, setWide] = useState(() => window.matchMedia?.("(min-width: 1024px)").matches ?? false);

  useLayoutEffect(() => {
    const query = window.matchMedia?.("(min-width: 1024px)");
    if (!query) return;
    const change = () => setWide(query.matches);
    query.addEventListener("change", change);
    return () => query.removeEventListener("change", change);
  }, []);

  const header = (
    <div className="px-4 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-[1320px]">
        <Kicker>{copy.explore.kicker}</Kicker>
        <KineticTitle parts={copy.explore.title} className="vh-display mt-4 max-w-[16ch] text-[2.8rem] text-[var(--vh-text)] sm:text-6xl lg:text-[4.2rem]" />
      </div>
    </div>
  );

  if (!wide || reduce) {
    return (
      <section className="relative py-24">
        {header}
        <div className="mt-12 grid gap-6 px-4 sm:px-6">
          {PAGE_ORDER.map((key, index) => (
            <div key={key} id={ANCHORS[key]} className="sticky" style={{ top: 72 + index * 14 }}>
              <Door page={key} index={index} />
            </div>
          ))}
        </div>
      </section>
    );
  }
  return <WideRail header={header} />;
}

function WideRail({ header }: { header: ReactNode }) {
  const ref = useRef<HTMLElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  // Read through a ref so a resize never needs a new transform.
  const distance = useRef(0);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end end"] });
  const x = useTransform(scrollYProgress, (value) => -distance.current * Math.min(1, Math.max(0, (value - 0.08) / 0.87)));

  useLayoutEffect(() => {
    const track = trackRef.current;
    if (!track) return;
    const measure = () => {
      distance.current = Math.max(0, track.scrollWidth - window.innerWidth);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(track);
    window.addEventListener("resize", measure);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, []);

  return (
    <section ref={ref} className="relative" style={{ height: `${PAGE_ORDER.length * 100 + 60}vh` }}>
      {/* Anchors at the scroll depth where each panel is centred. */}
      {PAGE_ORDER.map((key, index) => (
        <span key={key} id={ANCHORS[key]} className="absolute left-0" style={{ top: `${20 + index * 100}vh` }} />
      ))}
      <div className="sticky top-0 flex h-[100dvh] flex-col justify-center overflow-hidden pt-20">
        {header}
        <motion.div ref={trackRef} className="mt-8 flex w-max gap-8 pl-[max(2rem,calc((100vw-1320px)/2+2rem))] pr-[12vw] [perspective:2000px]" style={{ x }}>
          {PAGE_ORDER.map((key, index) => (
            <TurningPanel key={key} index={index} progress={scrollYProgress}>
              <Door page={key} index={index} />
            </TurningPanel>
          ))}
        </motion.div>
      </div>
    </section>
  );
}

function TurningPanel({ children, index, progress }: { children: ReactNode; index: number; progress: MotionValue<number> }) {
  const span = 0.87 / (PAGE_ORDER.length - 1);
  const centre = 0.08 + index * span;
  // Scroll-linked values may run on the browser's ScrollTimeline, which needs
  // offsets inside 0–1, so every range is clamped.
  const clamp = (value: number) => Math.min(1, Math.max(0, value));
  const near = [clamp(centre - span), centre, clamp(centre + span)];
  const far = [clamp(centre - span * 1.4), centre, clamp(centre + span * 1.4)];
  const rotateY = useTransform(progress, near, [-22, 0, 22]);
  const scale = useTransform(progress, near, [0.86, 1, 0.86]);
  const opacity = useTransform(progress, far, [0.35, 1, 0.35]);
  return (
    <motion.div className="w-[min(72vw,980px)] shrink-0" style={{ rotateY, scale, opacity }}>
      {children}
    </motion.div>
  );
}

function Door({ page, index }: { page: (typeof PAGE_ORDER)[number]; index: number }) {
  const { locale } = useLocale();
  const copy = getSiteCopy(locale);
  const item = copy.pages[page];
  const href = `${localeHref(locale)}/${item.path}`;
  return (
    <Link
      to={href}
      className="group relative block overflow-hidden lg:h-[min(56vh,520px)] lg:min-h-[400px] rounded-[28px] border border-[var(--vh-line-strong)] bg-[linear-gradient(160deg,#2b2927,#191816)] shadow-[0_50px_100px_-40px_rgba(0,0,0,0.9)]"
    >
      <div className="absolute inset-0 opacity-0 transition-opacity duration-700 group-hover:opacity-100 [background:radial-gradient(ellipse_at_70%_20%,rgba(154,106,161,0.35),transparent_60%)]" />
      <div className="relative grid h-full grid-cols-[minmax(0,1fr)] gap-6 p-5 sm:p-9 lg:grid-cols-[0.9fr_1.1fr]">
        <div className="flex flex-col">
          <span className="vh-mono text-[11px] text-[var(--vh-faint)]">0{index + 1} / 0{PAGE_ORDER.length}</span>
          <span className="vh-display mt-4 text-[3.2rem] lg:mt-auto text-[var(--vh-text)] transition-colors duration-500 group-hover:text-[var(--vh-orchid)] sm:text-7xl lg:text-[5.4rem]">{item.nav}</span>
          <span className="mt-4 max-w-sm text-[15px] leading-7 text-[var(--vh-muted)]">{item.door}</span>
          <span className="mt-6 inline-flex items-center gap-3">
            <span className="vh-btn-primary flex h-11 w-11 items-center justify-center rounded-full text-white transition-transform duration-500 group-hover:rotate-45 group-hover:scale-110">
              <ArrowUpRight size={18} weight="bold" />
            </span>
            <span className="vh-mono text-[11px] text-[var(--vh-soft)]">
              {copy.explore.open} · {item.preview}
            </span>
          </span>
        </div>
        <div className="relative order-first h-44 [perspective:1200px] sm:h-60 lg:order-none lg:h-auto">
          <div className="absolute inset-0 flex items-center justify-center transition-transform duration-700 [transform-style:preserve-3d] group-hover:[transform:rotateY(-8deg)_rotateX(6deg)_scale(1.03)]">
            <Preview page={page} />
          </div>
        </div>
      </div>
    </Link>
  );
}

function Preview({ page }: { page: (typeof PAGE_ORDER)[number] }) {
  const shot = (src: string) => (
    <div className="h-full rounded-[16px] border border-white/10 bg-[#1a1816] p-1.5 shadow-[0_40px_80px_-30px_rgba(0,0,0,0.9)] lg:h-auto lg:w-full">
      <img src={src} alt="" className="aspect-[3456/2234] h-full w-auto rounded-[11px] object-cover lg:h-auto lg:w-full" loading="lazy" draggable={false} />
    </div>
  );
  if (page === "pos") return shot(screenFloor);
  if (page === "floor") return shot(screenFloorEditor);
  if (page === "reservations") return shot(screenReservation);
  return (
    <div className="aspect-[9/19.5] h-[92%] max-h-[420px] rounded-[34px] border border-white/10 bg-[#0f0e0d] p-2 shadow-[0_40px_80px_-30px_rgba(0,0,0,0.9)]">
      <div className="flex h-full w-full flex-col gap-2 overflow-hidden rounded-[26px] bg-[#f4f2ef] p-3 pt-8">
        <div className="flex items-center gap-2">
          <BrandMark size={18} />
          <span className="h-2 w-14 rounded-full bg-[#d8d0c9]" />
        </div>
        <div className="h-20 rounded-[12px] bg-[#764b7c]" />
        <div className="vh-shimmer h-16 rounded-[10px] bg-[linear-gradient(90deg,#e9e5e0_0%,#f6f3ef_40%,#e9e5e0_80%)]" />
        <div className="grid grid-cols-2 gap-2">
          <div className="h-12 rounded-[10px] bg-[#ebe7e2]" />
          <div className="h-12 rounded-[10px] bg-[#ebe7e2]" />
        </div>
      </div>
    </div>
  );
}
