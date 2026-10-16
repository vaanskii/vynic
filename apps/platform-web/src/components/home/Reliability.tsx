import { CloudSlash, LockSimple } from "@phosphor-icons/react";
import { motion, useReducedMotion } from "motion/react";
import { useEffect, useState, type ReactNode } from "react";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy, type HomeCopy } from "./homeCopy";
import { BrandMark, Drift, Rise, SectionOpen, useOnScreen, useSeen } from "./primitives";

export function Reliability() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).reliable;
  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        <SectionOpen kicker={copy.kicker} title={copy.title} body={copy.body} />
        <div className="mt-14 grid grid-cols-[minmax(0,1fr)] gap-5 lg:grid-cols-2">
          <Drift amount={24}>
            <Rise y={40}>
              <OfflineCard copy={copy.offline} />
            </Rise>
          </Drift>
          <Drift amount={56}>
            <Rise y={40} delay={0.1}>
              <PaymentsCard copy={copy.payments} />
            </Rise>
          </Drift>
        </div>
      </div>
    </section>
  );
}

function CardShell({ title, body, footer, icon, children }: { title: string; body: string; footer: string; icon: ReactNode; children: ReactNode }) {
  return (
    <article className="vh-glass flex h-full flex-col rounded-[20px] p-6 sm:p-7">
      <h3 className="vh-sub text-[1.6rem] text-[var(--vh-text)]">{title}</h3>
      <p className="mt-2 max-w-md text-[14px] leading-6 text-[var(--vh-muted)]">{body}</p>
      <div className="mt-8 flex-1">{children}</div>
      <p className="vh-mono mt-6 flex items-center gap-2 border-t border-[var(--vh-line)] pt-4 text-[10px] text-[var(--vh-faint)]">
        {icon}
        {footer}
      </p>
    </article>
  );
}

// Node layout in a 100×60 box: hub in the middle, four terminals around it.
const NODES: Array<[number, number]> = [
  [14, 14],
  [86, 14],
  [14, 48],
  [86, 48],
];

function OfflineCard({ copy }: { copy: HomeCopy["reliable"]["offline"] }) {
  const reduce = useReducedMotion();
  const [ref, visible] = useOnScreen<HTMLDivElement>();
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    if (reduce || !visible) return;
    const timer = window.setInterval(() => setOffline((value) => !value), 3600);
    return () => window.clearInterval(timer);
  }, [reduce, visible]);

  return (
    <CardShell title={copy.title} body={copy.body} footer={copy.footer} icon={<CloudSlash size={12} />}>
      <div ref={ref} className="relative mx-auto aspect-[100/60] w-full max-w-[520px]">
        <svg className="absolute inset-0 h-full w-full" viewBox="0 0 100 60" aria-hidden="true">
          {NODES.map(([x, y], index) => {
            const d = `M 50 31 C ${(50 + x) / 2} 31, ${(50 + x) / 2} ${y}, ${x} ${y}`;
            return (
              <g key={index}>
                <path d={d} fill="none" stroke="rgba(216,182,222,0.28)" strokeWidth="0.35" strokeDasharray="0.8 0.8" />
                <path
                  d={d}
                  pathLength={1}
                  fill="none"
                  stroke={offline ? "#d7b48a" : "#d8b6de"}
                  strokeWidth="1.1"
                  strokeLinecap="round"
                  className="vh-pulse transition-[stroke] duration-700"
                  style={{ animationDelay: `${index * 0.35}s`, animationDirection: index % 2 ? "reverse" : "normal", filter: "drop-shadow(0 0 1.5px rgba(216,182,222,0.9))" }}
                />
              </g>
            );
          })}
        </svg>
        {NODES.map(([x, y], index) => (
          <div
            key={copy.nodes[index]}
            className="absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1.5"
            style={{ left: `${x}%`, top: `${(y / 60) * 100}%` }}
          >
            <span className="vh-mono flex h-9 w-9 items-center justify-center rounded-full border border-[var(--vh-line-strong)] bg-[var(--vh-panel)] text-[9px] text-[var(--vh-soft)]">
              {copy.nodes[index].slice(0, 2).toUpperCase()}
            </span>
            <span className="vh-mono whitespace-nowrap text-[9px] text-[var(--vh-faint)]">{copy.nodes[index]}</span>
          </div>
        ))}
        <div className="absolute left-1/2 top-[51.6%] -translate-x-1/2 -translate-y-1/2">
          <div className="vh-breathe flex h-16 w-16 items-center justify-center rounded-[18px] bg-[linear-gradient(160deg,#8f5f96,#5f3a65)]">
            <BrandMark size={40} />
          </div>
        </div>
        <motion.span
          layout
          className={`vh-mono absolute left-1/2 top-0 -translate-x-1/2 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border px-2.5 py-1 text-[10px] ${
            offline
              ? "border-[rgba(215,180,138,0.4)] bg-[rgba(215,180,138,0.1)] text-[var(--vh-amber)]"
              : "border-[rgba(169,194,166,0.3)] bg-[rgba(169,194,166,0.08)] text-[var(--vh-sage)]"
          }`}
          transition={{ duration: 0.4, ease: curve.out }}
        >
          <span className={`h-1.5 w-1.5 rounded-full ${offline ? "bg-[var(--vh-amber)]" : "bg-[var(--vh-sage)]"}`} />
          {offline ? copy.state[1] : copy.state[0]}
        </motion.span>
      </div>
    </CardShell>
  );
}

function PaymentsCard({ copy }: { copy: HomeCopy["reliable"]["payments"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  const reduce = useReducedMotion();
  const on = seen || reduce;
  return (
    <CardShell title={copy.title} body={copy.body} footer={copy.footer} icon={<LockSimple size={12} />}>
      <div ref={ref} className="grid gap-5">
        <p className="vh-mono text-[10px] text-[var(--vh-faint)]">{copy.head}</p>
        {copy.rows.map(([label, value], index) => (
          <div key={label} className="grid grid-cols-[minmax(0,7rem)_1fr_3rem] items-center gap-4">
            <span className="text-[13px] text-[var(--vh-soft)]">{label}</span>
            <div className="relative flex h-3 items-center">
              <div className="absolute inset-x-0 h-2 rounded-full bg-white/[0.06]" />
              <motion.div
                className={`absolute left-0 h-2 rounded-full ${index === 0 ? "bg-[linear-gradient(90deg,#764b7c,#d8b6de)] shadow-[0_0_14px_rgba(216,182,222,0.6)]" : "bg-[linear-gradient(90deg,#4a4643,#9a928a)]"}`}
                initial={reduce ? false : { width: 0 }}
                animate={{ width: on ? `${value}%` : 0 }}
                transition={{ duration: 1.4, ease: curve.out, delay: 0.15 + index * 0.15 }}
              />
              <motion.span
                className="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[var(--vh-panel)] bg-[var(--vh-text)]"
                initial={reduce ? false : { left: "0%" }}
                animate={{ left: on ? `${value}%` : "0%" }}
                transition={{ duration: 1.4, ease: curve.out, delay: 0.15 + index * 0.15 }}
              />
            </div>
            <span className="vh-mono text-right text-[11px] text-[var(--vh-muted)]">{value}%</span>
          </div>
        ))}
      </div>
    </CardShell>
  );
}
