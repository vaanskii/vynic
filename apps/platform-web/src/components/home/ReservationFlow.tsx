import { ForkKnife, PencilSimpleLine, UsersThree } from "@phosphor-icons/react";
import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { useRef } from "react";
import { useLocale } from "../../lib/i18n";
import { getHomeCopy } from "./homeCopy";
import { Rise, SectionOpen } from "./primitives";

const ICONS = [UsersThree, ForkKnife, PencilSimpleLine];

/** Guest → preorder → staff: a booking travels the line as you scroll. */
export function ReservationFlow({ bare = false }: { bare?: boolean }) {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale).reservations;
  const reduce = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start 80%", "end 45%"] });
  const fill = useTransform(scrollYProgress, [0, 1], ["0%", "100%"]);
  const chip = useTransform(scrollYProgress, [0, 1], ["0%", "100%"]);

  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        {bare ? null : <SectionOpen kicker={home.kicker} title={[copy.reservations.title, "", ""]} body={copy.reservations.body} />}
        <div ref={ref} className="relative mt-16">
          {/* Line + traveling booking (desktop) */}
          <div className="absolute left-[16.66%] right-[16.66%] top-[27px] hidden h-px bg-[var(--vh-line-strong)] lg:block">
            <motion.div className="h-full bg-[linear-gradient(90deg,#764b7c,#d8b6de)] shadow-[0_0_12px_rgba(216,182,222,0.7)]" style={reduce ? { width: "100%" } : { width: fill }} />
            {!reduce ? (
              <motion.div className="absolute -top-[38px] -translate-x-1/2" style={{ left: chip }}>
                <span className="vh-glass vh-mono whitespace-nowrap rounded-full px-3 py-1.5 text-[10px] text-[var(--vh-text)]">{home.booking}</span>
              </motion.div>
            ) : null}
          </div>
          <ol className="grid grid-cols-[minmax(0,1fr)] gap-10 lg:grid-cols-3 lg:gap-8">
            {copy.reservations.steps.map((step, index) => {
              const Icon = ICONS[index];
              return (
                <li key={step.title}>
                  <Rise delay={index * 0.1} className="flex flex-col items-start lg:items-center lg:text-center">
                    <span className="relative flex h-14 w-14 items-center justify-center rounded-[16px] border border-[rgba(216,182,222,0.3)] bg-[var(--vh-panel)] text-[var(--vh-orchid)] shadow-[0_0_30px_-8px_rgba(154,106,161,0.7)]">
                      <Icon size={24} weight="duotone" />
                    </span>
                    <p className="vh-mono mt-6 text-[10px] text-[var(--vh-faint)]">{String(index + 1).padStart(2, "0")} / 03</p>
                    <h3 className="vh-sub mt-2 text-[1.6rem] text-[var(--vh-text)]">{step.title}</h3>
                    <p className="mt-2 max-w-sm text-[14px] leading-6 text-[var(--vh-muted)]">{step.body}</p>
                  </Rise>
                </li>
              );
            })}
          </ol>
        </div>
      </div>
    </section>
  );
}
