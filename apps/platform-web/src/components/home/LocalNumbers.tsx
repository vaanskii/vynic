import { motion, useReducedMotion } from "motion/react";
import { getLocalizedContent } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy } from "./homeCopy";
import { CountUp, Rise, SectionOpen, useSeen } from "./primitives";

/**
 * Product facts, counted up — no invented customer metrics — followed by the
 * local details from the shared copy.
 */
export function LocalNumbers() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).numbers;
  const items = getLocalizedContent(locale).localFitItems;
  const [ref, seen] = useSeen<HTMLDivElement>(0.4);
  const reduce = useReducedMotion();
  const on = Boolean(seen || reduce);

  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        <SectionOpen kicker={copy.kicker} title={copy.title} body={copy.body} />
        <div ref={ref} className="mt-14 grid border-y border-[var(--vh-line)] sm:grid-cols-3">
          {copy.stats.map((stat, index) => (
            <div key={stat.label} className="border-b border-[var(--vh-line)] py-8 last:border-b-0 sm:border-b-0 sm:border-r sm:px-8 sm:first:pl-0 sm:last:border-r-0">
              <p className="vh-mono text-[10px] text-[var(--vh-faint)]">{stat.tag}</p>
              <p className="vh-display mt-3 text-7xl text-[var(--vh-text)] lg:text-[7.5rem]">
                <CountUp value={stat.value} run={seen} duration={1.2} />
                {stat.suffix}
              </p>
              <p className="mt-2 max-w-[26ch] text-[13px] leading-6 text-[var(--vh-muted)]">{stat.label}</p>
              <div className="mt-6 h-10">
                {index === 0 ? <OfflineLine on={on} /> : index === 1 ? <Segments on={on} /> : <FullBar on={on} />}
              </div>
            </div>
          ))}
        </div>
        <div className="mt-14 grid grid-cols-[minmax(0,1fr)] gap-x-10 gap-y-10 sm:grid-cols-2 lg:grid-cols-5">
          {items.map((item, index) => (
            <Rise key={item.title} delay={index * 0.06}>
              <p className="vh-mono text-[10px] text-[var(--vh-orchid)]">{String(index + 1).padStart(2, "0")}</p>
              <h3 className="vh-sub mt-2 text-[1.2rem] text-[var(--vh-text)]">{item.title}</h3>
              <p className="mt-2 text-[13px] leading-6 text-[var(--vh-muted)]">{item.body}</p>
            </Rise>
          ))}
        </div>
      </div>
    </section>
  );
}

/** Service keeps a steady line while the connection (dashed) drops out. */
function OfflineLine({ on }: { on: boolean }) {
  const reduce = useReducedMotion();
  const draw = reduce ? {} : { initial: { pathLength: 0 }, animate: { pathLength: on ? 1 : 0 }, transition: { duration: 1.6, ease: curve.inOut } };
  return (
    <svg viewBox="0 0 200 40" className="h-full w-full max-w-[260px] overflow-visible" aria-hidden="true">
      <motion.path d="M 0 30 L 60 30 L 70 38 L 110 38 L 120 30 L 200 30" fill="none" stroke="#6f6a64" strokeWidth="1" strokeDasharray="3 3" {...draw} />
      <motion.path d="M 0 14 C 40 12, 80 16, 120 12 S 170 10, 200 8" fill="none" stroke="#d8b6de" strokeWidth="1.6" strokeLinecap="round" style={{ filter: "drop-shadow(0 0 4px rgba(216,182,222,0.7))" }} {...draw} />
    </svg>
  );
}

function Segments({ on }: { on: boolean }) {
  return (
    <div className="flex h-full max-w-[260px] items-end gap-1.5">
      {Array.from({ length: 14 }, (_, index) => (
        <motion.span
          key={index}
          className={`flex-1 rounded-[3px] ${index < 7 ? "bg-[var(--vh-orchid)]" : "bg-[var(--vh-lilac)]/60"}`}
          initial={false}
          animate={{ height: on ? "100%" : "15%", opacity: on ? 1 : 0.3 }}
          transition={{ duration: 0.6, ease: curve.out, delay: index * 0.04 }}
        />
      ))}
    </div>
  );
}

function FullBar({ on }: { on: boolean }) {
  return (
    <div className="flex h-full max-w-[260px] items-center">
      <div className="relative h-1.5 w-full rounded-full bg-white/[0.06]">
        <motion.div
          className="absolute inset-y-0 left-0 rounded-full bg-[linear-gradient(90deg,#764b7c,#d8b6de)] shadow-[0_0_14px_rgba(216,182,222,0.6)]"
          initial={false}
          animate={{ width: on ? "100%" : "0%" }}
          transition={{ duration: 1.6, ease: curve.out }}
        />
      </div>
    </div>
  );
}
