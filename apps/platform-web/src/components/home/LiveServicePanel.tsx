import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useEffect, useMemo, useState } from "react";
import { curve } from "../../lib/motion";
import type { HomeCopy } from "./homeCopy";
import { useOnScreen } from "./primitives";

type TableState = "free" | "occupied" | "reserved" | "paying";

// The hall from the real POS floor: bar on top, nine tables below.
const TABLES: Array<{ id: number; x: number; y: number; w?: number }> = [
  { id: 2, x: 14, y: 28 },
  { id: 3, x: 40, y: 28 },
  { id: 4, x: 66, y: 28 },
  { id: 1, x: 14, y: 50 },
  { id: 5, x: 14, y: 72 },
  { id: 6, x: 14, y: 90 },
  { id: 7, x: 36, y: 90 },
  { id: 8, x: 58, y: 90 },
  { id: 9, x: 80, y: 90 },
];

// A short scripted service: each step is the floor after one event.
const SCRIPT: Array<Record<number, TableState>> = [
  { 1: "occupied", 2: "occupied", 4: "free", 8: "reserved", 3: "free", 6: "free", 7: "free", 9: "free", 5: "free" },
  { 1: "occupied", 2: "occupied", 4: "occupied", 8: "reserved", 3: "free", 6: "free", 7: "free", 9: "free", 5: "free" },
  { 1: "occupied", 2: "paying", 4: "occupied", 8: "reserved", 3: "free", 6: "free", 7: "free", 9: "free", 5: "free" },
  { 1: "occupied", 2: "free", 4: "occupied", 8: "reserved", 3: "occupied", 6: "free", 7: "free", 9: "free", 5: "free" },
  { 1: "occupied", 2: "free", 4: "occupied", 8: "occupied", 3: "occupied", 6: "free", 7: "free", 9: "reserved", 5: "free" },
  { 1: "paying", 2: "free", 4: "occupied", 8: "occupied", 3: "occupied", 6: "occupied", 7: "occupied", 9: "reserved", 5: "free" },
];

// Adds up to the real demo check: 368.00 + 10% service = 404.80 ₾.
const CHECK_LINES: Array<[string, string]> = [
  ["Khachapuri ×4", "100.00"],
  ["Mtsvadi ×5", "160.00"],
  ["Pkhali ×6", "78.00"],
  ["Lemonade ×4", "30.00"],
];
const CHECK_LINES_KA: Array<[string, string]> = [
  ["ხაჭაპური ×4", "100.00"],
  ["მწვადი ×5", "160.00"],
  ["ფხალი ×6", "78.00"],
  ["ლიმონათი ×4", "30.00"],
];

const TICK_MS = 2400;

