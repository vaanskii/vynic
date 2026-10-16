import { Clock } from "@phosphor-icons/react";
import { motion, useReducedMotion } from "motion/react";
import { useEffect, useState, type ReactNode } from "react";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy, type HomeCopy } from "./homeCopy";
import { CountUp, Drift, Rise, SectionOpen, useOnScreen, useSeen } from "./primitives";

export function DailyView() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).daily;
  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        <SectionOpen
          kicker={copy.kicker}
          title={copy.title}
          body={copy.body}
          aside={<p className="vh-mono mt-3 text-[10px] text-[var(--vh-faint)]">* {copy.sample}</p>}
        />
        <div className="mt-14 grid grid-cols-[minmax(0,1fr)] gap-4 lg:grid-cols-3">
          <Drift amount={18} className="lg:col-span-2">
            <Rise y={36}>
            <HeatCard copy={copy.heat} />
            </Rise>
          </Drift>
          <Drift amount={42}>
            <Rise y={36} delay={0.08}>
            <RingCard copy={copy.ring} />
            </Rise>
          </Drift>
          <Drift amount={30}>
            <Rise y={36} delay={0.04}>
            <GuestsCard copy={copy.guests} />
            </Rise>
          </Drift>
          <Drift amount={54}>
            <Rise y={36} delay={0.1}>
            <PaymentsWave copy={copy.pay} />
            </Rise>
          </Drift>
          <Drift amount={24}>
            <Rise y={36} delay={0.16}>
            <RoomCard copy={copy.room} />
            </Rise>
          </Drift>
        </div>
      </div>
    </section>
  );
}

function Tile({ head, children, aside, className = "" }: { head: string; children: ReactNode; aside?: ReactNode; className?: string }) {
  return (
    <div className={`vh-glass flex h-full flex-col rounded-[18px] p-5 ${className}`}>
      <div className="flex items-center justify-between gap-3">
        <span className="vh-mono text-[10px] text-[var(--vh-faint)]">{head}</span>
        {aside}
      </div>
      <div className="mt-4 flex-1">{children}</div>
    </div>
  );
}

/* Covers by hour: seven days, six evening hours. Friday is today. */
const HOURS = ["18", "19", "20", "21", "22", "23"];
const HEAT = [
  [1, 2, 3, 3, 2, 1],
  [1, 2, 3, 4, 2, 1],
  [2, 2, 3, 4, 3, 1],
  [2, 3, 4, 4, 3, 2],
  [3, 4, 5, 5, 4, 3],
  [3, 4, 5, 5, 5, 3],
  [2, 3, 3, 3, 2, 1],
];
const TODAY = 4;

