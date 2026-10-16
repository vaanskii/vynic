import { motion, useReducedMotion } from "motion/react";
import { useEffect, useState } from "react";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy } from "./homeCopy";
import { Rise, useOnScreen } from "./primitives";

const MONO = ["PS", "KT", "MG", "WB", "BK", "TB", "ZR"];

/**
 * "One venue record behind every surface": a row of surfaces on a dashed
 * line; a light runs along it and wakes each surface in turn.
 */
export function SurfacesRail() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).rail;
  const reduce = useReducedMotion();
  const [ref, visible] = useOnScreen<HTMLDivElement>();
  const [active, setActive] = useState(0);

  useEffect(() => {
    if (reduce || !visible) return;
    const timer = window.setInterval(() => setActive((value) => (value + 1) % copy.surfaces.length), 1300);
    return () => window.clearInterval(timer);
  }, [reduce, visible, copy.surfaces.length]);

  return (
    <section aria-label={copy.label} className="relative px-4 py-14 sm:px-6 lg:px-8">
      <div ref={ref} className="mx-auto max-w-[1320px]">
        <Rise>
          <p className="vh-mono text-[11px] text-[var(--vh-faint)]">{copy.label}</p>
        </Rise>
        <div className="relative mt-8">
          {/* Track */}
          <div className="absolute left-[6.25%] right-[6.25%] top-[22px] hidden border-t border-dashed border-[var(--vh-line-strong)] sm:block" />
          {!reduce ? (
            <motion.span
              className="absolute top-[19px] hidden h-[7px] w-[7px] rounded-full bg-[var(--vh-orchid)] shadow-[0_0_14px_3px_rgba(216,182,222,0.7)] sm:block"
              animate={{ left: `${((active + 0.5) / 8) * 100}%` }}
              transition={{ duration: 1.1, ease: curve.inOut }}
              style={{ marginLeft: -3 }}
            />
          ) : null}
          <ul className="relative grid grid-cols-4 gap-y-8 sm:grid-cols-8">
            {copy.surfaces.map((surface, index) => {
              const on = !reduce && index === active;
              return (
                <li key={surface} className="flex flex-col items-center gap-3">
                  <motion.span
                    className={`vh-mono flex h-11 w-11 items-center justify-center rounded-[12px] border text-[11px] transition-colors duration-500 ${
                      on
                        ? "border-[rgba(216,182,222,0.6)] bg-[rgba(118,75,124,0.45)] text-white shadow-[0_0_28px_-4px_rgba(154,106,161,0.9)]"
                        : "border-[var(--vh-line-strong)] bg-[var(--vh-panel)] text-[var(--vh-muted)]"
                    }`}
                    animate={on ? { scale: 1.08, y: -2 } : { scale: 1, y: 0 }}
                    transition={{ duration: 0.5, ease: curve.out }}
                  >
                    {MONO[index]}
                  </motion.span>
                  <span className={`vh-mono text-center text-[10px] transition-colors duration-500 ${on ? "text-[var(--vh-text)]" : "text-[var(--vh-faint)]"}`}>
                    {surface}
                  </span>
                </li>
              );
            })}
            <li className="flex flex-col items-center gap-3">
              <span className="vh-mono flex h-11 w-11 items-center justify-center rounded-[12px] border border-dashed border-[var(--vh-line-strong)] text-[13px] text-[var(--vh-faint)]">
                +
              </span>
              <span className="vh-mono text-center text-[10px] text-[var(--vh-faint)]">{copy.more}</span>
            </li>
          </ul>
        </div>
      </div>
    </section>
  );
}