function clock(minutes: number) {
  const total = 23 * 60 + 30 + minutes;
  const h = Math.floor(total / 60) % 24;
  const m = total % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/**
 * The hero's working POS: tables change state, the service counts follow,
 * and a short event log ticks in. Every few events the connection drops and
 * service carries on — the offline-first promise, shown rather than told.
 * Pauses off-screen; reduced motion shows one settled moment.
 */
export function LiveServicePanel({ copy, ka }: { copy: HomeCopy["panel"]; ka: boolean }) {
  const reduce = useReducedMotion();
  const [ref, visible] = useOnScreen<HTMLDivElement>();
  const [tick, setTick] = useState(reduce ? 4 : 0);

  useEffect(() => {
    if (reduce || !visible) return;
    const timer = window.setInterval(() => setTick((value) => value + 1), TICK_MS);
    return () => window.clearInterval(timer);
  }, [reduce, visible]);

  const floor = SCRIPT[tick % SCRIPT.length];
  const counts = useMemo(() => {
    const values = Object.values(floor);
    return {
      seated: values.filter((state) => state === "occupied").length,
      reserved: values.filter((state) => state === "reserved").length,
      paying: values.filter((state) => state === "paying").length,
      free: values.filter((state) => state === "free").length,
    };
  }, [floor]);

  // Connection: online, then 3 ticks offline, then a "synced" beat.
  const phase = tick % 9;
  const offline = phase >= 5 && phase <= 7;
  const justSynced = phase === 8;

  const events = Array.from({ length: 4 }, (_, index) => {
    const n = tick - index;
    return { key: n, time: clock(Math.max(0, n) * 3 + 11), text: copy.feed[((n % copy.feed.length) + copy.feed.length) % copy.feed.length], queued: offline && index < phase - 4 };
  });
  const lines = ka ? CHECK_LINES_KA : CHECK_LINES;

  return (
    <div ref={ref} className="relative">
      <div className="vh-glass overflow-hidden rounded-[18px]">
        {/* Title bar */}
        <div className="flex items-center justify-between gap-3 border-b border-[var(--vh-line)] px-4 py-3">
          <div className="flex items-center gap-3">
            <span className="text-[13px] font-medium text-[var(--vh-text)]">{copy.title}</span>
            <span className="vh-mono text-[10px] text-[var(--vh-faint)]">{copy.meta}</span>
          </div>
          <motion.span
            layout
            className={`vh-mono inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[10px] transition-colors duration-500 ${
              offline
                ? "border-[rgba(215,180,138,0.4)] bg-[rgba(215,180,138,0.1)] text-[var(--vh-amber)]"
                : "border-[rgba(169,194,166,0.3)] bg-[rgba(169,194,166,0.08)] text-[var(--vh-sage)]"
            }`}
          >
            <span className={`h-1.5 w-1.5 rounded-full ${offline ? "vh-blink bg-[var(--vh-amber)]" : "bg-[var(--vh-sage)]"}`} />
            {offline ? `${copy.offline} · ${copy.queued}` : justSynced ? `${copy.synced} · 3` : copy.online}
          </motion.span>
        </div>

        <div className="grid grid-cols-[minmax(0,1fr)] sm:grid-cols-[minmax(0,1.35fr)_minmax(0,0.65fr)]">
          {/* Floor */}
          <div className="relative aspect-[1.25] border-b border-[var(--vh-line)] sm:border-b-0 sm:border-r">
            <div className="absolute inset-0 opacity-60 [background-image:radial-gradient(rgba(247,246,244,0.08)_1px,transparent_1px)] [background-size:16px_16px]" />
            <div className="vh-mono absolute left-[14%] right-[30%] top-[7%] flex h-[11%] items-center justify-center rounded-[8px] border border-[rgba(185,168,196,0.35)] bg-[rgba(185,168,196,0.08)] text-[10px] tracking-[0.14em] text-[var(--vh-lilac)]">
              BAR
            </div>
            <div className="absolute right-[6%] top-[42%] h-[30%] w-[10%] rounded-[8px] border border-[rgba(216,182,222,0.28)] bg-[rgba(216,182,222,0.06)]" />
            {TABLES.map((table) => {
              const state = floor[table.id] ?? "free";
              return (
                <div
                  key={table.id}
                  data-state={state}
                  className="vh-table absolute flex h-[13%] w-[17%] -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-[8px] border border-[var(--vh-line-strong)] bg-white/[0.03] text-[var(--vh-soft)]"
                  style={{ left: `${table.x + 8}%`, top: `${table.y}%` }}
                >
                  <span className="text-[10px] font-medium leading-none">T{table.id}</span>
                  {table.id === 1 ? <span className="vh-mono mt-1 text-[8px] leading-none text-[var(--vh-orchid)]">404.80 ₾</span> : null}
                </div>
              );
            })}
          </div>

          {/* Service right now */}
          <div className="grid content-start gap-3 p-4">
            <p className="vh-mono text-[10px] uppercase tracking-[0.14em] text-[var(--vh-faint)]">{copy.floor}</p>
            <div className="grid grid-cols-2 gap-2">
              {(
                [
                  [copy.seated, counts.seated, "text-[var(--vh-orchid)]"],
                  [copy.reserved, counts.reserved, "text-[var(--vh-amber)]"],
                  [copy.paying, counts.paying, "text-[var(--vh-sage)]"],
                  [copy.free, counts.free, "text-[var(--vh-soft)]"],
                ] as const
              ).map(([label, value, tone]) => (
                <div key={label} className="rounded-[10px] border border-[var(--vh-line)] bg-black/20 px-2.5 py-2">
                  <p className="text-[10px] text-[var(--vh-faint)]">{label}</p>
                  <div className="relative h-6 overflow-hidden">
                    <AnimatePresence initial={false} mode="popLayout">
                      <motion.p
                        key={value}
                        className={`text-lg font-semibold leading-6 ${tone}`}
                        initial={{ y: 18, opacity: 0 }}
                        animate={{ y: 0, opacity: 1 }}
                        exit={{ y: -18, opacity: 0 }}
                        transition={{ duration: 0.5, ease: curve.out }}
                      >
                        {value}
                      </motion.p>
                    </AnimatePresence>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Event log */}
        <div className="border-t border-[var(--vh-line)] px-4 py-3">
          <p className="vh-mono mb-2 text-[10px] text-[var(--vh-faint)]">{copy.events}</p>
          <ul className="relative grid h-[92px] grid-cols-[minmax(0,1fr)] content-start gap-1.5 overflow-hidden">
            <AnimatePresence initial={false}>
              {events.map((event, index) => (
                <motion.li
                  key={event.key}
                  layout
                  className="vh-mono flex items-center gap-2.5 text-[11px]"
                  initial={{ opacity: 0, y: -14, filter: "blur(4px)" }}
                  animate={{ opacity: 1 - index * 0.24, y: 0, filter: "blur(0px)" }}
                  exit={{ opacity: 0, transition: { duration: 0.2 } }}
                  transition={{ duration: 0.6, ease: curve.out }}
                >
                  <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${event.queued ? "bg-[var(--vh-amber)]" : "bg-[var(--vh-orchid)]"}`} />
                  <span className="shrink-0 text-[var(--vh-faint)]">{event.time}</span>
                  <span className="truncate text-[var(--vh-soft)]">{event.text}</span>
                </motion.li>
              ))}
            </AnimatePresence>
          </ul>
        </div>
      </div>

      {/* Floating check, a layer in front of the panel */}
      <div data-depth="front" className="vh-glass absolute -bottom-8 -left-4 hidden w-[230px] rounded-[14px] p-3.5 sm:block lg:-left-14">
        <div className="flex items-center justify-between">
          <p className="text-[12px] font-medium text-[var(--vh-text)]">{copy.check}</p>
          <span className="vh-mono rounded-full bg-[rgba(118,75,124,0.35)] px-2 py-0.5 text-[9px] text-[var(--vh-orchid)]">#1756</span>
        </div>
        <div className="mt-2.5 grid gap-1">
          {lines.map(([name, price]) => (
            <div key={name} className="vh-mono flex justify-between text-[10px] text-[var(--vh-muted)]">
              <span>{name}</span>
              <span>{price}</span>
            </div>
          ))}
          <div className="vh-mono flex justify-between text-[10px] text-[var(--vh-muted)]">
            <span>{ka ? "მომსახურება 10%" : "Service 10%"}</span>
            <span>36.80</span>
          </div>
        </div>
        <div className="mt-2.5 flex items-end justify-between border-t border-[var(--vh-line)] pt-2">
          <span className="text-[10px] text-[var(--vh-faint)]">{copy.total}</span>
          <span className="text-[17px] font-semibold text-[var(--vh-text)]">404.80 ₾</span>
        </div>
      </div>
    </div>
  );
}