function HeatCard({ copy }: { copy: HomeCopy["daily"]["heat"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.4);
  const reduce = useReducedMotion();
  return (
    <Tile
      head={copy.head}
      aside={
        <span className="vh-mono inline-flex items-center gap-1.5 rounded-full border border-[rgba(216,182,222,0.3)] bg-[rgba(118,75,124,0.18)] px-2.5 py-1 text-[10px] text-[var(--vh-orchid)]">
          <Clock size={11} />
          {copy.next}
        </span>
      }
    >
      <div ref={ref} className="grid grid-cols-[22px_1fr] gap-3">
        <div className="vh-mono grid grid-rows-6 gap-1.5 text-[9px] text-[var(--vh-faint)]">
          {HOURS.map((hour) => (
            <span key={hour} className="flex items-center">{hour}</span>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1.5">
          {HEAT.map((column, day) => (
            <div key={day} className="grid grid-rows-6 gap-1.5">
              {column.map((level, hour) => {
                const today = day === TODAY;
                const now = today && hour === 3;
                return (
                  <motion.span
                    key={hour}
                    className={`h-5 rounded-[5px] ${now ? "vh-breathe" : ""}`}
                    style={{
                      background: today
                        ? `rgba(216,182,222,${0.14 + level * 0.15})`
                        : `rgba(247,246,244,${0.03 + level * 0.035})`,
                    }}
                    initial={reduce ? false : { opacity: 0, scaleX: 0.3 }}
                    animate={seen || reduce ? { opacity: 1, scaleX: 1 } : {}}
                    transition={{ duration: 0.6, ease: curve.out, delay: day * 0.05 + hour * 0.03 }}
                  />
                );
              })}
            </div>
          ))}
          {copy.days.map((day, index) => (
            <span key={day} className={`vh-mono pt-1 text-center text-[9px] ${index === TODAY ? "text-[var(--vh-text)]" : "text-[var(--vh-faint)]"}`}>
              {day}
              {index === TODAY ? <span className="mx-auto mt-1 block h-px w-4 bg-[var(--vh-orchid)]" /> : null}
            </span>
          ))}
        </div>
      </div>
    </Tile>
  );
}

function RingCard({ copy }: { copy: HomeCopy["daily"]["ring"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  const reduce = useReducedMotion();
  const value = 82;
  const radius = 44;
  const length = 2 * Math.PI * radius;
  return (
    <Tile head={copy.head}>
      <div ref={ref} className="flex h-full flex-col items-center justify-center gap-4 py-2">
        <div className="relative h-36 w-36">
          <svg viewBox="0 0 100 100" className="h-full w-full -rotate-90" aria-hidden="true">
            <circle cx="50" cy="50" r={radius} fill="none" stroke="rgba(247,246,244,0.07)" strokeWidth="6" />
            <motion.circle
              cx="50"
              cy="50"
              r={radius}
              fill="none"
              stroke="url(#vh-ring)"
              strokeWidth="6"
              strokeLinecap="round"
              strokeDasharray={length}
              initial={reduce ? false : { strokeDashoffset: length }}
              animate={{ strokeDashoffset: seen || reduce ? length * (1 - value / 100) : length }}
              transition={{ duration: 1.6, ease: curve.out }}
              style={{ filter: "drop-shadow(0 0 6px rgba(216,182,222,0.55))" }}
            />
            <defs>
              <linearGradient id="vh-ring" x1="0" x2="1" y1="0" y2="1">
                <stop offset="0" stopColor="#d8b6de" />
                <stop offset="1" stopColor="#764b7c" />
              </linearGradient>
            </defs>
          </svg>
          <span className="absolute inset-0 flex items-center justify-center text-3xl font-semibold text-[var(--vh-text)]">
            <CountUp value={value} run={seen} />%
          </span>
        </div>
        <p className="text-center text-[12px] text-[var(--vh-muted)]">{copy.caption}</p>
      </div>
    </Tile>
  );
}

const GUESTS = ["NB", "GK", "LM", "DT", "MA"];

function GuestsCard({ copy }: { copy: HomeCopy["daily"]["guests"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  const reduce = useReducedMotion();
  return (
    <Tile head={copy.head}>
      <div ref={ref}>
        <div className="flex -space-x-2">
          {GUESTS.map((initials, index) => (
            <motion.span
              key={initials}
              className="vh-mono flex h-9 w-9 items-center justify-center rounded-full border-2 border-[var(--vh-panel)] text-[10px] text-white"
              style={{ background: ["#764b7c", "#5f3a65", "#8f5f96", "#4a3f52", "#6b4470"][index] }}
              initial={reduce ? false : { opacity: 0, x: -10, scale: 0.8 }}
              animate={seen || reduce ? { opacity: 1, x: 0, scale: 1 } : {}}
              transition={{ duration: 0.5, ease: curve.out, delay: index * 0.08 }}
            >
              {initials}
            </motion.span>
          ))}
        </div>
        <p className="mt-5 flex items-baseline gap-2">
          <span className="text-3xl font-semibold text-[var(--vh-text)]">
            <CountUp value={5} run={seen} />
          </span>
          <span className="text-[13px] text-[var(--vh-muted)]">{copy.count}</span>
        </p>
        <p className="mt-2 text-[12px] text-[var(--vh-faint)]">{copy.caption}</p>
      </div>
    </Tile>
  );
}

function PaymentsWave({ copy }: { copy: HomeCopy["daily"]["pay"] }) {
  const [ref, seen] = useSeen<HTMLDivElement>(0.5);
  const reduce = useReducedMotion();
  const cash = "M 0 40 C 20 10, 40 10, 60 30 S 100 55, 120 30 S 160 5, 200 25";
  const card = "M 0 20 C 20 50, 40 50, 60 30 S 100 5, 120 30 S 160 55, 200 35";
  const draw = (delay: number) =>
    reduce ? {} : { initial: { pathLength: 0 }, animate: { pathLength: seen ? 1 : 0 }, transition: { duration: 1.8, ease: curve.inOut, delay } };
  return (
    <Tile head={copy.head}>
      <div ref={ref}>
        <svg viewBox="0 0 200 60" className="h-24 w-full overflow-visible" aria-hidden="true">
          <motion.path d={card} fill="none" stroke="#9a928a" strokeWidth="1.4" strokeLinecap="round" {...draw(0.2)} />
          <motion.path d={cash} fill="none" stroke="#d8b6de" strokeWidth="1.6" strokeLinecap="round" style={{ filter: "drop-shadow(0 0 4px rgba(216,182,222,0.7))" }} {...draw(0)} />
          {[60, 120].map((x) => (
            <motion.circle key={x} cx={x} cy={30} r="3" fill="#1c1a18" stroke="#d8b6de" strokeWidth="1.2" initial={reduce ? false : { opacity: 0 }} animate={{ opacity: seen || reduce ? 1 : 0 }} transition={{ delay: 1.2 }} />
          ))}
        </svg>
        <div className="vh-mono mt-3 flex gap-4 text-[10px] text-[var(--vh-faint)]">
          <span className="flex items-center gap-1.5">
            <span className="h-1.5 w-1.5 rounded-full bg-[var(--vh-orchid)]" />
            {copy.cash}
          </span>
          <span className="flex items-center gap-1.5">
            <span className="h-1.5 w-1.5 rounded-full bg-[var(--vh-muted)]" />
            {copy.card}
          </span>
        </div>
      </div>
    </Tile>
  );
}

// 4 × 8 dot floor; occupied tables glow, one changes each beat.
const ROOM_BASE = [1, 0, 1, 1, 0, 2, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 0, 2, 1, 1, 0, 0, 1, 1, 0, 1, 0];

function RoomCard({ copy }: { copy: HomeCopy["daily"]["room"] }) {
  const reduce = useReducedMotion();
  const [ref, visible] = useOnScreen<HTMLDivElement>();
  const [beat, setBeat] = useState(0);
  useEffect(() => {
    if (reduce || !visible) return;
    const timer = window.setInterval(() => setBeat((value) => value + 1), 1500);
    return () => window.clearInterval(timer);
  }, [reduce, visible]);
  const flip = (beat * 7) % ROOM_BASE.length;
  return (
    <Tile head={copy.head}>
      <div ref={ref}>
        <div className="grid grid-cols-8 gap-2">
          {ROOM_BASE.map((base, index) => {
            const state = index === flip ? (base === 1 ? 0 : 1) : base;
            return (
              <span
                key={index}
                className="aspect-square rounded-[4px] transition-[background-color,box-shadow] duration-700"
                style={{
                  background: state === 1 ? "rgba(154,106,161,0.75)" : state === 2 ? "rgba(215,180,138,0.55)" : "rgba(247,246,244,0.06)",
                  boxShadow: state === 1 ? "0 0 10px rgba(216,182,222,0.45)" : "none",
                }}
              />
            );
          })}
        </div>
        <p className="mt-4 text-[12px] text-[var(--vh-faint)]">{copy.caption}</p>
      </div>
    </Tile>
  );
}
