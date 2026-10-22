import { Check, Pause, WarningCircle } from "@phosphor-icons/react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useEffect, useState, type ReactNode } from "react";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy, type HomeCopy } from "./homeCopy";
import { KineticTitle } from "./kinetic";
import { BrandMark, Drift, Kicker, Rise, useSeen } from "./primitives";

/** 0 → 1 over `duration` seconds once `run` turns true. */
export function useTween(run: boolean, duration = 1.4, delay = 0) {
  const reduce = useReducedMotion();
  const [t, setT] = useState(reduce ? 1 : 0);
  useEffect(() => {
    if (!run || reduce) return;
    let frame = 0;
    const start = performance.now() + delay * 1000;
    const tick = (now: number) => {
      const raw = Math.min(1, Math.max(0, (now - start) / (duration * 1000)));
      setT(1 - Math.pow(1 - raw, 3));
      if (raw < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [run, duration, delay, reduce]);
  return t;
}

export function ServiceFlow() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).flow;

  return (
    <section id="how" className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        <div className="grid grid-cols-[minmax(0,1fr)] gap-12 lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)] lg:gap-20">
          {/* The heading stays pinned while the three moments scroll past it. */}
          <div className="lg:sticky lg:top-28 lg:self-start">
            <Kicker>{copy.kicker}</Kicker>
            <KineticTitle parts={copy.title} className="vh-display mt-5 max-w-[12ch] text-[2.8rem] text-[var(--vh-text)] sm:text-6xl lg:text-[5rem]" />
            <p className="mt-6 max-w-md text-[15px] leading-7 text-[var(--vh-muted)]">{copy.body}</p>
          </div>
          <div className="grid gap-20 lg:gap-28">
            <FeatureRow index={0} copy={copy} visual={<CheckTrace copy={copy.trace} />} />
            <FeatureRow index={1} copy={copy} visual={<CloseDayCard copy={copy.close} />} />
            <FeatureRow index={2} copy={copy} visual={<WeekBars copy={copy.week} />} />
          </div>
        </div>
      </div>
    </section>
  );
}

function FeatureRow({ index, copy, visual }: { index: number; copy: HomeCopy["flow"]; visual: ReactNode }) {
  const row = copy.rows[index];
  return (
    <div className="grid gap-6">
      <Drift amount={30}>
        <Rise y={50}>{visual}</Rise>
      </Drift>
      <Rise className="grid grid-cols-[3rem_minmax(0,1fr)] gap-4">
        <p className="vh-display text-3xl text-[var(--vh-orchid)]">0{index + 1}</p>
        <div>
          <h3 className="vh-sub text-[1.75rem] text-[var(--vh-text)] sm:text-[2.1rem]">{row.title}</h3>
          <p className="mt-2 max-w-md text-[15px] leading-7 text-[var(--vh-muted)]">{row.body}</p>
        </div>
      </Rise>
    </div>
  );
}

/* ---- 01 · Check trace ---------------------------------------------------- */

// Minutes on a 0–60 axis: [start, end] per step.
const TRACE: Array<[number, number]> = [
  [0, 3],
  [3, 24],
  [24, 26],
  [50, 58],
];

function CheckTrace({ copy }: { copy: HomeCopy["flow"]["trace"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  const t = useTween(seen, 2.6, 0.2);
  const steps = copy.steps.length;

  return (
    <div ref={ref} className="vh-glass rounded-[18px] p-5 sm:p-6">
      <div className="flex items-center justify-between gap-3">
        <span className="vh-mono text-[11px] text-[var(--vh-soft)]">{copy.head}</span>
        <motion.span className="vh-mono text-[11px] text-[var(--vh-faint)]" animate={{ opacity: t > 0.98 ? 1 : 0.25 }}>
          {copy.done}
        </motion.span>
      </div>
      <div className="mt-6 grid gap-3.5">
        {copy.steps.map((step, index) => {
          const [from, to] = TRACE[index];
          const local = Math.min(1, Math.max(0, t * steps - index));
          const done = local >= 1;
          const pending = index === steps - 1 && !done;
          return (
            <div key={step} className="grid grid-cols-[18px_minmax(0,9.5rem)_1fr] items-center gap-3">
              <span className={`flex h-4 w-4 items-center justify-center rounded-full transition-colors duration-500 ${done ? "bg-[rgba(169,194,166,0.18)] text-[var(--vh-sage)]" : "text-[var(--vh-faint)]"}`}>
                {done ? <Check size={10} weight="bold" /> : <span className={`h-1.5 w-1.5 rounded-full bg-current ${pending ? "vh-blink" : ""}`} />}
              </span>
              <span className={`vh-mono truncate text-[11px] transition-colors duration-500 ${done ? "text-[var(--vh-text)]" : "text-[var(--vh-faint)]"}`}>{step}</span>
              <div className="relative h-2.5">
                <div className="absolute inset-y-[4px] left-0 right-0 rounded-full bg-white/[0.04]" />
                <div
                  className={`absolute inset-y-0 origin-left rounded-full ${index === 3 ? "bg-[linear-gradient(90deg,#9a6aa1,#d8b6de)] shadow-[0_0_16px_rgba(216,182,222,0.55)]" : "bg-[linear-gradient(90deg,#6b4470,#b9a8c4)]"}`}
                  style={{ left: `${(from / 60) * 100}%`, width: `${Math.max(1.2, ((to - from) / 60) * 100)}%`, transform: `scaleX(${local})` }}
                />
              </div>
            </div>
          );
        })}
      </div>
      <div className="vh-mono mt-5 grid grid-cols-[18px_minmax(0,9.5rem)_1fr] gap-3 text-[10px] text-[var(--vh-faint)]">
        <span />
        <span />
        <div className="flex justify-between">
          {[0, 15, 30, 45, 60].map((value) => (
            <span key={value}>{value === 60 ? `${value} ${copy.unit}` : value}</span>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---- 02 · Close-day guardrails ------------------------------------------ */

function CloseDayCard({ copy }: { copy: HomeCopy["flow"]["close"] }) {
  const reduce = useReducedMotion();
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  // 0 typing · 1 message · 2..4 checks · 5 actions
  const [stage, setStage] = useState(reduce ? 5 : 0);
  const [waited, setWaited] = useState(reduce ? 2 : 0);

  useEffect(() => {
    if (!seen || reduce) return;
    const timers = [900, 1500, 2000, 2500, 3100].map((at, index) => window.setTimeout(() => setStage(index + 1), at));
    const clock = window.setInterval(() => setWaited((value) => value + 1), 4000);
    return () => {
      timers.forEach((timer) => window.clearTimeout(timer));
      window.clearInterval(clock);
    };
  }, [seen, reduce]);

  return (
    <div ref={ref} className="vh-glass rounded-[18px] p-5 sm:p-6">
      <div className="flex items-center justify-between">
        <span className="text-[13px] font-medium text-[var(--vh-text)]">{copy.head}</span>
        <span className="vh-mono text-[11px] text-[var(--vh-faint)]">{copy.today}</span>
      </div>
      <div className="mt-5 flex gap-3">
        <BrandMark size={32} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="text-[13px] font-medium text-[var(--vh-text)]">Vynic</span>
            <span className="vh-mono text-[10px] text-[var(--vh-faint)]">23:52</span>
          </div>
          <div className="relative mt-1 min-h-[22px]">
            <AnimatePresence mode="wait" initial={false}>
              {stage === 0 ? (
                <motion.span key="typing" className="flex gap-1 pt-2" exit={{ opacity: 0 }}>
                  {[0, 1, 2].map((dot) => (
                    <span key={dot} className="vh-blink h-1.5 w-1.5 rounded-full bg-[var(--vh-muted)]" style={{ animationDelay: `${dot * 0.18}s` }} />
                  ))}
                </motion.span>
              ) : (
                <motion.p
                  key="message"
                  className="text-[13px] leading-6 text-[var(--vh-soft)]"
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.5, ease: curve.out }}
                >
                  {copy.ask}
                </motion.p>
              )}
            </AnimatePresence>
          </div>
          <div className="mt-3 grid gap-2 border-l-2 border-[rgba(216,182,222,0.35)] pl-3">
            {copy.checks.map(([label, value], index) => {
              const shown = stage >= index + 2;
              const ok = index === copy.checks.length - 1;
              return (
                <motion.div
                  key={label}
                  className="grid grid-cols-[minmax(0,8.5rem)_1fr] items-center gap-3 text-[12px]"
                  initial={false}
                  animate={{ opacity: shown ? 1 : 0, x: shown ? 0 : -8 }}
                  transition={{ duration: 0.45, ease: curve.out }}
                >
                  <span className="vh-mono truncate text-[11px] text-[var(--vh-faint)]">{label}</span>
                  <span className={`flex items-center gap-1.5 ${ok ? "text-[var(--vh-sage)]" : "text-[var(--vh-amber)]"}`}>
                    {ok ? <Check size={12} weight="bold" /> : <WarningCircle size={13} weight="bold" />}
                    <span className="truncate text-[var(--vh-text)]">{value}</span>
                  </span>
                </motion.div>
              );
            })}
          </div>
          <motion.div
            className="mt-5 flex flex-wrap items-center gap-2"
            initial={false}
            animate={{ opacity: stage >= 5 ? 1 : 0, y: stage >= 5 ? 0 : 6 }}
            transition={{ duration: 0.5, ease: curve.out }}
          >
            <span className={`vh-btn-primary inline-flex h-8 items-center gap-1.5 rounded-[9px] px-3 text-[12px] font-semibold text-white ${stage >= 5 ? "vh-breathe" : ""}`}>
              <Check size={12} weight="bold" />
              {copy.review}
            </span>
            <span className="vh-btn-ghost inline-flex h-8 items-center gap-1.5 rounded-[9px] px-3 text-[12px] text-[var(--vh-soft)]">
              <Pause size={11} weight="fill" />
              {copy.hold}
            </span>
            <span className="vh-mono ml-auto text-[10px] text-[var(--vh-faint)]">
              {copy.waiting} · {waited} min
            </span>
          </motion.div>
        </div>
      </div>
    </div>
  );
}

/* ---- 03 · Isometric week ------------------------------------------------- */

const WEEK = [42, 48, 51, 57, 74, 88, 61];

function WeekBars({ copy }: { copy: HomeCopy["flow"]["week"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  const t = useTween(seen, 1.8, 0.15);
  const hot = WEEK.indexOf(Math.max(...WEEK));
  const width = 520;
  const height = 250;
  const slot = width / WEEK.length;
  const face = slot * 0.46;
  const depth = face * 0.42;
  const floor = height - 26;
  const max = 92;

  return (
    <div ref={ref} className="vh-glass rounded-[18px] p-5 sm:p-6">
      <div className="flex items-center justify-between gap-3">
        <span className="vh-mono text-[11px] text-[var(--vh-soft)]">{copy.head}</span>
        <span className="vh-mono text-[11px] text-[var(--vh-faint)]">{copy.average}</span>
      </div>
      <svg className="mt-4 w-full" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={copy.head}>
        <defs>
          <linearGradient id="vh-iso-front" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="#4a4643" />
            <stop offset="1" stopColor="#1f1d1b" />
          </linearGradient>
          <linearGradient id="vh-iso-side" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="#33302d" />
            <stop offset="1" stopColor="#161514" />
          </linearGradient>
          <linearGradient id="vh-iso-hot" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="#b583bc" />
            <stop offset="1" stopColor="#3d2640" />
          </linearGradient>
          <linearGradient id="vh-iso-hot-side" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="#7a4f80" />
            <stop offset="1" stopColor="#24172a" />
          </linearGradient>
          <filter id="vh-iso-glow" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="6" />
          </filter>
        </defs>
        <line x1="0" x2={width} y1={floor + 1} y2={floor + 1} stroke="rgba(247,246,244,0.08)" />
        {WEEK.map((value, index) => {
          const local = Math.min(1, Math.max(0, t * 1.6 - index * 0.09));
          const h = Math.max(4, (value / max) * (floor - 40) * local);
          const x = index * slot + (slot - face - depth) / 2;
          const top = floor - h;
          const isHot = index === hot;
          const front = isHot ? "url(#vh-iso-hot)" : "url(#vh-iso-front)";
          const side = isHot ? "url(#vh-iso-hot-side)" : "url(#vh-iso-side)";
          const lid = isHot ? "#efdff2" : "#b8b1aa";
          return (
            <g key={index}>
              {isHot ? (
                <polygon
                  points={`${x},${top} ${x + face},${top} ${x + face + depth},${top - depth * 0.6} ${x + depth},${top - depth * 0.6}`}
                  fill="#d8b6de"
                  filter="url(#vh-iso-glow)"
                  opacity={0.9 * local}
                />
              ) : null}
              <rect x={x} y={top} width={face} height={h} fill={front} />
              <polygon points={`${x + face},${top} ${x + face + depth},${top - depth * 0.6} ${x + face + depth},${floor - depth * 0.6} ${x + face},${floor}`} fill={side} />
              <polygon points={`${x},${top} ${x + face},${top} ${x + face + depth},${top - depth * 0.6} ${x + depth},${top - depth * 0.6}`} fill={lid} opacity={isHot ? 1 : 0.85} />
              <text x={x + face / 2 + depth / 2} y={height - 6} textAnchor="middle" className="vh-mono" fontSize="11" fill={isHot ? "#f7f6f4" : "#6f6a64"}>
                {copy.days[index]}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
